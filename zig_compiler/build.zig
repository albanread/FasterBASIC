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
        // JIT collector: walks post-regalloc Fn* → JitInst[]
        "jit_collect.c",
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

    // ── Capstone Disassembler C source files ───────────────────────────
    //
    // We compile only the core engine + AArch64 architecture from the
    // capstone/ directory (sibling to zig_compiler/).  This gives us
    // ARM64 disassembly for the JIT verbose report without pulling in
    // every architecture Capstone supports.

    const capstone_core_sources = &[_][]const u8{
        "cs.c",
        "MCInst.c",
        "MCInstPrinter.c",
        "MCInstrDesc.c",
        "MCRegisterInfo.c",
        "Mapping.c",
        "SStream.c",
        "utils.c",
    };

    const capstone_aarch64_sources = &[_][]const u8{
        "arch/AArch64/AArch64BaseInfo.c",
        "arch/AArch64/AArch64Disassembler.c",
        "arch/AArch64/AArch64DisassemblerExtension.c",
        "arch/AArch64/AArch64InstPrinter.c",
        "arch/AArch64/AArch64Mapping.c",
        "arch/AArch64/AArch64Module.c",
    };

    const capstone_c_flags = &[_][]const u8{
        "-std=c99",
        "-DCAPSTONE_HAS_AARCH64",
        "-DCAPSTONE_USE_SYS_DYN_MEM",
        "-Wall",
        "-Wno-unused-parameter",
        "-Wno-sign-compare",
        "-Wno-missing-field-initializers",
        "-Wno-unused-function",
        "-Wno-unused-variable",
        "-Wno-implicit-fallthrough",
    };

    // ── Main compiler executable ───────────────────────────────────────

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Add QBE include path so qbe.zig's C imports and the C sources
    // can find all.h, config.h, ops.h, qbe_bridge.h, jit_collect.h
    exe_mod.addIncludePath(b.path("qbe"));

    // Add runtime include path so C headers (basic_runtime.h,
    // array_descriptor.h, etc.) are found when compiling runtime C files.
    exe_mod.addIncludePath(b.path("runtime"));

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

    // Add Capstone include paths (public headers + internal headers)
    exe_mod.addIncludePath(b.path("../capstone/include"));
    exe_mod.addIncludePath(b.path("../capstone"));

    // Compile Capstone C sources into the module
    exe_mod.addCSourceFiles(.{
        .root = b.path("../capstone"),
        .files = capstone_core_sources,
        .flags = capstone_c_flags,
    });
    exe_mod.addCSourceFiles(.{
        .root = b.path("../capstone"),
        .files = capstone_aarch64_sources,
        .flags = capstone_c_flags,
    });

    // ── Runtime C sources compiled directly into fbc ───────────────────
    //
    // basic_runtime.c and worker_runtime.c are the remaining C files in
    // the runtime.  They are compiled into the fbc binary so that JIT-
    // executed code can call the real runtime functions in-process via
    // dlsym(RTLD_DEFAULT, ...).

    const runtime_c_flags = &[_][]const u8{
        "-std=c99",
        "-Wall",
        "-Wno-unused-parameter",
        "-Wno-missing-field-initializers",
    };

    exe_mod.addCSourceFiles(.{
        .root = b.path("runtime"),
        .files = &[_][]const u8{
            "basic_runtime.c",
            "worker_runtime.c",
            "hashmap_runtime.c",
            "runtime_shims.c",
        },
        .flags = runtime_c_flags,
    });

    const exe = b.addExecutable(.{
        .name = "fbc",
        .root_module = exe_mod,
    });

    // Export all symbols so dlsym(RTLD_DEFAULT, ...) can find runtime
    // functions linked into the binary.  Without this, the JIT linker's
    // dlsym fallback would fail to resolve _basic_print_int etc.
    exe.rdynamic = true;

    b.installArtifact(exe);

    // ── Zig Runtime Libraries ─────────────────────────────────────────
    //
    // Each runtime Zig module is compiled as a static library.  They are
    // both installed to zig-out/lib/ (for the AOT linker path) AND linked
    // into the fbc binary itself (so JIT-executed code can reach the real
    // runtime functions via dlsym).

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
        const src_path = b.fmt("runtime/{s}.zig", .{lib_name});
        const rt_mod = b.createModule(.{
            .root_source_file = b.path(src_path),
            .target = target,
            .optimize = .ReleaseFast,
            .link_libc = true,
        });
        // Runtime Zig files #include C headers from the runtime/ directory
        rt_mod.addIncludePath(b.path("runtime"));

        const rt_lib = b.addLibrary(.{
            .name = lib_name,
            .root_module = rt_mod,
        });

        // Install to zig-out/lib/ for AOT linking (cc links against these)
        b.installArtifact(rt_lib);

        // Link into fbc binary so JIT can find symbols via dlsym
        exe.linkLibrary(rt_lib);
    }

    // ── JIT Encoder standalone test ────────────────────────────────────
    //
    // Runs the jit_encode.zig + arm64_encoder.zig test suites.
    // These are pure Zig tests with no C dependencies.

    const jit_test_mod = b.createModule(.{
        .root_source_file = b.path("src/jit_encode.zig"),
        .target = target,
        .optimize = optimize,
    });
    const jit_tests = b.addTest(.{
        .root_module = jit_test_mod,
    });
    const run_jit_tests = b.addRunArtifact(jit_tests);

    const jit_test_step = b.step("test-jit", "Run JIT encoder unit tests");
    jit_test_step.dependOn(&run_jit_tests.step);

    // ── JIT Memory manager test ────────────────────────────────────────
    //
    // Runs the jit_memory.zig tests: W^X allocation, trampoline stubs,
    // icache invalidation, and platform-specific memory management.
    // Pure Zig tests with libc dependency (mmap, pthread, dlsym).

    const jit_memory_test_mod = b.createModule(.{
        .root_source_file = b.path("src/jit_memory.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const jit_memory_tests = b.addTest(.{
        .root_module = jit_memory_test_mod,
    });
    const run_jit_memory_tests = b.addRunArtifact(jit_memory_tests);

    jit_test_step.dependOn(&run_jit_memory_tests.step);

    // ── JIT Linker test ────────────────────────────────────────────────
    //
    // Runs the jit_linker.zig tests: data relocations, trampoline island
    // generation, external symbol resolution (dlsym), and BL patching.
    // Depends on jit_encode.zig and jit_memory.zig (pure Zig imports).

    const jit_linker_test_mod = b.createModule(.{
        .root_source_file = b.path("src/jit_linker.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const jit_linker_tests = b.addTest(.{
        .root_module = jit_linker_test_mod,
    });
    const run_jit_linker_tests = b.addRunArtifact(jit_linker_tests);

    jit_test_step.dependOn(&run_jit_linker_tests.step);

    // ── JIT Runtime test ───────────────────────────────────────────────
    //
    // Runs the jit_runtime.zig tests: execution harness, RuntimeContext,
    // signal handling, and JitExecResult formatting.
    // Depends on jit_encode.zig, jit_memory.zig, jit_linker.zig.

    const jit_runtime_test_mod = b.createModule(.{
        .root_source_file = b.path("src/jit_runtime.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const jit_runtime_tests = b.addTest(.{
        .root_module = jit_runtime_test_mod,
    });
    const run_jit_runtime_tests = b.addRunArtifact(jit_runtime_tests);

    jit_test_step.dependOn(&run_jit_runtime_tests.step);

    // ── JIT Capstone disassembler test ─────────────────────────────────
    //
    // Runs the jit_capstone.zig tests: Capstone init/deinit, instruction
    // disassembly, buffer disassembly, classification helpers.
    // Requires Capstone C sources linked in.

    const jit_capstone_test_mod = b.createModule(.{
        .root_source_file = b.path("src/jit_capstone.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // Capstone needs its include paths
    jit_capstone_test_mod.addIncludePath(b.path("../capstone/include"));
    jit_capstone_test_mod.addIncludePath(b.path("../capstone"));
    // Compile Capstone C sources into the test module
    jit_capstone_test_mod.addCSourceFiles(.{
        .root = b.path("../capstone"),
        .files = capstone_core_sources,
        .flags = capstone_c_flags,
    });
    jit_capstone_test_mod.addCSourceFiles(.{
        .root = b.path("../capstone"),
        .files = capstone_aarch64_sources,
        .flags = capstone_c_flags,
    });
    const jit_capstone_tests = b.addTest(.{
        .root_module = jit_capstone_test_mod,
    });
    const run_jit_capstone_tests = b.addRunArtifact(jit_capstone_tests);

    jit_test_step.dependOn(&run_jit_capstone_tests.step);

    const capstone_test_step = b.step("test-capstone", "Run Capstone disassembler unit tests");
    capstone_test_step.dependOn(&run_jit_capstone_tests.step);

    // Also add to the main test step
    // (added below after test_step is defined)

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

    // Include JIT encoder + memory + linker + runtime + capstone tests in the main test suite
    test_step.dependOn(&run_jit_tests.step);
    test_step.dependOn(&run_jit_memory_tests.step);
    test_step.dependOn(&run_jit_linker_tests.step);
    test_step.dependOn(&run_jit_runtime_tests.step);
    test_step.dependOn(&run_jit_capstone_tests.step);

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
        .{ .root_source_file = b.path("src/ast_optimize.zig"), .needs_qbe = false },
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
            // Provide basic_exit and other runtime stubs that QBE C code
            // references but that aren't available in test binaries.
            mod.addCSourceFiles(.{
                .root = b.path("qbe"),
                .files = &.{"qbe_test_stubs.c"},
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

            // Capstone include paths + sources (needed transitively by
            // jit_encode.zig → jit_capstone.zig → @cImport)
            mod.addIncludePath(b.path("../capstone/include"));
            mod.addIncludePath(b.path("../capstone"));
            mod.addCSourceFiles(.{
                .root = b.path("../capstone"),
                .files = capstone_core_sources,
                .flags = capstone_c_flags,
            });
            mod.addCSourceFiles(.{
                .root = b.path("../capstone"),
                .files = capstone_aarch64_sources,
                .flags = capstone_c_flags,
            });
        }

        const unit_tests = b.addTest(.{
            .root_module = mod,
        });
        const run_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_tests.step);
    }
}
