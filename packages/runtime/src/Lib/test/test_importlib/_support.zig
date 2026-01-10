//! test.test_importlib._support - Support utilities for importlib tests
//! Reference: cpython/Lib/test/test_importlib/test_abc.py

const std = @import("std");

pub const ModuleSpec = struct {
    name: []const u8,
    loader: ?*Loader = null,
    origin: ?[]const u8 = null,
    is_package: bool = false,
    submodule_search_locations: ?[]const []const u8 = null,

    pub fn init(name: []const u8) @This() { return .{ .name = name }; }
};

pub const Loader = struct {
    name: []const u8,
    pub fn create_module(self: *@This(), spec: ModuleSpec) ?*Module {
        _ = self; _ = spec; return null;
    }
    pub fn exec_module(self: *@This(), module: *Module) !void { _ = self; _ = module; }
};

pub const Module = struct {
    __name__: []const u8,
    __spec__: ?ModuleSpec = null,
    __loader__: ?*Loader = null,
    __package__: ?[]const u8 = null,
    __path__: ?[]const []const u8 = null,
    __file__: ?[]const u8 = null,

    pub fn init(name: []const u8) @This() { return .{ .__name__ = name }; }
};

pub const PathFinder = struct {
    search_paths: std.ArrayList([]const u8),
    
    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .search_paths = std.ArrayList([]const u8).init(allocator) };
    }
    pub fn deinit(self: *@This()) void { self.search_paths.deinit(); }
    pub fn find_spec(self: *@This(), name: []const u8) ?ModuleSpec {
        _ = self; return ModuleSpec.init(name);
    }
};

test "module_spec" {
    const spec = ModuleSpec.init("test_module");
    try std.testing.expectEqualStrings("test_module", spec.name);
}
