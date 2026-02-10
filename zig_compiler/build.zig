const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── QBE C source files ─────────────────────────────────────────────
    //
    // These are compiled by Zig's built-in C compiler and linked directly
    // into the fbc executable.  We compile everything except main.c
    // (replaced by qbe_bridge.c) and the tools/ / minic/ directories.

    const qbe_core_sources = &[_][]const u8{
        "parse.c",
        "ssa.c",
        "cfg.c",
        "emit.c",
        "abi.c",
        "alias.c",
        "copy.c",
        "fold.c",
        "gcm.c",
        "gvn.c",
        "ifopt.c",
        "live.c",
        "load.c",
        "mem.c",
        "rega.c",
        "simpl.c",
        "spill.c",
        "util.c",
        // Our bridge replaces main.c
        "qbe_bridge.c",
    };

    const qbe_amd64_sources = &[_][]const u8{
        "amd64/emit.c",
        "amd64/isel.c",
        "amd64/sysv.c",
        "amd64/targ.c",
    };

    const qbe_arm64_sources = &[_][]const u8{
        "arm64/abi.c",
        "arm64/emit.c",
        "arm64/isel.c",
        "arm64/targ.c",
    };

    const qbe_rv64_sources = &[_][]const u8{
        "rv64/abi.c",
        "rv64/emit.c",
        "rv64/isel.c",
        "rv64/targ.c",
    };

    const qbe_c_flags = &[_][]const u8{
        "-std=c99",
        "-Wall",
        "-Wno-unused-parameter",
        "-Wno-sign-compare",
        "-Wno-missing-field-initializers",
        "-Wno-unused-function",
    };

    // ── Main compiler executable ───────────────────────────────────────

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Add QBE include path so qbe.zig's C imports and the C sources
    // can find all.h, config.h, ops.h, qbe_bridge.h
    exe_mod.addIncludePath(b.path("qbe"));

    // Compile all QBE C sources into the module
    exe_mod.addCSourceFiles(.{
        .root = b.path("qbe"),
        .files = qbe_core_sources,
        .flags = qbe_c_flags,
    });
    exe_mod.addCSourceFiles(.{
        .root = b.path("qbe"),
        .files = qbe_amd64_sources,
        .flags = qbe_c_flags,
    });
    exe_mod.addCSourceFiles(.{
        .root = b.path("qbe"),
        .files = qbe_arm64_sources,
        .flags = qbe_c_flags,
    });
    exe_mod.addCSourceFiles(.{
        .root = b.path("qbe"),
        .files = qbe_rv64_sources,
        .flags = qbe_c_flags,
    });

    const exe = b.addExecutable(.{
        .name = "fbc",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    // ── Zig Runtime Libraries ─────────────────────────────────────────

    // Create zig-out/lib directory first
    const mkdir_cmd = b.addSystemCommand(&[_][]const u8{
        "mkdir",
        "-p",
        "zig-out/lib",
    });

    const zig_runtime_libs = [_][]const u8{
        "samm_pool",
        "samm_scope",
        "samm_core",
        "memory_mgmt",
        "class_runtime",
        "conversion_ops",
        "string_ops",
        "string_utf32",
        "list_ops",
        "string_pool",
        "array_descriptor_runtime",
        "math_ops",
        "basic_data",
        "fbc_bridge",
        "io_ops_format",
        "io_ops",
        "array_ops",
        "marshalling",
    };

    var zig_rt_steps: [zig_runtime_libs.len]std.Build.Step.Run = undefined;
    for (zig_runtime_libs, 0..) |lib_name, i| {
        const src_path = b.fmt("runtime/{s}.zig", .{lib_name});
        const out_path = b.fmt("zig-out/lib/lib{s}.a", .{lib_name});
        zig_rt_steps[i] = b.addSystemCommand(&[_][]const u8{
            "zig",
            "build-lib",
            src_path,
            "-lc",
            "-O",
            "ReleaseFast",
            b.fmt("-femit-bin={s}", .{out_path}),
        }).*;
        zig_rt_steps[i].step.dependOn(&mkdir_cmd.step);
    }

    for (&zig_rt_steps) |*step| {
        b.getInstallStep().dependOn(&step.step);
    }

    // ── Run step ───────────────────────────────────────────────────────

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the FasterBASIC compiler");
    run_step.dependOn(&run_cmd.step);

    // ── Unit tests ─────────────────────────────────────────────────────
    //
    // We build test binaries for each module.  Modules that import qbe.zig
    // (directly or transitively through main.zig) need the QBE C sources
    // linked in so the extern symbols resolve.

    const test_step = b.step("test", "Run unit tests");

    // Add SAMM pool unit tests
    const samm_pool_test_mod = b.createModule(.{
        .root_source_file = b.path("runtime/samm_pool.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const samm_pool_tests = b.addTest(.{
        .root_module = samm_pool_test_mod,
    });
    const run_samm_tests = b.addRunArtifact(samm_pool_tests);
    test_step.dependOn(&run_samm_tests.step);

    // Add SAMM scope unit tests
    const samm_scope_test_mod = b.createModule(.{
        .root_source_file = b.path("runtime/samm_scope.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const samm_scope_tests = b.addTest(.{
        .root_module = samm_scope_test_mod,
    });
    const run_samm_scope_tests = b.addRunArtifact(samm_scope_tests);
    test_step.dependOn(&run_samm_scope_tests.step);

    // Runtime modules with tests — these need test_stubs.c to satisfy
    // extern symbols from other runtime modules (the tests only exercise
    // internal helpers so the stubs are never actually called).
    const runtime_test_modules = [_][]const u8{
        "runtime/samm_core.zig",
        "runtime/memory_mgmt.zig",
        "runtime/string_ops.zig",
        "runtime/conversion_ops.zig",
        "runtime/class_runtime.zig",
        "runtime/math_ops.zig",
        "runtime/basic_data.zig",
        "runtime/io_ops_format.zig",
        "runtime/string_utf32.zig",
    };

    const stub_sources = [_][]const u8{"test_stubs.c"};

    for (runtime_test_modules) |rt_path| {
        const rt_mod = b.createModule(.{
            .root_source_file = b.path(rt_path),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        rt_mod.addCSourceFiles(.{
            .root = b.path("runtime"),
            .files = &stub_sources,
            .flags = &.{},
        });
        const rt_tests = b.addTest(.{
            .root_module = rt_mod,
        });
        const run_rt_tests = b.addRunArtifact(rt_tests);
        test_step.dependOn(&run_rt_tests.step);
    }

    // Helper: create a test module with QBE C sources linked in
    const TestModuleConfig = struct {
        root_source_file: std.Build.LazyPath,
        needs_qbe: bool,
    };

    const test_modules = [_]TestModuleConfig{
        .{ .root_source_file = b.path("src/main.zig"), .needs_qbe = true },
        .{ .root_source_file = b.path("src/lexer.zig"), .needs_qbe = false },
        .{ .root_source_file = b.path("src/parser.zig"), .needs_qbe = false },
        .{ .root_source_file = b.path("src/ast.zig"), .needs_qbe = false },
        .{ .root_source_file = b.path("src/semantic.zig"), .needs_qbe = false },
        .{ .root_source_file = b.path("src/codegen.zig"), .needs_qbe = false },
        .{ .root_source_file = b.path("src/cfg.zig"), .needs_qbe = false },
        .{ .root_source_file = b.path("src/qbe.zig"), .needs_qbe = true },
    };

    for (test_modules) |tm| {
        const mod = b.createModule(.{
            .root_source_file = tm.root_source_file,
            .target = target,
            .optimize = optimize,
            .link_libc = if (tm.needs_qbe) true else false,
        });

        if (tm.needs_qbe) {
            mod.addIncludePath(b.path("qbe"));
            mod.addCSourceFiles(.{
                .root = b.path("qbe"),
                .files = qbe_core_sources,
                .flags = qbe_c_flags,
            });
            mod.addCSourceFiles(.{
                .root = b.path("qbe"),
                .files = qbe_amd64_sources,
                .flags = qbe_c_flags,
            });
            mod.addCSourceFiles(.{
                .root = b.path("qbe"),
                .files = qbe_arm64_sources,
                .flags = qbe_c_flags,
            });
            mod.addCSourceFiles(.{
                .root = b.path("qbe"),
                .files = qbe_rv64_sources,
                .flags = qbe_c_flags,
            });
        }

        const unit_tests = b.addTest(.{
            .root_module = mod,
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
}
