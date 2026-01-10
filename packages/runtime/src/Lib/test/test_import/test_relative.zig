//! test.test_import.test_relative - Relative imports testing
//!
//! Tests for Python's relative import system including:
//! - Intra-package imports (from . import x)
//! - Parent package imports (from .. import x)
//! - Multiple level relative imports
//! - Relative import resolution
//! - Edge cases and error handling

const std = @import("std");
const Allocator = std.mem.Allocator;

/// RelativeImportError - Errors specific to relative imports
pub const RelativeImportError = error{
    ImportError,
    KeyError,
    ValueError,
    SystemError,
    OutOfMemory,
    AttemptedRelativeImportBeyondTopLevel,
    AttemptedRelativeImportInNonPackage,
    NoKnownParentPackage,
    ParentPackageNotLoaded,
};

/// Import level for relative imports
pub const ImportLevel = enum(i32) {
    absolute = 0,
    current = 1,
    parent = 2,
    grandparent = 3,

    pub fn fromInt(level: i32) ImportLevel {
        return switch (level) {
            0 => .absolute,
            1 => .current,
            2 => .parent,
            3 => .grandparent,
            else => .absolute, // Fallback for higher levels
        };
    }

    pub fn toInt(self: ImportLevel) i32 {
        return @intFromEnum(self);
    }
};

/// RelativeImportContext - Context for resolving relative imports
pub const RelativeImportContext = struct {
    /// The __name__ of the importing module
    module_name: []const u8,

    /// The __package__ of the importing module
    package: ?[]const u8,

    /// The __spec__.parent if available
    spec_parent: ?[]const u8,

    pub fn init(module_name: []const u8, package: ?[]const u8) RelativeImportContext {
        return .{
            .module_name = module_name,
            .package = package,
            .spec_parent = null,
        };
    }

    /// Get the effective package for relative imports
    pub fn getPackage(self: *const RelativeImportContext) ?[]const u8 {
        // __package__ takes precedence
        if (self.package) |pkg| {
            if (pkg.len > 0) return pkg;
        }

        // Fall back to __spec__.parent
        if (self.spec_parent) |parent| {
            return parent;
        }

        // Fall back to deriving from __name__
        // If __name__ ends with .__init__, use parent
        if (std.mem.endsWith(u8, self.module_name, ".__init__")) {
            return self.module_name[0 .. self.module_name.len - 9];
        }

        // Check if this is a package (has __path__)
        // For a module, package is parent of __name__
        if (std.mem.lastIndexOfScalar(u8, self.module_name, '.')) |idx| {
            return self.module_name[0..idx];
        }

        return null;
    }

    /// Check if relative imports are valid from this context
    pub fn canDoRelativeImport(self: *const RelativeImportContext) bool {
        return self.getPackage() != null;
    }
};

/// RelativeImportResolver - Resolves relative import names
pub const RelativeImportResolver = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) RelativeImportResolver {
        return .{ .allocator = allocator };
    }

    /// Resolve a relative import to an absolute module name
    /// level: number of dots (1 = ., 2 = .., etc.)
    /// name: the module name after the dots (can be empty for "from . import")
    /// package: the package context
    pub fn resolve(
        self: *const RelativeImportResolver,
        level: u32,
        name: []const u8,
        package: []const u8,
    ) RelativeImportError![]u8 {
        if (level == 0) {
            // Absolute import
            return self.allocator.dupe(u8, name);
        }

        // Split package into parts
        var parts = std.ArrayList([]const u8).init(self.allocator);
        defer parts.deinit();

        var iter = std.mem.splitScalar(u8, package, '.');
        while (iter.next()) |part| {
            try parts.append(part);
        }

        // Go up 'level - 1' levels (level 1 = current package)
        const levels_up = level - 1;
        if (levels_up >= parts.items.len) {
            return error.AttemptedRelativeImportBeyondTopLevel;
        }

        // Remove levels from the end
        const remaining = parts.items.len - levels_up;
        parts.shrinkRetainingCapacity(remaining);

        // Build result
        var result = std.ArrayList(u8).init(self.allocator);

        // Add package parts
        for (parts.items, 0..) |part, i| {
            if (i > 0) try result.append('.');
            try result.appendSlice(part);
        }

        // Add the name if present
        if (name.len > 0) {
            if (result.items.len > 0) try result.append('.');
            try result.appendSlice(name);
        }

        return result.toOwnedSlice();
    }

    /// Parse a relative import string (e.g., "...foo.bar")
    pub fn parseRelativeImport(self: *const RelativeImportResolver, import_str: []const u8) struct { level: u32, name: []const u8 } {
        _ = self;
        var level: u32 = 0;
        var pos: usize = 0;

        // Count leading dots
        while (pos < import_str.len and import_str[pos] == '.') {
            level += 1;
            pos += 1;
        }

        return .{
            .level = level,
            .name = import_str[pos..],
        };
    }

    /// Validate a relative import
    pub fn validateRelativeImport(
        self: *const RelativeImportResolver,
        level: u32,
        package: ?[]const u8,
    ) RelativeImportError!void {
        _ = self;
        if (level == 0) return; // Absolute import, always valid

        if (package == null or package.?.len == 0) {
            return error.AttemptedRelativeImportInNonPackage;
        }

        // Count package depth
        var depth: u32 = 1;
        for (package.?) |c| {
            if (c == '.') depth += 1;
        }

        if (level > depth) {
            return error.AttemptedRelativeImportBeyondTopLevel;
        }
    }
};

/// RelativeFromList - Handle "from .x import a, b, c"
pub const RelativeFromList = struct {
    names: std.ArrayListUnmanaged([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) RelativeFromList {
        return .{
            .names = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RelativeFromList) void {
        self.names.deinit(self.allocator);
    }

    pub fn add(self: *RelativeFromList, name: []const u8) !void {
        try self.names.append(self.allocator, name);
    }

    pub fn hasName(self: *const RelativeFromList, name: []const u8) bool {
        for (self.names.items) |n| {
            if (std.mem.eql(u8, n, name)) return true;
        }
        return false;
    }

    /// Check if this is a star import (from .x import *)
    pub fn isStarImport(self: *const RelativeFromList) bool {
        for (self.names.items) |n| {
            if (std.mem.eql(u8, n, "*")) return true;
        }
        return false;
    }

    pub fn count(self: *const RelativeFromList) usize {
        return self.names.items.len;
    }
};

/// ImportStatement - Represents a parsed import statement
pub const ImportStatement = struct {
    /// The module path (after dots)
    module: []const u8,

    /// Number of dots (0 = absolute)
    level: u32,

    /// Names to import (from ... import x, y, z)
    from_list: ?RelativeFromList,

    /// Alias (import x as y)
    alias: ?[]const u8,

    /// Is this a "from" import?
    is_from_import: bool,

    allocator: Allocator,

    pub fn init(allocator: Allocator) ImportStatement {
        return .{
            .module = "",
            .level = 0,
            .from_list = null,
            .alias = null,
            .is_from_import = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ImportStatement) void {
        if (self.from_list) |*fl| fl.deinit();
    }

    pub fn isRelative(self: *const ImportStatement) bool {
        return self.level > 0;
    }

    pub fn isAbsolute(self: *const ImportStatement) bool {
        return self.level == 0;
    }

    /// Get the import level enum
    pub fn getLevel(self: *const ImportStatement) ImportLevel {
        return ImportLevel.fromInt(@intCast(self.level));
    }
};

/// ModuleHierarchy - Utility for working with module hierarchies
pub const ModuleHierarchy = struct {
    /// Get all ancestor package names for a module
    pub fn getAncestors(allocator: Allocator, fullname: []const u8) ![][]const u8 {
        var ancestors = std.ArrayList([]const u8).init(allocator);

        var current = fullname;
        while (std.mem.lastIndexOfScalar(u8, current, '.')) |idx| {
            current = current[0..idx];
            try ancestors.append(current);
        }

        return ancestors.toOwnedSlice();
    }

    /// Get the depth of a module in the hierarchy
    pub fn getDepth(fullname: []const u8) u32 {
        var depth: u32 = 1;
        for (fullname) |c| {
            if (c == '.') depth += 1;
        }
        return depth;
    }

    /// Check if 'parent' is an ancestor of 'child'
    pub fn isAncestorOf(parent: []const u8, child: []const u8) bool {
        if (parent.len >= child.len) return false;
        if (!std.mem.startsWith(u8, child, parent)) return false;
        return child[parent.len] == '.';
    }

    /// Get the common ancestor of two modules
    pub fn getCommonAncestor(a: []const u8, b: []const u8) ?[]const u8 {
        var last_dot: ?usize = null;
        const min_len = @min(a.len, b.len);

        for (0..min_len) |i| {
            if (a[i] != b[i]) break;
            if (a[i] == '.') last_dot = i;
        }

        if (last_dot) |idx| {
            return a[0..idx];
        }

        return null;
    }
};

/// RelativeImportValidator - Validate relative imports at runtime
pub const RelativeImportValidator = struct {
    /// Check if a module can perform relative imports
    pub fn canImportRelatively(module_name: []const u8, module_package: ?[]const u8) bool {
        // If __package__ is set and non-empty, relative imports are valid
        if (module_package) |pkg| {
            if (pkg.len > 0) return true;
        }

        // If module_name contains a dot, it's in a package
        return std.mem.indexOfScalar(u8, module_name, '.') != null;
    }

    /// Get the effective package for a module
    pub fn getEffectivePackage(module_name: []const u8, module_package: ?[]const u8) ?[]const u8 {
        if (module_package) |pkg| {
            if (pkg.len > 0) return pkg;
        }

        // Derive from module name
        if (std.mem.lastIndexOfScalar(u8, module_name, '.')) |idx| {
            return module_name[0..idx];
        }

        return null;
    }

    /// Validate that a relative import won't go beyond top-level
    pub fn validateLevel(level: u32, package: []const u8) RelativeImportError!void {
        var package_depth: u32 = 1;
        for (package) |c| {
            if (c == '.') package_depth += 1;
        }

        if (level > package_depth) {
            return error.AttemptedRelativeImportBeyondTopLevel;
        }
    }
};

// =============================================================================
// Tests
// =============================================================================

test "import_level_enum" {
    try std.testing.expectEqual(ImportLevel.absolute, ImportLevel.fromInt(0));
    try std.testing.expectEqual(ImportLevel.current, ImportLevel.fromInt(1));
    try std.testing.expectEqual(ImportLevel.parent, ImportLevel.fromInt(2));

    try std.testing.expectEqual(@as(i32, 0), ImportLevel.absolute.toInt());
    try std.testing.expectEqual(@as(i32, 1), ImportLevel.current.toInt());
}

test "relative_import_context" {
    const ctx1 = RelativeImportContext.init("mypackage.submodule", "mypackage");
    try std.testing.expect(ctx1.canDoRelativeImport());
    try std.testing.expectEqualStrings("mypackage", ctx1.getPackage().?);

    const ctx2 = RelativeImportContext.init("toplevel", null);
    try std.testing.expect(!ctx2.canDoRelativeImport());
}

test "relative_import_resolver_basic" {
    const resolver = RelativeImportResolver.init(std.testing.allocator);

    // from . import submodule (level=1, name="submodule", package="mypackage")
    const result1 = try resolver.resolve(1, "submodule", "mypackage");
    defer std.testing.allocator.free(result1);
    try std.testing.expectEqualStrings("mypackage.submodule", result1);

    // from .. import other (level=2, name="other", package="mypackage.sub")
    const result2 = try resolver.resolve(2, "other", "mypackage.sub");
    defer std.testing.allocator.free(result2);
    try std.testing.expectEqualStrings("mypackage.other", result2);
}

test "relative_import_resolver_current_package" {
    const resolver = RelativeImportResolver.init(std.testing.allocator);

    // from . import x in mypackage.submodule
    const result = try resolver.resolve(1, "x", "mypackage");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("mypackage.x", result);
}

test "relative_import_resolver_parent_package" {
    const resolver = RelativeImportResolver.init(std.testing.allocator);

    // from .. import x in mypackage.sub.deep
    const result = try resolver.resolve(2, "x", "mypackage.sub.deep");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("mypackage.sub.x", result);
}

test "relative_import_resolver_beyond_top" {
    const resolver = RelativeImportResolver.init(std.testing.allocator);

    // from ... import x in mypackage (only 1 level deep)
    const result = resolver.resolve(3, "x", "mypackage");
    try std.testing.expectError(error.AttemptedRelativeImportBeyondTopLevel, result);
}

test "relative_import_resolver_parse" {
    const resolver = RelativeImportResolver.init(std.testing.allocator);

    const parsed1 = resolver.parseRelativeImport("...foo.bar");
    try std.testing.expectEqual(@as(u32, 3), parsed1.level);
    try std.testing.expectEqualStrings("foo.bar", parsed1.name);

    const parsed2 = resolver.parseRelativeImport(".module");
    try std.testing.expectEqual(@as(u32, 1), parsed2.level);
    try std.testing.expectEqualStrings("module", parsed2.name);

    const parsed3 = resolver.parseRelativeImport("absolute");
    try std.testing.expectEqual(@as(u32, 0), parsed3.level);
    try std.testing.expectEqualStrings("absolute", parsed3.name);
}

test "relative_from_list" {
    var from_list = RelativeFromList.init(std.testing.allocator);
    defer from_list.deinit();

    try from_list.add("foo");
    try from_list.add("bar");
    try from_list.add("baz");

    try std.testing.expectEqual(@as(usize, 3), from_list.count());
    try std.testing.expect(from_list.hasName("foo"));
    try std.testing.expect(from_list.hasName("bar"));
    try std.testing.expect(!from_list.hasName("qux"));
    try std.testing.expect(!from_list.isStarImport());
}

test "relative_from_list_star" {
    var from_list = RelativeFromList.init(std.testing.allocator);
    defer from_list.deinit();

    try from_list.add("*");
    try std.testing.expect(from_list.isStarImport());
}

test "import_statement_basic" {
    var stmt = ImportStatement.init(std.testing.allocator);
    defer stmt.deinit();

    stmt.module = "foo.bar";
    stmt.level = 0;

    try std.testing.expect(stmt.isAbsolute());
    try std.testing.expect(!stmt.isRelative());
}

test "import_statement_relative" {
    var stmt = ImportStatement.init(std.testing.allocator);
    defer stmt.deinit();

    stmt.module = "submodule";
    stmt.level = 2;

    try std.testing.expect(!stmt.isAbsolute());
    try std.testing.expect(stmt.isRelative());
    try std.testing.expectEqual(ImportLevel.parent, stmt.getLevel());
}

test "module_hierarchy_ancestors" {
    const ancestors = try ModuleHierarchy.getAncestors(std.testing.allocator, "a.b.c.d");
    defer std.testing.allocator.free(ancestors);

    try std.testing.expectEqual(@as(usize, 3), ancestors.len);
    try std.testing.expectEqualStrings("a.b.c", ancestors[0]);
    try std.testing.expectEqualStrings("a.b", ancestors[1]);
    try std.testing.expectEqualStrings("a", ancestors[2]);
}

test "module_hierarchy_depth" {
    try std.testing.expectEqual(@as(u32, 1), ModuleHierarchy.getDepth("foo"));
    try std.testing.expectEqual(@as(u32, 2), ModuleHierarchy.getDepth("foo.bar"));
    try std.testing.expectEqual(@as(u32, 3), ModuleHierarchy.getDepth("foo.bar.baz"));
}

test "module_hierarchy_is_ancestor" {
    try std.testing.expect(ModuleHierarchy.isAncestorOf("foo", "foo.bar"));
    try std.testing.expect(ModuleHierarchy.isAncestorOf("foo.bar", "foo.bar.baz"));
    try std.testing.expect(!ModuleHierarchy.isAncestorOf("foo.bar", "foo.bar")); // Same, not ancestor
    try std.testing.expect(!ModuleHierarchy.isAncestorOf("foo", "foobar")); // Not a proper prefix
}

test "module_hierarchy_common_ancestor" {
    const common1 = ModuleHierarchy.getCommonAncestor("foo.bar.baz", "foo.bar.qux");
    try std.testing.expect(common1 != null);
    try std.testing.expectEqualStrings("foo.bar", common1.?);

    const common2 = ModuleHierarchy.getCommonAncestor("foo.bar", "foo.baz");
    try std.testing.expect(common2 != null);
    try std.testing.expectEqualStrings("foo", common2.?);

    const common3 = ModuleHierarchy.getCommonAncestor("foo", "bar");
    try std.testing.expect(common3 == null);
}

test "relative_import_validator" {
    try std.testing.expect(RelativeImportValidator.canImportRelatively("pkg.module", null));
    try std.testing.expect(RelativeImportValidator.canImportRelatively("toplevel", "pkg"));
    try std.testing.expect(!RelativeImportValidator.canImportRelatively("toplevel", null));

    const pkg = RelativeImportValidator.getEffectivePackage("pkg.module", null);
    try std.testing.expect(pkg != null);
    try std.testing.expectEqualStrings("pkg", pkg.?);
}

test "relative_import_validator_level" {
    try RelativeImportValidator.validateLevel(1, "pkg.sub.deep");
    try RelativeImportValidator.validateLevel(2, "pkg.sub.deep");
    try RelativeImportValidator.validateLevel(3, "pkg.sub.deep");

    const result = RelativeImportValidator.validateLevel(4, "pkg.sub.deep");
    try std.testing.expectError(error.AttemptedRelativeImportBeyondTopLevel, result);
}
