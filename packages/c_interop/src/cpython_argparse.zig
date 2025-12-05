/// CPython Argument Parsing
///
/// Implements PyArg_ParseTuple and related functions
/// This is CRITICAL - 99% of C extension functions use this!
///
/// Format string examples:
///   "s"    - string
///   "i"    - int
///   "l"    - long
///   "d"    - double
///   "O"    - PyObject*
///   "s|i"  - string, optional int
///   "ll"   - two longs

const std = @import("std");
const cpython = @import("cpython_object.zig");
const traits = @import("pyobject_traits.zig");

// Use centralized pure Zig implementations (NO extern declarations)
const Py_INCREF = traits.externs.Py_INCREF;
const PyLong_FromLong = traits.externs.PyLong_FromLong;
const PyLong_AsLong = traits.externs.PyLong_AsLong;
const PyLong_AsLongLong = traits.externs.PyLong_AsLongLong;
const PyFloat_AsDouble = traits.externs.PyFloat_AsDouble;
const PyFloat_FromDouble = traits.externs.PyFloat_FromDouble;
const PyTuple_New = traits.externs.PyTuple_New;
const PyTuple_GetItem = traits.externs.PyTuple_GetItem;
const PyTuple_SetItem = traits.externs.PyTuple_SetItem;
const PyUnicode_AsUTF8 = traits.externs.PyUnicode_AsUTF8;

/// ============================================================================
/// PYARG_PARSETUPLE - The Big One!
/// ============================================================================

/// Parse Python tuple into C variables according to format string
///
/// Usage from C:
/// ```c
/// long a, b;
/// if (!PyArg_ParseTuple(args, "ll", &a, &b)) {
///     return NULL;
/// }
/// ```
///
/// Format codes:
///   s - string (char**)
///   i - int (int*)
///   l - long (long*)
///   L - long long (long long*)
///   d - double (double*)
///   f - float (float*)
///   O - PyObject* (PyObject**)
///   | - optional marker (everything after is optional)
///
export fn PyArg_ParseTuple(args: *cpython.PyObject, format: [*:0]const u8, ...) callconv(.C) c_int {
    // Get tuple
    const tuple = @as(*cpython.PyTupleObject, @ptrCast(args));

    // Parse format string
    const fmt = std.mem.span(format);
    var fmt_idx: usize = 0;
    var arg_idx: isize = 0;
    var optional = false;

    // Get variadic args pointer
    var va = @cVaStart();
    defer @cVaEnd(&va);

    while (fmt_idx < fmt.len) : (fmt_idx += 1) {
        const c = fmt[fmt_idx];

        switch (c) {
            '|' => {
                optional = true;
                continue;
            },
            ' ', '\t', '\n' => continue, // Skip whitespace

            's' => {
                // String - extract char*
                if (arg_idx >= tuple.ob_base.ob_size) {
                    if (optional) return 1; // Success, optional arg missing
                    return 0; // Error
                }

                const item = PyTuple_GetItem(args, arg_idx);
                if (item == null) return 0;

                // Extract string from PyUnicode object
                const dest = @cVaArg(&va, *[*:0]const u8);
                const pyunicode = @import("cpython_unicode.zig");
                if (pyunicode.PyUnicode_AsUTF8(item.?)) |str| {
                    dest.* = str;
                } else {
                    return 0;
                }

                arg_idx += 1;
            },

            'i' => {
                // Integer - extract int
                if (arg_idx >= tuple.ob_base.ob_size) {
                    if (optional) return 1;
                    return 0;
                }

                const item = PyTuple_GetItem(args, arg_idx);
                if (item == null) return 0;

                const dest = @cVaArg(&va, *c_int);
                const value = PyLong_AsLong(item.?);
                dest.* = @intCast(value);

                arg_idx += 1;
            },

            'l' => {
                // Long - extract long
                if (arg_idx >= tuple.ob_base.ob_size) {
                    if (optional) return 1;
                    return 0;
                }

                const item = PyTuple_GetItem(args, arg_idx);
                if (item == null) return 0;

                const dest = @cVaArg(&va, *c_long);
                dest.* = PyLong_AsLong(item.?);

                arg_idx += 1;
            },

            'L' => {
                // Long long
                if (arg_idx >= tuple.ob_base.ob_size) {
                    if (optional) return 1;
                    return 0;
                }

                const item = PyTuple_GetItem(args, arg_idx);
                if (item == null) return 0;

                const dest = @cVaArg(&va, *c_longlong);
                dest.* = PyLong_AsLongLong(item.?);

                arg_idx += 1;
            },

            'd' => {
                // Double
                if (arg_idx >= tuple.ob_base.ob_size) {
                    if (optional) return 1;
                    return 0;
                }

                const item = PyTuple_GetItem(args, arg_idx);
                if (item == null) return 0;

                const dest = @cVaArg(&va, *f64);
                dest.* = PyFloat_AsDouble(item.?);

                arg_idx += 1;
            },

            'f' => {
                // Float
                if (arg_idx >= tuple.ob_base.ob_size) {
                    if (optional) return 1;
                    return 0;
                }

                const item = PyTuple_GetItem(args, arg_idx);
                if (item == null) return 0;

                const dest = @cVaArg(&va, *f32);
                const val = PyFloat_AsDouble(item.?);
                dest.* = @floatCast(val);

                arg_idx += 1;
            },

            'O' => {
                // PyObject* - no conversion
                if (arg_idx >= tuple.ob_base.ob_size) {
                    if (optional) return 1;
                    return 0;
                }

                const item = PyTuple_GetItem(args, arg_idx);
                if (item == null) return 0;

                const dest = @cVaArg(&va, **cpython.PyObject);
                dest.* = item.?;

                arg_idx += 1;
            },

            else => {
                // Unknown format character
                return 0;
            },
        }
    }

    return 1; // Success
}

/// Parse tuple and keywords (extended version)
export fn PyArg_ParseTupleAndKeywords(
    args: *cpython.PyObject,
    kwargs: ?*cpython.PyObject,
    format: [*:0]const u8,
    keywords: [*]const ?[*:0]const u8,
    ...
) callconv(.C) c_int {
    const pydict = @import("pyobject_dict.zig");
    const pyunicode = @import("pyobject_unicode.zig");

    const tuple = @as(*cpython.PyTupleObject, @ptrCast(args));
    const fmt = std.mem.span(format);

    var va = @cVaStart();
    defer @cVaEnd(&va);

    var fmt_idx: usize = 0;
    var arg_idx: isize = 0;
    var kw_idx: usize = 0;
    var optional = false;

    while (fmt_idx < fmt.len) : (fmt_idx += 1) {
        const c = fmt[fmt_idx];

        switch (c) {
            '|' => {
                optional = true;
                continue;
            },
            ':' => break, // Function name follows, stop parsing
            ';' => break, // Error message follows, stop parsing
            ' ', '\t', '\n' => continue,

            's' => {
                const dest = @cVaArg(&va, *[*:0]const u8);
                const item = getArgOrKwarg(tuple, args, arg_idx, kwargs, keywords, kw_idx, pydict, pyunicode);
                if (item) |it| {
                    if (pyunicode.PyUnicode_AsUTF8(it)) |str| {
                        dest.* = str;
                    } else if (!optional) return 0;
                } else if (!optional) return 0;
                arg_idx += 1;
                kw_idx += 1;
            },

            'z' => {
                // String or None
                const dest = @cVaArg(&va, *?[*:0]const u8);
                const item = getArgOrKwarg(tuple, args, arg_idx, kwargs, keywords, kw_idx, pydict, pyunicode);
                if (item) |it| {
                    if (traits.isNone(it)) {
                        dest.* = null;
                    } else if (pyunicode.PyUnicode_AsUTF8(it)) |str| {
                        dest.* = str;
                    } else if (!optional) return 0;
                } else {
                    dest.* = null;
                }
                arg_idx += 1;
                kw_idx += 1;
            },

            'i' => {
                const dest = @cVaArg(&va, *c_int);
                const item = getArgOrKwarg(tuple, args, arg_idx, kwargs, keywords, kw_idx, pydict, pyunicode);
                if (item) |it| {
                    dest.* = @intCast(PyLong_AsLong(it));
                } else if (!optional) return 0;
                arg_idx += 1;
                kw_idx += 1;
            },

            'l' => {
                const dest = @cVaArg(&va, *c_long);
                const item = getArgOrKwarg(tuple, args, arg_idx, kwargs, keywords, kw_idx, pydict, pyunicode);
                if (item) |it| {
                    dest.* = PyLong_AsLong(it);
                } else if (!optional) return 0;
                arg_idx += 1;
                kw_idx += 1;
            },

            'L' => {
                const dest = @cVaArg(&va, *c_longlong);
                const item = getArgOrKwarg(tuple, args, arg_idx, kwargs, keywords, kw_idx, pydict, pyunicode);
                if (item) |it| {
                    dest.* = PyLong_AsLongLong(it);
                } else if (!optional) return 0;
                arg_idx += 1;
                kw_idx += 1;
            },

            'd' => {
                const dest = @cVaArg(&va, *f64);
                const item = getArgOrKwarg(tuple, args, arg_idx, kwargs, keywords, kw_idx, pydict, pyunicode);
                if (item) |it| {
                    dest.* = PyFloat_AsDouble(it);
                } else if (!optional) return 0;
                arg_idx += 1;
                kw_idx += 1;
            },

            'f' => {
                const dest = @cVaArg(&va, *f32);
                const item = getArgOrKwarg(tuple, args, arg_idx, kwargs, keywords, kw_idx, pydict, pyunicode);
                if (item) |it| {
                    dest.* = @floatCast(PyFloat_AsDouble(it));
                } else if (!optional) return 0;
                arg_idx += 1;
                kw_idx += 1;
            },

            'O' => {
                const dest = @cVaArg(&va, **cpython.PyObject);
                const item = getArgOrKwarg(tuple, args, arg_idx, kwargs, keywords, kw_idx, pydict, pyunicode);
                if (item) |it| {
                    dest.* = it;
                } else if (!optional) return 0;
                arg_idx += 1;
                kw_idx += 1;
            },

            'p' => {
                // Bool predicate
                const dest = @cVaArg(&va, *c_int);
                const item = getArgOrKwarg(tuple, args, arg_idx, kwargs, keywords, kw_idx, pydict, pyunicode);
                if (item) |it| {
                    dest.* = if (traits.isTruthy(it)) 1 else 0;
                } else if (!optional) return 0;
                arg_idx += 1;
                kw_idx += 1;
            },

            else => {},
        }
    }

    return 1;
}

/// Helper to get argument from positional args or kwargs
fn getArgOrKwarg(
    tuple: *cpython.PyTupleObject,
    args: *cpython.PyObject,
    arg_idx: isize,
    kwargs: ?*cpython.PyObject,
    keywords: [*]const ?[*:0]const u8,
    kw_idx: usize,
    pydict: anytype,
    pyunicode: anytype,
) ?*cpython.PyObject {
    // Try positional first
    if (arg_idx < tuple.ob_base.ob_size) {
        return PyTuple_GetItem(args, arg_idx);
    }

    // Try keyword argument
    if (kwargs) |kw| {
        if (keywords[kw_idx]) |name| {
            const key = pyunicode.PyUnicode_FromString(name) orelse return null;
            defer traits.decref(key);
            return pydict.PyDict_GetItem(kw, key);
        }
    }

    return null;
}

/// Build Python value from C values (inverse of ParseTuple)
export fn Py_BuildValue(format: [*:0]const u8, ...) callconv(.C) ?*cpython.PyObject {
    const pynone = @import("pyobject_none.zig");
    const pyunicode = @import("pyobject_unicode.zig");
    const pybytes = @import("pyobject_bytes.zig");

    const fmt = std.mem.span(format);
    var va = @cVaStart();
    defer @cVaEnd(&va);

    // Simple cases first
    if (fmt.len == 0) {
        // Return None
        return pynone.Py_None();
    }

    if (fmt.len == 1) {
        const c = fmt[0];
        switch (c) {
            'i' => {
                const value = @cVaArg(&va, c_int);
                return PyLong_FromLong(value);
            },
            'l' => {
                const value = @cVaArg(&va, c_long);
                return PyLong_FromLong(value);
            },
            'L' => {
                const value = @cVaArg(&va, c_longlong);
                return traits.externs.PyLong_FromLongLong(value);
            },
            'd' => {
                const value = @cVaArg(&va, f64);
                return PyFloat_FromDouble(value);
            },
            's' => {
                const str = @cVaArg(&va, [*:0]const u8);
                return pyunicode.PyUnicode_FromString(str);
            },
            'y' => {
                const str = @cVaArg(&va, [*:0]const u8);
                return pybytes.PyBytes_FromString(str);
            },
            'O', 'S', 'N' => {
                const value = @cVaArg(&va, *cpython.PyObject);
                Py_INCREF(value);
                return value;
            },
            else => return pynone.Py_None(),
        }
    }

    // Count actual format codes (excluding parentheses)
    var count: usize = 0;
    var in_parens = false;
    for (fmt) |c| {
        switch (c) {
            '(' => in_parens = true,
            ')' => in_parens = false,
            'i', 'l', 'L', 'd', 'f', 's', 'y', 'O', 'S', 'N', 'z' => {
                if (!in_parens) count += 1;
            },
            else => {},
        }
    }

    // Multiple values - create tuple
    const tuple = PyTuple_New(@intCast(count)) orelse return null;

    var arg_idx: isize = 0;
    for (fmt) |c| {
        const item: ?*cpython.PyObject = switch (c) {
            'i' => PyLong_FromLong(@cVaArg(&va, c_int)),
            'l' => PyLong_FromLong(@cVaArg(&va, c_long)),
            'L' => traits.externs.PyLong_FromLongLong(@cVaArg(&va, c_longlong)),
            'd', 'f' => PyFloat_FromDouble(@cVaArg(&va, f64)),
            's', 'z' => pyunicode.PyUnicode_FromString(@cVaArg(&va, [*:0]const u8)),
            'y' => pybytes.PyBytes_FromString(@cVaArg(&va, [*:0]const u8)),
            'O', 'S', 'N' => blk: {
                const obj = @cVaArg(&va, *cpython.PyObject);
                Py_INCREF(obj);
                break :blk obj;
            },
            '(', ')' => continue,
            else => continue,
        };

        if (item) |it| {
            _ = PyTuple_SetItem(tuple, arg_idx, it);
            arg_idx += 1;
        }
    }

    return tuple;
}

// PyLong_AsLongLong is now in traits.externs (pure Zig)

// Tests
test "PyArg_ParseTuple with longs" {
    // Create tuple with two longs
    const tuple = PyTuple_New(2);
    try std.testing.expect(tuple != null);

    const item1 = PyLong_FromLong(42);
    const item2 = PyLong_FromLong(100);

    _ = PyTuple_SetItem(tuple.?, 0, item1.?);
    _ = PyTuple_SetItem(tuple.?, 1, item2.?);

    // Parse it
    var a: c_long = undefined;
    var b: c_long = undefined;

    const result = PyArg_ParseTuple(tuple.?, "ll", &a, &b);
    try std.testing.expectEqual(@as(c_int, 1), result);
    try std.testing.expectEqual(@as(c_long, 42), a);
    try std.testing.expectEqual(@as(c_long, 100), b);
}

test "PyArg_ParseTuple with optional" {
    // Create tuple with one long
    const tuple = PyTuple_New(1);
    try std.testing.expect(tuple != null);

    const item = PyLong_FromLong(42);
    _ = PyTuple_SetItem(tuple.?, 0, item.?);

    // Parse with optional second arg
    var a: c_long = undefined;
    var b: c_long = 999; // Default value

    const result = PyArg_ParseTuple(tuple.?, "l|l", &a, &b);
    try std.testing.expectEqual(@as(c_int, 1), result);
    try std.testing.expectEqual(@as(c_long, 42), a);
    try std.testing.expectEqual(@as(c_long, 999), b); // Should remain default
}

test "Py_BuildValue creates tuple" {
    const result = Py_BuildValue("ll", @as(c_long, 10), @as(c_long, 20));
    try std.testing.expect(result != null);

    const size = cpython.Py_SIZE(@as(*cpython.PyVarObject, @ptrCast(result.?)));
    try std.testing.expectEqual(@as(isize, 2), size);
}
