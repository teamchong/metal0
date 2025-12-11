/// module_def - Module Definition Structures
/// Mirrors parts of cpython/Python/modsupport.c related to module definitions
///
/// Defines the structures used for module initialization, including ModuleDef,
/// MethodDef, and ModuleSlot. These are used for both single-phase and multi-phase
/// module initialization.

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");

/// Module definition for extension modules
pub const ModuleDef = struct {
    name: []const u8,
    doc: ?[]const u8,
    size: isize, // -1 for single-phase init
    methods: ?[]const MethodDef,
    slots: ?[]const ModuleSlot,
    traverse: ?*const fn (*anyopaque, *anyopaque) callconv(.C) c_int,
    clear: ?*const fn (*anyopaque) callconv(.C) c_int,
    free: ?*const fn (*anyopaque) callconv(.C) void,
};

/// Method definition
pub const MethodDef = struct {
    name: []const u8,
    func: *const anyopaque,
    flags: MethodFlags,
    doc: ?[]const u8,

    pub const MethodFlags = packed struct {
        varargs: bool = false,
        keywords: bool = false,
        noargs: bool = false,
        o: bool = false, // single object argument
        class: bool = false,
        static: bool = false,
        coexist: bool = false,
        fastcall: bool = false,
        _padding: u8 = 0,
    };

    pub const METH_VARARGS: u16 = 0x0001;
    pub const METH_KEYWORDS: u16 = 0x0002;
    pub const METH_NOARGS: u16 = 0x0004;
    pub const METH_O: u16 = 0x0008;
    pub const METH_CLASS: u16 = 0x0010;
    pub const METH_STATIC: u16 = 0x0020;
    pub const METH_COEXIST: u16 = 0x0040;
    pub const METH_FASTCALL: u16 = 0x0080;
};

/// Module slot for multi-phase initialization
pub const ModuleSlot = struct {
    slot: SlotId,
    value: *anyopaque,

    pub const SlotId = enum(c_int) {
        Py_mod_create = 1,
        Py_mod_exec = 2,
        Py_mod_multiple_interpreters = 3,
        Py_mod_gil = 4,
    };
};

/// Module state for extension modules
pub const ModuleState = struct {
    module: ?*anyopaque,
    dict: ?*anyopaque,
    name: []const u8,
    doc: ?[]const u8,
    def: ?*const ModuleDef,
    state: ?*anyopaque,
    weaklist: ?*anyopaque,
    index: isize,
};

/// Module object for AOT compatibility
pub const ModuleObject = struct {
    name: []const u8,
    doc: ?[]const u8,
    methods: ?*const MethodDef,
    state: ?*anyopaque,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ModuleObject) void {
        _ = self;
        // Module cleanup if needed
    }
};

/// GIL state for module operations
pub const GILState = enum {
    locked,
    unlocked,
};

/// Ensure GIL is held for module operations
pub fn ensureGIL() GILState {
    return .locked;
}

/// Release GIL
pub fn releaseGIL(state: GILState) void {
    _ = state;
}

/// Module initialization guard
pub const InitGuard = struct {
    initialized: bool = false,
    module: ?*anyopaque = null,

    pub fn acquire(self: *InitGuard) bool {
        if (self.initialized) return false;
        self.initialized = true;
        return true;
    }

    pub fn release(self: *InitGuard) void {
        self.initialized = false;
        self.module = null;
    }
};

/// Create a new module from definition
/// In AOT compilation, modules are statically defined at compile time.
/// This function returns a module placeholder that can be used for compatibility.
pub fn moduleCreate(def: *const ModuleDef) !*ModuleObject {
    // Use page allocator for module objects (long-lived)
    const allocator = allocator_helper.fast_allocator;
    const module = try allocator.create(ModuleObject);
    module.* = .{
        .name = def.name,
        .doc = def.doc,
        .methods = def.methods,
        .state = null,
        .allocator = allocator,
    };
    return module;
}

// Tests
test "method flags" {
    const flags = MethodDef.MethodFlags{
        .varargs = true,
        .keywords = true,
    };
    try std.testing.expect(flags.varargs);
    try std.testing.expect(flags.keywords);
    try std.testing.expect(!flags.noargs);
}
