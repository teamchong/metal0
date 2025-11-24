const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create collections module
    const collections_mod = b.addModule("collections", .{
        .root_source_file = b.path("numeric_impl.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Tests
    const tests = b.addTest(.{
        .name = "collections-test",
        .target = target,
        .optimize = optimize,
    });
    tests.root_module.addImport("collections", collections_mod);
    tests.addIncludePath(b.path("."));

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);

    _ = collections_mod;
}
