/// CPython System Module Interface
///
/// Implements the sys module interface for CPython compatibility.
///
/// ## Implementation Status
///
/// IMPLEMENTED (functional):
/// - PySys_WriteStdout/WriteStderr: Printf-style output to stdout/stderr
/// - PySys_FormatStdout/FormatStderr: Same as above
/// - PySys_GetSizeOf: Returns object memory size
/// - Py_GetRecursionLimit: Returns default limit (1000)
///
/// STUB (returns defaults/no-op):
/// - PySys_GetObject: Returns null (sys attributes not tracked)
/// - PySys_SetObject: Accepts silently
/// - PySys_SetPath: No-op (imports compiled statically)
/// - PySys_AddWarnOption: No-op (warnings not implemented)
/// - PySys_SetArgv/SetArgvEx: No-op (sys.argv not tracked)
/// - Py_SetRecursionLimit: No-op
/// - Py_EnterRecursiveCall/LeaveRecursiveCall: No-op (stack limit via native)
///
/// Note: metal0 AOT compilation means sys.path/sys.modules are not dynamic.
/// Most sys attributes are determined at compile time.

const std = @import("std");
const cpython = @import("cpython_object.zig");
const traits = @import("pyobject_traits.zig");

// Use centralized extern declarations
const Py_INCREF = traits.externs.Py_INCREF;
const Py_DECREF = traits.externs.Py_DECREF;

/// Global sys module dictionary - stores sys attributes
var sys_dict: ?*cpython.PyObject = null;
var sys_initialized: bool = false;

/// Initialize the sys module dictionary with default values
fn ensureSysInitialized() void {
    if (sys_initialized) return;
    sys_initialized = true;

    const pydict = @import("pyobject_dict.zig");
    const pylist = @import("pyobject_list.zig");
    const pyunicode = @import("cpython_unicode.zig");
    const pylong = @import("pyobject_long.zig");

    // Create sys dict
    sys_dict = pydict.PyDict_New();
    if (sys_dict == null) return;

    // sys.argv - empty list by default
    const argv = pylist.PyList_New(0);
    if (argv) |a| {
        _ = pydict.PyDict_SetItemString(sys_dict.?, "argv", a);
        traits.decref(a);
    }

    // sys.path - empty list by default (modules compiled statically)
    const path = pylist.PyList_New(0);
    if (path) |p| {
        _ = pydict.PyDict_SetItemString(sys_dict.?, "path", p);
        traits.decref(p);
    }

    // sys.modules - empty dict (modules are compiled in)
    const modules = pydict.PyDict_New();
    if (modules) |m| {
        _ = pydict.PyDict_SetItemString(sys_dict.?, "modules", m);
        traits.decref(m);
    }

    // sys.version - metal0 version string
    const version = pyunicode.PyUnicode_FromString("3.12.0 (metal0 AOT compiler)");
    if (version) |v| {
        _ = pydict.PyDict_SetItemString(sys_dict.?, "version", v);
        traits.decref(v);
    }

    // sys.version_info - tuple(3, 12, 0, 'final', 0)
    const pytuple = @import("pyobject_tuple.zig");
    const version_info = pytuple.PyTuple_New(5);
    if (version_info) |vi| {
        pytuple.PyTuple_SetItem(vi, 0, pylong.PyLong_FromLong(3));
        pytuple.PyTuple_SetItem(vi, 1, pylong.PyLong_FromLong(12));
        pytuple.PyTuple_SetItem(vi, 2, pylong.PyLong_FromLong(0));
        pytuple.PyTuple_SetItem(vi, 3, pyunicode.PyUnicode_FromString("final"));
        pytuple.PyTuple_SetItem(vi, 4, pylong.PyLong_FromLong(0));
        _ = pydict.PyDict_SetItemString(sys_dict.?, "version_info", vi);
        traits.decref(vi);
    }

    // sys.platform
    const platform = pyunicode.PyUnicode_FromString(switch (@import("builtin").os.tag) {
        .linux => "linux",
        .macos => "darwin",
        .windows => "win32",
        else => "unknown",
    });
    if (platform) |p| {
        _ = pydict.PyDict_SetItemString(sys_dict.?, "platform", p);
        traits.decref(p);
    }

    // sys.executable - placeholder
    const executable = pyunicode.PyUnicode_FromString("");
    if (executable) |e| {
        _ = pydict.PyDict_SetItemString(sys_dict.?, "executable", e);
        traits.decref(e);
    }

    // sys.maxsize
    const maxsize = pylong.PyLong_FromLongLong(std.math.maxInt(i64));
    if (maxsize) |m| {
        _ = pydict.PyDict_SetItemString(sys_dict.?, "maxsize", m);
        traits.decref(m);
    }

    // sys.byteorder
    const byteorder = pyunicode.PyUnicode_FromString(if (@import("builtin").cpu.arch.endian() == .little) "little" else "big");
    if (byteorder) |b| {
        _ = pydict.PyDict_SetItemString(sys_dict.?, "byteorder", b);
        traits.decref(b);
    }

    // sys.stdin/stdout/stderr - placeholders (null for now)
    // Extensions that need these should use C stdio directly
}

/// Get sys module attribute by name
/// Returns borrowed reference to sys.{name} or null if not found
export fn PySys_GetObject(name: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    ensureSysInitialized();

    if (sys_dict) |dict| {
        const pydict = @import("pyobject_dict.zig");
        return pydict.PyDict_GetItemString(dict, name);
    }

    return null;
}

/// Set sys module attribute
/// Steals reference to value
export fn PySys_SetObject(name: [*:0]const u8, value: ?*cpython.PyObject) callconv(.c) c_int {
    ensureSysInitialized();

    if (sys_dict) |dict| {
        const pydict = @import("pyobject_dict.zig");
        if (value) |v| {
            return pydict.PyDict_SetItemString(dict, name, v);
        } else {
            // null value means delete
            return pydict.PyDict_DelItemString(dict, name);
        }
    }

    return -1; // Failed - no sys dict
}

/// Set sys.path to the given path list
/// path should be a list of directory strings
/// STATUS: STUB - no-op (imports resolved at compile time)
export fn PySys_SetPath(path: [*:0]const u8) callconv(.c) void {
    _ = path;
    // Import paths resolved at compile time - runtime sys.path not used
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
/// STATUS: STUB - no-op (warnings not implemented)
export fn PySys_AddWarnOption(option: [*:0]const u8) callconv(.c) void {
    _ = option;
    // Warning options not tracked
}

/// Add directory to sys.path at the beginning
/// Used for adding import paths dynamically
/// STATUS: STUB - no-op (sys.argv/sys.path not tracked)
export fn PySys_SetArgvEx(argc: c_int, argv: [*][*:0]u8, updatepath: c_int) callconv(.c) void {
    _ = argc;
    _ = argv;
    _ = updatepath;
    // sys.argv not tracked - use std.os.argv directly if needed
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
/// STATUS: STUB - no-op (native stack limit used instead)
export fn Py_SetRecursionLimit(limit: c_int) callconv(.c) void {
    _ = limit;
    // Native stack limits used instead of Python recursion tracking
}

/// Check if current recursion depth exceeds limit
/// Returns 1 if too deep, 0 otherwise
/// STATUS: STUB - always returns 0 (not too deep)
export fn Py_EnterRecursiveCall(where: [*:0]const u8) callconv(.c) c_int {
    _ = where;
    // Native stack limits handle recursion depth - always allow
    return 0; // Not too deep
}

/// Exit recursive call tracking
/// Should be called when exiting a recursive function
/// STATUS: STUB - no-op
export fn Py_LeaveRecursiveCall() callconv(.c) void {
    // Native stack limits used - no tracking needed
}
