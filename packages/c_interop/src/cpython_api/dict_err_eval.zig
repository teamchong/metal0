/// PyDict_*, PyErr_*, PyEval_* Functions
/// Dictionary operations, error handling, and evaluation functions.

const std = @import("std");
const cpython = @import("../include/object.zig");
const pydict = @import("../objects/dictobject.zig");
const pyunicode = @import("../objects/unicodeobject.zig");
const pytuple = @import("../objects/tupleobject.zig");
const pylong = @import("../objects/longobject.zig");
const exceptions = @import("../objects/exceptions.zig");
const traits = @import("../objects/typetraits.zig");

// --- PyCapsule_* Functions ---

export fn PyCapsule_IsValid(capsule: *cpython.PyObject, name: ?[*:0]const u8) callconv(.c) c_int {
    _ = name;
    const misc = @import("../include/pymisc.zig");
    return if (misc.PyCapsule_GetPointer(capsule, null) != null) 1 else 0;
}

// --- PyCMethod_* ---

export fn PyCMethod_New(meth: *const cpython.PyMethodDef, self: ?*cpython.PyObject, module: ?*cpython.PyObject, cls: ?*cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject {
    _ = cls;
    const pymethod = @import("../objects/methodobject.zig");
    return pymethod.PyCFunction_NewEx(meth, self, module);
}

// --- PyCodec_* Error Handlers ---

// Structure for Unicode error objects (needed for codec error handlers)
pub const PyUnicodeErrorObject = extern struct {
    ob_base: cpython.PyObject,
    encoding: ?*cpython.PyObject,
    object: ?*cpython.PyObject,
    start: isize,
    end: isize,
    reason: ?*cpython.PyObject,
};

fn getUnicodeErrorPosition(exc: *cpython.PyObject) isize {
    const err_obj: *PyUnicodeErrorObject = @ptrCast(@alignCast(exc));
    return err_obj.end;
}

export fn PyCodec_BackslashReplaceErrors(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const end = getUnicodeErrorPosition(exc);
    const replacement = pyunicode.PyUnicode_FromString("\\x??") orelse return null;
    return pytuple.PyTuple_Pack(2, replacement, pylong.PyLong_FromLong(@intCast(end)));
}

export fn PyCodec_IgnoreErrors(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const end = getUnicodeErrorPosition(exc);
    const replacement = pyunicode.PyUnicode_FromString("") orelse return null;
    return pytuple.PyTuple_Pack(2, replacement, pylong.PyLong_FromLong(@intCast(end)));
}

export fn PyCodec_NameReplaceErrors(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const end = getUnicodeErrorPosition(exc);
    const replacement = pyunicode.PyUnicode_FromString("\\N{...}") orelse return null;
    return pytuple.PyTuple_Pack(2, replacement, pylong.PyLong_FromLong(@intCast(end)));
}

export fn PyCodec_ReplaceErrors(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const end = getUnicodeErrorPosition(exc);
    const replacement = pyunicode.PyUnicode_FromString("\xef\xbf\xbd") orelse return null; // U+FFFD
    return pytuple.PyTuple_Pack(2, replacement, pylong.PyLong_FromLong(@intCast(end)));
}

export fn PyCodec_StrictErrors(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    exceptions.PyErr_SetObject(&exceptions.PyExc_UnicodeDecodeError, exc);
    return null;
}

export fn PyCodec_XMLCharRefReplaceErrors(exc: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const end = getUnicodeErrorPosition(exc);
    const replacement = pyunicode.PyUnicode_FromString("&#...;") orelse return null;
    return pytuple.PyTuple_Pack(2, replacement, pylong.PyLong_FromLong(@intCast(end)));
}

// --- PyDict_* New Functions ---

export fn PyDict_GetItemRef(dict: *cpython.PyObject, key: *cpython.PyObject, result: *?*cpython.PyObject) callconv(.c) c_int {
    const item = pydict.PyDict_GetItem(dict, key);
    if (item) |i| {
        traits.incref(i);
        result.* = i;
        return 1;
    }
    result.* = null;
    return 0;
}

export fn PyDict_GetItemStringRef(dict: *cpython.PyObject, key: [*:0]const u8, result: *?*cpython.PyObject) callconv(.c) c_int {
    const item = pydict.PyDict_GetItemString(dict, key);
    if (item) |i| {
        traits.incref(i);
        result.* = i;
        return 1;
    }
    result.* = null;
    return 0;
}

export fn PyDict_SetDefaultRef(dict: *cpython.PyObject, key: *cpython.PyObject, default_value: *cpython.PyObject, result: *?*cpython.PyObject) callconv(.c) c_int {
    const existing = pydict.PyDict_GetItem(dict, key);
    if (existing) |e| {
        traits.incref(e);
        result.* = e;
        return 0;
    }
    _ = pydict.PyDict_SetItem(dict, key, default_value);
    traits.incref(default_value);
    result.* = default_value;
    return 1;
}

// --- PyErr_* Functions ---

export fn PyErr_Display(exc: *cpython.PyObject, value: *cpython.PyObject, tb: ?*cpython.PyObject) callconv(.c) void {
    _ = exc;
    _ = value;
    _ = tb;
}

export fn PyErr_DisplayException(exc: *cpython.PyObject) callconv(.c) void {
    _ = exc;
}

export fn PyErr_FormatV(exc_type: *cpython.PyTypeObject, format: [*:0]const u8, vargs: std.builtin.VaList) callconv(.c) ?*cpython.PyObject {
    const fmt = std.mem.span(format);
    var va_copy = vargs;

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
                'l' => {
                    if (fmt_idx + 1 < fmt.len and fmt[fmt_idx + 1] == 'd') {
                        fmt_idx += 1;
                        const val = @cVaArg(&va_copy, c_long);
                        const result = std.fmt.bufPrint(buf[buf_idx..], "{d}", .{val}) catch break;
                        buf_idx += result.len;
                    }
                },
                'p' => {
                    const val = @cVaArg(&va_copy, usize);
                    const result = std.fmt.bufPrint(buf[buf_idx..], "0x{x}", .{val}) catch break;
                    buf_idx += result.len;
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
    buf[buf_idx] = 0;

    exceptions.PyErr_SetString(exc_type, @ptrCast(&buf));
    return null;
}

export fn PyErr_GetExcInfo(ptype: *?*cpython.PyObject, pvalue: *?*cpython.PyObject, ptb: *?*cpython.PyObject) callconv(.c) void {
    ptype.* = null;
    pvalue.* = null;
    ptb.* = null;
}

export fn PyErr_GetHandledException() callconv(.c) ?*cpython.PyObject {
    return null;
}

export fn PyErr_GetRaisedException() callconv(.c) ?*cpython.PyObject {
    return null;
}

export fn PyErr_PrintEx(set_sys_last_vars: c_int) callconv(.c) void {
    _ = set_sys_last_vars;
}

export fn PyErr_ProgramText(filename: [*:0]const u8, lineno: c_int) callconv(.c) ?*cpython.PyObject {
    _ = filename;
    _ = lineno;
    return null;
}

export fn PyErr_ResourceWarning(source: ?*cpython.PyObject, stack_level: isize, format: [*:0]const u8) callconv(.c) c_int {
    _ = source;
    _ = stack_level;
    _ = format;
    return 0;
}

export fn PyErr_SetExcInfo(ptype: ?*cpython.PyObject, pvalue: ?*cpython.PyObject, ptb: ?*cpython.PyObject) callconv(.c) void {
    _ = ptype;
    _ = pvalue;
    _ = ptb;
}

export fn PyErr_SetFromErrnoWithFilenameObject(exc: *cpython.PyTypeObject, filename: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = filename;
    exceptions.PyErr_SetString(exc, "errno error");
    return null;
}

export fn PyErr_SetFromErrnoWithFilenameObjects(exc: *cpython.PyTypeObject, filename: ?*cpython.PyObject, filename2: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = filename;
    _ = filename2;
    exceptions.PyErr_SetString(exc, "errno error");
    return null;
}

export fn PyErr_SetHandledException(exc: ?*cpython.PyObject) callconv(.c) void {
    _ = exc;
}

export fn PyErr_SetImportError(msg: *cpython.PyObject, name: ?*cpython.PyObject, path: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = name;
    _ = path;
    exceptions.PyErr_SetObject(&exceptions.PyExc_ImportError, msg);
    return null;
}

export fn PyErr_SetImportErrorSubclass(exc: *cpython.PyObject, msg: *cpython.PyObject, name: ?*cpython.PyObject, path: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = exc;
    _ = name;
    _ = path;
    exceptions.PyErr_SetObject(&exceptions.PyExc_ImportError, msg);
    return null;
}

export fn PyErr_SetRaisedException(exc: ?*cpython.PyObject) callconv(.c) void {
    _ = exc;
}

export fn PyErr_WarnExplicit(category: ?*cpython.PyTypeObject, message: [*:0]const u8, filename: [*:0]const u8, lineno: c_int, module: ?[*:0]const u8, registry: ?*cpython.PyObject) callconv(.c) c_int {
    _ = category;
    _ = message;
    _ = filename;
    _ = lineno;
    _ = module;
    _ = registry;
    return 0;
}

export fn PyErr_WarnFormat(category: *cpython.PyTypeObject, stack_level: isize, format: [*:0]const u8) callconv(.c) c_int {
    return exceptions.PyErr_WarnEx(category, format, stack_level);
}

// --- PyEval_* Functions ---

export fn PyEval_EvalCodeEx(co: *cpython.PyObject, globals: *cpython.PyObject, locals: ?*cpython.PyObject, args: ?[*]const *cpython.PyObject, argcount: c_int, kws: ?[*]const *cpython.PyObject, kwcount: c_int, defs: ?[*]const *cpython.PyObject, defcount: c_int, kwdefs: ?*cpython.PyObject, closure: ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = args;
    _ = argcount;
    _ = kws;
    _ = kwcount;
    _ = defs;
    _ = defcount;
    _ = kwdefs;
    _ = closure;

    const eval_mod = @import("../include/ceval.zig");
    return eval_mod.PyEval_EvalCode(co, globals, locals orelse globals);
}

export fn PyEval_GetFrameBuiltins() callconv(.c) ?*cpython.PyObject {
    return null;
}

export fn PyEval_GetFrameGlobals() callconv(.c) ?*cpython.PyObject {
    return null;
}

export fn PyEval_GetFrameLocals() callconv(.c) ?*cpython.PyObject {
    return null;
}

// --- PyExceptionClass_* ---

export fn PyExceptionClass_Name(exc: *cpython.PyObject) callconv(.c) [*:0]const u8 {
    const tp = cpython.Py_TYPE(exc);
    return tp.tp_name orelse "Exception";
}
