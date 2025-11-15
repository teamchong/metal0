const std = @import("std");

/// Python C API bindings
const c = @cImport({
    @cInclude("Python.h");
    @cInclude("wchar.h");
});

/// Convert UTF-8 string to wchar_t* for Python
fn toWideString(allocator: std.mem.Allocator, str: []const u8) ![:0]c.wchar_t {
    // Null-terminate the input string
    const str_z = try allocator.dupeZ(u8, str);
    defer allocator.free(str_z);

    // Use mbstowcs to convert (requires locale setup)
    const len = c.mbstowcs(null, str_z.ptr, 0);
    if (len == @as(usize, @bitCast(@as(isize, -1)))) {
        return error.InvalidUtf8;
    }

    // Allocate wchar_t buffer (+1 for null terminator)
    const wstr = try allocator.allocSentinel(c.wchar_t, len, 0);
    _ = c.mbstowcs(wstr.ptr, str_z.ptr, len + 1);

    return wstr;
}

/// Find Python home directory
fn findPythonHome(allocator: std.mem.Allocator) !?[]const u8 {
    // Use sys.base_prefix to get the actual Python installation
    // (not the virtual environment, which lacks stdlib)
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "python3", "-c", "import sys; print(sys.base_prefix, end='')" },
    }) catch return null;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited == 0 and result.stdout.len > 0) {
        return try allocator.dupe(u8, result.stdout);
    }

    return null;
}

/// Initialize Python interpreter
pub fn initialize() !void {
    // Find Python installation (base_prefix for stdlib)
    const python_home = try findPythonHome(std.heap.c_allocator);
    defer if (python_home) |home| std.heap.c_allocator.free(home);

    var python_home_wide: ?[:0]c.wchar_t = null;
    defer if (python_home_wide) |w| std.heap.c_allocator.free(w);

    if (python_home) |home| {
        std.debug.print("Using Python home: {s}\n", .{home});
        python_home_wide = try toWideString(std.heap.c_allocator, home);
        c.Py_SetPythonHome(python_home_wide.?.ptr);
    }

    // Use Py_InitializeEx(0) to skip signal handler registration
    c.Py_InitializeEx(0);
    if (c.Py_IsInitialized() == 0) {
        return error.PythonInitFailed;
    }

    // Add venv site-packages to sys.path if VIRTUAL_ENV is set
    if (std.process.getEnvVarOwned(std.heap.c_allocator, "VIRTUAL_ENV")) |venv| {
        defer std.heap.c_allocator.free(venv);

        // Build Python code: import sys; sys.path.insert(0, 'path')
        var code_buf = std.ArrayList(u8){};
        defer code_buf.deinit(std.heap.c_allocator);

        try code_buf.writer(std.heap.c_allocator).print("import sys; sys.path.insert(0, r'{s}/lib/python3.12/site-packages')", .{venv});
        const code_z = try code_buf.toOwnedSliceSentinel(std.heap.c_allocator, 0);
        defer std.heap.c_allocator.free(code_z);

        std.debug.print("Adding to sys.path: {s}/lib/python3.12/site-packages\n", .{venv});
        const result = c.PyRun_SimpleString(code_z.ptr);
        if (result != 0) {
            std.debug.print("Failed to modify sys.path\n", .{});
        }
    } else |_| {}
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
