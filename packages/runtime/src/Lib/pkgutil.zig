/// pkgutil - Package utility functions
/// Mirrors cpython/Lib/pkgutil.py
///
/// Utilities to support packages (finding, importing, iterating).

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Module Info
// ============================================================================

/// Information about a module or package
pub const ModuleInfo = struct {
    /// The module finder that located this module
    module_finder: ?*anyopaque = null,
    /// The module name
    name: []const u8,
    /// Whether this is a package (has __path__)
    ispkg: bool,

    pub fn deinit(self: *ModuleInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
    }
};

// ============================================================================
// iter_modules - Iterate over modules
// ============================================================================

/// Iterator over modules in a path
pub const ModuleIterator = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    path: []const []const u8,
    path_index: usize = 0,
    dir: ?std.fs.Dir = null,
    iter: ?std.fs.Dir.Iterator = null,
    prefix: []const u8 = "",
    seen: hashmap_helper.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator, path: ?[]const []const u8, prefix: ?[]const u8) Self {
        const default_path = &[_][]const u8{"."};
        return .{
            .allocator = allocator,
            .path = path orelse default_path,
            .prefix = prefix orelse "",
            .seen = hashmap_helper.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.dir) |*d| {
            d.close();
        }
        self.seen.deinit();
    }

    pub fn next(self: *Self) !?ModuleInfo {
        while (true) {
            // If we don't have a directory open, open the next one
            if (self.dir == null) {
                if (self.path_index >= self.path.len) {
                    return null;
                }

                self.dir = std.fs.cwd().openDir(self.path[self.path_index], .{ .iterate = true }) catch {
                    self.path_index += 1;
                    continue;
                };
                self.iter = self.dir.?.iterate();
                self.path_index += 1;
            }

            // Get next entry
            if (self.iter) |*iter| {
                if (try iter.next()) |entry| {
                    const info = try self.processEntry(entry);
                    if (info) |i| {
                        return i;
                    }
                    continue;
                }
            }

            // No more entries in this directory
            if (self.dir) |*d| {
                d.close();
                self.dir = null;
                self.iter = null;
            }
        }
    }

    fn processEntry(self: *Self, entry: std.fs.Dir.Entry) !?ModuleInfo {
        const name = entry.name;

        // Skip hidden files and __pycache__
        if (name.len == 0 or name[0] == '.') return null;
        if (std.mem.eql(u8, name, "__pycache__")) return null;

        var module_name: []const u8 = undefined;
        var ispkg = false;

        if (entry.kind == .directory) {
            // Check if it's a package (has __init__.py)
            var dir_path_buf: [std.fs.max_path_bytes]u8 = undefined;
            const dir_path = std.fmt.bufPrint(&dir_path_buf, "{s}/{s}/__init__.py", .{ self.path[self.path_index - 1], name }) catch return null;

            const is_package = blk: {
                std.fs.cwd().access(dir_path, .{}) catch break :blk false;
                break :blk true;
            };

            if (!is_package) return null;

            module_name = name;
            ispkg = true;
        } else {
            // Check if it's a .py file
            if (!std.mem.endsWith(u8, name, ".py")) return null;
            if (std.mem.eql(u8, name, "__init__.py")) return null;

            // Strip .py extension
            module_name = name[0 .. name.len - 3];
            ispkg = false;
        }

        // Skip if already seen
        if (self.seen.contains(module_name)) return null;
        try self.seen.put(try self.allocator.dupe(u8, module_name), {});

        // Create full name with prefix
        var full_name: []const u8 = undefined;
        if (self.prefix.len > 0) {
            full_name = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.prefix, module_name });
        } else {
            full_name = try self.allocator.dupe(u8, module_name);
        }

        return ModuleInfo{
            .name = full_name,
            .ispkg = ispkg,
        };
    }
};

/// Iterate over all modules in given path(s)
pub fn iter_modules(
    allocator: std.mem.Allocator,
    path: ?[]const []const u8,
    prefix: ?[]const u8,
) ModuleIterator {
    return ModuleIterator.init(allocator, path, prefix);
}

// ============================================================================
// walk_packages - Walk packages recursively
// ============================================================================

/// Walk all packages recursively
pub fn walk_packages(
    allocator: std.mem.Allocator,
    path: ?[]const []const u8,
    prefix: ?[]const u8,
    onerror: ?*const fn ([]const u8) void,
) !std.ArrayList(ModuleInfo) {
    var result = std.ArrayList(ModuleInfo).init(allocator);
    errdefer result.deinit();

    var iter = iter_modules(allocator, path, prefix);
    defer iter.deinit();

    while (try iter.next()) |info| {
        try result.append(info);

        if (info.ispkg) {
            // Recursively walk subpackages
            const subpath = &[_][]const u8{info.name};
            const subprefix = try std.fmt.allocPrint(allocator, "{s}.", .{info.name});
            defer allocator.free(subprefix);

            var subresult = walk_packages(allocator, subpath, subprefix, onerror) catch |err| {
                if (onerror) |handler| {
                    handler(info.name);
                }
                _ = err;
                continue;
            };

            for (subresult.items) |subinfo| {
                try result.append(subinfo);
            }
            subresult.deinit();
        }
    }

    return result;
}

// ============================================================================
// get_data - Read package data
// ============================================================================

/// Read data from a package resource
pub fn get_data(allocator: std.mem.Allocator, package: []const u8, resource: []const u8) ![]u8 {
    // Convert package path (dots to slashes)
    var pkg_path = try allocator.alloc(u8, package.len);
    defer allocator.free(pkg_path);

    for (package, 0..) |c, i| {
        pkg_path[i] = if (c == '.') '/' else c;
    }

    // Build full path
    const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ pkg_path, resource });
    defer allocator.free(full_path);

    // Read file
    const file = try std.fs.cwd().openFile(full_path, .{});
    defer file.close();

    return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

// ============================================================================
// get_importer - Get importer for path item
// ============================================================================

/// Importer type (simplified representation)
pub const Importer = struct {
    path: []const u8,
    is_package_path: bool,

    pub fn find_module(self: *const Importer, fullname: []const u8) bool {
        // Check if module exists at this path
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;

        // Try .py file
        const py_path = std.fmt.bufPrint(&path_buf, "{s}/{s}.py", .{ self.path, fullname }) catch return false;
        if (std.fs.cwd().access(py_path, .{})) |_| {
            return true;
        } else |_| {}

        // Try package (__init__.py)
        const pkg_path = std.fmt.bufPrint(&path_buf, "{s}/{s}/__init__.py", .{ self.path, fullname }) catch return false;
        if (std.fs.cwd().access(pkg_path, .{})) |_| {
            return true;
        } else |_| {}

        return false;
    }
};

/// Importer cache (path → Importer)
var importer_cache: ?hashmap_helper.StringHashMap(Importer) = null;

/// Get the importer for a path item
pub fn get_importer(allocator: std.mem.Allocator, path_item: []const u8) ?*const Importer {
    // Initialize cache if needed
    if (importer_cache == null) {
        importer_cache = hashmap_helper.StringHashMap(Importer).init(allocator);
    }

    // Check cache first
    if (importer_cache) |*cache| {
        if (cache.getPtr(path_item)) |importer| {
            return importer;
        }

        // Check if path exists and is a directory
        if (std.fs.cwd().access(path_item, .{})) |_| {
            // Create new importer for this path
            cache.put(path_item, Importer{
                .path = path_item,
                .is_package_path = true,
            }) catch return null;

            return cache.getPtr(path_item);
        } else |_| {}
    }

    return null;
}

// ============================================================================
// find_loader - Find loader for module
// ============================================================================

/// Loader result
pub const LoaderResult = struct {
    loader: ?*const Importer,
    portions: []const []const u8,
};

/// Find loader for a module by searching paths
pub fn find_loader(allocator: std.mem.Allocator, fullname: []const u8, path: ?[]const []const u8) !?LoaderResult {
    // Default search paths
    const default_paths = [_][]const u8{
        ".",
        "/usr/lib/python3/dist-packages",
        "/usr/local/lib/python3.12/site-packages",
    };

    const search_paths = path orelse &default_paths;

    for (search_paths) |search_path| {
        if (get_importer(allocator, search_path)) |importer| {
            if (importer.find_module(fullname)) {
                return LoaderResult{
                    .loader = importer,
                    .portions = &[_][]const u8{},
                };
            }
        }
    }

    return null;
}

// ============================================================================
// get_loader - Get loader for module
// ============================================================================

/// Get loader for a module (convenience wrapper)
pub fn get_loader(allocator: std.mem.Allocator, module_or_name: []const u8) ?*const Importer {
    if (find_loader(allocator, module_or_name, null)) |result| {
        return result.loader;
    } else |_| {}
    return null;
}

// ============================================================================
// resolve_name - Resolve relative module name
// ============================================================================

/// Resolve a relative module name to absolute
pub fn resolve_name(allocator: std.mem.Allocator, name: []const u8, package: ?[]const u8) ![]const u8 {
    if (name.len == 0 or name[0] != '.') {
        // Already absolute
        return try allocator.dupe(u8, name);
    }

    const pkg = package orelse return error.ImportError;

    // Count leading dots
    var dots: usize = 0;
    while (dots < name.len and name[dots] == '.') {
        dots += 1;
    }

    // Find package base (remove 'dots-1' components from end)
    var pkg_parts = std.ArrayList([]const u8).init(allocator);
    defer pkg_parts.deinit();

    var parts_iter = std.mem.splitScalar(u8, pkg, '.');
    while (parts_iter.next()) |part| {
        try pkg_parts.append(part);
    }

    if (dots > pkg_parts.items.len) {
        return error.ImportError;
    }

    // Build result
    var result = std.ArrayList(u8).init(allocator);
    for (pkg_parts.items[0 .. pkg_parts.items.len - (dots - 1)]) |part| {
        if (result.items.len > 0) {
            try result.append('.');
        }
        try result.appendSlice(part);
    }

    if (dots < name.len) {
        if (result.items.len > 0) {
            try result.append('.');
        }
        try result.appendSlice(name[dots..]);
    }

    return result.toOwnedSlice();
}

// ============================================================================
// extend_path - Extend package path
// ============================================================================

/// Extend package __path__ for namespace packages
pub fn extend_path(allocator: std.mem.Allocator, path: []const []const u8, name: []const u8) ![]const []const u8 {
    var result = std.ArrayList([]const u8).init(allocator);

    // Keep existing paths
    for (path) |p| {
        try result.append(try allocator.dupe(u8, p));
    }

    // Would also check sys.path for additional namespace package paths
    _ = name;

    return result.toOwnedSlice();
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the pkgutil module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "ModuleInfo" {
    var info = ModuleInfo{
        .name = "test_module",
        .ispkg = false,
    };
    try std.testing.expectEqualStrings("test_module", info.name);
    try std.testing.expect(!info.ispkg);
    _ = &info;
}

test "resolve_name absolute" {
    const allocator = std.testing.allocator;
    const result = try resolve_name(allocator, "os.path", null);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("os.path", result);
}

test "resolve_name relative single dot" {
    const allocator = std.testing.allocator;
    const result = try resolve_name(allocator, ".submodule", "package");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("package.submodule", result);
}

test "resolve_name relative double dot" {
    const allocator = std.testing.allocator;
    const result = try resolve_name(allocator, "..sibling", "package.subpackage");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("package.sibling", result);
}

test "resolve_name no package error" {
    const allocator = std.testing.allocator;
    const result = resolve_name(allocator, ".relative", null);
    try std.testing.expectError(error.ImportError, result);
}

test "get_importer returns null" {
    const result = get_importer("/some/path");
    try std.testing.expect(result == null);
}

test "get_loader returns null" {
    const result = get_loader("os");
    try std.testing.expect(result == null);
}

test "find_loader returns null" {
    const result = try find_loader("os", null);
    try std.testing.expect(result == null);
}

test "extend_path preserves paths" {
    const allocator = std.testing.allocator;
    const paths = [_][]const u8{ "/path/one", "/path/two" };
    const result = try extend_path(allocator, &paths, "mypackage");
    defer {
        for (result) |p| allocator.free(p);
        allocator.free(result);
    }
    try std.testing.expectEqual(@as(usize, 2), result.len);
}

test "ModuleIterator init" {
    const allocator = std.testing.allocator;
    var iter = ModuleIterator.init(allocator, null, null);
    defer iter.deinit();
    try std.testing.expectEqual(@as(usize, 0), iter.path_index);
}
