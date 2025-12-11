/// Output path handling for compiled files
const std = @import("std");
const utils = @import("../utils.zig");

/// Binary output directory (.metal0/bin/)
/// Industry standard: all build outputs go to a dedicated directory
pub fn getPlatformDir(allocator: std.mem.Allocator) ![]const u8 {
    _ = allocator;
    return ".metal0/bin";
}

/// Ensure platform build directory exists
pub fn ensurePlatformDir(allocator: std.mem.Allocator) ![]const u8 {
    const platform_dir = try getPlatformDir(allocator);
    std.fs.cwd().makePath(platform_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
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

/// Get path with extension stripped (preserves directory structure)
/// e.g., "tests/cpython/test_bool.py" -> "tests/cpython/test_bool"
pub fn getPathNoExt(path: []const u8) []const u8 {
    if (std.mem.lastIndexOf(u8, path, ".")) |idx| {
        return path[0..idx];
    }
    return path;
}

/// Get module output path for a compiled .so file (mirrors source path)
pub fn getModuleOutputPath(allocator: std.mem.Allocator, module_path: []const u8) ![]const u8 {
    const platform_dir = try ensurePlatformDir(allocator);
    const path_no_ext = getPathNoExt(module_path);

    const output = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}.cpython-312-darwin.so",
        .{ platform_dir, path_no_ext },
    );

    // Ensure parent directory exists
    if (std.fs.path.dirname(output)) |parent| {
        std.fs.cwd().makePath(parent) catch {};
    }
    return output;
}

/// Determine output path for notebook compilation
pub fn getNotebookOutputPath(allocator: std.mem.Allocator, input_file: []const u8, output_file: ?[]const u8, binary: bool) ![]const u8 {
    const platform_dir = try ensurePlatformDir(allocator);

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

/// Determine output path for file compilation (mirrors source path)
pub fn getFileOutputPath(allocator: std.mem.Allocator, input_file: []const u8, output_file: ?[]const u8, binary: bool) ![]const u8 {
    const platform_dir = try ensurePlatformDir(allocator);

    // If output path specified, use it but ensure it's in platform_dir
    if (output_file) |path| {
        // If path is absolute or contains directory, use as-is
        if (std.fs.path.isAbsolute(path) or std.mem.indexOf(u8, path, "/") != null) {
            return try allocator.dupe(u8, path);
        }
        // Otherwise, put in platform_dir
        return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ platform_dir, path });
    }

    // Mirror source path structure to avoid conflicts
    const path_no_ext = getPathNoExt(input_file);

    const output = if (binary)
        try std.fmt.allocPrint(allocator, "{s}/{s}", .{ platform_dir, path_no_ext })
    else
        try std.fmt.allocPrint(allocator, "{s}/{s}.cpython-312-darwin.so", .{ platform_dir, path_no_ext });

    // Ensure parent directory exists
    if (std.fs.path.dirname(output)) |parent| {
        std.fs.cwd().makePath(parent) catch {};
    }
    return output;
}

/// Get WASM output path
pub fn getWasmOutputPath(allocator: std.mem.Allocator, input_file: []const u8, output_file: ?[]const u8) ![]const u8 {
    if (output_file) |path| {
        return try allocator.dupe(u8, path);
    }

    const platform_dir = try ensurePlatformDir(allocator);
    const name_no_ext = getBaseName(input_file);
    return try std.fmt.allocPrint(allocator, "{s}/{s}.wasm", .{ platform_dir, name_no_ext });
}
