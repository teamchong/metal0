const std = @import("std");

/// Copy a runtime subdirectory recursively to .build
pub fn copyRuntimeDir(allocator: std.mem.Allocator, dir_name: []const u8, build_dir: []const u8) !void {
    const src_dir_path = try std.fmt.allocPrint(allocator, "packages/runtime/src/{s}", .{dir_name});
    defer allocator.free(src_dir_path);
    const dst_dir_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ build_dir, dir_name });
    defer allocator.free(dst_dir_path);

    // Create destination directory
    std.fs.cwd().makeDir(dst_dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Open source directory
    var src_dir = std.fs.cwd().openDir(src_dir_path, .{ .iterate = true }) catch |err| {
        // If directory doesn't exist, that's okay - just skip it
        if (err == error.FileNotFound) return;
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

            // Patch relative utils imports to use local utils/ directory
            // Files at different depths need different patterns patched
            if (std.mem.endsWith(u8, entry.name, ".zig")) {
                content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"../../../../src/utils/", "@import(\"../utils/");
                content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"../../../src/utils/", "@import(\"utils/");
                content = try std.mem.replaceOwned(u8, allocator, content, "@import(\"../../src/utils/", "@import(\"utils/");
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

/// Copy c_interop directory to .build for C library interop
pub fn copyCInteropDir(allocator: std.mem.Allocator, build_dir: []const u8) !void {
    const src_dir_path = "packages/c_interop";
    const dst_dir_path = try std.fmt.allocPrint(allocator, "{s}/c_interop", .{build_dir});
    defer allocator.free(dst_dir_path);

    // Create destination directory
    std.fs.cwd().makeDir(dst_dir_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Open source directory
    var src_dir = std.fs.cwd().openDir(src_dir_path, .{ .iterate = true }) catch |err| {
        // If directory doesn't exist, that's okay - just skip it
        if (err == error.FileNotFound) return;
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

/// Copy src/utils directory to .build for hashmap_helper, wyhash
pub fn copySrcUtilsDir(allocator: std.mem.Allocator, build_dir: []const u8) !void {
    const src_dir_path = "src/utils";

    // Copy to main build dir
    const dst_paths = [_][]const u8{
        try std.fmt.allocPrint(allocator, "{s}/utils", .{build_dir}),
        try std.fmt.allocPrint(allocator, "{s}/http/utils", .{build_dir}),
        try std.fmt.allocPrint(allocator, "{s}/json/utils", .{build_dir}),
    };
    defer for (dst_paths) |path| allocator.free(path);

    for (dst_paths) |dst_dir_path| {
        // Create destination directory
        std.fs.cwd().makeDir(dst_dir_path) catch |err| {
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

/// Copy regex package to .build for re module
pub fn copyRegexPackage(allocator: std.mem.Allocator, build_dir: []const u8) !void {
    // Copy packages/regex/src/pyregex to .build/regex/src/pyregex
    try copyDirRecursive(allocator, "packages/regex/src/pyregex", try std.fmt.allocPrint(allocator, "{s}/regex/src/pyregex", .{build_dir}));
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
