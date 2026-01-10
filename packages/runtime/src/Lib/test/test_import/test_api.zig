//! test.test_import.test_api - Import API testing
//!
//! Tests for Python's import system API including:
//! - __import__() builtin function
//! - importlib.import_module()
//! - Module attributes (__name__, __file__, __package__, etc.)
//! - Import hooks and customization

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Import function signature matching Python's __import__
pub const ImportFn = *const fn (
    name: []const u8,
    globals: ?*const ModuleDict,
    locals: ?*const ModuleDict,
    fromlist: ?[]const []const u8,
    level: i32,
) ImportError!*Module;

/// Module dictionary type for globals/locals
pub const ModuleDict = struct {
    entries: std.StringHashMapUnmanaged(Value),
    allocator: Allocator,

    pub fn init(allocator: Allocator) ModuleDict {
        return .{
            .entries = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ModuleDict) void {
        self.entries.deinit(self.allocator);
    }

    pub fn get(self: *const ModuleDict, key: []const u8) ?Value {
        return self.entries.get(key);
    }

    pub fn put(self: *ModuleDict, key: []const u8, value: Value) !void {
        try self.entries.put(self.allocator, key, value);
    }

    pub fn contains(self: *const ModuleDict, key: []const u8) bool {
        return self.entries.contains(key);
    }
};

/// Generic Python value for the import system
pub const Value = union(enum) {
    none,
    boolean: bool,
    integer: i64,
    float: f64,
    string: []const u8,
    list: []Value,
    module: *Module,

    pub fn isNone(self: Value) bool {
        return self == .none;
    }

    pub fn asString(self: Value) ?[]const u8 {
        return switch (self) {
            .string => |s| s,
            else => null,
        };
    }
};

/// Python module representation
pub const Module = struct {
    __name__: []const u8,
    __file__: ?[]const u8,
    __package__: ?[]const u8,
    __loader__: ?*const Loader,
    __spec__: ?*const ModuleSpec,
    __dict__: ModuleDict,
    __doc__: ?[]const u8,
    __cached__: ?[]const u8,
    __path__: ?[]const []const u8,

    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8) !*Module {
        const module = try allocator.create(Module);
        module.* = .{
            .__name__ = name,
            .__file__ = null,
            .__package__ = null,
            .__loader__ = null,
            .__spec__ = null,
            .__dict__ = ModuleDict.init(allocator),
            .__doc__ = null,
            .__cached__ = null,
            .__path__ = null,
            .allocator = allocator,
        };
        return module;
    }

    pub fn deinit(self: *Module) void {
        self.__dict__.deinit();
        self.allocator.destroy(self);
    }

    pub fn getAttr(self: *const Module, name: []const u8) ?Value {
        if (std.mem.eql(u8, name, "__name__")) return .{ .string = self.__name__ };
        if (std.mem.eql(u8, name, "__file__")) {
            if (self.__file__) |f| return .{ .string = f };
            return .none;
        }
        if (std.mem.eql(u8, name, "__package__")) {
            if (self.__package__) |p| return .{ .string = p };
            return .none;
        }
        return self.__dict__.get(name);
    }

    pub fn setAttr(self: *Module, name: []const u8, value: Value) !void {
        try self.__dict__.put(name, value);
    }

    pub fn isPackage(self: *const Module) bool {
        return self.__path__ != null;
    }
};

/// Module spec (PEP 451)
pub const ModuleSpec = struct {
    name: []const u8,
    loader: ?*const Loader,
    origin: ?[]const u8,
    submodule_search_locations: ?[]const []const u8,
    loader_state: ?*anyopaque,
    cached: ?[]const u8,
    parent: ?[]const u8,
    has_location: bool,

    pub fn init(name: []const u8) ModuleSpec {
        return .{
            .name = name,
            .loader = null,
            .origin = null,
            .submodule_search_locations = null,
            .loader_state = null,
            .cached = null,
            .parent = null,
            .has_location = false,
        };
    }

    pub fn isPackageSpec(self: *const ModuleSpec) bool {
        return self.submodule_search_locations != null;
    }
};

/// Abstract loader interface
pub const Loader = struct {
    vtable: *const VTable,

    pub const VTable = struct {
        create_module: *const fn (*const Loader, *const ModuleSpec) ?*Module,
        exec_module: *const fn (*const Loader, *Module) LoaderError!void,
        load_module: *const fn (*const Loader, []const u8) LoaderError!*Module,
    };

    pub fn createModule(self: *const Loader, spec: *const ModuleSpec) ?*Module {
        return self.vtable.create_module(self, spec);
    }

    pub fn execModule(self: *const Loader, module: *Module) LoaderError!void {
        return self.vtable.exec_module(self, module);
    }
};

pub const LoaderError = error{
    ModuleNotFound,
    LoaderFailed,
    ExecutionFailed,
};

pub const ImportError = error{
    ModuleNotFoundError,
    ImportError,
    OutOfMemory,
};

/// Import system state
pub const ImportState = struct {
    modules: std.StringHashMapUnmanaged(*Module),
    meta_path: std.ArrayListUnmanaged(*const Finder),
    path_hooks: std.ArrayListUnmanaged(PathHook),
    path_importer_cache: std.StringHashMapUnmanaged(?*const Finder),
    path: std.ArrayListUnmanaged([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) ImportState {
        return .{
            .modules = .{},
            .meta_path = .{},
            .path_hooks = .{},
            .path_importer_cache = .{},
            .path = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ImportState) void {
        self.modules.deinit(self.allocator);
        self.meta_path.deinit(self.allocator);
        self.path_hooks.deinit(self.allocator);
        self.path_importer_cache.deinit(self.allocator);
        self.path.deinit(self.allocator);
    }

    pub fn getModule(self: *const ImportState, name: []const u8) ?*Module {
        return self.modules.get(name);
    }

    pub fn registerModule(self: *ImportState, name: []const u8, module: *Module) !void {
        try self.modules.put(self.allocator, name, module);
    }

    pub fn addMetaPathFinder(self: *ImportState, finder: *const Finder) !void {
        try self.meta_path.append(self.allocator, finder);
    }

    pub fn addPathHook(self: *ImportState, hook: PathHook) !void {
        try self.path_hooks.append(self.allocator, hook);
    }
};

/// Path hook function type
pub const PathHook = *const fn (path: []const u8) ?*const Finder;

/// Abstract finder interface
pub const Finder = struct {
    vtable: *const VTable,

    pub const VTable = struct {
        find_spec: *const fn (*const Finder, []const u8, ?[]const u8, ?*Module) ?*ModuleSpec,
        find_module: *const fn (*const Finder, []const u8, ?[]const u8) ?*const Loader,
    };

    pub fn findSpec(self: *const Finder, name: []const u8, path: ?[]const u8, target: ?*Module) ?*ModuleSpec {
        return self.vtable.find_spec(self, name, path, target);
    }
};

/// Perform a Python import
pub fn importModule(state: *ImportState, name: []const u8) ImportError!*Module {
    // Check cache first
    if (state.getModule(name)) |module| {
        return module;
    }

    // Try meta path finders
    for (state.meta_path.items) |finder| {
        if (finder.findSpec(name, null, null)) |spec| {
            if (spec.loader) |loader| {
                if (loader.createModule(spec)) |module| {
                    loader.execModule(module) catch return error.ImportError;
                    state.registerModule(name, module) catch return error.OutOfMemory;
                    return module;
                }
            }
        }
    }

    return error.ModuleNotFoundError;
}

/// Split a dotted module name into parts
pub fn splitModuleName(allocator: Allocator, name: []const u8) ![][]const u8 {
    var parts = std.ArrayList([]const u8).init(allocator);
    var iter = std.mem.splitScalar(u8, name, '.');
    while (iter.next()) |part| {
        try parts.append(part);
    }
    return parts.toOwnedSlice();
}

/// Get the parent package name
pub fn getParentPackage(name: []const u8) ?[]const u8 {
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |idx| {
        return name[0..idx];
    }
    return null;
}

// =============================================================================
// Tests
// =============================================================================

test "module_dict_operations" {
    var dict = ModuleDict.init(std.testing.allocator);
    defer dict.deinit();

    try dict.put("key1", .{ .string = "value1" });
    try dict.put("key2", .{ .integer = 42 });

    try std.testing.expect(dict.contains("key1"));
    try std.testing.expect(dict.contains("key2"));
    try std.testing.expect(!dict.contains("key3"));

    const val1 = dict.get("key1");
    try std.testing.expect(val1 != null);
    try std.testing.expectEqualStrings("value1", val1.?.asString().?);

    const val2 = dict.get("key2");
    try std.testing.expect(val2 != null);
    try std.testing.expectEqual(@as(i64, 42), val2.?.integer);
}

test "module_creation" {
    const module = try Module.init(std.testing.allocator, "test_module");
    defer module.deinit();

    try std.testing.expectEqualStrings("test_module", module.__name__);
    try std.testing.expect(module.__file__ == null);
    try std.testing.expect(module.__package__ == null);
    try std.testing.expect(!module.isPackage());
}

test "module_attributes" {
    const module = try Module.init(std.testing.allocator, "mymodule");
    defer module.deinit();

    module.__file__ = "/path/to/mymodule.py";
    module.__package__ = "mypackage";

    const name = module.getAttr("__name__");
    try std.testing.expect(name != null);
    try std.testing.expectEqualStrings("mymodule", name.?.asString().?);

    const file = module.getAttr("__file__");
    try std.testing.expect(file != null);
    try std.testing.expectEqualStrings("/path/to/mymodule.py", file.?.asString().?);

    const pkg = module.getAttr("__package__");
    try std.testing.expect(pkg != null);
    try std.testing.expectEqualStrings("mypackage", pkg.?.asString().?);
}

test "module_setattr" {
    const module = try Module.init(std.testing.allocator, "test");
    defer module.deinit();

    try module.setAttr("custom_attr", .{ .integer = 123 });

    const val = module.getAttr("custom_attr");
    try std.testing.expect(val != null);
    try std.testing.expectEqual(@as(i64, 123), val.?.integer);
}

test "module_spec_init" {
    const spec = ModuleSpec.init("my.module");

    try std.testing.expectEqualStrings("my.module", spec.name);
    try std.testing.expect(spec.loader == null);
    try std.testing.expect(spec.origin == null);
    try std.testing.expect(!spec.isPackageSpec());
    try std.testing.expect(!spec.has_location);
}

test "import_state_init" {
    var state = ImportState.init(std.testing.allocator);
    defer state.deinit();

    try std.testing.expect(state.modules.count() == 0);
    try std.testing.expect(state.meta_path.items.len == 0);
    try std.testing.expect(state.path_hooks.items.len == 0);
}

test "import_state_register_module" {
    var state = ImportState.init(std.testing.allocator);
    defer state.deinit();

    const module = try Module.init(std.testing.allocator, "registered");
    defer module.deinit();

    try state.registerModule("registered", module);

    const found = state.getModule("registered");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("registered", found.?.__name__);
}

test "split_module_name" {
    const parts = try splitModuleName(std.testing.allocator, "os.path.join");
    defer std.testing.allocator.free(parts);

    try std.testing.expectEqual(@as(usize, 3), parts.len);
    try std.testing.expectEqualStrings("os", parts[0]);
    try std.testing.expectEqualStrings("path", parts[1]);
    try std.testing.expectEqualStrings("join", parts[2]);
}

test "split_single_name" {
    const parts = try splitModuleName(std.testing.allocator, "os");
    defer std.testing.allocator.free(parts);

    try std.testing.expectEqual(@as(usize, 1), parts.len);
    try std.testing.expectEqualStrings("os", parts[0]);
}

test "get_parent_package" {
    const parent1 = getParentPackage("os.path.join");
    try std.testing.expect(parent1 != null);
    try std.testing.expectEqualStrings("os.path", parent1.?);

    const parent2 = getParentPackage("os.path");
    try std.testing.expect(parent2 != null);
    try std.testing.expectEqualStrings("os", parent2.?);

    const parent3 = getParentPackage("os");
    try std.testing.expect(parent3 == null);
}

test "value_types" {
    const none_val = Value.none;
    try std.testing.expect(none_val.isNone());

    const bool_val = Value{ .boolean = true };
    try std.testing.expect(!bool_val.isNone());

    const str_val = Value{ .string = "hello" };
    try std.testing.expectEqualStrings("hello", str_val.asString().?);

    const int_val = Value{ .integer = 42 };
    try std.testing.expect(int_val.asString() == null);
}
