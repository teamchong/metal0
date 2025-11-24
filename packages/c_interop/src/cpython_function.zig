/// CPython Function Objects
///
/// Implements PyCFunction_* for creating callable C function objects.

const std = @import("std");
const cpython = @import("cpython_object.zig");
const cpython_module = @import("cpython_module.zig");

const allocator = std.heap.c_allocator;

/// ============================================================================
/// FUNCTION TYPE OBJECTS
/// ============================================================================

/// PyCFunctionObject - C function wrapper
pub const PyCFunctionObject = extern struct {
    ob_base: cpython.PyObject,
    m_ml: *const cpython_module.PyMethodDef,
    m_self: ?*cpython.PyObject,
    m_module: ?*cpython.PyObject,
    m_weakreflist: ?*cpython.PyObject,
};

/// Dummy function type
var PyCFunction_Type: cpython.PyTypeObject = undefined;
var function_type_initialized = false;

fn initFunctionType() void {
    if (function_type_initialized) return;

    PyCFunction_Type = .{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = &PyCFunction_Type,
            },
            .ob_size = 0,
        },
        .tp_name = "builtin_function_or_method",
        .tp_basicsize = @sizeOf(PyCFunctionObject),
        .tp_itemsize = 0,
        .tp_dealloc = null,
        .tp_repr = null,
        .tp_hash = null,
        .tp_call = null,
        .tp_str = null,
        .tp_getattro = null,
        .tp_setattro = null,
    };

    function_type_initialized = true;
}

/// ============================================================================
/// FUNCTION CREATION
/// ============================================================================

/// Create new C function object
///
/// CPython: PyObject* PyCFunction_NewEx(PyMethodDef *ml, PyObject *self, PyObject *module)
export fn PyCFunction_NewEx(
    ml: *const cpython_module.PyMethodDef,
    self: ?*cpython.PyObject,
    module: ?*cpython.PyObject,
) callconv(.c) ?*cpython.PyObject {
    initFunctionType();

    const func = allocator.create(PyCFunctionObject) catch return null;

    func.ob_base = .{
        .ob_refcnt = 1,
        .ob_type = &PyCFunction_Type,
    };

    func.m_ml = ml;
    func.m_self = self;
    func.m_module = module;
    func.m_weakreflist = null;

    // Increment refs for self and module
    if (self) |s| Py_INCREF(s);
    if (module) |m| Py_INCREF(m);

    return @ptrCast(&func.ob_base);
}

/// Create new C function object (legacy API)
///
/// CPython: PyObject* PyCFunction_New(PyMethodDef *ml, PyObject *self)
export fn PyCFunction_New(
    ml: *const cpython_module.PyMethodDef,
    self: ?*cpython.PyObject,
) callconv(.c) ?*cpython.PyObject {
    return PyCFunction_NewEx(ml, self, null);
}

/// Get function from function object
///
/// CPython: PyCFunction PyCFunction_GetFunction(PyObject *op)
export fn PyCFunction_GetFunction(op: *cpython.PyObject) callconv(.c) ?cpython_module.PyCFunction {
    const func = @as(*PyCFunctionObject, @ptrCast(op));
    return func.m_ml.ml_meth;
}

/// Get self from function object
///
/// CPython: PyObject* PyCFunction_GetSelf(PyObject *op)
export fn PyCFunction_GetSelf(op: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const func = @as(*PyCFunctionObject, @ptrCast(op));
    return func.m_self;
}

/// Get flags from function object
///
/// CPython: int PyCFunction_GetFlags(PyObject *op)
export fn PyCFunction_GetFlags(op: *cpython.PyObject) callconv(.c) c_int {
    const func = @as(*PyCFunctionObject, @ptrCast(op));
    return func.m_ml.ml_flags;
}

/// ============================================================================
/// HELPER FUNCTIONS
/// ============================================================================

extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;

/// ============================================================================
/// TESTS
/// ============================================================================

test "PyCFunctionObject layout" {
    try std.testing.expect(@sizeOf(PyCFunctionObject) > 0);
}
