const std = @import("std");

/// Python C API bindings
const c = @cImport({
    @cInclude("Python.h");
});

/// Initialize Python interpreter
pub fn initialize() !void {
    // Try to get Python home from environment or use system Python
    const python_home = std.process.getEnvVarOwned(std.heap.c_allocator, "VIRTUAL_ENV") catch null;

    if (python_home) |home| {
        defer std.heap.c_allocator.free(home);
        const home_wide = try std.heap.c_allocator.dupeZ(u8, home);
        defer std.heap.c_allocator.free(home_wide);

        // Note: Py_SetPythonHome needs wchar_t*, skipping for now
        // c.Py_SetPythonHome(@ptrCast(home_wide.ptr));
    }

    // Use Py_InitializeEx(0) to skip signal handler registration
    c.Py_InitializeEx(0);
    if (c.Py_IsInitialized() == 0) {
        return error.PythonInitFailed;
    }
}

/// Finalize Python interpreter
pub fn finalize() void {
    c.Py_Finalize();
}

/// Import a Python module
/// Returns an opaque pointer to PyObject
pub fn importModule(allocator: std.mem.Allocator, module_name: []const u8) !*anyopaque {
    // Convert to null-terminated string
    const name_z = try allocator.dupeZ(u8, module_name);
    defer allocator.free(name_z);

    const module = c.PyImport_ImportModule(name_z.ptr);
    if (module == null) {
        c.PyErr_Print();
        return error.ImportFailed;
    }

    return @ptrCast(module);
}

/// Import specific name from a module
/// from module_name import item_name
pub fn importFrom(allocator: std.mem.Allocator, module_name: []const u8, item_name: []const u8) !*anyopaque {
    const module = try importModule(allocator, module_name);

    const item_z = try allocator.dupeZ(u8, item_name);
    defer allocator.free(item_z);

    const item = c.PyObject_GetAttrString(@ptrCast(module), item_z.ptr);
    if (item == null) {
        c.PyErr_Print();
        return error.AttributeNotFound;
    }

    return @ptrCast(item);
}

/// Call a Python function with arguments
pub fn callFunction(func: *anyopaque, args: []const *anyopaque) !*anyopaque {
    // Build tuple of arguments
    const py_args = c.PyTuple_New(@intCast(args.len));
    if (py_args == null) return error.OutOfMemory;

    for (args, 0..) |arg, i| {
        _ = c.PyTuple_SetItem(py_args, @intCast(i), @ptrCast(arg));
    }

    // Call function
    const result = c.PyObject_CallObject(@ptrCast(func), py_args);
    c.Py_DecRef(py_args);

    if (result == null) {
        c.PyErr_Print();
        return error.CallFailed;
    }

    return @ptrCast(result);
}

/// Convert Zig int to Python int
pub fn fromInt(value: i64) !*anyopaque {
    const py_int = c.PyLong_FromLongLong(value);
    if (py_int == null) return error.ConversionFailed;
    return @ptrCast(py_int);
}

/// Convert Zig float to Python float
pub fn fromFloat(value: f64) !*anyopaque {
    const py_float = c.PyFloat_FromDouble(value);
    if (py_float == null) return error.ConversionFailed;
    return @ptrCast(py_float);
}

/// Convert Zig string to Python string
pub fn fromString(allocator: std.mem.Allocator, value: []const u8) !*anyopaque {
    const value_z = try allocator.dupeZ(u8, value);
    defer allocator.free(value_z);

    const py_str = c.PyUnicode_FromString(value_z.ptr);
    if (py_str == null) return error.ConversionFailed;
    return @ptrCast(py_str);
}

/// Convert Python int to Zig int
pub fn toInt(py_obj: *anyopaque) !i64 {
    const value = c.PyLong_AsLongLong(@ptrCast(py_obj));
    if (value == -1 and c.PyErr_Occurred() != null) {
        c.PyErr_Print();
        return error.ConversionFailed;
    }
    return value;
}

/// Convert Python float to Zig float
pub fn toFloat(py_obj: *anyopaque) !f64 {
    const value = c.PyFloat_AsDouble(@ptrCast(py_obj));
    if (value == -1.0 and c.PyErr_Occurred() != null) {
        c.PyErr_Print();
        return error.ConversionFailed;
    }
    return value;
}

/// Decrease reference count
pub fn decref(py_obj: *anyopaque) void {
    c.Py_DecRef(@ptrCast(py_obj));
}

/// Increase reference count
pub fn incref(py_obj: *anyopaque) void {
    c.Py_IncRef(@ptrCast(py_obj));
}
