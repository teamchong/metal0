/// Output path handling for compiled files
const std = @import("std");
const utils = @import("../utils.zig");

/// Platform directory name (e.g., "build/lib.macosx-11.0-arm64")
pub fn getPlatformDir(allocator: std.mem.Allocator) ![]const u8 {
    const arch = utils.getArch();
    return try std.fmt.allocPrint(allocator, "build/lib.macosx-11.0-{s}", .{arch});
}

/// Ensure platform build directory exists
pub fn ensurePlatformDir(allocator: std.mem.Allocator) ![]const u8 {
    const platform_dir = try getPlatformDir(allocator);
    std.fs.cwd().makePath(platform_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            allocator.free(platform_dir);
            return err;
        }
    };
    return platform_dir;
}

/// Extract base name without extension from a path
pub fn getBaseName(path: []const u8) []const u8 {
    const basename = std.fs.path.basename(path);
    return if (std.mem.lastIndexOf(u8, basename, ".")) |idx|
        basename[0..idx]
    else
        basename;
}

/// Get module output path for a compiled .so file
pub fn getModuleOutputPath(allocator: std.mem.Allocator, module_path: []const u8) ![]const u8 {
    const platform_dir = try ensurePlatformDir(allocator);
    defer allocator.free(platform_dir);

    const name_no_ext = getBaseName(module_path);

    return try std.fmt.allocPrint(
        allocator,
        "{s}/{s}.cpython-312-darwin.so",
        .{ platform_dir, name_no_ext },
    );
}

/// Determine output path for notebook compilation
pub fn getNotebookOutputPath(allocator: std.mem.Allocator, input_file: []const u8, output_file: ?[]const u8, binary: bool) ![]const u8 {
    const platform_dir = try ensurePlatformDir(allocator);
    defer allocator.free(platform_dir);

    // If output path specified, use it but ensure it's in platform_dir
    if (output_file) |path| {
        // If path is absolute or contains directory, use as-is
        if (std.fs.path.isAbsolute(path) or std.mem.indexOf(u8, path, "/") != null) {
            return try allocator.dupe(u8, path);
        }
        // Otherwise, put in platform_dir
        return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ platform_dir, path });
    }

    const name_no_ext = getBaseName(input_file);

    if (binary) {
        return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ platform_dir, name_no_ext });
    } else {
        return try std.fmt.allocPrint(allocator, "{s}/{s}.cpython-312-darwin.so", .{ platform_dir, name_no_ext });
    }
}

/// Determine output path for file compilation
pub fn getFileOutputPath(allocator: std.mem.Allocator, input_file: []const u8, output_file: ?[]const u8, binary: bool) ![]const u8 {
    const platform_dir = try ensurePlatformDir(allocator);
    defer allocator.free(platform_dir);

    // If output path specified, use it but ensure it's in platform_dir
    if (output_file) |path| {
        // If path is absolute or contains directory, use as-is
        if (std.fs.path.isAbsolute(path) or std.mem.indexOf(u8, path, "/") != null) {
            return try allocator.dupe(u8, path);
        }
        // Otherwise, put in platform_dir
        return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ platform_dir, path });
    }

    const name_no_ext = getBaseName(input_file);

    if (binary) {
        return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ platform_dir, name_no_ext });
    } else {
        return try std.fmt.allocPrint(allocator, "{s}/{s}.cpython-312-darwin.so", .{ platform_dir, name_no_ext });
    }
}

/// Get WASM output path
pub fn getWasmOutputPath(allocator: std.mem.Allocator, input_file: []const u8, output_file: ?[]const u8) ![]const u8 {
    if (output_file) |path| {
        return try allocator.dupe(u8, path);
    }

    const name_no_ext = getBaseName(input_file);
    return try std.fmt.allocPrint(allocator, "{s}.wasm", .{name_no_ext});
}
