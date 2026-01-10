//! test.test_import.test_pkg - Package imports testing
//!
//! Tests for Python's package import system including:
//! - Regular packages (__init__.py)
//! - Namespace packages (PEP 420)
//! - Package __path__ attribute
//! - Subpackage imports
//! - Package resource access
//! - Package __all__ attribute

const std = @import("std");
const Allocator = std.mem.Allocator;

/// PackageError - Errors related to package operations
pub const PackageError = error{
    NotAPackage,
    InvalidPackagePath,
    SubmoduleNotFound,
    InitFileNotFound,
    OutOfMemory,
};

/// Package represents a Python package
pub const Package = struct {
    name: []const u8,
    path: PackagePath,
    init_module: ?*Module,
    submodules: std.StringHashMapUnmanaged(*Module),
    subpackages: std.StringHashMapUnmanaged(*Package),
    __all__: ?[]const []const u8,
    is_namespace: bool,
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8, is_namespace: bool) !*Package {
        const pkg = try allocator.create(Package);
        pkg.* = .{
            .name = name,
            .path = PackagePath.init(allocator),
            .init_module = null,
            .submodules = .{},
            .subpackages = .{},
            .__all__ = null,
            .is_namespace = is_namespace,
            .allocator = allocator,
        };
        return pkg;
    }

    pub fn deinit(self: *Package) void {
        self.path.deinit();
        self.submodules.deinit(self.allocator);
        self.subpackages.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Check if this is a namespace package (no __init__.py)
    pub fn isNamespacePackage(self: *const Package) bool {
        return self.is_namespace;
    }

    /// Get the qualified name of the package
    pub fn getQualifiedName(self: *const Package) []const u8 {
        return self.name;
    }

    /// Get a submodule by name
    pub fn getSubmodule(self: *const Package, name: []const u8) ?*Module {
        return self.submodules.get(name);
    }

    /// Get a subpackage by name
    pub fn getSubpackage(self: *const Package, name: []const u8) ?*Package {
        return self.subpackages.get(name);
    }

    /// Add a submodule
    pub fn addSubmodule(self: *Package, name: []const u8, module: *Module) !void {
        try self.submodules.put(self.allocator, name, module);
    }

    /// Add a subpackage
    pub fn addSubpackage(self: *Package, name: []const u8, pkg: *Package) !void {
        try self.subpackages.put(self.allocator, name, pkg);
    }

    /// Check if a name is in __all__
    pub fn isExported(self: *const Package, name: []const u8) bool {
        if (self.__all__) |all| {
            for (all) |exported| {
                if (std.mem.eql(u8, exported, name)) return true;
            }
            return false;
        }
        // If no __all__, everything is exported (unless starts with _)
        return !std.mem.startsWith(u8, name, "_");
    }

    /// Get all exported names
    pub fn getExportedNames(self: *const Package, allocator: Allocator) ![][]const u8 {
        if (self.__all__) |all| {
            const result = try allocator.alloc([]const u8, all.len);
            @memcpy(result, all);
            return result;
        }

        // Return all public names
        var result = std.ArrayList([]const u8).init(allocator);
        var iter = self.submodules.keyIterator();
        while (iter.next()) |key| {
            if (!std.mem.startsWith(u8, key.*, "_")) {
                try result.append(key.*);
            }
        }
        return result.toOwnedSlice();
    }
};

/// PackagePath represents __path__ attribute
pub const PackagePath = struct {
    paths: std.ArrayListUnmanaged([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) PackagePath {
        return .{
            .paths = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PackagePath) void {
        self.paths.deinit(self.allocator);
    }

    pub fn append(self: *PackagePath, path: []const u8) !void {
        try self.paths.append(self.allocator, path);
    }

    pub fn insert(self: *PackagePath, index: usize, path: []const u8) !void {
        try self.paths.insert(self.allocator, index, path);
    }

    pub fn remove(self: *PackagePath, path: []const u8) bool {
        for (self.paths.items, 0..) |p, i| {
            if (std.mem.eql(u8, p, path)) {
                _ = self.paths.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn len(self: *const PackagePath) usize {
        return self.paths.items.len;
    }

    pub fn get(self: *const PackagePath, index: usize) ?[]const u8 {
        if (index >= self.paths.items.len) return null;
        return self.paths.items[index];
    }

    pub fn contains(self: *const PackagePath, path: []const u8) bool {
        for (self.paths.items) |p| {
            if (std.mem.eql(u8, p, path)) return true;
        }
        return false;
    }

    pub fn toSlice(self: *const PackagePath) []const []const u8 {
        return self.paths.items;
    }
};

/// Module representation
pub const Module = struct {
    __name__: []const u8,
    __file__: ?[]const u8,
    __package__: ?[]const u8,
    __path__: ?PackagePath,
    __doc__: ?[]const u8,
    __dict__: std.StringHashMapUnmanaged(Value),
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8) !*Module {
        const module = try allocator.create(Module);
        module.* = .{
            .__name__ = name,
            .__file__ = null,
            .__package__ = null,
            .__path__ = null,
            .__doc__ = null,
            .__dict__ = .{},
            .allocator = allocator,
        };
        return module;
    }

    pub fn deinit(self: *Module) void {
        if (self.__path__) |*p| p.deinit();
        self.__dict__.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn isPackage(self: *const Module) bool {
        return self.__path__ != null;
    }

    pub fn setAttr(self: *Module, name: []const u8, value: Value) !void {
        try self.__dict__.put(self.allocator, name, value);
    }

    pub fn getAttr(self: *const Module, name: []const u8) ?Value {
        return self.__dict__.get(name);
    }
};

/// Value type
pub const Value = union(enum) {
    none,
    boolean: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    list: []const []const u8,
    module: *Module,
    package: *Package,
};

/// NamespacePackage - PEP 420 namespace package support
pub const NamespacePackage = struct {
    name: []const u8,
    portions: std.ArrayListUnmanaged(Portion),
    allocator: Allocator,

    pub const Portion = struct {
        path: []const u8,
        finder: ?*anyopaque,
    };

    pub fn init(allocator: Allocator, name: []const u8) !*NamespacePackage {
        const pkg = try allocator.create(NamespacePackage);
        pkg.* = .{
            .name = name,
            .portions = .{},
            .allocator = allocator,
        };
        return pkg;
    }

    pub fn deinit(self: *NamespacePackage) void {
        self.portions.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn addPortion(self: *NamespacePackage, path: []const u8, finder: ?*anyopaque) !void {
        try self.portions.append(self.allocator, .{ .path = path, .finder = finder });
    }

    pub fn getPath(self: *const NamespacePackage, allocator: Allocator) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(allocator);
        for (self.portions.items) |portion| {
            try result.append(portion.path);
        }
        return result.toOwnedSlice();
    }

    pub fn hasPortions(self: *const NamespacePackage) bool {
        return self.portions.items.len > 0;
    }
};

/// PackageLoader - Loads packages and their init modules
pub const PackageLoader = struct {
    search_path: std.ArrayListUnmanaged([]const u8),
    loaded_packages: std.StringHashMapUnmanaged(*Package),
    allocator: Allocator,

    pub fn init(allocator: Allocator) PackageLoader {
        return .{
            .search_path = .{},
            .loaded_packages = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PackageLoader) void {
        self.search_path.deinit(self.allocator);
        self.loaded_packages.deinit(self.allocator);
    }

    pub fn addSearchPath(self: *PackageLoader, path: []const u8) !void {
        try self.search_path.append(self.allocator, path);
    }

    /// Find a package by name
    pub fn findPackage(self: *PackageLoader, name: []const u8) ?*Package {
        return self.loaded_packages.get(name);
    }

    /// Check if a path contains a package (has __init__.py)
    pub fn isPackageDir(self: *const PackageLoader, path: []const u8) bool {
        // Would check for __init__.py existence
        _ = self;
        _ = path;
        return false;
    }

    /// Check if this is a namespace package (no __init__.py but submodules exist)
    pub fn isNamespacePackageDir(self: *const PackageLoader, path: []const u8) bool {
        // Would check for directory without __init__.py but with .py files
        _ = self;
        _ = path;
        return false;
    }

    /// Load a package
    pub fn loadPackage(self: *PackageLoader, name: []const u8) !*Package {
        // Check if already loaded
        if (self.loaded_packages.get(name)) |pkg| {
            return pkg;
        }

        // Create new package
        const is_namespace = false; // Would determine based on __init__.py
        const pkg = try Package.init(self.allocator, name, is_namespace);

        // Cache it
        try self.loaded_packages.put(self.allocator, name, pkg);

        return pkg;
    }

    /// Get all loaded package names
    pub fn getLoadedPackageNames(self: *const PackageLoader, allocator: Allocator) ![][]const u8 {
        var result = std.ArrayList([]const u8).init(allocator);
        var iter = self.loaded_packages.keyIterator();
        while (iter.next()) |key| {
            try result.append(key.*);
        }
        return result.toOwnedSlice();
    }
};

/// PackageResource - Access to package resources (data files)
pub const PackageResource = struct {
    package: *const Package,
    allocator: Allocator,

    pub fn init(allocator: Allocator, package: *const Package) PackageResource {
        return .{
            .package = package,
            .allocator = allocator,
        };
    }

    /// Check if a resource exists
    pub fn isResource(self: *const PackageResource, name: []const u8) bool {
        // Would check if file exists in package path
        _ = self;
        _ = name;
        return false;
    }

    /// Get list of resources
    pub fn contents(self: *const PackageResource) ![][]const u8 {
        // Would list files in package directory
        return self.allocator.alloc([]const u8, 0);
    }

    /// Read a text resource
    pub fn readText(self: *const PackageResource, name: []const u8) ![]const u8 {
        _ = self;
        _ = name;
        return error.InvalidPackagePath;
    }

    /// Read binary resource
    pub fn readBinary(self: *const PackageResource, name: []const u8) ![]const u8 {
        _ = self;
        _ = name;
        return error.InvalidPackagePath;
    }

    /// Get path to resource (if available)
    pub fn path(self: *const PackageResource, name: []const u8) ![]const u8 {
        // Construct path to resource
        for (self.package.path.paths.items) |pkg_path| {
            var buf: [512]u8 = undefined;
            const resource_path = std.fmt.bufPrint(&buf, "{s}/{s}", .{ pkg_path, name }) catch continue;
            return resource_path;
        }
        return error.InvalidPackagePath;
    }
};

/// PackageUtils - Utility functions for packages
pub const PackageUtils = struct {
    /// Get the parent package name
    pub fn getParentPackage(fullname: []const u8) ?[]const u8 {
        if (std.mem.lastIndexOfScalar(u8, fullname, '.')) |idx| {
            return fullname[0..idx];
        }
        return null;
    }

    /// Get the tail module name
    pub fn getTailName(fullname: []const u8) []const u8 {
        if (std.mem.lastIndexOfScalar(u8, fullname, '.')) |idx| {
            return fullname[idx + 1 ..];
        }
        return fullname;
    }

    /// Check if name looks like a package path
    pub fn isPackageName(name: []const u8) bool {
        // Has dots and valid identifiers
        var iter = std.mem.splitScalar(u8, name, '.');
        while (iter.next()) |part| {
            if (part.len == 0) return false;
            if (!isValidIdentifier(part)) return false;
        }
        return true;
    }

    fn isValidIdentifier(name: []const u8) bool {
        if (name.len == 0) return false;
        const first = name[0];
        if (!std.ascii.isAlphabetic(first) and first != '_') return false;
        for (name[1..]) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
        }
        return true;
    }

    /// Split a module name into package parts
    pub fn splitName(allocator: Allocator, fullname: []const u8) ![][]const u8 {
        var parts = std.ArrayList([]const u8).init(allocator);
        var iter = std.mem.splitScalar(u8, fullname, '.');
        while (iter.next()) |part| {
            try parts.append(part);
        }
        return parts.toOwnedSlice();
    }

    /// Join package parts into a name
    pub fn joinName(allocator: Allocator, parts: []const []const u8) ![]u8 {
        var total_len: usize = 0;
        for (parts, 0..) |part, i| {
            total_len += part.len;
            if (i < parts.len - 1) total_len += 1;
        }

        const result = try allocator.alloc(u8, total_len);
        var pos: usize = 0;
        for (parts, 0..) |part, i| {
            @memcpy(result[pos..][0..part.len], part);
            pos += part.len;
            if (i < parts.len - 1) {
                result[pos] = '.';
                pos += 1;
            }
        }
        return result;
    }
};

// =============================================================================
// Tests
// =============================================================================

test "package_creation" {
    const pkg = try Package.init(std.testing.allocator, "mypackage", false);
    defer pkg.deinit();

    try std.testing.expectEqualStrings("mypackage", pkg.name);
    try std.testing.expect(!pkg.isNamespacePackage());
}

test "namespace_package_creation" {
    const pkg = try Package.init(std.testing.allocator, "namespace_pkg", true);
    defer pkg.deinit();

    try std.testing.expect(pkg.isNamespacePackage());
}

test "package_path" {
    var path = PackagePath.init(std.testing.allocator);
    defer path.deinit();

    try path.append("/usr/lib/python3/mypackage");
    try path.append("/home/user/.local/lib/python3/mypackage");

    try std.testing.expectEqual(@as(usize, 2), path.len());
    try std.testing.expect(path.contains("/usr/lib/python3/mypackage"));
    try std.testing.expect(!path.contains("/nonexistent"));

    try std.testing.expect(path.remove("/usr/lib/python3/mypackage"));
    try std.testing.expectEqual(@as(usize, 1), path.len());
}

test "package_path_insert" {
    var path = PackagePath.init(std.testing.allocator);
    defer path.deinit();

    try path.append("/path/a");
    try path.append("/path/c");
    try path.insert(1, "/path/b");

    try std.testing.expectEqual(@as(usize, 3), path.len());
    try std.testing.expectEqualStrings("/path/a", path.get(0).?);
    try std.testing.expectEqualStrings("/path/b", path.get(1).?);
    try std.testing.expectEqualStrings("/path/c", path.get(2).?);
}

test "package_exported_names" {
    const pkg = try Package.init(std.testing.allocator, "test_pkg", false);
    defer pkg.deinit();

    // Without __all__, underscore names are not exported
    try std.testing.expect(!pkg.isExported("_private"));
    try std.testing.expect(pkg.isExported("public"));
}

test "package_with_all" {
    var pkg_stack: Package = undefined;
    pkg_stack.name = "test";
    pkg_stack.__all__ = &.{ "foo", "bar" };
    pkg_stack.is_namespace = false;
    pkg_stack.submodules = .{};
    pkg_stack.subpackages = .{};
    pkg_stack.init_module = null;
    pkg_stack.allocator = std.testing.allocator;
    pkg_stack.path = PackagePath.init(std.testing.allocator);
    defer pkg_stack.path.deinit();

    try std.testing.expect(pkg_stack.isExported("foo"));
    try std.testing.expect(pkg_stack.isExported("bar"));
    try std.testing.expect(!pkg_stack.isExported("baz"));
}

test "namespace_package_portions" {
    const ns_pkg = try NamespacePackage.init(std.testing.allocator, "ns_pkg");
    defer ns_pkg.deinit();

    try ns_pkg.addPortion("/path/a/ns_pkg", null);
    try ns_pkg.addPortion("/path/b/ns_pkg", null);

    try std.testing.expect(ns_pkg.hasPortions());

    const paths = try ns_pkg.getPath(std.testing.allocator);
    defer std.testing.allocator.free(paths);

    try std.testing.expectEqual(@as(usize, 2), paths.len);
}

test "package_loader_init" {
    var loader = PackageLoader.init(std.testing.allocator);
    defer loader.deinit();

    try loader.addSearchPath("/usr/lib/python3");
    try std.testing.expectEqual(@as(usize, 1), loader.search_path.items.len);
}

test "package_utils_parent" {
    const parent1 = PackageUtils.getParentPackage("foo.bar.baz");
    try std.testing.expect(parent1 != null);
    try std.testing.expectEqualStrings("foo.bar", parent1.?);

    const parent2 = PackageUtils.getParentPackage("foo");
    try std.testing.expect(parent2 == null);
}

test "package_utils_tail" {
    const tail1 = PackageUtils.getTailName("foo.bar.baz");
    try std.testing.expectEqualStrings("baz", tail1);

    const tail2 = PackageUtils.getTailName("foo");
    try std.testing.expectEqualStrings("foo", tail2);
}

test "package_utils_is_package_name" {
    try std.testing.expect(PackageUtils.isPackageName("foo"));
    try std.testing.expect(PackageUtils.isPackageName("foo.bar"));
    try std.testing.expect(PackageUtils.isPackageName("foo.bar.baz"));
    try std.testing.expect(PackageUtils.isPackageName("_private"));
    try std.testing.expect(!PackageUtils.isPackageName(""));
    try std.testing.expect(!PackageUtils.isPackageName("foo..bar"));
    try std.testing.expect(!PackageUtils.isPackageName("123foo"));
}

test "package_utils_split_name" {
    const parts = try PackageUtils.splitName(std.testing.allocator, "foo.bar.baz");
    defer std.testing.allocator.free(parts);

    try std.testing.expectEqual(@as(usize, 3), parts.len);
    try std.testing.expectEqualStrings("foo", parts[0]);
    try std.testing.expectEqualStrings("bar", parts[1]);
    try std.testing.expectEqualStrings("baz", parts[2]);
}

test "package_utils_join_name" {
    const name = try PackageUtils.joinName(std.testing.allocator, &.{ "foo", "bar", "baz" });
    defer std.testing.allocator.free(name);

    try std.testing.expectEqualStrings("foo.bar.baz", name);
}

test "module_is_package" {
    const module = try Module.init(std.testing.allocator, "test");
    defer module.deinit();

    try std.testing.expect(!module.isPackage());

    module.__path__ = PackagePath.init(std.testing.allocator);
    try std.testing.expect(module.isPackage());
}
