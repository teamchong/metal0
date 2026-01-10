//! test.test_importlib.test_spec - Tests for module specs
const std = @import("std");

pub const ModuleSpec = struct {
    name: []const u8,
    loader: ?*Loader = null,
    origin: ?[]const u8 = null,
    submodule_search_locations: ?[]const []const u8 = null,
    loader_state: ?*anyopaque = null,
    cached: ?[]const u8 = null,
    parent: ?[]const u8 = null,
    is_package: bool = false,
    has_location: bool = false,
    
    pub fn init(name: []const u8) @This() {
        return .{ .name = name };
    }
    
    pub fn from_file_location(name: []const u8, location: []const u8) @This() {
        return .{ .name = name, .origin = location, .has_location = true };
    }
    
    pub fn parent_name(self: @This()) ?[]const u8 {
        if (std.mem.lastIndexOf(u8, self.name, ".")) |idx| {
            return self.name[0..idx];
        }
        return null;
    }
};

pub const Loader = struct {
    name: []const u8 = "GenericLoader",
};

fn testModuleSpec() !void {
    const spec = ModuleSpec.init("mymodule");
    try std.testing.expectEqualStrings("mymodule", spec.name);
    try std.testing.expect(!spec.is_package);
}

fn testModuleSpecFromFileLocation() !void {
    const spec = ModuleSpec.from_file_location("mymod", "/path/to/mymod.py");
    try std.testing.expectEqualStrings("mymod", spec.name);
    try std.testing.expectEqualStrings("/path/to/mymod.py", spec.origin.?);
    try std.testing.expect(spec.has_location);
}

fn testParentName() !void {
    const spec = ModuleSpec.init("package.subpackage.module");
    if (spec.parent_name()) |parent| {
        try std.testing.expectEqualStrings("package.subpackage", parent);
    }
}

test "module_spec" { try testModuleSpec(); }
test "module_spec_from_file" { try testModuleSpecFromFileLocation(); }
test "parent_name" { try testParentName(); }
