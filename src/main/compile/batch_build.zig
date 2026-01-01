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

    // C interop module - enables C extension support (numpy, pytorch, etc.)
    const c_interop = b.addModule("c_interop", .{
        .root_source_file = b.path("../packages/c_interop/src/registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    c_interop.addImport("runtime", runtime);
    c_interop.addImport("utils.hashmap_helper", hashmap_helper);

    // ══════════════════════════════════════════════════════════════════════════
    // PACKAGE MODULES - read from package_modules.txt manifest
    // These are external packages (numpy, pytest, etc.) that were compiled during codegen
    // ══════════════════════════════════════════════════════════════════════════

    // Store package modules for later injection into test executables
    const PackageModule = struct {
        name: []const u8,
        module: *std.Build.Module,
    };
    var package_modules_list: [64]PackageModule = undefined;
    var package_module_count: usize = 0;

    const pkg_manifest_path = "package_modules.txt";
    if (std.fs.cwd().openFile(pkg_manifest_path, .{})) |pkg_file| {
        defer pkg_file.close();

        var pkg_buf: [256 * 1024]u8 = undefined;
        const pkg_size = pkg_file.readAll(&pkg_buf) catch 0;
        const pkg_content = pkg_buf[0..pkg_size];

        // Parse package manifest: each line is "module_name:absolute_path"
        var pkg_lines = std.mem.splitScalar(u8, pkg_content, '\n');
        while (pkg_lines.next()) |pkg_line| {
            if (pkg_line.len == 0) continue;
            if (package_module_count >= 64) break; // Safety limit

            var pkg_parts = std.mem.splitScalar(u8, pkg_line, ':');
            const mod_name = pkg_parts.next() orelse continue;
            const mod_path = pkg_parts.next() orelse continue;

            if (mod_name.len == 0 or mod_path.len == 0) continue;

            // Create module for this package
            // Use .cwd_relative for absolute paths (Zig 0.15)
            const pkg_mod = b.addModule(mod_name, .{
                .root_source_file = .{ .cwd_relative = mod_path },
                .target = target,
                .optimize = optimize,
            });

            // Package modules need access to runtime and c_interop
            pkg_mod.addImport("runtime", runtime);
            pkg_mod.addImport("c_interop", c_interop);
            pkg_mod.addImport("utils.hashmap_helper", hashmap_helper);
            pkg_mod.addImport("utils.allocator_helper", allocator_helper);
            pkg_mod.addImport("bigint", bigint);

            package_modules_list[package_module_count] = .{
                .name = mod_name,
                .module = pkg_mod,
            };
            package_module_count += 1;

            std.debug.print("Registered package module: {s}\n", .{mod_name});
        }
    } else |_| {
        // No package modules manifest - that's OK, just means no external packages
    }

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

    // Note: Prefetching is skipped in batch builds because:
    // 1. Zig's build scripts can't spawn threads (prefetch uses std.Thread)
    // 2. Batch compilation already shares module analysis, making individual file prefetch less beneficial
    // 3. Prefetch optimization is still active in individual file compilation (main compilation path)

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
                    .{ .name = "c_interop", .module = c_interop },
                },
            }),
        });

        // Add package modules (numpy, pytest, etc.) to this executable
        // These are registered dynamically from package_modules.txt
        // IMPORTANT: Only add modules that are actually imported by this test
        // Zig 0.15 errors on "module declared but not used"
        const zig_file = std.fs.cwd().openFile(zig_path_rel, .{}) catch null;
        if (zig_file) |file| {
            defer file.close();
            var file_buf: [64 * 1024]u8 = undefined;
            const file_size = file.readAll(&file_buf) catch 0;
            const file_content = file_buf[0..file_size];

            for (package_modules_list[0..package_module_count]) |pkg| {
                // Check if this test actually imports this package
                // Look for @import("package_name") in the generated code
                var import_pattern_buf: [128]u8 = undefined;
                const import_pattern = std.fmt.bufPrint(&import_pattern_buf, "@import(\"{s}\")", .{pkg.name}) catch continue;
                if (std.mem.indexOf(u8, file_content, import_pattern) != null) {
                    exe.root_module.addImport(pkg.name, pkg.module);
                }
            }
        } else {
            // Fallback: add all package modules if we can't read the file
            for (package_modules_list[0..package_module_count]) |pkg| {
                exe.root_module.addImport(pkg.name, pkg.module);
            }
        }

        // Link libc
        exe.linkLibC();

        // Link pre-built runtime archive if provided (HUGE speed boost)
        // In Zig 0.15, use .cwd_relative for absolute paths (runtime archive is at ~/.metal0/runtime/)
        if (runtime_archive) |archive_path| {
            exe.addObjectFile(.{ .cwd_relative = archive_path });
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
