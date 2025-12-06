/// _codecs Module - Codec Registry and Base Codecs
///
/// Implements CPython's Modules/_codecsmodule.c
/// Provides codec search function registry and standard base codecs
///
/// Reference: cpython/Modules/_codecsmodule.c

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// CODEC REGISTRY
// ============================================================================

/// Maximum number of registered codec search functions
const MAX_SEARCH_FUNCTIONS = 100;

/// Registered codec search functions
var search_functions: [MAX_SEARCH_FUNCTIONS]?*cpython.PyObject = [_]?*cpython.PyObject{null} ** MAX_SEARCH_FUNCTIONS;
var num_search_functions: usize = 0;

/// Register a codec search function
pub export fn PyCodec_Register(search_function: ?*cpython.PyObject) c_int {
    if (search_function == null) return -1;
    if (num_search_functions >= MAX_SEARCH_FUNCTIONS) return -1;

    search_function.?.ob_refcnt += 1;
    search_functions[num_search_functions] = search_function;
    num_search_functions += 1;
    return 0;
}

/// Unregister a codec search function
pub export fn PyCodec_Unregister(search_function: ?*cpython.PyObject) c_int {
    if (search_function == null) return -1;

    for (0..num_search_functions) |i| {
        if (search_functions[i] == search_function) {
            search_function.?.ob_refcnt -= 1;
            // Shift remaining functions
            var j = i;
            while (j < num_search_functions - 1) : (j += 1) {
                search_functions[j] = search_functions[j + 1];
            }
            search_functions[num_search_functions - 1] = null;
            num_search_functions -= 1;
            return 0;
        }
    }
    return -1; // Not found
}

/// Lookup a codec by encoding name
pub export fn PyCodec_Lookup(encoding: [*:0]const u8) ?*cpython.PyObject {
    if (encoding[0] == 0) return null;

    // Normalize encoding name (lowercase, replace hyphens with underscores)
    var normalized: [256]u8 = undefined;
    var i: usize = 0;
    while (encoding[i] != 0 and i < 255) : (i += 1) {
        var c = encoding[i];
        if (c >= 'A' and c <= 'Z') c = c - 'A' + 'a';
        if (c == '-') c = '_';
        normalized[i] = c;
    }
    normalized[i] = 0;

    // Search through registered functions
    const pyunicode = @import("../objects/unicodeobject.zig");
    const name_obj = pyunicode.PyUnicode_FromString(&normalized);
    if (name_obj == null) return null;

    for (0..num_search_functions) |j| {
        if (search_functions[j]) |func| {
            // Call search function with encoding name
            const object_mod = @import("../objects/object.zig");
            const result = object_mod.PyObject_CallOneArg(func, name_obj);
            if (result != null and result != &object_mod._Py_NoneStruct) {
                name_obj.?.ob_refcnt -= 1;
                return result;
            }
            if (result) |r| r.ob_refcnt -= 1;
        }
    }

    name_obj.?.ob_refcnt -= 1;
    return null; // Codec not found
}

// ============================================================================
// ENCODING/DECODING FUNCTIONS
// ============================================================================

/// Encode a Unicode string to bytes using the specified encoding
pub export fn PyCodec_Encode(obj: ?*cpython.PyObject, encoding: [*:0]const u8, errors: ?[*:0]const u8) ?*cpython.PyObject {
    if (obj == null) return null;

    _ = errors;

    // Get codec for encoding
    const codec = PyCodec_Lookup(encoding);
    if (codec == null) return null;
    defer codec.?.ob_refcnt -= 1;

    // For now, just use UTF-8 encoding directly for common cases
    const enc_lower = std.mem.span(encoding);
    if (std.mem.eql(u8, enc_lower, "utf-8") or std.mem.eql(u8, enc_lower, "utf8")) {
        const pyunicode = @import("../objects/unicodeobject.zig");
        return pyunicode.PyUnicode_AsEncodedString(obj, "utf-8", null);
    }

    return null;
}

/// Decode bytes to a Unicode string using the specified encoding
pub export fn PyCodec_Decode(obj: ?*cpython.PyObject, encoding: [*:0]const u8, errors: ?[*:0]const u8) ?*cpython.PyObject {
    if (obj == null) return null;

    _ = errors;

    // Get codec for encoding
    const codec = PyCodec_Lookup(encoding);
    if (codec == null) return null;
    defer codec.?.ob_refcnt -= 1;

    // For now, just use UTF-8 decoding directly for common cases
    const pybytes = @import("../objects/bytesobject.zig");
    if (pybytes.PyBytes_Check(obj.?) != 0) {
        const data = pybytes.PyBytes_AsString(obj.?);
        const size = pybytes.PyBytes_Size(obj.?);
        const pyunicode = @import("../objects/unicodeobject.zig");
        return pyunicode.PyUnicode_DecodeUTF8(data, size, null);
    }

    return null;
}

// ============================================================================
// MODULE FUNCTIONS
// ============================================================================

/// Register a codec search function (Python API)
fn codec_register(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;

    const tuple = @import("../objects/tupleobject.zig");
    if (tuple.PyTuple_Size(args.?) < 1) return null;

    const search_func = tuple.PyTuple_GetItem(args.?, 0);
    if (PyCodec_Register(search_func) < 0) return null;

    const object_mod = @import("../objects/object.zig");
    return &object_mod._Py_NoneStruct;
}

/// Lookup a codec
fn codec_lookup(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;

    const tuple = @import("../objects/tupleobject.zig");
    const pyunicode = @import("../objects/unicodeobject.zig");

    if (tuple.PyTuple_Size(args.?) < 1) return null;

    const encoding_obj = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    const encoding = pyunicode.PyUnicode_AsUTF8(encoding_obj) orelse return null;

    return PyCodec_Lookup(encoding);
}

/// Encode using a codec
fn codec_encode(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;

    const tuple = @import("../objects/tupleobject.zig");
    const pyunicode = @import("../objects/unicodeobject.zig");

    const nargs = tuple.PyTuple_Size(args.?);
    if (nargs < 1) return null;

    const obj = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    const encoding = if (nargs >= 2)
        pyunicode.PyUnicode_AsUTF8(tuple.PyTuple_GetItem(args.?, 1) orelse return null) orelse "utf-8"
    else
        "utf-8";

    return PyCodec_Encode(obj, encoding, null);
}

/// Decode using a codec
fn codec_decode(self: ?*cpython.PyObject, args: ?*cpython.PyObject) callconv(.C) ?*cpython.PyObject {
    _ = self;
    if (args == null) return null;

    const tuple = @import("../objects/tupleobject.zig");
    const pyunicode = @import("../objects/unicodeobject.zig");

    const nargs = tuple.PyTuple_Size(args.?);
    if (nargs < 1) return null;

    const obj = tuple.PyTuple_GetItem(args.?, 0) orelse return null;
    const encoding = if (nargs >= 2)
        pyunicode.PyUnicode_AsUTF8(tuple.PyTuple_GetItem(args.?, 1) orelse return null) orelse "utf-8"
    else
        "utf-8";

    return PyCodec_Decode(obj, encoding, null);
}

// ============================================================================
// MODULE DEFINITION
// ============================================================================

const codecs_methods = [_]cpython.PyMethodDef{
    .{
        .ml_name = "register",
        .ml_meth = @ptrCast(&codec_register),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Register a codec search function.",
    },
    .{
        .ml_name = "lookup",
        .ml_meth = @ptrCast(&codec_lookup),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Lookup a codec by encoding name.",
    },
    .{
        .ml_name = "encode",
        .ml_meth = @ptrCast(&codec_encode),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Encode an object using a codec.",
    },
    .{
        .ml_name = "decode",
        .ml_meth = @ptrCast(&codec_decode),
        .ml_flags = cpython.METH_VARARGS,
        .ml_doc = "Decode an object using a codec.",
    },
    .{ .ml_name = null, .ml_meth = null, .ml_flags = 0, .ml_doc = null },
};

pub export var _codecsmodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_codecs",
    .m_doc = "Provides access to the codec registry and base codecs.",
    .m_size = -1,
    .m_methods = @constCast(&codecs_methods),
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit__codecs() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    return module_mod.PyModule_Create(&_codecsmodule);
}
