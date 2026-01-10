//! test.test_module.test_meta - Module meta path testing
//! Tests for Python's sys.meta_path and meta path finders
//! Reference: CPython Lib/test/test_importlib/test_api.py

const std = @import("std");
const importlib = @import("../../importlib.zig");
const machinery = @import("../../importlib/machinery.zig");
const abc = @import("../../importlib/abc.zig");

// ============================================================================
// Types
// ============================================================================

pub const ModuleSpec = importlib.ModuleSpec;

// ============================================================================
// Meta Path Simulation
// ============================================================================

/// Simulates Python's sys.meta_path list
pub const MetaPath = struct {
    finders: std.ArrayList(FinderEntry),
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Entry in meta_path
    pub const FinderEntry = struct {
        name: []const u8,
        finder_type: FinderType,
    };

    pub const FinderType = enum {
        builtin,
        frozen,
        path,
        custom,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .finders = std.ArrayList(FinderEntry){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.finders.deinit(self.allocator);
    }

    /// Add a finder to meta_path
    pub fn append(self: *Self, entry: FinderEntry) !void {
        try self.finders.append(self.allocator, entry);
    }

    /// Insert a finder at the beginning
    pub fn insert(self: *Self, index: usize, entry: FinderEntry) !void {
        try self.finders.insert(self.allocator, index, entry);
    }

    /// Remove a finder by name
    pub fn remove(self: *Self, name: []const u8) bool {
        for (self.finders.items, 0..) |entry, i| {
            if (std.mem.eql(u8, entry.name, name)) {
                _ = self.finders.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    /// Get number of finders
    pub fn len(self: *const Self) usize {
        return self.finders.items.len;
    }

    /// Find spec by searching all finders in order
    pub fn findSpec(self: *Self, fullname: []const u8) ?ModuleSpec {
        for (self.finders.items) |entry| {
            switch (entry.finder_type) {
                .builtin => {
                    if (machinery.BuiltinImporter.findSpec(fullname, null, null)) |spec| {
                        return spec;
                    }
                },
                .frozen => {
                    if (machinery.FrozenImporter.findSpec(fullname, null, null)) |spec| {
                        return spec;
                    }
                },
                else => {},
            }
        }
        return null;
    }

    /// Initialize with default CPython finders
    pub fn initWithDefaults(allocator: std.mem.Allocator) !Self {
        var self = Self.init(allocator);
        try self.append(.{ .name = "BuiltinImporter", .finder_type = .builtin });
        try self.append(.{ .name = "FrozenImporter", .finder_type = .frozen });
        try self.append(.{ .name = "PathFinder", .finder_type = .path });
        return self;
    }
};

// ============================================================================
// Module Attributes Testing
// ============================================================================

/// Module attribute container for testing
pub const ModuleAttributes = struct {
    __name__: []const u8,
    __doc__: ?[]const u8 = null,
    __file__: ?[]const u8 = null,
    __package__: ?[]const u8 = null,
    __loader__: ?*anyopaque = null,
    __spec__: ?*ModuleSpec = null,
    __path__: ?[]const []const u8 = null,
    __cached__: ?[]const u8 = null,

    const Self = @This();

    pub fn init(name: []const u8) Self {
        return .{ .__name__ = name };
    }

    pub fn isPackage(self: *const Self) bool {
        return self.__path__ != null;
    }

    pub fn hasLocation(self: *const Self) bool {
        return self.__file__ != null;
    }
};

// ============================================================================
// Meta Path Hook Testing
// ============================================================================

/// Hook for intercepting import operations
pub const ImportHook = struct {
    imports: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    enabled: bool = true,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .imports = std.ArrayList([]const u8){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.imports.deinit(self.allocator);
    }

    pub fn record(self: *Self, name: []const u8) !void {
        if (self.enabled) {
            try self.imports.append(self.allocator, name);
        }
    }

    pub fn getImports(self: *const Self) []const []const u8 {
        return self.imports.items;
    }

    pub fn clear(self: *Self) void {
        self.imports.clearRetainingCapacity();
    }

    pub fn wasImported(self: *const Self, name: []const u8) bool {
        for (self.imports.items) |imp| {
            if (std.mem.eql(u8, imp, name)) {
                return true;
            }
        }
        return false;
    }
};

// ============================================================================
// Test Functions
// ============================================================================

/// Test MetaPath initialization
pub fn testMetaPathInit(allocator: std.mem.Allocator) !void {
    var meta_path = MetaPath.init(allocator);
    defer meta_path.deinit();
    try std.testing.expectEqual(@as(usize, 0), meta_path.len());
}

/// Test MetaPath with default finders
pub fn testMetaPathDefaults(allocator: std.mem.Allocator) !void {
    var meta_path = try MetaPath.initWithDefaults(allocator);
    defer meta_path.deinit();
    try std.testing.expectEqual(@as(usize, 3), meta_path.len());
}

/// Test MetaPath append
pub fn testMetaPathAppend(allocator: std.mem.Allocator) !void {
    var meta_path = MetaPath.init(allocator);
    defer meta_path.deinit();
    try meta_path.append(.{ .name = "CustomFinder", .finder_type = .custom });
    try std.testing.expectEqual(@as(usize, 1), meta_path.len());
}

/// Test MetaPath insert at beginning
pub fn testMetaPathInsert(allocator: std.mem.Allocator) !void {
    var meta_path = try MetaPath.initWithDefaults(allocator);
    defer meta_path.deinit();
    try meta_path.insert(0, .{ .name = "FirstFinder", .finder_type = .custom });
    try std.testing.expectEqualStrings("FirstFinder", meta_path.finders.items[0].name);
}

/// Test MetaPath remove
pub fn testMetaPathRemove(allocator: std.mem.Allocator) !void {
    var meta_path = try MetaPath.initWithDefaults(allocator);
    defer meta_path.deinit();
    const removed = meta_path.remove("FrozenImporter");
    try std.testing.expect(removed);
    try std.testing.expectEqual(@as(usize, 2), meta_path.len());
}

/// Test MetaPath findSpec for builtin
pub fn testMetaPathFindBuiltin(allocator: std.mem.Allocator) !void {
    var meta_path = try MetaPath.initWithDefaults(allocator);
    defer meta_path.deinit();
    const spec = meta_path.findSpec("sys");
    try std.testing.expect(spec != null);
}

/// Test MetaPath findSpec not found
pub fn testMetaPathFindNotFound(allocator: std.mem.Allocator) !void {
    var meta_path = try MetaPath.initWithDefaults(allocator);
    defer meta_path.deinit();
    const spec = meta_path.findSpec("nonexistent_module_xyz");
    try std.testing.expect(spec == null);
}

/// Test ModuleAttributes initialization
pub fn testModuleAttributesInit() !void {
    const attrs = ModuleAttributes.init("mymodule");
    try std.testing.expectEqualStrings("mymodule", attrs.__name__);
    try std.testing.expect(attrs.__doc__ == null);
    try std.testing.expect(!attrs.isPackage());
}

/// Test ModuleAttributes for package
pub fn testModuleAttributesPackage() !void {
    var attrs = ModuleAttributes.init("mypkg");
    attrs.__path__ = &.{"/path/to/mypkg"};
    try std.testing.expect(attrs.isPackage());
}

/// Test ImportHook initialization
pub fn testImportHookInit(allocator: std.mem.Allocator) !void {
    var hook = ImportHook.init(allocator);
    defer hook.deinit();
    try std.testing.expectEqual(@as(usize, 0), hook.getImports().len);
}

/// Test ImportHook recording
pub fn testImportHookRecord(allocator: std.mem.Allocator) !void {
    var hook = ImportHook.init(allocator);
    defer hook.deinit();
    try hook.record("os");
    try hook.record("sys");
    try std.testing.expectEqual(@as(usize, 2), hook.getImports().len);
    try std.testing.expect(hook.wasImported("os"));
    try std.testing.expect(hook.wasImported("sys"));
}

/// Test ImportHook disabled
pub fn testImportHookDisabled(allocator: std.mem.Allocator) !void {
    var hook = ImportHook.init(allocator);
    defer hook.deinit();
    hook.enabled = false;
    try hook.record("os");
    try std.testing.expectEqual(@as(usize, 0), hook.getImports().len);
}

// ============================================================================
// Zig Tests
// ============================================================================

test "MetaPath init" {
    const allocator = std.testing.allocator;
    var meta_path = MetaPath.init(allocator);
    defer meta_path.deinit();
    try std.testing.expectEqual(@as(usize, 0), meta_path.len());
}

test "MetaPath defaults" {
    const allocator = std.testing.allocator;
    var meta_path = try MetaPath.initWithDefaults(allocator);
    defer meta_path.deinit();
    try std.testing.expectEqual(@as(usize, 3), meta_path.len());
}

test "MetaPath append" {
    const allocator = std.testing.allocator;
    var meta_path = MetaPath.init(allocator);
    defer meta_path.deinit();
    try meta_path.append(.{ .name = "Test", .finder_type = .custom });
    try std.testing.expectEqual(@as(usize, 1), meta_path.len());
}

test "MetaPath insert" {
    const allocator = std.testing.allocator;
    var meta_path = try MetaPath.initWithDefaults(allocator);
    defer meta_path.deinit();
    try meta_path.insert(0, .{ .name = "First", .finder_type = .custom });
    try std.testing.expectEqualStrings("First", meta_path.finders.items[0].name);
}

test "MetaPath remove existing" {
    const allocator = std.testing.allocator;
    var meta_path = try MetaPath.initWithDefaults(allocator);
    defer meta_path.deinit();
    try std.testing.expect(meta_path.remove("FrozenImporter"));
}

test "MetaPath remove nonexistent" {
    const allocator = std.testing.allocator;
    var meta_path = try MetaPath.initWithDefaults(allocator);
    defer meta_path.deinit();
    try std.testing.expect(!meta_path.remove("NoSuchFinder"));
}

test "MetaPath findSpec builtin" {
    const allocator = std.testing.allocator;
    var meta_path = try MetaPath.initWithDefaults(allocator);
    defer meta_path.deinit();
    try std.testing.expect(meta_path.findSpec("sys") != null);
}

test "MetaPath findSpec not found" {
    const allocator = std.testing.allocator;
    var meta_path = try MetaPath.initWithDefaults(allocator);
    defer meta_path.deinit();
    try std.testing.expect(meta_path.findSpec("xyz123") == null);
}

test "ModuleAttributes init" {
    const attrs = ModuleAttributes.init("test");
    try std.testing.expectEqualStrings("test", attrs.__name__);
}

test "ModuleAttributes not package" {
    const attrs = ModuleAttributes.init("module");
    try std.testing.expect(!attrs.isPackage());
}

test "ModuleAttributes is package" {
    var attrs = ModuleAttributes.init("pkg");
    attrs.__path__ = &.{"/pkg"};
    try std.testing.expect(attrs.isPackage());
}

test "ModuleAttributes no location" {
    const attrs = ModuleAttributes.init("builtin");
    try std.testing.expect(!attrs.hasLocation());
}

test "ModuleAttributes has location" {
    var attrs = ModuleAttributes.init("file_mod");
    attrs.__file__ = "/path/to/file_mod.py";
    try std.testing.expect(attrs.hasLocation());
}

test "ImportHook init" {
    const allocator = std.testing.allocator;
    var hook = ImportHook.init(allocator);
    defer hook.deinit();
    try std.testing.expect(hook.enabled);
}

test "ImportHook record" {
    const allocator = std.testing.allocator;
    var hook = ImportHook.init(allocator);
    defer hook.deinit();
    try hook.record("module1");
    try std.testing.expectEqual(@as(usize, 1), hook.getImports().len);
}

test "ImportHook wasImported true" {
    const allocator = std.testing.allocator;
    var hook = ImportHook.init(allocator);
    defer hook.deinit();
    try hook.record("os");
    try std.testing.expect(hook.wasImported("os"));
}

test "ImportHook wasImported false" {
    const allocator = std.testing.allocator;
    var hook = ImportHook.init(allocator);
    defer hook.deinit();
    try std.testing.expect(!hook.wasImported("nonexistent"));
}

test "ImportHook clear" {
    const allocator = std.testing.allocator;
    var hook = ImportHook.init(allocator);
    defer hook.deinit();
    try hook.record("a");
    try hook.record("b");
    hook.clear();
    try std.testing.expectEqual(@as(usize, 0), hook.getImports().len);
}

test "ImportHook disabled" {
    const allocator = std.testing.allocator;
    var hook = ImportHook.init(allocator);
    defer hook.deinit();
    hook.enabled = false;
    try hook.record("ignored");
    try std.testing.expectEqual(@as(usize, 0), hook.getImports().len);
}
