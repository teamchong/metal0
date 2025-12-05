const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Shared modules - define ONCE, use everywhere
    const hashmap_helper = b.addModule("hashmap_helper", .{
        .root_source_file = b.path("src/utils/hashmap_helper.zig"),
    });
    const allocator_helper = b.addModule("allocator_helper", .{
        .root_source_file = b.path("src/utils/allocator_helper.zig"),
    });
    const runtime = b.createModule(.{
        .root_source_file = b.path("packages/runtime/src/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime.addIncludePath(b.path("vendor/libdeflate"));
    runtime.addCSourceFiles(.{
        .files = &.{
            "vendor/libdeflate/lib/deflate_compress.c",
            "vendor/libdeflate/lib/deflate_decompress.c",
            "vendor/libdeflate/lib/utils.c",
            "vendor/libdeflate/lib/gzip_compress.c",
            "vendor/libdeflate/lib/gzip_decompress.c",
            "vendor/libdeflate/lib/zlib_compress.c",
            "vendor/libdeflate/lib/zlib_decompress.c",
            "vendor/libdeflate/lib/adler32.c",
            "vendor/libdeflate/lib/crc32.c",
            "vendor/libdeflate/lib/arm/cpu_features.c",
            "vendor/libdeflate/lib/x86/cpu_features.c",
        },
        .flags = &[_][]const u8{ "-std=c99", "-O3" },
    });
    const collections = b.addModule("collections", .{
        .root_source_file = b.path("packages/collections/collections.zig"),
    });
    const fnv_hash = b.addModule("fnv_hash", .{
        .root_source_file = b.path("src/utils/fnv_hash.zig"),
    });
    const zig_keywords = b.addModule("zig_keywords", .{
        .root_source_file = b.path("src/utils/zig_keywords.zig"),
    });
    const ast = b.addModule("ast", .{
        .root_source_file = b.path("src/ast.zig"),
    });

    const gzip_module = b.addModule("gzip", .{
        .root_source_file = b.path("packages/runtime/src/gzip/gzip.zig"),
    });
    gzip_module.addIncludePath(b.path("vendor/libdeflate"));

    // SIMD dispatch for JSON parsing (shared between runtime and shared/json)
    // MUST be defined BEFORE json_mod since json_mod depends on it
    const json_simd = b.addModule("json_simd", .{
        .root_source_file = b.path("packages/shared/json/simd/dispatch.zig"),
    });

    // Shared JSON library with SIMD acceleration
    const json_mod = b.addModule("json", .{
        .root_source_file = b.path("packages/shared/json/json.zig"),
    });
    // json module imports simd via module dependency, not direct path
    json_mod.addImport("json_simd", json_simd);

    // HTTP/2 module with TLS 1.3 (AES-NI accelerated) and gzip decompression
    const h2_mod = b.addModule("h2", .{
        .root_source_file = b.path("packages/shared/http/h2/h2.zig"),
    });
    h2_mod.addImport("gzip", gzip_module);

    // Regex module for re stdlib
    const regex_mod = b.addModule("regex", .{
        .root_source_file = b.path("packages/regex/src/pyregex/regex.zig"),
    });

    // BigInt module for arbitrary precision integers
    const bigint_mod = b.addModule("bigint", .{
        .root_source_file = b.path("packages/bigint/src/bigint.zig"),
    });

    // Data structures module (pool, bounded_array, bump_allocator)
    const ds_mod = b.addModule("ds", .{
        .root_source_file = b.path("packages/ds/src/ds.zig"),
    });

    // Glob pattern matching module
    const glob_mod = b.addModule("glob", .{
        .root_source_file = b.path("packages/glob/src/glob.zig"),
    });
    glob_mod.addImport("ds", ds_mod);

    // Tokenizer module for BPE tokenization (GPT-4, etc.)
    const tokenizer_mod = b.addModule("tokenizer", .{
        .root_source_file = b.path("packages/tokenizer/src/tokenizer.zig"),
    });
    tokenizer_mod.addImport("json", json_mod);

    // Package manager module (PEP 440, 508, requirements.txt, METADATA parsing)
    const pkg_mod = b.addModule("pkg", .{
        .root_source_file = b.path("packages/pkg/src/pkg.zig"),
    });
    pkg_mod.addImport("json", json_mod);
    pkg_mod.addImport("h2", h2_mod);

    // Function traits analysis framework (call graph, mutation, async, etc.)
    const function_traits = b.addModule("function_traits", .{
        .root_source_file = b.path("src/analysis/function_traits.zig"),
    });
    function_traits.addImport("ast", ast);
    function_traits.addImport("hashmap_helper", hashmap_helper);

    // Debug info module for debugger support (external debug symbols like .pdb/.dSYM)
    const debug_info_mod = b.addModule("debug_info", .{
        .root_source_file = b.path("src/debug/debug_info.zig"),
    });

    // Source map module (re-exports debug_info for convenience)
    const source_map_mod = b.addModule("source_map", .{
        .root_source_file = b.path("src/debug/source_map.zig"),
    });
    _ = source_map_mod;

    // Module dependencies
    runtime.addImport("hashmap_helper", hashmap_helper);
    runtime.addImport("json_simd", json_simd);
    runtime.addImport("regex", regex_mod);
    runtime.addImport("bigint", bigint_mod);
    runtime.addImport("gzip", gzip_module);
    runtime.addImport("h2", h2_mod);
    runtime.addImport("tokenizer", tokenizer_mod);
    collections.addImport("runtime", runtime);

    // C interop module - with runtime access for eval/exec support
    const c_interop_mod = b.createModule(.{
        .root_source_file = b.path("packages/c_interop/src/registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    c_interop_mod.addImport("runtime", runtime);
    c_interop_mod.addImport("collections", collections);

    // WasmEdge bindings for server (optional - only linked if WASMEDGE_DIR is set)
    const wasmedge_mod = b.createModule(.{
        .root_source_file = b.path("packages/wasmedge/wasmedge.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Try to find WasmEdge from environment
    const wasmedge_dir = std.process.getEnvVarOwned(b.allocator, "WASMEDGE_DIR") catch null;
    if (wasmedge_dir) |dir| {
        defer b.allocator.free(dir);
        wasmedge_mod.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{dir}) });
        wasmedge_mod.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{dir}) });
        wasmedge_mod.linkSystemLibrary("wasmedge", .{});
    }

    // Unified metal0 module - mirrors Python's "from metal0 import ..."
    const metal0_mod = b.createModule(.{
        .root_source_file = b.path("packages/metal0.zig"),
        .target = target,
        .optimize = optimize,
    });
    metal0_mod.addImport("runtime", runtime);
    metal0_mod.addImport("collections", collections);
    metal0_mod.addImport("wasmedge", wasmedge_mod);
    metal0_mod.addImport("c_interop", c_interop_mod);
    metal0_mod.addImport("json", json_mod);
    metal0_mod.addImport("h2", h2_mod);
    metal0_mod.addImport("regex", regex_mod);
    metal0_mod.addImport("bigint", bigint_mod);
    metal0_mod.addImport("tokenizer", tokenizer_mod);
    metal0_mod.addImport("pkg", pkg_mod);
    metal0_mod.addImport("ds", ds_mod);
    metal0_mod.addImport("glob", glob_mod);

    // Main metal0 compiler executable
    const exe = b.addExecutable(.{
        .name = "metal0",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("hashmap_helper", hashmap_helper);
    exe.root_module.addImport("allocator_helper", allocator_helper);
    exe.root_module.addImport("runtime", runtime);
    exe.root_module.addImport("collections", collections);
    exe.root_module.addImport("fnv_hash", fnv_hash);
    exe.root_module.addImport("zig_keywords", zig_keywords);
    exe.root_module.addImport("ast", ast);
    // lexer and parser are imported via relative paths from src/
    exe.root_module.addImport("c_interop", c_interop_mod);
    exe.root_module.addImport("pkg", pkg_mod);
    exe.root_module.addImport("function_traits", function_traits);
    exe.root_module.addImport("debug_info", debug_info_mod);
    exe.root_module.addImport("wasmedge", wasmedge_mod);
    exe.root_module.addImport("metal0", metal0_mod);
    exe.linkLibC();

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the metal0 compiler");
    run_step.dependOn(&run_cmd.step);

    // Zig runtime tests
    // Create comptime_eval module with ast dependency
    const comptime_eval_module = b.createModule(.{
        .root_source_file = b.path("src/analysis/comptime_eval.zig"),
        .target = target,
        .optimize = optimize,
    });
    comptime_eval_module.addImport("ast", ast);

    // Create test module
    const runtime_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_comptime_eval.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add imports to test module
    runtime_tests.root_module.addImport("ast", ast);
    runtime_tests.root_module.addImport("comptime_eval", comptime_eval_module);

    const run_runtime_tests = b.addRunArtifact(runtime_tests);
    const test_step = b.step("test-zig", "Run Zig runtime unit tests");
    test_step.dependOn(&run_runtime_tests.step);

    // Green thread runtime modules
    const green_thread_module = b.createModule(.{
        .root_source_file = b.path("packages/runtime/src/green_thread.zig"),
        .target = target,
        .optimize = optimize,
    });

    const work_queue_module = b.createModule(.{
        .root_source_file = b.path("packages/runtime/src/work_queue.zig"),
        .target = target,
        .optimize = optimize,
    });
    work_queue_module.addImport("green_thread", green_thread_module);

    const netpoller_module = b.createModule(.{
        .root_source_file = b.path("packages/runtime/src/netpoller.zig"),
        .target = target,
        .optimize = optimize,
    });
    netpoller_module.addImport("green_thread", green_thread_module);

    const scheduler_module = b.createModule(.{
        .root_source_file = b.path("packages/runtime/src/scheduler.zig"),
        .target = target,
        .optimize = optimize,
    });
    scheduler_module.addImport("green_thread", green_thread_module);
    scheduler_module.addImport("work_queue", work_queue_module);
    scheduler_module.addImport("netpoller", netpoller_module);

    // Add async I/O support to HTTP/2 module
    h2_mod.addImport("green_thread", green_thread_module);
    h2_mod.addImport("netpoller", netpoller_module);

    // Add async I/O support to package manager module
    pkg_mod.addImport("green_thread", green_thread_module);
    pkg_mod.addImport("netpoller", netpoller_module);

    // Add async I/O support to runtime module (enables H2 client with goroutines)
    runtime.addImport("green_thread", green_thread_module);
    runtime.addImport("netpoller", netpoller_module);
    runtime.addImport("work_queue", work_queue_module);
    runtime.addImport("scheduler", scheduler_module);

    // Goroutine tests
    const goroutine_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_goroutines.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    goroutine_tests.root_module.addImport("scheduler", scheduler_module);
    goroutine_tests.root_module.addImport("green_thread", green_thread_module);

    const run_goroutine_tests = b.addRunArtifact(goroutine_tests);
    const goroutine_test_step = b.step("test-goroutines", "Run goroutine runtime tests");
    goroutine_test_step.dependOn(&run_goroutine_tests.step);

    // Basic goroutine tests (smaller, faster)
    const goroutine_basic_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_goroutines_basic.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    goroutine_basic_tests.root_module.addImport("scheduler", scheduler_module);
    goroutine_basic_tests.root_module.addImport("green_thread", green_thread_module);

    const run_goroutine_basic_tests = b.addRunArtifact(goroutine_basic_tests);
    const goroutine_basic_test_step = b.step("test-goroutines-basic", "Run basic goroutine tests");
    goroutine_basic_test_step.dependOn(&run_goroutine_basic_tests.step);

    // JSON spec compliance tests
    const json_spec_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/runtime/src/json/test_spec.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    json_spec_tests.root_module.addImport("hashmap_helper", hashmap_helper);
    json_spec_tests.root_module.addImport("allocator_helper", allocator_helper);
    json_spec_tests.root_module.addImport("runtime", runtime);

    const run_json_spec_tests = b.addRunArtifact(json_spec_tests);
    const json_test_step = b.step("test-json", "Run JSON spec compliance tests");
    json_test_step.dependOn(&run_json_spec_tests.step);

    // Manual JSON test
    const json_manual_test = b.addExecutable(.{
        .name = "test_json_manual",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test_json_manual.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    json_manual_test.root_module.addImport("runtime", runtime);
    json_manual_test.root_module.addImport("hashmap_helper", hashmap_helper);
    json_manual_test.root_module.addImport("allocator_helper", allocator_helper);
    json_manual_test.linkLibC();

    b.installArtifact(json_manual_test);

    const run_json_manual_test = b.addRunArtifact(json_manual_test);
    const json_manual_step = b.step("test-json-manual", "Run manual JSON tests");
    json_manual_step.dependOn(&run_json_manual_test.step);

    // Tokenizer correctness test
    const test_correctness_exe = b.addExecutable(.{
        .name = "test_correctness",
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/tokenizer/src/test_correctness.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_correctness_exe.root_module.addImport("tokenizer", tokenizer_mod);
    test_correctness_exe.root_module.addImport("json", json_mod);
    test_correctness_exe.root_module.addImport("allocator_helper", allocator_helper);
    test_correctness_exe.linkLibC();
    b.installArtifact(test_correctness_exe);

    // JSON parse benchmark
    const bench_json_parse = b.addExecutable(.{
        .name = "bench_metal0_json_parse",
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/runtime/benchmarks/bench_metal0_json_parse_fast.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    bench_json_parse.root_module.addImport("runtime", runtime);
    bench_json_parse.root_module.addImport("allocator_helper", allocator_helper);
    bench_json_parse.linkLibC();

    b.installArtifact(bench_json_parse);

    const run_bench_json_parse = b.addRunArtifact(bench_json_parse);
    const bench_json_parse_step = b.step("bench-json-parse", "Build and run JSON parse benchmark");
    bench_json_parse_step.dependOn(&run_bench_json_parse.step);

    // JSON stringify benchmark
    const bench_json_stringify = b.addExecutable(.{
        .name = "bench_metal0_json_stringify",
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/runtime/benchmarks/bench_metal0_json_stringify_fast.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    bench_json_stringify.root_module.addImport("runtime", runtime);
    bench_json_stringify.root_module.addImport("allocator_helper", allocator_helper);
    bench_json_stringify.linkLibC();

    b.installArtifact(bench_json_stringify);

    const run_bench_json_stringify = b.addRunArtifact(bench_json_stringify);
    const bench_json_stringify_step = b.step("bench-json-stringify", "Build and run JSON stringify benchmark");
    bench_json_stringify_step.dependOn(&run_bench_json_stringify.step);

    // Goroutine fan-out benchmark
    const bench_goroutine = b.addExecutable(.{
        .name = "bench_goroutine",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmarks/asyncio/bench_fanout.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    bench_goroutine.root_module.addImport("scheduler", scheduler_module);
    bench_goroutine.root_module.addImport("green_thread", green_thread_module);
    bench_goroutine.linkLibC();

    b.installArtifact(bench_goroutine);

    const run_bench_goroutine = b.addRunArtifact(bench_goroutine);
    const bench_goroutine_step = b.step("bench-goroutine", "Build and run goroutine fan-out benchmark");
    bench_goroutine_step.dependOn(&run_bench_goroutine.step);

    // Tokenizer encoding benchmark
    const tokenizer_bench = b.addExecutable(.{
        .name = "tokenizer_bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/tokenizer/src/bench_simple.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    tokenizer_bench.root_module.addImport("json", json_mod);
    tokenizer_bench.linkLibC();
    b.installArtifact(tokenizer_bench);

    const run_tokenizer_bench = b.addRunArtifact(tokenizer_bench);
    const tokenizer_bench_step = b.step("bench-tokenizer", "Build and run tokenizer encoding benchmark");
    tokenizer_bench_step.dependOn(&run_tokenizer_bench.step);

    // BPE Training benchmark
    const bench_train = b.addExecutable(.{
        .name = "bench_train",
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/tokenizer/src/bench_train.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    bench_train.root_module.addImport("json", json_mod);
    bench_train.root_module.addImport("allocator_helper", allocator_helper);
    bench_train.root_module.addImport("hashmap_helper", hashmap_helper);
    bench_train.linkLibC();
    b.installArtifact(bench_train);

    const run_bench_train = b.addRunArtifact(bench_train);
    const bench_train_step = b.step("bench-train", "Build and run BPE training benchmark");
    bench_train_step.dependOn(&run_bench_train.step);

    // Token optimizer proxy - build from packages/token_optimizer/ directory
    // It has its own build.zig with zigimg dependency
    // Run: cd packages/token_optimizer && zig build
    const token_optimizer_step = b.step("token-optimizer", "Token optimizer (build from packages/token_optimizer/)");
    _ = token_optimizer_step;

    // Gzip tests with libdeflate
    const gzip_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/runtime/src/gzip/test_gzip.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    gzip_tests.linkLibC();
    gzip_tests.addIncludePath(b.path("vendor/libdeflate"));
    gzip_tests.addCSourceFiles(.{
        .files = &.{
            "vendor/libdeflate/lib/deflate_compress.c",
            "vendor/libdeflate/lib/deflate_decompress.c",
            "vendor/libdeflate/lib/utils.c",
            "vendor/libdeflate/lib/gzip_compress.c",
            "vendor/libdeflate/lib/gzip_decompress.c",
            "vendor/libdeflate/lib/zlib_compress.c",
            "vendor/libdeflate/lib/zlib_decompress.c",
            "vendor/libdeflate/lib/adler32.c",
            "vendor/libdeflate/lib/crc32.c",
            "vendor/libdeflate/lib/arm/cpu_features.c",
            "vendor/libdeflate/lib/x86/cpu_features.c",
        },
        .flags = &.{"-std=c99"},
    });

    const run_gzip_tests = b.addRunArtifact(gzip_tests);
    const gzip_test_step = b.step("test-gzip", "Run gzip compression tests");
    gzip_test_step.dependOn(&run_gzip_tests.step);

    // Package manager tests (PEP 440, 508, requirements.txt, METADATA, PubGrub)
    const pkg_test_module = b.createModule(.{
        .root_source_file = b.path("packages/pkg/src/pkg.zig"),
        .target = target,
        .optimize = optimize,
    });
    pkg_test_module.addImport("json", json_mod);
    pkg_test_module.addImport("h2", h2_mod);
    pkg_test_module.addImport("green_thread", green_thread_module);
    pkg_test_module.addImport("netpoller", netpoller_module);

    const pkg_tests = b.addTest(.{
        .root_module = pkg_test_module,
    });

    const run_pkg_tests = b.addRunArtifact(pkg_tests);
    const pkg_test_step = b.step("test-pkg", "Run package manager parser tests");
    pkg_test_step.dependOn(&run_pkg_tests.step);

    // Package resolver CLI tool (for testing)
    const pkg_module = b.createModule(.{
        .root_source_file = b.path("packages/pkg/src/pkg.zig"),
        .target = target,
        .optimize = optimize,
    });
    pkg_module.addImport("json", json_mod);
    pkg_module.addImport("h2", h2_mod);
    pkg_module.addImport("green_thread", green_thread_module);
    pkg_module.addImport("netpoller", netpoller_module);

    const resolve_exe = b.addExecutable(.{
        .name = "resolve",
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/pkg/src/resolve/test_resolve.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "pkg", .module = pkg_module },
            },
        }),
    });
    // Link libdeflate for gzip decompression
    resolve_exe.root_module.addIncludePath(b.path("vendor/libdeflate"));
    resolve_exe.root_module.addCSourceFiles(.{
        .files = &.{
            "vendor/libdeflate/lib/deflate_compress.c",
            "vendor/libdeflate/lib/deflate_decompress.c",
            "vendor/libdeflate/lib/utils.c",
            "vendor/libdeflate/lib/gzip_compress.c",
            "vendor/libdeflate/lib/gzip_decompress.c",
            "vendor/libdeflate/lib/adler32.c",
            "vendor/libdeflate/lib/crc32.c",
            "vendor/libdeflate/lib/arm/cpu_features.c",
            "vendor/libdeflate/lib/x86/cpu_features.c",
        },
        .flags = &[_][]const u8{ "-std=c99", "-O3" },
    });
    resolve_exe.linkLibC();
    b.installArtifact(resolve_exe);

    const run_resolve = b.addRunArtifact(resolve_exe);
    run_resolve.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_resolve.addArgs(args);
    }
    const resolve_step = b.step("resolve", "Run package resolver (usage: zig build resolve -- numpy pandas)");
    resolve_step.dependOn(&run_resolve.step);

    // Bytecode VM tests (for eval/exec) - test opcode and VM directly
    // (compiler.zig has parser/lexer deps that require separate build config)
    const opcode_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bytecode/opcode.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const vm_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bytecode/vm.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    // VM uses runtime.PyValue conditionally
    vm_tests.root_module.addImport("runtime", runtime);

    const run_opcode_tests = b.addRunArtifact(opcode_tests);
    const run_vm_tests = b.addRunArtifact(vm_tests);

    const bytecode_test_step = b.step("test-bytecode", "Run bytecode VM tests");
    bytecode_test_step.dependOn(&run_opcode_tests.step);
    bytecode_test_step.dependOn(&run_vm_tests.step);
}
