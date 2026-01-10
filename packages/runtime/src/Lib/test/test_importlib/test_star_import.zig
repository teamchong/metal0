//! test.test_importlib.test_star_import - Tests for from X import *
const std = @import("std");

pub const StarImport = struct {
    module: []const u8,
    all_names: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, module: []const u8) @This() {
        return .{
            .allocator = allocator,
            .module = module,
            .all_names = std.ArrayList([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void { self.all_names.deinit(); }
    
    pub fn get_all(self: *@This()) ![]const []const u8 {
        _ = self;
        return &.{};
    }
    
    pub fn execute(self: *@This()) !void {
        const names = try self.get_all();
        for (names) |name| {
            try self.all_names.append(name);
        }
    }
};

fn testStarImport() !void {
    const allocator = std.testing.allocator;
    var si = StarImport.init(allocator, "collections");
    defer si.deinit();
    try std.testing.expectEqualStrings("collections", si.module);
}

test "star_import" { try testStarImport(); }
