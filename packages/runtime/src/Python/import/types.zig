/// import types - Module definition types
const std = @import("std");

/// Module definition structure (mirrors PyModuleDef)
pub const ModuleDef = struct {
    name: []const u8,
    doc: ?[]const u8 = null,
    size: i64 = -1,
    methods: ?[]const MethodDef = null,
    slots: ?[]const ModuleDefSlot = null,
    traverse: ?TraverseFunc = null,
    clear: ?ClearFunc = null,
    free: ?FreeFunc = null,
    base: ModuleDefBase = .{},
};

/// Module definition base (internal bookkeeping)
pub const ModuleDefBase = struct {
    m_index: i64 = 0,
    m_init: ?InitFunc = null,
    m_copy: ?*anyopaque = null,
};

/// Method definition
pub const MethodDef = struct {
    name: []const u8,
    func: *const fn (?*anyopaque, ?*anyopaque) ?*anyopaque,
    flags: i32 = 0,
    doc: ?[]const u8 = null,
};

/// Module slot types
pub const ModuleDefSlotId = enum(i32) {
    Py_mod_create = 1,
    Py_mod_exec = 2,
    Py_mod_multiple_interpreters = 3,
    Py_mod_gil = 4,
};

/// Module definition slot
pub const ModuleDefSlot = struct {
    slot: ModuleDefSlotId,
    value: ?*anyopaque,
};

/// Function types
pub const InitFunc = *const fn () ?*anyopaque;
pub const TraverseFunc = *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque) i32;
pub const ClearFunc = *const fn (?*anyopaque) i32;
pub const FreeFunc = *const fn (?*anyopaque) void;

/// Built-in module entry
pub const InittabEntry = struct {
    name: []const u8,
    init: InitFunc,
};

/// Frozen module entry
pub const FrozenModule = struct {
    name: []const u8,
    code: []const u8,
    size: usize,
    is_package: bool = false,
    get_code: ?*const fn () []const u8 = null,
};

/// Import error types
pub const ImportError = error{
    ModuleNotFound,
    CircularImport,
    ImportLockFailed,
    InvalidModule,
    NoMemory,
};
