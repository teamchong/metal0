/// Build directory structure for metal0
///
/// Two-tier build structure:
/// 1. Project-local <project>/.metal0/ - codegen, binaries (project-specific)
/// 2. Global ~/.metal0/ - shared runtime libraries (reused across projects)
///
/// Project root detection (priority order):
/// 1. pyproject.toml (modern Python standard)
/// 2. setup.py or setup.cfg (legacy Python)
/// 3. .git/ directory (VCS fallback)
///
/// Example:
/// myproject/
/// ├── pyproject.toml          # Project root marker
/// ├── src/app.py
/// └── .metal0/                # Project build artifacts
///     ├── src/app.zig         # Generated Zig
///     ├── src/app             # Binary
///     └── lib/libruntime.a    # Symlink to ~/.metal0/runtime/
///
/// ~/.metal0/
/// └── runtime/
///     └── libruntime-{hash}.a # Content-addressed, shared across projects
const std = @import("std");

/// Output directory name (hidden, gitignored)
pub const OUTPUT_DIR = ".metal0";

/// Global cache directory name
pub const GLOBAL_CACHE = ".metal0";

// ============================================================================
// Project Root Detection
// ============================================================================

/// Project root marker type
pub const RootMarker = enum {
    pyproject, // pyproject.toml (highest priority)
    setup_py, // setup.py
    setup_cfg, // setup.cfg
    git, // .git/ directory (lowest priority)
};

/// Project root detection result
pub const ProjectRoot = struct {
    path: []const u8,
    marker: RootMarker,
};

/// Find project root by walking up from source file
/// Checks markers in priority order: pyproject.toml > setup.py > setup.cfg > .git
/// Returns relative path "." if project root is CWD, preserving relative path structure
pub fn findProjectRoot(allocator: std.mem.Allocator, start_path: []const u8) !?ProjectRoot {
    // Get CWD for comparison
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    // Get absolute path for the start location
    const abs_start = if (std.fs.path.isAbsolute(start_path))
        try allocator.dupe(u8, start_path)
    else
        try std.fs.path.join(allocator, &.{ cwd, start_path });

    // Start from directory containing the file (or the directory itself)
    var current = try allocator.dupe(u8, std.fs.path.dirname(abs_start) orelse abs_start);
    allocator.free(abs_start); // Don't need abs_start anymore

    while (true) {
        // Check markers in priority order
        const markers = [_]struct { name: []const u8, marker: RootMarker, is_dir: bool }{
            .{ .name = "pyproject.toml", .marker = .pyproject, .is_dir = false },
            .{ .name = "setup.py", .marker = .setup_py, .is_dir = false },
            .{ .name = "setup.cfg", .marker = .setup_cfg, .is_dir = false },
            .{ .name = ".git", .marker = .git, .is_dir = true },
        };

        for (markers) |m| {
            const check_path = try std.fs.path.join(allocator, &.{ current, m.name });
            defer allocator.free(check_path);

            const exists = if (m.is_dir)
                dirExists(check_path)
            else
                fileExists(check_path);

            if (exists) {
                // If project root is CWD, return "." for relative paths
                const result_path = if (std.mem.eql(u8, current, cwd))
                    try allocator.dupe(u8, ".")
                else
                    current;

                // Free current if we're returning "."
                if (std.mem.eql(u8, current, cwd)) {
                    allocator.free(current);
                }

                return ProjectRoot{
                    .path = result_path,
                    .marker = m.marker,
                };
            }
        }

        // Walk up to parent directory
        const parent = std.fs.path.dirname(current);
        if (parent == null or std.mem.eql(u8, parent.?, current)) {
            // Reached filesystem root - free current and return null
            allocator.free(current);
            return null;
        }

        // Duplicate parent BEFORE freeing current (parent is a slice into current)
        const new_current = try allocator.dupe(u8, parent.?);
        allocator.free(current);
        current = new_current;
    }
}

/// Check if file exists
fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Check if directory exists
fn dirExists(path: []const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}

// ============================================================================
// Global Cache (~/.metal0/)
// ============================================================================

/// Get global cache directory path (~/.metal0/)
pub fn globalCacheDir(allocator: std.mem.Allocator) ![]const u8 {
    const builtin = @import("builtin");
    const home = if (comptime builtin.os.tag == .windows)
        std.process.getEnvVarOwned(allocator, "USERPROFILE") catch "C:\\Users\\Public"
    else
        std.posix.getenv("HOME") orelse "/tmp";

    defer if (comptime builtin.os.tag == .windows) allocator.free(home);
    return std.fmt.allocPrint(allocator, "{s}/" ++ GLOBAL_CACHE, .{home});
}

/// Get global runtime directory (~/.metal0/runtime/)
pub fn globalRuntimeDir(allocator: std.mem.Allocator) ![]const u8 {
    const builtin = @import("builtin");
    const home = if (comptime builtin.os.tag == .windows)
        std.process.getEnvVarOwned(allocator, "USERPROFILE") catch "C:\\Users\\Public"
    else
        std.posix.getenv("HOME") orelse "/tmp";

    defer if (comptime builtin.os.tag == .windows) allocator.free(home);
    return std.fmt.allocPrint(allocator, "{s}/" ++ GLOBAL_CACHE ++ "/runtime", .{home});
}

/// Compute SHA256 hash of runtime source directory
/// Uses 1MB prefix hash optimization from zell (100-1000x faster for large dirs)
/// Returns hex string suitable for cache key
pub fn computeRuntimeHash(allocator: std.mem.Allocator) ![]const u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});

    // Hash key files that affect runtime behavior
    const runtime_files = [_][]const u8{
        "packages/runtime/src/runtime.zig",
        "packages/runtime/src/Objects/object.zig",
        "packages/runtime/src/runtime/builtins.zig",
        "build.zig", // Build config affects output
    };

    for (runtime_files) |file_path| {
        const file = std.fs.cwd().openFile(file_path, .{}) catch continue;
        defer file.close();

        // Read first 64KB (enough for headers + key functions)
        const read_size = 64 * 1024;
        var buffer: [read_size]u8 = undefined;
        const bytes_read = file.readAll(&buffer) catch continue;

        hasher.update(buffer[0..bytes_read]);
    }

    var hash_bytes: [32]u8 = undefined;
    hasher.final(&hash_bytes);

    // Convert to hex string
    const hex = try allocator.alloc(u8, 64);
    _ = std.fmt.bufPrint(hex, "{s}", .{std.fmt.fmtSliceHexLower(&hash_bytes)}) catch unreachable;
    return hex;
}

/// Get content-addressed runtime library path
/// e.g., ~/.metal0/runtime/libruntime-{hash}.a
pub fn globalRuntimePath(allocator: std.mem.Allocator, hash: []const u8) ![]const u8 {
    const builtin = @import("builtin");
    const home = if (comptime builtin.os.tag == .windows)
        std.process.getEnvVarOwned(allocator, "USERPROFILE") catch "C:\\Users\\Public"
    else
        std.posix.getenv("HOME") orelse "/tmp";

    defer if (comptime builtin.os.tag == .windows) allocator.free(home);
    return std.fmt.allocPrint(allocator, "{s}/" ++ GLOBAL_CACHE ++ "/runtime/libruntime-{s}.a", .{ home, hash });
}

/// Ensure global cache directories exist
pub fn ensureGlobalCacheDir(allocator: std.mem.Allocator) !void {
    const cache_dir = try globalCacheDir(allocator);
    defer allocator.free(cache_dir);
    std.fs.cwd().makePath(cache_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    const runtime_dir = try globalRuntimeDir(allocator);
    defer allocator.free(runtime_dir);
    std.fs.cwd().makePath(runtime_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
}

// ============================================================================
// Project-Local Paths (<project>/.metal0/)
// ============================================================================

/// Get project .metal0 directory path
/// e.g., "myproject" -> "myproject/.metal0"
pub fn projectOutputDir(allocator: std.mem.Allocator, project_root: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}/" ++ OUTPUT_DIR, .{project_root});
}

/// Get relative path from project root to source file
/// e.g., project_root="myproject", source_path="myproject/src/app.py" -> "src/app.py"
pub fn getRelativePath(allocator: std.mem.Allocator, project_root: []const u8, source_path: []const u8) ![]const u8 {
    // If source_path starts with project_root, strip it
    if (std.mem.startsWith(u8, source_path, project_root)) {
        var rel = source_path[project_root.len..];
        // Skip leading slash
        if (rel.len > 0 and rel[0] == '/') {
            rel = rel[1..];
        }
        return allocator.dupe(u8, rel);
    }
    return allocator.dupe(u8, source_path);
}

/// Subdirectory for generated code (avoids conflicts with cache/, lib/, etc.)
/// Using "gen" is industry standard for generated files (Android, protobuf, etc.)
pub const SRC_SUBDIR = "gen";

/// Get path for generated Zig source (project-relative)
/// e.g., project_root="myproject", source_path="myproject/src/app.py"
///       -> "myproject/.metal0/gen/src/app.zig"
/// e.g., project_root=".", source_path="tests/cpython/test_bool.py"
///       -> ".metal0/gen/tests/cpython/test_bool.zig"
pub fn projectZigPath(allocator: std.mem.Allocator, project_root: []const u8, source_path: []const u8) ![]const u8 {
    const rel_path = try getRelativePath(allocator, project_root, source_path);
    defer allocator.free(rel_path);
    const stem = getPathNoExt(rel_path);

    // Handle "." project root - don't prefix with "./"
    if (std.mem.eql(u8, project_root, ".")) {
        return std.fmt.allocPrint(allocator, OUTPUT_DIR ++ "/" ++ SRC_SUBDIR ++ "/{s}.zig", .{stem});
    }
    return std.fmt.allocPrint(allocator, "{s}/" ++ OUTPUT_DIR ++ "/" ++ SRC_SUBDIR ++ "/{s}.zig", .{ project_root, stem });
}

/// Get path for binary (project-relative)
/// e.g., project_root="myproject", source_path="myproject/src/app.py"
///       -> "myproject/.metal0/gen/src/app"
/// e.g., project_root=".", source_path="tests/cpython/test_bool.py"
///       -> ".metal0/gen/tests/cpython/test_bool"
pub fn projectBinaryPath(allocator: std.mem.Allocator, project_root: []const u8, source_path: []const u8) ![]const u8 {
    const rel_path = try getRelativePath(allocator, project_root, source_path);
    defer allocator.free(rel_path);
    const stem = getPathNoExt(rel_path);

    // Handle "." project root - don't prefix with "./"
    if (std.mem.eql(u8, project_root, ".")) {
        return std.fmt.allocPrint(allocator, OUTPUT_DIR ++ "/" ++ SRC_SUBDIR ++ "/{s}", .{stem});
    }
    return std.fmt.allocPrint(allocator, "{s}/" ++ OUTPUT_DIR ++ "/" ++ SRC_SUBDIR ++ "/{s}", .{ project_root, stem });
}

/// Get path without extension (preserves directory structure)
/// e.g., "src/app.py" -> "src/app"
fn getPathNoExt(path: []const u8) []const u8 {
    if (std.mem.lastIndexOf(u8, path, ".")) |idx| {
        // Make sure it's after the last slash
        if (std.mem.lastIndexOf(u8, path, "/")) |slash_idx| {
            if (idx > slash_idx) return path[0..idx];
        } else {
            return path[0..idx];
        }
    }
    return path;
}

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

/// Compute relative import path from one Zig file to another
/// Both paths should be within the .metal0 directory structure
/// e.g., from ".metal0/gen/tests/numpy/test_numpy_version.zig"
///       to   ".metal0/gen/venv/lib/python3.12/site-packages/numpy/__init__.zig"
///       -> "../../venv/lib/python3.12/site-packages/numpy/__init__.zig"
pub fn relativeImportPath(allocator: std.mem.Allocator, from_path: []const u8, to_path: []const u8) ![]const u8 {
    // Get the directory containing the from_path file
    const from_dir = std.fs.path.dirname(from_path) orelse ".";

    // Split both paths into components
    var from_components = std.ArrayList([]const u8){};
    defer from_components.deinit(allocator);
    var to_components = std.ArrayList([]const u8){};
    defer to_components.deinit(allocator);

    // Parse from_dir components
    var from_iter = std.mem.splitScalar(u8, from_dir, '/');
    while (from_iter.next()) |component| {
        if (component.len > 0) {
            try from_components.append(allocator, component);
        }
    }

    // Parse to_path components
    var to_iter = std.mem.splitScalar(u8, to_path, '/');
    while (to_iter.next()) |component| {
        if (component.len > 0) {
            try to_components.append(allocator, component);
        }
    }

    // Find common prefix length
    var common_prefix: usize = 0;
    while (common_prefix < from_components.items.len and
        common_prefix < to_components.items.len and
        std.mem.eql(u8, from_components.items[common_prefix], to_components.items[common_prefix]))
    {
        common_prefix += 1;
    }

    // Build the relative path
    var result = std.ArrayList(u8){};
    defer result.deinit(allocator);

    // Add ".." for each remaining component in from_dir
    const levels_up = from_components.items.len - common_prefix;
    for (0..levels_up) |_| {
        if (result.items.len > 0) {
            try result.append(allocator, '/');
        }
        try result.appendSlice(allocator, "..");
    }

    // Add remaining components from to_path
    for (to_components.items[common_prefix..]) |component| {
        if (result.items.len > 0) {
            try result.append(allocator, '/');
        }
        try result.appendSlice(allocator, component);
    }

    // If no relative path needed (same directory), use "./"
    if (result.items.len == 0) {
        const basename = std.fs.path.basename(to_path);
        return std.fmt.allocPrint(allocator, "./{s}", .{basename});
    }

    return allocator.dupe(u8, result.items);
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
