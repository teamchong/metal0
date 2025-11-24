/// Python unicode (str) object implementation
///
/// Simplified UTF-8 storage for "make it work" phase

const std = @import("std");
const cpython = @import("cpython_object.zig");
const opt = @import("optimization_helpers.zig");

const allocator = std.heap.c_allocator;

/// PyUnicodeObject - Python string (UTF-8 storage)
pub const PyUnicodeObject = extern struct {
    ob_base: cpython.PyObject,
    length: isize,        // Length in characters (not bytes)
    hash: isize,          // Cached hash (-1 if not computed)
    utf8: ?[*:0]u8,      // UTF-8 encoded string
    utf8_length: isize,   // Length in bytes
};

// Forward declarations
fn unicode_dealloc(obj: *cpython.PyObject) callconv(.c) void;
fn unicode_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn unicode_str(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;
fn unicode_hash(obj: *cpython.PyObject) callconv(.c) isize;
fn unicode_concat(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject;

/// Sequence protocol for strings
var unicode_as_sequence: cpython.PySequenceMethods = .{
    .sq_length = unicode_length,
    .sq_concat = unicode_concat,
    .sq_repeat = null,
    .sq_item = null,
    .sq_ass_item = null,
    .sq_contains = null,
    .sq_inplace_concat = null,
    .sq_inplace_repeat = null,
};

fn unicode_length(obj: *cpython.PyObject) callconv(.c) isize {
    const str_obj = @as(*PyUnicodeObject, @ptrCast(obj));
    return str_obj.length;
}

/// PyUnicode_Type - the 'str' type
pub var PyUnicode_Type: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "str",
    .tp_basicsize = @sizeOf(PyUnicodeObject),
    .tp_itemsize = 0,
    .tp_dealloc = unicode_dealloc,
    .tp_repr = unicode_repr,
    .tp_as_sequence = &unicode_as_sequence,
    .tp_hash = unicode_hash,
    .tp_str = unicode_str,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "str(object='') -> string",
    // Other slots null
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_as_number = null,
    .tp_as_mapping = null,
    .tp_call = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
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
// Core API Functions
// ============================================================================

/// Create Unicode from UTF-8 C string
export fn PyUnicode_FromString(str: [*:0]const u8) callconv(.c) ?*cpython.PyObject {
    const len = std.mem.len(str);
    return PyUnicode_FromStringAndSize(str, @intCast(len));
}

/// Create Unicode from UTF-8 buffer with size
export fn PyUnicode_FromStringAndSize(str: ?[*]const u8, size: isize) callconv(.c) ?*cpython.PyObject {
    if (size < 0) return null;
    
    const obj = allocator.create(PyUnicodeObject) catch return null;
    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = &PyUnicode_Type;
    obj.hash = -1;
    obj.utf8_length = size;
    
    // Allocate UTF-8 buffer
    if (size == 0) {
        obj.utf8 = "";
        obj.length = 0;
    } else if (str) |s| {
        const buffer = allocator.allocSentinel(u8, @intCast(size), 0) catch {
            allocator.destroy(obj);
            return null;
        };
        @memcpy(buffer[0..@intCast(size)], s[0..@intCast(size)]);
        obj.utf8 = buffer.ptr;
        
        // Count UTF-8 characters (simplified - just count non-continuation bytes)
        var char_count: isize = 0;
        for (buffer) |byte| {
            if ((byte & 0xC0) != 0x80) {
                char_count += 1;
            }
        }
        obj.length = char_count;
    } else {
        obj.utf8 = null;
        obj.length = 0;
    }
    
    return @ptrCast(&obj.ob_base);
}

/// Create Unicode from format string
export fn PyUnicode_FromFormat(format: [*:0]const u8, ...) callconv(.c) ?*cpython.PyObject {
    // TODO: Implement printf-style formatting
    _ = format;
    return null;
}

/// Get UTF-8 representation
export fn PyUnicode_AsUTF8(obj: *cpython.PyObject) callconv(.c) ?[*:0]const u8 {
    if (PyUnicode_Check(obj) == 0) return null;
    
    const str_obj = @as(*PyUnicodeObject, @ptrCast(obj));
    return str_obj.utf8;
}

/// Get UTF-8 with size
export fn PyUnicode_AsUTF8AndSize(obj: *cpython.PyObject, size: ?*isize) callconv(.c) ?[*:0]const u8 {
    if (PyUnicode_Check(obj) == 0) return null;
    
    const str_obj = @as(*PyUnicodeObject, @ptrCast(obj));
    if (size) |s| {
        s.* = str_obj.utf8_length;
    }
    return str_obj.utf8;
}

/// Get character length
export fn PyUnicode_GetLength(obj: *cpython.PyObject) callconv(.c) isize {
    if (PyUnicode_Check(obj) == 0) return -1;
    
    const str_obj = @as(*PyUnicodeObject, @ptrCast(obj));
    return str_obj.length;
}

/// Type check
export fn PyUnicode_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    return if (type_obj == &PyUnicode_Type) 1 else 0;
}

/// Exact type check
export fn PyUnicode_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    return if (type_obj == &PyUnicode_Type) 1 else 0;
}

/// Decode UTF-8 bytes to Unicode
export fn PyUnicode_DecodeUTF8(data: [*]const u8, size: isize, errors: ?[*:0]const u8) callconv(.c) ?*cpython.PyObject {
    _ = errors; // Ignore error handling for now
    return PyUnicode_FromStringAndSize(data, size);
}

/// Encode Unicode to UTF-8 bytes
export fn PyUnicode_AsUTF8String(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyUnicode_Check(obj) == 0) return null;
    
    const str_obj = @as(*PyUnicodeObject, @ptrCast(obj));
    
    // TODO: Return PyBytesObject wrapping utf8 data
    // For now just return null
    _ = str_obj;
    return null;
}

/// Concatenate two strings
export fn PyUnicode_Concat(left: *cpython.PyObject, right: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    if (PyUnicode_Check(left) == 0 or PyUnicode_Check(right) == 0) {
        return null;
    }
    
    return unicode_concat(left, right);
}

/// Join strings with separator
export fn PyUnicode_Join(sep: *cpython.PyObject, seq: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // TODO: Join sequence of strings with separator
    _ = sep;
    _ = seq;
    return null;
}

/// Format string
export fn PyUnicode_Format(format: *cpython.PyObject, args: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // TODO: Python % formatting
    _ = format;
    _ = args;
    return null;
}

/// Compare strings
export fn PyUnicode_Compare(left: *cpython.PyObject, right: *cpython.PyObject) callconv(.c) c_int {
    if (PyUnicode_Check(left) == 0 or PyUnicode_Check(right) == 0) {
        return -1;
    }
    
    const left_str = @as(*PyUnicodeObject, @ptrCast(left));
    const right_str = @as(*PyUnicodeObject, @ptrCast(right));
    
    if (left_str.utf8 == null or right_str.utf8 == null) return -1;
    
    const left_bytes = left_str.utf8.?[0..@intCast(left_str.utf8_length)];
    const right_bytes = right_str.utf8.?[0..@intCast(right_str.utf8_length)];
    
    return std.mem.order(u8, left_bytes, right_bytes).compare(std.math.CompareOperator.eq);
}

/// Find substring
export fn PyUnicode_Find(str: *cpython.PyObject, substr: *cpython.PyObject, start: isize, end: isize, direction: c_int) callconv(.c) isize {
    // TODO: Implement substring search
    _ = str;
    _ = substr;
    _ = start;
    _ = end;
    _ = direction;
    return -1;
}

/// Count occurrences
export fn PyUnicode_Count(str: *cpython.PyObject, substr: *cpython.PyObject, start: isize, end: isize) callconv(.c) isize {
    // TODO: Count substring occurrences
    _ = str;
    _ = substr;
    _ = start;
    _ = end;
    return -1;
}

/// Replace substring
export fn PyUnicode_Replace(str: *cpython.PyObject, substr: *cpython.PyObject, replstr: *cpython.PyObject, maxcount: isize) callconv(.c) ?*cpython.PyObject {
    // TODO: Replace substring
    _ = str;
    _ = substr;
    _ = replstr;
    _ = maxcount;
    return null;
}

/// Split string
export fn PyUnicode_Split(str: *cpython.PyObject, sep: ?*cpython.PyObject, maxsplit: isize) callconv(.c) ?*cpython.PyObject {
    // TODO: Split into list
    _ = str;
    _ = sep;
    _ = maxsplit;
    return null;
}

/// Substring
export fn PyUnicode_Substring(str: *cpython.PyObject, start: isize, end: isize) callconv(.c) ?*cpython.PyObject {
    if (PyUnicode_Check(str) == 0) return null;
    
    const str_obj = @as(*PyUnicodeObject, @ptrCast(str));
    
    // Clamp indices
    var real_start = start;
    var real_end = end;
    
    if (real_start < 0) real_start = 0;
    if (real_end > str_obj.length) real_end = str_obj.length;
    if (real_start >= real_end) return PyUnicode_FromStringAndSize(null, 0);
    
    // TODO: Handle UTF-8 slicing properly (need to find byte positions)
    // For now, simplified version
    _ = real_start;
    _ = real_end;
    
    return null;
}

// ============================================================================
// Internal Methods
// ============================================================================

fn unicode_concat(a: *cpython.PyObject, b: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const a_str = @as(*PyUnicodeObject, @ptrCast(a));
    const b_str = @as(*PyUnicodeObject, @ptrCast(b));
    
    if (a_str.utf8 == null or b_str.utf8 == null) return null;
    
    const total_len = a_str.utf8_length + b_str.utf8_length;
    const buffer = allocator.allocSentinel(u8, @intCast(total_len), 0) catch return null;
    
    @memcpy(buffer[0..@intCast(a_str.utf8_length)], a_str.utf8.?[0..@intCast(a_str.utf8_length)]);
    @memcpy(buffer[@intCast(a_str.utf8_length)..@intCast(total_len)], b_str.utf8.?[0..@intCast(b_str.utf8_length)]);
    
    const obj = allocator.create(PyUnicodeObject) catch {
        allocator.free(buffer);
        return null;
    };
    
    obj.ob_base.ob_refcnt = 1;
    obj.ob_base.ob_type = &PyUnicode_Type;
    obj.length = a_str.length + b_str.length;
    obj.hash = -1;
    obj.utf8 = buffer.ptr;
    obj.utf8_length = total_len;
    
    return @ptrCast(&obj.ob_base);
}

fn unicode_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const str_obj = @as(*PyUnicodeObject, @ptrCast(obj));
    
    if (str_obj.utf8) |utf8| {
        if (str_obj.utf8_length > 0) {
            const slice = utf8[0..@intCast(str_obj.utf8_length)];
            allocator.free(slice);
        }
    }
    
    allocator.destroy(str_obj);
}

fn unicode_repr(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // TODO: Return quoted string representation
    const str_obj = @as(*PyUnicodeObject, @ptrCast(obj));
    _ = str_obj;
    return null;
}

fn unicode_str(obj: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    // String representation is itself
    obj.ob_refcnt += 1;
    return obj;
}

fn unicode_hash(obj: *cpython.PyObject) callconv(.c) isize {
    const str_obj = @as(*PyUnicodeObject, @ptrCast(obj));

    // Return cached hash if available
    if (str_obj.hash != -1) {
        return str_obj.hash;
    }

    // Compute hash using wyhash (1.05x faster than djb2, from Bun)
    if (str_obj.utf8 == null) return 0;

    const bytes = str_obj.utf8.?[0..@intCast(str_obj.utf8_length)];
    const hash = opt.hashString(bytes);

    const result: isize = @intCast(hash);
    str_obj.hash = result;
    return result;
}

// Tests
test "unicode exports" {
    _ = PyUnicode_FromString;
    _ = PyUnicode_AsUTF8;
    _ = PyUnicode_Check;
}
