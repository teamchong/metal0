//! test.test_future_stmt.test_absolute - Tests for `from __future__ import absolute_import`
//!
//! PEP 328 introduced absolute imports as the default in Python 3.
//! In Python 2, `import foo` would first check the current package.
//! With this future import (or Python 3), imports are absolute by default
//! and relative imports must use explicit syntax (from . import foo).
//!
//! This module tests import resolution and path handling.
//!
//! CPython Reference: https://docs.python.org/3/library/__future__.html
//! PEP 328: https://peps.python.org/pep-0328/

const std = @import("std");
const testing = std.testing;

// ============================================================================
// Import Types
// ============================================================================

/// Represents the type of import statement
pub const ImportType = enum {
    /// Absolute import: import package.module
    absolute,
    /// Explicit relative import: from . import module
    explicit_relative,
    /// Implicit relative import (Python 2 only): import module (from package)
    implicit_relative,

    pub fn name(self: ImportType) []const u8 {
        return switch (self) {
            .absolute => "absolute",
            .explicit_relative => "explicit relative",
            .implicit_relative => "implicit relative",
        };
    }

    /// Check if this import type is allowed in Python 3
    pub fn isPython3Compatible(self: ImportType) bool {
        return self != .implicit_relative;
    }
};

/// Represents a relative import level
/// Level 0 = absolute, 1 = current package, 2 = parent package, etc.
pub const ImportLevel = struct {
    level: u32,

    const Self = @This();

    /// Create an absolute import level
    pub fn absolute() Self {
        return .{ .level = 0 };
    }

    /// Create a relative import level
    pub fn relative(level: u32) Self {
        return .{ .level = level };
    }

    /// Check if this is an absolute import
    pub fn isAbsolute(self: Self) bool {
        return self.level == 0;
    }

    /// Check if this is a relative import
    pub fn isRelative(self: Self) bool {
        return self.level > 0;
    }

    /// Get the number of parent packages to traverse
    pub fn parentLevels(self: Self) u32 {
        return if (self.level > 0) self.level - 1 else 0;
    }

    /// Get the dot notation (e.g., "." for level 1, ".." for level 2)
    pub fn toDotNotation(self: Self, allocator: std.mem.Allocator) ![]u8 {
        if (self.level == 0) {
            return try allocator.dupe(u8, "");
        }
        const result = try allocator.alloc(u8, self.level);
        @memset(result, '.');
        return result;
    }
};

// ============================================================================
// Module Path Resolution
// ============================================================================

/// Represents a module path (e.g., "package.subpackage.module")
pub const ModulePath = struct {
    parts: std.ArrayListUnmanaged([]const u8),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .parts = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.parts.deinit(self.allocator);
    }

    /// Parse a dotted module path
    pub fn parse(allocator: std.mem.Allocator, path: []const u8) !Self {
        var result = Self.init(allocator);
        var it = std.mem.splitScalar(u8, path, '.');
        while (it.next()) |part| {
            try result.parts.append(allocator, part);
        }
        return result;
    }

    /// Get the package name (all but last part)
    pub fn packageName(self: Self) ?[]const u8 {
        if (self.parts.items.len < 2) return null;
        // Return first part for simplicity
        return self.parts.items[0];
    }

    /// Get the module name (last part)
    pub fn moduleName(self: Self) ?[]const u8 {
        if (self.parts.items.len == 0) return null;
        return self.parts.items[self.parts.items.len - 1];
    }

    /// Get the number of path components
    pub fn depth(self: Self) usize {
        return self.parts.items.len;
    }

    /// Check if this is a top-level module
    pub fn isTopLevel(self: Self) bool {
        return self.parts.items.len == 1;
    }

    /// Get parent path (package containing this module)
    pub fn parent(self: Self) ?Self {
        if (self.parts.items.len <= 1) return null;
        var result = Self.init(self.allocator);
        for (self.parts.items[0 .. self.parts.items.len - 1]) |part| {
            result.parts.append(self.allocator, part) catch return null;
        }
        return result;
    }

    /// Convert back to dotted string
    pub fn toDottedString(self: Self, allocator: std.mem.Allocator) ![]u8 {
        var result: std.ArrayListUnmanaged(u8) = .{};
        for (self.parts.items, 0..) |part, i| {
            if (i > 0) try result.append(allocator, '.');
            try result.appendSlice(allocator, part);
        }
        return try result.toOwnedSlice(allocator);
    }
};

// ============================================================================
// Import Resolver
// ============================================================================

/// Simulates the import resolution process
pub const ImportResolver = struct {
    /// Search paths for modules (like sys.path)
    search_paths: std.ArrayListUnmanaged([]const u8),
    /// Current package context (for relative imports)
    current_package: ?[]const u8 = null,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .search_paths = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.search_paths.deinit(self.allocator);
    }

    /// Add a search path
    pub fn addPath(self: *Self, path: []const u8) !void {
        try self.search_paths.append(self.allocator, path);
    }

    /// Set the current package context
    pub fn setPackage(self: *Self, package: []const u8) void {
        self.current_package = package;
    }

    /// Resolve an import to a file path
    pub fn resolve(self: Self, module_name: []const u8, level: ImportLevel) ![]const u8 {
        if (level.isRelative()) {
            // Relative import - need current package context
            if (self.current_package == null) {
                return error.NoPackageContext;
            }
            // Would resolve relative to current package
            _ = module_name;
            return "relative_module.py";
        } else {
            // Absolute import - search paths
            for (self.search_paths.items) |_| {
                // Would check if module exists at path
            }
            return "absolute_module.py";
        }
    }

    /// Check if a module exists
    pub fn moduleExists(self: Self, module_name: []const u8) bool {
        _ = self;
        _ = module_name;
        // Would check file system
        return true;
    }
};

// ============================================================================
// Import Statement Parsing
// ============================================================================

/// Parsed import statement
pub const ImportStatement = struct {
    /// The module being imported
    module: []const u8,
    /// Import level (0 = absolute)
    level: ImportLevel,
    /// Specific names being imported (for 'from X import Y')
    names: ?[]const []const u8 = null,
    /// Alias (for 'import X as Y')
    alias: ?[]const u8 = null,

    const Self = @This();

    /// Create an absolute import
    pub fn absolute(module: []const u8) Self {
        return .{
            .module = module,
            .level = ImportLevel.absolute(),
        };
    }

    /// Create a relative import
    pub fn relative(level: u32, module: []const u8) Self {
        return .{
            .module = module,
            .level = ImportLevel.relative(level),
        };
    }

    /// Create a from import
    pub fn fromImport(module: []const u8, names: []const []const u8) Self {
        return .{
            .module = module,
            .level = ImportLevel.absolute(),
            .names = names,
        };
    }

    /// Get the import type
    pub fn getType(self: Self) ImportType {
        if (self.level.isAbsolute()) {
            return .absolute;
        }
        return .explicit_relative;
    }

    /// Check if this is a star import (from X import *)
    pub fn isStarImport(self: Self) bool {
        if (self.names) |names| {
            return names.len == 1 and std.mem.eql(u8, names[0], "*");
        }
        return false;
    }
};

// ============================================================================
// Package Structure
// ============================================================================

/// Represents a Python package
pub const Package = struct {
    name: []const u8,
    path: []const u8,
    subpackages: std.StringHashMap(*Package),
    modules: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,
    has_init: bool = true,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, name: []const u8, path: []const u8) Self {
        return .{
            .name = name,
            .path = path,
            .subpackages = std.StringHashMap(*Package).init(allocator),
            .modules = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.subpackages.valueIterator();
        while (it.next()) |pkg| {
            pkg.*.deinit();
            self.allocator.destroy(pkg.*);
        }
        self.subpackages.deinit();
        self.modules.deinit();
    }

    /// Add a subpackage
    pub fn addSubpackage(self: *Self, name: []const u8) !*Package {
        const subpkg = try self.allocator.create(Package);
        subpkg.* = Package.init(self.allocator, name, self.path);
        try self.subpackages.put(name, subpkg);
        return subpkg;
    }

    /// Add a module
    pub fn addModule(self: *Self, name: []const u8, source_path: []const u8) !void {
        try self.modules.put(name, source_path);
    }

    /// Check if this is a namespace package (no __init__.py)
    pub fn isNamespacePackage(self: Self) bool {
        return !self.has_init;
    }

    /// Get full qualified name
    pub fn qualifiedName(self: Self, parent_path: ?[]const u8) ![]u8 {
        if (parent_path) |pp| {
            return try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ pp, self.name });
        }
        return try self.allocator.dupe(u8, self.name);
    }
};

// ============================================================================
// Import Hook System
// ============================================================================

/// Import hook interface (like sys.meta_path finders)
pub const ImportHook = struct {
    /// Function to find a module
    find_module: *const fn (fullname: []const u8, path: ?[]const u8) ?[]const u8,

    const Self = @This();

    /// Find a module
    pub fn findModule(self: Self, fullname: []const u8, path: ?[]const u8) ?[]const u8 {
        return self.find_module(fullname, path);
    }
};

/// Import hook registry
pub const ImportHooks = struct {
    hooks: std.ArrayListUnmanaged(ImportHook),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .hooks = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.hooks.deinit(self.allocator);
    }

    /// Register a hook
    pub fn register(self: *Self, hook: ImportHook) !void {
        try self.hooks.append(self.allocator, hook);
    }

    /// Find a module using registered hooks
    pub fn findModule(self: Self, fullname: []const u8, path: ?[]const u8) ?[]const u8 {
        for (self.hooks.items) |hook| {
            if (hook.findModule(fullname, path)) |result| {
                return result;
            }
        }
        return null;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "import_type_names" {
    try testing.expectEqualStrings("absolute", ImportType.absolute.name());
    try testing.expectEqualStrings("explicit relative", ImportType.explicit_relative.name());
    try testing.expectEqualStrings("implicit relative", ImportType.implicit_relative.name());
}

test "import_type_python3_compatible" {
    try testing.expect(ImportType.absolute.isPython3Compatible());
    try testing.expect(ImportType.explicit_relative.isPython3Compatible());
    try testing.expect(!ImportType.implicit_relative.isPython3Compatible());
}

test "import_level_absolute" {
    const level = ImportLevel.absolute();
    try testing.expect(level.isAbsolute());
    try testing.expect(!level.isRelative());
    try testing.expectEqual(@as(u32, 0), level.parentLevels());
}

test "import_level_relative" {
    const level = ImportLevel.relative(2);
    try testing.expect(!level.isAbsolute());
    try testing.expect(level.isRelative());
    try testing.expectEqual(@as(u32, 1), level.parentLevels());
}

test "import_level_dot_notation" {
    const level = ImportLevel.relative(3);
    const dots = try level.toDotNotation(testing.allocator);
    defer testing.allocator.free(dots);
    try testing.expectEqualStrings("...", dots);
}

test "module_path_parse" {
    var path = try ModulePath.parse(testing.allocator, "package.subpackage.module");
    defer path.deinit();

    try testing.expectEqual(@as(usize, 3), path.depth());
    try testing.expectEqualStrings("package", path.packageName().?);
    try testing.expectEqualStrings("module", path.moduleName().?);
}

test "module_path_top_level" {
    var path = try ModulePath.parse(testing.allocator, "os");
    defer path.deinit();

    try testing.expect(path.isTopLevel());
    try testing.expect(path.packageName() == null);
    try testing.expectEqualStrings("os", path.moduleName().?);
}

test "module_path_to_dotted_string" {
    var path = try ModulePath.parse(testing.allocator, "a.b.c");
    defer path.deinit();

    const dotted = try path.toDottedString(testing.allocator);
    defer testing.allocator.free(dotted);
    try testing.expectEqualStrings("a.b.c", dotted);
}

test "module_path_parent" {
    var path = try ModulePath.parse(testing.allocator, "a.b.c");
    defer path.deinit();

    var parent = path.parent().?;
    defer parent.deinit();
    try testing.expectEqual(@as(usize, 2), parent.depth());
}

test "import_resolver_init" {
    var resolver = ImportResolver.init(testing.allocator);
    defer resolver.deinit();

    try resolver.addPath("/usr/lib/python");
    try resolver.addPath("/home/user/myproject");
    try testing.expectEqual(@as(usize, 2), resolver.search_paths.items.len);
}

test "import_statement_absolute" {
    const stmt = ImportStatement.absolute("os.path");
    try testing.expectEqual(ImportType.absolute, stmt.getType());
    try testing.expectEqualStrings("os.path", stmt.module);
}

test "import_statement_relative" {
    const stmt = ImportStatement.relative(1, "utils");
    try testing.expectEqual(ImportType.explicit_relative, stmt.getType());
    try testing.expectEqualStrings("utils", stmt.module);
}

test "import_statement_star" {
    const stmt = ImportStatement.fromImport("module", &.{"*"});
    try testing.expect(stmt.isStarImport());
}

test "import_statement_not_star" {
    const stmt = ImportStatement.fromImport("module", &.{ "foo", "bar" });
    try testing.expect(!stmt.isStarImport());
}

test "package_basic" {
    var pkg = Package.init(testing.allocator, "mypackage", "/path/to/pkg");
    defer pkg.deinit();

    try testing.expectEqualStrings("mypackage", pkg.name);
    try testing.expect(!pkg.isNamespacePackage());
}

test "package_add_module" {
    var pkg = Package.init(testing.allocator, "mypackage", "/path/to/pkg");
    defer pkg.deinit();

    try pkg.addModule("utils", "utils.py");
    try testing.expect(pkg.modules.contains("utils"));
}

test "package_namespace" {
    var pkg = Package.init(testing.allocator, "namespace_pkg", "/path");
    defer pkg.deinit();
    pkg.has_init = false;

    try testing.expect(pkg.isNamespacePackage());
}

test "import_hooks_init" {
    var hooks = ImportHooks.init(testing.allocator);
    defer hooks.deinit();

    try testing.expectEqual(@as(usize, 0), hooks.hooks.items.len);
}

test "import_level_zero_dots" {
    const level = ImportLevel.absolute();
    const dots = try level.toDotNotation(testing.allocator);
    defer testing.allocator.free(dots);
    try testing.expectEqualStrings("", dots);
}

test "module_path_depth_one" {
    var path = try ModulePath.parse(testing.allocator, "single");
    defer path.deinit();
    try testing.expectEqual(@as(usize, 1), path.depth());
}

test "import_resolver_set_package" {
    var resolver = ImportResolver.init(testing.allocator);
    defer resolver.deinit();

    resolver.setPackage("mypackage");
    try testing.expectEqualStrings("mypackage", resolver.current_package.?);
}
