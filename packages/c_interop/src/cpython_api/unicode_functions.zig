/// PyUnicode_* Functions
/// Unicode string manipulation and encoding/decoding.

const std = @import("std");
const cpython = @import("../include/object.zig");
const pyunicode = @import("../objects/unicodeobject.zig");
const pybytes = @import("../objects/bytesobject.zig");
const pybool = @import("../objects/boolobject.zig");
const pylist = @import("../objects/listobject.zig");
const pytuple = @import("../objects/tupleobject.zig");
const pydict = @import("../objects/dictobject.zig");
const pylong = @import("../objects/longobject.zig");
const traits = @import("../objects/typetraits.zig");

pub export fn PyUnicode_Append(p_left: *?*cpython.PyObject, right: *cpython.PyObject) callconv(.c) void {
    if (p_left.*) |left| {
        const left_str = pyunicode.PyUnicode_AsUTF8(left) orelse return;
        const right_str = pyunicode.PyUnicode_AsUTF8(right) orelse return;
        const left_len = std.mem.len(left_str);
        const right_len = std.mem.len(right_str);
        const total = left_len + right_len;
        const buf = std.heap.c_allocator.alloc(u8, total + 1) catch return;
        @memcpy(buf[0..left_len], left_str[0..left_len]);
        @memcpy(buf[left_len..total], right_str[0..right_len]);
        buf[total] = 0;
        traits.decref(left);
        p_left.* = pyunicode.PyUnicode_FromString(@ptrCast(buf.ptr));
    }
}

pub export fn PyUnicode_AppendAndDel(p_left: *?*cpython.PyObject, right: *cpython.PyObject) callconv(.c) void {
    PyUnicode_Append(p_left, right);
    traits.decref(right);
}

pub export fn PyUnicode_AsCharmapString(str_obj: *cpython.PyObject, mapping: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = mapping;
    const str = pyunicode.PyUnicode_AsUTF8(str_obj) orelse return null;
    return pybytes.PyBytes_FromString(str);
}

pub export fn PyUnicode_AsEncodedString(str_obj: *cpython.PyObject, encoding: ?[*:0]const u8, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = encoding;
    _ = errors;
    const str = pyunicode.PyUnicode_AsUTF8(str_obj) orelse return null;
    return pybytes.PyBytes_FromString(str);
}

pub export fn PyUnicode_AsMBCSString(str_obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const str = pyunicode.PyUnicode_AsUTF8(str_obj) orelse return null;
    return pybytes.PyBytes_FromString(str);
}

pub export fn PyUnicode_AsRawUnicodeEscapeString(str_obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const str = pyunicode.PyUnicode_AsUTF8(str_obj) orelse return null;
    return pybytes.PyBytes_FromString(str);
}

pub export fn PyUnicode_AsUnicodeEscapeString(str_obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const str = pyunicode.PyUnicode_AsUTF8(str_obj) orelse return null;
    return pybytes.PyBytes_FromString(str);
}

pub export fn PyUnicode_AsWideChar(str_obj: *cpython.PyObject, w: [*]u16, size: isize) callconv(.c) isize {
    const str = pyunicode.PyUnicode_AsUTF8(str_obj) orelse return -1;
    var i: usize = 0;
    const max: usize = @intCast(size);
    while (i < max and str[i] != 0) : (i += 1) {
        w[i] = str[i];
    }
    return @intCast(i);
}

pub export fn PyUnicode_AsWideCharString(str_obj: *cpython.PyObject, size: ?*isize) callconv(.c) ?[*]u16 {
    const str = pyunicode.PyUnicode_AsUTF8(str_obj) orelse return null;
    const len = std.mem.len(str);
    const buf = std.heap.c_allocator.alloc(u16, len + 1) catch return null;
    for (str[0..len], 0..) |c, i| {
        buf[i] = c;
    }
    buf[len] = 0;
    if (size) |s| s.* = @intCast(len);
    return buf.ptr;
}

pub export fn PyUnicode_BuildEncodingMap(string: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const str = pyunicode.PyUnicode_AsUTF8(string) orelse return null;
    const len = pyunicode.PyUnicode_GetLength(string);

    const dict = pydict.PyDict_New() orelse return null;

    var i: isize = 0;
    while (i < len and i < 256) : (i += 1) {
        const ch = str[@intCast(i)];
        if (ch != 0) {
            var char_buf: [2]u8 = .{ ch, 0 };
            const key = pyunicode.PyUnicode_FromString(@ptrCast(&char_buf)) orelse continue;
            const val = pylong.PyLong_FromLong(@intCast(i));
            if (val) |v| {
                _ = pydict.PyDict_SetItem(dict, key, v);
            }
        }
    }

    return dict;
}

pub export fn PyUnicode_CompareWithASCIIString(left: *cpython.PyObject, right: [*:0]const u8) callconv(.c) c_int {
    const left_str = pyunicode.PyUnicode_AsUTF8(left) orelse return -1;
    var i: usize = 0;
    while (left_str[i] != 0 and right[i] != 0) : (i += 1) {
        if (left_str[i] != right[i]) return @as(c_int, left_str[i]) - @as(c_int, right[i]);
    }
    return @as(c_int, left_str[i]) - @as(c_int, right[i]);
}

pub export fn PyUnicode_Decode(s: [*]const u8, size: isize, encoding: ?[*:0]const u8, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = encoding;
    _ = errors;
    return pyunicode.PyUnicode_FromStringAndSize(s, size);
}

pub export fn PyUnicode_DecodeCharmap(s: [*]const u8, size: isize, mapping: ?*cpython.PyObject, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = mapping;
    _ = errors;
    return pyunicode.PyUnicode_FromStringAndSize(s, size);
}

pub export fn PyUnicode_DecodeCodePageStateful(code_page: c_int, s: [*]const u8, size: isize, errors: ?[*:0]const u8, consumed: ?*isize) callconv(.c) ?*cpython.PyObject {
    _ = code_page;
    _ = errors;
    if (consumed) |c| c.* = size;
    return pyunicode.PyUnicode_FromStringAndSize(s, size);
}

pub export fn PyUnicode_DecodeFSDefault(s: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    return pyunicode.PyUnicode_FromString(s);
}

pub export fn PyUnicode_DecodeFSDefaultAndSize(s: [*]const u8, size: isize) callconv(.c) ?*cpython.PyObject {
    return pyunicode.PyUnicode_FromStringAndSize(s, size);
}

pub export fn PyUnicode_DecodeMBCS(s: [*]const u8, size: isize, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = errors;
    return pyunicode.PyUnicode_FromStringAndSize(s, size);
}

pub export fn PyUnicode_DecodeMBCSStateful(s: [*]const u8, size: isize, errors: ?[*:0]const u8, consumed: ?*isize) callconv(.c) ?*cpython.PyObject {
    _ = errors;
    if (consumed) |c| c.* = size;
    return pyunicode.PyUnicode_FromStringAndSize(s, size);
}

pub export fn PyUnicode_DecodeRawUnicodeEscape(s: [*]const u8, size: isize, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = errors;
    return pyunicode.PyUnicode_FromStringAndSize(s, size);
}

pub export fn PyUnicode_DecodeUnicodeEscape(s: [*]const u8, size: isize, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = errors;
    return pyunicode.PyUnicode_FromStringAndSize(s, size);
}

pub export fn PyUnicode_EncodeCodePage(code_page: c_int, str_obj: *cpython.PyObject, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = code_page;
    _ = errors;
    const str = pyunicode.PyUnicode_AsUTF8(str_obj) orelse return null;
    return pybytes.PyBytes_FromString(str);
}

pub export fn PyUnicode_EncodeFSDefault(str_obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const str = pyunicode.PyUnicode_AsUTF8(str_obj) orelse return null;
    return pybytes.PyBytes_FromString(str);
}

pub export fn PyUnicode_Equal(left: *cpython.PyObject, right: *cpython.PyObject) callconv(.c) c_int {
    const left_str = pyunicode.PyUnicode_AsUTF8(left) orelse return -1;
    const right_str = pyunicode.PyUnicode_AsUTF8(right) orelse return -1;
    return if (std.mem.eql(u8, std.mem.span(left_str), std.mem.span(right_str))) 1 else 0;
}

pub export fn PyUnicode_FindChar(str: *cpython.PyObject, ch: u32, start: isize, end: isize, direction: c_int) callconv(.c) isize {
    const s = pyunicode.PyUnicode_AsUTF8(str) orelse return -2;
    const len = @as(isize, @intCast(std.mem.len(s)));
    const real_start: usize = @intCast(@max(0, start));
    const real_end: usize = @intCast(@min(len, end));
    if (direction >= 0) {
        for (real_start..real_end) |i| {
            if (s[i] == @as(u8, @intCast(ch & 0xFF))) return @intCast(i);
        }
    } else {
        var i = real_end;
        while (i > real_start) {
            i -= 1;
            if (s[i] == @as(u8, @intCast(ch & 0xFF))) return @intCast(i);
        }
    }
    return -1;
}

pub export fn PyUnicode_FromEncodedObject(obj: *cpython.PyObject, encoding: ?[*:0]const u8, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = encoding;
    _ = errors;
    if (pybytes.PyBytes_Check(obj) != 0) {
        const data = pybytes.PyBytes_AsString(obj) orelse return null;
        return pyunicode.PyUnicode_FromString(data);
    }
    return null;
}

pub export fn PyUnicode_FromFormat(format: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    return pyunicode.PyUnicode_FromString(format);
}

pub export fn PyUnicode_FromFormatV(format: [*:0]const u8, va: std.builtin.VaList) callconv(.c) ?*cpython.PyObject {
    const fmt = std.mem.span(format);
    var va_copy = va;

    var buf: [4096]u8 = undefined;
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
                'S', 'R', 'A', 'U' => {
                    const obj = @cVaArg(&va_copy, *cpython.PyObject);
                    if (pyunicode.PyUnicode_AsUTF8(obj)) |str| {
                        const str_slice = std.mem.span(str);
                        const copy_len = @min(str_slice.len, buf.len - buf_idx - 1);
                        @memcpy(buf[buf_idx .. buf_idx + copy_len], str_slice[0..copy_len]);
                        buf_idx += copy_len;
                    }
                },
                'd', 'i' => {
                    const val = @cVaArg(&va_copy, c_int);
                    const result = std.fmt.bufPrint(buf[buf_idx..], "{d}", .{val}) catch break;
                    buf_idx += result.len;
                },
                'l' => {
                    if (fmt_idx + 1 < fmt.len and (fmt[fmt_idx + 1] == 'd' or fmt[fmt_idx + 1] == 'i')) {
                        fmt_idx += 1;
                        const val = @cVaArg(&va_copy, c_long);
                        const result = std.fmt.bufPrint(buf[buf_idx..], "{d}", .{val}) catch break;
                        buf_idx += result.len;
                    }
                },
                'u' => {
                    const val = @cVaArg(&va_copy, c_uint);
                    const result = std.fmt.bufPrint(buf[buf_idx..], "{d}", .{val}) catch break;
                    buf_idx += result.len;
                },
                'x' => {
                    const val = @cVaArg(&va_copy, c_int);
                    const result = std.fmt.bufPrint(buf[buf_idx..], "{x}", .{val}) catch break;
                    buf_idx += result.len;
                },
                'p' => {
                    const val = @cVaArg(&va_copy, usize);
                    const result = std.fmt.bufPrint(buf[buf_idx..], "0x{x}", .{val}) catch break;
                    buf_idx += result.len;
                },
                'c' => {
                    const val = @cVaArg(&va_copy, c_int);
                    if (buf_idx < buf.len - 1) {
                        buf[buf_idx] = @intCast(val & 0xFF);
                        buf_idx += 1;
                    }
                },
                '%' => {
                    if (buf_idx < buf.len - 1) {
                        buf[buf_idx] = '%';
                        buf_idx += 1;
                    }
                },
                else => {
                    if (buf_idx < buf.len - 2) {
                        buf[buf_idx] = '%';
                        buf[buf_idx + 1] = fmt[fmt_idx];
                        buf_idx += 2;
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

    return pyunicode.PyUnicode_FromStringAndSize(&buf, @intCast(buf_idx));
}

pub export fn PyUnicode_FromObject(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (pyunicode.PyUnicode_Check(obj) != 0) {
        traits.incref(obj);
        return obj;
    }
    return null;
}

pub export fn PyUnicode_FromOrdinal(ordinal: c_int) callconv(.c) ?*cpython.PyObject {
    var buf: [5]u8 = undefined;
    const len = std.unicode.utf8Encode(@intCast(ordinal), &buf) catch return null;
    buf[len] = 0;
    return pyunicode.PyUnicode_FromString(@ptrCast(&buf));
}

pub export fn PyUnicode_FromWideChar(w: [*]const u16, size: isize) callconv(.c) ?*cpython.PyObject {
    const len: usize = if (size < 0) blk: {
        var i: usize = 0;
        while (w[i] != 0) : (i += 1) {}
        break :blk i;
    } else @intCast(size);
    const buf = std.heap.c_allocator.alloc(u8, len + 1) catch return null;
    for (0..len) |i| {
        buf[i] = @intCast(w[i] & 0xFF);
    }
    buf[len] = 0;
    return pyunicode.PyUnicode_FromString(@ptrCast(buf.ptr));
}

pub export fn PyUnicode_FSConverter(obj: *cpython.PyObject, result: *?*cpython.PyObject) callconv(.c) c_int {
    result.* = PyUnicode_EncodeFSDefault(obj);
    return if (result.* != null) 1 else 0;
}

pub export fn PyUnicode_FSDecoder(obj: *cpython.PyObject, result: *?*cpython.PyObject) callconv(.c) c_int {
    if (pyunicode.PyUnicode_Check(obj) != 0) {
        traits.incref(obj);
        result.* = obj;
        return 1;
    }
    if (pybytes.PyBytes_Check(obj) != 0) {
        const data = pybytes.PyBytes_AsString(obj) orelse return 0;
        result.* = pyunicode.PyUnicode_FromString(data);
        return if (result.* != null) 1 else 0;
    }
    return 0;
}

pub export fn PyUnicode_GetDefaultEncoding() callconv(.c) [*:0]const u8 {
    return "utf-8";
}

pub export fn PyUnicode_InternFromString(str: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    return pyunicode.PyUnicode_FromString(str);
}

pub export fn PyUnicode_InternInPlace(p_unicode: *?*cpython.PyObject) callconv(.c) void {
    _ = p_unicode;
}

pub export fn PyUnicode_IsIdentifier(str: *cpython.PyObject) callconv(.c) c_int {
    const s = pyunicode.PyUnicode_AsUTF8(str) orelse return 0;
    if (s[0] == 0) return 0;
    if (!std.ascii.isAlphabetic(s[0]) and s[0] != '_') return 0;
    var i: usize = 1;
    while (s[i] != 0) : (i += 1) {
        if (!std.ascii.isAlphanumeric(s[i]) and s[i] != '_') return 0;
    }
    return 1;
}

pub export fn PyUnicode_Partition(str: *cpython.PyObject, sep: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const s = pyunicode.PyUnicode_AsUTF8(str) orelse return null;
    const sep_str = pyunicode.PyUnicode_AsUTF8(sep) orelse return null;
    const s_len = std.mem.len(s);
    const sep_len = std.mem.len(sep_str);

    if (std.mem.indexOf(u8, s[0..s_len], sep_str[0..sep_len])) |pos| {
        const result = pytuple.PyTuple_New(3) orelse return null;
        _ = pytuple.PyTuple_SetItem(result, 0, pyunicode.PyUnicode_FromStringAndSize(s, @intCast(pos)) orelse return null);
        _ = pytuple.PyTuple_SetItem(result, 1, pyunicode.PyUnicode_FromString(sep_str) orelse return null);
        _ = pytuple.PyTuple_SetItem(result, 2, pyunicode.PyUnicode_FromString(s + pos + sep_len) orelse return null);
        return result;
    } else {
        const result = pytuple.PyTuple_New(3) orelse return null;
        traits.incref(str);
        _ = pytuple.PyTuple_SetItem(result, 0, str);
        _ = pytuple.PyTuple_SetItem(result, 1, pyunicode.PyUnicode_FromString("") orelse return null);
        _ = pytuple.PyTuple_SetItem(result, 2, pyunicode.PyUnicode_FromString("") orelse return null);
        return result;
    }
}

pub export fn PyUnicode_ReadChar(str_obj: *cpython.PyObject, index: isize) callconv(.c) u32 {
    const s = pyunicode.PyUnicode_AsUTF8(str_obj) orelse return 0xFFFFFFFF;
    if (index < 0) return 0xFFFFFFFF;
    const i: usize = @intCast(index);
    return s[i];
}

pub export fn PyUnicode_Resize(p_unicode: *?*cpython.PyObject, length: isize) callconv(.c) c_int {
    _ = p_unicode;
    _ = length;
    return 0;
}

pub export fn PyUnicode_RichCompare(left: *cpython.PyObject, right: *cpython.PyObject, op: c_int) callconv(.c) ?*cpython.PyObject {
    const cmp = PyUnicode_CompareWithASCIIString(left, pyunicode.PyUnicode_AsUTF8(right) orelse return null);
    const result = switch (op) {
        0 => cmp < 0, // Py_LT
        1 => cmp <= 0, // Py_LE
        2 => cmp == 0, // Py_EQ
        3 => cmp != 0, // Py_NE
        4 => cmp > 0, // Py_GT
        5 => cmp >= 0, // Py_GE
        else => false,
    };
    return if (result) @ptrCast(&pybool._Py_TrueStruct) else @ptrCast(&pybool._Py_FalseStruct);
}

pub export fn PyUnicode_RPartition(str: *cpython.PyObject, sep: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const s = pyunicode.PyUnicode_AsUTF8(str) orelse return null;
    const sep_str = pyunicode.PyUnicode_AsUTF8(sep) orelse return null;
    const s_len = std.mem.len(s);
    const sep_len = std.mem.len(sep_str);

    if (std.mem.lastIndexOf(u8, s[0..s_len], sep_str[0..sep_len])) |pos| {
        const result = pytuple.PyTuple_New(3) orelse return null;
        _ = pytuple.PyTuple_SetItem(result, 0, pyunicode.PyUnicode_FromStringAndSize(s, @intCast(pos)) orelse return null);
        _ = pytuple.PyTuple_SetItem(result, 1, pyunicode.PyUnicode_FromString(sep_str) orelse return null);
        _ = pytuple.PyTuple_SetItem(result, 2, pyunicode.PyUnicode_FromString(s + pos + sep_len) orelse return null);
        return result;
    } else {
        const result = pytuple.PyTuple_New(3) orelse return null;
        _ = pytuple.PyTuple_SetItem(result, 0, pyunicode.PyUnicode_FromString("") orelse return null);
        _ = pytuple.PyTuple_SetItem(result, 1, pyunicode.PyUnicode_FromString("") orelse return null);
        traits.incref(str);
        _ = pytuple.PyTuple_SetItem(result, 2, str);
        return result;
    }
}

pub export fn PyUnicode_RSplit(str: *cpython.PyObject, sep: ?*cpython.PyObject, maxsplit: isize) callconv(.c) ?*cpython.PyObject {
    const s = pyunicode.PyUnicode_AsUTF8(str) orelse return null;
    const s_len = std.mem.len(s);
    const result = pylist.PyList_New(0) orelse return null;

    if (sep) |sep_obj| {
        const sep_str = pyunicode.PyUnicode_AsUTF8(sep_obj) orelse return null;
        const sep_len = std.mem.len(sep_str);

        var splits: isize = 0;
        var end: usize = s_len;

        while (end > 0 and (maxsplit < 0 or splits < maxsplit)) {
            if (std.mem.lastIndexOf(u8, s[0..end], sep_str[0..sep_len])) |pos| {
                const part = pyunicode.PyUnicode_FromStringAndSize(s + pos + sep_len, @intCast(end - pos - sep_len)) orelse return null;
                _ = pylist.PyList_Insert(result, 0, part);
                end = pos;
                splits += 1;
            } else break;
        }

        if (end > 0) {
            const part = pyunicode.PyUnicode_FromStringAndSize(s, @intCast(end)) orelse return null;
            _ = pylist.PyList_Insert(result, 0, part);
        }
    } else {
        traits.incref(str);
        _ = pylist.PyList_Append(result, str);
    }

    return result;
}

pub export fn PyUnicode_Splitlines(str: *cpython.PyObject, keepends: c_int) callconv(.c) ?*cpython.PyObject {
    const s = pyunicode.PyUnicode_AsUTF8(str) orelse return null;
    const s_len = std.mem.len(s);
    const result = pylist.PyList_New(0) orelse return null;

    var start: usize = 0;
    var i: usize = 0;
    while (i < s_len) : (i += 1) {
        const c = s[i];
        const is_newline = c == '\n' or c == '\r';
        if (is_newline) {
            const end = i;
            if (c == '\r' and i + 1 < s_len and s[i + 1] == '\n') {
                i += 1;
            }

            const line_end = if (keepends != 0) i + 1 else end;
            const line = pyunicode.PyUnicode_FromStringAndSize(s + start, @intCast(line_end - start)) orelse return null;
            _ = pylist.PyList_Append(result, line);
            start = i + 1;
        }
    }

    if (start < s_len) {
        const line = pyunicode.PyUnicode_FromStringAndSize(s + start, @intCast(s_len - start)) orelse return null;
        _ = pylist.PyList_Append(result, line);
    }

    return result;
}

pub export fn PyUnicode_Translate(str: *cpython.PyObject, table: *cpython.PyObject, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = table;
    _ = errors;
    traits.incref(str);
    return str;
}

pub export fn PyUnicode_WriteChar(str_obj: *cpython.PyObject, index: isize, ch: u32) callconv(.c) c_int {
    _ = str_obj;
    _ = index;
    _ = ch;
    return -1; // Immutable
}
