//! test.test_module.test_path - Module path testing
//! Tests for Python's module path handling and sys.path
//! Reference: CPython Lib/test/test_importlib/test_path.py

const std = @import("std");
const builtin = @import("builtin");
const importlib = @import("../../importlib.zig");

// ============================================================================
// Types
// ============================================================================

pub const ModuleSpec = importlib.ModuleSpec;

// ============================================================================
// Path Constants
// ============================================================================

/// Path separator for current platform
pub const PATH_SEP: u8 = if (builtin.os.tag == .windows) '\\' else '/';

/// Path list separator (like PATH environment variable)
pub const PATH_LIST_SEP: u8 = if (builtin.os.tag == .windows) ';' else ':';

/// Python source file extension
pub const PY_EXT = ".py";

/// Bytecode file extension
pub const PYC_EXT = ".pyc";

/// Package marker file
pub const INIT_FILE = "__init__.py";

// ============================================================================
// Module Path Utilities
// ============================================================================

/// Represents a module search path
pub const ModulePath = struct {
    paths: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .paths = std.ArrayList([]const u8){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.paths.deinit(self.allocator);
    }

    /// Add a path to the search list
    pub fn append(self: *Self, path: []const u8) !void {
        try self.paths.append(self.allocator, path);
    }

    /// Insert a path at the beginning
    pub fn insert(self: *Self, path: []const u8) !void {
        try self.paths.insert(self.allocator, 0, path);
    }

    /// Remove a path from the list
    pub fn remove(self: *Self, path: []const u8) bool {
        for (self.paths.items, 0..) |p, i| {
            if (std.mem.eql(u8, p, path)) {
                _ = self.paths.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Check if path exists in list
    pub fn contains(self: *const Self, path: []const u8) bool {
        for (self.paths.items) |p| {
            if (std.mem.eql(u8, p, path)) return true;
        }
        return false;
    }

    /// Get number of paths
    pub fn len(self: *const Self) usize {
        return self.paths.items.len;
    }

    /// Get all paths
    pub fn items(self: *const Self) []const []const u8 {
        return self.paths.items;
    }
};

/// Convert module name to file path
pub fn moduleNameToPath(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    for (name) |c| {
        if (c == '.') {
            try result.append(allocator, PATH_SEP);
        } else {
            try result.append(allocator, c);
        }
    }
    try result.appendSlice(allocator, PY_EXT);

    return result.toOwnedSlice(allocator);
}

/// Convert module name to package path
pub fn moduleNameToPackagePath(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    for (name) |c| {
        if (c == '.') {
            try result.append(allocator, PATH_SEP);
        } else {
            try result.append(allocator, c);
        }
    }
    try result.append(allocator, PATH_SEP);
    try result.appendSlice(allocator, INIT_FILE);

    return result.toOwnedSlice(allocator);
}

/// Join base path with module path
pub fn joinPath(allocator: std.mem.Allocator, base: []const u8, module_path: []const u8) ![]u8 {
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    try result.appendSlice(allocator, base);
    if (base.len > 0 and base[base.len - 1] != PATH_SEP) {
        try result.append(allocator, PATH_SEP);
    }
    try result.appendSlice(allocator, module_path);

    return result.toOwnedSlice(allocator);
}

/// Normalize a path (remove redundant separators, resolve . and ..)
pub fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var parts = std.ArrayList([]const u8){};
    defer parts.deinit(allocator);

    var iter = std.mem.splitScalar(u8, path, PATH_SEP);
    while (iter.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".")) {
            // Skip empty parts and current directory
            continue;
        } else if (std.mem.eql(u8, part, "..")) {
            // Go up one directory
            if (parts.items.len > 0) {
                _ = parts.pop();
            }
        } else {
            try parts.append(allocator, part);
        }
    }

    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    // Preserve leading separator for absolute paths
    if (path.len > 0 and path[0] == PATH_SEP) {
        try result.append(allocator, PATH_SEP);
    }

    for (parts.items, 0..) |part, i| {
        if (i > 0) try result.append(allocator, PATH_SEP);
        try result.appendSlice(allocator, part);
    }

    return result.toOwnedSlice(allocator);
}

/// Check if path is absolute
pub fn isAbsolutePath(path: []const u8) bool {
    if (path.len == 0) return false;

    if (builtin.os.tag == .windows) {
        // Windows: check for drive letter (C:\) or UNC path (\\)
        if (path.len >= 3 and std.ascii.isAlphabetic(path[0]) and path[1] == ':') {
            return path[2] == '\\' or path[2] == '/';
        }
        return (path.len >= 2 and path[0] == '\\' and path[1] == '\\');
    } else {
        // POSIX: starts with /
        return path[0] == '/';
    }
}

/// Get directory name from path
pub fn dirname(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, PATH_SEP)) |idx| {
        return path[0..idx];
    }
    return "";
}

/// Get base name from path
pub fn basename(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, PATH_SEP)) |idx| {
        return path[idx + 1 ..];
    }
    return path;
}

/// Get file extension
pub fn extension(path: []const u8) []const u8 {
    const base = basename(path);
    if (std.mem.lastIndexOfScalar(u8, base, '.')) |idx| {
        return base[idx..];
    }
    return "";
}

// ============================================================================
// Test Functions
// ============================================================================

/// Test ModulePath initialization
pub fn testModulePathInit(allocator: std.mem.Allocator) !void {
    var path = ModulePath.init(allocator);
    defer path.deinit();
    try std.testing.expectEqual(@as(usize, 0), path.len());
}

/// Test ModulePath append
pub fn testModulePathAppend(allocator: std.mem.Allocator) !void {
    var path = ModulePath.init(allocator);
    defer path.deinit();
    try path.append("/usr/lib/python3");
    try path.append("/home/user/lib");
    try std.testing.expectEqual(@as(usize, 2), path.len());
}

/// Test ModulePath insert
pub fn testModulePathInsert(allocator: std.mem.Allocator) !void {
    var path = ModulePath.init(allocator);
    defer path.deinit();
    try path.append("/second");
    try path.insert("/first");
    try std.testing.expectEqualStrings("/first", path.items()[0]);
}

/// Test moduleNameToPath
pub fn testModuleNameToPath(allocator: std.mem.Allocator) !void {
    const result = try moduleNameToPath(allocator, "os.path");
    defer allocator.free(result);
    // Should be "os/path.py" on Unix or "os\path.py" on Windows
    try std.testing.expect(std.mem.endsWith(u8, result, ".py"));
}

/// Test isAbsolutePath
pub fn testIsAbsolutePath() !void {
    if (builtin.os.tag == .windows) {
        try std.testing.expect(isAbsolutePath("C:\\Windows"));
        try std.testing.expect(isAbsolutePath("\\\\server\\share"));
        try std.testing.expect(!isAbsolutePath("relative\\path"));
    } else {
        try std.testing.expect(isAbsolutePath("/usr/bin"));
        try std.testing.expect(!isAbsolutePath("relative/path"));
    }
}

/// Test dirname and basename
pub fn testDirnameBasename() !void {
    if (builtin.os.tag != .windows) {
        try std.testing.expectEqualStrings("/usr/lib", dirname("/usr/lib/python3"));
        try std.testing.expectEqualStrings("python3", basename("/usr/lib/python3"));
    }
}

/// Test extension
pub fn testExtension() !void {
    try std.testing.expectEqualStrings(".py", extension("module.py"));
    try std.testing.expectEqualStrings(".pyc", extension("module.cpython-312.pyc"));
    try std.testing.expectEqualStrings("", extension("noextension"));
}

// ============================================================================
// Zig Tests
// ============================================================================

test "PATH_SEP" {
    if (builtin.os.tag == .windows) {
        try std.testing.expectEqual(@as(u8, '\\'), PATH_SEP);
    } else {
        try std.testing.expectEqual(@as(u8, '/'), PATH_SEP);
    }
}

test "ModulePath init" {
    const allocator = std.testing.allocator;
    var path = ModulePath.init(allocator);
    defer path.deinit();
    try std.testing.expectEqual(@as(usize, 0), path.len());
}

test "ModulePath append" {
    const allocator = std.testing.allocator;
    var path = ModulePath.init(allocator);
    defer path.deinit();
    try path.append("/path1");
    try path.append("/path2");
    try std.testing.expectEqual(@as(usize, 2), path.len());
}

test "ModulePath insert" {
    const allocator = std.testing.allocator;
    var path = ModulePath.init(allocator);
    defer path.deinit();
    try path.append("/second");
    try path.insert("/first");
    try std.testing.expectEqualStrings("/first", path.items()[0]);
}

test "ModulePath remove existing" {
    const allocator = std.testing.allocator;
    var path = ModulePath.init(allocator);
    defer path.deinit();
    try path.append("/remove_me");
    try std.testing.expect(path.remove("/remove_me"));
    try std.testing.expectEqual(@as(usize, 0), path.len());
}

test "ModulePath remove nonexistent" {
    const allocator = std.testing.allocator;
    var path = ModulePath.init(allocator);
    defer path.deinit();
    try std.testing.expect(!path.remove("/not_there"));
}

test "ModulePath contains true" {
    const allocator = std.testing.allocator;
    var path = ModulePath.init(allocator);
    defer path.deinit();
    try path.append("/exists");
    try std.testing.expect(path.contains("/exists"));
}

test "ModulePath contains false" {
    const allocator = std.testing.allocator;
    var path = ModulePath.init(allocator);
    defer path.deinit();
    try std.testing.expect(!path.contains("/missing"));
}

test "moduleNameToPath simple" {
    const allocator = std.testing.allocator;
    const result = try moduleNameToPath(allocator, "mymodule");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("mymodule.py", result);
}

test "moduleNameToPath dotted" {
    const allocator = std.testing.allocator;
    const result = try moduleNameToPath(allocator, "pkg.sub.mod");
    defer allocator.free(result);
    try std.testing.expect(std.mem.endsWith(u8, result, ".py"));
    try std.testing.expect(std.mem.indexOfScalar(u8, result, PATH_SEP) != null);
}

test "moduleNameToPackagePath" {
    const allocator = std.testing.allocator;
    const result = try moduleNameToPackagePath(allocator, "mypkg");
    defer allocator.free(result);
    try std.testing.expect(std.mem.endsWith(u8, result, INIT_FILE));
}

test "joinPath" {
    const allocator = std.testing.allocator;
    const result = try joinPath(allocator, "/base", "module.py");
    defer allocator.free(result);
    try std.testing.expect(std.mem.startsWith(u8, result, "/base"));
    try std.testing.expect(std.mem.endsWith(u8, result, "module.py"));
}

test "joinPath with trailing sep" {
    const allocator = std.testing.allocator;
    const result = try joinPath(allocator, "/base/", "module.py");
    defer allocator.free(result);
    // Should not have double separator
    try std.testing.expect(std.mem.indexOf(u8, result, "//") == null);
}

test "normalizePath dots" {
    const allocator = std.testing.allocator;
    const result = try normalizePath(allocator, "/a/./b/../c");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/a/c", result);
}

test "normalizePath redundant seps" {
    const allocator = std.testing.allocator;
    const result = try normalizePath(allocator, "/a//b///c");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("/a/b/c", result);
}

test "isAbsolutePath unix" {
    if (builtin.os.tag != .windows) {
        try std.testing.expect(isAbsolutePath("/absolute"));
        try std.testing.expect(!isAbsolutePath("relative"));
        try std.testing.expect(!isAbsolutePath(""));
    }
}

test "dirname" {
    if (builtin.os.tag != .windows) {
        try std.testing.expectEqualStrings("/usr", dirname("/usr/bin"));
        try std.testing.expectEqualStrings("", dirname("nodir"));
    }
}

test "basename" {
    if (builtin.os.tag != .windows) {
        try std.testing.expectEqualStrings("bin", basename("/usr/bin"));
        try std.testing.expectEqualStrings("file", basename("file"));
    }
}

test "extension py" {
    try std.testing.expectEqualStrings(".py", extension("test.py"));
}

test "extension pyc" {
    try std.testing.expectEqualStrings(".pyc", extension("test.pyc"));
}

test "extension none" {
    try std.testing.expectEqualStrings("", extension("noext"));
}

test "extension multiple dots" {
    try std.testing.expectEqualStrings(".pyc", extension("test.cpython-312.pyc"));
}

test "PY_EXT constant" {
    try std.testing.expectEqualStrings(".py", PY_EXT);
}

test "PYC_EXT constant" {
    try std.testing.expectEqualStrings(".pyc", PYC_EXT);
}

test "INIT_FILE constant" {
    try std.testing.expectEqualStrings("__init__.py", INIT_FILE);
}
