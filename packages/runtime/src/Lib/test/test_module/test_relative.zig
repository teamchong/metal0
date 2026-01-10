//! test.test_module.test_relative - Relative import testing
//! Tests for Python's relative import syntax (from . import, from .. import)
//! Reference: CPython Lib/test/test_importlib/test_relative_imports.py

const std = @import("std");
const importlib = @import("../../importlib.zig");

// ============================================================================
// Types
// ============================================================================

pub const ModuleSpec = importlib.ModuleSpec;
pub const ImportError = importlib.ImportError;

// ============================================================================
// Relative Import Resolution
// ============================================================================

/// Result of relative import resolution
pub const ResolveResult = struct {
    name: []const u8,
    level: usize,
    absolute_name: ?[]const u8 = null,

    pub fn isAbsolute(self: *const ResolveResult) bool {
        return self.level == 0;
    }

    pub fn isRelative(self: *const ResolveResult) bool {
        return self.level > 0;
    }
};

/// Resolve a relative import name to an absolute name
/// name: The module name (may be empty for 'from . import x')
/// package: The current package context
/// level: Number of leading dots (1 = current package, 2 = parent, etc.)
pub fn resolveRelativeImport(
    allocator: std.mem.Allocator,
    name: []const u8,
    package: ?[]const u8,
    level: usize,
) ![]u8 {
    if (level == 0) {
        // Absolute import
        return allocator.dupe(u8, name);
    }

    const pkg = package orelse return error.InvalidName;
    if (pkg.len == 0) return error.InvalidName;

    // Split package into parts
    var parts = std.ArrayList([]const u8){};
    defer parts.deinit(allocator);

    var iter = std.mem.splitScalar(u8, pkg, '.');
    while (iter.next()) |part| {
        try parts.append(allocator, part);
    }

    // Navigate up the package hierarchy
    if (level > parts.items.len) {
        return error.InvalidName; // Attempted relative import beyond top-level package
    }

    // Remove trailing parts based on level
    const keep_count = parts.items.len - (level - 1);
    while (parts.items.len > keep_count) {
        _ = parts.pop();
    }

    // Build the result
    var result = std.ArrayList(u8){};
    errdefer result.deinit(allocator);

    for (parts.items, 0..) |part, i| {
        if (i > 0) try result.append(allocator, '.');
        try result.appendSlice(allocator, part);
    }

    // Append the relative module name if not empty
    if (name.len > 0) {
        if (result.items.len > 0) {
            try result.append(allocator, '.');
        }
        try result.appendSlice(allocator, name);
    }

    return result.toOwnedSlice(allocator);
}

/// Count leading dots in an import statement
pub fn countLeadingDots(import_str: []const u8) usize {
    var count: usize = 0;
    for (import_str) |c| {
        if (c == '.') {
            count += 1;
        } else {
            break;
        }
    }
    return count;
}

/// Extract module name after dots
pub fn extractModuleName(import_str: []const u8) []const u8 {
    const dots = countLeadingDots(import_str);
    return import_str[dots..];
}

/// Parse a relative import specification
pub fn parseRelativeImport(import_str: []const u8) ResolveResult {
    const level = countLeadingDots(import_str);
    const name = import_str[level..];
    return .{
        .name = name,
        .level = level,
    };
}

// ============================================================================
// Import Context for Testing
// ============================================================================

/// Represents the import context (__name__, __package__)
pub const ImportContext = struct {
    __name__: []const u8,
    __package__: ?[]const u8 = null,

    const Self = @This();

    pub fn init(name: []const u8, package: ?[]const u8) Self {
        return .{
            .__name__ = name,
            .__package__ = package,
        };
    }

    /// Create context for a top-level module
    pub fn forModule(name: []const u8) Self {
        return .{
            .__name__ = name,
            .__package__ = null,
        };
    }

    /// Create context for a module in a package
    pub fn forPackageModule(name: []const u8, package: []const u8) Self {
        return .{
            .__name__ = name,
            .__package__ = package,
        };
    }

    /// Create context for a package's __init__.py
    pub fn forPackageInit(package: []const u8) Self {
        return .{
            .__name__ = package,
            .__package__ = package,
        };
    }

    /// Get the package for relative imports
    pub fn getImportPackage(self: *const Self) ?[]const u8 {
        // If __package__ is set, use it
        if (self.__package__) |pkg| {
            return pkg;
        }
        // Otherwise, derive from __name__ (remove last component)
        if (std.mem.lastIndexOfScalar(u8, self.__name__, '.')) |idx| {
            return self.__name__[0..idx];
        }
        // Top-level module has no package
        return null;
    }

    /// Check if relative imports are allowed
    pub fn allowsRelativeImport(self: *const Self) bool {
        return self.getImportPackage() != null;
    }
};

// ============================================================================
// Test Functions
// ============================================================================

/// Test resolving single dot import
pub fn testResolveSingleDot(allocator: std.mem.Allocator) !void {
    const result = try resolveRelativeImport(allocator, "sibling", "pkg", 1);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("pkg.sibling", result);
}

/// Test resolving double dot import
pub fn testResolveDoubleDot(allocator: std.mem.Allocator) !void {
    const result = try resolveRelativeImport(allocator, "uncle", "pkg.sub", 2);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("pkg.uncle", result);
}

/// Test resolving triple dot import
pub fn testResolveTripleDot(allocator: std.mem.Allocator) !void {
    const result = try resolveRelativeImport(allocator, "mod", "pkg.a.b", 3);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("pkg.mod", result);
}

/// Test empty name (from . import x)
pub fn testResolveEmptyName(allocator: std.mem.Allocator) !void {
    const result = try resolveRelativeImport(allocator, "", "pkg.sub", 1);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("pkg.sub", result);
}

/// Test absolute import (level 0)
pub fn testResolveAbsolute(allocator: std.mem.Allocator) !void {
    const result = try resolveRelativeImport(allocator, "os.path", null, 0);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("os.path", result);
}

/// Test beyond top-level error
pub fn testResolveBeyondTopLevel(allocator: std.mem.Allocator) !void {
    const result = resolveRelativeImport(allocator, "mod", "pkg", 3);
    try std.testing.expectError(error.InvalidName, result);
}

/// Test countLeadingDots
pub fn testCountLeadingDots() !void {
    try std.testing.expectEqual(@as(usize, 0), countLeadingDots("module"));
    try std.testing.expectEqual(@as(usize, 1), countLeadingDots(".sibling"));
    try std.testing.expectEqual(@as(usize, 2), countLeadingDots("..parent"));
    try std.testing.expectEqual(@as(usize, 3), countLeadingDots("...grandparent"));
    try std.testing.expectEqual(@as(usize, 3), countLeadingDots("..."));
}

/// Test extractModuleName
pub fn testExtractModuleName() !void {
    try std.testing.expectEqualStrings("module", extractModuleName("module"));
    try std.testing.expectEqualStrings("sibling", extractModuleName(".sibling"));
    try std.testing.expectEqualStrings("parent", extractModuleName("..parent"));
    try std.testing.expectEqualStrings("", extractModuleName("..."));
}

/// Test parseRelativeImport
pub fn testParseRelativeImport() !void {
    const r1 = parseRelativeImport("module");
    try std.testing.expectEqual(@as(usize, 0), r1.level);
    try std.testing.expectEqualStrings("module", r1.name);

    const r2 = parseRelativeImport(".sibling");
    try std.testing.expectEqual(@as(usize, 1), r2.level);
    try std.testing.expectEqualStrings("sibling", r2.name);

    const r3 = parseRelativeImport("..parent");
    try std.testing.expectEqual(@as(usize, 2), r3.level);
    try std.testing.expectEqualStrings("parent", r3.name);
}

/// Test ImportContext
pub fn testImportContext() !void {
    // Top-level module
    const ctx1 = ImportContext.forModule("mymodule");
    try std.testing.expect(!ctx1.allowsRelativeImport());

    // Module in package
    const ctx2 = ImportContext.forPackageModule("pkg.mod", "pkg");
    try std.testing.expect(ctx2.allowsRelativeImport());

    // Package __init__
    const ctx3 = ImportContext.forPackageInit("mypkg");
    try std.testing.expect(ctx3.allowsRelativeImport());
}

// ============================================================================
// Zig Tests
// ============================================================================

test "countLeadingDots none" {
    try std.testing.expectEqual(@as(usize, 0), countLeadingDots("module"));
}

test "countLeadingDots one" {
    try std.testing.expectEqual(@as(usize, 1), countLeadingDots(".mod"));
}

test "countLeadingDots two" {
    try std.testing.expectEqual(@as(usize, 2), countLeadingDots("..mod"));
}

test "countLeadingDots three" {
    try std.testing.expectEqual(@as(usize, 3), countLeadingDots("...mod"));
}

test "countLeadingDots only dots" {
    try std.testing.expectEqual(@as(usize, 4), countLeadingDots("...."));
}

test "extractModuleName no dots" {
    try std.testing.expectEqualStrings("foo", extractModuleName("foo"));
}

test "extractModuleName one dot" {
    try std.testing.expectEqualStrings("bar", extractModuleName(".bar"));
}

test "extractModuleName empty after dots" {
    try std.testing.expectEqualStrings("", extractModuleName(".."));
}

test "parseRelativeImport absolute" {
    const r = parseRelativeImport("os.path");
    try std.testing.expect(r.isAbsolute());
    try std.testing.expect(!r.isRelative());
}

test "parseRelativeImport relative" {
    const r = parseRelativeImport(".sibling");
    try std.testing.expect(!r.isAbsolute());
    try std.testing.expect(r.isRelative());
}

test "resolveRelativeImport single dot" {
    const allocator = std.testing.allocator;
    const result = try resolveRelativeImport(allocator, "sub", "pkg", 1);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("pkg.sub", result);
}

test "resolveRelativeImport double dot" {
    const allocator = std.testing.allocator;
    const result = try resolveRelativeImport(allocator, "other", "pkg.sub", 2);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("pkg.other", result);
}

test "resolveRelativeImport from package init" {
    const allocator = std.testing.allocator;
    const result = try resolveRelativeImport(allocator, "submod", "pkg.sub", 1);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("pkg.sub.submod", result);
}

test "resolveRelativeImport empty name" {
    const allocator = std.testing.allocator;
    const result = try resolveRelativeImport(allocator, "", "pkg", 1);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("pkg", result);
}

test "resolveRelativeImport absolute" {
    const allocator = std.testing.allocator;
    const result = try resolveRelativeImport(allocator, "abs_mod", null, 0);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("abs_mod", result);
}

test "resolveRelativeImport beyond top level" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidName, resolveRelativeImport(allocator, "x", "pkg", 5));
}

test "resolveRelativeImport no package" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidName, resolveRelativeImport(allocator, "x", null, 1));
}

test "ImportContext forModule" {
    const ctx = ImportContext.forModule("standalone");
    try std.testing.expectEqualStrings("standalone", ctx.__name__);
    try std.testing.expect(ctx.__package__ == null);
}

test "ImportContext forPackageModule" {
    const ctx = ImportContext.forPackageModule("pkg.mod", "pkg");
    try std.testing.expectEqualStrings("pkg.mod", ctx.__name__);
    try std.testing.expectEqualStrings("pkg", ctx.__package__.?);
}

test "ImportContext forPackageInit" {
    const ctx = ImportContext.forPackageInit("mypkg");
    try std.testing.expectEqualStrings("mypkg", ctx.__name__);
    try std.testing.expectEqualStrings("mypkg", ctx.__package__.?);
}

test "ImportContext getImportPackage with package" {
    const ctx = ImportContext.forPackageModule("pkg.sub.mod", "pkg.sub");
    try std.testing.expectEqualStrings("pkg.sub", ctx.getImportPackage().?);
}

test "ImportContext getImportPackage derived" {
    var ctx = ImportContext.forModule("pkg.mod");
    ctx.__package__ = null;
    try std.testing.expectEqualStrings("pkg", ctx.getImportPackage().?);
}

test "ImportContext getImportPackage none" {
    const ctx = ImportContext.forModule("toplevel");
    try std.testing.expect(ctx.getImportPackage() == null);
}

test "ImportContext allowsRelativeImport true" {
    const ctx = ImportContext.forPackageModule("pkg.mod", "pkg");
    try std.testing.expect(ctx.allowsRelativeImport());
}

test "ImportContext allowsRelativeImport false" {
    const ctx = ImportContext.forModule("standalone");
    try std.testing.expect(!ctx.allowsRelativeImport());
}

test "ResolveResult isAbsolute" {
    const r = ResolveResult{ .name = "mod", .level = 0 };
    try std.testing.expect(r.isAbsolute());
}

test "ResolveResult isRelative" {
    const r = ResolveResult{ .name = "mod", .level = 2 };
    try std.testing.expect(r.isRelative());
}
