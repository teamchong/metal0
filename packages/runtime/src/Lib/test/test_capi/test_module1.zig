//! test.test_capi.test_module1 - C API Module Tests Part 1
const std = @import("std");

/// PyModule definition structure
pub const PyModuleDef = struct {
    name: []const u8,
    doc: ?[]const u8 = null,
    size: isize = -1,
    methods: ?[]const PyMethodDef = null,
    slots: ?[]const PyModuleDef_Slot = null,

    pub fn init(name: []const u8) PyModuleDef {
        return .{ .name = name };
    }

    pub fn with_doc(self: PyModuleDef, doc: []const u8) PyModuleDef {
        var copy = self;
        copy.doc = doc;
        return copy;
    }
};

/// Method definition
pub const PyMethodDef = struct {
    name: []const u8,
    flags: MethodFlags = .{},
    doc: ?[]const u8 = null,
};

/// Method flags
pub const MethodFlags = packed struct {
    varargs: bool = false,
    keywords: bool = false,
    noargs: bool = false,
    o: bool = false,
    class_method: bool = false,
    static_method: bool = false,
    _padding: u2 = 0,
};

/// Module slot definition
pub const PyModuleDef_Slot = struct {
    slot: SlotType,
    value: ?*anyopaque = null,

    pub const SlotType = enum(i32) {
        Py_mod_create = 1,
        Py_mod_exec = 2,
        Py_mod_multiple_interpreters = 3,
        Py_mod_gil = 4,
    };
};

/// Module state structure
pub const ModuleState = struct {
    initialized: bool = false,
    ref_count: usize = 0,
    data: ?*anyopaque = null,

    pub fn init() ModuleState {
        return .{ .initialized = true, .ref_count = 1 };
    }

    pub fn incref(self: *ModuleState) void {
        self.ref_count += 1;
    }

    pub fn decref(self: *ModuleState) bool {
        if (self.ref_count > 0) {
            self.ref_count -= 1;
            return self.ref_count == 0;
        }
        return true;
    }
};

/// Create a new module
pub fn PyModule_Create(def: *const PyModuleDef) !*Module {
    const allocator = std.heap.page_allocator;
    const module = try allocator.create(Module);
    module.* = Module.init(def);
    return module;
}

/// Module structure
pub const Module = struct {
    def: *const PyModuleDef,
    state: ModuleState,
    dict: std.StringHashMap([]const u8),

    pub fn init(def: *const PyModuleDef) Module {
        return .{
            .def = def,
            .state = ModuleState.init(),
            .dict = std.StringHashMap([]const u8).init(std.heap.page_allocator),
        };
    }

    pub fn deinit(self: *Module) void {
        self.dict.deinit();
    }

    pub fn get_name(self: *Module) []const u8 {
        return self.def.name;
    }

    pub fn set_attr(self: *Module, key: []const u8, value: []const u8) !void {
        try self.dict.put(key, value);
    }

    pub fn get_attr(self: *Module, key: []const u8) ?[]const u8 {
        return self.dict.get(key);
    }
};

/// Add an integer constant to module
pub fn PyModule_AddIntConstant(module: *Module, name: []const u8, value: i64) !void {
    var buf: [32]u8 = undefined;
    const str = std.fmt.bufPrint(&buf, "{}", .{value}) catch return error.FormatError;
    try module.set_attr(name, str);
}

/// Add a string constant to module
pub fn PyModule_AddStringConstant(module: *Module, name: []const u8, value: []const u8) !void {
    try module.set_attr(name, value);
}

test "PyModuleDef creation" {
    const def = PyModuleDef.init("test_module").with_doc("Test module documentation");
    try std.testing.expectEqualStrings("test_module", def.name);
    try std.testing.expectEqualStrings("Test module documentation", def.doc.?);
}

test "Module creation" {
    const def = PyModuleDef.init("mymodule");
    const module = try PyModule_Create(&def);
    defer module.deinit();

    try std.testing.expectEqualStrings("mymodule", module.get_name());
    try std.testing.expect(module.state.initialized);
}

test "Module attributes" {
    const def = PyModuleDef.init("attrmodule");
    const module = try PyModule_Create(&def);
    defer module.deinit();

    try module.set_attr("version", "1.0.0");
    try std.testing.expectEqualStrings("1.0.0", module.get_attr("version").?);
    try std.testing.expect(module.get_attr("nonexistent") == null);
}

test "ModuleState reference counting" {
    var state = ModuleState.init();
    try std.testing.expectEqual(@as(usize, 1), state.ref_count);

    state.incref();
    try std.testing.expectEqual(@as(usize, 2), state.ref_count);

    try std.testing.expect(!state.decref());
    try std.testing.expectEqual(@as(usize, 1), state.ref_count);

    try std.testing.expect(state.decref());
}

test "MethodFlags" {
    const flags = MethodFlags{ .varargs = true, .keywords = true };
    try std.testing.expect(flags.varargs);
    try std.testing.expect(flags.keywords);
    try std.testing.expect(!flags.noargs);
}
