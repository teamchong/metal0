const std = @import("std");

/// Copy a runtime subdirectory recursively to cache
pub fn copyRuntimeDir(allocator: std.mem.Allocator, dir_name: []const u8, build_dir: []const u8) !void {
    const src_dir_path = try std.fmt.allocPrint(allocator, "packages/runtime/src/{s}", .{dir_name});
    defer allocator.free(src_dir_path);
    const dst_dir_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ build_dir, dir_name });
    defer allocator.free(dst_dir_path);

    // Create destination directory
    std.fs.cwd().makeDir(dst_dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Open source directory - fail loudly if not found
    var src_dir = std.fs.cwd().openDir(src_dir_path, .{ .iterate = true }) catch |err| {
        std.debug.print("ERROR: Failed to open runtime directory '{s}': {any}\n", .{ src_dir_path, err });
        return err;
    };
    defer src_dir.close();

    // Iterate through files in source directory
    var iterator = src_dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file) {
            // Copy file
            const src_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_dir_path, entry.name });
            defer allocator.free(src_file_path);
            const dst_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_dir_path, entry.name });
            defer allocator.free(dst_file_path);

            const src_file = try std.fs.cwd().openFile(src_file_path, .{});
            defer src_file.close();
            const dst_file = try std.fs.cwd().createFile(dst_file_path, .{});
            defer dst_file.close();

            var content = try src_file.readToEndAlloc(allocator, 10 * 1024 * 1024);

            // Patch imports for standalone compilation
            // Files at different depths need different patterns patched
            if (std.mem.endsWith(u8, entry.name, ".zig")) {
                // Determine directory depth for proper relative imports
                // Count slashes in dir_name to know how deep we are
                const depth = blk: {
                    var count: usize = 0;
                    for (dir_name) |c| {
                        if (c == '/') count += 1;
                    }
                    break :blk count;
                };

                // Patch relative utils imports to use local utils/ directory
                content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"../../../../src/utils/", "@import(\"../utils/");
                content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"../../../src/utils/", "@import(\"utils/");
                content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"../../src/utils/", "@import(\"utils/");

                // Patch module imports to file imports (for modules defined in build.zig)
                // Adjust path based on depth: runtime/ needs ../utils/, top-level needs utils/
                if (depth > 0) {
                    // Files in subdirectories need ../ prefix
                    content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"hashmap_helper\")", "@import(\"../utils/hashmap_helper.zig\")");
                    content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"allocator_helper\")", "@import(\"../utils/allocator_helper.zig\")");
                } else {
                    content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"hashmap_helper\")", "@import(\"utils/hashmap_helper.zig\")");
                    content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"allocator_helper\")", "@import(\"utils/allocator_helper.zig\")");
                }
                content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"runtime.zig\")", "@import(\"../runtime.zig\")");
                // Patch bigint module import for files in runtime/ subdirectory
                content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"bigint\")", "@import(\"../bigint.zig\")");

                // Patch green_thread/scheduler/work_queue/netpoller module imports
                // These are in the runtime/ directory, so files in runtime/ need file imports
                if (std.mem.startsWith(u8, dir_name, "runtime")) {
                    content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"green_thread\")", "@import(\"green_thread.zig\")");
                    content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"work_queue\")", "@import(\"work_queue.zig\")");
                    content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"scheduler\")", "@import(\"scheduler.zig\")");
                    content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"netpoller\")", "@import(\"netpoller.zig\")");
                }
                // Patch json_simd module - different depths need different paths
                // Files in json/ need simd/dispatch.zig
                // Files in json/parse/ or json/parse_direct/ need ../simd/dispatch.zig
                if (std.mem.indexOf(u8, dst_dir_path, "/parse") != null or
                    std.mem.indexOf(u8, dst_dir_path, "/parse_direct") != null)
                {
                    content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"json_simd\")", "@import(\"../simd/dispatch.zig\")");
                } else {
                    content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"json_simd\")", "@import(\"simd/dispatch.zig\")");
                }
                // Fix parse_direct import in subdirectories
                content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"../parse_direct.zig\")", "@import(\"../parse_direct.zig\")");

                // Patch h2 module for files in Lib/http/
                // h2 is at cache root (cache/h2/), Lib/http is at cache/Lib/http/
                if (std.mem.indexOf(u8, dir_name, "Lib/http") != null) {
                    content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"h2\")", "@import(\"../../h2/h2.zig\")");
                }
            }

            try dst_file.writeAll(content);
        } else if (entry.kind == .directory) {
            // Recursively copy subdirectory
            const subdir_name = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_name, entry.name });
            defer allocator.free(subdir_name);
            try copyRuntimeDir(allocator, subdir_name, build_dir);
        }
    }
}

/// Copy a single runtime file to cache
pub fn copyRuntimeFile(allocator: std.mem.Allocator, filename: []const u8, build_dir: []const u8) !void {
    const src_path = try std.fmt.allocPrint(allocator, "packages/runtime/src/{s}", .{filename});
    defer allocator.free(src_path);
    const dst_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ build_dir, filename });
    defer allocator.free(dst_path);

    const src_file = std.fs.cwd().openFile(src_path, .{}) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer src_file.close();
    const dst_file = try std.fs.cwd().createFile(dst_path, .{});
    defer dst_file.close();

    const content = try src_file.readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(content);
    try dst_file.writeAll(content);
}

/// Copy JSON SIMD files from shared/json/simd to cache/Lib/json/simd
pub fn copyJsonSimd(allocator: std.mem.Allocator, build_dir: []const u8) !void {
    const src_dir_path = "packages/shared/json/simd";
    const dst_dir_path = try std.fmt.allocPrint(allocator, "{s}/Lib/json/simd", .{build_dir});
    defer allocator.free(dst_dir_path);

    // Create destination directory
    std.fs.cwd().makePath(dst_dir_path) catch {};

    // Open source directory
    var src_dir = std.fs.cwd().openDir(src_dir_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer src_dir.close();

    // Copy all .zig files
    var iterator = src_dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const src_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_dir_path, entry.name });
            defer allocator.free(src_file_path);
            const dst_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_dir_path, entry.name });
            defer allocator.free(dst_file_path);

            const src_file = try std.fs.cwd().openFile(src_file_path, .{});
            defer src_file.close();
            const dst_file = try std.fs.cwd().createFile(dst_file_path, .{});
            defer dst_file.close();

            const content = try src_file.readToEndAlloc(allocator, 1024 * 1024);
            defer allocator.free(content);
            try dst_file.writeAll(content);
        }
    }
}

/// Copy c_interop directory to cache for C library interop
pub fn copyCInteropDir(allocator: std.mem.Allocator, build_dir: []const u8) !void {
    const src_dir_path = "packages/c_interop";
    const dst_dir_path = try std.fmt.allocPrint(allocator, "{s}/c_interop", .{build_dir});
    defer allocator.free(dst_dir_path);

    // Create destination directory
    std.fs.cwd().makeDir(dst_dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Open source directory - fail loudly if not found
    var src_dir = std.fs.cwd().openDir(src_dir_path, .{ .iterate = true }) catch |err| {
        std.debug.print("ERROR: Failed to open runtime directory '{s}': {any}\n", .{ src_dir_path, err });
        return err;
    };
    defer src_dir.close();

    // Iterate through files and directories
    var iterator = src_dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file) {
            // Copy file
            const src_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_dir_path, entry.name });
            defer allocator.free(src_file_path);
            const dst_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_dir_path, entry.name });
            defer allocator.free(dst_file_path);

            const src_file = try std.fs.cwd().openFile(src_file_path, .{});
            defer src_file.close();
            const dst_file = try std.fs.cwd().createFile(dst_file_path, .{});
            defer dst_file.close();

            const content = try src_file.readToEndAlloc(allocator, 10 * 1024 * 1024);
            defer allocator.free(content);
            try dst_file.writeAll(content);
        } else if (entry.kind == .directory) {
            // Recursively copy subdirectory
            const new_src = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_dir_path, entry.name });
            defer allocator.free(new_src);
            const new_dst = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_dir_path, entry.name });
            try copyDirRecursive(allocator, new_src, new_dst);
        }
    }
}

/// Copy src/utils directory to cache for hashmap_helper, wyhash
pub fn copySrcUtilsDir(allocator: std.mem.Allocator, build_dir: []const u8) !void {
    const src_dir_path = "src/utils";

    // Copy to main build dir and all subdirectories that might need utils/
    // (CPython-mirrored structure - files import ../utils/ or utils/ depending on depth)
    const dst_paths = [_][]const u8{
        try std.fmt.allocPrint(allocator, "{s}/utils", .{build_dir}),
        try std.fmt.allocPrint(allocator, "{s}/Lib/utils", .{build_dir}),
        try std.fmt.allocPrint(allocator, "{s}/Lib/http/utils", .{build_dir}),
        try std.fmt.allocPrint(allocator, "{s}/Lib/json/utils", .{build_dir}),
        try std.fmt.allocPrint(allocator, "{s}/Objects/utils", .{build_dir}),
        try std.fmt.allocPrint(allocator, "{s}/Python/utils", .{build_dir}),
        try std.fmt.allocPrint(allocator, "{s}/Modules/utils", .{build_dir}),
        try std.fmt.allocPrint(allocator, "{s}/runtime/utils", .{build_dir}),
    };
    defer for (dst_paths) |path| allocator.free(path);

    for (dst_paths) |dst_dir_path| {
        // Create destination directory (use makePath to create parent dirs)
        std.fs.cwd().makePath(dst_dir_path) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Copy all .zig files from src/utils
        {
            var src_dir = std.fs.cwd().openDir(src_dir_path, .{ .iterate = true }) catch |err| {
                if (err == error.FileNotFound) continue;
                return err;
            };
            defer src_dir.close();

            var iterator = src_dir.iterate();
            while (try iterator.next()) |entry| {
                if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
                    const src_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_dir_path, entry.name });
                    defer allocator.free(src_file_path);
                    const dst_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_dir_path, entry.name });
                    defer allocator.free(dst_file_path);

                    const src_file = try std.fs.cwd().openFile(src_file_path, .{});
                    defer src_file.close();
                    const dst_file = try std.fs.cwd().createFile(dst_file_path, .{});
                    defer dst_file.close();

                    const content = try src_file.readToEndAlloc(allocator, 1024 * 1024);
                    defer allocator.free(content);
                    try dst_file.writeAll(content);
                }
            }
        }
    }
}

/// Copy regex package to cache for re module
pub fn copyRegexPackage(allocator: std.mem.Allocator, build_dir: []const u8) !void {
    // Copy packages/regex/src/pyregex to cache/regex/src/pyregex
    try copyDirRecursive(allocator, "packages/regex/src/pyregex", try std.fmt.allocPrint(allocator, "{s}/regex/src/pyregex", .{build_dir}));
}

/// Copy tokenizer package to cache for metal0.tokenizer
pub fn copyTokenizerPackage(allocator: std.mem.Allocator, build_dir: []const u8) !void {
    // Copy packages/tokenizer/src to cache/tokenizer/src
    try copyTokenizerDirWithPatching(allocator, "packages/tokenizer/src", try std.fmt.allocPrint(allocator, "{s}/tokenizer/src", .{build_dir}));
}

/// Recursively copy tokenizer directory with import patching
fn copyTokenizerDirWithPatching(allocator: std.mem.Allocator, src_path: []const u8, dst_path: []const u8) !void {
    defer allocator.free(dst_path);

    // Create destination directory
    std.fs.cwd().makePath(dst_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Open source directory
    var src_dir = std.fs.cwd().openDir(src_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer src_dir.close();

    // Iterate through entries
    var iterator = src_dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file) {
            const src_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_path, entry.name });
            defer allocator.free(src_file_path);
            const dst_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_path, entry.name });
            defer allocator.free(dst_file_path);

            const src_file = try std.fs.cwd().openFile(src_file_path, .{});
            defer src_file.close();
            const dst_file = try std.fs.cwd().createFile(dst_file_path, .{});
            defer dst_file.close();

            var content = try src_file.readToEndAlloc(allocator, 10 * 1024 * 1024);

            // Patch imports for .zig files
            if (std.mem.endsWith(u8, entry.name, ".zig")) {
                // Patch @import("json") to relative path from tokenizer/src/
                // json.zig is at cache root level, so from tokenizer/src/ it's ../../json.zig
                content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"json\")", "@import(\"../../json.zig\")");
            }

            try dst_file.writeAll(content);
            allocator.free(content);
        } else if (entry.kind == .directory) {
            const new_src = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_path, entry.name });
            defer allocator.free(new_src);
            const new_dst = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_path, entry.name });
            try copyTokenizerDirWithPatching(allocator, new_src, new_dst);
        }
    }
}

/// Copy h2 package (HTTP/2 client) to cache for http module
pub fn copyH2Package(allocator: std.mem.Allocator, build_dir: []const u8) !void {
    const src_dir_path = "packages/shared/http/h2";
    const dst_dir_path = try std.fmt.allocPrint(allocator, "{s}/h2", .{build_dir});
    defer allocator.free(dst_dir_path);

    // Create destination directory
    std.fs.cwd().makePath(dst_dir_path) catch {};

    // Open source directory
    var src_dir = std.fs.cwd().openDir(src_dir_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer src_dir.close();

    // Copy all .zig files with import patching
    var iterator = src_dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) {
            const src_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_dir_path, entry.name });
            defer allocator.free(src_file_path);
            const dst_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_dir_path, entry.name });
            defer allocator.free(dst_file_path);

            const src_file = try std.fs.cwd().openFile(src_file_path, .{});
            defer src_file.close();
            const dst_file = try std.fs.cwd().createFile(dst_file_path, .{});
            defer dst_file.close();

            var content = try src_file.readToEndAlloc(allocator, 2 * 1024 * 1024);

            // Patch module imports for standalone compilation
            // h2 is in cache/h2/, so it needs to import from parent directory (../)
            content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"gzip\")", "@import(\"../Modules/gzip/gzip.zig\")");
            content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"netpoller\")", "@import(\"../runtime/netpoller.zig\")");
            content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"green_thread\")", "@import(\"../runtime/green_thread.zig\")");

            try dst_file.writeAll(content);
            allocator.free(content);
        }
    }
}

/// Recursively copy directory
pub fn copyDirRecursive(allocator: std.mem.Allocator, src_path: []const u8, dst_path: []const u8) !void {
    defer allocator.free(dst_path);

    // Create destination directory
    std.fs.cwd().makePath(dst_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Open source directory
    var src_dir = std.fs.cwd().openDir(src_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    defer src_dir.close();

    // Iterate through entries
    var iterator = src_dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file) {
            const src_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_path, entry.name });
            defer allocator.free(src_file_path);
            const dst_file_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_path, entry.name });
            defer allocator.free(dst_file_path);

            const src_file = try std.fs.cwd().openFile(src_file_path, .{});
            defer src_file.close();
            const dst_file = try std.fs.cwd().createFile(dst_file_path, .{});
            defer dst_file.close();

            const content = try src_file.readToEndAlloc(allocator, 10 * 1024 * 1024);
            defer allocator.free(content);
            try dst_file.writeAll(content);
        } else if (entry.kind == .directory) {
            const new_src = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_path, entry.name });
            defer allocator.free(new_src);
            const new_dst = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_path, entry.name });
            try copyDirRecursive(allocator, new_src, new_dst);
        }
    }
}
