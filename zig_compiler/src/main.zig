//! FasterBASIC Compiler — Zig Implementation
//!
//! Entry point and command-line interface for the `fbc` compiler.
//!
//! Pipeline:
//!   1. Read .bas source file
//!   2. Lex → token stream
//!   3. Parse → AST
//!   4. Semantic analysis → symbol table + validated AST
//!   5. Code generation → QBE IL text
//!   6. (Optional) Invoke external QBE backend → assembly
//!   7. (Optional) Invoke assembler/linker → native executable
//!
//! Usage:
//!   fbc input.bas                     Compile to executable (default name from input)
//!   fbc input.bas -o program          Compile to named executable
//!   fbc input.bas -i                  Emit QBE IL to stdout
//!   fbc input.bas -i -o output.qbe    Emit QBE IL to file
//!   fbc input.bas -c -o output.s      Emit assembly to file
//!   fbc input.bas --show-il           Compile and print IL to stderr
//!   fbc input.bas --trace-ast         Dump the AST and exit
//!   fbc input.bas --trace-symbols     Dump the symbol table and exit
//!   fbc input.bas -v                  Verbose output
//!   fbc --help                        Show help
//!   fbc --version                     Show version

const std = @import("std");
const lexer_mod = @import("lexer.zig");
const token_mod = @import("token.zig");
const parser_mod = @import("parser.zig");
const ast = @import("ast.zig");
const semantic = @import("semantic.zig");
const ast_optimize = @import("ast_optimize.zig");
const cfg_mod = @import("cfg.zig");
const codegen = @import("codegen.zig");
const qbe = @import("qbe.zig");

const Lexer = lexer_mod.Lexer;
const Token = token_mod.Token;
const Tag = token_mod.Tag;
const Parser = parser_mod.Parser;
const SemanticAnalyzer = semantic.SemanticAnalyzer;
const CFGCodeGenerator = codegen.CFGCodeGenerator;
const CFGBuilder = cfg_mod.CFGBuilder;

const version_string = "fbc 0.1.0 (FasterBASIC Zig Compiler)";

// ─── CLI Options ────────────────────────────────────────────────────────────

const OutputMode = enum {
    executable,
    il_only,
    asm_only,
    jit,
};

const Options = struct {
    input_path: ?[]const u8 = null,
    output_path: ?[]const u8 = null,
    mode: OutputMode = .executable,
    show_il: bool = false,
    trace_ast: bool = false,
    trace_symbols: bool = false,
    trace_cfg: bool = false,
    verbose: bool = false,
    show_help: bool = false,
    show_version: bool = false,
    show_tokens: bool = false,
    run_after_compile: bool = false,
    jit_verbose: bool = false,
    metrics: bool = false,
    no_optimize: bool = false,
    cc_path: []const u8 = "cc",
    runtime_dir: ?[]const u8 = null,
    error_message: ?[]const u8 = null,
    /// Arguments to pass to the JIT-compiled program (collected after
    /// the input file when --run is used).
    program_args: []const []const u8 = &.{},
    /// Path to a folder for --batch-jit mode: recursively scan for .bas
    /// files and JIT-execute each one sequentially in a single process.
    batch_jit_path: ?[]const u8 = null,
    /// Stop batch-jit on first failure instead of continuing.
    batch_fail_fast: bool = false,
    /// Per-file timeout in seconds for batch-jit mode (0 = no timeout).
    batch_timeout: u32 = 30,
};

fn parseArgs(allocator: std.mem.Allocator) Options {
    var opts = Options{};

    var args = std.process.args();
    _ = args.skip(); // skip argv[0]

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            opts.show_help = true;
            return opts;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-V")) {
            opts.show_version = true;
            return opts;
        } else if (std.mem.eql(u8, arg, "-o")) {
            opts.output_path = args.next() orelse {
                opts.error_message = "Missing argument for -o";
                return opts;
            };
        } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--il")) {
            opts.mode = .il_only;
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--asm")) {
            opts.mode = .asm_only;
        } else if (std.mem.eql(u8, arg, "--show-il")) {
            opts.show_il = true;
        } else if (std.mem.eql(u8, arg, "--trace-ast") or std.mem.eql(u8, arg, "-A")) {
            opts.trace_ast = true;
        } else if (std.mem.eql(u8, arg, "--trace-symbols") or std.mem.eql(u8, arg, "-S")) {
            opts.trace_symbols = true;
        } else if (std.mem.eql(u8, arg, "--trace-cfg") or std.mem.eql(u8, arg, "-G")) {
            opts.trace_cfg = true;
        } else if (std.mem.eql(u8, arg, "--show-tokens")) {
            opts.show_tokens = true;
        } else if (std.mem.eql(u8, arg, "--jit") or std.mem.eql(u8, arg, "-J")) {
            opts.mode = .jit;
        } else if (std.mem.eql(u8, arg, "--jit-verbose")) {
            opts.mode = .jit;
            opts.jit_verbose = true;
        } else if (std.mem.eql(u8, arg, "--metrics")) {
            opts.metrics = true;
        } else if (std.mem.eql(u8, arg, "--batch-jit")) {
            opts.batch_jit_path = args.next() orelse {
                opts.error_message = "Missing folder argument for --batch-jit";
                return opts;
            };
            opts.mode = .jit;
        } else if (std.mem.eql(u8, arg, "--timeout")) {
            const val = args.next() orelse {
                opts.error_message = "Missing seconds argument for --timeout";
                return opts;
            };
            opts.batch_timeout = std.fmt.parseInt(u32, val, 10) catch {
                opts.error_message = "Invalid number for --timeout";
                return opts;
            };
        } else if (std.mem.eql(u8, arg, "--fail-fast")) {
            opts.batch_fail_fast = true;
        } else if (std.mem.eql(u8, arg, "--no-optimize")) {
            opts.no_optimize = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            opts.verbose = true;
        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--run")) {
            opts.run_after_compile = true;
            opts.mode = .jit; // --run implies JIT mode
        } else if (std.mem.eql(u8, arg, "--cc")) {
            opts.cc_path = args.next() orelse {
                opts.error_message = "Missing argument for --cc";
                return opts;
            };
        } else if (std.mem.eql(u8, arg, "--runtime-dir")) {
            opts.runtime_dir = args.next() orelse {
                opts.error_message = "Missing argument for --runtime-dir";
                return opts;
            };
        } else if (arg.len > 0 and arg[0] == '-') {
            opts.error_message = arg;
            return opts;
        } else {
            // Positional argument: input file
            if (opts.input_path != null) {
                opts.error_message = "Multiple input files are not supported";
                return opts;
            }
            opts.input_path = arg;

            // In --run mode, everything after the input file is a
            // program argument — stop parsing compiler flags.
            if (opts.run_after_compile) {
                var prog_args: std.ArrayListUnmanaged([]const u8) = .{};
                // argv[0] for the program = the .bas source path
                prog_args.append(allocator, arg) catch {};
                while (args.next()) |parg| {
                    prog_args.append(allocator, parg) catch {};
                }
                opts.program_args = prog_args.toOwnedSlice(allocator) catch &.{};
                return opts;
            }
        }
    }

    return opts;
}

// ─── Help Text ──────────────────────────────────────────────────────────────

fn printHelp(writer: anytype) void {
    writer.print(
        \\{s}
        \\
        \\Usage: fbc [options] <input.bas>
        \\       fbc --run <input.bas> [program args...]
        \\
        \\Compiles FasterBASIC source files to native executables via QBE IL.
        \\
        \\Output Modes:
        \\  (default)                Compile to native executable
        \\  -i, --il                 Emit QBE Intermediate Language only
        \\  -c, --asm                Emit assembly only
        \\  -J, --jit                JIT compile and execute in-process (ARM64)
        \\  -r, --run                JIT compile and run, passing remaining args to program
        \\
        \\Options:
        \\  -o <path>                Output file path (default: derived from input)
        \\  -v, --verbose            Verbose compiler output
        \\  --no-optimize            Disable AST optimization pass
        \\  -h, --help               Show this help message
        \\  -V, --version            Show version information
        \\
        \\JIT Options:
        \\  --jit-verbose            JIT mode with full pipeline/link/layout report
        \\  --metrics                Print phase timings and SAMM memory stats after JIT run
        \\  --batch-jit <folder>     Recursively find .bas files and JIT-execute each one
        \\  --fail-fast              Stop batch-jit on first failure
        \\  --timeout <secs>         Per-file timeout for batch-jit (default: 30, 0=none)
        \\
        \\Debug / Trace:
        \\  --show-il                Print generated QBE IL to stderr
        \\  --show-tokens            Print token stream to stderr
        \\  -A, --trace-ast          Dump the AST and exit
        \\  -S, --trace-symbols      Dump the symbol table and exit
        \\  -G, --trace-cfg          Dump CFG analysis and exit
        \\
        \\Toolchain:
        \\  --cc <path>              Path to the C compiler/linker (default: cc)
        \\  --runtime-dir <path>     Path to the BASIC runtime library sources
        \\
        \\QBE Backend (embedded):
        \\  QBE is built into this compiler — no external qbe binary needed.
        \\
        \\Examples:
        \\  fbc hello.bas                    # Compile hello.bas → hello
        \\  fbc hello.bas -o greet           # Compile hello.bas → greet
        \\  fbc hello.bas -i                 # Print QBE IL to stdout
        \\  fbc hello.bas -i -o hello.qbe    # Write QBE IL to hello.qbe
        \\  fbc hello.bas --show-il          # Compile and show IL on stderr
        \\  fbc --run hello.bas arg1 arg2    # JIT run with program arguments
        \\  fbc hello.bas --jit              # JIT compile and execute in-process
        \\  fbc hello.bas --jit-verbose      # JIT with full diagnostic report
        \\  fbc --batch-jit tests/           # JIT-execute all .bas files in folder
        \\  fbc --batch-jit tests/ --metrics # Batch with per-file metrics
        \\
        \\
    , .{version_string}) catch {};
}

// ─── Source File Reading ────────────────────────────────────────────────────

fn readSourceFile(path: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        return err;
    };
    defer file.close();

    const stat = try file.stat();
    if (stat.size > 100 * 1024 * 1024) {
        return error.FileTooBig;
    }

    return try file.readToEndAlloc(allocator, 100 * 1024 * 1024);
}

// ─── Derive Output Path ────────────────────────────────────────────────────

fn deriveOutputPath(input_path: []const u8, mode: OutputMode, allocator: std.mem.Allocator) ![]const u8 {
    // Strip directory components: "path/to/hello.bas" → "hello.bas"
    const basename = std.fs.path.basename(input_path);

    // Strip extension: "hello.bas" → "hello"
    const stem = blk: {
        if (std.mem.lastIndexOfScalar(u8, basename, '.')) |dot_pos| {
            break :blk basename[0..dot_pos];
        }
        break :blk basename;
    };

    return switch (mode) {
        .executable => try allocator.dupe(u8, stem),
        .il_only => try std.fmt.allocPrint(allocator, "{s}.qbe", .{stem}),
        .asm_only => try std.fmt.allocPrint(allocator, "{s}.s", .{stem}),
        .jit => try allocator.dupe(u8, stem), // JIT doesn't need output path, but handle for completeness
    };
}

// ─── Token Dump ─────────────────────────────────────────────────────────────

fn dumpTokens(tokens: []const Token, writer: anytype) void {
    writer.print("\n=== Token Stream ({d} tokens) ===\n", .{tokens.len}) catch {};
    for (tokens, 0..) |tok, i| {
        writer.print("  [{d:>4}] {s:<20} ", .{ i, @tagName(tok.tag) }) catch {};
        if (tok.lexeme.len > 0) {
            if (tok.lexeme.len <= 40) {
                writer.print("\"{s}\"", .{tok.lexeme}) catch {};
            } else {
                writer.print("\"{s}...\"", .{tok.lexeme[0..37]}) catch {};
            }
        }
        if (tok.tag == .number) {
            writer.print(" = {d}", .{tok.number_value}) catch {};
        }
        writer.print("  ({d}:{d})\n", .{ tok.location.line, tok.location.column }) catch {};
    }
    writer.print("=== End Token Stream ===\n\n", .{}) catch {};
}

// ─── AST Dump ───────────────────────────────────────────────────────────────

fn dumpAST(program: *const ast.Program, writer: anytype) void {
    writer.print("\n=== AST Dump ({d} program lines) ===\n", .{program.lines.len}) catch {};
    for (program.lines, 0..) |line, i| {
        writer.print("  Line {d} (line_number={d}, {d} statements):\n", .{
            i,
            line.line_number,
            line.statements.len,
        }) catch {};
        for (line.statements, 0..) |stmt, j| {
            writer.print("    [{d}] {s}", .{ j, @tagName(std.meta.activeTag(stmt.data)) }) catch {};
            dumpStmtDetail(stmt, writer);
            writer.print("  ({d}:{d})\n", .{ stmt.loc.line, stmt.loc.column }) catch {};
        }
    }
    writer.print("=== End AST Dump ===\n\n", .{}) catch {};
}

fn dumpStmtDetail(stmt: *const ast.Statement, writer: anytype) void {
    switch (stmt.data) {
        .print => |pr| {
            writer.print(" ({d} items, trailing_nl={any})", .{ pr.items.len, pr.trailing_newline }) catch {};
        },
        .let => |lt| {
            writer.print(" var=\"{s}\"", .{lt.variable}) catch {};
            if (lt.type_suffix) |s| writer.print(" suffix={s}", .{@tagName(s)}) catch {};
            if (lt.member_chain.len > 0) writer.print(" members={d}", .{lt.member_chain.len}) catch {};
            if (lt.indices.len > 0) writer.print(" indices={d}", .{lt.indices.len}) catch {};
        },
        .if_stmt => |ifs| {
            writer.print(" then={d} elseif={d} else={d} multi={any}", .{
                ifs.then_statements.len,
                ifs.elseif_clauses.len,
                ifs.else_statements.len,
                ifs.is_multi_line,
            }) catch {};
        },
        .for_stmt => |fs| {
            writer.print(" var=\"{s}\" body={d}", .{ fs.variable, fs.body.len }) catch {};
        },
        .while_stmt => |ws| {
            writer.print(" body={d}", .{ws.body.len}) catch {};
        },
        .do_stmt => |ds| {
            writer.print(" body={d}", .{ds.body.len}) catch {};
        },
        .repeat_stmt => |rs| {
            writer.print(" body={d}", .{rs.body.len}) catch {};
        },
        .dim => |dim| {
            writer.print(" ({d} decls)", .{dim.arrays.len}) catch {};
            for (dim.arrays) |arr| {
                writer.print(" \"{s}\"", .{arr.name}) catch {};
                if (arr.dimensions.len > 0) writer.print("({d}d)", .{arr.dimensions.len}) catch {};
                if (arr.has_as_type) writer.print(" AS ...", .{}) catch {};
            }
        },
        .function => |func| {
            writer.print(" \"{s}\" ({d} params, {d} body stmts)", .{
                func.function_name,
                func.parameters.len,
                func.body.len,
            }) catch {};
        },
        .sub => |sub| {
            writer.print(" \"{s}\" ({d} params, {d} body stmts)", .{
                sub.sub_name,
                sub.parameters.len,
                sub.body.len,
            }) catch {};
        },
        .type_decl => |td| {
            writer.print(" \"{s}\" ({d} fields)", .{ td.type_name, td.fields.len }) catch {};
        },
        .class => |cls| {
            writer.print(" \"{s}\"", .{cls.class_name}) catch {};
            if (cls.parent_class_name.len > 0) writer.print(" EXTENDS \"{s}\"", .{cls.parent_class_name}) catch {};
            writer.print(" ({d} fields)", .{cls.fields.len}) catch {};
        },
        .call => |cs| {
            writer.print(" \"{s}\" ({d} args)", .{ cs.sub_name, cs.arguments.len }) catch {};
        },
        .label => |lbl| {
            writer.print(" \"{s}\"", .{lbl.label_name}) catch {};
        },
        .goto_stmt => |gt| {
            if (gt.is_label) {
                writer.print(" label=\"{s}\"", .{gt.label}) catch {};
            } else {
                writer.print(" line={d}", .{gt.line_number}) catch {};
            }
        },
        .gosub => |gs| {
            if (gs.is_label) {
                writer.print(" label=\"{s}\"", .{gs.label}) catch {};
            } else {
                writer.print(" line={d}", .{gs.line_number}) catch {};
            }
        },
        .constant => |con| {
            writer.print(" \"{s}\"", .{con.name}) catch {};
        },
        .option => |opt| {
            writer.print(" {s} = {d}", .{ @tagName(opt.option_type), opt.value }) catch {};
        },
        .case_stmt => |cs| {
            writer.print(" ({d} when clauses)", .{cs.when_clauses.len}) catch {};
        },
        .data_stmt => |ds| {
            writer.print(" ({d} values)", .{ds.values.len}) catch {};
        },
        .return_stmt => |rs| {
            if (rs.return_value != null) writer.print(" (with value)", .{}) catch {};
        },
        .exit_stmt => |es| {
            writer.print(" {s}", .{@tagName(es.exit_type)}) catch {};
        },
        .try_catch => |tc| {
            writer.print(" try={d} catch={d} finally={d}", .{
                tc.try_block.len,
                tc.catch_clauses.len,
                tc.finally_block.len,
            }) catch {};
        },
        .console => |con| {
            writer.print(" ({d} items)", .{con.items.len}) catch {};
        },
        .swap => |sw| {
            writer.print(" \"{s}\" <-> \"{s}\"", .{ sw.var1, sw.var2 }) catch {};
        },
        .inc, .dec => |id| {
            writer.print(" \"{s}\"", .{id.var_name}) catch {};
        },
        .erase => |er| {
            writer.print(" ({d} arrays)", .{er.array_names.len}) catch {};
        },
        .rem => |rm| {
            if (rm.comment.len > 0) writer.print(" \"{s}\"", .{rm.comment}) catch {};
        },
        else => {},
    }
}

// ─── Symbol Table Dump ──────────────────────────────────────────────────────

fn dumpSymbolTable(st: *const semantic.SymbolTable, writer: anytype) void {
    writer.print("\n=== Symbol Table Dump ===\n", .{}) catch {};

    // Variables
    writer.print("\nVariables ({d}):\n", .{st.variables.count()}) catch {};
    {
        var it = st.variables.iterator();
        while (it.next()) |entry| {
            const sym = entry.value_ptr;
            writer.print("  {s}: base_type={s} declared={any} used={any} global={any}\n", .{
                entry.key_ptr.*,
                sym.type_desc.base_type.name(),
                sym.is_declared,
                sym.is_used,
                sym.is_global,
            }) catch {};
        }
    }

    // Arrays
    writer.print("\nArrays ({d}):\n", .{st.arrays.count()}) catch {};
    {
        var it = st.arrays.iterator();
        while (it.next()) |entry| {
            const sym = entry.value_ptr;
            writer.print("  {s}: element_type={s}", .{
                entry.key_ptr.*,
                sym.element_type_desc.base_type.name(),
            }) catch {};
            if (sym.as_type_name.len > 0) writer.print(" as_type=\"{s}\"", .{sym.as_type_name}) catch {};
            writer.print("\n", .{}) catch {};
        }
    }

    // Functions/Subs
    writer.print("\nFunctions ({d}):\n", .{st.functions.count()}) catch {};
    {
        var it = st.functions.iterator();
        while (it.next()) |entry| {
            const sym = entry.value_ptr;
            writer.print("  {s}: return={s} params={d}\n", .{
                entry.key_ptr.*,
                sym.return_type_desc.base_type.name(),
                sym.parameters.len,
            }) catch {};
        }
    }

    // Types (UDTs)
    writer.print("\nTypes ({d}):\n", .{st.types.count()}) catch {};
    {
        var it = st.types.iterator();
        while (it.next()) |entry| {
            const sym = entry.value_ptr;
            writer.print("  {s}: {d} fields\n", .{
                entry.key_ptr.*,
                sym.fields.len,
            }) catch {};
            for (sym.fields) |field| {
                writer.print("    .{s}: {s}\n", .{ field.name, field.type_desc.base_type.name() }) catch {};
            }
        }
    }

    // Classes
    writer.print("\nClasses ({d}):\n", .{st.classes.count()}) catch {};
    {
        var it = st.classes.iterator();
        while (it.next()) |entry| {
            const sym = entry.value_ptr;
            writer.print("  {s} (id={d})", .{ entry.key_ptr.*, sym.class_id }) catch {};
            if (sym.parent_class) |parent| {
                writer.print(" EXTENDS {s}", .{parent.name}) catch {};
            }
            writer.print(" size={d} fields={d} methods={d}\n", .{
                sym.object_size,
                sym.fields.len,
                sym.methods.len,
            }) catch {};
        }
    }

    // Labels
    writer.print("\nLabels ({d}):\n", .{st.labels.count()}) catch {};
    {
        var it = st.labels.iterator();
        while (it.next()) |entry| {
            const sym = entry.value_ptr;
            writer.print("  {s}: id={d}\n", .{ entry.key_ptr.*, sym.label_id }) catch {};
        }
    }

    // Constants
    writer.print("\nConstants ({d}):\n", .{st.constants.count()}) catch {};
    {
        var it = st.constants.iterator();
        while (it.next()) |entry| {
            const sym = entry.value_ptr;
            writer.print("  {s}: ", .{entry.key_ptr.*}) catch {};
            switch (sym.kind) {
                .integer_const => writer.print("INTEGER = {d}\n", .{sym.int_value}) catch {},
                .double_const => writer.print("DOUBLE = {d}\n", .{sym.double_value}) catch {},
                .string_const => writer.print("STRING = \"{s}\"\n", .{sym.string_value}) catch {},
            }
        }
    }

    // DATA segment
    writer.print("\nDATA segment: {d} values\n", .{st.data_segment.values.items.len}) catch {};
    if (st.data_segment.values.items.len > 0) {
        writer.print("  Values: ", .{}) catch {};
        const max_show: usize = 20;
        const count = @min(st.data_segment.values.items.len, max_show);
        for (0..count) |i| {
            if (i > 0) writer.print(", ", .{}) catch {};
            writer.print("\"{s}\"", .{st.data_segment.values.items[i]}) catch {};
        }
        if (st.data_segment.values.items.len > max_show) {
            writer.print(" ... ({d} more)", .{st.data_segment.values.items.len - max_show}) catch {};
        }
        writer.print("\n", .{}) catch {};
    }

    // Configuration
    writer.print("\nConfiguration:\n", .{}) catch {};
    writer.print("  array_base = {d}\n", .{st.array_base}) catch {};
    writer.print("  samm_enabled = {any}\n", .{st.samm_enabled}) catch {};
    writer.print("  neon_enabled = {any}\n", .{st.neon_enabled}) catch {};
    writer.print("  error_tracking = {any}\n", .{st.error_tracking}) catch {};

    writer.print("\n=== End Symbol Table ===\n\n", .{}) catch {};
}

// ─── External Tool Invocation ───────────────────────────────────────────────

fn runExternalCommand(argv: []const []const u8, allocator: std.mem.Allocator, verbose: bool, stderr_writer: anytype) !void {
    if (verbose) {
        stderr_writer.print("[CMD]", .{}) catch {};
        for (argv) |arg| {
            stderr_writer.print(" {s}", .{arg}) catch {};
        }
        stderr_writer.print("\n", .{}) catch {};
    }

    var child = std.process.Child.init(argv, allocator);
    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;
    try child.spawn();
    const result = try child.wait();

    switch (result) {
        .Exited => |code| {
            if (code != 0) {
                stderr_writer.print("Error: command exited with code {d}\n", .{code}) catch {};
                return error.ExternalCommandFailed;
            }
        },
        else => {
            stderr_writer.print("Error: command terminated abnormally\n", .{}) catch {};
            return error.ExternalCommandFailed;
        },
    }
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// List all .c files in a directory.  Returns an owned slice of owned strings.
fn listCFiles(dir_path: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
    var results: std.ArrayList([]const u8) = .empty;
    defer results.deinit(allocator); // only the list; callers own the strings

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return &.{};
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        const name = entry.name;
        if (name.len < 3) continue;
        if (!std.mem.endsWith(u8, name, ".c")) continue;
        // Skip test stub files — they provide weak no-op stubs for
        // unit-testing runtime modules in isolation and must NOT be
        // linked into production binaries (they shadow the real
        // Zig runtime implementations, causing NULL-pointer crashes).
        if (std.mem.startsWith(u8, name, "test_")) continue;
        const full = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, name });
        try results.append(allocator, full);
    }

    return try results.toOwnedSlice(allocator);
}

/// Try to locate the runtime/ directory.
/// Search order:
///   1. Explicitly supplied --runtime-dir
///   2. <exe_dir>/../runtime/       (installed layout)
///   3. <exe_dir>/../../runtime/    (in-tree: zig-out/bin -> ../../runtime)
///   4. ./runtime/                  (cwd fallback)
fn findRuntimeDir(explicit: ?[]const u8, allocator: std.mem.Allocator) ?[]const u8 {
    // 1. Explicit
    if (explicit) |dir| {
        if (fileExists(dir)) return dir;
    }

    // Helper: check if a candidate directory contains basic_runtime.c
    const candidates = [_][]const u8{
        // Try relative to cwd
        "runtime",
    };

    // 2-4: Simple relative checks
    for (candidates) |cand| {
        const probe = std.fmt.allocPrint(allocator, "{s}/basic_runtime.c", .{cand}) catch continue;
        defer allocator.free(probe);
        if (fileExists(probe)) {
            return allocator.dupe(u8, cand) catch null;
        }
    }

    // Try paths relative to executable
    const exe_path = std.fs.selfExePathAlloc(allocator) catch return null;
    defer allocator.free(exe_path);

    // Find directory of executable
    const exe_dir = std.fs.path.dirname(exe_path) orelse return null;

    const relative_tries = [_][]const u8{
        "/../runtime",
        "/../../runtime",
    };

    for (relative_tries) |suffix| {
        const try_dir = std.fmt.allocPrint(allocator, "{s}{s}", .{ exe_dir, suffix }) catch continue;
        const probe = std.fmt.allocPrint(allocator, "{s}/basic_runtime.c", .{try_dir}) catch {
            allocator.free(try_dir);
            continue;
        };
        defer allocator.free(probe);
        if (fileExists(probe)) {
            return try_dir;
        }
        allocator.free(try_dir);
    }

    return null;
}

// ─── Check for .bas extension ───────────────────────────────────────────────

fn isBasicFile(path: []const u8) bool {
    if (path.len < 4) return false;
    const ext = path[path.len - 4 ..];
    return std.ascii.eqlIgnoreCase(ext, ".bas");
}

// ─── SAMM Stats (extern) ────────────────────────────────────────────────────

const SAMMStats = extern struct {
    scopes_entered: u64,
    scopes_exited: u64,
    objects_allocated: u64,
    objects_freed: u64,
    objects_cleaned: u64,
    cleanup_batches: u64,
    double_free_attempts: u64,
    bloom_false_positives: u64,
    retain_calls: u64,
    total_bytes_allocated: u64,
    total_bytes_freed: u64,
    strings_tracked: u64,
    strings_cleaned: u64,
    current_scope_depth: c_int,
    peak_scope_depth: c_int,
    bloom_memory_bytes: usize,
    total_cleanup_time_ms: f64,
    background_worker_active: c_int,
};

extern fn samm_get_stats(out: ?*SAMMStats) callconv(.c) void;
extern fn msg_metrics_reset() callconv(.c) void;
extern fn basic_jit_call(callback: *const fn (*anyopaque) callconv(.c) c_int, ctx: *anyopaque) callconv(.c) c_int;
extern fn basic_jit_set_timeout(seconds: c_uint) callconv(.c) void;
extern fn basic_jit_suppress_stdout() callconv(.c) c_int;
extern fn basic_jit_restore_stdout(saved_fd: c_int) callconv(.c) void;
extern fn basic_jit_arm_signals() callconv(.c) void;
extern fn basic_jit_disarm_signals() callconv(.c) void;

// ─── Metrics Helpers ────────────────────────────────────────────────────────

fn nsToMs(ns: i128) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
}

fn phaseMs(start_ns: i128, end_ns: i128) f64 {
    return nsToMs(end_ns - start_ns);
}

fn pct(part_ms: f64, total_ms: f64) f64 {
    if (total_ms <= 0.0) return 0.0;
    return (part_ms / total_ms) * 100.0;
}

const MetricsTimes = struct {
    read_ms: f64,
    lex_ms: f64,
    parse_ms: f64,
    semantic_ms: f64,
    cfg_ms: f64,
    codegen_ms: f64,
    jit_compile_ms: f64,
    jit_link_ms: f64,
    jit_exec_ms: f64,
    total_ms: f64,
};

fn printMetrics(writer: anytype, stats: SAMMStats, times: MetricsTimes) void {
    writer.print("\n", .{}) catch {};
    writer.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{}) catch {};
    writer.print("  fbc --metrics (JIT)\n", .{}) catch {};
    writer.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{}) catch {};
    writer.print("  Read source:         {d:.3} ms ({d:.1}%)\n", .{ times.read_ms, pct(times.read_ms, times.total_ms) }) catch {};
    writer.print("  Lexing:              {d:.3} ms ({d:.1}%)\n", .{ times.lex_ms, pct(times.lex_ms, times.total_ms) }) catch {};
    writer.print("  Parsing:             {d:.3} ms ({d:.1}%)\n", .{ times.parse_ms, pct(times.parse_ms, times.total_ms) }) catch {};
    writer.print("  Semantic analysis:   {d:.3} ms ({d:.1}%)\n", .{ times.semantic_ms, pct(times.semantic_ms, times.total_ms) }) catch {};
    writer.print("  CFG build:           {d:.3} ms ({d:.1}%)\n", .{ times.cfg_ms, pct(times.cfg_ms, times.total_ms) }) catch {};
    writer.print("  QBE IL codegen:      {d:.3} ms ({d:.1}%)\n", .{ times.codegen_ms, pct(times.codegen_ms, times.total_ms) }) catch {};
    writer.print("  JIT compile/encode:  {d:.3} ms ({d:.1}%)\n", .{ times.jit_compile_ms, pct(times.jit_compile_ms, times.total_ms) }) catch {};
    writer.print("  JIT link/finalize:   {d:.3} ms ({d:.1}%)\n", .{ times.jit_link_ms, pct(times.jit_link_ms, times.total_ms) }) catch {};
    writer.print("  JIT execute:         {d:.3} ms ({d:.1}%)\n", .{ times.jit_exec_ms, pct(times.jit_exec_ms, times.total_ms) }) catch {};
    writer.print("  TOTAL:               {d:.3} ms\n", .{times.total_ms}) catch {};

    const leaked_objects: i64 = @as(i64, @intCast(stats.objects_allocated)) - @as(i64, @intCast(stats.objects_freed + stats.objects_cleaned));
    const leaked_bytes: i64 = @as(i64, @intCast(stats.total_bytes_allocated)) - @as(i64, @intCast(stats.total_bytes_freed));

    writer.print("\n", .{}) catch {};
    writer.print("  SAMM Memory Manager\n", .{}) catch {};
    writer.print("  ----------------------------------------------------\n", .{}) catch {};
    writer.print("  Objects allocated:    {d}\n", .{stats.objects_allocated}) catch {};
    writer.print("  Objects freed (DEL):  {d}\n", .{stats.objects_freed}) catch {};
    writer.print("  Objects cleaned (bg): {d}\n", .{stats.objects_cleaned}) catch {};
    writer.print("  Strings tracked:      {d}\n", .{stats.strings_tracked}) catch {};
    writer.print("  Strings cleaned:      {d}\n", .{stats.strings_cleaned}) catch {};
    writer.print("  Bytes allocated:      {d}\n", .{stats.total_bytes_allocated}) catch {};
    writer.print("  Bytes freed:          {d}\n", .{stats.total_bytes_freed}) catch {};
    writer.print("  Leaked objects:       {d}\n", .{if (leaked_objects > 0) leaked_objects else 0}) catch {};
    writer.print("  Leaked bytes:         {d}\n", .{if (leaked_bytes > 0) leaked_bytes else 0}) catch {};
    writer.print("  Cleanup batches:      {d}\n", .{stats.cleanup_batches}) catch {};
    writer.print("  Cleanup time:         {d:.3} ms\n", .{stats.total_cleanup_time_ms}) catch {};
    writer.print("  Scope depth (cur/peak): {d}/{d}\n", .{ stats.current_scope_depth, stats.peak_scope_depth }) catch {};
    writer.print("  Bloom memory:         {d} bytes\n", .{stats.bloom_memory_bytes}) catch {};
    writer.print("  Background worker:    {s}\n", .{if (stats.background_worker_active != 0) "active" else "stopped"}) catch {};
    writer.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{}) catch {};
}

// ─── Main ───────────────────────────────────────────────────────────────────

// ─── Batch JIT: scan a directory recursively for .bas files ─────────────────

fn scanBasicFilesRecursive(
    dir_path: []const u8,
    allocator: std.mem.Allocator,
) ![][]const u8 {
    var results: std.ArrayList([]const u8) = .empty;

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        stderr.print("Error: cannot open directory '{s}': {s}\n", .{ dir_path, @errorName(err) }) catch {};
        return results.toOwnedSlice(allocator) catch &[_][]const u8{};
    };
    defer dir.close();

    // Use a walker for recursive traversal
    var walker = dir.walk(allocator) catch |err| {
        const stderr = std.fs.File.stderr().deprecatedWriter();
        stderr.print("Error: cannot walk directory '{s}': {s}\n", .{ dir_path, @errorName(err) }) catch {};
        return results.toOwnedSlice(allocator) catch &[_][]const u8{};
    };
    defer walker.deinit();

    while (walker.next() catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!isBasicFile(entry.path)) continue;

        // Build full path: dir_path / entry.path
        const full_path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, entry.path }) catch continue;
        results.append(allocator, full_path) catch continue;
    }

    // Sort for deterministic execution order (sort in-place before extracting)
    std.mem.sort([]const u8, results.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);
    return results.toOwnedSlice(allocator) catch &[_][]const u8{};
}

// ─── Batch JIT: compile and execute a single .bas file ──────────────────────
//
// Returns true on success, false on failure.
// Uses its own arena so all compiler memory is freed after each run.
// The JIT-compiled program itself calls samm_init/samm_shutdown, so
// runtime global state is properly cycled between runs.

const DirectBLAnalysis = @import("jit_linker.zig").DirectBLAnalysis;
const analyzeDirectBLReach = @import("jit_linker.zig").analyzeDirectBLReach;

const BatchResult = struct {
    ok: bool,
    exit_code: i32,
    compile_ms: f64,
    exec_ms: f64,
    error_phase: ?[]const u8,
    timed_out: bool = false,
    bl_analysis: DirectBLAnalysis = .{},
};

fn runSingleBatchFile(
    file_path: []const u8,
    gpa_alloc: std.mem.Allocator,
    verbose: bool,
    jit_verbose: bool,
    show_metrics: bool,
    timeout_secs: u32,
    no_optimize: bool,
) BatchResult {
    const stderr = std.fs.File.stderr().deprecatedWriter();

    // Create a per-file arena so all compiler objects are freed on return
    var file_arena = std.heap.ArenaAllocator.init(gpa_alloc);
    defer file_arena.deinit();
    const allocator = file_arena.allocator();

    const t_file_start = std.time.nanoTimestamp();

    // ── Read source ─────────────────────────────────────────────────
    const source = readSourceFile(file_path, allocator) catch |err| {
        stderr.print("  ERROR: cannot read '{s}': {s}\n", .{ file_path, @errorName(err) }) catch {};
        return .{ .ok = false, .exit_code = -1, .compile_ms = 0, .exec_ms = 0, .error_phase = "read" };
    };

    // ── Lex ─────────────────────────────────────────────────────────
    var lex = Lexer.init(source, allocator);
    defer lex.deinit();
    lex.tokenize() catch {
        stderr.print("  ERROR: lexer failure\n", .{}) catch {};
        return .{ .ok = false, .exit_code = -1, .compile_ms = 0, .exec_ms = 0, .error_phase = "lex" };
    };
    if (lex.hasErrors()) {
        for (lex.errors.items) |lerr| {
            stderr.print("  LEX {d}:{d}: {s}\n", .{ lerr.location.line, lerr.location.column, lerr.message }) catch {};
        }
        return .{ .ok = false, .exit_code = -1, .compile_ms = 0, .exec_ms = 0, .error_phase = "lex" };
    }

    // ── Parse ───────────────────────────────────────────────────────
    var parser = Parser.init(lex.tokens.items, allocator);
    defer parser.deinit();
    const program = parser.parse() catch {
        stderr.print("  ERROR: parser failure\n", .{}) catch {};
        if (parser.hasErrors()) {
            for (parser.errors.items) |perr| {
                stderr.print("  PARSE {d}:{d}: {s}\n", .{ perr.location.line, perr.location.column, perr.message }) catch {};
            }
        }
        return .{ .ok = false, .exit_code = -1, .compile_ms = 0, .exec_ms = 0, .error_phase = "parse" };
    };
    if (parser.hasErrors()) {
        for (parser.errors.items) |perr| {
            stderr.print("  PARSE {d}:{d}: {s}\n", .{ perr.location.line, perr.location.column, perr.message }) catch {};
        }
        return .{ .ok = false, .exit_code = -1, .compile_ms = 0, .exec_ms = 0, .error_phase = "parse" };
    }

    // ── Semantic analysis ───────────────────────────────────────────
    var analyzer = SemanticAnalyzer.init(allocator);
    defer analyzer.deinit();
    const sem_ok = analyzer.analyze(&program) catch {
        stderr.print("  ERROR: semantic analysis failure\n", .{}) catch {};
        return .{ .ok = false, .exit_code = -1, .compile_ms = 0, .exec_ms = 0, .error_phase = "semantic" };
    };
    if (!sem_ok) {
        for (analyzer.errors.items) |serr| {
            stderr.print("  SEM {d}:{d}: [{s}] {s}\n", .{
                serr.location.line,
                serr.location.column,
                @tagName(serr.error_type),
                serr.message,
            }) catch {};
        }
        return .{ .ok = false, .exit_code = -1, .compile_ms = 0, .exec_ms = 0, .error_phase = "semantic" };
    }

    // ── AST optimization ────────────────────────────────────────────
    var ast_opt = ast_optimize.ASTOptimizer.init(analyzer.getSymbolTable(), allocator);
    defer ast_opt.deinit();
    if (!no_optimize) {
        ast_opt.optimize(@constCast(&program)) catch {
            stderr.print("  ERROR: AST optimization failure\n", .{}) catch {};
            return .{ .ok = false, .exit_code = -1, .compile_ms = 0, .exec_ms = 0, .error_phase = "ast_opt" };
        };
    }

    // ── CFG ─────────────────────────────────────────────────────────
    var cfg_builder = CFGBuilder.init(allocator);
    defer cfg_builder.deinit();
    const program_cfg = cfg_builder.buildFromProgram(&program) catch {
        stderr.print("  ERROR: CFG construction failure\n", .{}) catch {};
        return .{ .ok = false, .exit_code = -1, .compile_ms = 0, .exec_ms = 0, .error_phase = "cfg" };
    };

    // ── Codegen ─────────────────────────────────────────────────────
    var gen = CFGCodeGenerator.init(&analyzer, program_cfg, &cfg_builder, allocator);
    defer gen.deinit();
    gen.verbose = false; // suppress per-file codegen verbosity
    gen.samm_enabled = analyzer.options.samm_enabled;
    gen.for_step_directions = &ast_opt.for_step_directions;

    const il = gen.generate(&program) catch {
        stderr.print("  ERROR: code generation failure\n", .{}) catch {};
        return .{ .ok = false, .exit_code = -1, .compile_ms = 0, .exec_ms = 0, .error_phase = "codegen" };
    };

    // ── JIT compile ─────────────────────────────────────────────────
    // Wrap in basic_jit_call so that if QBE's die_() fires (calling
    // basic_exit), we longjmp back here instead of killing the process.
    const CompileCtx = struct {
        alloc: std.mem.Allocator,
        il_ptr: []const u8,
        out: ?qbe.JitResult = null,

        fn run(raw: *anyopaque) callconv(.c) c_int {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.out = qbe.compileILJit(self.alloc, self.il_ptr, null) catch return -1;
            return 0;
        }
    };
    var compile_ctx = CompileCtx{ .alloc = allocator, .il_ptr = il };
    const compile_rc = basic_jit_call(CompileCtx.run, @ptrCast(&compile_ctx));
    if (compile_rc < 0) {
        // QBE died or compilation error — compile_rc < -1 means basic_exit was called
        stderr.print("  ERROR: JIT compilation failed\n", .{}) catch {};
        return .{ .ok = false, .exit_code = -1, .compile_ms = 0, .exec_ms = 0, .error_phase = "jit_compile" };
    }
    const jit_result = compile_ctx.out orelse {
        stderr.print("  ERROR: JIT compilation returned no result\n", .{}) catch {};
        return .{ .ok = false, .exit_code = -1, .compile_ms = 0, .exec_ms = 0, .error_phase = "jit_compile" };
    };

    if (jit_verbose) {
        const pr = jit_result.pipelineReport();
        stderr.print("{s}\n", .{pr}) catch {};
    }

    // ── JIT link ────────────────────────────────────────────────────
    const jit_runtime = @import("jit_runtime.zig");
    const jit_stubs = @import("jit_stubs.zig");
    const ctx = jit_stubs.buildJitRuntimeContext();

    var session = jit_runtime.JitSession.compileFromModule(
        allocator,
        jit_result.module,
        &ctx,
        null,
        0,
        jit_result.inst_count,
        jit_result.func_count,
        jit_result.data_count,
        jit_result.pipelineReport(),
    ) catch {
        stderr.print("  ERROR: JIT session creation failed\n", .{}) catch {};
        return .{ .ok = false, .exit_code = -1, .compile_ms = 0, .exec_ms = 0, .error_phase = "jit_link" };
    };
    defer session.deinit();

    // ── Direct BL reach analysis (non-destructive) ──────────────────
    const bl_analysis = analyzeDirectBLReach(
        &session.region,
        &session.module,
        &session.link_result.resolved_symbols,
    );

    if (!session.finalized) {
        stderr.print("  ERROR: JIT session failed to finalize\n", .{}) catch {};
        return .{ .ok = false, .exit_code = -1, .compile_ms = 0, .exec_ms = 0, .error_phase = "jit_link" };
    }

    const t_before_exec = std.time.nanoTimestamp();

    // ── Arm per-file timeout ────────────────────────────────────────
    if (timeout_secs > 0)
        basic_jit_set_timeout(@intCast(timeout_secs));

    // ── Execute ─────────────────────────────────────────────────────
    const exec_result = session.execute();

    // ── Disarm timeout ──────────────────────────────────────────────
    if (timeout_secs > 0)
        basic_jit_set_timeout(0);

    const t_after_exec = std.time.nanoTimestamp();

    const compile_ms = phaseMs(t_file_start, t_before_exec);
    const exec_ms = phaseMs(t_before_exec, t_after_exec);

    // ── Per-file metrics ────────────────────────────────────────────
    if (show_metrics) {
        var samm_stats: SAMMStats = undefined;
        samm_get_stats(&samm_stats);

        const total_ms = phaseMs(t_file_start, t_after_exec);

        stderr.print("  compile={d:.3}ms  exec={d:.3}ms  total={d:.3}ms", .{ compile_ms, exec_ms, total_ms }) catch {};
        stderr.print("  samm_alloc={d}  samm_freed={d}", .{ samm_stats.objects_allocated, samm_stats.objects_freed + samm_stats.objects_cleaned }) catch {};

        const leaked: i64 = @as(i64, @intCast(samm_stats.objects_allocated)) - @as(i64, @intCast(samm_stats.objects_freed + samm_stats.objects_cleaned));
        if (leaked > 0) {
            stderr.print("  LEAKED={d}", .{leaked}) catch {};
        }
        stderr.print("\n", .{}) catch {};
    }

    if (verbose) {
        stderr.print("  compile={d:.3}ms  exec={d:.3}ms\n", .{ compile_ms, exec_ms }) catch {};
    }

    if (exec_result.completed) {
        const is_timeout = exec_result.exit_code == 124;
        return .{
            .ok = exec_result.exit_code == 0,
            .exit_code = exec_result.exit_code,
            .compile_ms = compile_ms,
            .exec_ms = exec_ms,
            .error_phase = if (is_timeout) "timeout" else if (exec_result.exit_code != 0) "runtime" else null,
            .timed_out = is_timeout,
            .bl_analysis = bl_analysis,
        };
    } else {
        stderr.print("  ERROR: JIT execution did not complete", .{}) catch {};
        if (exec_result.signal != 0) {
            stderr.print(" (signal {d})", .{exec_result.signal}) catch {};
        }
        stderr.print("\n", .{}) catch {};
        return .{ .ok = false, .exit_code = -1, .compile_ms = compile_ms, .exec_ms = exec_ms, .error_phase = "exec", .bl_analysis = bl_analysis };
    }
}

// ─── Entry Point ────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    const stderr = std.fs.File.stderr().deprecatedWriter();
    const stdout = std.fs.File.stdout().deprecatedWriter();

    // Parse command-line arguments
    const opts = parseArgs(allocator);

    // Handle --help
    if (opts.show_help) {
        printHelp(stdout);
        return;
    }

    // Handle --version
    if (opts.show_version) {
        stdout.print("{s}\n", .{version_string}) catch {};
        stdout.print("QBE backend: {s} (target: {s})\n", .{ qbe.version(), qbe.defaultTarget() }) catch {};
        return;
    }

    // Handle parse errors
    if (opts.error_message) |msg| {
        stderr.print("Error: {s}\n", .{msg}) catch {};
        stderr.print("Try 'fbc --help' for usage information.\n", .{}) catch {};
        std.process.exit(1);
    }

    // ── Batch JIT mode ──────────────────────────────────────────────
    if (opts.batch_jit_path) |batch_dir| {
        stderr.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{}) catch {};
        stderr.print("  fbc --batch-jit  {s}\n", .{batch_dir}) catch {};
        stderr.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{}) catch {};

        const files = scanBasicFilesRecursive(batch_dir, allocator) catch |err| {
            stderr.print("Error: cannot scan '{s}': {s}\n", .{ batch_dir, @errorName(err) }) catch {};
            std.process.exit(1);
        };

        if (files.len == 0) {
            stderr.print("No .bas files found in '{s}'\n", .{batch_dir}) catch {};
            std.process.exit(1);
        }

        stderr.print("Found {d} .bas file(s)\n\n", .{files.len}) catch {};

        // Arm SIGABRT + SIGALRM handlers for the entire batch run so
        // they stay active across both compilation (basic_jit_call) and
        // execution (basic_jit_exec) phases.
        basic_jit_arm_signals();
        defer basic_jit_disarm_signals();

        // Reset opcode histogram so we get a clean tally for this batch
        qbe.histogramReset();

        const t_batch_start = std.time.nanoTimestamp();
        var passed: usize = 0;
        var failed: usize = 0;
        var total_compile_ms: f64 = 0;
        var total_exec_ms: f64 = 0;
        var batch_bl_analysis = DirectBLAnalysis{};

        for (files, 0..) |file_path, i| {
            // Reset messaging metrics between runs so they don't accumulate
            msg_metrics_reset();

            stderr.print("[{d}/{d}] {s}\n", .{ i + 1, files.len, file_path }) catch {};

            const result = runSingleBatchFile(
                file_path,
                gpa.allocator(),
                opts.verbose,
                opts.jit_verbose,
                opts.metrics,
                opts.batch_timeout,
                opts.no_optimize,
            );

            total_compile_ms += result.compile_ms;
            total_exec_ms += result.exec_ms;
            batch_bl_analysis.accumulate(&result.bl_analysis);

            if (result.ok) {
                stderr.print("  OK    {s}\n", .{file_path}) catch {};
                passed += 1;
            } else {
                if (result.timed_out) {
                    stderr.print("  TIMEOUT (>{d}s)  {s}\n", .{ opts.batch_timeout, file_path }) catch {};
                } else if (result.error_phase) |phase| {
                    stderr.print("  FAIL ({s}, exit={d})  {s}\n", .{ phase, result.exit_code, file_path }) catch {};
                } else {
                    stderr.print("  FAIL (exit={d})  {s}\n", .{ result.exit_code, file_path }) catch {};
                }
                failed += 1;
                if (opts.batch_fail_fast) {
                    stderr.print("\n--fail-fast: stopping after first failure\n", .{}) catch {};
                    break;
                }
            }
        }

        const t_batch_end = std.time.nanoTimestamp();
        const batch_total_ms = phaseMs(t_batch_start, t_batch_end);

        stderr.print("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{}) catch {};
        stderr.print("  Batch Summary\n", .{}) catch {};
        stderr.print("──────────────────────────────────────────────────────\n", .{}) catch {};
        stderr.print("  Files:     {d}\n", .{files.len}) catch {};
        stderr.print("  Passed:    {d}\n", .{passed}) catch {};
        stderr.print("  Failed:    {d}\n", .{failed}) catch {};
        stderr.print("  Compile:   {d:.3} ms\n", .{total_compile_ms}) catch {};
        stderr.print("  Execute:   {d:.3} ms\n", .{total_exec_ms}) catch {};
        stderr.print("  Total:     {d:.3} ms\n", .{batch_total_ms}) catch {};
        stderr.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{}) catch {};

        // Print the accumulated opcode histogram when --metrics is active
        if (opts.metrics) {
            qbe.histogramDump();
            batch_bl_analysis.dump(stderr);
        }

        if (failed > 0) {
            std.process.exit(1);
        }
        return;
    }

    // Require input file
    const input_path = opts.input_path orelse {
        stderr.print("Error: no input file specified\n", .{}) catch {};
        stderr.print("Try 'fbc --help' for usage information.\n", .{}) catch {};
        std.process.exit(1);
    };

    // Validate input file extension
    if (!isBasicFile(input_path)) {
        stderr.print("Warning: input file '{s}' does not have a .bas extension\n", .{input_path}) catch {};
    }

    if (opts.verbose or (opts.mode == .jit and opts.jit_verbose)) {
        stderr.print("{s}\n", .{version_string}) catch {};
        stderr.print("Input: {s}\n", .{input_path}) catch {};
        stderr.print("Mode: {s}\n", .{@tagName(opts.mode)}) catch {};
    }

    // ── Metrics timing ──────────────────────────────────────────────────
    const t_start_ns = std.time.nanoTimestamp();
    var t_after_read_ns: i128 = t_start_ns;
    var t_after_lex_ns: i128 = t_start_ns;
    var t_after_parse_ns: i128 = t_start_ns;
    var t_after_semantic_ns: i128 = t_start_ns;
    var t_after_cfg_ns: i128 = t_start_ns;
    var t_after_codegen_ns: i128 = t_start_ns;
    var t_after_jit_compile_ns: i128 = t_start_ns;
    var t_after_jit_link_ns: i128 = t_start_ns;
    var t_after_jit_exec_ns: i128 = t_start_ns;

    // ── Phase 1: Read source file ───────────────────────────────────────

    const source = readSourceFile(input_path, allocator) catch |err| {
        stderr.print("Error: cannot open '{s}': {s}\n", .{ input_path, @errorName(err) }) catch {};
        std.process.exit(1);
    };
    defer allocator.free(source);

    if (opts.verbose) {
        stderr.print("Read {d} bytes from {s}\n", .{ source.len, input_path }) catch {};
    }
    t_after_read_ns = std.time.nanoTimestamp();

    // ── Phase 2: Lexical analysis ───────────────────────────────────────

    var lex = Lexer.init(source, allocator);
    defer lex.deinit();

    lex.tokenize() catch |err| {
        stderr.print("Error: lexer failure: {s}\n", .{@errorName(err)}) catch {};
        std.process.exit(1);
    };

    if (lex.hasErrors()) {
        stderr.print("Lexer errors in '{s}':\n", .{input_path}) catch {};
        for (lex.errors.items) |lerr| {
            stderr.print("  {d}:{d}: {s}\n", .{ lerr.location.line, lerr.location.column, lerr.message }) catch {};
        }
        std.process.exit(1);
    }

    if (opts.verbose) {
        stderr.print("Lexer: {d} tokens\n", .{lex.tokens.items.len}) catch {};
    }
    t_after_lex_ns = std.time.nanoTimestamp();

    if (opts.show_tokens) {
        dumpTokens(lex.tokens.items, stderr);
    }

    // ── Phase 3: Parsing ────────────────────────────────────────────────

    var parser = Parser.init(lex.tokens.items, allocator);
    defer parser.deinit();

    const program = parser.parse() catch |err| {
        stderr.print("Error: parser failure: {s}\n", .{@errorName(err)}) catch {};
        if (parser.hasErrors()) {
            for (parser.errors.items) |perr| {
                stderr.print("  {d}:{d}: {s}\n", .{ perr.location.line, perr.location.column, perr.message }) catch {};
            }
        }
        std.process.exit(1);
    };

    if (parser.hasErrors()) {
        stderr.print("Parse errors in '{s}':\n", .{input_path}) catch {};
        for (parser.errors.items) |perr| {
            stderr.print("  {d}:{d}: {s}\n", .{ perr.location.line, perr.location.column, perr.message }) catch {};
        }
        std.process.exit(1);
    }

    if (opts.verbose) {
        stderr.print("Parser: {d} program lines\n", .{program.lines.len}) catch {};
    }
    t_after_parse_ns = std.time.nanoTimestamp();

    // ── Debug: AST dump ─────────────────────────────────────────────────

    if (opts.trace_ast) {
        dumpAST(&program, stderr);
        return;
    }

    // ── Phase 4: Semantic analysis ──────────────────────────────────────

    var analyzer = SemanticAnalyzer.init(allocator);
    defer analyzer.deinit();

    const sem_ok = analyzer.analyze(&program) catch |err| {
        stderr.print("Error: semantic analysis failure: {s}\n", .{@errorName(err)}) catch {};
        std.process.exit(1);
    };

    if (!sem_ok) {
        stderr.print("Semantic errors in '{s}':\n", .{input_path}) catch {};
        for (analyzer.errors.items) |serr| {
            stderr.print("  {d}:{d}: [{s}] {s}\n", .{
                serr.location.line,
                serr.location.column,
                @tagName(serr.error_type),
                serr.message,
            }) catch {};
        }
        std.process.exit(1);
    }

    // Print warnings
    for (analyzer.warnings.items) |warn| {
        stderr.print("Warning at {d}:{d}: {s}\n", .{
            warn.location.line,
            warn.location.column,
            warn.message,
        }) catch {};
    }

    if (opts.verbose) {
        stderr.print("Semantic analysis: OK ({d} warnings)\n", .{analyzer.warnings.items.len}) catch {};
    }
    t_after_semantic_ns = std.time.nanoTimestamp();

    // ── Debug: Symbol table dump ────────────────────────────────────────

    if (opts.trace_symbols) {
        dumpSymbolTable(analyzer.getSymbolTable(), stderr);
        return;
    }

    // ── Phase 4a: AST optimization ──────────────────────────────────────

    var ast_opt = ast_optimize.ASTOptimizer.init(analyzer.getSymbolTable(), allocator);
    defer ast_opt.deinit();

    if (!opts.no_optimize) {
        ast_opt.optimize(@constCast(&program)) catch |err| {
            stderr.print("Error: AST optimization failure: {s}\n", .{@errorName(err)}) catch {};
            std.process.exit(1);
        };
    }

    if (opts.verbose and ast_opt.stats.total() > 0) {
        stderr.print("AST optimizer: {d} optimizations (fold={d} prop={d} str={d}/{d} pow={d} dead={d} iif={d} alg={d} for={d} not={d} dblneg={d} strfn={d} div2mul={d} mod2and={d} deadloop={d} bool={d})\n", .{
            ast_opt.stats.total(),
            ast_opt.stats.constants_folded,
            ast_opt.stats.constants_propagated,
            ast_opt.stats.strings_folded,
            ast_opt.stats.string_identities,
            ast_opt.stats.powers_reduced,
            ast_opt.stats.dead_branches,
            ast_opt.stats.iifs_simplified,
            ast_opt.stats.algebraic_identities,
            ast_opt.stats.for_loops_specialized,
            ast_opt.stats.not_folded,
            ast_opt.stats.double_negations,
            ast_opt.stats.string_funcs_folded,
            ast_opt.stats.div_to_mul,
            ast_opt.stats.mod_to_and,
            ast_opt.stats.dead_loops,
            ast_opt.stats.bool_identities,
        }) catch {};
    }

    // ── Phase 4b: Control Flow Graph construction ───────────────────────

    var cfg_builder = CFGBuilder.init(allocator);
    defer cfg_builder.deinit();

    const program_cfg = cfg_builder.buildFromProgram(&program) catch |err| {
        stderr.print("Error: CFG construction failure: {s}\n", .{@errorName(err)}) catch {};
        std.process.exit(1);
    };

    if (opts.verbose) {
        stderr.print("CFG: {d} blocks, {d} edges, {d} loops, {d} unreachable\n", .{
            program_cfg.numBlocks(),
            program_cfg.numEdges(),
            program_cfg.loops.items.len,
            program_cfg.unreachable_count,
        }) catch {};
    }
    t_after_cfg_ns = std.time.nanoTimestamp();

    // ── Debug: CFG dump ─────────────────────────────────────────────────

    if (opts.trace_cfg) {
        program_cfg.dump(stderr);

        // Also dump sub-CFGs for any FUNCTION/SUB definitions.
        var func_it = cfg_builder.function_cfgs.iterator();
        while (func_it.next()) |entry| {
            entry.value_ptr.dump(stderr);
        }

        return;
    }

    // Report unreachable code as warnings.
    if (program_cfg.unreachable_count > 0) {
        var unreachable_blocks: std.ArrayList(u32) = .empty;
        defer unreachable_blocks.deinit(allocator);
        program_cfg.getUnreachableBlocks(&unreachable_blocks, allocator) catch {};
        for (unreachable_blocks.items) |blk_idx| {
            const blk = program_cfg.getBlockConst(blk_idx);
            if (!blk.isEmpty()) {
                stderr.print("Warning: unreachable code at {d}:{d} (block {s})\n", .{
                    blk.loc.line,
                    blk.loc.column,
                    blk.name,
                }) catch {};
            }
        }
    }

    // ── Phase 5: Code generation (CFG-driven) ───────────────────────────

    var gen = CFGCodeGenerator.init(&analyzer, program_cfg, &cfg_builder, allocator);
    defer gen.deinit();

    gen.verbose = opts.verbose;
    gen.samm_enabled = analyzer.options.samm_enabled;
    gen.for_step_directions = &ast_opt.for_step_directions;

    const il = gen.generate(&program) catch |err| {
        stderr.print("Error: code generation failure: {s}\n", .{@errorName(err)}) catch {};
        std.process.exit(1);
    };

    if (opts.verbose) {
        stderr.print("Code generation: {d} bytes of QBE IL\n", .{il.len}) catch {};
    }
    t_after_codegen_ns = std.time.nanoTimestamp();

    if (opts.show_il) {
        stderr.print("\n=== Generated QBE IL ===\n{s}\n=== End QBE IL ===\n\n", .{il}) catch {};
    }

    // ── Phase 6: Output ─────────────────────────────────────────────────

    switch (opts.mode) {
        .jit => {
            // ── JIT Mode: QBE IL → ARM64 machine code → execute in-process ──

            if (opts.verbose or opts.jit_verbose) {
                stderr.print("JIT: compiling QBE IL ({d} bytes)...\n", .{il.len}) catch {};
            }

            // Step 1: QBE IL → JitModule (compile + encode)
            const jit_result = qbe.compileILJit(allocator, il, null) catch |err| {
                stderr.print("Error: JIT compilation failed: {s}\n", .{@errorName(err)}) catch {};
                std.process.exit(1);
            };
            t_after_jit_compile_ns = std.time.nanoTimestamp();

            if (opts.jit_verbose) {
                const pr = jit_result.pipelineReport();
                stderr.print("\n{s}\n", .{pr}) catch {};
            }

            if (opts.verbose or opts.jit_verbose) {
                stderr.print("JIT: {d} instructions, {d} functions, {d} data items\n", .{
                    jit_result.inst_count,
                    jit_result.func_count,
                    jit_result.data_count,
                }) catch {};
                stderr.print("JIT: code={d} bytes, data={d} bytes\n", .{
                    jit_result.module.code_len,
                    jit_result.module.data_len,
                }) catch {};
            }

            // Step 2: Import JIT runtime and create execution session
            const jit_runtime = @import("jit_runtime.zig");
            const jit_stubs = @import("jit_stubs.zig");

            // Build RuntimeContext — the real runtime is linked into fbc,
            // so all symbols are resolved via dlsym(RTLD_DEFAULT, ...).
            const ctx = jit_stubs.buildJitRuntimeContext();

            // Create execution session from the compiled module.
            // The runtime is linked into fbc, so the linker's dlsym
            // fallback resolves every external call to the real
            // implementation (print, strings, SAMM, arrays, etc.).
            var session = jit_runtime.JitSession.compileFromModule(
                allocator,
                jit_result.module,
                &ctx,
                null, // insts — not needed, module has load_addr_relocs
                0, // ninst
                jit_result.inst_count,
                jit_result.func_count,
                jit_result.data_count,
                jit_result.pipelineReport(),
            ) catch |err| {
                stderr.print("Error: JIT session creation failed: {s}\n", .{@errorName(err)}) catch {};
                std.process.exit(1);
            };
            defer session.deinit();
            t_after_jit_link_ns = std.time.nanoTimestamp();

            if (opts.jit_verbose) {
                session.dumpFullReport(stderr) catch {};
            }

            if (!session.finalized) {
                stderr.print("Error: JIT session failed to finalize (linking errors)\n", .{}) catch {};
                // Dump link diagnostics
                session.link_result.dumpReport(stderr) catch {};
                std.process.exit(1);
            }

            if (opts.verbose or opts.jit_verbose) {
                stderr.print("JIT: executing...\n", .{}) catch {};
            }

            // Step 3: Execute
            const exec_result = if (opts.run_after_compile and opts.program_args.len > 0) blk: {
                // --run mode: pass program arguments to main(argc, argv)
                break :blk session.executeWithArgs(opts.program_args);
            } else blk: {
                break :blk session.execute();
            };
            t_after_jit_exec_ns = std.time.nanoTimestamp();

            if (opts.jit_verbose) {
                exec_result.dump(stderr) catch {};
            }

            // ── Metrics report ──────────────────────────────────────
            if (opts.metrics) {
                var samm_stats: SAMMStats = undefined;
                samm_get_stats(&samm_stats);

                const m_read = phaseMs(t_start_ns, t_after_read_ns);
                const m_lex = phaseMs(t_after_read_ns, t_after_lex_ns);
                const m_parse = phaseMs(t_after_lex_ns, t_after_parse_ns);
                const m_sem = phaseMs(t_after_parse_ns, t_after_semantic_ns);
                const m_cfg = phaseMs(t_after_semantic_ns, t_after_cfg_ns);
                const m_cg = phaseMs(t_after_cfg_ns, t_after_codegen_ns);
                const m_jc = phaseMs(t_after_codegen_ns, t_after_jit_compile_ns);
                const m_jl = phaseMs(t_after_jit_compile_ns, t_after_jit_link_ns);
                const m_je = phaseMs(t_after_jit_link_ns, t_after_jit_exec_ns);
                const m_total = phaseMs(t_start_ns, t_after_jit_exec_ns);

                printMetrics(stderr, samm_stats, .{
                    .read_ms = m_read,
                    .lex_ms = m_lex,
                    .parse_ms = m_parse,
                    .semantic_ms = m_sem,
                    .cfg_ms = m_cfg,
                    .codegen_ms = m_cg,
                    .jit_compile_ms = m_jc,
                    .jit_link_ms = m_jl,
                    .jit_exec_ms = m_je,
                    .total_ms = m_total,
                });
            }

            if (exec_result.completed) {
                if (opts.verbose or opts.jit_verbose) {
                    stderr.print("JIT: exit code = {d}\n", .{exec_result.exit_code}) catch {};
                }
                if (exec_result.exit_code != 0) {
                    std.process.exit(@intCast(@as(u32, @bitCast(exec_result.exit_code)) & 0xFF));
                }
            } else {
                stderr.print("Error: JIT execution did not complete", .{}) catch {};
                if (exec_result.signal != 0) {
                    stderr.print(" (signal {d})", .{exec_result.signal}) catch {};
                }
                stderr.print("\n", .{}) catch {};
                std.process.exit(1);
            }
        },

        .il_only => {
            // Write IL to stdout or file
            if (opts.output_path) |out_path| {
                const out_file = std.fs.cwd().createFile(out_path, .{}) catch |err| {
                    stderr.print("Error: cannot create output file '{s}': {s}\n", .{ out_path, @errorName(err) }) catch {};
                    std.process.exit(1);
                };
                defer out_file.close();
                out_file.writeAll(il) catch |err| {
                    stderr.print("Error: cannot write output file: {s}\n", .{@errorName(err)}) catch {};
                    std.process.exit(1);
                };
                if (opts.verbose) {
                    stderr.print("Wrote QBE IL to {s}\n", .{out_path}) catch {};
                }
            } else {
                stdout.writeAll(il) catch {};
            }
        },

        .asm_only => {
            // Compile IL → assembly in-process via embedded QBE
            const output_path = opts.output_path orelse (deriveOutputPath(input_path, .asm_only, allocator) catch {
                stderr.print("Error: cannot derive output path\n", .{}) catch {};
                std.process.exit(1);
            });

            if (opts.verbose) {
                stderr.print("Compiling QBE IL to assembly (in-process, target={s})...\n", .{qbe.defaultTarget()}) catch {};
            }

            qbe.compileIL(il, output_path, null) catch |err| {
                stderr.print("Error: QBE compilation failed: {s}\n", .{@errorName(err)}) catch {};
                std.process.exit(1);
            };

            if (opts.verbose) {
                stderr.print("Wrote assembly to {s}\n", .{output_path}) catch {};
            }
        },

        .executable => {
            // Full compilation: IL → assembly (in-process QBE) → link → executable
            const output_path = opts.output_path orelse (deriveOutputPath(input_path, .executable, allocator) catch {
                stderr.print("Error: cannot derive output path\n", .{}) catch {};
                std.process.exit(1);
            });

            const asm_tmp_path = std.fmt.allocPrint(allocator, "/tmp/fbc_{d}.s", .{std.time.milliTimestamp()}) catch {
                stderr.print("Error: out of memory\n", .{}) catch {};
                std.process.exit(1);
            };
            defer allocator.free(asm_tmp_path);

            // Step 1: QBE IL → assembly (in-process)
            if (opts.verbose) {
                stderr.print("Compiling QBE IL to assembly (in-process, target={s})...\n", .{qbe.defaultTarget()}) catch {};
            }
            qbe.compileIL(il, asm_tmp_path, null) catch |err| {
                stderr.print("Error: QBE compilation failed: {s}\n", .{@errorName(err)}) catch {};
                std.process.exit(1);
            };
            defer std.fs.cwd().deleteFile(asm_tmp_path) catch {};

            // Step 2: Locate the runtime directory
            const rt_dir = findRuntimeDir(opts.runtime_dir, allocator);

            if (opts.verbose) {
                if (rt_dir) |d| {
                    stderr.print("Runtime directory: {s}\n", .{d}) catch {};
                } else {
                    stderr.print("Warning: runtime directory not found — linking without runtime\n", .{}) catch {};
                }
            }

            // Step 3: Assemble + link → executable
            if (opts.verbose) {
                stderr.print("Linking executable...\n", .{}) catch {};
            }

            // Build link command:
            //   cc -O1 -o <output> <asm_file> <runtime .c files...> -I<runtime_dir> -lm
            var link_args: std.ArrayList([]const u8) = .empty;
            defer link_args.deinit(allocator);

            try link_args.append(allocator, opts.cc_path);
            try link_args.append(allocator, "-O1");
            try link_args.append(allocator, "-o");
            try link_args.append(allocator, output_path);
            try link_args.append(allocator, asm_tmp_path);

            // Add all runtime C source files
            var rt_file_count: usize = 0;
            if (rt_dir) |dir| {
                // First check for a pre-built static library
                const lib_path = std.fmt.allocPrint(allocator, "{s}/libfbruntime.a", .{dir}) catch {
                    stderr.print("Error: out of memory\n", .{}) catch {};
                    std.process.exit(1);
                };

                if (fileExists(lib_path)) {
                    // Use pre-built archive
                    try link_args.append(allocator, lib_path);
                    rt_file_count = 1;
                    if (opts.verbose) {
                        stderr.print("  Using pre-built runtime: {s}\n", .{lib_path}) catch {};
                    }
                } else {
                    allocator.free(lib_path);

                    // Compile runtime .c files directly
                    const rt_files = listCFiles(dir, allocator) catch |err| {
                        stderr.print("Error: cannot list runtime sources in '{s}': {s}\n", .{ dir, @errorName(err) }) catch {};
                        std.process.exit(1);
                    };

                    for (rt_files) |cf| {
                        try link_args.append(allocator, cf);
                    }
                    rt_file_count = rt_files.len;

                    // Add -I<runtime_dir> so runtime headers can find each other
                    const inc_flag = std.fmt.allocPrint(allocator, "-I{s}", .{dir}) catch {
                        stderr.print("Error: out of memory\n", .{}) catch {};
                        std.process.exit(1);
                    };
                    try link_args.append(allocator, inc_flag);
                }

                // Check for Zig-compiled SAMM pool library in zig-out/lib
                // (relative to executable directory, not runtime directory)
                const exe_path = std.fs.selfExePathAlloc(allocator) catch {
                    stderr.print("Error: cannot determine exe path\n", .{}) catch {};
                    std.process.exit(1);
                };
                defer allocator.free(exe_path);

                if (std.fs.path.dirname(exe_path)) |exe_dir| {
                    // All Zig runtime libraries (SAMM + runtime ports)
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
                        "binary_io",
                        "array_ops",
                        "marshalling",
                        "messaging",
                        "terminal_io",
                    };
                    for (zig_runtime_libs) |lib_name| {
                        const zig_lib_path = std.fmt.allocPrint(allocator, "{s}/../lib/lib{s}.a", .{ exe_dir, lib_name }) catch {
                            stderr.print("Error: out of memory\n", .{}) catch {};
                            std.process.exit(1);
                        };
                        if (fileExists(zig_lib_path)) {
                            try link_args.append(allocator, zig_lib_path);
                            if (opts.verbose) {
                                stderr.print("  Using Zig runtime lib: {s}\n", .{zig_lib_path}) catch {};
                            }
                        } else {
                            allocator.free(zig_lib_path);
                        }
                    }
                }
            }

            // Always link libm (math functions used by runtime)
            try link_args.append(allocator, "-lm");

            if (rt_file_count == 0) {
                stderr.print("Warning: no runtime files found — executable may have unresolved symbols\n", .{}) catch {};
            }

            if (opts.verbose) {
                stderr.print("  Linking with {d} runtime source(s)\n", .{rt_file_count}) catch {};
            }

            runExternalCommand(link_args.items, allocator, opts.verbose, stderr) catch |err| {
                stderr.print("Error: linking failed: {s}\n", .{@errorName(err)}) catch {};
                stderr.print("Make sure '{s}' is installed and in your PATH.\n", .{opts.cc_path}) catch {};
                if (rt_dir == null) {
                    stderr.print("Hint: specify --runtime-dir <path> pointing to the FasterBASIC runtime/ directory.\n", .{}) catch {};
                }
                std.process.exit(1);
            };

            stderr.print("Compiled: {s} → {s}\n", .{ input_path, output_path }) catch {};

            // Optionally run the compiled program
            if (opts.run_after_compile) {
                if (opts.verbose) {
                    stderr.print("Running ./{s}...\n", .{output_path}) catch {};
                }
                stderr.print("\n", .{}) catch {};

                const run_path = std.fmt.allocPrint(allocator, "./{s}", .{output_path}) catch {
                    stderr.print("Error: out of memory\n", .{}) catch {};
                    std.process.exit(1);
                };
                defer allocator.free(run_path);

                var run_child = std.process.Child.init(&.{run_path}, allocator);
                run_child.stderr_behavior = .Inherit;
                run_child.stdout_behavior = .Inherit;
                run_child.stdin_behavior = .Inherit;
                try run_child.spawn();
                const run_result = try run_child.wait();

                switch (run_result) {
                    .Exited => |code| {
                        if (code != 0) {
                            std.process.exit(code);
                        }
                    },
                    else => {
                        std.process.exit(1);
                    },
                }
            }
        },
    }
}

// ─── Tests ──────────────────────────────────────────────────────────────────

test "derive output path - executable" {
    const allocator = std.testing.allocator;
    const path = try deriveOutputPath("hello.bas", .executable, allocator);
    defer allocator.free(path);
    try std.testing.expectEqualStrings("hello", path);
}

test "derive output path - il" {
    const allocator = std.testing.allocator;
    const path = try deriveOutputPath("hello.bas", .il_only, allocator);
    defer allocator.free(path);
    try std.testing.expectEqualStrings("hello.qbe", path);
}

test "derive output path - asm" {
    const allocator = std.testing.allocator;
    const path = try deriveOutputPath("hello.bas", .asm_only, allocator);
    defer allocator.free(path);
    try std.testing.expectEqualStrings("hello.s", path);
}

test "derive output path - with directory" {
    const allocator = std.testing.allocator;
    const path = try deriveOutputPath("path/to/program.bas", .executable, allocator);
    defer allocator.free(path);
    try std.testing.expectEqualStrings("program", path);
}

test "derive output path - no extension" {
    const allocator = std.testing.allocator;
    const path = try deriveOutputPath("program", .executable, allocator);
    defer allocator.free(path);
    try std.testing.expectEqualStrings("program", path);
}

test "isBasicFile" {
    try std.testing.expect(isBasicFile("hello.bas"));
    try std.testing.expect(isBasicFile("path/to/hello.bas"));
    try std.testing.expect(isBasicFile("HELLO.BAS"));
    try std.testing.expect(!isBasicFile("hello.txt"));
    try std.testing.expect(!isBasicFile("bas"));
    try std.testing.expect(!isBasicFile("ab"));
}

test "full pipeline - hello world" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "PRINT \"Hello, World!\"\nEND\n";

    // Lex
    var lex = Lexer.init(source, allocator);
    try lex.tokenize();
    try std.testing.expect(!lex.hasErrors());

    // Parse
    var parser = Parser.init(lex.tokens.items, allocator);
    const program = try parser.parse();
    try std.testing.expect(!parser.hasErrors());
    try std.testing.expect(program.lines.len >= 2);

    // Semantic
    var analyzer = SemanticAnalyzer.init(allocator);
    const sem_ok = try analyzer.analyze(&program);
    try std.testing.expect(sem_ok);

    // CFG
    var cfg_builder = CFGBuilder.init(allocator);
    defer cfg_builder.deinit();
    const program_cfg = try cfg_builder.buildFromProgram(&program);

    // Codegen
    var gen = CFGCodeGenerator.init(&analyzer, program_cfg, &cfg_builder, allocator);
    defer gen.deinit();
    const il = try gen.generate(&program);
    try std.testing.expect(il.len > 0);

    // Verify IL contains expected elements
    try std.testing.expect(std.mem.indexOf(u8, il, "export function") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, "print_") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, "ret") != null);
}

test "full pipeline - arithmetic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source = "DIM x AS INTEGER\nx = 1 + 2 * 3\nPRINT x\nEND\n";

    var lex = Lexer.init(source, allocator);
    try lex.tokenize();
    try std.testing.expect(!lex.hasErrors());

    var parser = Parser.init(lex.tokens.items, allocator);
    const program = try parser.parse();
    try std.testing.expect(!parser.hasErrors());

    var analyzer = SemanticAnalyzer.init(allocator);
    const sem_ok = try analyzer.analyze(&program);
    try std.testing.expect(sem_ok);

    // CFG
    var cfg_builder = CFGBuilder.init(allocator);
    defer cfg_builder.deinit();
    const program_cfg = try cfg_builder.buildFromProgram(&program);

    var gen = CFGCodeGenerator.init(&analyzer, program_cfg, &cfg_builder, allocator);
    defer gen.deinit();
    const il = try gen.generate(&program);
    try std.testing.expect(il.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, il, "add") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, "mul") != null);
}

test "full pipeline - for loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        \\FOR i = 1 TO 10
        \\  PRINT i
        \\NEXT i
        \\END
    ;

    var lex = Lexer.init(source, allocator);
    try lex.tokenize();
    try std.testing.expect(!lex.hasErrors());

    var parser = Parser.init(lex.tokens.items, allocator);
    const program = try parser.parse();
    try std.testing.expect(!parser.hasErrors());

    var analyzer = SemanticAnalyzer.init(allocator);
    const sem_ok = try analyzer.analyze(&program);
    try std.testing.expect(sem_ok);

    // CFG
    var cfg_builder = CFGBuilder.init(allocator);
    defer cfg_builder.deinit();
    const program_cfg = try cfg_builder.buildFromProgram(&program);

    var gen = CFGCodeGenerator.init(&analyzer, program_cfg, &cfg_builder, allocator);
    defer gen.deinit();
    const il = try gen.generate(&program);
    try std.testing.expect(il.len > 0);
    // FOR loop should produce branch instructions (CFG block names vary)
    try std.testing.expect(std.mem.indexOf(u8, il, "jnz") != null);
}

test "full pipeline - function definition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        \\FUNCTION Add(a AS INTEGER, b AS INTEGER) AS INTEGER
        \\  RETURN a + b
        \\END FUNCTION
        \\PRINT Add(3, 4)
        \\END
    ;

    var lex = Lexer.init(source, allocator);
    try lex.tokenize();
    try std.testing.expect(!lex.hasErrors());

    var parser = Parser.init(lex.tokens.items, allocator);
    const program = try parser.parse();
    try std.testing.expect(!parser.hasErrors());

    var analyzer = SemanticAnalyzer.init(allocator);
    const sem_ok = try analyzer.analyze(&program);
    try std.testing.expect(sem_ok);

    // CFG
    var cfg_builder = CFGBuilder.init(allocator);
    defer cfg_builder.deinit();
    const program_cfg = try cfg_builder.buildFromProgram(&program);

    var gen = CFGCodeGenerator.init(&analyzer, program_cfg, &cfg_builder, allocator);
    defer gen.deinit();
    const il = try gen.generate(&program);
    try std.testing.expect(il.len > 0);
    // Should contain the function definition
    try std.testing.expect(std.mem.indexOf(u8, il, "func_ADD") != null or std.mem.indexOf(u8, il, "sub_ADD") != null);
}

test "full pipeline - type declaration" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        \\TYPE Point
        \\  x AS DOUBLE
        \\  y AS DOUBLE
        \\END TYPE
        \\PRINT CREATE Point(1.0, 2.0)
        \\END
    ;

    var lex = Lexer.init(source, allocator);
    try lex.tokenize();
    try std.testing.expect(!lex.hasErrors());

    var parser = Parser.init(lex.tokens.items, allocator);
    const program = try parser.parse();
    try std.testing.expect(!parser.hasErrors());

    var analyzer = SemanticAnalyzer.init(allocator);
    const sem_ok = try analyzer.analyze(&program);
    try std.testing.expect(sem_ok);

    // CFG
    var cfg_builder = CFGBuilder.init(allocator);
    defer cfg_builder.deinit();
    const program_cfg = try cfg_builder.buildFromProgram(&program);

    var gen = CFGCodeGenerator.init(&analyzer, program_cfg, &cfg_builder, allocator);
    defer gen.deinit();
    const il = try gen.generate(&program);
    try std.testing.expect(il.len > 0);
}

test "full pipeline - while loop" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        \\DIM x AS INTEGER
        \\x = 10
        \\WHILE x > 0
        \\  PRINT x
        \\  DEC x
        \\WEND
        \\END
    ;

    var lex = Lexer.init(source, allocator);
    try lex.tokenize();
    try std.testing.expect(!lex.hasErrors());

    var parser = Parser.init(lex.tokens.items, allocator);
    const program = try parser.parse();
    try std.testing.expect(!parser.hasErrors());

    var analyzer = SemanticAnalyzer.init(allocator);
    const sem_ok = try analyzer.analyze(&program);
    try std.testing.expect(sem_ok);

    // CFG
    var cfg_builder = CFGBuilder.init(allocator);
    defer cfg_builder.deinit();
    const program_cfg = try cfg_builder.buildFromProgram(&program);

    var gen = CFGCodeGenerator.init(&analyzer, program_cfg, &cfg_builder, allocator);
    defer gen.deinit();
    const il = try gen.generate(&program);
    try std.testing.expect(il.len > 0);
    // WHILE loop should produce conditional branches
    try std.testing.expect(std.mem.indexOf(u8, il, "jnz") != null);
}

test "full pipeline - if statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        \\DIM x AS INTEGER
        \\x = 42
        \\IF x > 10 THEN
        \\  PRINT "big"
        \\ELSE
        \\  PRINT "small"
        \\ENDIF
        \\END
    ;

    var lex = Lexer.init(source, allocator);
    try lex.tokenize();
    try std.testing.expect(!lex.hasErrors());

    var parser = Parser.init(lex.tokens.items, allocator);
    const program = try parser.parse();
    try std.testing.expect(!parser.hasErrors());

    var analyzer = SemanticAnalyzer.init(allocator);
    const sem_ok = try analyzer.analyze(&program);
    try std.testing.expect(sem_ok);

    // CFG
    var cfg_builder = CFGBuilder.init(allocator);
    defer cfg_builder.deinit();
    const program_cfg = try cfg_builder.buildFromProgram(&program);

    var gen = CFGCodeGenerator.init(&analyzer, program_cfg, &cfg_builder, allocator);
    defer gen.deinit();
    const il = try gen.generate(&program);
    try std.testing.expect(il.len > 0);
    // IF/ELSE should produce conditional branches
    try std.testing.expect(std.mem.indexOf(u8, il, "jnz") != null);
}

test "full pipeline - select case" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const source =
        \\DIM x AS INTEGER
        \\x = 2
        \\SELECT CASE x
        \\CASE 1
        \\  PRINT "one"
        \\CASE 2
        \\  PRINT "two"
        \\CASE ELSE
        \\  PRINT "other"
        \\ENDCASE
        \\END
    ;

    var lex = Lexer.init(source, allocator);
    try lex.tokenize();
    try std.testing.expect(!lex.hasErrors());

    var parser = Parser.init(lex.tokens.items, allocator);
    const program = try parser.parse();
    try std.testing.expect(!parser.hasErrors());

    var analyzer = SemanticAnalyzer.init(allocator);
    const sem_ok = try analyzer.analyze(&program);
    try std.testing.expect(sem_ok);

    // CFG
    var cfg_builder = CFGBuilder.init(allocator);
    defer cfg_builder.deinit();
    const program_cfg = try cfg_builder.buildFromProgram(&program);

    var gen = CFGCodeGenerator.init(&analyzer, program_cfg, &cfg_builder, allocator);
    defer gen.deinit();
    const il = try gen.generate(&program);
    try std.testing.expect(il.len > 0);
    // SELECT CASE should produce conditional branches
    try std.testing.expect(std.mem.indexOf(u8, il, "jnz") != null or std.mem.indexOf(u8, il, "jmp") != null);
}
