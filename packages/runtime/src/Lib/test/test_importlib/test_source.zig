//! test.test_importlib.test_source - Tests for source loaders
const std = @import("std");

pub const SourceFileLoader = struct {
    name: []const u8,
    path: []const u8,
    
    pub fn init(name: []const u8, path: []const u8) @This() {
        return .{ .name = name, .path = path };
    }
    
    pub fn get_filename(self: @This()) []const u8 {
        return self.path;
    }
    
    pub fn get_data(self: @This(), path: []const u8) ![]const u8 {
        _ = self; _ = path;
        return error.FileNotFound;
    }
    
    pub fn path_stats(self: @This(), path: []const u8) !PathStats {
        _ = self; _ = path;
        return error.FileNotFound;
    }
};

pub const SourcelessFileLoader = struct {
    name: []const u8,
    path: []const u8,
    
    pub fn init(name: []const u8, path: []const u8) @This() {
        return .{ .name = name, .path = path };
    }
    
    pub fn get_filename(self: @This()) []const u8 {
        return self.path;
    }
};

pub const PathStats = struct {
    mtime: i64 = 0,
    size: i64 = 0,
};

fn testSourceFileLoader() !void {
    const loader = SourceFileLoader.init("mymodule", "/path/to/mymodule.py");
    try std.testing.expectEqualStrings("mymodule", loader.name);
    try std.testing.expectEqualStrings("/path/to/mymodule.py", loader.get_filename());
}

fn testSourcelessFileLoader() !void {
    const loader = SourcelessFileLoader.init("compiled", "/path/to/compiled.pyc");
    try std.testing.expectEqualStrings("compiled", loader.name);
}

test "source_file_loader" { try testSourceFileLoader(); }
test "sourceless_file_loader" { try testSourcelessFileLoader(); }
