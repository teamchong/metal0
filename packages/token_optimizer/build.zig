const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Import runtime gzip module
    const runtime_gzip = b.addModule("gzip", .{
        .root_source_file = b.path("../../packages/runtime/src/gzip/gzip.zig"),
    });
    runtime_gzip.addIncludePath(b.path("../../vendor/libdeflate"));

    // Import shared JSON library (2.17x faster than std.json)
    const json_simd = b.addModule("json_simd", .{
        .root_source_file = b.path("../shared/json/simd/dispatch.zig"),
    });
    const shared_json = b.addModule("json", .{
        .root_source_file = b.path("../shared/json/json.zig"),
    });
    shared_json.addImport("json_simd", json_simd);

    // Common reusable packages
    const anthropic_types = b.addModule("anthropic_types", .{
        .root_source_file = b.path("../anthropic_types/src/api_types.zig"),
    });
    anthropic_types.addImport("json", shared_json);

    const pixel_font = b.addModule("pixel_font", .{
        .root_source_file = b.path("../pixel_font/src/font_5x7.zig"),
    });

    const pixel_render = b.addModule("pixel_render", .{
        .root_source_file = b.path("../pixel_render/src/render.zig"),
    });
    pixel_render.addImport("pixel_font", pixel_font);
    pixel_render.addImport("anthropic_types", anthropic_types);

    const tiny_gif = b.addModule("tiny_gif", .{
        .root_source_file = b.path("../tiny_gif/src/gif.zig"),
    });

    const green_thread_module = b.createModule(.{
        .root_source_file = b.path("../runtime/src/green_thread.zig"),
        .target = target,
        .optimize = optimize,
    });

    const netpoller_module = b.createModule(.{
        .root_source_file = b.path("../runtime/src/netpoller.zig"),
        .target = target,
        .optimize = optimize,
    });
    netpoller_module.addImport("green_thread", green_thread_module);

    const h2_mod = b.addModule("h2", .{
        .root_source_file = b.path("../shared/http/h2/h2.zig"),
    });
    h2_mod.addImport("gzip", runtime_gzip);
    h2_mod.addImport("green_thread", green_thread_module);
    h2_mod.addImport("netpoller", netpoller_module);

    // Import zigimg for PNG/GIF helpers
    const zigimg = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });
    const zigimg_module = zigimg.module("zigimg");

    const pal_png = b.addModule("pal_png", .{
        .root_source_file = b.path("../pal_png/src/png_zigimg.zig"),
    });
    pal_png.addImport("zigimg", zigimg_module);

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
    proxy.root_module.addImport("json", shared_json);
    proxy.root_module.addImport("anthropic_types", anthropic_types);
    proxy.root_module.addImport("pixel_render", pixel_render);
    proxy.root_module.addImport("pal_png", pal_png);
    proxy.root_module.addImport("tiny_gif", tiny_gif);
    proxy.root_module.addImport("h2", h2_mod);

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
    test_render.root_module.addImport("json", shared_json);
    test_render.root_module.addImport("anthropic_types", anthropic_types);
    test_render.root_module.addImport("pixel_render", pixel_render);

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
    test_compress.root_module.addImport("json", shared_json);
    test_compress.root_module.addImport("anthropic_types", anthropic_types);
    test_compress.root_module.addImport("pixel_render", pixel_render);
    test_compress.root_module.addImport("pal_png", pal_png);
    test_compress.root_module.addImport("tiny_gif", tiny_gif);
    test_compress.root_module.addImport("zigimg", zigimg_module);

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
    test_gif.root_module.addImport("pixel_render", pixel_render);
    test_gif.root_module.addImport("tiny_gif", tiny_gif);

    const run_test_gif = b.addRunArtifact(test_gif);
    test_step.dependOn(&run_test_gif.step);

    // Test: api_types.zig
    const test_api_types = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test_api_types.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_api_types.root_module.addImport("json", shared_json);
    test_api_types.root_module.addImport("anthropic_types", anthropic_types);

    const run_test_api_types = b.addRunArtifact(test_api_types);
    test_step.dependOn(&run_test_api_types.step);
}
