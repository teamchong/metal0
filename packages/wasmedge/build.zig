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

    // Try to find WasmEdge via pkg-config first
    if (b.systemIntegrationOption(.wasmedge)) |_| {
        wasmedge.linkSystemLibrary("wasmedge", .{});
    } else {
        // Fallback: expect headers in standard locations or WASMEDGE_DIR
        const wasmedge_dir = std.process.getEnvVarOwned(b.allocator, "WASMEDGE_DIR") catch null;
        if (wasmedge_dir) |dir| {
            defer b.allocator.free(dir);
            wasmedge.addIncludePath(.{ .cwd_relative = b.fmt("{s}/include", .{dir}) });
            wasmedge.addLibraryPath(.{ .cwd_relative = b.fmt("{s}/lib", .{dir}) });
        }
        wasmedge.linkSystemLibrary("wasmedge", .{});
    }

    // Tests
    const tests = b.addTest(.{
        .root_source_file = b.path("wasmedge.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run wasmedge binding tests");
    test_step.dependOn(&run_tests.step);
}
