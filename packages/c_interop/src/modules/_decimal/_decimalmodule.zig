/// _decimal Module - Arbitrary Precision Decimal Arithmetic
///
/// Implements CPython's Modules/_decimal/_decimal.c
/// Provides decimal.Decimal class for financial calculations
///
/// Reference: cpython/Modules/_decimal/_decimal.c
const std = @import("std");
const cpython = @import("../../include/object.zig");

const allocator = std.heap.c_allocator;

// Re-export submodule types
pub const mpdecimal = @import("mpdecimal.zig");
pub const decimal = @import("decimal.zig");
pub const context = @import("context.zig");

// Re-export key types
pub const mpd_t = mpdecimal.mpd_t;
pub const mpd_context_t = mpdecimal.mpd_context_t;
pub const PyDecObject = decimal.PyDecObject;
pub const PyDecContextObject = decimal.PyDecContextObject;
pub const PyDecSignalDictObject = decimal.PyDecSignalDictObject;
pub const PyDecContextManagerObject = decimal.PyDecContextManagerObject;

// ============================================================================
// MODULE FUNCTIONS
// ============================================================================

/// getcontext - Get current thread's context
fn decimal_getcontext(self: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    // Get context from thread-local storage
    // For now, return default context
    return context.Context_new(null, null, null);
}

/// setcontext - Set current thread's context
fn decimal_setcontext(self: ?*cpython.PyObject, ctx: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = ctx;
    // Set context in thread-local storage
    const object_mod = @import("../../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

/// localcontext - Context manager for temporary context
fn decimal_localcontext(self: ?*cpython.PyObject, args: ?*cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = self;
    _ = args;
    _ = kwargs;
    // Create context manager
    return null;
}

// ============================================================================
// METHOD TABLE
// ============================================================================

pub export var decimal_methods: [4]cpython.PyMethodDef = .{
    .{ .ml_name = "getcontext", .ml_meth = @ptrCast(&decimal_getcontext), .ml_flags = 0x0004, .ml_doc = "Get the current default context." },
    .{ .ml_name = "setcontext", .ml_meth = @ptrCast(&decimal_setcontext), .ml_flags = 0x0008, .ml_doc = "Set the current default context." },
    .{ .ml_name = "localcontext", .ml_meth = @ptrCast(&decimal_localcontext), .ml_flags = 0x0003, .ml_doc = "Return a context manager for a temporary context." },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

// ============================================================================
// MODULE DEFINITION
// ============================================================================

pub export var _decimal_module: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_decimal",
    .m_doc = "C implementation of the decimal module.",
    .m_size = @sizeOf(decimal.decimal_state),
    .m_methods = &decimal_methods,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

/// Module initialization
pub export fn PyInit__decimal() callconv(.c) ?*cpython.PyObject {
    const module_mod = @import("../../objects/moduleobject.zig");
    const module = module_mod.PyModule_Create(&_decimal_module);
    if (module == null) return null;

    // Add type objects
    _ = module_mod.PyModule_AddObject(module, "Decimal", @ptrCast(&decimal.PyDec_Type));
    _ = module_mod.PyModule_AddObject(module, "Context", @ptrCast(&context.PyDecContext_Type));

    // Add rounding constants
    _ = module_mod.PyModule_AddIntConstant(module, "ROUND_UP", mpdecimal.MPD_ROUND_UP);
    _ = module_mod.PyModule_AddIntConstant(module, "ROUND_DOWN", mpdecimal.MPD_ROUND_DOWN);
    _ = module_mod.PyModule_AddIntConstant(module, "ROUND_CEILING", mpdecimal.MPD_ROUND_CEILING);
    _ = module_mod.PyModule_AddIntConstant(module, "ROUND_FLOOR", mpdecimal.MPD_ROUND_FLOOR);
    _ = module_mod.PyModule_AddIntConstant(module, "ROUND_HALF_UP", mpdecimal.MPD_ROUND_HALF_UP);
    _ = module_mod.PyModule_AddIntConstant(module, "ROUND_HALF_DOWN", mpdecimal.MPD_ROUND_HALF_DOWN);
    _ = module_mod.PyModule_AddIntConstant(module, "ROUND_HALF_EVEN", mpdecimal.MPD_ROUND_HALF_EVEN);
    _ = module_mod.PyModule_AddIntConstant(module, "ROUND_05UP", mpdecimal.MPD_ROUND_05UP);

    // Add limits
    _ = module_mod.PyModule_AddIntConstant(module, "MAX_PREC", @intCast(mpdecimal.MPD_MAX_PREC));
    _ = module_mod.PyModule_AddIntConstant(module, "MAX_EMAX", @intCast(mpdecimal.MPD_MAX_EMAX));
    _ = module_mod.PyModule_AddIntConstant(module, "MIN_EMIN", @intCast(mpdecimal.MPD_MIN_EMIN));

    // Set module state references
    decimal._decimal_state.PyDec_Type = &decimal.PyDec_Type;
    decimal._decimal_state.PyDecContext_Type = &context.PyDecContext_Type;

    return module;
}
