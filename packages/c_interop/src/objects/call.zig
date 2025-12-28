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
    if (callable == null) return null;

    const func = PyVectorcall_Function(callable) orelse return null;

    const tuple = @import("tupleobject.zig");

    // Get args count
    var nargs: usize = 0;
    if (args) |a| {
        if (tuple.PyTuple_Check(a) != 0) {
            nargs = @intCast(tuple.PyTuple_Size(a));
        }
    }

    // Build args array from tuple
    if (nargs == 0) {
        return func(callable, @as([*]const ?*PyObject, undefined), 0, kwargs);
    }

    // Stack-allocate for small arg counts
    var stack_args: [8]?*PyObject = undefined;
    var args_ptr: [*]?*PyObject = undefined;

    if (nargs <= 8) {
        args_ptr = &stack_args;
    } else {
        // Need heap allocation for large arg counts
        const heap_args = std.heap.c_allocator.alloc(?*PyObject, nargs) catch return null;
        args_ptr = heap_args.ptr;
    }

    // Copy args from tuple
    for (0..nargs) |i| {
        args_ptr[i] = tuple.PyTuple_GetItem(args.?, @intCast(i));
    }

    const result = func(callable, args_ptr, nargs, kwargs);

    // Free heap allocation if used
    if (nargs > 8) {
        std.heap.c_allocator.free(args_ptr[0..nargs]);
    }

    return result;
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
    _ = format;
    _ = args;

    if (obj == null) return null;

    const pyunicode = @import("unicodeobject.zig");

    // Get the method attribute
    const name_obj = pyunicode.PyUnicode_FromString(name);
    if (name_obj == null) return null;
    defer name_obj.?.ob_refcnt -= 1;

    var method: ?*PyObject = null;
    if (obj.?.ob_type.tp_getattro) |getattr_fn| {
        method = getattr_fn(obj.?, name_obj.?);
    }

    if (method == null) return null;
    defer method.?.ob_refcnt -= 1;

    // Call the method with no args (format parsing not implemented)
    return PyObject_CallNoArgs(method);
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
/// Note: Varargs in Zig require special handling. This version takes up to 8 args.
pub export fn PyObject_CallFunctionObjArgs(callable: ?*PyObject, arg0: ?*PyObject, arg1: ?*PyObject, arg2: ?*PyObject, arg3: ?*PyObject, arg4: ?*PyObject, arg5: ?*PyObject, arg6: ?*PyObject, arg7: ?*PyObject) ?*PyObject {
    if (callable == null) return null;

    // Build args array from non-null args (NULL-terminated)
    var args: [8]?*PyObject = undefined;
    var nargs: usize = 0;

    const arg_list = [_]?*PyObject{ arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7 };

    for (arg_list) |arg| {
        if (arg == null) break;
        args[nargs] = arg;
        nargs += 1;
    }

    // Try vectorcall
    if (PyVectorcall_Function(callable)) |func| {
        return func(callable, &args, nargs, null);
    }

    // Fall back to building tuple and calling
    const tuple = @import("tupleobject.zig");
    const args_tuple = tuple.PyTuple_New(@intCast(nargs));
    if (args_tuple == null) return null;

    for (0..nargs) |i| {
        if (args[i]) |a| {
            a.ob_refcnt += 1;
            _ = tuple.PyTuple_SetItem(args_tuple.?, @intCast(i), a);
        }
    }

    const result = PyObject_Call(callable, args_tuple, null);
    args_tuple.?.ob_refcnt -= 1;
    return result;
}

/// PyObject_CallMethodObjArgs - Call method with varargs PyObject* (NULL-terminated)
pub export fn PyObject_CallMethodObjArgs(obj: ?*PyObject, name: ?*PyObject, arg0: ?*PyObject, arg1: ?*PyObject, arg2: ?*PyObject, arg3: ?*PyObject, arg4: ?*PyObject, arg5: ?*PyObject, arg6: ?*PyObject) ?*PyObject {
    if (obj == null or name == null) return null;

    // Get the method
    var method: ?*PyObject = null;
    if (obj.?.ob_type.tp_getattro) |getattr_fn| {
        method = getattr_fn(obj.?, name.?);
    }

    if (method == null) return null;
    defer method.?.ob_refcnt -= 1;

    // Call with remaining args
    return PyObject_CallFunctionObjArgs(method, arg0, arg1, arg2, arg3, arg4, arg5, arg6, null);
}

// ============================================================================
// TYPE CHECKING
// ============================================================================

/// Check if object is callable
/// Note: Use objects/object.zig for the exported version (has more complete __call__ check)
fn PyCallable_Check_internal(obj: ?*PyObject) c_int {
    if (obj == null) return 0;
    const tp = obj.?.ob_type orelse return 0;
    return if (tp.tp_call != null) 1 else 0;
}
