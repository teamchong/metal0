const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // WasmEdge module
    const wasmedge = b.addModule("wasmedge", .{
        .root_source_file = b.path("wasmedge.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Get WASMEDGE_DIR from environment
    const wasmedge_dir = std.process.getEnvVarOwned(b.allocator, "WASMEDGE_DIR") catch null;
    if (wasmedge_dir) |dir| {
        defer b.allocator.free(dir);
        wasmedge.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{dir}) });
        wasmedge.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{dir}) });
    }
    wasmedge.linkSystemLibrary("wasmedge", .{});

    // Tests - create as executable with test runner
    const tests = b.addTest(.{
        .root_module = wasmedge,
    });

    // Add library paths to tests too
    const test_wasmedge_dir = std.process.getEnvVarOwned(b.allocator, "WASMEDGE_DIR") catch null;
    if (test_wasmedge_dir) |dir| {
        defer b.allocator.free(dir);
        tests.root_module.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{dir}) });
        tests.root_module.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{dir}) });
    }
    tests.root_module.linkSystemLibrary("wasmedge", .{});

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run wasmedge binding tests");
    test_step.dependOn(&run_tests.step);
}
