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

// External dependencies
extern fn Py_INCREF(*cpython.PyObject) callconv(.c) void;
extern fn Py_DECREF(*cpython.PyObject) callconv(.c) void;
extern fn PyErr_SetString(*cpython.PyObject, [*:0]const u8) callconv(.c) void;
extern fn PyMem_Malloc(usize) callconv(.c) ?*anyopaque;
extern fn PyMem_Free(?*anyopaque) callconv(.c) void;
extern fn PyObject_Malloc(usize) callconv(.c) ?*anyopaque;
extern fn PyObject_Free(?*anyopaque) callconv(.c) void;

// Exception types
extern var PyExc_TypeError: cpython.PyObject;
extern var PyExc_ValueError: cpython.PyObject;

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
        .tp_repr = unicode_repr,
        .tp_hash = unicode_hash,
        .tp_call = null,
        .tp_str = unicode_str,
        .tp_getattro = null,
        .tp_setattro = null,
    };

    unicode_type_initialized = true;
}

/// Destructor for unicode objects
fn unicode_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const unicode = @as(*PyUnicodeObject, @ptrCast(obj));

    // Get unicode data
    const data_ptr = @intFromPtr(unicode) + @sizeOf(PyUnicodeObject);
    const data = @as(*?*UnicodeData, @ptrFromInt(data_ptr)).*;

    if (data) |d| {
        // Free UTF-8 buffer
        PyMem_Free(d.utf8);
        // Free data structure
        PyObject_Free(d);
    }

    // Free object itself
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
    const unicode = @as(*PyUnicodeObject, @ptrCast(obj));
    const data_ptr = @intFromPtr(unicode) + @sizeOf(PyUnicodeObject);
    const data = @as(*?*UnicodeData, @ptrFromInt(data_ptr)).*;

    if (data) |d| {
        // Simple hash using wyhash
        const bytes = d.utf8[0..d.byte_length];
        const hash = std.hash.Wyhash.hash(0, bytes);
        return @intCast(hash);
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
    const data_ptr_addr = @intFromPtr(unicode) + @sizeOf(PyUnicodeObject);
    @as(*?*UnicodeData, @ptrFromInt(data_ptr_addr)).* = data;

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

    const unicode = @as(*PyUnicodeObject, @ptrCast(obj));
    const data_ptr = @intFromPtr(unicode) + @sizeOf(PyUnicodeObject);
    const data = @as(*?*UnicodeData, @ptrFromInt(data_ptr)).*;

    if (data) |d| {
        return d.utf8;
    }

    return null;
}

/// Get UTF-8 C string with size
///
/// CPython: const char* PyUnicode_AsUTF8AndSize(PyObject *obj, Py_ssize_t *size)
/// Returns: C string and writes size to size pointer
export fn PyUnicode_AsUTF8AndSize(obj: *cpython.PyObject, size: *isize) callconv(.c) ?[*:0]const u8 {
    const str = PyUnicode_AsUTF8(obj) orelse return null;

    const unicode = @as(*PyUnicodeObject, @ptrCast(obj));
    const data_ptr = @intFromPtr(unicode) + @sizeOf(PyUnicodeObject);
    const data = @as(*?*UnicodeData, @ptrFromInt(data_ptr)).*;

    if (data) |d| {
        size.* = @intCast(d.byte_length);
    }

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

    const unicode = @as(*PyUnicodeObject, @ptrCast(obj));
    const data_ptr = @intFromPtr(unicode) + @sizeOf(PyUnicodeObject);
    const data = @as(*?*UnicodeData, @ptrFromInt(data_ptr)).*;

    if (data) |d| {
        return @intCast(d.length);
    }

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
    const type_name = std.mem.span(type_obj.tp_name);
    if (std.mem.eql(u8, type_name, "str")) {
        return 1;
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
    _ = separator;
    _ = seq;

    // TODO: Implement join operation
    PyErr_SetString(&PyExc_TypeError, "join not yet implemented");
    return null;
}

/// Split string by separator
///
/// CPython: PyObject* PyUnicode_Split(PyObject *s, PyObject *sep, Py_ssize_t maxsplit)
/// Returns: List of substrings or null on error
export fn PyUnicode_Split(s: *cpython.PyObject, sep: ?*cpython.PyObject, maxsplit: isize) callconv(.c) ?*cpython.PyObject {
    _ = s;
    _ = sep;
    _ = maxsplit;

    // TODO: Implement split operation
    PyErr_SetString(&PyExc_TypeError, "split not yet implemented");
    return null;
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
    _ = obj;
    // TODO: Return PyBytes object with UTF-8 encoding
    PyErr_SetString(&PyExc_TypeError, "UTF-8 encoding not yet implemented");
    return null;
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
export fn PyUnicode_Replace(str: *cpython.PyObject, substr: *cpython.PyObject, replstr: *cpython.PyObject, maxcount: isize) callconv(.c) ?*cpython.PyObject {
    _ = str;
    _ = substr;
    _ = replstr;
    _ = maxcount;

    // TODO: Implement replace operation
    PyErr_SetString(&PyExc_TypeError, "replace not yet implemented");
    return null;
}

/// Convert to lowercase
///
/// CPython: PyObject* PyUnicode_Lower(PyObject *obj)
/// Returns: Lowercase string or null on error
export fn PyUnicode_Lower(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = obj;

    // TODO: Implement lowercase conversion
    PyErr_SetString(&PyExc_TypeError, "lower not yet implemented");
    return null;
}

/// Convert to uppercase
///
/// CPython: PyObject* PyUnicode_Upper(PyObject *obj)
/// Returns: Uppercase string or null on error
export fn PyUnicode_Upper(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = obj;

    // TODO: Implement uppercase conversion
    PyErr_SetString(&PyExc_TypeError, "upper not yet implemented");
    return null;
}

/// Strip whitespace from both ends
///
/// CPython: PyObject* PyUnicode_Strip(PyObject *obj)
/// Returns: Stripped string or null on error
export fn PyUnicode_Strip(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    _ = obj;

    // TODO: Implement strip operation
    PyErr_SetString(&PyExc_TypeError, "strip not yet implemented");
    return null;
}

// ============================================================================
// TESTS
// ============================================================================

test "PyUnicode functions exist" {
    const testing = std.testing;

    // Verify that all essential functions are defined
    // Actual functionality tests require linking with full CPython implementation
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
    };

    // 18 core functions
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
