/// _json Module - JSON C Accelerator
///
/// Implements CPython's Modules/_json.c
/// Provides C implementation for JSON encoding/decoding
///
/// Reference: cpython/Modules/_json.c

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// JSON SCANNER (DECODER)
// ============================================================================

/// ScannerObject - JSON scanner/decoder state
pub const ScannerObject = extern struct {
    ob_base: cpython.PyObject,
    strict: c_int, // Strict mode
    object_hook: ?*cpython.PyObject, // Function to call on decoded objects
    object_pairs_hook: ?*cpython.PyObject, // Function to call on decoded pairs
    parse_float: ?*cpython.PyObject, // Custom float parser
    parse_int: ?*cpython.PyObject, // Custom int parser
    parse_constant: ?*cpython.PyObject, // Custom constant parser (NaN, Infinity)
};

/// Create a new scanner
pub export fn _json_Scanner_new() ?*cpython.PyObject {
    const mem = allocator.alignedAlloc(u8, @alignOf(ScannerObject), @sizeOf(ScannerObject)) catch return null;
    const scanner: *ScannerObject = @ptrCast(@alignCast(mem.ptr));

    scanner.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &ScannerType },
        .strict = 1,
        .object_hook = null,
        .object_pairs_hook = null,
        .parse_float = null,
        .parse_int = null,
        .parse_constant = null,
    };

    return @ptrCast(scanner);
}

// ============================================================================
// JSON ENCODER
// ============================================================================

/// EncoderObject - JSON encoder state
pub const EncoderObject = extern struct {
    ob_base: cpython.PyObject,
    markers: ?*cpython.PyObject, // Dict for circular reference detection
    default_fn: ?*cpython.PyObject, // Default function for non-JSON types
    encoder: ?*cpython.PyObject, // String encoder
    indent: ?*cpython.PyObject, // Indentation string
    key_separator: ?*cpython.PyObject, // Key separator (": " or ":")
    item_separator: ?*cpython.PyObject, // Item separator (", " or ",")
    sort_keys: c_int, // Sort dict keys
    skipkeys: c_int, // Skip non-string keys
    allow_nan: c_int, // Allow NaN/Infinity
    fast_encode: c_int, // Use fast encoding path
};

/// Create a new encoder
pub export fn _json_Encoder_new() ?*cpython.PyObject {
    const mem = allocator.alignedAlloc(u8, @alignOf(EncoderObject), @sizeOf(EncoderObject)) catch return null;
    const encoder: *EncoderObject = @ptrCast(@alignCast(mem.ptr));

    const pyunicode = @import("../objects/unicodeobject.zig");

    encoder.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &EncoderType },
        .markers = null,
        .default_fn = null,
        .encoder = null,
        .indent = null,
        .key_separator = pyunicode.PyUnicode_FromString(": "),
        .item_separator = pyunicode.PyUnicode_FromString(", "),
        .sort_keys = 0,
        .skipkeys = 0,
        .allow_nan = 0,
        .fast_encode = 1,
    };

    return @ptrCast(encoder);
}

// ============================================================================
// ENCODING FUNCTIONS
// ============================================================================

/// Encode a string value
pub export fn _json_encode_string(s: ?*cpython.PyObject) ?*cpython.PyObject {
    if (s == null) return null;

    const pyunicode = @import("../objects/unicodeobject.zig");
    const str = pyunicode.PyUnicode_AsUTF8(s.?) orelse return null;
    const len = pyunicode.PyUnicode_GetLength(s.?);

    // Estimate output size (worst case: all characters escaped)
    const max_len: usize = @intCast(len * 6 + 2); // 2 for quotes
    var buffer = allocator.alloc(u8, max_len) catch return null;
    defer allocator.free(buffer);

    var out_pos: usize = 0;
    buffer[out_pos] = '"';
    out_pos += 1;

    var i: usize = 0;
    const str_len: usize = @intCast(len);
    while (i < str_len) : (i += 1) {
        const c = str[i];
        switch (c) {
            '"' => {
                buffer[out_pos] = '\\';
                buffer[out_pos + 1] = '"';
                out_pos += 2;
            },
            '\\' => {
                buffer[out_pos] = '\\';
                buffer[out_pos + 1] = '\\';
                out_pos += 2;
            },
            '\n' => {
                buffer[out_pos] = '\\';
                buffer[out_pos + 1] = 'n';
                out_pos += 2;
            },
            '\r' => {
                buffer[out_pos] = '\\';
                buffer[out_pos + 1] = 'r';
                out_pos += 2;
            },
            '\t' => {
                buffer[out_pos] = '\\';
                buffer[out_pos + 1] = 't';
                out_pos += 2;
            },
            else => {
                if (c < 0x20) {
                    // Escape control characters
                    const hex = "0123456789abcdef";
                    buffer[out_pos] = '\\';
                    buffer[out_pos + 1] = 'u';
                    buffer[out_pos + 2] = '0';
                    buffer[out_pos + 3] = '0';
                    buffer[out_pos + 4] = hex[(c >> 4) & 0xF];
                    buffer[out_pos + 5] = hex[c & 0xF];
                    out_pos += 6;
                } else {
                    buffer[out_pos] = c;
                    out_pos += 1;
                }
            },
        }
    }

    buffer[out_pos] = '"';
    out_pos += 1;

    return pyunicode.PyUnicode_FromStringAndSize(buffer.ptr, @intCast(out_pos));
}

/// Encode an integer value
pub export fn _json_encode_int(obj: ?*cpython.PyObject) ?*cpython.PyObject {
    if (obj == null) return null;

    const pylong = @import("../objects/longobject.zig");
    const pyunicode = @import("../objects/unicodeobject.zig");

    const value = pylong.PyLong_AsLongLong(obj.?);
    var buffer: [32]u8 = undefined;
    const slice = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch return null;

    return pyunicode.PyUnicode_FromStringAndSize(slice.ptr, @intCast(slice.len));
}

/// Encode a float value
pub export fn _json_encode_float(obj: ?*cpython.PyObject, allow_nan: c_int) ?*cpython.PyObject {
    if (obj == null) return null;

    const pyfloat = @import("../objects/floatobject.zig");
    const pyunicode = @import("../objects/unicodeobject.zig");

    const value = pyfloat.PyFloat_AsDouble(obj.?);

    // Check for special values
    if (std.math.isNan(value)) {
        if (allow_nan != 0) {
            return pyunicode.PyUnicode_FromString("NaN");
        }
        return null; // Would raise ValueError
    }
    if (std.math.isInf(value)) {
        if (allow_nan != 0) {
            return if (value > 0)
                pyunicode.PyUnicode_FromString("Infinity")
            else
                pyunicode.PyUnicode_FromString("-Infinity");
        }
        return null;
    }

    var buffer: [64]u8 = undefined;
    const slice = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch return null;

    return pyunicode.PyUnicode_FromStringAndSize(slice.ptr, @intCast(slice.len));
}

// ============================================================================
// DECODING FUNCTIONS
// ============================================================================

/// Decode a JSON string
pub export fn _json_decode_string(s: [*:0]const u8, end: *isize) ?*cpython.PyObject {
    const pyunicode = @import("../objects/unicodeobject.zig");

    // Skip opening quote
    var pos: usize = 1;
    const start = pos;

    // Find end of string
    while (s[pos] != 0) : (pos += 1) {
        if (s[pos] == '"' and (pos == 0 or s[pos - 1] != '\\')) {
            break;
        }
    }

    end.* = @intCast(pos + 1);
    return pyunicode.PyUnicode_FromStringAndSize(s + start, @intCast(pos - start));
}

// ============================================================================
// TYPE OBJECTS
// ============================================================================

pub export var ScannerType: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_json.Scanner",
    .tp_basicsize = @sizeOf(ScannerObject),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = "JSON scanner",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = null,
    .tp_free = null,
    .tp_is_gc = null,
    .tp_bases = null,
    .tp_mro = null,
    .tp_cache = null,
    .tp_subclasses = null,
    .tp_weaklist = null,
    .tp_del = null,
    .tp_version_tag = 0,
    .tp_finalize = null,
    .tp_vectorcall = null,
};

pub export var EncoderType: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "_json.Encoder",
    .tp_basicsize = @sizeOf(EncoderObject),
    .tp_itemsize = 0,
    .tp_dealloc = null,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = "JSON encoder",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = null,
    .tp_free = null,
    .tp_is_gc = null,
    .tp_bases = null,
    .tp_mro = null,
    .tp_cache = null,
    .tp_subclasses = null,
    .tp_weaklist = null,
    .tp_del = null,
    .tp_version_tag = 0,
    .tp_finalize = null,
    .tp_vectorcall = null,
};

// ============================================================================
// MODULE DEFINITION
// ============================================================================

pub export var _jsonmodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_json",
    .m_doc = "json speedups",
    .m_size = -1,
    .m_methods = null,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit__json() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    const module = module_mod.PyModule_Create(&_jsonmodule);
    if (module == null) return null;

    _ = module_mod.PyModule_AddObject(module, "make_scanner", @ptrCast(&ScannerType));
    _ = module_mod.PyModule_AddObject(module, "make_encoder", @ptrCast(&EncoderType));

    return module;
}
