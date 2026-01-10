//! test.test_importlib.test_namespace_pkgs - Tests for namespace packages
//! Reference: cpython/Lib/test/test_importlib/test_namespace_pkgs.py

const std = @import("std");

pub const NamespacePackage = struct {
    const Self = @This();
    
    name: []const u8,
    paths: std.ArrayList([]const u8),
    submodules: std.StringHashMap(*Module),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return .{
            .allocator = allocator,
            .name = name,
            .paths = std.ArrayList([]const u8).init(allocator),
            .submodules = std.StringHashMap(*Module).init(allocator),
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.paths.deinit();
        self.submodules.deinit();
    }
    
    pub fn add_path(self: *Self, path: []const u8) !void {
        try self.paths.append(path);
    }
    
    pub fn get_submodule(self: *Self, name: []const u8) ?*Module {
        return self.submodules.get(name);
    }
    
    pub fn add_submodule(self: *Self, name: []const u8, module: *Module) !void {
        try self.submodules.put(name, module);
    }
    
    pub fn path_count(self: *Self) usize {
        return self.paths.items.len;
    }
};

pub const NamespaceLoader = struct {
    const Self = @This();
    
    package: *NamespacePackage,
    
    pub fn init(pkg: *NamespacePackage) Self {
        return .{ .package = pkg };
    }
    
    pub fn create_module(self: *Self, spec: ModuleSpec) *Module {
        _ = self; 
        var module = Module.init(spec.name);
        module.__path__ = &.{};
        return &module;
    }
    
    pub fn exec_module(self: *Self, module: *Module) void {
        _ = self; _ = module;
    }
};

pub const Module = struct {
    __name__: []const u8,
    __path__: ?[]const []const u8 = null,
    __file__: ?[]const u8 = null,
    
    pub fn init(name: []const u8) @This() {
        return .{ .__name__ = name };
    }
};

pub const ModuleSpec = struct {
    name: []const u8,
    is_package: bool = true,
    submodule_search_locations: ?[]const []const u8 = null,
    
    pub fn init(name: []const u8) @This() {
        return .{ .name = name };
    }
};

fn testNamespacePackage() !void {
    const allocator = std.testing.allocator;
    var pkg = NamespacePackage.init(allocator, "myns");
    defer pkg.deinit();
    
    try pkg.add_path("/path/one/myns");
    try pkg.add_path("/path/two/myns");
    
    try std.testing.expectEqual(@as(usize, 2), pkg.path_count());
}

fn testNamespacePackageSubmodules() !void {
    const allocator = std.testing.allocator;
    var pkg = NamespacePackage.init(allocator, "myns");
    defer pkg.deinit();
    
    var sub = Module.init("myns.sub");
    try pkg.add_submodule("sub", &sub);
    
    if (pkg.get_submodule("sub")) |m| {
        try std.testing.expectEqualStrings("myns.sub", m.__name__);
    } else {
        return error.SubmoduleNotFound;
    }
}

fn testNamespaceLoader() !void {
    const allocator = std.testing.allocator;
    var pkg = NamespacePackage.init(allocator, "testns");
    defer pkg.deinit();
    
    var loader = NamespaceLoader.init(&pkg);
    const spec = ModuleSpec.init("testns");
    
    const module = loader.create_module(spec);
    try std.testing.expectEqualStrings("testns", module.__name__);
}

test "namespace_package" { try testNamespacePackage(); }
test "namespace_package_submodules" { try testNamespacePackageSubmodules(); }
test "namespace_loader" { try testNamespaceLoader(); }
