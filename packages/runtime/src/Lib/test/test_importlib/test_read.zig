//! test.test_importlib.test_read - Tests for resource reading
const std = @import("std");

pub fn read_text(package: []const u8, resource: []const u8) ![]const u8 {
    _ = package; _ = resource;
    return error.ResourceNotFound;
}

pub fn read_binary(package: []const u8, resource: []const u8) ![]const u8 {
    _ = package; _ = resource;
    return error.ResourceNotFound;
}

pub const Traversable = struct {
    path: []const u8,
    
    pub fn init(path: []const u8) @This() { return .{ .path = path }; }
    
    pub fn read_bytes(self: @This()) ![]const u8 {
        _ = self;
        return error.NotImplemented;
    }
    
    pub fn read_text(self: @This(), encoding: []const u8) ![]const u8 {
        _ = self; _ = encoding;
        return error.NotImplemented;
    }
    
    pub fn joinpath(self: @This(), child: []const u8) @This() {
        _ = self; _ = child;
        return @This().init("");
    }
    
    pub fn iterdir(self: @This()) ![]const @This() {
        _ = self;
        return &.{};
    }
};

fn testReadFunctions() !void {
    try std.testing.expectError(error.ResourceNotFound, read_text("pkg", "file.txt"));
    try std.testing.expectError(error.ResourceNotFound, read_binary("pkg", "file.bin"));
}

fn testTraversable() !void {
    const t = Traversable.init("/some/path");
    try std.testing.expectEqualStrings("/some/path", t.path);
}

test "read_functions" { try testReadFunctions(); }
test "traversable" { try testTraversable(); }
