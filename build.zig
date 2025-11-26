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

    // Module dependencies
    runtime.addImport("hashmap_helper", hashmap_helper);
    collections.addImport("runtime", runtime);

    // C interop module
    const c_interop_mod = b.createModule(.{
        .root_source_file = b.path("packages/c_interop/src/registry.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Main pyaot compiler executable
    const exe = b.addExecutable(.{
        .name = "pyaot",
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
    exe.root_module.addImport("c_interop", c_interop_mod);
    exe.linkLibC();

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the pyaot compiler");
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

    const scheduler_module = b.createModule(.{
        .root_source_file = b.path("packages/runtime/src/scheduler.zig"),
        .target = target,
        .optimize = optimize,
    });
    scheduler_module.addImport("green_thread", green_thread_module);
    scheduler_module.addImport("work_queue", work_queue_module);

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

    // Work-stealing benchmark
    const bench_work_stealing = b.addExecutable(.{
        .name = "bench_work_stealing",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/bench_work_stealing.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    bench_work_stealing.root_module.addImport("scheduler", scheduler_module);
    bench_work_stealing.root_module.addImport("green_thread", green_thread_module);

    b.installArtifact(bench_work_stealing);

    const run_bench_work_stealing = b.addRunArtifact(bench_work_stealing);
    const bench_work_stealing_step = b.step("bench-work-stealing", "Run work-stealing benchmark");
    bench_work_stealing_step.dependOn(&run_bench_work_stealing.step);

    // JSON parse benchmark
    const bench_json_parse = b.addExecutable(.{
        .name = "bench_pyaot_json_parse",
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/runtime/benchmarks/bench_pyaot_json_parse_fast.zig"),
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

    // Token optimizer proxy
    const token_optimizer = b.addExecutable(.{
        .name = "token_optimizer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/token_optimizer/src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    token_optimizer.root_module.addImport("gzip", gzip_module);
    token_optimizer.linkLibC();
    token_optimizer.addIncludePath(b.path("vendor/libdeflate"));
    token_optimizer.addCSourceFiles(.{
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

    b.installArtifact(token_optimizer);

    const run_token_optimizer = b.addRunArtifact(token_optimizer);
    const token_optimizer_step = b.step("token-optimizer", "Run token optimizer proxy");
    token_optimizer_step.dependOn(&run_token_optimizer.step);

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

}
