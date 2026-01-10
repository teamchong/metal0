//! test.test_import.test_path - Path hooks and sys.path testing
//!
//! Tests for Python's import path system including:
//! - sys.path manipulation
//! - Path hooks (sys.path_hooks)
//! - Path importer cache (sys.path_importer_cache)
//! - FileFinder and path-based imports

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Path entry representing a location in sys.path
pub const PathEntry = struct {
    path: []const u8,
    kind: PathKind,
    finder: ?*const PathFinder,

    pub const PathKind = enum {
        directory,
        zip_archive,
        namespace,
        frozen,
        builtin,
    };

    pub fn init(path: []const u8, kind: PathKind) PathEntry {
        return .{
            .path = path,
            .kind = kind,
            .finder = null,
        };
    }

    pub fn isDirectory(self: PathEntry) bool {
        return self.kind == .directory;
    }

    pub fn isArchive(self: PathEntry) bool {
        return self.kind == .zip_archive;
    }
};

/// sys.path representation
pub const SysPath = struct {
    entries: std.ArrayListUnmanaged(PathEntry),
    allocator: Allocator,

    pub fn init(allocator: Allocator) SysPath {
        return .{
            .entries = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SysPath) void {
        self.entries.deinit(self.allocator);
    }

    pub fn append(self: *SysPath, path: []const u8) !void {
        try self.entries.append(self.allocator, PathEntry.init(path, .directory));
    }

    pub fn insert(self: *SysPath, index: usize, path: []const u8) !void {
        try self.entries.insert(self.allocator, index, PathEntry.init(path, .directory));
    }

    pub fn remove(self: *SysPath, path: []const u8) bool {
        for (self.entries.items, 0..) |entry, i| {
            if (std.mem.eql(u8, entry.path, path)) {
                _ = self.entries.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn contains(self: *const SysPath, path: []const u8) bool {
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.path, path)) return true;
        }
        return false;
    }

    pub fn get(self: *const SysPath, index: usize) ?PathEntry {
        if (index >= self.entries.items.len) return null;
        return self.entries.items[index];
    }

    pub fn len(self: *const SysPath) usize {
        return self.entries.items.len;
    }
};

/// Path hook function type - called for each path entry
pub const PathHookFn = *const fn (path: []const u8) PathHookError!*const PathFinder;

pub const PathHookError = error{
    ImportError,
    NotSupported,
};

/// Path hooks registry
pub const PathHooks = struct {
    hooks: std.ArrayListUnmanaged(PathHookFn),
    allocator: Allocator,

    pub fn init(allocator: Allocator) PathHooks {
        return .{
            .hooks = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PathHooks) void {
        self.hooks.deinit(self.allocator);
    }

    pub fn register(self: *PathHooks, hook: PathHookFn) !void {
        try self.hooks.append(self.allocator, hook);
    }

    pub fn unregister(self: *PathHooks, hook: PathHookFn) bool {
        for (self.hooks.items, 0..) |h, i| {
            if (h == hook) {
                _ = self.hooks.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn findFinder(self: *const PathHooks, path: []const u8) ?*const PathFinder {
        for (self.hooks.items) |hook| {
            if (hook(path)) |finder| {
                return finder;
            } else |_| {
                continue;
            }
        }
        return null;
    }
};

/// Path importer cache (sys.path_importer_cache)
pub const PathImporterCache = struct {
    cache: std.StringHashMapUnmanaged(CacheEntry),
    allocator: Allocator,

    pub const CacheEntry = union(enum) {
        finder: *const PathFinder,
        none_finder, // Path doesn't support import
        not_checked, // Not yet checked
    };

    pub fn init(allocator: Allocator) PathImporterCache {
        return .{
            .cache = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PathImporterCache) void {
        self.cache.deinit(self.allocator);
    }

    pub fn get(self: *const PathImporterCache, path: []const u8) ?CacheEntry {
        return self.cache.get(path);
    }

    pub fn put(self: *PathImporterCache, path: []const u8, entry: CacheEntry) !void {
        try self.cache.put(self.allocator, path, entry);
    }

    pub fn invalidate(self: *PathImporterCache, path: []const u8) bool {
        return self.cache.remove(path);
    }

    pub fn clear(self: *PathImporterCache) void {
        self.cache.clearRetainingCapacity();
    }
};

/// Abstract path finder interface
pub const PathFinder = struct {
    vtable: *const VTable,
    path: []const u8,

    pub const VTable = struct {
        find_spec: *const fn (*const PathFinder, []const u8, ?*const Target) ?*ModuleSpec,
        find_loader: *const fn (*const PathFinder, []const u8) ?*const Loader,
        invalidate_caches: *const fn (*const PathFinder) void,
    };

    pub const Target = struct {
        module: *anyopaque,
    };

    pub fn findSpec(self: *const PathFinder, fullname: []const u8, target: ?*const Target) ?*ModuleSpec {
        return self.vtable.find_spec(self, fullname, target);
    }

    pub fn findLoader(self: *const PathFinder, fullname: []const u8) ?*const Loader {
        return self.vtable.find_loader(self, fullname);
    }

    pub fn invalidateCaches(self: *const PathFinder) void {
        self.vtable.invalidate_caches(self);
    }
};

/// Module spec for path-based imports
pub const ModuleSpec = struct {
    name: []const u8,
    loader: ?*const Loader,
    origin: ?[]const u8,
    cached: ?[]const u8,
    parent: ?[]const u8,
    submodule_search_locations: ?[]const []const u8,
    has_location: bool,
    loader_state: ?*anyopaque,

    pub fn init(name: []const u8) ModuleSpec {
        return .{
            .name = name,
            .loader = null,
            .origin = null,
            .cached = null,
            .parent = null,
            .submodule_search_locations = null,
            .has_location = false,
            .loader_state = null,
        };
    }

    pub fn withOrigin(self: ModuleSpec, origin: []const u8) ModuleSpec {
        var spec = self;
        spec.origin = origin;
        spec.has_location = true;
        return spec;
    }

    pub fn isPackage(self: *const ModuleSpec) bool {
        return self.submodule_search_locations != null;
    }
};

/// Abstract loader interface
pub const Loader = struct {
    vtable: *const VTable,

    pub const VTable = struct {
        create_module: *const fn (*const Loader, *const ModuleSpec) ?*Module,
        exec_module: *const fn (*const Loader, *Module) LoaderError!void,
    };

    pub fn createModule(self: *const Loader, spec: *const ModuleSpec) ?*Module {
        return self.vtable.create_module(self, spec);
    }

    pub fn execModule(self: *const Loader, module: *Module) LoaderError!void {
        return self.vtable.exec_module(self, module);
    }
};

pub const LoaderError = error{
    LoadFailed,
    ExecutionFailed,
};

/// Module representation
pub const Module = struct {
    __name__: []const u8,
    __file__: ?[]const u8,
    __path__: ?[]const []const u8,
};

/// FileFinder - finds modules in a directory
pub const FileFinder = struct {
    path: []const u8,
    loaders: []const LoaderDetail,
    path_mtime: i64,
    path_cache: std.StringHashMapUnmanaged(void),
    allocator: Allocator,

    pub const LoaderDetail = struct {
        loader: *const Loader,
        suffixes: []const []const u8,
    };

    pub fn init(allocator: Allocator, path: []const u8, loaders: []const LoaderDetail) FileFinder {
        return .{
            .path = path,
            .loaders = loaders,
            .path_mtime = -1,
            .path_cache = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FileFinder) void {
        self.path_cache.deinit(self.allocator);
    }

    pub fn findSpec(self: *FileFinder, fullname: []const u8) ?ModuleSpec {
        // Extract the module name (last component)
        const module_name = blk: {
            if (std.mem.lastIndexOfScalar(u8, fullname, '.')) |idx| {
                break :blk fullname[idx + 1 ..];
            }
            break :blk fullname;
        };

        // Check for package (__init__.py)
        var buf: [512]u8 = undefined;
        const pkg_path = std.fmt.bufPrint(&buf, "{s}/{s}/__init__.py", .{ self.path, module_name }) catch return null;
        _ = pkg_path;

        // For now, just return a basic spec
        var spec = ModuleSpec.init(fullname);
        spec.has_location = true;
        return spec;
    }

    pub fn invalidateCaches(self: *FileFinder) void {
        self.path_cache.clearRetainingCapacity();
        self.path_mtime = -1;
    }
};

/// Path utilities
pub const PathUtils = struct {
    /// Join path components
    pub fn join(allocator: Allocator, components: []const []const u8) ![]u8 {
        var total_len: usize = 0;
        for (components, 0..) |comp, i| {
            total_len += comp.len;
            if (i < components.len - 1) total_len += 1; // separator
        }

        const result = try allocator.alloc(u8, total_len);
        var pos: usize = 0;
        for (components, 0..) |comp, i| {
            @memcpy(result[pos..][0..comp.len], comp);
            pos += comp.len;
            if (i < components.len - 1) {
                result[pos] = '/';
                pos += 1;
            }
        }
        return result;
    }

    /// Get the directory name from a path
    pub fn dirname(path: []const u8) ?[]const u8 {
        if (std.mem.lastIndexOfScalar(u8, path, '/')) |idx| {
            return path[0..idx];
        }
        return null;
    }

    /// Get the base name from a path
    pub fn basename(path: []const u8) []const u8 {
        if (std.mem.lastIndexOfScalar(u8, path, '/')) |idx| {
            return path[idx + 1 ..];
        }
        return path;
    }

    /// Check if path is absolute
    pub fn isAbsolute(path: []const u8) bool {
        if (path.len == 0) return false;
        return path[0] == '/';
    }

    /// Normalize path (remove . and ..)
    pub fn normalize(allocator: Allocator, path: []const u8) ![]u8 {
        var components = std.ArrayList([]const u8).init(allocator);
        defer components.deinit();

        var iter = std.mem.splitScalar(u8, path, '/');
        while (iter.next()) |comp| {
            if (comp.len == 0 or std.mem.eql(u8, comp, ".")) {
                continue;
            } else if (std.mem.eql(u8, comp, "..")) {
                if (components.items.len > 0) {
                    _ = components.pop();
                }
            } else {
                try components.append(comp);
            }
        }

        return join(allocator, components.items);
    }
};

// =============================================================================
// Tests
// =============================================================================

test "sys_path_basic" {
    var path = SysPath.init(std.testing.allocator);
    defer path.deinit();

    try path.append("/usr/lib/python3");
    try path.append("/home/user/.local/lib/python3");

    try std.testing.expectEqual(@as(usize, 2), path.len());
    try std.testing.expect(path.contains("/usr/lib/python3"));
    try std.testing.expect(!path.contains("/nonexistent"));
}

test "sys_path_insert" {
    var path = SysPath.init(std.testing.allocator);
    defer path.deinit();

    try path.append("/path/a");
    try path.append("/path/c");
    try path.insert(1, "/path/b");

    try std.testing.expectEqual(@as(usize, 3), path.len());
    try std.testing.expectEqualStrings("/path/a", path.get(0).?.path);
    try std.testing.expectEqualStrings("/path/b", path.get(1).?.path);
    try std.testing.expectEqualStrings("/path/c", path.get(2).?.path);
}

test "sys_path_remove" {
    var path = SysPath.init(std.testing.allocator);
    defer path.deinit();

    try path.append("/path/a");
    try path.append("/path/b");
    try path.append("/path/c");

    try std.testing.expect(path.remove("/path/b"));
    try std.testing.expectEqual(@as(usize, 2), path.len());
    try std.testing.expect(!path.contains("/path/b"));

    try std.testing.expect(!path.remove("/nonexistent"));
}

test "path_entry_kinds" {
    const dir_entry = PathEntry.init("/usr/lib/python3", .directory);
    try std.testing.expect(dir_entry.isDirectory());
    try std.testing.expect(!dir_entry.isArchive());

    const zip_entry = PathEntry.init("/path/to/archive.zip", .zip_archive);
    try std.testing.expect(!zip_entry.isDirectory());
    try std.testing.expect(zip_entry.isArchive());
}

test "path_hooks_registry" {
    var hooks = PathHooks.init(std.testing.allocator);
    defer hooks.deinit();

    const dummy_hook: PathHookFn = struct {
        fn hook(_: []const u8) PathHookError!*const PathFinder {
            return error.NotSupported;
        }
    }.hook;

    try hooks.register(dummy_hook);
    try std.testing.expectEqual(@as(usize, 1), hooks.hooks.items.len);

    try std.testing.expect(hooks.unregister(dummy_hook));
    try std.testing.expectEqual(@as(usize, 0), hooks.hooks.items.len);
}

test "path_importer_cache" {
    var cache = PathImporterCache.init(std.testing.allocator);
    defer cache.deinit();

    try cache.put("/path/a", .none_finder);
    try cache.put("/path/b", .not_checked);

    const entry_a = cache.get("/path/a");
    try std.testing.expect(entry_a != null);
    try std.testing.expect(entry_a.? == .none_finder);

    const entry_b = cache.get("/path/b");
    try std.testing.expect(entry_b != null);
    try std.testing.expect(entry_b.? == .not_checked);

    try std.testing.expect(cache.get("/path/c") == null);
}

test "path_importer_cache_invalidate" {
    var cache = PathImporterCache.init(std.testing.allocator);
    defer cache.deinit();

    try cache.put("/path/a", .none_finder);
    try std.testing.expect(cache.invalidate("/path/a"));
    try std.testing.expect(cache.get("/path/a") == null);
}

test "module_spec_creation" {
    var spec = ModuleSpec.init("mymodule");
    try std.testing.expectEqualStrings("mymodule", spec.name);
    try std.testing.expect(!spec.has_location);
    try std.testing.expect(!spec.isPackage());

    spec = spec.withOrigin("/path/to/mymodule.py");
    try std.testing.expect(spec.has_location);
    try std.testing.expectEqualStrings("/path/to/mymodule.py", spec.origin.?);
}

test "file_finder_basic" {
    var finder = FileFinder.init(std.testing.allocator, "/usr/lib/python3", &.{});
    defer finder.deinit();

    try std.testing.expectEqualStrings("/usr/lib/python3", finder.path);
}

test "path_utils_join" {
    const result = try PathUtils.join(std.testing.allocator, &.{ "a", "b", "c" });
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("a/b/c", result);
}

test "path_utils_dirname" {
    const dir1 = PathUtils.dirname("/path/to/file.py");
    try std.testing.expect(dir1 != null);
    try std.testing.expectEqualStrings("/path/to", dir1.?);

    const dir2 = PathUtils.dirname("file.py");
    try std.testing.expect(dir2 == null);
}

test "path_utils_basename" {
    const base1 = PathUtils.basename("/path/to/file.py");
    try std.testing.expectEqualStrings("file.py", base1);

    const base2 = PathUtils.basename("file.py");
    try std.testing.expectEqualStrings("file.py", base2);
}

test "path_utils_is_absolute" {
    try std.testing.expect(PathUtils.isAbsolute("/absolute/path"));
    try std.testing.expect(!PathUtils.isAbsolute("relative/path"));
    try std.testing.expect(!PathUtils.isAbsolute(""));
}

test "path_utils_normalize" {
    const result = try PathUtils.normalize(std.testing.allocator, "/a/b/../c/./d");
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("a/c/d", result);
}
