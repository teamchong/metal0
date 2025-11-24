/// CPython System Module Interface
///
/// Implements the sys module interface for CPython compatibility.

const std = @import("std");
const cpython = @import("cpython_object.zig");

// External dependencies
extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;

/// Get sys module attribute by name
/// Returns borrowed reference to sys.{name} or null if not found
export fn PySys_GetObject(name: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = name;
    // TODO: Implement sys attribute lookup
    // Common attributes: argv, path, modules, exc_info, version, platform
    return null;
}

/// Set sys module attribute
/// Steals reference to value
export fn PySys_SetObject(name: [*:0]const u8, value: ?*cpython.PyObject) callconv(.c) c_int {
    _ = name;
    if (value) |v| {
        _ = v;
        // TODO: Set sys.{name} = value
    }
    return 0; // Success
}

/// Set sys.path to the given path list
/// path should be a list of directory strings
export fn PySys_SetPath(path: [*:0]const u8) callconv(.c) void {
    _ = path;
    // TODO: Parse path string (colon-separated on Unix, semicolon on Windows)
    // and set sys.path to list of directories
}

/// Get size of Python object in bytes
/// Equivalent to sys.getsizeof()
export fn PySys_GetSizeOf(obj: *cpython.PyObject) callconv(.c) isize {
    const type_obj = cpython.Py_TYPE(obj);

    // Basic size from type
    var size: isize = @intCast(type_obj.tp_basicsize);

    // Add variable part for variable-size objects
    if (type_obj.tp_itemsize > 0) {
        const var_obj: *cpython.PyVarObject = @ptrCast(@alignCast(obj));
        size += @as(isize, @intCast(type_obj.tp_itemsize)) * var_obj.ob_size;
    }

    return size;
}

/// Write formatted output to sys.stdout
/// Uses C printf format strings
export fn PySys_WriteStdout(format: [*:0]const u8, ...) callconv(.c) void {
    var va = @cVaStart();
    defer @cVaEnd(&va);

    _ = std.c.vprintf(format, va);
}

/// Write formatted output to sys.stderr
/// Uses C printf format strings
export fn PySys_WriteStderr(format: [*:0]const u8, ...) callconv(.c) void {
    var va = @cVaStart();
    defer @cVaEnd(&va);

    // vfprintf to stderr
    _ = std.c.vfprintf(std.c.stderr, format, va);
}

/// Format and write to sys.stdout
/// Similar to PySys_WriteStdout but with explicit formatting
export fn PySys_FormatStdout(format: [*:0]const u8, ...) callconv(.c) void {
    var va = @cVaStart();
    defer @cVaEnd(&va);

    _ = std.c.vprintf(format, va);
}

/// Format and write to sys.stderr
/// Similar to PySys_WriteStderr but with explicit formatting
export fn PySys_FormatStderr(format: [*:0]const u8, ...) callconv(.c) void {
    var va = @cVaStart();
    defer @cVaEnd(&va);

    _ = std.c.vfprintf(std.c.stderr, format, va);
}

/// Add warning option to sys.warnoptions
/// Equivalent to -W command line option
export fn PySys_AddWarnOption(option: [*:0]const u8) callconv(.c) void {
    _ = option;
    // TODO: Append to sys.warnoptions list
}

/// Add directory to sys.path at the beginning
/// Used for adding import paths dynamically
export fn PySys_SetArgvEx(argc: c_int, argv: [*][*:0]u8, updatepath: c_int) callconv(.c) void {
    _ = argc;
    _ = argv;
    _ = updatepath;
    // TODO: Set sys.argv and optionally update sys.path
}

/// Set sys.argv from command line arguments
/// Convenience wrapper that always updates path
export fn PySys_SetArgv(argc: c_int, argv: [*][*:0]u8) callconv(.c) void {
    PySys_SetArgvEx(argc, argv, 1);
}

/// Get the current recursion limit
/// Default is usually 1000
export fn Py_GetRecursionLimit() callconv(.c) c_int {
    return 1000; // Default CPython recursion limit
}

/// Set the maximum recursion depth
/// Used to prevent stack overflow in deep recursion
export fn Py_SetRecursionLimit(limit: c_int) callconv(.c) void {
    _ = limit;
    // TODO: Store recursion limit globally
}

/// Check if current recursion depth exceeds limit
/// Returns 1 if too deep, 0 otherwise
export fn Py_EnterRecursiveCall(where: [*:0]const u8) callconv(.c) c_int {
    _ = where;
    // TODO: Increment recursion counter and check limit
    return 0; // Not too deep
}

/// Exit recursive call tracking
/// Should be called when exiting a recursive function
export fn Py_LeaveRecursiveCall() callconv(.c) void {
    // TODO: Decrement recursion counter
}
