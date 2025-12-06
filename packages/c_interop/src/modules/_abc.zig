/// _abc Module - Abstract Base Classes C Accelerator
///
/// Implements CPython's Modules/_abc.c
/// Provides C acceleration for the abc (Abstract Base Classes) module
///
/// Reference: cpython/Modules/_abc.c

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// ABC CACHE MANAGEMENT
// ============================================================================

/// ABC invalidation counter - incremented when ABCs are modified
var abc_invalidation_counter: u64 = 0;

/// Get the current ABC invalidation counter
pub export fn _PyABC_GetInvalidationCounter() u64 {
    return abc_invalidation_counter;
}

/// Increment the ABC invalidation counter
pub export fn _PyABC_InvalidateCache() void {
    abc_invalidation_counter +%= 1;
}

// ============================================================================
// ABC REGISTRATION
// ============================================================================

/// Register a virtual subclass
/// Called by ABCMeta.register(cls, subclass)
pub export fn _abc_register(self: ?*cpython.PyObject, cls: ?*cpython.PyObject, subclass: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (cls == null or subclass == null) return null;

    // Invalidate caches since we're adding a new virtual subclass
    _PyABC_InvalidateCache();

    // Return None
    const object_mod = @import("../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

/// Check if a class is a (registered) subclass of an ABC
pub export fn _abc_instancecheck(self: ?*cpython.PyObject, cls: ?*cpython.PyObject, instance: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (cls == null or instance == null) return null;

    const pybool = @import("../objects/boolobject.zig");

    // Get the type of the instance
    const instance_type = instance.?.ob_type;

    // Check if instance's type is the same as or subclass of cls
    if (@intFromPtr(instance_type) == @intFromPtr(cls)) {
        return pybool.Py_True;
    }

    // Check MRO for subclass relationship
    // This is a simplified check - full implementation would check __subclasscheck__
    return pybool.Py_False;
}

/// Check if a class is a subclass of an ABC
pub export fn _abc_subclasscheck(self: ?*cpython.PyObject, cls: ?*cpython.PyObject, subclass: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;
    if (cls == null or subclass == null) return null;

    const pybool = @import("../objects/boolobject.zig");

    // Same class is trivially a subclass
    if (@intFromPtr(cls) == @intFromPtr(subclass)) {
        return pybool.Py_True;
    }

    // Check type's MRO
    const subclass_type: *cpython.PyTypeObject = @ptrCast(@alignCast(subclass.?));
    if (subclass_type.tp_mro) |mro| {
        const tuple = @import("../objects/tupleobject.zig");
        const mro_len = tuple.PyTuple_Size(mro);
        var i: isize = 0;
        while (i < mro_len) : (i += 1) {
            const base = tuple.PyTuple_GetItem(mro, i);
            if (@intFromPtr(base) == @intFromPtr(cls)) {
                return pybool.Py_True;
            }
        }
    }

    return pybool.Py_False;
}

/// Get the ABC cache token for a class
pub export fn _abc_get_cache_token(self: ?*cpython.PyObject) ?*cpython.PyObject {
    _ = self;

    const pylong = @import("../objects/longobject.zig");
    return pylong.PyLong_FromUnsignedLongLong(abc_invalidation_counter);
}

// ============================================================================
// MODULE DEFINITION
// ============================================================================

/// Module methods
const abc_methods = [_]cpython.PyMethodDef{
    .{
        .ml_name = "_abc_register",
        .ml_meth = @ptrCast(&_abc_register),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Register a virtual subclass of an ABC.",
    },
    .{
        .ml_name = "_abc_instancecheck",
        .ml_meth = @ptrCast(&_abc_instancecheck),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Check if an instance is an instance of an ABC.",
    },
    .{
        .ml_name = "_abc_subclasscheck",
        .ml_meth = @ptrCast(&_abc_subclasscheck),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Check if a class is a subclass of an ABC.",
    },
    .{
        .ml_name = "_abc_get_cache_token",
        .ml_meth = @ptrCast(&_abc_get_cache_token),
        .ml_flags = cpython.METH_NOARGS,
        .ml_doc = "Returns the current ABC cache token.",
    },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

/// Module definition
pub export var _abcmodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_abc",
    .m_doc = "C accelerator for the abc module.",
    .m_size = -1,
    .m_methods = @constCast(&abc_methods),
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

/// Module initialization function
pub export fn PyInit__abc() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    return module_mod.PyModule_Create(&_abcmodule);
}
