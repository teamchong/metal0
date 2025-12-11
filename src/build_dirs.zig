/// Build directory structure for metal0
///
/// .metal0/
/// ├── cache/      # Incremental build cache (.zig, .o, .hash)
/// ├── lib/        # Static archives (.a)
/// ├── bin/        # Final binaries
/// └── runtime/    # Cached runtime files
const std = @import("std");

/// Root build directory
pub const ROOT = ".metal0";

/// Subdirectories
pub const CACHE = ROOT ++ "/cache";
pub const LIB = ROOT ++ "/lib";
pub const BIN = ROOT ++ "/bin";
pub const RUNTIME = ROOT ++ "/runtime";

/// Mirrored source structure in cache (preserves relative imports)
pub const PACKAGES = CACHE ++ "/packages";
pub const SRC = CACHE ++ "/src";

/// Initialize build directory structure
pub fn init() !void {
    // Create all directories
    inline for ([_][]const u8{ ROOT, CACHE, LIB, BIN, RUNTIME, PACKAGES, SRC }) |dir| {
        std.fs.cwd().makeDir(dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }
}

/// Get path for generated Zig source (mirrors source path to avoid conflicts)
/// e.g., "tests/cpython/test_bool.py" -> ".metal0/cache/tests/cpython/test_bool.zig"
pub fn zigPath(allocator: std.mem.Allocator, source_path: []const u8) ![]const u8 {
    // Remove .py extension and add .zig
    const stem = if (std.mem.endsWith(u8, source_path, ".py"))
        source_path[0 .. source_path.len - 3]
    else
        source_path;
    return std.fmt.allocPrint(allocator, CACHE ++ "/{s}.zig", .{stem});
}

/// Get path for compiled object file (mirrors source path)
pub fn objectPath(allocator: std.mem.Allocator, source_path: []const u8) ![]const u8 {
    const stem = if (std.mem.endsWith(u8, source_path, ".py"))
        source_path[0 .. source_path.len - 3]
    else if (std.mem.endsWith(u8, source_path, ".zig"))
        source_path[0 .. source_path.len - 4]
    else
        source_path;
    return std.fmt.allocPrint(allocator, CACHE ++ "/{s}.o", .{stem});
}

/// Get path for hash file (for incremental build detection)
pub fn hashPath(allocator: std.mem.Allocator, source_path: []const u8) ![]const u8 {
    const stem = if (std.mem.endsWith(u8, source_path, ".py"))
        source_path[0 .. source_path.len - 3]
    else
        source_path;
    return std.fmt.allocPrint(allocator, CACHE ++ "/{s}.hash", .{stem});
}

/// Get path for static archive
pub fn archivePath(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, LIB ++ "/lib{s}.a", .{name});
}

/// Get path for final binary (mirrors source path)
/// e.g., "tests/cpython/test_bool.py" -> ".metal0/bin/tests/cpython/test_bool"
pub fn binaryPath(allocator: std.mem.Allocator, source_path: []const u8) ![]const u8 {
    const stem = if (std.mem.endsWith(u8, source_path, ".py"))
        source_path[0 .. source_path.len - 3]
    else
        source_path;
    return std.fmt.allocPrint(allocator, BIN ++ "/{s}", .{stem});
}

/// Ensure parent directories exist for a path
pub fn ensureParentDir(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| {
        std.fs.cwd().makePath(parent) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }
}

/// Get runtime directory (for cached runtime files)
pub fn runtimeDir() []const u8 {
    return RUNTIME;
}

/// Legacy: get build dir for backward compatibility
/// DEPRECATED: Use specific functions above (cacheDir, binDir, libDir, runtimeDir)
pub fn getBuildDir() []const u8 {
    return CACHE;
}
