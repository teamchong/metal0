//! test.test_importlib.test_resources - Tests for package resources
const std = @import("std");

pub fn files(package: []const u8) Traversable {
    return Traversable.init(package);
}

pub fn as_file(resource: Traversable) !std.fs.File {
    _ = resource;
    return error.NotImplemented;
}

pub const Traversable = struct {
    name: []const u8,
    is_dir: bool = false,
    is_file: bool = false,
    
    pub fn init(name: []const u8) @This() { return .{ .name = name }; }
    
    pub fn joinpath(self: @This(), child: []const u8) @This() {
        _ = self; _ = child;
        return @This().init("");
    }
    
    pub fn iterdir(self: @This()) []const @This() {
        _ = self;
        return &.{};
    }
    
    pub fn read_bytes(self: @This()) ![]const u8 {
        _ = self;
        return error.NotImplemented;
    }
    
    pub fn read_text(self: @This()) ![]const u8 {
        _ = self;
        return error.NotImplemented;
    }
};

fn testFiles() !void {
    const t = files("mypackage");
    try std.testing.expectEqualStrings("mypackage", t.name);
}

fn testTraversableJoinpath() !void {
    const t = Traversable.init("package");
    const child = t.joinpath("subdir");
    _ = child;
}

test "files" { try testFiles(); }
test "traversable_joinpath" { try testTraversableJoinpath(); }
