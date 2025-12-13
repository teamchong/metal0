/// Output path handling for compiled files
/// Uses source-relative .metal0/ directories
const std = @import("std");
const utils = @import("../utils.zig");
const build_dirs = @import("../../build_dirs.zig");

/// Extract base name without extension from a path
pub fn getBaseName(path: []const u8) []const u8 {
    return build_dirs.getBaseName(path);
}

/// Get path with extension stripped (preserves directory structure)
/// e.g., "tests/cpython/test_bool.py" -> "tests/cpython/test_bool"
pub fn getPathNoExt(path: []const u8) []const u8 {
    if (std.mem.lastIndexOf(u8, path, ".")) |idx| {
        return path[0..idx];
    }
    return path;
}

/// Ensure output directory exists for a source file
/// Returns the .metal0 directory path
pub fn ensureOutputDir(allocator: std.mem.Allocator, source_path: []const u8) ![]const u8 {
    return build_dirs.ensureOutputDir(allocator, source_path);
}

/// Get module output path for a compiled .so file
/// e.g., "tests/cpython/test_bool.py" -> "tests/cpython/.metal0/test_bool.cpython-312-darwin.so"
pub fn getModuleOutputPath(allocator: std.mem.Allocator, module_path: []const u8) ![]const u8 {
    const out_dir = try ensureOutputDir(allocator, module_path);
    defer allocator.free(out_dir);
    const name = getBaseName(module_path);

    const output = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}.cpython-312-darwin.so",
        .{ out_dir, name },
    );

    return output;
}

/// Determine output path for notebook compilation
pub fn getNotebookOutputPath(allocator: std.mem.Allocator, input_file: []const u8, output_file: ?[]const u8, binary: bool) ![]const u8 {
    // If output path specified, use as-is
    if (output_file) |path| {
        return try allocator.dupe(u8, path);
    }

    const out_dir = try ensureOutputDir(allocator, input_file);
    defer allocator.free(out_dir);
    const name = getBaseName(input_file);

    if (binary) {
        return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ out_dir, name });
    } else {
        return try std.fmt.allocPrint(allocator, "{s}/{s}.cpython-312-darwin.so", .{ out_dir, name });
    }
}

/// Determine output path for file compilation
/// e.g., "tests/cpython/test_bool.py" -> "tests/cpython/.metal0/test_bool"
pub fn getFileOutputPath(allocator: std.mem.Allocator, input_file: []const u8, output_file: ?[]const u8, binary: bool) ![]const u8 {
    // If output path specified, use as-is
    if (output_file) |path| {
        return try allocator.dupe(u8, path);
    }

    return if (binary)
        try build_dirs.binaryPath(allocator, input_file)
    else
        try getModuleOutputPath(allocator, input_file);
}

/// Get WASM output path
pub fn getWasmOutputPath(allocator: std.mem.Allocator, input_file: []const u8, output_file: ?[]const u8) ![]const u8 {
    if (output_file) |path| {
        return try allocator.dupe(u8, path);
    }

    const out_dir = try ensureOutputDir(allocator, input_file);
    defer allocator.free(out_dir);
    const name = getBaseName(input_file);
    return try std.fmt.allocPrint(allocator, "{s}/{s}.wasm", .{ out_dir, name });
}

// ============================================================================
// Legacy functions for backward compatibility
// ============================================================================

/// Legacy: Get platform directory (uses CWD/.metal0)
pub fn getPlatformDir(allocator: std.mem.Allocator) ![]const u8 {
    _ = allocator;
    return build_dirs.ROOT;
}

/// Legacy: Ensure platform directory exists
pub fn ensurePlatformDir(allocator: std.mem.Allocator) ![]const u8 {
    _ = allocator;
    std.fs.cwd().makePath(build_dirs.ROOT) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };
    return build_dirs.ROOT;
}
