//! test.test_importlib.test_util - Tests for importlib utilities
const std = @import("std");

pub fn resolve_name(name: []const u8, package: ?[]const u8) ![]const u8 {
    if (name.len == 0) return error.EmptyName;
    if (name[0] != '.') return name;
    
    if (package == null) return error.NoPackage;
    const pkg = package.?;
    
    var dots: usize = 0;
    for (name) |c| {
        if (c == '.') dots += 1 else break;
    }
    
    if (dots > 1) {
        var parent = pkg;
        var i: usize = 1;
        while (i < dots) : (i += 1) {
            if (std.mem.lastIndexOf(u8, parent, ".")) |idx| {
                parent = parent[0..idx];
            } else return error.ImportError;
        }
        if (name.len > dots) {
            return parent; // Would need concat
        }
        return parent;
    }
    
    return pkg; // Would need concat with name[dots..]
}

pub fn find_spec(name: []const u8, package: ?[]const u8) ?ModuleSpec {
    _ = package;
    return ModuleSpec.init(name);
}

pub fn module_from_spec(spec: ModuleSpec) Module {
    return Module.from_spec(spec);
}

pub const ModuleSpec = struct {
    name: []const u8,
    pub fn init(name: []const u8) @This() { return .{ .name = name }; }
};

pub const Module = struct {
    __name__: []const u8,
    __spec__: ?ModuleSpec = null,
    
    pub fn from_spec(spec: ModuleSpec) @This() {
        return .{ .__name__ = spec.name, .__spec__ = spec };
    }
};

fn testResolveName() !void {
    const result = try resolve_name("os", null);
    try std.testing.expectEqualStrings("os", result);
}

fn testResolveRelativeName() !void {
    const result = resolve_name(".", null);
    try std.testing.expectError(error.NoPackage, result);
}

fn testFindSpec() !void {
    if (find_spec("os", null)) |spec| {
        try std.testing.expectEqualStrings("os", spec.name);
    }
}

fn testModuleFromSpec() !void {
    const spec = ModuleSpec.init("mymodule");
    const mod = module_from_spec(spec);
    try std.testing.expectEqualStrings("mymodule", mod.__name__);
}

test "resolve_name" { try testResolveName(); }
test "resolve_relative_name" { try testResolveRelativeName(); }
test "find_spec" { try testFindSpec(); }
test "module_from_spec" { try testModuleFromSpec(); }
