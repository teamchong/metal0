const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Import runtime gzip module
    const runtime_gzip = b.addModule("gzip", .{
        .root_source_file = b.path("../../packages/runtime/src/gzip/gzip.zig"),
    });
    runtime_gzip.addIncludePath(b.path("../../vendor/libdeflate"));

    // Import zigimg for GIF encoding
    const zigimg = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });
    const zigimg_module = zigimg.module("zigimg");

    // Proxy server executable
    const proxy = b.addExecutable(.{
        .name = "token_optimizer_proxy",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    proxy.root_module.addImport("gzip", runtime_gzip);
    proxy.root_module.addImport("zigimg", zigimg_module);

    // Add libdeflate for gzip compression
    proxy.linkLibC();
    proxy.addIncludePath(b.path("../../vendor/libdeflate"));
    proxy.addCSourceFiles(.{
        .files = &.{
            "../../vendor/libdeflate/lib/deflate_compress.c",
            "../../vendor/libdeflate/lib/deflate_decompress.c",
            "../../vendor/libdeflate/lib/utils.c",
            "../../vendor/libdeflate/lib/gzip_compress.c",
            "../../vendor/libdeflate/lib/gzip_decompress.c",
            "../../vendor/libdeflate/lib/zlib_compress.c",
            "../../vendor/libdeflate/lib/zlib_decompress.c",
            "../../vendor/libdeflate/lib/adler32.c",
            "../../vendor/libdeflate/lib/crc32.c",
            "../../vendor/libdeflate/lib/arm/cpu_features.c",
            "../../vendor/libdeflate/lib/x86/cpu_features.c",
        },
        .flags = &[_][]const u8{ "-std=c99", "-O3" },
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
