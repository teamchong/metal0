//! test.test_importlib.test_pkg - Tests for package imports
const std = @import("std");

pub const Package = struct {
    name: []const u8,
    path: ?[]const u8 = null,
    subpackages: std.ArrayList([]const u8),
    modules: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8) @This() {
        return .{
            .allocator = allocator,
            .name = name,
            .subpackages = std.ArrayList([]const u8).init(allocator),
            .modules = std.ArrayList([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void {
        self.subpackages.deinit();
        self.modules.deinit();
    }
    
    pub fn add_subpackage(self: *@This(), name: []const u8) !void {
        try self.subpackages.append(name);
    }
    
    pub fn add_module(self: *@This(), name: []const u8) !void {
        try self.modules.append(name);
    }
};

fn testPackage() !void {
    const allocator = std.testing.allocator;
    var pkg = Package.init(allocator, "mypackage");
    defer pkg.deinit();
    
    try pkg.add_subpackage("sub");
    try pkg.add_module("utils");
    
    try std.testing.expectEqual(@as(usize, 1), pkg.subpackages.items.len);
    try std.testing.expectEqual(@as(usize, 1), pkg.modules.items.len);
}

test "package" { try testPackage(); }
