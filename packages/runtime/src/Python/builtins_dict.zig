/// Builtins dictionary builder for eval/exec
/// Creates a dict containing Python's built-in constants and functions
const std = @import("std");
const runtime = @import("../runtime.zig");
const cpython = @import("../cpython.zig");
const PyObject = runtime.PyObject;
const PyDict = @import("../Objects/dictobject.zig").PyDict;
const PyInt = @import("../Objects/intobject.zig").PyInt;
const PyFloat = @import("../Objects/floatobject.zig").PyFloat;
const listobject = @import("../Objects/listobject.zig");
const PyList = listobject.PyList;
const PyListObject = listobject.PyListObject;
const PyTuple = @import("../Objects/tupleobject.zig").PyTuple;
const PySet = @import("../Objects/setobject.zig").PySet;
const builtinfunc = @import("../Objects/builtinfunc.zig");
const PyBuiltinFunction = builtinfunc.PyBuiltinFunction;
const PyBuiltinFunction_Check = builtinfunc.PyBuiltinFunction_Check;
const pyobject_utils = @import("../runtime/pyobject_utils.zig");

// =============================================================================
// Builtin Function Wrappers
// These wrap Zig functions to take []*PyObject args and return *PyObject
// =============================================================================

/// len(obj) -> int
fn wrapLen(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;
    const result = pyobject_utils.pyLen(args[0]);
    return PyInt.create(allocator, @intCast(result));
}

/// bool(obj) -> bool
fn wrapBool(_: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;
    const result = pyobject_utils.pyTruthy(args[0]);
    return if (result) runtime.Py_True else runtime.Py_False;
}

/// int(obj) -> int
fn wrapInt(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;
    const obj = args[0];

    // If already an int, return it
    if (cpython.PyLong_Check(obj)) {
        runtime.incref(obj);
        return obj;
    }

    // Handle floats: truncate to int (Python's int() behavior)
    if (cpython.PyFloat_Check(obj)) {
        const float_val = pyobject_utils.pyObjToFloat(obj);
        const int_val: i64 = @intFromFloat(float_val);
        return PyInt.create(allocator, int_val);
    }

    // Convert other types to int
    const result = pyobject_utils.pyObjToInt(obj);
    return PyInt.create(allocator, result);
}

/// float(obj) -> float
fn wrapFloat(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;
    const obj = args[0];

    // If already a float, return it
    if (cpython.PyFloat_Check(obj)) {
        runtime.incref(obj);
        return obj;
    }

    // Convert to float
    const result = pyobject_utils.pyObjToFloat(obj);
    return PyFloat.create(allocator, result);
}

/// str(obj) -> str
fn wrapStr(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;
    const obj = args[0];

    // If already a string, return it
    if (cpython.PyUnicode_Check(obj)) {
        runtime.incref(obj);
        return obj;
    }

    // Convert integers to string
    if (cpython.PyLong_Check(obj)) {
        const val = pyobject_utils.pyObjToInt(obj);
        const str = try std.fmt.allocPrint(allocator, "{d}", .{val});
        return runtime.PyString.create(allocator, str);
    }

    // Convert floats to string
    if (cpython.PyFloat_Check(obj)) {
        const val = pyobject_utils.pyObjToFloat(obj);
        const str = try std.fmt.allocPrint(allocator, "{d}", .{val});
        return runtime.PyString.create(allocator, str);
    }

    // Convert booleans to string
    if (cpython.PyBool_Check(obj)) {
        const str = if (obj == runtime.Py_True) "True" else "False";
        return runtime.PyString.create(allocator, str);
    }

    // None
    if (obj == runtime.Py_None) {
        return runtime.PyString.create(allocator, "None");
    }

    // Fallback for other types
    return runtime.PyString.create(allocator, "<object>");
}

/// type(obj) -> type
fn wrapType(_: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;
    const obj = args[0];
    // Return the type object
    return @ptrCast(obj.ob_type);
}

/// abs(x) -> number
fn wrapAbs(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;
    const obj = args[0];

    if (cpython.PyLong_Check(obj)) {
        const val = pyobject_utils.pyObjToInt(obj);
        const result = if (val < 0) -val else val;
        return PyInt.create(allocator, result);
    }
    if (cpython.PyFloat_Check(obj)) {
        const val = pyobject_utils.pyObjToFloat(obj);
        const result = @abs(val);
        return PyFloat.create(allocator, result);
    }
    return error.TypeError;
}

// =============================================================================
// Phase 3c: Extended Builtins
// =============================================================================

/// range(stop) or range(start, stop) or range(start, stop, step)
fn wrapRange(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len < 1 or args.len > 3) return error.TypeError;

    var start: i64 = 0;
    var stop: i64 = 0;
    var step: i64 = 1;

    if (args.len == 1) {
        // range(stop)
        stop = pyobject_utils.pyObjToInt(args[0]);
    } else if (args.len == 2) {
        // range(start, stop)
        start = pyobject_utils.pyObjToInt(args[0]);
        stop = pyobject_utils.pyObjToInt(args[1]);
    } else {
        // range(start, stop, step)
        start = pyobject_utils.pyObjToInt(args[0]);
        stop = pyobject_utils.pyObjToInt(args[1]);
        step = pyobject_utils.pyObjToInt(args[2]);
    }

    if (step == 0) return error.ValueError;

    const result = try PyList.create(allocator);

    if (step > 0) {
        var i = start;
        while (i < stop) : (i += step) {
            const item = try PyInt.create(allocator, i);
            try PyList.append(result, item);
            runtime.decref(item, allocator);
        }
    } else {
        var i = start;
        while (i > stop) : (i += step) {
            const item = try PyInt.create(allocator, i);
            try PyList.append(result, item);
            runtime.decref(item, allocator);
        }
    }

    return result;
}

/// list() or list(iterable)
fn wrapList(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len == 0) {
        return PyList.create(allocator);
    }
    if (args.len != 1) return error.TypeError;

    const obj = args[0];

    // If already a list, copy it
    if (runtime.PyList_Check(obj)) {
        const source: *PyListObject = @ptrCast(@alignCast(obj));
        const result = try PyList.create(allocator);
        const size: usize = @intCast(source.ob_base.ob_size);
        for (0..size) |i| {
            const item = source.ob_item[i];
            runtime.incref(item);
            try PyList.append(result, item);
        }
        return result;
    }

    // Create empty list for other types (TODO: handle iterables)
    return PyList.create(allocator);
}

/// tuple() or tuple(iterable)
fn wrapTuple(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len == 0) {
        return PyTuple.create(allocator, 0);
    }
    if (args.len != 1) return error.TypeError;

    const obj = args[0];

    // If it's a list, convert to tuple
    if (runtime.PyList_Check(obj)) {
        const source: *PyListObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(source.ob_base.ob_size);
        const result = try PyTuple.create(allocator, size);
        for (0..size) |i| {
            const item = source.ob_item[i];
            runtime.incref(item);
            PyTuple.setItem(result, i, item);
        }
        return result;
    }

    // Create empty tuple for other types
    return PyTuple.create(allocator, 0);
}

/// dict()
fn wrapDict(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len > 0) return error.TypeError; // dict() only supports no-arg form in eval
    return PyDict.create(allocator);
}

/// set() or set(iterable)
fn wrapSet(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len == 0) {
        return PySet.create(allocator);
    }
    if (args.len != 1) return error.TypeError;

    const obj = args[0];

    // If it's a list, convert to set
    if (runtime.PyList_Check(obj)) {
        return PySet.fromList(allocator, obj);
    }

    // Create empty set for other types
    return PySet.create(allocator);
}

/// min(a, b, ...) or min(iterable)
fn wrapMin(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len == 0) return error.TypeError;

    // Single iterable case
    if (args.len == 1 and runtime.PyList_Check(args[0])) {
        const list_obj: *PyListObject = @ptrCast(@alignCast(args[0]));
        const size: usize = @intCast(list_obj.ob_base.ob_size);
        var min_val: i64 = std.math.maxInt(i64);
        for (0..size) |i| {
            const item = list_obj.ob_item[i];
            if (cpython.PyLong_Check(item)) {
                const val = pyobject_utils.pyObjToInt(item);
                if (val < min_val) min_val = val;
            }
        }
        return PyInt.create(allocator, min_val);
    }

    // Varargs case - find min among all args
    var min_val: i64 = pyobject_utils.pyObjToInt(args[0]);
    for (args[1..]) |arg| {
        const val = pyobject_utils.pyObjToInt(arg);
        if (val < min_val) {
            min_val = val;
        }
    }
    return PyInt.create(allocator, min_val);
}

/// max(a, b, ...) or max(iterable)
fn wrapMax(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len == 0) return error.TypeError;

    // Single iterable case
    if (args.len == 1 and runtime.PyList_Check(args[0])) {
        const list_obj: *PyListObject = @ptrCast(@alignCast(args[0]));
        const size: usize = @intCast(list_obj.ob_base.ob_size);
        var max_val: i64 = std.math.minInt(i64);
        for (0..size) |i| {
            const item = list_obj.ob_item[i];
            if (cpython.PyLong_Check(item)) {
                const val = pyobject_utils.pyObjToInt(item);
                if (val > max_val) max_val = val;
            }
        }
        return PyInt.create(allocator, max_val);
    }

    // Varargs case - find max among all args
    var max_val: i64 = pyobject_utils.pyObjToInt(args[0]);
    for (args[1..]) |arg| {
        const val = pyobject_utils.pyObjToInt(arg);
        if (val > max_val) {
            max_val = val;
        }
    }
    return PyInt.create(allocator, max_val);
}

/// sum(iterable, start=0)
fn wrapSum(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len < 1 or args.len > 2) return error.TypeError;

    const start: i64 = if (args.len == 2) pyobject_utils.pyObjToInt(args[1]) else 0;

    if (runtime.PyList_Check(args[0])) {
        const list_obj: *PyListObject = @ptrCast(@alignCast(args[0]));
        const size: usize = @intCast(list_obj.ob_base.ob_size);
        var total: i64 = start;
        for (0..size) |i| {
            const item = list_obj.ob_item[i];
            if (cpython.PyLong_Check(item)) {
                total += pyobject_utils.pyObjToInt(item);
            }
        }
        return PyInt.create(allocator, total);
    }

    return PyInt.create(allocator, start);
}

/// print(*args) -> None
fn wrapPrint(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    // Build output string
    var first = true;
    for (args) |arg| {
        if (!first) {
            _ = std.posix.write(std.posix.STDOUT_FILENO, " ") catch {};
        }
        first = false;

        // Convert arg to string and print
        if (cpython.PyUnicode_Check(arg)) {
            const str_obj: *cpython.PyUnicodeObject = @ptrCast(@alignCast(arg));
            const len: usize = @intCast(str_obj.length);
            _ = std.posix.write(std.posix.STDOUT_FILENO, str_obj.data[0..len]) catch {};
        } else if (cpython.PyLong_Check(arg)) {
            const val = pyobject_utils.pyObjToInt(arg);
            const str = std.fmt.allocPrint(allocator, "{d}", .{val}) catch continue;
            defer allocator.free(str);
            _ = std.posix.write(std.posix.STDOUT_FILENO, str) catch {};
        } else if (cpython.PyFloat_Check(arg)) {
            const val = pyobject_utils.pyObjToFloat(arg);
            const str = std.fmt.allocPrint(allocator, "{d}", .{val}) catch continue;
            defer allocator.free(str);
            _ = std.posix.write(std.posix.STDOUT_FILENO, str) catch {};
        } else if (cpython.PyBool_Check(arg)) {
            const bool_obj: *cpython.PyBoolObject = @ptrCast(@alignCast(arg));
            const str = if (bool_obj.getValue()) "True" else "False";
            _ = std.posix.write(std.posix.STDOUT_FILENO, str) catch {};
        } else if (arg == runtime.Py_None) {
            _ = std.posix.write(std.posix.STDOUT_FILENO, "None") catch {};
        } else if (runtime.PyList_Check(arg)) {
            // Format list
            _ = std.posix.write(std.posix.STDOUT_FILENO, "[") catch {};
            const list_obj: *PyListObject = @ptrCast(@alignCast(arg));
            const size: usize = @intCast(list_obj.ob_base.ob_size);
            var list_first = true;
            for (0..size) |i| {
                if (!list_first) {
                    _ = std.posix.write(std.posix.STDOUT_FILENO, ", ") catch {};
                }
                list_first = false;
                const item = list_obj.ob_item[i];
                if (cpython.PyLong_Check(item)) {
                    const val = pyobject_utils.pyObjToInt(item);
                    const str = std.fmt.allocPrint(allocator, "{d}", .{val}) catch continue;
                    defer allocator.free(str);
                    _ = std.posix.write(std.posix.STDOUT_FILENO, str) catch {};
                }
            }
            _ = std.posix.write(std.posix.STDOUT_FILENO, "]") catch {};
        } else {
            _ = std.posix.write(std.posix.STDOUT_FILENO, "<object>") catch {};
        }
    }
    _ = std.posix.write(std.posix.STDOUT_FILENO, "\n") catch {};

    return runtime.Py_None;
}

/// sorted(iterable) -> list
fn wrapSorted(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;

    if (runtime.PyList_Check(args[0])) {
        const source: *PyListObject = @ptrCast(@alignCast(args[0]));
        const size: usize = @intCast(source.ob_base.ob_size);
        const result = try PyList.create(allocator);

        // Copy items to result list
        for (0..size) |i| {
            const item = source.ob_item[i];
            runtime.incref(item);
            try PyList.append(result, item);
        }

        // Sort the result
        PyList.sort(result);
        return result;
    }

    // Return empty list for non-list types
    return PyList.create(allocator);
}

/// reversed(iterable) -> list
fn wrapReversed(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;

    if (runtime.PyList_Check(args[0])) {
        const source: *PyListObject = @ptrCast(@alignCast(args[0]));
        const size: usize = @intCast(source.ob_base.ob_size);
        const result = try PyList.create(allocator);

        // Copy items in reverse order
        var i: usize = size;
        while (i > 0) {
            i -= 1;
            const item = source.ob_item[i];
            runtime.incref(item);
            try PyList.append(result, item);
        }
        return result;
    }

    // Return empty list for non-list types
    return PyList.create(allocator);
}

/// enumerate(iterable, start=0) -> list of (index, item) tuples
fn wrapEnumerate(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len < 1 or args.len > 2) return error.TypeError;

    const start: i64 = if (args.len == 2) pyobject_utils.pyObjToInt(args[1]) else 0;

    if (runtime.PyList_Check(args[0])) {
        const source: *PyListObject = @ptrCast(@alignCast(args[0]));
        const size: usize = @intCast(source.ob_base.ob_size);
        const result = try PyList.create(allocator);

        var index: i64 = start;
        for (0..size) |i| {
            const item = source.ob_item[i];
            const tuple = try PyTuple.create(allocator, 2);
            const idx_obj = try PyInt.create(allocator, index);
            PyTuple.setItem(tuple, 0, idx_obj);
            runtime.decref(idx_obj, allocator);
            runtime.incref(item);
            PyTuple.setItem(tuple, 1, item);
            try PyList.append(result, tuple);
            runtime.decref(tuple, allocator);
            index += 1;
        }
        return result;
    }

    // Return empty list for non-list types
    return PyList.create(allocator);
}

/// zip(iter1, iter2) -> list of tuples
fn wrapZip(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len < 2) return error.TypeError;

    // Support zip of 2 lists
    if (args.len >= 2 and runtime.PyList_Check(args[0]) and runtime.PyList_Check(args[1])) {
        const list1: *PyListObject = @ptrCast(@alignCast(args[0]));
        const list2: *PyListObject = @ptrCast(@alignCast(args[1]));
        const size1: usize = @intCast(list1.ob_base.ob_size);
        const size2: usize = @intCast(list2.ob_base.ob_size);
        const min_len = @min(size1, size2);

        const result = try PyList.create(allocator);
        for (0..min_len) |i| {
            const tuple = try PyTuple.create(allocator, 2);
            runtime.incref(list1.ob_item[i]);
            PyTuple.setItem(tuple, 0, list1.ob_item[i]);
            runtime.incref(list2.ob_item[i]);
            PyTuple.setItem(tuple, 1, list2.ob_item[i]);
            try PyList.append(result, tuple);
            runtime.decref(tuple, allocator);
        }
        return result;
    }

    // Return empty list for other cases
    return PyList.create(allocator);
}

// =============================================================================
// Phase 3c+: Additional Builtins
// =============================================================================

/// all(iterable) -> bool - True if all elements are truthy
fn wrapAll(_: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;

    if (runtime.PyList_Check(args[0])) {
        const list_obj: *PyListObject = @ptrCast(@alignCast(args[0]));
        const size: usize = @intCast(list_obj.ob_base.ob_size);

        for (0..size) |i| {
            const item = list_obj.ob_item[i];
            if (!pyobject_utils.pyTruthy(item)) {
                return runtime.Py_False;
            }
        }
        return runtime.Py_True;
    }

    // Empty or non-list -> True (vacuous truth)
    return runtime.Py_True;
}

/// any(iterable) -> bool - True if any element is truthy
fn wrapAny(_: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;

    if (runtime.PyList_Check(args[0])) {
        const list_obj: *PyListObject = @ptrCast(@alignCast(args[0]));
        const size: usize = @intCast(list_obj.ob_base.ob_size);

        for (0..size) |i| {
            const item = list_obj.ob_item[i];
            if (pyobject_utils.pyTruthy(item)) {
                return runtime.Py_True;
            }
        }
        return runtime.Py_False;
    }

    // Empty or non-list -> False
    return runtime.Py_False;
}

/// round(number, ndigits=0) -> number
fn wrapRound(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len < 1 or args.len > 2) return error.TypeError;

    const ndigits: i64 = if (args.len == 2) pyobject_utils.pyObjToInt(args[1]) else 0;

    if (cpython.PyFloat_Check(args[0])) {
        const val = pyobject_utils.pyObjToFloat(args[0]);
        const multiplier = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(ndigits)));
        const rounded = @round(val * multiplier) / multiplier;
        if (ndigits <= 0) {
            return PyInt.create(allocator, @intFromFloat(rounded));
        }
        return PyFloat.create(allocator, rounded);
    }

    if (cpython.PyLong_Check(args[0])) {
        // Rounding an integer returns the integer (or scaled for negative ndigits)
        const val = pyobject_utils.pyObjToInt(args[0]);
        if (ndigits >= 0) {
            return PyInt.create(allocator, val);
        }
        // Negative ndigits: round to nearest 10^(-ndigits)
        const scale = std.math.pow(i64, 10, @intCast(-ndigits));
        const rounded = @divTrunc(val + @divTrunc(scale, 2), scale) * scale;
        return PyInt.create(allocator, rounded);
    }

    return error.TypeError;
}

/// pow(base, exp, mod=None) -> number
fn wrapPow(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len < 2 or args.len > 3) return error.TypeError;

    const base = pyobject_utils.pyObjToInt(args[0]);
    const exp = pyobject_utils.pyObjToInt(args[1]);

    if (args.len == 3 and args[2] != runtime.Py_None) {
        // Modular exponentiation
        const mod = pyobject_utils.pyObjToInt(args[2]);
        if (mod == 0) return error.ValueError;
        var result: i64 = 1;
        var b = @mod(base, mod);
        var e = exp;
        while (e > 0) {
            if (@mod(e, 2) == 1) {
                result = @mod(result * b, mod);
            }
            e = @divTrunc(e, 2);
            b = @mod(b * b, mod);
        }
        return PyInt.create(allocator, result);
    }

    // Simple exponentiation
    if (exp < 0) {
        // Negative exponent returns float
        const base_f: f64 = @floatFromInt(base);
        const exp_f: f64 = @floatFromInt(exp);
        return PyFloat.create(allocator, std.math.pow(f64, base_f, exp_f));
    }

    var result: i64 = 1;
    var i: i64 = 0;
    while (i < exp) : (i += 1) {
        result *= base;
    }
    return PyInt.create(allocator, result);
}

/// ord(char) -> int - Unicode code point of character
fn wrapOrd(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;

    if (cpython.PyUnicode_Check(args[0])) {
        const str_obj: *cpython.PyUnicodeObject = @ptrCast(@alignCast(args[0]));
        const len: usize = @intCast(str_obj.length);
        if (len != 1) return error.TypeError; // ord() expects single character

        const data = str_obj.data[0..len];
        // Decode UTF-8 to get codepoint
        const codepoint: u32 = blk: {
            const byte = data[0];
            if (byte < 0x80) {
                break :blk byte;
            } else if (byte < 0xE0) {
                break :blk (@as(u32, byte & 0x1F) << 6) | (data[1] & 0x3F);
            } else if (byte < 0xF0) {
                break :blk (@as(u32, byte & 0x0F) << 12) | (@as(u32, data[1] & 0x3F) << 6) | (data[2] & 0x3F);
            } else {
                break :blk (@as(u32, byte & 0x07) << 18) | (@as(u32, data[1] & 0x3F) << 12) | (@as(u32, data[2] & 0x3F) << 6) | (data[3] & 0x3F);
            }
        };
        return PyInt.create(allocator, @intCast(codepoint));
    }

    return error.TypeError;
}

/// chr(i) -> str - Character from Unicode code point
fn wrapChr(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;

    // Extract integer value directly from PyLong
    const codepoint: u32 = blk: {
        if (cpython.PyLong_Check(args[0])) {
            const long_obj: *cpython.PyLongObject = @ptrCast(@alignCast(args[0]));
            break :blk @intCast(long_obj.getValue());
        }
        return error.TypeError;
    };
    if (codepoint > 0x10FFFF) return error.ValueError;

    // Encode as UTF-8
    var buf: [4]u8 = undefined;
    const len: usize = if (codepoint < 0x80) blk: {
        buf[0] = @intCast(codepoint);
        break :blk 1;
    } else if (codepoint < 0x800) blk: {
        buf[0] = @intCast(0xC0 | (codepoint >> 6));
        buf[1] = @intCast(0x80 | (codepoint & 0x3F));
        break :blk 2;
    } else if (codepoint < 0x10000) blk: {
        buf[0] = @intCast(0xE0 | (codepoint >> 12));
        buf[1] = @intCast(0x80 | ((codepoint >> 6) & 0x3F));
        buf[2] = @intCast(0x80 | (codepoint & 0x3F));
        break :blk 3;
    } else blk: {
        buf[0] = @intCast(0xF0 | (codepoint >> 18));
        buf[1] = @intCast(0x80 | ((codepoint >> 12) & 0x3F));
        buf[2] = @intCast(0x80 | ((codepoint >> 6) & 0x3F));
        buf[3] = @intCast(0x80 | (codepoint & 0x3F));
        break :blk 4;
    };

    return runtime.PyString.create(allocator, buf[0..len]);
}

/// hex(x) -> str - Convert integer to hexadecimal string
fn wrapHex(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;

    const val = pyobject_utils.pyObjToInt(args[0]);
    const is_negative = val < 0;
    const abs_val: u64 = if (is_negative) @intCast(-val) else @intCast(val);

    const prefix = if (is_negative) "-0x" else "0x";
    const hex_str = try std.fmt.allocPrint(allocator, "{s}{x}", .{ prefix, abs_val });
    return runtime.PyString.create(allocator, hex_str);
}

/// oct(x) -> str - Convert integer to octal string
fn wrapOct(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;

    const val = pyobject_utils.pyObjToInt(args[0]);
    const is_negative = val < 0;
    const abs_val: u64 = if (is_negative) @intCast(-val) else @intCast(val);

    const prefix = if (is_negative) "-0o" else "0o";
    const oct_str = try std.fmt.allocPrint(allocator, "{s}{o}", .{ prefix, abs_val });
    return runtime.PyString.create(allocator, oct_str);
}

/// bin(x) -> str - Convert integer to binary string
fn wrapBin(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;

    const val = pyobject_utils.pyObjToInt(args[0]);
    const is_negative = val < 0;
    const abs_val: u64 = if (is_negative) @intCast(-val) else @intCast(val);

    const prefix = if (is_negative) "-0b" else "0b";
    const bin_str = try std.fmt.allocPrint(allocator, "{s}{b}", .{ prefix, abs_val });
    return runtime.PyString.create(allocator, bin_str);
}

/// callable(obj) -> bool - Check if object appears callable
fn wrapCallable(_: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;

    const obj = args[0];

    // Check if it's a PyBuiltinFunction
    if (PyBuiltinFunction_Check(obj)) {
        return runtime.Py_True;
    }

    // For other types, we'd need more introspection
    // For now, return False for non-builtin-functions
    return runtime.Py_False;
}

/// repr(obj) -> str - Printable representation of object
fn wrapRepr(allocator: std.mem.Allocator, args: []*PyObject) !*PyObject {
    if (args.len != 1) return error.TypeError;

    const obj = args[0];

    if (cpython.PyUnicode_Check(obj)) {
        const str_obj: *cpython.PyUnicodeObject = @ptrCast(@alignCast(obj));
        const len: usize = @intCast(str_obj.length);
        const data = str_obj.data[0..len];
        // repr of string includes quotes
        const repr_str = try std.fmt.allocPrint(allocator, "'{s}'", .{data});
        return runtime.PyString.create(allocator, repr_str);
    }

    if (cpython.PyLong_Check(obj)) {
        const val = pyobject_utils.pyObjToInt(obj);
        const str = try std.fmt.allocPrint(allocator, "{d}", .{val});
        return runtime.PyString.create(allocator, str);
    }

    if (cpython.PyFloat_Check(obj)) {
        const val = pyobject_utils.pyObjToFloat(obj);
        const str = try std.fmt.allocPrint(allocator, "{d}", .{val});
        return runtime.PyString.create(allocator, str);
    }

    if (cpython.PyBool_Check(obj)) {
        const bool_obj: *cpython.PyBoolObject = @ptrCast(@alignCast(obj));
        return runtime.PyString.create(allocator, if (bool_obj.getValue()) "True" else "False");
    }

    if (obj == runtime.Py_None) {
        return runtime.PyString.create(allocator, "None");
    }

    if (runtime.PyList_Check(obj)) {
        return runtime.PyString.create(allocator, "[...]");
    }

    return runtime.PyString.create(allocator, "<object>");
}

// =============================================================================
// Builtins Dict Creation
// =============================================================================

/// Create a builtins dict with Python's built-in constants and functions
pub fn createBuiltinsDict(allocator: std.mem.Allocator) !*PyObject {
    const dict = try PyDict.create(allocator);

    // Built-in constants
    try PyDict.set(dict, "True", runtime.Py_True);
    try PyDict.set(dict, "False", runtime.Py_False);
    try PyDict.set(dict, "None", runtime.Py_None);

    // Core builtin functions
    try PyDict.set(dict, "len", try PyBuiltinFunction.create(allocator, "len", wrapLen));
    try PyDict.set(dict, "bool", try PyBuiltinFunction.create(allocator, "bool", wrapBool));
    try PyDict.set(dict, "int", try PyBuiltinFunction.create(allocator, "int", wrapInt));
    try PyDict.set(dict, "float", try PyBuiltinFunction.create(allocator, "float", wrapFloat));
    try PyDict.set(dict, "str", try PyBuiltinFunction.create(allocator, "str", wrapStr));
    try PyDict.set(dict, "type", try PyBuiltinFunction.create(allocator, "type", wrapType));
    try PyDict.set(dict, "abs", try PyBuiltinFunction.create(allocator, "abs", wrapAbs));

    // Phase 3c: Extended builtins
    try PyDict.set(dict, "range", try PyBuiltinFunction.create(allocator, "range", wrapRange));
    try PyDict.set(dict, "list", try PyBuiltinFunction.create(allocator, "list", wrapList));
    try PyDict.set(dict, "tuple", try PyBuiltinFunction.create(allocator, "tuple", wrapTuple));
    try PyDict.set(dict, "dict", try PyBuiltinFunction.create(allocator, "dict", wrapDict));
    try PyDict.set(dict, "set", try PyBuiltinFunction.create(allocator, "set", wrapSet));
    try PyDict.set(dict, "min", try PyBuiltinFunction.create(allocator, "min", wrapMin));
    try PyDict.set(dict, "max", try PyBuiltinFunction.create(allocator, "max", wrapMax));
    try PyDict.set(dict, "sum", try PyBuiltinFunction.create(allocator, "sum", wrapSum));
    try PyDict.set(dict, "print", try PyBuiltinFunction.create(allocator, "print", wrapPrint));
    try PyDict.set(dict, "sorted", try PyBuiltinFunction.create(allocator, "sorted", wrapSorted));
    try PyDict.set(dict, "reversed", try PyBuiltinFunction.create(allocator, "reversed", wrapReversed));
    try PyDict.set(dict, "enumerate", try PyBuiltinFunction.create(allocator, "enumerate", wrapEnumerate));
    try PyDict.set(dict, "zip", try PyBuiltinFunction.create(allocator, "zip", wrapZip));

    // Phase 3c+: Additional builtins
    try PyDict.set(dict, "all", try PyBuiltinFunction.create(allocator, "all", wrapAll));
    try PyDict.set(dict, "any", try PyBuiltinFunction.create(allocator, "any", wrapAny));
    try PyDict.set(dict, "round", try PyBuiltinFunction.create(allocator, "round", wrapRound));
    try PyDict.set(dict, "pow", try PyBuiltinFunction.create(allocator, "pow", wrapPow));
    try PyDict.set(dict, "ord", try PyBuiltinFunction.create(allocator, "ord", wrapOrd));
    try PyDict.set(dict, "chr", try PyBuiltinFunction.create(allocator, "chr", wrapChr));
    try PyDict.set(dict, "hex", try PyBuiltinFunction.create(allocator, "hex", wrapHex));
    try PyDict.set(dict, "oct", try PyBuiltinFunction.create(allocator, "oct", wrapOct));
    try PyDict.set(dict, "bin", try PyBuiltinFunction.create(allocator, "bin", wrapBin));
    try PyDict.set(dict, "callable", try PyBuiltinFunction.create(allocator, "callable", wrapCallable));
    try PyDict.set(dict, "repr", try PyBuiltinFunction.create(allocator, "repr", wrapRepr));

    return dict;
}

/// Global cached builtins dict (created once, reused)
var cached_builtins: ?*PyObject = null;

/// Get or create the global builtins dict
pub fn getBuiltinsDict(allocator: std.mem.Allocator) !*PyObject {
    if (cached_builtins) |builtins| {
        return builtins;
    }
    cached_builtins = try createBuiltinsDict(allocator);
    return cached_builtins.?;
}
