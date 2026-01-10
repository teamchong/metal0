//! test.test_importlib.test_windows - Windows-specific importlib tests
const std = @import("std");
const builtin = @import("builtin");

pub const is_windows = builtin.os.tag == .windows;

pub const WindowsRegistryFinder = struct {
    const Self = @This();
    
    registry_key: []const u8 = "SOFTWARE\\Python",
    
    pub fn find_spec(self: *Self, name: []const u8, path: ?[]const []const u8, target: ?*Module) ?ModuleSpec {
        _ = self; _ = path; _ = target;
        if (!is_windows) return null;
        return ModuleSpec.init(name);
    }
    
    pub fn find_module(self: *Self, name: []const u8, path: ?[]const []const u8) ?*Loader {
        _ = self; _ = name; _ = path;
        return null;
    }
};

pub const ExtensionFileLoader = struct {
    name: []const u8,
    path: []const u8,
    
    pub fn init(name: []const u8, path: []const u8) @This() {
        return .{ .name = name, .path = path };
    }
    
    pub fn is_package(self: @This(), fullname: []const u8) bool {
        _ = self; _ = fullname;
        return false;
    }
};

pub const ModuleSpec = struct {
    name: []const u8,
    pub fn init(name: []const u8) @This() { return .{ .name = name }; }
};

pub const Module = struct {};
pub const Loader = struct {};

fn testWindowsRegistryFinder() !void {
    var finder = WindowsRegistryFinder{};
    // On non-Windows, should return null
    if (!is_windows) {
        try std.testing.expect(finder.find_spec("test", null, null) == null);
    }
}

fn testExtensionFileLoader() !void {
    const loader = ExtensionFileLoader.init("myext", "/path/to/myext.pyd");
    try std.testing.expectEqualStrings("myext", loader.name);
    try std.testing.expect(!loader.is_package("myext"));
}

test "windows_registry_finder" { try testWindowsRegistryFinder(); }
test "extension_file_loader" { try testExtensionFileLoader(); }
