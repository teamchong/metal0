//! test.test_importlib.test_from_import - Tests for from X import Y
const std = @import("std");

pub const FromImport = struct {
    module: []const u8,
    names: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, module: []const u8) @This() {
        return .{
            .allocator = allocator,
            .module = module,
            .names = std.ArrayList([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *@This()) void { self.names.deinit(); }
    pub fn add_name(self: *@This(), name: []const u8) !void { try self.names.append(name); }
    pub fn execute(self: *@This()) !void { _ = self; }
};

fn testFromImport() !void {
    const allocator = std.testing.allocator;
    var fi = FromImport.init(allocator, "os.path");
    defer fi.deinit();
    try fi.add_name("join");
    try fi.add_name("exists");
    try std.testing.expectEqual(@as(usize, 2), fi.names.items.len);
}

test "from_import" { try testFromImport(); }
