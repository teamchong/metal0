/// CPython Unicode String Implementation
///
/// This file implements PyUnicode operations for UTF-8 string handling.
///
/// PyUnicode is one of the most frequently used types in Python and
/// critical for NumPy (dimension names, dtype names, error messages, etc.)
///
/// Implementation notes:
/// - Uses simplified UTF-8 storage (CPython uses multiple representations)
/// - Lazy conversion between formats (not implemented yet)
/// - Compatible binary layout for C extensions

const std = @import("std");
const cpython = @import("cpython_object.zig");
const helpers = @import("optimization_helpers.zig");

// External dependencies
extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;
extern fn PyErr_SetString(*cpython.PyTypeObject, [*:0]const u8) callconv(.c) void;
extern fn PyMem_Malloc(usize) callconv(.c) ?*anyopaque;
extern fn PyMem_Free(?*anyopaque) callconv(.c) void;
extern fn PyObject_Malloc(usize) callconv(.c) ?*anyopaque;
extern fn PyObject_Free(?*anyopaque) callconv(.c) void;

// Exception types
extern var PyExc_TypeError: cpython.PyTypeObject;
extern var PyExc_ValueError: cpython.PyTypeObject;

/// ============================================================================
/// PYUNICODE TYPE DEFINITION
/// ============================================================================

/// PyUnicodeObject - CPython-compatible unicode string
///
/// CPython 3.12+ uses a compact representation with multiple internal formats.
/// We simplify to always use UTF-8 for compatibility and simplicity.
pub const PyUnicodeObject = extern struct {
    ob_base: cpython.PyVarObject,
    // Internal data follows (handled via separate allocation)
};

/// Internal unicode data structure (not part of CPython ABI)
const UnicodeData = struct {
    utf8: [*:0]u8, // Null-terminated UTF-8 string
    length: usize, // Character count (not byte count)
    byte_length: usize, // Byte count
};

/// Helper: Get UnicodeData pointer from PyUnicodeObject
/// Eliminates repeated pointer arithmetic throughout the file
inline fn getUnicodeData(obj: *cpython.PyObject) ?*UnicodeData {
    const unicode = helpers.pyObjCast(*PyUnicodeObject, obj);
    const data_ptr = helpers.getPostObjectData(*?*UnicodeData, unicode, @sizeOf(PyUnicodeObject));
    return data_ptr.*;
}

/// Helper: Set UnicodeData pointer on PyUnicodeObject
inline fn setUnicodeData(obj: *cpython.PyObject, data: ?*UnicodeData) void {
    const unicode = helpers.pyObjCast(*PyUnicodeObject, obj);
    const data_ptr = helpers.getPostObjectData(*?*UnicodeData, unicode, @sizeOf(PyUnicodeObject));
    data_ptr.* = data;
}

/// Global PyUnicode_Type (will be initialized at runtime)
var PyUnicode_Type_Obj: cpython.PyTypeObject = undefined;
var unicode_type_initialized: bool = false;

fn ensureUnicodeTypeInit() void {
    if (unicode_type_initialized) return;

    PyUnicode_Type_Obj = .{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = &PyUnicode_Type_Obj, // Self-reference
            },
            .ob_size = 0,
        },
        .tp_name = "str",
        .tp_basicsize = @sizeOf(PyUnicodeObject),
        .tp_itemsize = 0,
        .tp_dealloc = unicode_dealloc,
        .tp_vectorcall_offset = 0,
        .tp_getattr = null,
        .tp_setattr = null,
        .tp_as_async = null,
        .tp_repr = unicode_repr,
        .tp_as_number = null,
        .tp_as_sequence = null,
        .tp_as_mapping = null,
        .tp_hash = unicode_hash,
        .tp_call = null,
        .tp_str = unicode_str,
        .tp_getattro = null,
        .tp_setattro = null,
        .tp_as_buffer = null,
        .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE | cpython.Py_TPFLAGS_UNICODE_SUBCLASS,
        .tp_doc = "str(object='') -> str",
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
        .tp_watched = 0,
        .tp_versions_used = 0,
    };

    unicode_type_initialized = true;
}

/// Destructor for unicode objects
fn unicode_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    if (getUnicodeData(obj)) |d| {
        PyMem_Free(d.utf8);
        PyObject_Free(d);
    }
    PyObject_Free(obj);
}

/// Get repr of unicode object
fn unicode_repr(obj: *cpython.PyObject) callconv(.c) *cpython.PyObject {
    // For now, return the string itself
    return unicode_str(obj);
}

/// Get str of unicode object (identity for strings)
fn unicode_str(obj: *cpython.PyObject) callconv(.c) *cpython.PyObject {
    Py_INCREF(obj);
    return obj;
}

/// Hash function for unicode objects
fn unicode_hash(obj: *cpython.PyObject) callconv(.c) isize {
    if (getUnicodeData(obj)) |d| {
        return @intCast(helpers.hashString(d.utf8[0..d.byte_length]));
    }
    return 0;
}

/// ============================================================================
/// STRING CREATION
/// ============================================================================

/// Create unicode from null-terminated C string
///
/// CPython: PyObject* PyUnicode_FromString(const char *str)
/// Returns: New unicode object or null on error
export fn PyUnicode_FromString(str: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    const len = std.mem.len(str);
    return PyUnicode_FromStringAndSize(str, @intCast(len));
}

/// Create unicode from C string with explicit size
///
/// CPython: PyObject* PyUnicode_FromStringAndSize(const char *str, Py_ssize_t size)
/// Returns: New unicode object or null on error
export fn PyUnicode_FromStringAndSize(str: [*]const u8, size: isize) callconv(.c) ?*cpython.PyObject {
    ensureUnicodeTypeInit();

    // Allocate PyUnicodeObject
    const unicode_mem = PyObject_Malloc(@sizeOf(PyUnicodeObject) + @sizeOf(?*UnicodeData)) orelse return null;
    const unicode = @as(*PyUnicodeObject, @ptrCast(@alignCast(unicode_mem)));

    // Initialize object header
    unicode.ob_base = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyUnicode_Type_Obj,
        },
        .ob_size = size,
    };

    // Allocate internal data structure
    const data_mem = PyObject_Malloc(@sizeOf(UnicodeData)) orelse {
        PyObject_Free(unicode);
        return null;
    };
    const data = @as(*UnicodeData, @ptrCast(@alignCast(data_mem)));

    const usize_len: usize = @intCast(size);

    // Allocate UTF-8 buffer (with null terminator)
    const utf8_mem = PyMem_Malloc(usize_len + 1) orelse {
        PyObject_Free(data);
        PyObject_Free(unicode);
        return null;
    };
    const utf8_buf = @as([*:0]u8, @ptrCast(@alignCast(utf8_mem)));

    // Copy string data
    @memcpy(utf8_buf[0..usize_len], str[0..usize_len]);
    utf8_buf[usize_len] = 0; // Null terminate

    // Fill data structure
    data.* = .{
        .utf8 = utf8_buf,
        .length = usize_len, // Simplified: assume ASCII (1 char = 1 byte)
        .byte_length = usize_len,
    };

    // Store data pointer after unicode object
    setUnicodeData(@ptrCast(&unicode.ob_base.ob_base), data);

    return @ptrCast(&unicode.ob_base.ob_base);
}

/// ============================================================================
/// STRING CONVERSION TO C
/// ============================================================================

/// Get UTF-8 C string from unicode object
///
/// CPython: const char* PyUnicode_AsUTF8(PyObject *obj)
/// Returns: Null-terminated C string or null on error
export fn PyUnicode_AsUTF8(obj: *cpython.PyObject) callconv(.c) ?[*:0]const u8 {
    if (PyUnicode_Check(obj) == 0) {
        PyErr_SetString(&PyExc_TypeError, "expected str object");
        return null;
    }
    if (getUnicodeData(obj)) |d| return d.utf8;
    return null;
}

/// Get UTF-8 C string with size
///
/// CPython: const char* PyUnicode_AsUTF8AndSize(PyObject *obj, Py_ssize_t *size)
/// Returns: C string and writes size to size pointer
export fn PyUnicode_AsUTF8AndSize(obj: *cpython.PyObject, size: *isize) callconv(.c) ?[*:0]const u8 {
    const str = PyUnicode_AsUTF8(obj) orelse return null;
    if (getUnicodeData(obj)) |d| size.* = @intCast(d.byte_length);
    return str;
}

/// ============================================================================
/// STRING PROPERTIES
/// ============================================================================

/// Get character length of unicode string
///
/// CPython: Py_ssize_t PyUnicode_GetLength(PyObject *obj)
/// Returns: Character count (not byte count) or -1 on error
export fn PyUnicode_GetLength(obj: *cpython.PyObject) callconv(.c) isize {
    if (PyUnicode_Check(obj) == 0) {
        PyErr_SetString(&PyExc_TypeError, "expected str object");
        return -1;
    }
    if (getUnicodeData(obj)) |d| return @intCast(d.length);
    return 0;
}

/// Check if object is a unicode string
///
/// CPython: int PyUnicode_Check(PyObject *obj)
/// Returns: 1 if unicode, 0 otherwise
export fn PyUnicode_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    ensureUnicodeTypeInit();

    const type_obj = cpython.Py_TYPE(obj);
    if (type_obj == &PyUnicode_Type_Obj) {
        return 1;
    }

    // Check by name for robustness
    if (type_obj.tp_name) |name| {
        const type_name: []const u8 = std.mem.span(name);
        if (std.mem.eql(u8, type_name, "str")) {
            return 1;
        }
    }

    return 0;
}

/// ============================================================================
/// STRING OPERATIONS
/// ============================================================================

/// Concatenate two unicode strings
///
/// CPython: PyObject* PyUnicode_Concat(PyObject *left, PyObject *right)
/// Returns: New concatenated string or null on error
export fn PyUnicode_Concat(left: *cpython.PyObject, right: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // Type check
    if (PyUnicode_Check(left) == 0 or PyUnicode_Check(right) == 0) {
        PyErr_SetString(&PyExc_TypeError, "can only concatenate str (not other types)");
        return null;
    }

    // Get left string
    var left_size: isize = 0;
    const left_str = PyUnicode_AsUTF8AndSize(left, &left_size) orelse return null;

    // Get right string
    var right_size: isize = 0;
    const right_str = PyUnicode_AsUTF8AndSize(right, &right_size) orelse return null;

    // Allocate combined buffer
    const total_size: usize = @intCast(left_size + right_size);
    const combined = PyMem_Malloc(total_size + 1) orelse return null;
    const combined_buf = @as([*]u8, @ptrCast(combined));

    // Copy both strings
    const left_usize: usize = @intCast(left_size);
    const right_usize: usize = @intCast(right_size);
    @memcpy(combined_buf[0..left_usize], left_str[0..left_usize]);
    @memcpy(combined_buf[left_usize .. left_usize + right_usize], right_str[0..right_usize]);
    combined_buf[total_size] = 0;

    // Create new unicode object
    const result = PyUnicode_FromStringAndSize(combined_buf, @intCast(total_size));

    // Free temporary buffer
    PyMem_Free(combined);

    return result;
}

/// Format string with arguments (simplified)
///
/// CPython: PyObject* PyUnicode_Format(PyObject *format, PyObject *args)
/// Returns: Formatted string or null on error
export fn PyUnicode_Format(format: *cpython.PyObject, args: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = format;
    _ = args;

    // TODO: Implement proper string formatting
    PyErr_SetString(&PyExc_TypeError, "string formatting not yet implemented");
    return null;
}

/// Join sequence of strings with separator
///
/// CPython: PyObject* PyUnicode_Join(PyObject *separator, PyObject *seq)
/// Returns: Joined string or null on error
export fn PyUnicode_Join(separator: *cpython.PyObject, seq: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const sep_str = PyUnicode_AsUTF8(separator) orelse return null;
    const sep_slice = std.mem.span(sep_str);

    // Handle list
    const list = @import("pyobject_list.zig");
    if (list.PyList_Check(seq) != 0) {
        const size = list.PyList_Size(seq);
        if (size == 0) return PyUnicode_FromString("");

        var buf: [16384]u8 = undefined;
        var pos: usize = 0;

        var i: isize = 0;
        while (i < size) : (i += 1) {
            if (i > 0) {
                for (sep_slice) |c| {
                    if (pos < buf.len - 1) {
                        buf[pos] = c;
                        pos += 1;
                    }
                }
            }
            if (list.PyList_GetItem(seq, i)) |item| {
                if (PyUnicode_AsUTF8(item)) |item_str| {
                    const item_slice = std.mem.span(item_str);
                    for (item_slice) |c| {
                        if (pos < buf.len - 1) {
                            buf[pos] = c;
                            pos += 1;
                        }
                    }
                }
            }
        }
        return PyUnicode_FromStringAndSize(&buf, @intCast(pos));
    }

    // Handle tuple
    const tuple = @import("pyobject_tuple.zig");
    if (tuple.PyTuple_Check(seq) != 0) {
        const size = tuple.PyTuple_Size(seq);
        if (size == 0) return PyUnicode_FromString("");

        var buf: [16384]u8 = undefined;
        var pos: usize = 0;

        var i: isize = 0;
        while (i < size) : (i += 1) {
            if (i > 0) {
                for (sep_slice) |c| {
                    if (pos < buf.len - 1) {
                        buf[pos] = c;
                        pos += 1;
                    }
                }
            }
            if (tuple.PyTuple_GetItem(seq, i)) |item| {
                if (PyUnicode_AsUTF8(item)) |item_str| {
                    const item_slice = std.mem.span(item_str);
                    for (item_slice) |c| {
                        if (pos < buf.len - 1) {
                            buf[pos] = c;
                            pos += 1;
                        }
                    }
                }
            }
        }
        return PyUnicode_FromStringAndSize(&buf, @intCast(pos));
    }

    PyErr_SetString(&PyExc_TypeError, "can only join list or tuple");
    return null;
}

/// Split string by separator
///
/// CPython: PyObject* PyUnicode_Split(PyObject *s, PyObject *sep, Py_ssize_t maxsplit)
/// Returns: List of substrings or null on error
export fn PyUnicode_Split(s: *cpython.PyObject, sep: ?*cpython.PyObject, maxsplit: isize) callconv(.c) ?*cpython.PyObject {
    const str = PyUnicode_AsUTF8(s) orelse return null;
    const str_slice = std.mem.span(str);

    const list = @import("pyobject_list.zig");
    const result = list.PyList_New(0) orelse return null;

    if (sep) |sep_obj| {
        const sep_str = PyUnicode_AsUTF8(sep_obj) orelse return null;
        const sep_slice = std.mem.span(sep_str);

        var splits: isize = 0;
        var start: usize = 0;

        while (start <= str_slice.len) {
            if (maxsplit >= 0 and splits >= maxsplit) {
                // Add remaining as last element
                const substr = PyUnicode_FromStringAndSize(str + start, @intCast(str_slice.len - start));
                if (substr) |sub| _ = list.PyList_Append(result, sub);
                break;
            }

            if (std.mem.indexOfPos(u8, str_slice, start, sep_slice)) |pos| {
                const substr = PyUnicode_FromStringAndSize(str + start, @intCast(pos - start));
                if (substr) |sub| _ = list.PyList_Append(result, sub);
                start = pos + sep_slice.len;
                splits += 1;
            } else {
                // No more separators, add rest
                const substr = PyUnicode_FromStringAndSize(str + start, @intCast(str_slice.len - start));
                if (substr) |sub| _ = list.PyList_Append(result, sub);
                break;
            }
        }
    } else {
        // Split on whitespace
        var start: usize = 0;
        var splits: isize = 0;

        while (start < str_slice.len) {
            // Skip leading whitespace
            while (start < str_slice.len and std.ascii.isWhitespace(str_slice[start])) {
                start += 1;
            }
            if (start >= str_slice.len) break;

            if (maxsplit >= 0 and splits >= maxsplit) {
                const substr = PyUnicode_FromStringAndSize(str + start, @intCast(str_slice.len - start));
                if (substr) |sub| _ = list.PyList_Append(result, sub);
                break;
            }

            // Find end of word
            var end = start;
            while (end < str_slice.len and !std.ascii.isWhitespace(str_slice[end])) {
                end += 1;
            }

            const substr = PyUnicode_FromStringAndSize(str + start, @intCast(end - start));
            if (substr) |sub| _ = list.PyList_Append(result, sub);
            start = end;
            splits += 1;
        }
    }

    return result;
}

/// ============================================================================
/// ADDITIONAL ESSENTIAL FUNCTIONS
/// ============================================================================

/// Decode UTF-8 bytes to unicode
///
/// CPython: PyObject* PyUnicode_DecodeUTF8(const char *s, Py_ssize_t size, const char *errors)
/// Returns: Unicode object or null on error
export fn PyUnicode_DecodeUTF8(s: [*]const u8, size: isize, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = errors; // Simplified: ignore error handling mode
    return PyUnicode_FromStringAndSize(s, size);
}

/// Encode unicode to UTF-8 bytes
///
/// CPython: PyObject* PyUnicode_AsUTF8String(PyObject *obj)
/// Returns: Bytes object or null on error
export fn PyUnicode_AsUTF8String(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    var size: isize = 0;
    const str = PyUnicode_AsUTF8AndSize(obj, &size) orelse return null;

    const bytes = @import("pyobject_bytes.zig");
    return bytes.PyBytes_FromStringAndSize(str, size);
}

/// Compare two unicode strings
///
/// CPython: int PyUnicode_Compare(PyObject *left, PyObject *right)
/// Returns: -1 (less), 0 (equal), 1 (greater), -1 on error
export fn PyUnicode_Compare(left: *cpython.PyObject, right: *cpython.PyObject) callconv(.c) c_int {
    if (PyUnicode_Check(left) == 0 or PyUnicode_Check(right) == 0) {
        PyErr_SetString(&PyExc_TypeError, "can only compare str objects");
        return -1;
    }

    const left_str = PyUnicode_AsUTF8(left) orelse return -1;
    const right_str = PyUnicode_AsUTF8(right) orelse return -1;

    const cmp = std.mem.orderZ(u8, left_str, right_str);
    return switch (cmp) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

/// Check if unicode contains substring
///
/// CPython: int PyUnicode_Contains(PyObject *container, PyObject *element)
/// Returns: 1 if contains, 0 if not, -1 on error
export fn PyUnicode_Contains(container: *cpython.PyObject, element: *cpython.PyObject) callconv(.c) c_int {
    if (PyUnicode_Check(container) == 0 or PyUnicode_Check(element) == 0) {
        PyErr_SetString(&PyExc_TypeError, "can only check str containment");
        return -1;
    }

    const container_str = PyUnicode_AsUTF8(container) orelse return -1;
    const element_str = PyUnicode_AsUTF8(element) orelse return -1;

    const haystack = std.mem.span(container_str);
    const needle = std.mem.span(element_str);

    if (std.mem.indexOf(u8, haystack, needle)) |_| {
        return 1;
    }

    return 0;
}

/// Replace occurrences of substring
///
/// CPython: PyObject* PyUnicode_Replace(PyObject *str, PyObject *substr, PyObject *replstr, Py_ssize_t maxcount)
/// Returns: New string with replacements or null on error
export fn PyUnicode_Replace(str_obj: *cpython.PyObject, substr: *cpython.PyObject, replstr: *cpython.PyObject, maxcount: isize) callconv(.c) ?*cpython.PyObject {
    const str = PyUnicode_AsUTF8(str_obj) orelse return null;
    const old = PyUnicode_AsUTF8(substr) orelse return null;
    const new = PyUnicode_AsUTF8(replstr) orelse return null;

    const str_slice = std.mem.span(str);
    const old_slice = std.mem.span(old);
    const new_slice = std.mem.span(new);

    // Handle empty pattern
    if (old_slice.len == 0) {
        Py_INCREF(str_obj);
        return str_obj;
    }

    var buf: [32768]u8 = undefined;
    var pos: usize = 0;
    var start: usize = 0;
    var count: isize = 0;

    while (start <= str_slice.len) {
        if (maxcount >= 0 and count >= maxcount) {
            // Copy remaining string
            const remaining = str_slice.len - start;
            if (pos + remaining < buf.len) {
                @memcpy(buf[pos .. pos + remaining], str_slice[start..]);
                pos += remaining;
            }
            break;
        }

        if (std.mem.indexOfPos(u8, str_slice, start, old_slice)) |found| {
            // Copy text before match
            const before_len = found - start;
            if (pos + before_len < buf.len) {
                @memcpy(buf[pos .. pos + before_len], str_slice[start..found]);
                pos += before_len;
            }
            // Copy replacement
            if (pos + new_slice.len < buf.len) {
                @memcpy(buf[pos .. pos + new_slice.len], new_slice);
                pos += new_slice.len;
            }
            start = found + old_slice.len;
            count += 1;
        } else {
            // No more matches, copy rest
            const remaining = str_slice.len - start;
            if (pos + remaining < buf.len) {
                @memcpy(buf[pos .. pos + remaining], str_slice[start..]);
                pos += remaining;
            }
            break;
        }
    }

    return PyUnicode_FromStringAndSize(&buf, @intCast(pos));
}

/// Convert to lowercase
///
/// CPython: PyObject* PyUnicode_Lower(PyObject *obj)
/// Returns: Lowercase string or null on error
export fn PyUnicode_Lower(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const str = PyUnicode_AsUTF8(obj) orelse return null;
    const str_slice = std.mem.span(str);

    var buf: [32768]u8 = undefined;
    const len = @min(str_slice.len, buf.len - 1);

    for (0..len) |i| {
        buf[i] = std.ascii.toLower(str_slice[i]);
    }

    return PyUnicode_FromStringAndSize(&buf, @intCast(len));
}

/// Convert to uppercase
///
/// CPython: PyObject* PyUnicode_Upper(PyObject *obj)
/// Returns: Uppercase string or null on error
export fn PyUnicode_Upper(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const str = PyUnicode_AsUTF8(obj) orelse return null;
    const str_slice = std.mem.span(str);

    var buf: [32768]u8 = undefined;
    const len = @min(str_slice.len, buf.len - 1);

    for (0..len) |i| {
        buf[i] = std.ascii.toUpper(str_slice[i]);
    }

    return PyUnicode_FromStringAndSize(&buf, @intCast(len));
}

/// Strip whitespace from both ends
///
/// CPython: PyObject* PyUnicode_Strip(PyObject *obj)
/// Returns: Stripped string or null on error
export fn PyUnicode_Strip(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const str = PyUnicode_AsUTF8(obj) orelse return null;
    const str_slice = std.mem.span(str);

    // Find start (skip leading whitespace)
    var start: usize = 0;
    while (start < str_slice.len and std.ascii.isWhitespace(str_slice[start])) {
        start += 1;
    }

    // Find end (skip trailing whitespace)
    var end: usize = str_slice.len;
    while (end > start and std.ascii.isWhitespace(str_slice[end - 1])) {
        end -= 1;
    }

    return PyUnicode_FromStringAndSize(str + start, @intCast(end - start));
}

/// Strip whitespace from left side only
///
/// CPython: PyObject* PyUnicode_LStrip(PyObject *obj)
/// Returns: Left-stripped string or null on error
export fn PyUnicode_LStrip(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const str = PyUnicode_AsUTF8(obj) orelse return null;
    const str_slice = std.mem.span(str);

    var start: usize = 0;
    while (start < str_slice.len and std.ascii.isWhitespace(str_slice[start])) {
        start += 1;
    }

    return PyUnicode_FromStringAndSize(str + start, @intCast(str_slice.len - start));
}

/// Strip whitespace from right side only
///
/// CPython: PyObject* PyUnicode_RStrip(PyObject *obj)
/// Returns: Right-stripped string or null on error
export fn PyUnicode_RStrip(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const str = PyUnicode_AsUTF8(obj) orelse return null;
    const str_slice = std.mem.span(str);

    var end: usize = str_slice.len;
    while (end > 0 and std.ascii.isWhitespace(str_slice[end - 1])) {
        end -= 1;
    }

    return PyUnicode_FromStringAndSize(str, @intCast(end));
}

/// Check if string starts with prefix
///
/// CPython: int PyUnicode_Tailmatch(PyObject *str, PyObject *substr, Py_ssize_t start, Py_ssize_t end, int direction)
/// direction: -1 for startswith, 1 for endswith
/// Returns: 1 if match, 0 if not, -1 on error
export fn PyUnicode_Tailmatch(str_obj: *cpython.PyObject, substr: *cpython.PyObject, start: isize, end: isize, direction: c_int) callconv(.c) c_int {
    const str = PyUnicode_AsUTF8(str_obj) orelse return -1;
    const prefix = PyUnicode_AsUTF8(substr) orelse return -1;

    const str_slice = std.mem.span(str);
    const prefix_slice = std.mem.span(prefix);

    // Normalize start/end
    var s: usize = 0;
    var e: usize = str_slice.len;

    if (start >= 0) {
        s = @min(@as(usize, @intCast(start)), str_slice.len);
    }
    if (end >= 0) {
        e = @min(@as(usize, @intCast(end)), str_slice.len);
    }

    if (s > e) return 0;

    const substr_len = e - s;
    if (prefix_slice.len > substr_len) return 0;

    if (direction < 0) {
        // startswith
        if (std.mem.startsWith(u8, str_slice[s..e], prefix_slice)) {
            return 1;
        }
    } else {
        // endswith
        if (std.mem.endsWith(u8, str_slice[s..e], prefix_slice)) {
            return 1;
        }
    }

    return 0;
}

/// Find substring in string
///
/// CPython: Py_ssize_t PyUnicode_Find(PyObject *str, PyObject *substr, Py_ssize_t start, Py_ssize_t end, int direction)
/// direction: 1 for forward, -1 for reverse
/// Returns: Index of first match or -1 if not found, -2 on error
export fn PyUnicode_Find(str_obj: *cpython.PyObject, substr: *cpython.PyObject, start: isize, end: isize, direction: c_int) callconv(.c) isize {
    const str = PyUnicode_AsUTF8(str_obj) orelse return -2;
    const needle = PyUnicode_AsUTF8(substr) orelse return -2;

    const str_slice = std.mem.span(str);
    const needle_slice = std.mem.span(needle);

    // Normalize start/end
    var s: usize = 0;
    var e: usize = str_slice.len;

    if (start >= 0) {
        s = @min(@as(usize, @intCast(start)), str_slice.len);
    }
    if (end >= 0) {
        e = @min(@as(usize, @intCast(end)), str_slice.len);
    }

    if (s > e or needle_slice.len > e - s) return -1;

    if (direction >= 0) {
        // Forward search
        if (std.mem.indexOf(u8, str_slice[s..e], needle_slice)) |pos| {
            return @intCast(s + pos);
        }
    } else {
        // Reverse search
        if (std.mem.lastIndexOf(u8, str_slice[s..e], needle_slice)) |pos| {
            return @intCast(s + pos);
        }
    }

    return -1;
}

/// Count occurrences of substring
///
/// CPython: Py_ssize_t PyUnicode_Count(PyObject *str, PyObject *substr, Py_ssize_t start, Py_ssize_t end)
/// Returns: Count of non-overlapping occurrences, -1 on error
export fn PyUnicode_Count(str_obj: *cpython.PyObject, substr: *cpython.PyObject, start: isize, end: isize) callconv(.c) isize {
    const str = PyUnicode_AsUTF8(str_obj) orelse return -1;
    const needle = PyUnicode_AsUTF8(substr) orelse return -1;

    const str_slice = std.mem.span(str);
    const needle_slice = std.mem.span(needle);

    // Normalize start/end
    var s: usize = 0;
    var e: usize = str_slice.len;

    if (start >= 0) {
        s = @min(@as(usize, @intCast(start)), str_slice.len);
    }
    if (end >= 0) {
        e = @min(@as(usize, @intCast(end)), str_slice.len);
    }

    if (s > e) return 0;
    if (needle_slice.len == 0) return @intCast(e - s + 1);

    var count: isize = 0;
    var pos: usize = s;

    while (pos + needle_slice.len <= e) {
        if (std.mem.indexOfPos(u8, str_slice[0..e], pos, needle_slice)) |found| {
            count += 1;
            pos = found + needle_slice.len;
        } else {
            break;
        }
    }

    return count;
}

/// Get substring (slice)
///
/// CPython: PyObject* PyUnicode_Substring(PyObject *str, Py_ssize_t start, Py_ssize_t end)
/// Returns: New string with slice or null on error
export fn PyUnicode_Substring(str_obj: *cpython.PyObject, start: isize, end: isize) callconv(.c) ?*cpython.PyObject {
    const str = PyUnicode_AsUTF8(str_obj) orelse return null;
    const str_slice = std.mem.span(str);

    // Normalize bounds
    var s: usize = 0;
    var e: usize = str_slice.len;

    if (start >= 0) {
        s = @min(@as(usize, @intCast(start)), str_slice.len);
    }
    if (end >= 0) {
        e = @min(@as(usize, @intCast(end)), str_slice.len);
    }

    if (s >= e) return PyUnicode_FromString("");

    return PyUnicode_FromStringAndSize(str + s, @intCast(e - s));
}

/// Title case string (first letter of each word uppercase)
///
/// CPython: PyObject* PyUnicode_Title(PyObject *str)
/// Returns: Title-cased string or null on error
export fn PyUnicode_Title(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const str = PyUnicode_AsUTF8(obj) orelse return null;
    const str_slice = std.mem.span(str);

    var buf: [32768]u8 = undefined;
    const len = @min(str_slice.len, buf.len - 1);

    var prev_space = true;
    for (0..len) |i| {
        const c = str_slice[i];
        if (std.ascii.isWhitespace(c)) {
            buf[i] = c;
            prev_space = true;
        } else if (prev_space) {
            buf[i] = std.ascii.toUpper(c);
            prev_space = false;
        } else {
            buf[i] = std.ascii.toLower(c);
        }
    }

    return PyUnicode_FromStringAndSize(&buf, @intCast(len));
}

/// Capitalize string (first letter uppercase, rest lowercase)
///
/// CPython: PyObject* PyUnicode_Capitalize(PyObject *str)
/// Returns: Capitalized string or null on error
export fn PyUnicode_Capitalize(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const str = PyUnicode_AsUTF8(obj) orelse return null;
    const str_slice = std.mem.span(str);

    if (str_slice.len == 0) return PyUnicode_FromString("");

    var buf: [32768]u8 = undefined;
    const len = @min(str_slice.len, buf.len - 1);

    buf[0] = std.ascii.toUpper(str_slice[0]);
    for (1..len) |i| {
        buf[i] = std.ascii.toLower(str_slice[i]);
    }

    return PyUnicode_FromStringAndSize(&buf, @intCast(len));
}

/// Swap case (upper to lower, lower to upper)
///
/// CPython: PyObject* PyUnicode_SwapCase(PyObject *str)
/// Returns: Swapped-case string or null on error
export fn PyUnicode_SwapCase(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const str = PyUnicode_AsUTF8(obj) orelse return null;
    const str_slice = std.mem.span(str);

    var buf: [32768]u8 = undefined;
    const len = @min(str_slice.len, buf.len - 1);

    for (0..len) |i| {
        const c = str_slice[i];
        if (std.ascii.isUpper(c)) {
            buf[i] = std.ascii.toLower(c);
        } else if (std.ascii.isLower(c)) {
            buf[i] = std.ascii.toUpper(c);
        } else {
            buf[i] = c;
        }
    }

    return PyUnicode_FromStringAndSize(&buf, @intCast(len));
}

/// Check if string is alphanumeric
///
/// Returns: 1 if all alphanumeric and not empty, 0 otherwise
export fn PyUnicode_IsAlnum(obj: *cpython.PyObject) callconv(.c) c_int {
    const str = PyUnicode_AsUTF8(obj) orelse return 0;
    const str_slice = std.mem.span(str);

    if (str_slice.len == 0) return 0;

    for (str_slice) |c| {
        if (!std.ascii.isAlphanumeric(c)) return 0;
    }
    return 1;
}

/// Check if string is alphabetic
///
/// Returns: 1 if all alphabetic and not empty, 0 otherwise
export fn PyUnicode_IsAlpha(obj: *cpython.PyObject) callconv(.c) c_int {
    const str = PyUnicode_AsUTF8(obj) orelse return 0;
    const str_slice = std.mem.span(str);

    if (str_slice.len == 0) return 0;

    for (str_slice) |c| {
        if (!std.ascii.isAlphabetic(c)) return 0;
    }
    return 1;
}

/// Check if string is all digits
///
/// Returns: 1 if all digits and not empty, 0 otherwise
export fn PyUnicode_IsDigit(obj: *cpython.PyObject) callconv(.c) c_int {
    const str = PyUnicode_AsUTF8(obj) orelse return 0;
    const str_slice = std.mem.span(str);

    if (str_slice.len == 0) return 0;

    for (str_slice) |c| {
        if (!std.ascii.isDigit(c)) return 0;
    }
    return 1;
}

/// Check if string is all lowercase
///
/// Returns: 1 if all lowercase letters and has at least one cased char, 0 otherwise
export fn PyUnicode_IsLower(obj: *cpython.PyObject) callconv(.c) c_int {
    const str = PyUnicode_AsUTF8(obj) orelse return 0;
    const str_slice = std.mem.span(str);

    var has_cased = false;
    for (str_slice) |c| {
        if (std.ascii.isUpper(c)) return 0;
        if (std.ascii.isLower(c)) has_cased = true;
    }
    return if (has_cased) 1 else 0;
}

/// Check if string is all uppercase
///
/// Returns: 1 if all uppercase letters and has at least one cased char, 0 otherwise
export fn PyUnicode_IsUpper(obj: *cpython.PyObject) callconv(.c) c_int {
    const str = PyUnicode_AsUTF8(obj) orelse return 0;
    const str_slice = std.mem.span(str);

    var has_cased = false;
    for (str_slice) |c| {
        if (std.ascii.isLower(c)) return 0;
        if (std.ascii.isUpper(c)) has_cased = true;
    }
    return if (has_cased) 1 else 0;
}

/// Check if string is whitespace
///
/// Returns: 1 if all whitespace and not empty, 0 otherwise
export fn PyUnicode_IsSpace(obj: *cpython.PyObject) callconv(.c) c_int {
    const str = PyUnicode_AsUTF8(obj) orelse return 0;
    const str_slice = std.mem.span(str);

    if (str_slice.len == 0) return 0;

    for (str_slice) |c| {
        if (!std.ascii.isWhitespace(c)) return 0;
    }
    return 1;
}

/// Check if string is title-cased
///
/// Returns: 1 if title-cased, 0 otherwise
export fn PyUnicode_IsTitle(obj: *cpython.PyObject) callconv(.c) c_int {
    const str = PyUnicode_AsUTF8(obj) orelse return 0;
    const str_slice = std.mem.span(str);

    if (str_slice.len == 0) return 0;

    var prev_space = true;
    var has_cased = false;

    for (str_slice) |c| {
        if (std.ascii.isWhitespace(c)) {
            prev_space = true;
        } else if (prev_space) {
            if (!std.ascii.isUpper(c) and std.ascii.isAlphabetic(c)) return 0;
            if (std.ascii.isAlphabetic(c)) has_cased = true;
            prev_space = false;
        } else {
            if (std.ascii.isUpper(c)) return 0;
            if (std.ascii.isLower(c)) has_cased = true;
        }
    }

    return if (has_cased) 1 else 0;
}

// ============================================================================
// TESTS
// ============================================================================

test "PyUnicode functions exist" {
    const testing = std.testing;

    // Verify that all essential functions are defined
    const funcs = .{
        PyUnicode_FromString,
        PyUnicode_FromStringAndSize,
        PyUnicode_AsUTF8,
        PyUnicode_AsUTF8AndSize,
        PyUnicode_GetLength,
        PyUnicode_Check,
        PyUnicode_Concat,
        PyUnicode_Format,
        PyUnicode_Join,
        PyUnicode_Split,
        PyUnicode_DecodeUTF8,
        PyUnicode_AsUTF8String,
        PyUnicode_Compare,
        PyUnicode_Contains,
        PyUnicode_Replace,
        PyUnicode_Lower,
        PyUnicode_Upper,
        PyUnicode_Strip,
        PyUnicode_LStrip,
        PyUnicode_RStrip,
        PyUnicode_Tailmatch,
        PyUnicode_Find,
        PyUnicode_Count,
        PyUnicode_Substring,
        PyUnicode_Title,
        PyUnicode_Capitalize,
        PyUnicode_SwapCase,
        PyUnicode_IsAlnum,
        PyUnicode_IsAlpha,
        PyUnicode_IsDigit,
        PyUnicode_IsLower,
        PyUnicode_IsUpper,
        PyUnicode_IsSpace,
        PyUnicode_IsTitle,
    };

    inline for (funcs) |func| {
        _ = func;
    }

    try testing.expect(true);
}

test "PyUnicodeObject size" {
    const testing = std.testing;

    // Verify PyUnicodeObject has correct size
    try testing.expect(@sizeOf(PyUnicodeObject) >= @sizeOf(cpython.PyVarObject));
}
