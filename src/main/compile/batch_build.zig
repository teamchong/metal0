//! Batch test compilation build system
//! Compiles all tests in a single Zig process, sharing runtime module analysis
//!
//! This is THE key optimization: instead of invoking `zig build-exe` 397 times
//! (each parsing 236K LOC runtime), we invoke `zig build` ONCE and compile
//! all tests in parallel with shared module analysis.
//!
//! Expected performance:
//!   Before: 397 tests × 2-3s = 13+ minutes
//!   After:  1 × 60s (shared analysis) + 397 × 0.1s (parallel codegen) = ~100s
//!
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Pre-built runtime archive path (skips recompiling 236K LOC runtime)
    const runtime_archive = b.option([]const u8, "runtime-archive", "Path to pre-built libruntime.a");

    // ══════════════════════════════════════════════════════════════════════════
    // MODULE DEFINITIONS - mirrors src/compiler.zig MODULES exactly
    // ══════════════════════════════════════════════════════════════════════════

    // Leaf modules (no dependencies)
    const hashmap_helper = b.addModule("utils.hashmap_helper", .{
        .root_source_file = b.path("../src/utils/hashmap_helper.zig"),
        .target = target,
        .optimize = optimize,
    });

    const allocator_helper = b.addModule("utils.allocator_helper", .{
        .root_source_file = b.path("../src/utils/allocator_helper.zig"),
        .target = target,
        .optimize = optimize,
    });

    const bigint = b.addModule("bigint", .{
        .root_source_file = b.path("../packages/bigint/src/bigint.zig"),
        .target = target,
        .optimize = optimize,
    });

    const green_thread = b.addModule("green_thread", .{
        .root_source_file = b.path("../packages/runtime/src/runtime/green_thread.zig"),
        .target = target,
        .optimize = optimize,
    });

    const gzip = b.addModule("gzip", .{
        .root_source_file = b.path("../packages/runtime/src/Modules/gzip/gzip.zig"),
        .target = target,
        .optimize = optimize,
    });
    gzip.addIncludePath(b.path("../vendor/libdeflate"));

    // Always disable AVX-512 for maximum reliability across all platforms
    const c_flags: []const []const u8 = &.{
        "-std=c99",
        "-O3",
        "-DLIBDEFLATE_ASSEMBLER_DOES_NOT_SUPPORT_AVX512VNNI",
        "-DLIBDEFLATE_ASSEMBLER_DOES_NOT_SUPPORT_VPCLMULQDQ",
    };

    gzip.addCSourceFiles(.{
        .files = &.{
            "../vendor/libdeflate/lib/deflate_compress.c",
            "../vendor/libdeflate/lib/deflate_decompress.c",
            "../vendor/libdeflate/lib/utils.c",
            "../vendor/libdeflate/lib/gzip_compress.c",
            "../vendor/libdeflate/lib/gzip_decompress.c",
            "../vendor/libdeflate/lib/zlib_compress.c",
            "../vendor/libdeflate/lib/zlib_decompress.c",
            "../vendor/libdeflate/lib/adler32.c",
            "../vendor/libdeflate/lib/crc32.c",
            "../vendor/libdeflate/lib/arm/cpu_features.c",
            "../vendor/libdeflate/lib/x86/cpu_features.c",
        },
        .flags = c_flags,
    });

    const regex = b.addModule("regex", .{
        .root_source_file = b.path("../packages/regex/src/pyregex/regex.zig"),
        .target = target,
        .optimize = optimize,
    });

    const json_simd = b.addModule("json_simd", .{
        .root_source_file = b.path("../packages/shared/json/simd/dispatch.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Modules with dependencies
    const json = b.addModule("json", .{
        .root_source_file = b.path("../packages/shared/json/json.zig"),
        .target = target,
        .optimize = optimize,
    });
    json.addImport("json_simd", json_simd);
    json.addImport("utils.hashmap_helper", hashmap_helper);

    const netpoller = b.addModule("netpoller", .{
        .root_source_file = b.path("../packages/runtime/src/runtime/netpoller.zig"),
        .target = target,
        .optimize = optimize,
    });
    netpoller.addImport("green_thread", green_thread);

    const work_queue = b.addModule("work_queue", .{
        .root_source_file = b.path("../packages/runtime/src/runtime/work_queue.zig"),
        .target = target,
        .optimize = optimize,
    });
    work_queue.addImport("green_thread", green_thread);

    const scheduler = b.addModule("scheduler", .{
        .root_source_file = b.path("../packages/runtime/src/runtime/scheduler.zig"),
        .target = target,
        .optimize = optimize,
    });
    scheduler.addImport("green_thread", green_thread);
    scheduler.addImport("work_queue", work_queue);
    scheduler.addImport("netpoller", netpoller);

    const tokenizer = b.addModule("tokenizer", .{
        .root_source_file = b.path("../packages/tokenizer/src/tokenizer.zig"),
        .target = target,
        .optimize = optimize,
    });
    tokenizer.addImport("json", json);
    tokenizer.addImport("utils.hashmap_helper", hashmap_helper);

    // Runtime module - the big one (236K LOC)
    const runtime = b.addModule("runtime", .{
        .root_source_file = b.path("../packages/runtime/src/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime.addImport("utils.hashmap_helper", hashmap_helper);
    runtime.addImport("utils.allocator_helper", allocator_helper);
    runtime.addImport("bigint", bigint);
    runtime.addImport("gzip", gzip);
    runtime.addImport("regex", regex);
    runtime.addImport("tokenizer", tokenizer);
    runtime.addImport("green_thread", green_thread);
    runtime.addImport("netpoller", netpoller);
    runtime.addImport("scheduler", scheduler);

    // ══════════════════════════════════════════════════════════════════════════
    // TEST EXECUTABLES - read from manifest file
    // ══════════════════════════════════════════════════════════════════════════

    const manifest_path = "test_manifest.txt";
    const manifest_file = std.fs.cwd().openFile(manifest_path, .{}) catch |err| {
        std.debug.print("Cannot open {s}: {any}\n", .{ manifest_path, err });
        std.debug.print("Run 'metal0 test' to generate the manifest first.\n", .{});
        return;
    };
    defer manifest_file.close();

    var buf: [1024 * 1024]u8 = undefined;
    const manifest_size = manifest_file.readAll(&buf) catch |err| {
        std.debug.print("Cannot read manifest: {any}\n", .{err});
        return;
    };
    const manifest_content = buf[0..manifest_size];

    // Parse manifest: each line is "zig_path:bin_name"
    var line_iter = std.mem.splitScalar(u8, manifest_content, '\n');

    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        var parts = std.mem.splitScalar(u8, line, ':');
        const zig_path_rel = parts.next() orelse continue;
        const bin_name = parts.next() orelse continue;

        // Skip empty names
        if (bin_name.len == 0) continue;

        // Create executable with root_module
        // NOTE: Must include all modules that runtime re-exports, since the generated
        // test code may directly reference types from these modules (e.g., BigInt)

        // bin_name is like "tests/cpython/test_bool" - extract dir and name
        const bin_dir = if (std.mem.lastIndexOf(u8, bin_name, "/")) |idx|
            bin_name[0..idx]
        else
            "";
        const exe_name = if (std.mem.lastIndexOf(u8, bin_name, "/")) |idx|
            bin_name[idx + 1 ..]
        else
            bin_name;

        const exe = b.addExecutable(.{
            .name = exe_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(zig_path_rel),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "runtime", .module = runtime },
                    .{ .name = "utils.hashmap_helper", .module = hashmap_helper },
                    .{ .name = "utils.allocator_helper", .module = allocator_helper },
                    .{ .name = "bigint", .module = bigint },
                },
            }),
        });

        // Link libc
        exe.linkLibC();

        // Link pre-built runtime archive if provided (HUGE speed boost)
        // Use .path for absolute paths (runtime archive is at ~/.metal0/runtime/)
        if (runtime_archive) |archive_path| {
            exe.addObjectFile(.{ .path = archive_path });
        }

        // Install to the correct relative path
        // e.g., bin_name="tests/cpython/test_bool" -> install to <prefix>/tests/cpython/test_bool
        const install_step = b.addInstallArtifact(exe, .{
            .dest_dir = if (bin_dir.len > 0)
                .{ .override = .{ .custom = bin_dir } }
            else
                .{ .override = .bin },
        });
        b.default_step.dependOn(&install_step.step);
    }
}
