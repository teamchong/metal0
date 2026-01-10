//! test.test_module.test_pkg - Package handling testing
//! Tests for Python package structure and __init__.py handling
//! Reference: CPython Lib/test/test_importlib/test_pkg.py

const std = @import("std");
const importlib = @import("../../importlib.zig");

// ============================================================================
// Types
// ============================================================================

pub const ModuleSpec = importlib.ModuleSpec;

// ============================================================================
// Package Structure Representation
// ============================================================================

/// Represents a Python package structure for testing
pub const Package = struct {
    name: []const u8,
    path: []const u8,
    submodules: std.StringHashMap(SubModule),
    subpackages: std.StringHashMap(*Package),
    init_source: ?[]const u8 = null,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Submodule within a package
    pub const SubModule = struct {
        name: []const u8,
        source: []const u8 = "",
        is_package: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8, path: []const u8) Self {
        return .{
            .name = name,
            .path = path,
            .submodules = std.StringHashMap(SubModule).init(allocator),
            .subpackages = std.StringHashMap(*Package).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.submodules.deinit();
        var it = self.subpackages.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.subpackages.deinit();
    }

    /// Add a submodule to the package
    pub fn addSubmodule(self: *Self, name: []const u8, source: []const u8) !void {
        try self.submodules.put(name, .{ .name = name, .source = source });
    }

    /// Add a subpackage to the package
    pub fn addSubpackage(self: *Self, name: []const u8) !*Package {
        var subpath_buf: [512]u8 = undefined;
        const subpath = std.fmt.bufPrint(&subpath_buf, "{s}/{s}", .{ self.path, name }) catch return error.PathTooLong;

        const subpkg = try self.allocator.create(Package);
        subpkg.* = Package.init(self.allocator, name, subpath);
        try self.subpackages.put(name, subpkg);
        return subpkg;
    }

    /// Check if module exists in package
    pub fn hasModule(self: *const Self, name: []const u8) bool {
        return self.submodules.contains(name);
    }

    /// Check if subpackage exists
    pub fn hasSubpackage(self: *const Self, name: []const u8) bool {
        return self.subpackages.contains(name);
    }

    /// Get full module name
    pub fn getFullName(self: *const Self, submodule: []const u8) ![]u8 {
        var buf: [256]u8 = undefined;
        return std.fmt.bufPrint(&buf, "{s}.{s}", .{ self.name, submodule }) catch return error.NameTooLong;
    }

    /// Check if this is a namespace package
    pub fn isNamespacePackage(self: *const Self) bool {
        return self.init_source == null;
    }

    /// Get __init__.py path
    pub fn getInitPath(self: *const Self) ![]u8 {
        var buf: [512]u8 = undefined;
        return std.fmt.bufPrint(&buf, "{s}/__init__.py", .{self.path}) catch return error.PathTooLong;
    }
};

// ============================================================================
// Package Layout Types
// ============================================================================

/// Different package layout styles
pub const PackageLayout = enum {
    /// Regular package with __init__.py
    regular,
    /// Namespace package (no __init__.py)
    namespace,
    /// Package with only compiled __init__.pyc
    compiled,
    /// Package with __init__ as directory (legacy)
    legacy,
};

/// Package validation result
pub const ValidationResult = struct {
    valid: bool,
    has_init: bool,
    has_pycache: bool,
    module_count: usize,
    subpackage_count: usize,
    errors: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ValidationResult {
        return .{
            .valid = true,
            .has_init = false,
            .has_pycache = false,
            .module_count = 0,
            .subpackage_count = 0,
            .errors = std.ArrayList([]const u8){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ValidationResult) void {
        self.errors.deinit(self.allocator);
    }

    pub fn addError(self: *ValidationResult, err: []const u8) !void {
        self.valid = false;
        try self.errors.append(self.allocator, err);
    }
};

// ============================================================================
// Package Name Resolution
// ============================================================================

/// Parse a dotted package name
pub fn parsePackageName(name: []const u8) struct { parts: [16][]const u8, len: usize } {
    var parts: [16][]const u8 = undefined;
    var len: usize = 0;

    var iter = std.mem.splitScalar(u8, name, '.');
    while (iter.next()) |part| {
        if (len >= 16) break;
        parts[len] = part;
        len += 1;
    }

    return .{ .parts = parts, .len = len };
}

/// Get parent package name
pub fn getParentPackage(name: []const u8) ?[]const u8 {
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |idx| {
        return name[0..idx];
    }
    return null;
}

/// Get leaf module name
pub fn getLeafName(name: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |idx| {
        return name[idx + 1 ..];
    }
    return name;
}

/// Check if name is a top-level package
pub fn isTopLevel(name: []const u8) bool {
    return std.mem.indexOfScalar(u8, name, '.') == null;
}

// ============================================================================
// Test Functions
// ============================================================================

/// Test Package initialization
pub fn testPackageInit(allocator: std.mem.Allocator) !void {
    var pkg = Package.init(allocator, "mypkg", "/path/to/mypkg");
    defer pkg.deinit();
    try std.testing.expectEqualStrings("mypkg", pkg.name);
    try std.testing.expectEqualStrings("/path/to/mypkg", pkg.path);
}

/// Test adding submodules
pub fn testPackageAddSubmodule(allocator: std.mem.Allocator) !void {
    var pkg = Package.init(allocator, "pkg", "/pkg");
    defer pkg.deinit();
    try pkg.addSubmodule("utils", "def util(): pass");
    try std.testing.expect(pkg.hasModule("utils"));
}

/// Test adding subpackages
pub fn testPackageAddSubpackage(allocator: std.mem.Allocator) !void {
    var pkg = Package.init(allocator, "pkg", "/pkg");
    defer pkg.deinit();
    const subpkg = try pkg.addSubpackage("sub");
    try std.testing.expectEqualStrings("sub", subpkg.name);
    try std.testing.expect(pkg.hasSubpackage("sub"));
}

/// Test namespace package detection
pub fn testNamespacePackage(allocator: std.mem.Allocator) !void {
    var pkg = Package.init(allocator, "ns_pkg", "/ns_pkg");
    defer pkg.deinit();
    // No init_source = namespace package
    try std.testing.expect(pkg.isNamespacePackage());

    pkg.init_source = "# __init__.py";
    try std.testing.expect(!pkg.isNamespacePackage());
}

/// Test parse package name
pub fn testParsePackageName() !void {
    const result = parsePackageName("pkg.sub.mod");
    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqualStrings("pkg", result.parts[0]);
    try std.testing.expectEqualStrings("sub", result.parts[1]);
    try std.testing.expectEqualStrings("mod", result.parts[2]);
}

/// Test get parent package
pub fn testGetParentPackage() !void {
    try std.testing.expectEqualStrings("pkg.sub", getParentPackage("pkg.sub.mod").?);
    try std.testing.expectEqualStrings("pkg", getParentPackage("pkg.sub").?);
    try std.testing.expect(getParentPackage("pkg") == null);
}

/// Test get leaf name
pub fn testGetLeafName() !void {
    try std.testing.expectEqualStrings("mod", getLeafName("pkg.sub.mod"));
    try std.testing.expectEqualStrings("sub", getLeafName("pkg.sub"));
    try std.testing.expectEqualStrings("pkg", getLeafName("pkg"));
}

/// Test is top level
pub fn testIsTopLevel() !void {
    try std.testing.expect(isTopLevel("pkg"));
    try std.testing.expect(!isTopLevel("pkg.sub"));
    try std.testing.expect(!isTopLevel("pkg.sub.mod"));
}

/// Test ValidationResult
pub fn testValidationResult(allocator: std.mem.Allocator) !void {
    var result = ValidationResult.init(allocator);
    defer result.deinit();
    try std.testing.expect(result.valid);
    try result.addError("test error");
    try std.testing.expect(!result.valid);
}

// ============================================================================
// Zig Tests
// ============================================================================

test "Package init" {
    const allocator = std.testing.allocator;
    var pkg = Package.init(allocator, "test_pkg", "/test");
    defer pkg.deinit();
    try std.testing.expectEqualStrings("test_pkg", pkg.name);
}

test "Package addSubmodule" {
    const allocator = std.testing.allocator;
    var pkg = Package.init(allocator, "pkg", "/pkg");
    defer pkg.deinit();
    try pkg.addSubmodule("mod1", "x = 1");
    try std.testing.expect(pkg.hasModule("mod1"));
}

test "Package hasModule false" {
    const allocator = std.testing.allocator;
    var pkg = Package.init(allocator, "pkg", "/pkg");
    defer pkg.deinit();
    try std.testing.expect(!pkg.hasModule("nonexistent"));
}

test "Package addSubpackage" {
    const allocator = std.testing.allocator;
    var pkg = Package.init(allocator, "pkg", "/pkg");
    defer pkg.deinit();
    _ = try pkg.addSubpackage("subpkg");
    try std.testing.expect(pkg.hasSubpackage("subpkg"));
}

test "Package hasSubpackage false" {
    const allocator = std.testing.allocator;
    var pkg = Package.init(allocator, "pkg", "/pkg");
    defer pkg.deinit();
    try std.testing.expect(!pkg.hasSubpackage("none"));
}

test "Package isNamespacePackage true" {
    const allocator = std.testing.allocator;
    var pkg = Package.init(allocator, "ns", "/ns");
    defer pkg.deinit();
    try std.testing.expect(pkg.isNamespacePackage());
}

test "Package isNamespacePackage false" {
    const allocator = std.testing.allocator;
    var pkg = Package.init(allocator, "regular", "/regular");
    defer pkg.deinit();
    pkg.init_source = "";
    try std.testing.expect(!pkg.isNamespacePackage());
}

test "parsePackageName simple" {
    const result = parsePackageName("pkg");
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("pkg", result.parts[0]);
}

test "parsePackageName dotted" {
    const result = parsePackageName("a.b.c.d");
    try std.testing.expectEqual(@as(usize, 4), result.len);
}

test "getParentPackage with parent" {
    const parent = getParentPackage("pkg.mod");
    try std.testing.expect(parent != null);
    try std.testing.expectEqualStrings("pkg", parent.?);
}

test "getParentPackage no parent" {
    const parent = getParentPackage("toplevel");
    try std.testing.expect(parent == null);
}

test "getLeafName simple" {
    try std.testing.expectEqualStrings("x", getLeafName("x"));
}

test "getLeafName dotted" {
    try std.testing.expectEqualStrings("leaf", getLeafName("a.b.leaf"));
}

test "isTopLevel true" {
    try std.testing.expect(isTopLevel("module"));
}

test "isTopLevel false" {
    try std.testing.expect(!isTopLevel("pkg.module"));
}

test "ValidationResult init" {
    const allocator = std.testing.allocator;
    var result = ValidationResult.init(allocator);
    defer result.deinit();
    try std.testing.expect(result.valid);
}

test "ValidationResult addError" {
    const allocator = std.testing.allocator;
    var result = ValidationResult.init(allocator);
    defer result.deinit();
    try result.addError("error1");
    try std.testing.expect(!result.valid);
    try std.testing.expectEqual(@as(usize, 1), result.errors.items.len);
}

test "PackageLayout enum" {
    const layout: PackageLayout = .regular;
    try std.testing.expect(layout == .regular);
}

test "SubModule struct" {
    const sub = Package.SubModule{ .name = "test", .source = "pass" };
    try std.testing.expectEqualStrings("test", sub.name);
    try std.testing.expect(!sub.is_package);
}

test "nested packages" {
    const allocator = std.testing.allocator;
    var root = Package.init(allocator, "root", "/root");
    defer root.deinit();

    const level1 = try root.addSubpackage("level1");
    const level2 = try level1.addSubpackage("level2");
    try level2.addSubmodule("deep", "x = 'deep'");

    try std.testing.expect(root.hasSubpackage("level1"));
    try std.testing.expect(level1.hasSubpackage("level2"));
    try std.testing.expect(level2.hasModule("deep"));
}
