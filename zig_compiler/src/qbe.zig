//! QBE Backend Integration — In-process IL → Assembly compilation
//!
//! This module provides Zig bindings to the embedded QBE C backend.
//! Instead of shelling out to an external `qbe` binary, we call QBE's
//! optimization and emission pipeline directly via the C bridge.
//!
//! The C bridge (qbe/qbe_bridge.c) defines the global state that QBE's
//! internal modules expect and exposes a simple compile function.
//!
//! Usage:
//!   const qbe = @import("qbe.zig");
//!
//!   // Compile QBE IL text to an assembly file
//!   try qbe.compileIL(il_text, "/tmp/output.s", null);
//!
//!   // Or with explicit target
//!   try qbe.compileIL(il_text, "/tmp/output.s", "arm64_apple");
//!
//! Thread safety: NOT thread-safe. QBE uses extensive mutable global state.

const std = @import("std");

// ── C bridge extern declarations ───────────────────────────────────────

const c = struct {
    // Return codes from qbe_bridge.h
    const QBE_OK: c_int = 0;
    const QBE_ERR_OUTPUT: c_int = -1;
    const QBE_ERR_INPUT: c_int = -2;
    const QBE_ERR_TARGET: c_int = -3;
    const QBE_ERR_PARSE: c_int = -4;

    extern fn qbe_compile_il(
        il_text: [*]const u8,
        il_len: usize,
        asm_path: [*:0]const u8,
        target_name: ?[*:0]const u8,
    ) c_int;

    extern fn qbe_compile_il_to_file(
        il_text: [*]const u8,
        il_len: usize,
        output_file: *anyopaque,
        target_name: ?[*:0]const u8,
    ) c_int;

    extern fn qbe_default_target() [*:0]const u8;
    extern fn qbe_available_targets() [*]const ?[*:0]const u8;
    extern fn qbe_version() [*:0]const u8;
};

// ── Error type ─────────────────────────────────────────────────────────

pub const QBEError = error{
    /// Cannot open or write the output assembly file.
    OutputError,
    /// Cannot create input stream from IL text (empty input?).
    InputError,
    /// Unknown target name.
    UnknownTarget,
    /// QBE IL parse error — the IL text was malformed.
    ParseError,
    /// Unexpected error code from the C bridge.
    UnexpectedError,
};

// ── Public API ─────────────────────────────────────────────────────────

/// Compile QBE IL text to an assembly file.
///
/// Parameters:
///   - `il_text`:     The QBE IL source text (e.g., from CodeGenerator.generate()).
///   - `asm_path`:    Output path for the generated assembly file.
///   - `target_name`: Target architecture name, or null for host default.
///                     Valid names: "amd64_sysv", "amd64_apple", "arm64",
///                     "arm64_apple", "rv64".
///
/// Returns QBEError on failure.
pub fn compileIL(il_text: []const u8, asm_path: []const u8, target_name: ?[]const u8) QBEError!void {
    if (il_text.len == 0) return QBEError.InputError;

    // We need a NUL-terminated asm_path for the C API.
    // Stack-allocate a buffer for typical paths; this avoids heap allocation.
    var path_buf: [4096]u8 = undefined;
    if (asm_path.len >= path_buf.len) return QBEError.OutputError;
    @memcpy(path_buf[0..asm_path.len], asm_path);
    path_buf[asm_path.len] = 0;
    const asm_path_z: [*:0]const u8 = path_buf[0..asm_path.len :0];

    // NUL-terminate the target name if provided.
    var target_buf: [64]u8 = undefined;
    var target_z: ?[*:0]const u8 = null;
    if (target_name) |tn| {
        if (tn.len >= target_buf.len) return QBEError.UnknownTarget;
        @memcpy(target_buf[0..tn.len], tn);
        target_buf[tn.len] = 0;
        target_z = target_buf[0..tn.len :0];
    }

    const rc = c.qbe_compile_il(il_text.ptr, il_text.len, asm_path_z, target_z);
    try checkResult(rc);
}

/// Compile QBE IL text to an assembly file, allocating paths with the given allocator.
///
/// This variant handles paths of any length by heap-allocating the
/// NUL-terminated copy. Prefer `compileIL()` for typical use.
pub fn compileILAlloc(
    allocator: std.mem.Allocator,
    il_text: []const u8,
    asm_path: []const u8,
    target_name: ?[]const u8,
) (std.mem.Allocator.Error || QBEError)!void {
    if (il_text.len == 0) return QBEError.InputError;

    const asm_path_z = try allocator.dupeZ(u8, asm_path);
    defer allocator.free(asm_path_z);

    var target_z: ?[*:0]const u8 = null;
    var target_alloc: ?[:0]const u8 = null;
    defer if (target_alloc) |ta| allocator.free(ta);

    if (target_name) |tn| {
        const tz = try allocator.dupeZ(u8, tn);
        target_alloc = tz;
        target_z = tz.ptr;
    }

    const rc = c.qbe_compile_il(il_text.ptr, il_text.len, asm_path_z.ptr, target_z);
    try checkResult(rc);
}

/// Returns the default target name for the current platform.
/// E.g., "arm64_apple" on Apple Silicon macOS.
pub fn defaultTarget() []const u8 {
    const ptr = c.qbe_default_target();
    return std.mem.span(ptr);
}

/// Returns a list of all available QBE target names.
pub fn availableTargets() []const []const u8 {
    // We build a static slice from the C null-terminated array.
    // This is safe because the C side returns static data.
    const raw = c.qbe_available_targets();

    var count: usize = 0;
    while (raw[count] != null) : (count += 1) {}

    // Use a static buffer to hold the slices (max 8 targets).
    const S = struct {
        var buf: [8][]const u8 = undefined;
        var init: bool = false;
        var len: usize = 0;
    };

    if (!S.init) {
        var i: usize = 0;
        while (i < count and i < 8) : (i += 1) {
            S.buf[i] = std.mem.span(raw[i].?);
        }
        S.len = i;
        S.init = true;
    }

    return S.buf[0..S.len];
}

/// Returns the QBE version string (e.g., "qbe+fasterbasic-zig").
pub fn version() []const u8 {
    return std.mem.span(c.qbe_version());
}

// ── Internal ───────────────────────────────────────────────────────────

fn checkResult(rc: c_int) QBEError!void {
    if (rc == c.QBE_OK) return;
    return switch (rc) {
        c.QBE_ERR_OUTPUT => QBEError.OutputError,
        c.QBE_ERR_INPUT => QBEError.InputError,
        c.QBE_ERR_TARGET => QBEError.UnknownTarget,
        c.QBE_ERR_PARSE => QBEError.ParseError,
        else => QBEError.UnexpectedError,
    };
}

// ── Tests ──────────────────────────────────────────────────────────────

test "qbe version is non-empty" {
    const v = version();
    try std.testing.expect(v.len > 0);
    // Should contain our identifier
    try std.testing.expect(std.mem.indexOf(u8, v, "fasterbasic") != null);
}

test "qbe default target is non-empty" {
    const t = defaultTarget();
    try std.testing.expect(t.len > 0);
}

test "qbe available targets includes default" {
    const targets = availableTargets();
    try std.testing.expect(targets.len > 0);

    const def = defaultTarget();
    var found = false;
    for (targets) |t| {
        if (std.mem.eql(u8, t, def)) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "qbe compile trivial IL to assembly" {
    // Minimal QBE IL: a function that returns 0
    const il =
        \\export function w $main() {
        \\@start
        \\  ret 0
        \\}
        \\
    ;

    const tmp_path = "/tmp/fbc_qbe_test.s";

    try compileIL(il, tmp_path, null);

    // Verify the output file was created and contains assembly
    const file = try std.fs.cwd().openFile(tmp_path, .{});
    defer file.close();
    const stat = try file.stat();
    try std.testing.expect(stat.size > 0);

    // Read and verify it looks like assembly
    var buf: [4096]u8 = undefined;
    const n = try file.readAll(&buf);
    const asm_text = buf[0..n];
    // Should contain the function name somewhere
    try std.testing.expect(std.mem.indexOf(u8, asm_text, "main") != null);

    // Clean up
    std.fs.cwd().deleteFile(tmp_path) catch {};
}

test "qbe compile IL with print call" {
    // QBE IL that calls an external function (like our runtime would)
    const il =
        \\data $hello_str = { b "Hello, World!\n", b 0 }
        \\
        \\export function w $main() {
        \\@start
        \\  %s =l loadl $hello_str
        \\  call $puts(l %s)
        \\  ret 0
        \\}
        \\
    ;

    const tmp_path = "/tmp/fbc_qbe_test2.s";

    try compileIL(il, tmp_path, null);

    const file = try std.fs.cwd().openFile(tmp_path, .{});
    defer file.close();
    const stat = try file.stat();
    try std.testing.expect(stat.size > 0);

    // Clean up
    std.fs.cwd().deleteFile(tmp_path) catch {};
}

test "qbe rejects empty IL" {
    const result = compileIL("", "/tmp/fbc_qbe_empty.s", null);
    try std.testing.expectError(QBEError.InputError, result);
}

test "qbe rejects unknown target" {
    const il =
        \\export function w $main() {
        \\@start
        \\  ret 0
        \\}
        \\
    ;
    const result = compileIL(il, "/tmp/fbc_qbe_badtarget.s", "z80_cpm");
    try std.testing.expectError(QBEError.UnknownTarget, result);
}
