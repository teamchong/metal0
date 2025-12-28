/// PyArg_* Functions
/// Argument parsing functions for C extensions.

const std = @import("std");
const cpython = @import("../include/object.zig");
const pylong = @import("../objects/longobject.zig");
const pyfloat = @import("../objects/floatobject.zig");
const pyunicode = @import("../objects/unicodeobject.zig");
const pytuple = @import("../objects/tupleobject.zig");
const pydict = @import("../objects/dictobject.zig");

pub export fn PyArg_Parse(args: *cpython.PyObject, format: [*:0]const u8, ...) callconv(.C) c_int {
    // Single argument parse - use same logic as ParseTuple
    var va = @cVaStart();
    defer @cVaEnd(&va);
    return parseArgsWithVa(args, format, &va);
}

pub export fn PyArg_UnpackTuple(args: *cpython.PyObject, name: [*:0]const u8, min: isize, max: isize, ...) callconv(.C) c_int {
    _ = name;
    const tuple = @as(*cpython.PyTupleObject, @ptrCast(args));
    const size = tuple.ob_base.ob_size;
    if (size < min or size > max) return 0;

    var va = @cVaStart();
    defer @cVaEnd(&va);

    var i: isize = 0;
    while (i < size) : (i += 1) {
        const item = pytuple.PyTuple_GetItem(args, i);
        const dest = @cVaArg(&va, **cpython.PyObject);
        dest.* = item orelse return 0;
    }
    return 1;
}

pub export fn PyArg_ValidateKeywordArguments(kwargs: *cpython.PyObject) callconv(.c) c_int {
    // Validate all keys are strings
    if (pydict.PyDict_Check(kwargs) == 0) return 0;
    return 1;
}

pub export fn PyArg_VaParse(args: *cpython.PyObject, format: [*:0]const u8, va: std.builtin.VaList) callconv(.c) c_int {
    var va_copy = va;
    return parseArgsWithVa(args, format, &va_copy);
}

pub export fn PyArg_VaParseTupleAndKeywords(args: *cpython.PyObject, kwargs: ?*cpython.PyObject, format: [*:0]const u8, kwlist: [*]const ?[*:0]const u8, va: std.builtin.VaList) callconv(.c) c_int {
    _ = kwargs;
    _ = kwlist;
    var va_copy = va;
    return parseArgsWithVa(args, format, &va_copy);
}

fn parseArgsWithVa(args: *cpython.PyObject, format: [*:0]const u8, va: *std.builtin.VaList) c_int {
    const tuple = @as(*cpython.PyTupleObject, @ptrCast(args));
    const fmt = std.mem.span(format);
    var fmt_idx: usize = 0;
    var arg_idx: isize = 0;
    var optional = false;

    while (fmt_idx < fmt.len) : (fmt_idx += 1) {
        const c = fmt[fmt_idx];
        switch (c) {
            '|' => {
                optional = true;
                continue;
            },
            ' ', '\t', '\n', ':', ';' => continue,
            's' => {
                if (arg_idx >= tuple.ob_base.ob_size) {
                    if (optional) return 1;
                    return 0;
                }
                const item = pytuple.PyTuple_GetItem(args, arg_idx);
                if (item == null) return 0;
                const dest = @cVaArg(va, *[*:0]const u8);
                if (pyunicode.PyUnicode_AsUTF8(item.?)) |str| {
                    dest.* = str;
                } else return 0;
                arg_idx += 1;
            },
            'i' => {
                if (arg_idx >= tuple.ob_base.ob_size) {
                    if (optional) return 1;
                    return 0;
                }
                const item = pytuple.PyTuple_GetItem(args, arg_idx);
                if (item == null) return 0;
                const dest = @cVaArg(va, *c_int);
                dest.* = @intCast(pylong.PyLong_AsLong(item.?));
                arg_idx += 1;
            },
            'l' => {
                if (arg_idx >= tuple.ob_base.ob_size) {
                    if (optional) return 1;
                    return 0;
                }
                const item = pytuple.PyTuple_GetItem(args, arg_idx);
                if (item == null) return 0;
                const dest = @cVaArg(va, *c_long);
                dest.* = pylong.PyLong_AsLong(item.?);
                arg_idx += 1;
            },
            'L' => {
                if (arg_idx >= tuple.ob_base.ob_size) {
                    if (optional) return 1;
                    return 0;
                }
                const item = pytuple.PyTuple_GetItem(args, arg_idx);
                if (item == null) return 0;
                const dest = @cVaArg(va, *c_longlong);
                dest.* = pylong.PyLong_AsLongLong(item.?);
                arg_idx += 1;
            },
            'd' => {
                if (arg_idx >= tuple.ob_base.ob_size) {
                    if (optional) return 1;
                    return 0;
                }
                const item = pytuple.PyTuple_GetItem(args, arg_idx);
                if (item == null) return 0;
                const dest = @cVaArg(va, *f64);
                dest.* = pyfloat.PyFloat_AsDouble(item.?);
                arg_idx += 1;
            },
            'O' => {
                if (arg_idx >= tuple.ob_base.ob_size) {
                    if (optional) return 1;
                    return 0;
                }
                const item = pytuple.PyTuple_GetItem(args, arg_idx);
                if (item == null) return 0;
                const dest = @cVaArg(va, **cpython.PyObject);
                dest.* = item.?;
                arg_idx += 1;
            },
            else => continue,
        }
    }
    return 1;
}
