const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Proxy server executable
    const proxy = b.addExecutable(.{
        .name = "token_optimizer_proxy",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(proxy);

    // Run step for proxy server
    const run_proxy = b.addRunArtifact(proxy);
    run_proxy.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_proxy.addArgs(args);
    }

    const run_step = b.step("run", "Run the proxy server");
    run_step.dependOn(&run_proxy.step);

    // Test: render.zig
    const test_render = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test_render.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_test_render = b.addRunArtifact(test_render);
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_test_render.step);

    // Test: compress.zig
    const test_compress = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test_compress.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_test_compress = b.addRunArtifact(test_compress);
    test_step.dependOn(&run_test_compress.step);

    // Test: gif.zig
    const test_gif = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test_gif.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_test_gif = b.addRunArtifact(test_gif);
    test_step.dependOn(&run_test_gif.step);
}
