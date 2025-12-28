/// PyUnicodeDecodeError_*, PyUnicodeEncodeError_*, PyUnicodeTranslateError_* Functions
/// Unicode error object manipulation.

const std = @import("std");
const cpython = @import("../include/object.zig");
const pyunicode = @import("../objects/unicodeobject.zig");
const pybytes = @import("../objects/bytesobject.zig");
const exceptions = @import("../objects/exceptions.zig");
const traits = @import("../objects/typetraits.zig");

/// Structure for Unicode error objects
pub const PyUnicodeErrorObject = extern struct {
    ob_base: cpython.PyObject,
    encoding: ?*cpython.PyObject,
    object: ?*cpython.PyObject,
    start: isize,
    end: isize,
    reason: ?*cpython.PyObject,
};

// --- PyUnicodeDecodeError_* ---

pub export fn PyUnicodeDecodeError_Create(encoding: [*:0]const u8, object: [*]const u8, length: isize, start: isize, end: isize, reason: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    const err_obj = std.heap.c_allocator.create(PyUnicodeErrorObject) catch return null;
    err_obj.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &exceptions.PyExc_UnicodeDecodeError,
        },
        .encoding = pyunicode.PyUnicode_FromString(encoding),
        .object = pybytes.PyBytes_FromStringAndSize(object, length),
        .start = start,
        .end = end,
        .reason = pyunicode.PyUnicode_FromString(reason),
    };
    return @ptrCast(err_obj);
}

pub export fn PyUnicodeDecodeError_GetEncoding(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    if (err_obj.encoding) |enc| {
        traits.incref(enc);
        return enc;
    }
    return pyunicode.PyUnicode_FromString("utf-8");
}

pub export fn PyUnicodeDecodeError_GetEnd(exc: *cpython.PyObject, end: *isize) callconv(.c) c_int {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    end.* = err_obj.end;
    return 0;
}

pub export fn PyUnicodeDecodeError_GetObject(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    if (err_obj.object) |obj| {
        traits.incref(obj);
        return obj;
    }
    return null;
}

pub export fn PyUnicodeDecodeError_GetReason(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    if (err_obj.reason) |r| {
        traits.incref(r);
        return r;
    }
    return pyunicode.PyUnicode_FromString("decode error");
}

pub export fn PyUnicodeDecodeError_GetStart(exc: *cpython.PyObject, start: *isize) callconv(.c) c_int {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    start.* = err_obj.start;
    return 0;
}

pub export fn PyUnicodeDecodeError_SetEnd(exc: *cpython.PyObject, end: isize) callconv(.c) c_int {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    err_obj.end = end;
    return 0;
}

pub export fn PyUnicodeDecodeError_SetReason(exc: *cpython.PyObject, reason: *cpython.PyObject) callconv(.c) c_int {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    if (err_obj.reason) |old| {
        traits.decref(old);
    }
    traits.incref(reason);
    err_obj.reason = reason;
    return 0;
}

pub export fn PyUnicodeDecodeError_SetStart(exc: *cpython.PyObject, start: isize) callconv(.c) c_int {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    err_obj.start = start;
    return 0;
}

// --- PyUnicodeEncodeError_* ---

pub export fn PyUnicodeEncodeError_GetEncoding(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    if (err_obj.encoding) |enc| {
        traits.incref(enc);
        return enc;
    }
    return pyunicode.PyUnicode_FromString("utf-8");
}

pub export fn PyUnicodeEncodeError_GetEnd(exc: *cpython.PyObject, end: *isize) callconv(.c) c_int {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    end.* = err_obj.end;
    return 0;
}

pub export fn PyUnicodeEncodeError_GetObject(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    if (err_obj.object) |obj| {
        traits.incref(obj);
        return obj;
    }
    return null;
}

pub export fn PyUnicodeEncodeError_GetReason(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    if (err_obj.reason) |r| {
        traits.incref(r);
        return r;
    }
    return pyunicode.PyUnicode_FromString("encode error");
}

pub export fn PyUnicodeEncodeError_GetStart(exc: *cpython.PyObject, start: *isize) callconv(.c) c_int {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    start.* = err_obj.start;
    return 0;
}

pub export fn PyUnicodeEncodeError_SetEnd(exc: *cpython.PyObject, end: isize) callconv(.c) c_int {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    err_obj.end = end;
    return 0;
}

pub export fn PyUnicodeEncodeError_SetReason(exc: *cpython.PyObject, reason: *cpython.PyObject) callconv(.c) c_int {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    if (err_obj.reason) |old| {
        traits.decref(old);
    }
    traits.incref(reason);
    err_obj.reason = reason;
    return 0;
}

pub export fn PyUnicodeEncodeError_SetStart(exc: *cpython.PyObject, start: isize) callconv(.c) c_int {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    err_obj.start = start;
    return 0;
}

// --- PyUnicodeTranslateError_* ---

pub export fn PyUnicodeTranslateError_GetEnd(exc: *cpython.PyObject, end: *isize) callconv(.c) c_int {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    end.* = err_obj.end;
    return 0;
}

pub export fn PyUnicodeTranslateError_GetObject(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    if (err_obj.object) |obj| {
        traits.incref(obj);
        return obj;
    }
    return null;
}

pub export fn PyUnicodeTranslateError_GetReason(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    if (err_obj.reason) |r| {
        traits.incref(r);
        return r;
    }
    return pyunicode.PyUnicode_FromString("translate error");
}

pub export fn PyUnicodeTranslateError_GetStart(exc: *cpython.PyObject, start: *isize) callconv(.c) c_int {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    start.* = err_obj.start;
    return 0;
}

pub export fn PyUnicodeTranslateError_SetEnd(exc: *cpython.PyObject, end: isize) callconv(.c) c_int {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    err_obj.end = end;
    return 0;
}

pub export fn PyUnicodeTranslateError_SetReason(exc: *cpython.PyObject, reason: *cpython.PyObject) callconv(.c) c_int {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    if (err_obj.reason) |old| {
        traits.decref(old);
    }
    traits.incref(reason);
    err_obj.reason = reason;
    return 0;
}

pub export fn PyUnicodeTranslateError_SetStart(exc: *cpython.PyObject, start: isize) callconv(.c) c_int {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    err_obj.start = start;
    return 0;
}
