/// Call Protocol Implementation
///
/// Implements CPython's Objects/call.c
/// Provides function call machinery for Python objects
///
/// Reference: cpython/Objects/call.c

const std = @import("std");
const cpython = @import("../include/object.zig");

pub const PyObject = cpython.PyObject;
pub const PyTypeObject = cpython.PyTypeObject;

// ============================================================================
// VECTORCALL PROTOCOL (PEP 590)
// ============================================================================

/// Vectorcall function signature
pub const vectorcallfunc = *const fn (
    callable: ?*PyObject,
    args: [*]const ?*PyObject,
    nargsf: usize,
    kwnames: ?*PyObject,
) ?*PyObject;

/// Flag indicating keyword arguments follow positional arguments
pub const PY_VECTORCALL_ARGUMENTS_OFFSET: usize = 1 << (8 * @sizeOf(usize) - 1);

/// Get number of positional arguments from nargsf
pub inline fn PyVectorcall_NARGS(nargsf: usize) usize {
    return nargsf & ~PY_VECTORCALL_ARGUMENTS_OFFSET;
}

/// Check if object supports vectorcall
pub fn PyVectorcall_Check(callable: ?*PyObject) bool {
    if (callable == null) return false;
    const tp = callable.?.ob_type orelse return false;
    return (tp.tp_flags & cpython.Py_TPFLAGS_HAVE_VECTORCALL) != 0;
}

/// Get vectorcall function from object
pub fn PyVectorcall_Function(callable: ?*PyObject) ?vectorcallfunc {
    if (!PyVectorcall_Check(callable)) return null;
    const tp = callable.?.ob_type orelse return null;
    const offset = tp.tp_vectorcall_offset;
    if (offset <= 0) return null;

    // Read function pointer at offset
    const ptr = @as([*]const u8, @ptrCast(callable.?)) + @as(usize, @intCast(offset));
    return @as(*const ?vectorcallfunc, @ptrCast(@alignCast(ptr))).*;
}

/// Call using vectorcall protocol
pub fn PyVectorcall_Call(callable: ?*PyObject, args: ?*PyObject, kwargs: ?*PyObject) ?*PyObject {
    _ = callable;
    _ = args;
    _ = kwargs;
    // TODO: Implement vectorcall
    return null;
}

// ============================================================================
// GENERAL CALL API
// ============================================================================

/// PyObject_Call - Call callable with args tuple and kwargs dict
pub export fn PyObject_Call(callable: ?*PyObject, args: ?*PyObject, kwargs: ?*PyObject) ?*PyObject {
    if (callable == null) return null;

    // Try vectorcall first (fast path)
    if (PyVectorcall_Check(callable)) {
        return PyVectorcall_Call(callable, args, kwargs);
    }

    // Fall back to tp_call
    const tp = callable.?.ob_type orelse return null;
    const call_fn = tp.tp_call orelse return null;
    return call_fn(callable, args, kwargs);
}

/// PyObject_CallObject - Call with args tuple only
pub export fn PyObject_CallObject(callable: ?*PyObject, args: ?*PyObject) ?*PyObject {
    return PyObject_Call(callable, args, null);
}

/// PyObject_CallNoArgs - Call with no arguments
pub export fn PyObject_CallNoArgs(callable: ?*PyObject) ?*PyObject {
    if (callable == null) return null;

    // Try vectorcall (fastest path)
    if (PyVectorcall_Function(callable)) |func| {
        return func(callable, @as([*]const ?*PyObject, undefined), 0, null);
    }

    // Fall back to regular call with empty tuple
    return PyObject_Call(callable, null, null);
}

/// PyObject_CallOneArg - Call with single argument
pub export fn PyObject_CallOneArg(callable: ?*PyObject, arg: ?*PyObject) ?*PyObject {
    if (callable == null) return null;

    // Try vectorcall
    if (PyVectorcall_Function(callable)) |func| {
        var args = [_]?*PyObject{arg};
        return func(callable, &args, 1 | PY_VECTORCALL_ARGUMENTS_OFFSET, null);
    }

    // Fall back to regular call
    return PyObject_Call(callable, null, null);
}

/// _PyObject_CallMethod - Call method by name
pub fn _PyObject_CallMethod(obj: ?*PyObject, name: [*:0]const u8, format: ?[*:0]const u8, args: anytype) ?*PyObject {
    _ = obj;
    _ = name;
    _ = format;
    _ = args;
    // TODO: Implement method call
    return null;
}

// ============================================================================
// FUNCTION CALL HELPERS
// ============================================================================

/// _PyObject_MakeTpCall - Make call via tp_call slot
pub fn _PyObject_MakeTpCall(tstate: ?*anyopaque, callable: ?*PyObject, args: [*]const ?*PyObject, nargs: usize, kwargs: ?*PyObject) ?*PyObject {
    _ = tstate;
    _ = callable;
    _ = args;
    _ = nargs;
    _ = kwargs;
    return null;
}

/// PyObject_CallFunctionObjArgs - Call with varargs PyObject* (NULL-terminated)
pub export fn PyObject_CallFunctionObjArgs(callable: ?*PyObject, ...) ?*PyObject {
    _ = callable;
    // TODO: Implement varargs call
    return null;
}

/// PyObject_CallMethodObjArgs - Call method with varargs PyObject* (NULL-terminated)
pub export fn PyObject_CallMethodObjArgs(obj: ?*PyObject, name: ?*PyObject, ...) ?*PyObject {
    _ = obj;
    _ = name;
    // TODO: Implement method varargs call
    return null;
}

// ============================================================================
// TYPE CHECKING
// ============================================================================

/// Check if object is callable
pub export fn PyCallable_Check(obj: ?*PyObject) c_int {
    if (obj == null) return 0;
    const tp = obj.?.ob_type orelse return 0;
    return if (tp.tp_call != null) 1 else 0;
}
