/// Build directory structure for metal0
///
/// Source-local .metal0/ - each source file's outputs go to .metal0/ in its directory
///
/// tests/cpython/test_bool.py ->
///   tests/cpython/.metal0/test_bool.zig  (generated Zig)
///   tests/cpython/.metal0/test_bool      (binary)
///
/// /path/to/app.py ->
///   /path/to/.metal0/app.zig
///   /path/to/.metal0/app
const std = @import("std");

/// Output directory name (hidden, gitignored)
pub const OUTPUT_DIR = ".metal0";

/// Get the base name without extension from a path
/// e.g., "tests/cpython/test_bool.py" -> "test_bool"
pub fn getBaseName(path: []const u8) []const u8 {
    const basename = std.fs.path.basename(path);
    return if (std.mem.lastIndexOf(u8, basename, ".")) |idx|
        basename[0..idx]
    else
        basename;
}

/// Get .metal0 directory path for a source file
/// e.g., "tests/cpython/test_bool.py" -> "tests/cpython/.metal0"
/// e.g., "app.py" -> ".metal0"
pub fn outputDir(allocator: std.mem.Allocator, source_path: []const u8) ![]const u8 {
    const dir = std.fs.path.dirname(source_path);
    if (dir) |d| {
        return std.fmt.allocPrint(allocator, "{s}/" ++ OUTPUT_DIR, .{d});
    } else {
        return allocator.dupe(u8, OUTPUT_DIR);
    }
}

/// Get path for generated Zig source
/// e.g., "tests/cpython/test_bool.py" -> "tests/cpython/.metal0/test_bool.zig"
pub fn zigPath(allocator: std.mem.Allocator, source_path: []const u8) ![]const u8 {
    const dir = std.fs.path.dirname(source_path);
    const stem = getBaseName(source_path);
    if (dir) |d| {
        return std.fmt.allocPrint(allocator, "{s}/" ++ OUTPUT_DIR ++ "/{s}.zig", .{ d, stem });
    } else {
        return std.fmt.allocPrint(allocator, OUTPUT_DIR ++ "/{s}.zig", .{stem});
    }
}

/// Get path for compiled object file
/// e.g., "tests/cpython/test_bool.py" -> "tests/cpython/.metal0/test_bool.o"
pub fn objectPath(allocator: std.mem.Allocator, source_path: []const u8) ![]const u8 {
    const dir = std.fs.path.dirname(source_path);
    const stem = getBaseName(source_path);
    if (dir) |d| {
        return std.fmt.allocPrint(allocator, "{s}/" ++ OUTPUT_DIR ++ "/{s}.o", .{ d, stem });
    } else {
        return std.fmt.allocPrint(allocator, OUTPUT_DIR ++ "/{s}.o", .{stem});
    }
}

/// Get path for hash file (for incremental build detection)
/// e.g., "tests/cpython/test_bool.py" -> "tests/cpython/.metal0/test_bool.hash"
pub fn hashPath(allocator: std.mem.Allocator, source_path: []const u8) ![]const u8 {
    const dir = std.fs.path.dirname(source_path);
    const stem = getBaseName(source_path);
    if (dir) |d| {
        return std.fmt.allocPrint(allocator, "{s}/" ++ OUTPUT_DIR ++ "/{s}.hash", .{ d, stem });
    } else {
        return std.fmt.allocPrint(allocator, OUTPUT_DIR ++ "/{s}.hash", .{stem});
    }
}

/// Get path for final binary
/// e.g., "tests/cpython/test_bool.py" -> "tests/cpython/.metal0/test_bool"
pub fn binaryPath(allocator: std.mem.Allocator, source_path: []const u8) ![]const u8 {
    const dir = std.fs.path.dirname(source_path);
    const stem = getBaseName(source_path);
    if (dir) |d| {
        return std.fmt.allocPrint(allocator, "{s}/" ++ OUTPUT_DIR ++ "/{s}", .{ d, stem });
    } else {
        return std.fmt.allocPrint(allocator, OUTPUT_DIR ++ "/{s}", .{stem});
    }
}

/// Get path for static archive in source directory
/// e.g., "tests/cpython/test_bool.py" -> "tests/cpython/.metal0/lib/libruntime.a"
pub fn archivePath(allocator: std.mem.Allocator, source_path: []const u8, name: []const u8) ![]const u8 {
    const dir = std.fs.path.dirname(source_path);
    if (dir) |d| {
        return std.fmt.allocPrint(allocator, "{s}/" ++ OUTPUT_DIR ++ "/lib/lib{s}.a", .{ d, name });
    } else {
        return std.fmt.allocPrint(allocator, OUTPUT_DIR ++ "/lib/lib{s}.a", .{name});
    }
}

/// Ensure .metal0 directory exists for a source file
pub fn ensureOutputDir(allocator: std.mem.Allocator, source_path: []const u8) ![]const u8 {
    const out_dir = try outputDir(allocator, source_path);
    std.fs.cwd().makePath(out_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    return out_dir;
}

/// Ensure parent directories exist for a path
pub fn ensureParentDir(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |parent| {
        std.fs.cwd().makePath(parent) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }
}

// ============================================================================
// Legacy constants for backward compatibility during migration
// DEPRECATED: Use source-relative functions above
// ============================================================================

/// Legacy root (for files that still use hardcoded paths)
pub const ROOT = ".metal0";
pub const CACHE = ROOT;
pub const LIB = ROOT ++ "/lib";
pub const BIN = ROOT;
pub const RUNTIME = ROOT ++ "/runtime";
pub const PACKAGES = ROOT ++ "/packages";
pub const SRC = ROOT ++ "/src";

/// Legacy init (creates .metal0 in CWD)
pub fn init() !void {
    inline for ([_][]const u8{ ROOT, LIB, RUNTIME }) |dir| {
        std.fs.cwd().makeDir(dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }
}

/// Legacy: get build dir for backward compatibility
pub fn getBuildDir() []const u8 {
    return ROOT;
}

/// Legacy: runtime directory
pub fn runtimeDir() []const u8 {
    return RUNTIME;
}

// ============================================================================
// Clean functionality - recursively find and remove .metal0 directories
// ============================================================================

/// Recursively find and remove all .metal0 directories under a path
/// Returns count of directories removed
pub fn cleanRecursive(allocator: std.mem.Allocator, root_path: []const u8) !usize {
    var count: usize = 0;
    var dirs_to_remove: std.ArrayList([]const u8) = .{};
    defer {
        for (dirs_to_remove.items) |p| allocator.free(p);
        dirs_to_remove.deinit(allocator);
    }

    // Walk directory tree to find .metal0 directories
    try findMetal0Dirs(allocator, root_path, &dirs_to_remove);

    // Remove them (in reverse order to handle nested cases)
    var i = dirs_to_remove.items.len;
    while (i > 0) {
        i -= 1;
        const dir_path = dirs_to_remove.items[i];
        std.fs.cwd().deleteTree(dir_path) catch |err| {
            std.debug.print("Warning: failed to remove {s}: {any}\n", .{ dir_path, err });
            continue;
        };
        count += 1;
    }

    return count;
}

/// Helper: recursively find all .metal0 directories
fn findMetal0Dirs(allocator: std.mem.Allocator, path: []const u8, result: *std.ArrayList([]const u8)) !void {
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;

        // Check if this is a .metal0 directory
        if (std.mem.eql(u8, entry.name, OUTPUT_DIR)) {
            const full_path = if (std.mem.eql(u8, path, "."))
                try allocator.dupe(u8, OUTPUT_DIR)
            else
                try std.fmt.allocPrint(allocator, "{s}/{s}", .{ path, OUTPUT_DIR });
            try result.append(allocator, full_path);
            // Don't recurse into .metal0 directories
            continue;
        }

        // Skip hidden directories and common non-source directories
        if (entry.name[0] == '.' or
            std.mem.eql(u8, entry.name, "node_modules") or
            std.mem.eql(u8, entry.name, "zig-out") or
            std.mem.eql(u8, entry.name, "zig-cache") or
            std.mem.eql(u8, entry.name, ".zig-cache"))
        {
            continue;
        }

        // Recurse into subdirectory
        const sub_path = if (std.mem.eql(u8, path, "."))
            try allocator.dupe(u8, entry.name)
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ path, entry.name });
        defer allocator.free(sub_path);
        try findMetal0Dirs(allocator, sub_path, result);
    }
}

/// Clean .metal0 directory for a specific source file
pub fn cleanForSource(source_path: []const u8) !void {
    const dir = std.fs.path.dirname(source_path);
    const target = if (dir) |d|
        d ++ "/" ++ OUTPUT_DIR
    else
        OUTPUT_DIR;

    std.fs.cwd().deleteTree(target) catch |err| {
        if (err != error.FileNotFound) return err;
    };
}
