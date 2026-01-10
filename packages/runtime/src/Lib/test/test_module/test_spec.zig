//! test.test_module.test_spec - ModuleSpec testing
//! Tests for Python's importlib.machinery.ModuleSpec
//! Reference: CPython Lib/test/test_importlib/test_spec.py

const std = @import("std");
const importlib = @import("../../importlib.zig");

/// ModuleSpec from importlib
pub const ModuleSpec = importlib.ModuleSpec;

// ============================================================================
// Test Fixtures
// ============================================================================

/// Mock loader for testing
pub const MockLoader = struct {
    name: []const u8,
    is_package: bool = false,
    source_code: ?[]const u8 = null,

    pub fn init(name: []const u8) MockLoader {
        return .{ .name = name };
    }

    pub fn initPackage(name: []const u8) MockLoader {
        return .{ .name = name, .is_package = true };
    }

    pub fn createModule(self: *const MockLoader, spec: *const ModuleSpec) ?*anyopaque {
        _ = self;
        _ = spec;
        return null;
    }

    pub fn execModule(self: *const MockLoader, module: *anyopaque) !void {
        _ = self;
        _ = module;
    }

    pub fn getSource(self: *const MockLoader) ?[]const u8 {
        return self.source_code;
    }
};

/// Test helper for creating specs
pub const SpecHelper = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SpecHelper {
        return .{ .allocator = allocator };
    }

    pub fn createSpec(self: *SpecHelper, name: []const u8) ModuleSpec {
        return ModuleSpec.init(self.allocator, name, null);
    }

    pub fn createPackageSpec(self: *SpecHelper, name: []const u8) ModuleSpec {
        var spec = ModuleSpec.init(self.allocator, name, null);
        spec.submodule_search_locations = std.ArrayList([]const u8){};
        return spec;
    }

    pub fn createSpecWithOrigin(self: *SpecHelper, name: []const u8, origin: []const u8) ModuleSpec {
        var spec = ModuleSpec.init(self.allocator, name, null);
        spec.origin = origin;
        spec.has_location = true;
        return spec;
    }
};

// ============================================================================
// ModuleSpec Attribute Tests
// ============================================================================

/// Test that ModuleSpec stores name correctly
pub fn testSpecName(allocator: std.mem.Allocator) !void {
    var spec = ModuleSpec.init(allocator, "mymodule", null);
    defer spec.deinit();
    try std.testing.expectEqualStrings("mymodule", spec.name);
}

/// Test that ModuleSpec stores dotted names
pub fn testSpecDottedName(allocator: std.mem.Allocator) !void {
    var spec = ModuleSpec.init(allocator, "pkg.subpkg.module", null);
    defer spec.deinit();
    try std.testing.expectEqualStrings("pkg.subpkg.module", spec.name);
}

/// Test default loader is null
pub fn testSpecDefaultLoader(allocator: std.mem.Allocator) !void {
    var spec = ModuleSpec.init(allocator, "test", null);
    defer spec.deinit();
    try std.testing.expect(spec.loader == null);
}

/// Test origin attribute
pub fn testSpecOrigin(allocator: std.mem.Allocator) !void {
    var spec = ModuleSpec.init(allocator, "test", null);
    defer spec.deinit();
    spec.origin = "/path/to/module.py";
    try std.testing.expectEqualStrings("/path/to/module.py", spec.origin.?);
}

/// Test has_location attribute
pub fn testSpecHasLocation(allocator: std.mem.Allocator) !void {
    var spec = ModuleSpec.init(allocator, "test", null);
    defer spec.deinit();
    try std.testing.expect(!spec.has_location);
    spec.has_location = true;
    try std.testing.expect(spec.has_location);
}

/// Test cached attribute
pub fn testSpecCached(allocator: std.mem.Allocator) !void {
    var spec = ModuleSpec.init(allocator, "test", null);
    defer spec.deinit();
    try std.testing.expect(spec.cached == null);
    spec.cached = "/path/to/__pycache__/module.cpython-312.pyc";
    try std.testing.expectEqualStrings("/path/to/__pycache__/module.cpython-312.pyc", spec.cached.?);
}

/// Test parent attribute
pub fn testSpecParent(allocator: std.mem.Allocator) !void {
    var spec = ModuleSpec.init(allocator, "pkg.module", null);
    defer spec.deinit();
    spec.parent = "pkg";
    try std.testing.expectEqualStrings("pkg", spec.parent.?);
}

// ============================================================================
// Package Detection Tests
// ============================================================================

/// Test isPackage returns false for non-packages
pub fn testIsPackageFalse(allocator: std.mem.Allocator) !void {
    var spec = ModuleSpec.init(allocator, "module", null);
    defer spec.deinit();
    try std.testing.expect(!spec.isPackage());
}

/// Test isPackage returns true when submodule_search_locations set
pub fn testIsPackageTrue(allocator: std.mem.Allocator) !void {
    var spec = ModuleSpec.init(allocator, "package", null);
    defer spec.deinit();
    spec.submodule_search_locations = std.ArrayList([]const u8){};
    try std.testing.expect(spec.isPackage());
}

/// Test package with multiple search locations
pub fn testPackageSearchLocations(allocator: std.mem.Allocator) !void {
    var spec = ModuleSpec.init(allocator, "namespace_pkg", null);
    defer spec.deinit();
    spec.submodule_search_locations = std.ArrayList([]const u8){};
    try spec.submodule_search_locations.?.append(allocator, "/path1/namespace_pkg");
    try spec.submodule_search_locations.?.append(allocator, "/path2/namespace_pkg");
    try std.testing.expectEqual(@as(usize, 2), spec.submodule_search_locations.?.items.len);
}

// ============================================================================
// Spec Comparison and Equality Tests
// ============================================================================

/// Test specs with same name are logically equal
pub fn testSpecEquality(allocator: std.mem.Allocator) !void {
    var spec1 = ModuleSpec.init(allocator, "test", null);
    defer spec1.deinit();
    var spec2 = ModuleSpec.init(allocator, "test", null);
    defer spec2.deinit();
    try std.testing.expectEqualStrings(spec1.name, spec2.name);
}

/// Test specs with different names are not equal
pub fn testSpecInequality(allocator: std.mem.Allocator) !void {
    var spec1 = ModuleSpec.init(allocator, "test1", null);
    defer spec1.deinit();
    var spec2 = ModuleSpec.init(allocator, "test2", null);
    defer spec2.deinit();
    try std.testing.expect(!std.mem.eql(u8, spec1.name, spec2.name));
}

// ============================================================================
// Loader State Tests
// ============================================================================

/// Test loader_state is null by default
pub fn testLoaderStateDefault(allocator: std.mem.Allocator) !void {
    var spec = ModuleSpec.init(allocator, "test", null);
    defer spec.deinit();
    try std.testing.expect(spec.loader_state == null);
}

// ============================================================================
// Integration Tests
// ============================================================================

/// Test creating a complete spec for a file-based module
pub fn testFileBasedModuleSpec(allocator: std.mem.Allocator) !void {
    var spec = ModuleSpec.init(allocator, "mypackage.mymodule", null);
    defer spec.deinit();
    spec.origin = "/usr/lib/python3/site-packages/mypackage/mymodule.py";
    spec.has_location = true;
    spec.parent = "mypackage";
    spec.cached = "/usr/lib/python3/site-packages/mypackage/__pycache__/mymodule.cpython-312.pyc";

    try std.testing.expectEqualStrings("mypackage.mymodule", spec.name);
    try std.testing.expect(spec.origin != null);
    try std.testing.expect(spec.has_location);
    try std.testing.expectEqualStrings("mypackage", spec.parent.?);
}

/// Test creating a complete spec for a namespace package
pub fn testNamespacePackageSpec(allocator: std.mem.Allocator) !void {
    var spec = ModuleSpec.init(allocator, "namespace_pkg", null);
    defer spec.deinit();
    spec.submodule_search_locations = std.ArrayList([]const u8){};
    spec.origin = null;
    spec.has_location = false;

    try std.testing.expect(spec.isPackage());
    try std.testing.expect(spec.origin == null);
    try std.testing.expect(!spec.has_location);
}

/// Test creating spec for built-in module
pub fn testBuiltinModuleSpec(allocator: std.mem.Allocator) !void {
    var spec = ModuleSpec.init(allocator, "sys", null);
    defer spec.deinit();
    spec.origin = "built-in";

    try std.testing.expectEqualStrings("sys", spec.name);
    try std.testing.expectEqualStrings("built-in", spec.origin.?);
    try std.testing.expect(!spec.isPackage());
}

// ============================================================================
// Zig Tests
// ============================================================================

test "ModuleSpec init" {
    const allocator = std.testing.allocator;
    var spec = ModuleSpec.init(allocator, "test_module", null);
    defer spec.deinit();
    try std.testing.expectEqualStrings("test_module", spec.name);
    try std.testing.expect(!spec.isPackage());
}

test "ModuleSpec isPackage" {
    const allocator = std.testing.allocator;
    var spec = ModuleSpec.init(allocator, "test_pkg", null);
    defer spec.deinit();
    try std.testing.expect(!spec.isPackage());
    spec.submodule_search_locations = std.ArrayList([]const u8){};
    try std.testing.expect(spec.isPackage());
}

test "ModuleSpec origin" {
    const allocator = std.testing.allocator;
    var spec = ModuleSpec.init(allocator, "mymod", null);
    defer spec.deinit();
    spec.origin = "/path/to/mymod.py";
    try std.testing.expectEqualStrings("/path/to/mymod.py", spec.origin.?);
}

test "ModuleSpec parent" {
    const allocator = std.testing.allocator;
    var spec = ModuleSpec.init(allocator, "pkg.sub.mod", null);
    defer spec.deinit();
    spec.parent = "pkg.sub";
    try std.testing.expectEqualStrings("pkg.sub", spec.parent.?);
}

test "ModuleSpec search_locations" {
    const allocator = std.testing.allocator;
    var spec = ModuleSpec.init(allocator, "mypkg", null);
    defer spec.deinit();
    spec.submodule_search_locations = std.ArrayList([]const u8){};
    try spec.submodule_search_locations.?.append(allocator, "/path1");
    try spec.submodule_search_locations.?.append(allocator, "/path2");
    try std.testing.expectEqual(@as(usize, 2), spec.submodule_search_locations.?.items.len);
}

test "SpecHelper createSpec" {
    const allocator = std.testing.allocator;
    var helper = SpecHelper.init(allocator);
    var spec = helper.createSpec("helper_test");
    defer spec.deinit();
    try std.testing.expectEqualStrings("helper_test", spec.name);
}

test "SpecHelper createPackageSpec" {
    const allocator = std.testing.allocator;
    var helper = SpecHelper.init(allocator);
    var spec = helper.createPackageSpec("helper_pkg");
    defer spec.deinit();
    try std.testing.expect(spec.isPackage());
}

test "MockLoader init" {
    const loader = MockLoader.init("test_loader");
    try std.testing.expectEqualStrings("test_loader", loader.name);
    try std.testing.expect(!loader.is_package);
}

test "MockLoader initPackage" {
    const loader = MockLoader.initPackage("test_pkg_loader");
    try std.testing.expectEqualStrings("test_pkg_loader", loader.name);
    try std.testing.expect(loader.is_package);
}
