//! test.test_module.test_finder - Module finder testing
//! Tests for Python's importlib finder classes
//! Reference: CPython Lib/test/test_importlib/test_finder.py

const std = @import("std");
const importlib = @import("../../importlib.zig");
const machinery = @import("../../importlib/machinery.zig");
const abc = @import("../../importlib/abc.zig");

// ============================================================================
// Finder Types from importlib
// ============================================================================

pub const ModuleSpec = importlib.ModuleSpec;
pub const PathFinder = importlib.PathFinder;
pub const Finder = importlib.Finder;

// ============================================================================
// Finder Protocol Types
// ============================================================================

/// Abstract meta path finder protocol
pub const MetaPathFinderProtocol = struct {
    /// Find spec for module
    pub fn findSpec(fullname: []const u8, path: ?[]const []const u8, target: ?*anyopaque) ?ModuleSpec {
        _ = fullname;
        _ = path;
        _ = target;
        return null;
    }

    /// Deprecated: Find module
    pub fn findModule(fullname: []const u8, path: ?[]const u8) ?*anyopaque {
        _ = fullname;
        _ = path;
        return null;
    }

    /// Invalidate caches
    pub fn invalidateCaches() void {}
};

/// Abstract path entry finder protocol
pub const PathEntryFinderProtocol = struct {
    /// Find spec for module in this path entry
    pub fn findSpec(fullname: []const u8, target: ?*anyopaque) ?ModuleSpec {
        _ = fullname;
        _ = target;
        return null;
    }

    /// Deprecated: Find loader for module
    pub fn findLoader(fullname: []const u8) ?*anyopaque {
        _ = fullname;
        return null;
    }

    /// Invalidate caches
    pub fn invalidateCaches() void {}
};

// ============================================================================
// Mock Finders for Testing
// ============================================================================

/// Mock meta path finder for testing
pub const MockMetaPathFinder = struct {
    name: []const u8,
    modules: std.StringHashMap(ModuleSpec),
    allocator: std.mem.Allocator,
    call_count: usize = 0,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return .{
            .name = name,
            .modules = std.StringHashMap(ModuleSpec).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.modules.deinit();
    }

    pub fn addModule(self: *Self, mod_name: []const u8) !void {
        const spec = ModuleSpec.init(self.allocator, mod_name, null);
        try self.modules.put(mod_name, spec);
    }

    pub fn findSpec(self: *Self, fullname: []const u8, path: ?[]const []const u8, target: ?*anyopaque) ?ModuleSpec {
        _ = path;
        _ = target;
        self.call_count += 1;
        return self.modules.get(fullname);
    }

    pub fn invalidateCaches(self: *Self) void {
        self.modules.clearRetainingCapacity();
        self.call_count = 0;
    }
};

/// Mock path entry finder for testing
pub const MockPathEntryFinder = struct {
    path: []const u8,
    modules: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, path: []const u8) Self {
        return .{
            .path = path,
            .modules = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.modules.deinit();
    }

    pub fn addModule(self: *Self, mod_name: []const u8, file_path: []const u8) !void {
        try self.modules.put(mod_name, file_path);
    }

    pub fn findSpec(self: *Self, fullname: []const u8, target: ?*anyopaque) ?ModuleSpec {
        _ = target;
        if (self.modules.get(fullname)) |_| {
            return ModuleSpec.init(self.allocator, fullname, null);
        }
        return null;
    }
};

/// Null finder that always returns null
pub const NullFinder = struct {
    pub fn findSpec(fullname: []const u8, path: ?[]const u8, target: ?*anyopaque) ?ModuleSpec {
        _ = fullname;
        _ = path;
        _ = target;
        return null;
    }
};

// ============================================================================
// BuiltinImporter Tests
// ============================================================================

/// Test BuiltinImporter finds builtin modules
pub fn testBuiltinImporterFindsBuiltin() !void {
    const spec = machinery.BuiltinImporter.findSpec("sys", null, null);
    try std.testing.expect(spec != null);
    try std.testing.expectEqualStrings("sys", spec.?.name);
}

/// Test BuiltinImporter returns null for non-builtin
pub fn testBuiltinImporterNotFound() !void {
    const spec = machinery.BuiltinImporter.findSpec("nonexistent_builtin", null, null);
    try std.testing.expect(spec == null);
}

/// Test BuiltinImporter isPackage returns false
pub fn testBuiltinImporterIsPackage() !void {
    const is_pkg = machinery.BuiltinImporter.isPackage("sys");
    try std.testing.expect(!is_pkg);
}

// ============================================================================
// FrozenImporter Tests
// ============================================================================

/// Test FrozenImporter returns null (no frozen modules in AOT)
pub fn testFrozenImporterReturnsNull() !void {
    const spec = machinery.FrozenImporter.findSpec("_frozen_importlib", null, null);
    try std.testing.expect(spec == null);
}

// ============================================================================
// PathFinder Tests
// ============================================================================

/// Test PathFinder returns null for nonexistent module
pub fn testPathFinderNotFound(allocator: std.mem.Allocator) !void {
    const spec = PathFinder.find_spec(allocator, "definitely_not_a_module_12345", null, null);
    try std.testing.expect(spec == null);
}

/// Test PathFinder with empty path
pub fn testPathFinderEmptyPath(allocator: std.mem.Allocator) !void {
    const empty_path: []const []const u8 = &.{};
    const spec = PathFinder.find_spec(allocator, "module", empty_path, null);
    try std.testing.expect(spec == null);
}

// ============================================================================
// FileFinder Tests
// ============================================================================

/// Test FileFinder initialization
pub fn testFileFinderInit(allocator: std.mem.Allocator) !void {
    var finder = machinery.FileFinder.init(allocator, "/usr/lib/python3");
    defer finder.deinit();
    try std.testing.expectEqualStrings("/usr/lib/python3", finder.path);
}

/// Test FileFinder invalidateCaches
pub fn testFileFinderInvalidateCaches(allocator: std.mem.Allocator) !void {
    var finder = machinery.FileFinder.init(allocator, "/path");
    defer finder.deinit();
    finder.invalidateCaches();
    // Should not crash
}

// ============================================================================
// WindowsRegistryFinder Tests
// ============================================================================

/// Test WindowsRegistryFinder returns null on non-Windows
pub fn testWindowsRegistryFinderNonWindows() !void {
    const spec = machinery.WindowsRegistryFinder.findSpec("win_module", null, null);
    // On non-Windows, should always return null
    if (@import("builtin").os.tag != .windows) {
        try std.testing.expect(spec == null);
    }
}

// ============================================================================
// Finder Priority Tests
// ============================================================================

/// Finder chain for priority testing
pub const FinderChain = struct {
    finders: std.ArrayList(*const fn ([]const u8) ?ModuleSpec),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FinderChain {
        return .{
            .finders = std.ArrayList(*const fn ([]const u8) ?ModuleSpec){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FinderChain) void {
        self.finders.deinit(self.allocator);
    }

    pub fn findSpec(self: *FinderChain, name: []const u8) ?ModuleSpec {
        for (self.finders.items) |finder| {
            if (finder(name)) |spec| {
                return spec;
            }
        }
        return null;
    }
};

// ============================================================================
// Abstract Finder Tests
// ============================================================================

/// Test MetaPathFinder abstract interface
pub fn testMetaPathFinderAbstract() !void {
    const spec = abc.MetaPathFinder.findSpec("test", null, null);
    try std.testing.expect(spec == null);
}

/// Test PathEntryFinder abstract interface
pub fn testPathEntryFinderAbstract() !void {
    const spec = abc.PathEntryFinder.findSpec("test", null);
    try std.testing.expect(spec == null);
}

// ============================================================================
// Zig Tests
// ============================================================================

test "MetaPathFinderProtocol" {
    const spec = MetaPathFinderProtocol.findSpec("test", null, null);
    try std.testing.expect(spec == null);
}

test "PathEntryFinderProtocol" {
    const spec = PathEntryFinderProtocol.findSpec("test", null);
    try std.testing.expect(spec == null);
}

test "MockMetaPathFinder init" {
    const allocator = std.testing.allocator;
    var finder = MockMetaPathFinder.init(allocator, "test_finder");
    defer finder.deinit();
    try std.testing.expectEqualStrings("test_finder", finder.name);
}

test "MockMetaPathFinder addModule and findSpec" {
    const allocator = std.testing.allocator;
    var finder = MockMetaPathFinder.init(allocator, "test");
    defer finder.deinit();

    try finder.addModule("mymodule");
    const spec = finder.findSpec("mymodule", null, null);
    try std.testing.expect(spec != null);
    try std.testing.expectEqualStrings("mymodule", spec.?.name);
}

test "MockMetaPathFinder not found" {
    const allocator = std.testing.allocator;
    var finder = MockMetaPathFinder.init(allocator, "test");
    defer finder.deinit();

    const spec = finder.findSpec("nonexistent", null, null);
    try std.testing.expect(spec == null);
}

test "MockMetaPathFinder call_count" {
    const allocator = std.testing.allocator;
    var finder = MockMetaPathFinder.init(allocator, "test");
    defer finder.deinit();

    _ = finder.findSpec("a", null, null);
    _ = finder.findSpec("b", null, null);
    try std.testing.expectEqual(@as(usize, 2), finder.call_count);
}

test "MockMetaPathFinder invalidateCaches" {
    const allocator = std.testing.allocator;
    var finder = MockMetaPathFinder.init(allocator, "test");
    defer finder.deinit();

    try finder.addModule("mod");
    finder.invalidateCaches();
    const spec = finder.findSpec("mod", null, null);
    try std.testing.expect(spec == null);
}

test "MockPathEntryFinder init" {
    const allocator = std.testing.allocator;
    var finder = MockPathEntryFinder.init(allocator, "/test/path");
    defer finder.deinit();
    try std.testing.expectEqualStrings("/test/path", finder.path);
}

test "MockPathEntryFinder findSpec" {
    const allocator = std.testing.allocator;
    var finder = MockPathEntryFinder.init(allocator, "/lib");
    defer finder.deinit();

    try finder.addModule("testmod", "/lib/testmod.py");
    const spec = finder.findSpec("testmod", null);
    try std.testing.expect(spec != null);
}

test "NullFinder always null" {
    const spec = NullFinder.findSpec("anything", null, null);
    try std.testing.expect(spec == null);
}

test "BuiltinImporter finds sys" {
    const spec = machinery.BuiltinImporter.findSpec("sys", null, null);
    try std.testing.expect(spec != null);
}

test "BuiltinImporter finds builtins" {
    const spec = machinery.BuiltinImporter.findSpec("builtins", null, null);
    try std.testing.expect(spec != null);
}

test "BuiltinImporter not found" {
    const spec = machinery.BuiltinImporter.findSpec("xyz_not_builtin", null, null);
    try std.testing.expect(spec == null);
}

test "FrozenImporter returns null" {
    const spec = machinery.FrozenImporter.findSpec("test", null, null);
    try std.testing.expect(spec == null);
}

test "FileFinder init" {
    const allocator = std.testing.allocator;
    var finder = machinery.FileFinder.init(allocator, "/test");
    defer finder.deinit();
    try std.testing.expectEqualStrings("/test", finder.path);
}

test "FileFinder findSpec returns null for path-only" {
    const allocator = std.testing.allocator;
    var finder = machinery.FileFinder.init(allocator, "/nonexistent");
    defer finder.deinit();
    const spec = finder.findSpec("test", null);
    try std.testing.expect(spec == null);
}

test "FinderChain init" {
    const allocator = std.testing.allocator;
    var chain = FinderChain.init(allocator);
    defer chain.deinit();
    try std.testing.expectEqual(@as(usize, 0), chain.finders.items.len);
}

test "abc.MetaPathFinder" {
    const spec = abc.MetaPathFinder.findSpec("test", null, null);
    try std.testing.expect(spec == null);
}

test "abc.PathEntryFinder" {
    const spec = abc.PathEntryFinder.findSpec("test", null);
    try std.testing.expect(spec == null);
}
