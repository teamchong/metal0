/// CPython Call Protocol
///
/// Implements the call protocol for invoking callable objects with various argument patterns.
/// NOTE: Core PyObject_Call and PyObject_CallObject are in cpython_object_protocol.zig

const std = @import("std");
const cpython = @import("cpython_object.zig");
const traits = @import("pyobject_traits.zig");
const obj_proto = @import("cpython_object_protocol.zig");

// Re-export core call functions from object protocol
pub const PyObject_Call = obj_proto.PyObject_Call;
pub const PyObject_CallObject = obj_proto.PyObject_CallObject;

/// Call with format string arguments
export fn PyObject_CallFunction(callable: *cpython.PyObject, format: ?[*:0]const u8, ...) callconv(.c) ?*cpython.PyObject {
    _ = format;
    // TODO: Parse format string and build args tuple
    return obj_proto.PyObject_Call(callable, @ptrFromInt(0), null);
}

/// Call method with format string
export fn PyObject_CallMethod(obj: *cpython.PyObject, name: [*:0]const u8, format: ?[*:0]const u8, ...) callconv(.c) ?*cpython.PyObject {
    _ = name;
    _ = format;
    _ = obj;
    // TODO: Get method from object, then call with args
    traits.setError("RuntimeError", "PyObject_CallMethod not fully implemented");
    return null;
}

/// Call with single argument
export fn PyObject_CallOneArg(callable: *cpython.PyObject, arg: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const pytuple = @import("pyobject_tuple.zig");

    // Create tuple with single arg
    const args_tuple = pytuple.PyTuple_New(1) orelse return null;
    _ = pytuple.PyTuple_SetItem(args_tuple, 0, traits.incref(arg)); // SetItem steals ref

    const result = obj_proto.PyObject_Call(callable, args_tuple, null);
    traits.decref(args_tuple);
    return result;
}

/// Call with no arguments
export fn PyObject_CallNoArgs(callable: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const pytuple = @import("pyobject_tuple.zig");

    // Create empty tuple for args
    const empty_args = pytuple.PyTuple_New(0) orelse return null;
    defer traits.decref(empty_args);

    return obj_proto.PyObject_Call(callable, empty_args, null);
}

// ============================================================================
// Vectorcall Protocol - Fast calling convention (PEP 590)
// ============================================================================

/// Flag indicating that the first argument is actually self (for methods)
pub const PY_VECTORCALL_ARGUMENTS_OFFSET: usize = 1 << (@bitSizeOf(usize) - 1);

/// Extract number of args from nargsf (mask out the offset flag)
export fn PyVectorcall_NARGS(nargsf: usize) callconv(.c) usize {
    return nargsf & ~PY_VECTORCALL_ARGUMENTS_OFFSET;
}

/// Call with positional args array (vectorcall protocol)
export fn PyObject_Vectorcall(callable: *cpython.PyObject, args: ?[*]const ?*cpython.PyObject, nargsf: usize, kwnames: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const nargs = PyVectorcall_NARGS(nargsf);

    // Check for vectorcall support on the type
    const tp = cpython.Py_TYPE(callable);
    if (tp.tp_vectorcall_offset != 0) {
        // Get vectorcall function pointer from callable object
        const base_ptr: [*]const u8 = @ptrCast(callable);
        const offset: usize = @intCast(tp.tp_vectorcall_offset);
        const vcall_ptr: *const cpython.vectorcallfunc = @ptrCast(@alignCast(base_ptr + offset));
        if (vcall_ptr.*) |vcall| {
            return vcall(callable, args orelse @ptrFromInt(0), nargs, kwnames);
        }
    }

    // Fallback: build tuple and dict from args
    const pytuple = @import("pyobject_tuple.zig");
    const pydict = @import("pyobject_dict.zig");

    // Build positional args tuple
    const args_tuple = pytuple.PyTuple_New(@intCast(nargs)) orelse return null;
    if (args) |a| {
        for (0..nargs) |i| {
            if (a[i]) |arg| {
                _ = pytuple.PyTuple_SetItem(args_tuple, @intCast(i), traits.incref(arg));
            }
        }
    }

    // Build kwargs dict if kwnames provided
    var kwargs: ?*cpython.PyObject = null;
    if (kwnames) |kw| {
        const nkw: usize = @intCast(pytuple.PyTuple_Size(kw));
        if (nkw > 0) {
            kwargs = pydict.PyDict_New();
            if (kwargs) |kd| {
                if (args) |a| {
                    for (0..nkw) |i| {
                        const key = pytuple.PyTuple_GetItem(kw, @intCast(i));
                        const val = a[nargs + i];
                        if (key != null and val != null) {
                            _ = pydict.PyDict_SetItem(kd, key.?, val.?);
                        }
                    }
                }
            }
        }
    }

    const result = obj_proto.PyObject_Call(callable, args_tuple, kwargs);
    traits.decref(args_tuple);
    if (kwargs) |kd| traits.decref(kd);
    return result;
}

/// Call using vectorcall with dict for kwargs
export fn PyObject_VectorcallDict(callable: *cpython.PyObject, args: ?[*]const ?*cpython.PyObject, nargsf: usize, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = nargsf;
    const pytuple = @import("pyobject_tuple.zig");

    // Simple fallback: build tuple from args
    const nargs = PyVectorcall_NARGS(nargsf);
    const args_tuple = pytuple.PyTuple_New(@intCast(nargs)) orelse return null;
    if (args) |a| {
        for (0..nargs) |i| {
            if (a[i]) |arg| {
                _ = pytuple.PyTuple_SetItem(args_tuple, @intCast(i), traits.incref(arg));
            }
        }
    }

    const result = obj_proto.PyObject_Call(callable, args_tuple, kwargs);
    traits.decref(args_tuple);
    return result;
}

/// Call method using vectorcall
export fn PyObject_VectorcallMethod(name: *cpython.PyObject, args: ?[*]const ?*cpython.PyObject, nargsf: usize, kwnames: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const nargs = PyVectorcall_NARGS(nargsf);
    if (nargs == 0 or args == null) {
        traits.setError("TypeError", "vectorcall method requires at least self argument");
        return null;
    }

    // First arg is self (with offset flag)
    const has_offset = (nargsf & PY_VECTORCALL_ARGUMENTS_OFFSET) != 0;
    const self_idx: usize = if (has_offset) 0 else 0;
    const self = args.?[self_idx] orelse {
        traits.setError("TypeError", "vectorcall method self is null");
        return null;
    };

    // Get method from self
    const misc = @import("cpython_misc.zig");
    const method = misc.PyObject_GetAttr(self, name) orelse return null;
    defer traits.decref(method);

    // Call method with remaining args (skip self)
    const method_args = if (nargs > 1) args.? + 1 else null;
    const method_nargs = if (nargs > 1) nargs - 1 else 0;

    return PyObject_Vectorcall(method, method_args, method_nargs, kwnames);
}

/// Get vectorcall function from callable (returns null if not supported)
export fn PyVectorcall_Function(callable: *cpython.PyObject) callconv(.c) cpython.vectorcallfunc {
    const tp = cpython.Py_TYPE(callable);
    if (tp.tp_vectorcall_offset == 0) return null;

    const base_ptr: [*]const u8 = @ptrCast(callable);
    const offset: usize = @intCast(tp.tp_vectorcall_offset);
    const vcall_ptr: *const cpython.vectorcallfunc = @ptrCast(@alignCast(base_ptr + offset));
    return vcall_ptr.*;
}

/// Call callable using vectorcall (entry point that checks for vectorcall support)
export fn PyVectorcall_Call(callable: *cpython.PyObject, args: *cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // This is a helper that converts tuple/dict args to vectorcall
    return obj_proto.PyObject_Call(callable, args, kwargs);
}

/// Call method (no args)
export fn PyObject_CallMethodNoArgs(obj: *cpython.PyObject, name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const misc = @import("cpython_misc.zig");

    // Get method from object
    const method = misc.PyObject_GetAttr(obj, name) orelse return null;
    defer traits.decref(method);

    // Call method with no args
    return PyObject_CallNoArgs(method);
}

/// Call method (one arg)
export fn PyObject_CallMethodOneArg(obj: *cpython.PyObject, name: *cpython.PyObject, arg: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const misc = @import("cpython_misc.zig");

    // Get method from object
    const method = misc.PyObject_GetAttr(obj, name) orelse return null;
    defer traits.decref(method);

    // Call method with one arg
    return PyObject_CallOneArg(method, arg);
}

/// Check if object is callable
export fn PyCallable_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (traits.isCallable(obj)) 1 else 0;
}

// Tests
test "call protocol exports" {
    _ = PyObject_Call;
    _ = PyObject_CallNoArgs;
    _ = PyCallable_Check;
}
