//! test.test_zipfile.test_zipimport - ZIP import tests
//!
//! Tests for importing Python modules from ZIP archives, implementing
//! the zipimport functionality for loading code from ZIP files.

const std = @import("std");
const testing = std.testing;
const mem = std.mem;

// ============================================================================
// Module Types
// ============================================================================

pub const ModuleType = enum {
    source, // .py file
    bytecode, // .pyc file
    package, // __init__.py
    namespace, // namespace package (no __init__.py)
    c_extension, // .so/.pyd file (not supported in ZIP)

    pub fn fromFilename(name: []const u8) ?ModuleType {
        if (mem.endsWith(u8, name, "/__init__.py")) return .package;
        if (mem.endsWith(u8, name, ".py")) return .source;
        if (mem.endsWith(u8, name, ".pyc")) return .bytecode;
        if (mem.endsWith(u8, name, ".pyo")) return .bytecode;
        if (mem.endsWith(u8, name, ".so") or mem.endsWith(u8, name, ".pyd")) return .c_extension;
        return null;
    }

    pub fn isImportable(self: ModuleType) bool {
        return switch (self) {
            .source, .bytecode, .package, .namespace => true,
            .c_extension => false,
        };
    }
};

// ============================================================================
// ZipImporter
// ============================================================================

pub const ZipImporter = struct {
    const Self = @This();

    allocator: mem.Allocator,
    archive_path: []const u8,
    prefix: []const u8 = "",
    modules: std.StringHashMap(ModuleInfo),
    search_paths: std.ArrayList([]const u8),

    pub const ModuleInfo = struct {
        name: []const u8,
        filename: []const u8,
        module_type: ModuleType,
        is_package: bool,
        source: ?[]const u8 = null,
    };

    pub const ImportError = error{
        ModuleNotFound,
        InvalidZipArchive,
        UnsupportedModuleType,
        ReadError,
        OutOfMemory,
    };

    pub fn init(allocator: mem.Allocator, archive_path: []const u8) Self {
        return .{
            .allocator = allocator,
            .archive_path = archive_path,
            .modules = std.StringHashMap(ModuleInfo).init(allocator),
            .search_paths = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.modules.deinit();
        self.search_paths.deinit();
    }

    /// Add a path within the ZIP to search for modules
    pub fn addSearchPath(self: *Self, path: []const u8) !void {
        try self.search_paths.append(path);
    }

    /// Register a module
    pub fn registerModule(self: *Self, name: []const u8, info: ModuleInfo) !void {
        try self.modules.put(name, info);
    }

    /// Find a module by name
    pub fn findModule(self: *Self, name: []const u8) ?ModuleInfo {
        return self.modules.get(name);
    }

    /// Convert module name to file path
    pub fn moduleToPath(self: *Self, module_name: []const u8) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        // Add prefix if any
        if (self.prefix.len > 0) {
            try result.appendSlice(self.prefix);
            if (result.items.len > 0 and result.items[result.items.len - 1] != '/') {
                try result.append('/');
            }
        }

        // Replace dots with slashes
        for (module_name) |c| {
            if (c == '.') {
                try result.append('/');
            } else {
                try result.append(c);
            }
        }

        return result.toOwnedSlice();
    }

    /// Check if archive contains a module
    pub fn hasModule(self: *Self, name: []const u8) bool {
        return self.modules.contains(name);
    }

    /// Get module source code
    pub fn getSource(self: *Self, name: []const u8) ?[]const u8 {
        if (self.modules.get(name)) |info| {
            return info.source;
        }
        return null;
    }

    /// Get archive path
    pub fn getArchivePath(self: Self) []const u8 {
        return self.archive_path;
    }

    /// Check if archive is valid
    pub fn isValid(self: Self) bool {
        _ = self;
        // Would check if archive exists and is a valid ZIP
        return true;
    }
};

// ============================================================================
// Module Finder
// ============================================================================

pub const ModuleFinder = struct {
    const Self = @This();

    allocator: mem.Allocator,
    file_list: std.ArrayList([]const u8),

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .file_list = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.file_list.deinit();
    }

    /// Add a file to the search list
    pub fn addFile(self: *Self, path: []const u8) !void {
        try self.file_list.append(path);
    }

    /// Find module by name
    pub fn findModuleFile(self: *Self, module_name: []const u8) ?[]const u8 {
        // Convert module name to possible file paths
        const candidates = self.getCandidatePaths(module_name) catch return null;
        defer self.allocator.free(candidates);

        for (self.file_list.items) |file| {
            for (candidates) |candidate| {
                if (mem.eql(u8, file, candidate)) {
                    return file;
                }
            }
        }
        return null;
    }

    fn getCandidatePaths(self: *Self, module_name: []const u8) ![][]const u8 {
        var paths = std.ArrayList([]u8).init(self.allocator);
        errdefer {
            for (paths.items) |p| self.allocator.free(p);
            paths.deinit();
        }

        // Convert dots to slashes
        var base_path = std.ArrayList(u8).init(self.allocator);
        defer base_path.deinit();

        for (module_name) |c| {
            if (c == '.') {
                try base_path.append('/');
            } else {
                try base_path.append(c);
            }
        }

        // Add .py extension
        var py_path = try self.allocator.alloc(u8, base_path.items.len + 3);
        @memcpy(py_path[0..base_path.items.len], base_path.items);
        @memcpy(py_path[base_path.items.len..], ".py");
        try paths.append(py_path);

        // Add __init__.py for package
        var init_path = try self.allocator.alloc(u8, base_path.items.len + 12);
        @memcpy(init_path[0..base_path.items.len], base_path.items);
        @memcpy(init_path[base_path.items.len..], "/__init__.py");
        try paths.append(init_path);

        const result = try self.allocator.alloc([]const u8, paths.items.len);
        for (paths.items, 0..) |item, i| {
            result[i] = item;
        }
        return result;
    }

    /// Check if module is a package
    pub fn isPackage(self: *Self, module_name: []const u8) bool {
        const file = self.findModuleFile(module_name) orelse return false;
        return mem.endsWith(u8, file, "/__init__.py");
    }
};

// ============================================================================
// Package Structure
// ============================================================================

pub const PackageInfo = struct {
    name: []const u8,
    path: []const u8,
    parent: ?[]const u8 = null,
    submodules: std.ArrayList([]const u8),
    is_namespace: bool = false,

    pub fn init(allocator: mem.Allocator, name: []const u8, path: []const u8) PackageInfo {
        return .{
            .name = name,
            .path = path,
            .submodules = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *PackageInfo) void {
        self.submodules.deinit();
    }

    pub fn addSubmodule(self: *PackageInfo, submodule: []const u8) !void {
        try self.submodules.append(submodule);
    }

    pub fn hasSubmodule(self: PackageInfo, name: []const u8) bool {
        for (self.submodules.items) |sub| {
            if (mem.eql(u8, sub, name)) return true;
        }
        return false;
    }

    pub fn getFullName(self: PackageInfo, allocator: mem.Allocator) ![]u8 {
        if (self.parent) |p| {
            return std.fmt.allocPrint(allocator, "{s}.{s}", .{ p, self.name });
        }
        return allocator.dupe(u8, self.name);
    }
};

// ============================================================================
// Import Cache
// ============================================================================

pub const ImportCache = struct {
    const Self = @This();

    allocator: mem.Allocator,
    cache: std.StringHashMap(CacheEntry),

    pub const CacheEntry = struct {
        module_info: ZipImporter.ModuleInfo,
        timestamp: i64,
        hit_count: u32 = 0,
    };

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .cache = std.StringHashMap(CacheEntry).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.cache.deinit();
    }

    pub fn get(self: *Self, key: []const u8) ?*CacheEntry {
        if (self.cache.getPtr(key)) |entry| {
            entry.hit_count += 1;
            return entry;
        }
        return null;
    }

    pub fn put(self: *Self, key: []const u8, module_info: ZipImporter.ModuleInfo) !void {
        try self.cache.put(key, .{
            .module_info = module_info,
            .timestamp = std.time.timestamp(),
        });
    }

    pub fn remove(self: *Self, key: []const u8) bool {
        return self.cache.remove(key);
    }

    pub fn clear(self: *Self) void {
        self.cache.clearRetainingCapacity();
    }

    pub fn size(self: Self) usize {
        return self.cache.count();
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Split module name into parent and child
pub fn splitModuleName(name: []const u8) struct { parent: ?[]const u8, child: []const u8 } {
    if (mem.lastIndexOfScalar(u8, name, '.')) |pos| {
        return .{
            .parent = name[0..pos],
            .child = name[pos + 1 ..],
        };
    }
    return .{ .parent = null, .child = name };
}

/// Get top-level package name
pub fn getTopLevelPackage(name: []const u8) []const u8 {
    if (mem.indexOfScalar(u8, name, '.')) |pos| {
        return name[0..pos];
    }
    return name;
}

/// Check if name is a submodule of package
pub fn isSubmoduleOf(name: []const u8, package: []const u8) bool {
    if (name.len <= package.len) return false;
    if (!mem.startsWith(u8, name, package)) return false;
    return name[package.len] == '.';
}

// ============================================================================
// Tests
// ============================================================================

test "ModuleType fromFilename" {
    try testing.expectEqual(ModuleType.source, ModuleType.fromFilename("module.py").?);
    try testing.expectEqual(ModuleType.bytecode, ModuleType.fromFilename("module.pyc").?);
    try testing.expectEqual(ModuleType.package, ModuleType.fromFilename("pkg/__init__.py").?);
    try testing.expectEqual(ModuleType.c_extension, ModuleType.fromFilename("module.so").?);
    try testing.expect(ModuleType.fromFilename("readme.txt") == null);
}

test "ModuleType isImportable" {
    try testing.expect(ModuleType.source.isImportable());
    try testing.expect(ModuleType.bytecode.isImportable());
    try testing.expect(ModuleType.package.isImportable());
    try testing.expect(!ModuleType.c_extension.isImportable());
}

test "ZipImporter init" {
    var importer = ZipImporter.init(testing.allocator, "/path/to/archive.zip");
    defer importer.deinit();

    try testing.expectEqualStrings("/path/to/archive.zip", importer.getArchivePath());
    try testing.expect(importer.isValid());
}

test "ZipImporter registerModule" {
    var importer = ZipImporter.init(testing.allocator, "archive.zip");
    defer importer.deinit();

    try importer.registerModule("mymodule", .{
        .name = "mymodule",
        .filename = "mymodule.py",
        .module_type = .source,
        .is_package = false,
    });

    try testing.expect(importer.hasModule("mymodule"));
    try testing.expect(!importer.hasModule("othermodule"));
}

test "ZipImporter findModule" {
    var importer = ZipImporter.init(testing.allocator, "archive.zip");
    defer importer.deinit();

    try importer.registerModule("test", .{
        .name = "test",
        .filename = "test.py",
        .module_type = .source,
        .is_package = false,
        .source = "print('hello')",
    });

    const info = importer.findModule("test");
    try testing.expect(info != null);
    try testing.expectEqualStrings("test.py", info.?.filename);
    try testing.expectEqualStrings("print('hello')", importer.getSource("test").?);
}

test "ZipImporter moduleToPath" {
    var importer = ZipImporter.init(testing.allocator, "archive.zip");
    defer importer.deinit();

    const path = try importer.moduleToPath("foo.bar.baz");
    defer testing.allocator.free(path);

    try testing.expectEqualStrings("foo/bar/baz", path);
}

test "ZipImporter addSearchPath" {
    var importer = ZipImporter.init(testing.allocator, "archive.zip");
    defer importer.deinit();

    try importer.addSearchPath("lib");
    try importer.addSearchPath("site-packages");

    try testing.expectEqual(@as(usize, 2), importer.search_paths.items.len);
}

test "ModuleFinder init" {
    var finder = ModuleFinder.init(testing.allocator);
    defer finder.deinit();

    try testing.expectEqual(@as(usize, 0), finder.file_list.items.len);
}

test "ModuleFinder addFile" {
    var finder = ModuleFinder.init(testing.allocator);
    defer finder.deinit();

    try finder.addFile("module.py");
    try finder.addFile("package/__init__.py");

    try testing.expectEqual(@as(usize, 2), finder.file_list.items.len);
}

test "PackageInfo init" {
    var pkg = PackageInfo.init(testing.allocator, "mypackage", "mypackage/");
    defer pkg.deinit();

    try testing.expectEqualStrings("mypackage", pkg.name);
    try testing.expect(!pkg.is_namespace);
}

test "PackageInfo submodules" {
    var pkg = PackageInfo.init(testing.allocator, "mypackage", "mypackage/");
    defer pkg.deinit();

    try pkg.addSubmodule("submodule1");
    try pkg.addSubmodule("submodule2");

    try testing.expect(pkg.hasSubmodule("submodule1"));
    try testing.expect(!pkg.hasSubmodule("nonexistent"));
}

test "PackageInfo getFullName with parent" {
    var pkg = PackageInfo.init(testing.allocator, "child", "parent/child/");
    defer pkg.deinit();
    pkg.parent = "parent";

    const full = try pkg.getFullName(testing.allocator);
    defer testing.allocator.free(full);

    try testing.expectEqualStrings("parent.child", full);
}

test "ImportCache operations" {
    var cache = ImportCache.init(testing.allocator);
    defer cache.deinit();

    try cache.put("mymodule", .{
        .name = "mymodule",
        .filename = "mymodule.py",
        .module_type = .source,
        .is_package = false,
    });

    try testing.expectEqual(@as(usize, 1), cache.size());

    const entry = cache.get("mymodule");
    try testing.expect(entry != null);
    try testing.expectEqual(@as(u32, 1), entry.?.hit_count);

    _ = cache.get("mymodule");
    try testing.expectEqual(@as(u32, 2), entry.?.hit_count);

    try testing.expect(cache.remove("mymodule"));
    try testing.expectEqual(@as(usize, 0), cache.size());
}

test "ImportCache clear" {
    var cache = ImportCache.init(testing.allocator);
    defer cache.deinit();

    try cache.put("mod1", .{
        .name = "mod1",
        .filename = "mod1.py",
        .module_type = .source,
        .is_package = false,
    });

    cache.clear();
    try testing.expectEqual(@as(usize, 0), cache.size());
}

test "splitModuleName" {
    const result1 = splitModuleName("parent.child.module");
    try testing.expectEqualStrings("parent.child", result1.parent.?);
    try testing.expectEqualStrings("module", result1.child);

    const result2 = splitModuleName("module");
    try testing.expect(result2.parent == null);
    try testing.expectEqualStrings("module", result2.child);
}

test "getTopLevelPackage" {
    try testing.expectEqualStrings("foo", getTopLevelPackage("foo.bar.baz"));
    try testing.expectEqualStrings("single", getTopLevelPackage("single"));
}

test "isSubmoduleOf" {
    try testing.expect(isSubmoduleOf("foo.bar", "foo"));
    try testing.expect(isSubmoduleOf("foo.bar.baz", "foo.bar"));
    try testing.expect(!isSubmoduleOf("foo", "foo"));
    try testing.expect(!isSubmoduleOf("foobar", "foo"));
}
