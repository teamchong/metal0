//! test.test_importlib.test_abc - Tests for importlib.abc
//! Reference: cpython/Lib/test/test_importlib/test_abc.py

const std = @import("std");

// ============================================================================
// Abstract Base Classes for Import System
// ============================================================================

pub const Finder = struct {
    const Self = @This();
    
    find_module_fn: ?*const fn (*Self, []const u8, ?[]const []const u8) ?*Loader = null,
    find_spec_fn: ?*const fn (*Self, []const u8, ?[]const []const u8) ?ModuleSpec = null,
    
    pub fn find_module(self: *Self, name: []const u8, path: ?[]const []const u8) ?*Loader {
        if (self.find_module_fn) |f| return f(self, name, path);
        return null;
    }
    
    pub fn find_spec(self: *Self, name: []const u8, path: ?[]const []const u8) ?ModuleSpec {
        if (self.find_spec_fn) |f| return f(self, name, path);
        return null;
    }
};

pub const Loader = struct {
    const Self = @This();
    
    name: []const u8 = "Loader",
    create_module_fn: ?*const fn (*Self, ModuleSpec) ?*Module = null,
    exec_module_fn: ?*const fn (*Self, *Module) anyerror!void = null,
    load_module_fn: ?*const fn (*Self, []const u8) anyerror!*Module = null,
    
    pub fn create_module(self: *Self, spec: ModuleSpec) ?*Module {
        if (self.create_module_fn) |f| return f(self, spec);
        return null;
    }
    
    pub fn exec_module(self: *Self, module: *Module) !void {
        if (self.exec_module_fn) |f| return f(self, module);
    }
    
    pub fn load_module(self: *Self, name: []const u8) !*Module {
        if (self.load_module_fn) |f| return f(self, name);
        return error.LoaderError;
    }
};

pub const MetaPathFinder = struct {
    const Self = @This();
    
    priority: i32 = 0,
    finder: Finder = .{},
    
    pub fn find_spec(self: *Self, name: []const u8, path: ?[]const []const u8, target: ?*Module) ?ModuleSpec {
        _ = target;
        return self.finder.find_spec(name, path);
    }
};

pub const PathEntryFinder = struct {
    const Self = @This();
    
    path_entry: []const u8,
    
    pub fn init(path: []const u8) Self {
        return .{ .path_entry = path };
    }
    
    pub fn find_spec(self: *Self, name: []const u8, target: ?*Module) ?ModuleSpec {
        _ = self; _ = target;
        return ModuleSpec.init(name);
    }
};

pub const ResourceLoader = struct {
    const Self = @This();
    
    pub fn get_data(self: *Self, path: []const u8) ![]const u8 {
        _ = self; _ = path;
        return error.ResourceNotFound;
    }
};

pub const InspectLoader = struct {
    const Self = @This();
    
    loader: Loader = .{},
    
    pub fn get_code(self: *Self, name: []const u8) ![]const u8 {
        _ = self; _ = name;
        return error.NoCode;
    }
    
    pub fn get_source(self: *Self, name: []const u8) ![]const u8 {
        _ = self; _ = name;
        return error.NoSource;
    }
    
    pub fn is_package(self: *Self, name: []const u8) bool {
        _ = self; _ = name;
        return false;
    }
};

pub const ExecutionLoader = struct {
    const Self = @This();
    
    inspect_loader: InspectLoader = .{},
    
    pub fn get_filename(self: *Self, name: []const u8) ![]const u8 {
        _ = self; _ = name;
        return error.NoFilename;
    }
};

pub const SourceLoader = struct {
    const Self = @This();
    
    exec_loader: ExecutionLoader = .{},
    
    pub fn path_stats(self: *Self, path: []const u8) !PathStats {
        _ = self; _ = path;
        return error.NoStats;
    }
    
    pub fn path_mtime(self: *Self, path: []const u8) !i64 {
        _ = self; _ = path;
        return error.NoMtime;
    }
    
    pub fn set_data(self: *Self, path: []const u8, data: []const u8) !void {
        _ = self; _ = path; _ = data;
    }
};

// ============================================================================
// Supporting Types
// ============================================================================

pub const ModuleSpec = struct {
    name: []const u8,
    loader: ?*Loader = null,
    origin: ?[]const u8 = null,
    is_package: bool = false,
    submodule_search_locations: ?[]const []const u8 = null,
    loader_state: ?*anyopaque = null,
    cached: ?[]const u8 = null,
    parent: ?[]const u8 = null,
    has_location: bool = false,

    pub fn init(name: []const u8) @This() { 
        return .{ .name = name }; 
    }
    
    pub fn with_loader(name: []const u8, loader: *Loader) @This() {
        return .{ .name = name, .loader = loader };
    }
    
    pub fn with_origin(name: []const u8, origin: []const u8) @This() {
        return .{ .name = name, .origin = origin, .has_location = true };
    }
};

pub const Module = struct {
    __name__: []const u8,
    __spec__: ?ModuleSpec = null,
    __loader__: ?*Loader = null,
    __package__: ?[]const u8 = null,
    __path__: ?[]const []const u8 = null,
    __file__: ?[]const u8 = null,
    __doc__: ?[]const u8 = null,
    __dict__: ?*anyopaque = null,

    pub fn init(name: []const u8) @This() { 
        return .{ .__name__ = name }; 
    }
    
    pub fn from_spec(spec: ModuleSpec) @This() {
        return .{
            .__name__ = spec.name,
            .__spec__ = spec,
            .__loader__ = spec.loader,
        };
    }
};

pub const PathStats = struct {
    mtime: i64 = 0,
    size: i64 = 0,
};

// ============================================================================
// Test Cases
// ============================================================================

fn testModuleSpec() !void {
    const spec = ModuleSpec.init("my_module");
    try std.testing.expectEqualStrings("my_module", spec.name);
    try std.testing.expect(spec.loader == null);
    try std.testing.expect(!spec.is_package);
}

fn testModuleSpecWithOrigin() !void {
    const spec = ModuleSpec.with_origin("my_module", "/path/to/module.py");
    try std.testing.expectEqualStrings("my_module", spec.name);
    try std.testing.expectEqualStrings("/path/to/module.py", spec.origin.?);
    try std.testing.expect(spec.has_location);
}

fn testModule() !void {
    const mod = Module.init("test_module");
    try std.testing.expectEqualStrings("test_module", mod.__name__);
    try std.testing.expect(mod.__spec__ == null);
}

fn testModuleFromSpec() !void {
    const spec = ModuleSpec.init("from_spec_module");
    const mod = Module.from_spec(spec);
    try std.testing.expectEqualStrings("from_spec_module", mod.__name__);
    try std.testing.expect(mod.__spec__ != null);
}

fn testFinder() !void {
    var finder = Finder{};
    try std.testing.expect(finder.find_module("test", null) == null);
    try std.testing.expect(finder.find_spec("test", null) == null);
}

fn testLoader() !void {
    var loader = Loader{};
    const spec = ModuleSpec.init("test");
    try std.testing.expect(loader.create_module(spec) == null);
}

fn testMetaPathFinder() !void {
    var mpf = MetaPathFinder{};
    try std.testing.expect(mpf.find_spec("test", null, null) == null);
}

fn testPathEntryFinder() !void {
    var pef = PathEntryFinder.init("/some/path");
    try std.testing.expectEqualStrings("/some/path", pef.path_entry);
    if (pef.find_spec("module", null)) |spec| {
        try std.testing.expectEqualStrings("module", spec.name);
    }
}

fn testInspectLoader() !void {
    var il = InspectLoader{};
    try std.testing.expect(!il.is_package("test"));
    try std.testing.expectError(error.NoCode, il.get_code("test"));
    try std.testing.expectError(error.NoSource, il.get_source("test"));
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "module_spec" { try testModuleSpec(); }
test "module_spec_with_origin" { try testModuleSpecWithOrigin(); }
test "module" { try testModule(); }
test "module_from_spec" { try testModuleFromSpec(); }
test "finder" { try testFinder(); }
test "loader" { try testLoader(); }
test "meta_path_finder" { try testMetaPathFinder(); }
test "path_entry_finder" { try testPathEntryFinder(); }
test "inspect_loader" { try testInspectLoader(); }
