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

// Use centralized extern declarations
const Py_INCREF = traits.externs.Py_INCREF;
const PyLong_FromLong = traits.externs.PyLong_FromLong;
const PyTuple_New = traits.externs.PyTuple_New;
const PyTuple_GetItem = traits.externs.PyTuple_GetItem;
const PyTuple_SetItem = traits.externs.PyTuple_SetItem;

// Float operations (need local externs - not in traits yet)
extern fn PyFloat_AsDouble(*cpython.PyObject) callconv(.C) f64;
extern fn PyFloat_FromDouble(f64) callconv(.C) ?*cpython.PyObject;
extern fn PyLong_AsLong(*cpython.PyObject) callconv(.C) c_long;
extern fn PyUnicode_AsUTF8(*cpython.PyObject) callconv(.C) ?[*:0]const u8;

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

                // TODO: Extract actual string
                // For now, just get the pointer destination
                const dest = @cVaArg(&va, *[*:0]const u8);
                _ = dest;
                _ = item;

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
    keywords: [*]const [*:0]const u8,
    ...
) callconv(.C) c_int {
    // For now, ignore keywords and just parse tuple
    _ = kwargs;
    _ = keywords;

    // Forward to PyArg_ParseTuple
    // TODO: Implement keyword argument parsing
    var va = @cVaStart();
    defer @cVaEnd(&va);

    // This is a simplified implementation
    // Real implementation would parse keywords from kwargs dict
    return PyArg_ParseTuple(args, format, va);
}

/// Build Python value from C values (inverse of ParseTuple)
export fn Py_BuildValue(format: [*:0]const u8, ...) callconv(.C) ?*cpython.PyObject {
    const fmt = std.mem.span(format);
    var va = @cVaStart();
    defer @cVaEnd(&va);

    // Simple cases first
    if (fmt.len == 0) {
        // Return None
        // TODO: Proper None singleton
        return null;
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
            'd' => {
                const value = @cVaArg(&va, f64);
                return PyFloat_FromDouble(value);
            },
            'O' => {
                const value = @cVaArg(&va, *cpython.PyObject);
                // Increment refcount (borrowed → owned)
                Py_INCREF(value);
                return value;
            },
            else => return null,
        }
    }

    // Multiple values - create tuple
    const size: isize = @intCast(fmt.len);
    const tuple = PyTuple_New(size);
    if (tuple == null) return null;

    for (fmt, 0..) |c, i| {
        const item: ?*cpython.PyObject = switch (c) {
            'i' => PyLong_FromLong(@cVaArg(&va, c_int)),
            'l' => PyLong_FromLong(@cVaArg(&va, c_long)),
            'd' => PyFloat_FromDouble(@cVaArg(&va, f64)),
            'O' => blk: {
                const obj = @cVaArg(&va, *cpython.PyObject);
                Py_INCREF(obj);
                break :blk obj;
            },
            else => null,
        };

        if (item == null) {
            // TODO: Proper cleanup
            return null;
        }

        const idx: isize = @intCast(i);
        _ = PyTuple_SetItem(tuple.?, idx, item.?);
    }

    return tuple;
}

// PyLong_AsLongLong is not in traits yet
extern fn PyLong_AsLongLong(*cpython.PyObject) callconv(.C) c_longlong;

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
