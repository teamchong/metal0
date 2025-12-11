/// PyBuffer_* and PyBytes_* Functions
/// Buffer protocol and bytes object manipulation.

const std = @import("std");
const cpython = @import("../include/object.zig");
const pybytes = @import("../objects/bytesobject.zig");
const traits = @import("../objects/typetraits.zig");

// --- PyBuffer_* Functions ---

export fn PyBuffer_FromContiguous(view: *cpython.Py_buffer, buf: [*]const u8, len: isize, order: u8) callconv(.c) c_int {
    _ = order;
    if (view.buf) |dest| {
        @memcpy(@as([*]u8, @ptrCast(dest))[0..@intCast(len)], buf[0..@intCast(len)]);
    }
    return 0;
}

export fn PyBuffer_ToContiguous(buf: [*]u8, view: *const cpython.Py_buffer, len: isize, order: u8) callconv(.c) c_int {
    _ = order;
    if (view.buf) |src| {
        @memcpy(buf[0..@intCast(len)], @as([*]const u8, @ptrCast(src))[0..@intCast(len)]);
    }
    return 0;
}

// --- PyBytes_* Functions ---

export fn PyBytes_DecodeEscape(s: [*]const u8, len: isize, errors: ?[*:0]const u8, is_unicode: c_int, recode_encoding: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = errors;
    _ = is_unicode;
    _ = recode_encoding;
    return pybytes.PyBytes_FromStringAndSize(s, len);
}

export fn PyBytes_FromFormatV(format: [*:0]const u8, va: std.builtin.VaList) callconv(.c) ?*cpython.PyObject {
    // Format string similar to printf, output as bytes
    const fmt = std.mem.span(format);
    var va_copy = va;

    var buf: [1024]u8 = undefined;
    var buf_idx: usize = 0;
    var fmt_idx: usize = 0;

    while (fmt_idx < fmt.len and buf_idx < buf.len - 1) {
        if (fmt[fmt_idx] == '%' and fmt_idx + 1 < fmt.len) {
            fmt_idx += 1;
            switch (fmt[fmt_idx]) {
                's' => {
                    const str = @cVaArg(&va_copy, [*:0]const u8);
                    const str_slice = std.mem.span(str);
                    const copy_len = @min(str_slice.len, buf.len - buf_idx - 1);
                    @memcpy(buf[buf_idx .. buf_idx + copy_len], str_slice[0..copy_len]);
                    buf_idx += copy_len;
                },
                'd', 'i' => {
                    const val = @cVaArg(&va_copy, c_int);
                    const result = std.fmt.bufPrint(buf[buf_idx..], "{d}", .{val}) catch break;
                    buf_idx += result.len;
                },
                'x' => {
                    const val = @cVaArg(&va_copy, c_int);
                    const result = std.fmt.bufPrint(buf[buf_idx..], "{x}", .{val}) catch break;
                    buf_idx += result.len;
                },
                'c' => {
                    const val: u8 = @intCast(@cVaArg(&va_copy, c_int));
                    buf[buf_idx] = val;
                    buf_idx += 1;
                },
                '%' => {
                    buf[buf_idx] = '%';
                    buf_idx += 1;
                },
                else => {
                    buf[buf_idx] = '%';
                    buf_idx += 1;
                    if (buf_idx < buf.len - 1) {
                        buf[buf_idx] = fmt[fmt_idx];
                        buf_idx += 1;
                    }
                },
            }
            fmt_idx += 1;
        } else {
            buf[buf_idx] = fmt[fmt_idx];
            buf_idx += 1;
            fmt_idx += 1;
        }
    }

    return pybytes.PyBytes_FromStringAndSize(@ptrCast(&buf), @intCast(buf_idx));
}

export fn PyBytes_FromObject(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // If already bytes, incref and return
    if (pybytes.PyBytes_Check(obj) != 0) {
        traits.incref(obj);
        return obj;
    }
    // Try buffer protocol or encode string
    return null;
}
