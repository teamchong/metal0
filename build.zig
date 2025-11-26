const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
    exe.root_module.addImport("c_interop", c_interop_mod);

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
    // Create shared ast module
    const ast_module = b.createModule(.{
        .root_source_file = b.path("src/ast.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create comptime_eval module with ast dependency
    const comptime_eval_module = b.createModule(.{
        .root_source_file = b.path("src/analysis/comptime_eval.zig"),
        .target = target,
        .optimize = optimize,
    });
    comptime_eval_module.addImport("ast", ast_module);

    // Create test module
    const runtime_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_comptime_eval.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add imports to test module
    runtime_tests.root_module.addImport("ast", ast_module);
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

    // Token optimizer proxy
    const token_optimizer = b.addExecutable(.{
        .name = "token_optimizer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("packages/token_optimizer/src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(token_optimizer);

    const run_token_optimizer = b.addRunArtifact(token_optimizer);
    const token_optimizer_step = b.step("token-optimizer", "Run token optimizer proxy");
    token_optimizer_step.dependOn(&run_token_optimizer.step);

}
