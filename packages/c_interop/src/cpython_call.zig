/// CPython Call Protocol
///
/// Implements the call protocol for invoking callable objects with various argument patterns.

const std = @import("std");
const cpython = @import("cpython_object.zig");

// External dependencies
extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;
extern fn PyErr_SetString(*cpython.PyObject, [*:0]const u8) callconv(.c) void;

/// Call callable with args and kwargs
export fn PyObject_CallObject(callable: *cpython.PyObject, args: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return PyObject_Call(callable, args orelse @ptrFromInt(0), null);
}

/// Call callable with args tuple
export fn PyObject_Call(callable: *cpython.PyObject, args: *cpython.PyObject, kwargs: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const type_obj = cpython.Py_TYPE(callable);
    
    if (type_obj.tp_call) |call_func| {
        return call_func(callable, args, kwargs);
    }
    
    PyErr_SetString(@ptrFromInt(0), "object is not callable");
    return null;
}

/// Call with format string arguments
export fn PyObject_CallFunction(callable: *cpython.PyObject, format: ?[*:0]const u8, ...) callconv(.c) ?*cpython.PyObject {
    _ = format;
    // TODO: Parse format string and build args tuple
    return PyObject_Call(callable, @ptrFromInt(0), null);
}

/// Call method with format string
export fn PyObject_CallMethod(obj: *cpython.PyObject, name: [*:0]const u8, format: ?[*:0]const u8, ...) callconv(.c) ?*cpython.PyObject {
    _ = name;
    _ = format;
    _ = obj;
    // TODO: Get method from object, then call with args
    PyErr_SetString(@ptrFromInt(0), "PyObject_CallMethod not fully implemented");
    return null;
}

/// Call with single argument
export fn PyObject_CallOneArg(callable: *cpython.PyObject, arg: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Create tuple with single arg
    // TODO: Use PyTuple_Pack when available
    _ = arg;
    return PyObject_Call(callable, @ptrFromInt(0), null);
}

/// Call with no arguments
export fn PyObject_CallNoArgs(callable: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    return PyObject_Call(callable, @ptrFromInt(0), null);
}

/// Call with positional args array
export fn PyObject_Vectorcall(callable: *cpython.PyObject, args: [*]const ?*cpython.PyObject, nargsf: usize, kwnames: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = nargsf;
    _ = kwnames;
    
    // Simplified: fall back to regular call
    return PyObject_Call(callable, @ptrFromInt(0), null);
}

/// Call method (no args)
export fn PyObject_CallMethodNoArgs(obj: *cpython.PyObject, name: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = obj;
    _ = name;
    
    PyErr_SetString(@ptrFromInt(0), "PyObject_CallMethodNoArgs stub");
    return null;
}

/// Call method (one arg)
export fn PyObject_CallMethodOneArg(obj: *cpython.PyObject, name: *cpython.PyObject, arg: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = obj;
    _ = name;
    _ = arg;
    
    PyErr_SetString(@ptrFromInt(0), "PyObject_CallMethodOneArg stub");
    return null;
}

/// Check if object is callable
export fn PyCallable_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    
    if (type_obj.tp_call != null) {
        return 1;
    }
    
    return 0;
}

// Tests
test "call protocol exports" {
    _ = PyObject_Call;
    _ = PyObject_CallNoArgs;
    _ = PyCallable_Check;
}
