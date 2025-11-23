const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module
    const regex_module = b.addModule("regex", .{
        .root_source_file = b.path("src/mvzr.zig"),
    });

    // Test step
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/mvzr.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run regex tests");
    test_step.dependOn(&run_tests.step);

    // Example executable
    const example = b.addExecutable(.{
        .name = "example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("example.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(example);

    const run_example = b.addRunArtifact(example);
    const example_step = b.step("example", "Run regex example");
    example_step.dependOn(&run_example.step);

    // Benchmark executable
    const bench_zig = b.addExecutable(.{
        .name = "bench_zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench_zig.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(bench_zig);

    const run_bench_zig = b.addRunArtifact(bench_zig);
    const bench_step = b.step("bench", "Run Zig regex benchmark");
    bench_step.dependOn(&run_bench_zig.step);

    _ = regex_module;
}
