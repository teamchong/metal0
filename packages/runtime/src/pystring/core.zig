/// Core PyString operations - creation, access, concatenation
/// CPython ABI compatible using PyUnicodeObject
const std = @import("std");
const runtime = @import("../runtime.zig");
const PyObject = runtime.PyObject;
const PyUnicodeObject = runtime.PyUnicodeObject;
const PyUnicode_Type = &runtime.PyUnicode_Type;
const PythonError = runtime.PythonError;

// Unicode state flags (simplified from CPython)
const UNICODE_ASCII: u32 = 0x0001;
const UNICODE_READY: u32 = 0x0002;

/// Python string type using CPython-compatible PyUnicodeObject
pub const PyString = struct {
    // Legacy fields for compatibility
    data: []const u8 = undefined,
    source: ?*PyObject = null,

    pub fn create(allocator: std.mem.Allocator, str: []const u8) !*PyObject {
        const str_obj = try allocator.create(PyUnicodeObject);

        // Copy string data
        const owned = try allocator.dupe(u8, str);

        str_obj.* = PyUnicodeObject{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = PyUnicode_Type,
            },
            .length = @intCast(str.len),
            .hash = -1, // Not computed yet
            .state = UNICODE_ASCII | UNICODE_READY,
            ._padding = 0,
            .data = owned.ptr,
        };
        return @ptrCast(str_obj);
    }

    /// Check if this string is borrowed (COW) - not used in new layout
    pub fn isBorrowed(obj: *PyObject) bool {
        _ = obj;
        return false; // New layout doesn't use COW
    }

    /// Free PyString resources
    pub fn deinit(obj: *PyObject, allocator: std.mem.Allocator) void {
        std.debug.assert(runtime.PyUnicode_Check(obj));
        const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));

        const str_len: usize = @intCast(str_obj.length);
        if (str_len > 0) {
            allocator.free(str_obj.data[0..str_len]);
        }
        allocator.destroy(str_obj);
    }

    /// Create PyString with owned data (takes ownership, no duplication)
    pub fn createOwned(allocator: std.mem.Allocator, owned_str: []const u8) !*PyObject {
        const str_obj = try allocator.create(PyUnicodeObject);

        str_obj.* = PyUnicodeObject{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = PyUnicode_Type,
            },
            .length = @intCast(owned_str.len),
            .hash = -1,
            .state = UNICODE_ASCII | UNICODE_READY,
            ._padding = 0,
            .data = owned_str.ptr,
        };
        return @ptrCast(str_obj);
    }

    /// Create PyString borrowing from another - new layout copies instead
    pub fn createBorrowed(allocator: std.mem.Allocator, source_obj: *PyObject, slice: []const u8) !*PyObject {
        _ = source_obj; // Not used - we copy instead of borrow in new layout
        return create(allocator, slice);
    }

    pub fn getValue(obj: *PyObject) []const u8 {
        std.debug.assert(runtime.PyUnicode_Check(obj));
        const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
        const str_len: usize = @intCast(str_obj.length);
        return str_obj.data[0..str_len];
    }

    pub fn len(obj: *PyObject) usize {
        std.debug.assert(runtime.PyUnicode_Check(obj));
        const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
        return @intCast(str_obj.length);
    }

    pub fn getItem(allocator: std.mem.Allocator, obj: *PyObject, index: i64) !*PyObject {
        std.debug.assert(runtime.PyUnicode_Check(obj));
        const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
        const str_len: usize = @intCast(str_obj.length);

        const idx: usize = @intCast(index);
        if (idx >= str_len) {
            return PythonError.IndexError;
        }

        // Return single character as a new string
        const result = try allocator.alloc(u8, 1);
        result[0] = str_obj.data[idx];

        return createOwned(allocator, result);
    }

    pub fn charAt(allocator: std.mem.Allocator, obj: *PyObject, index_val: i64) !*PyObject {
        std.debug.assert(runtime.PyUnicode_Check(obj));
        const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
        const str_len: i64 = str_obj.length;

        // Handle negative indices
        const idx = if (index_val < 0) str_len + index_val else index_val;

        if (idx < 0 or idx >= str_len) {
            return PythonError.IndexError;
        }

        // Return single character as a new string
        const result = try allocator.alloc(u8, 1);
        result[0] = str_obj.data[@intCast(idx)];

        return createOwned(allocator, result);
    }

    pub fn concat(allocator: std.mem.Allocator, a: *PyObject, b: *PyObject) !*PyObject {
        std.debug.assert(runtime.PyUnicode_Check(a));
        std.debug.assert(runtime.PyUnicode_Check(b));

        const a_obj: *PyUnicodeObject = @ptrCast(@alignCast(a));
        const b_obj: *PyUnicodeObject = @ptrCast(@alignCast(b));

        const a_len: usize = @intCast(a_obj.length);
        const b_len: usize = @intCast(b_obj.length);

        const result = try allocator.alloc(u8, a_len + b_len);
        @memcpy(result[0..a_len], a_obj.data[0..a_len]);
        @memcpy(result[a_len..], b_obj.data[0..b_len]);

        return createOwned(allocator, result);
    }

    /// Optimized concatenation for multiple strings - single allocation
    pub fn concatMulti(allocator: std.mem.Allocator, strings: []const *PyObject) !*PyObject {
        if (strings.len == 0) {
            return try create(allocator, "");
        }
        if (strings.len == 1) {
            runtime.incref(strings[0]);
            return strings[0];
        }

        // Calculate total length
        var total_len: usize = 0;
        for (strings) |str| {
            std.debug.assert(runtime.PyUnicode_Check(str));
            const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(str));
            total_len += @as(usize, @intCast(str_obj.length));
        }

        // Allocate result buffer once
        const result = try allocator.alloc(u8, total_len);
        var pos: usize = 0;

        // Copy all strings
        for (strings) |str| {
            const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(str));
            const str_len: usize = @intCast(str_obj.length);
            @memcpy(result[pos .. pos + str_len], str_obj.data[0..str_len]);
            pos += str_len;
        }

        return createOwned(allocator, result);
    }

    pub fn toInt(obj: *PyObject) !i64 {
        const str_val = getValue(obj);
        return std.fmt.parseInt(i64, str_val, 10);
    }
};

// CPython-compatible C API functions
pub fn PyUnicode_FromString(str: [*:0]const u8) callconv(.C) *PyObject {
    const allocator = std.heap.page_allocator;
    const len = std.mem.len(str);
    return PyString.create(allocator, str[0..len]) catch @panic("PyUnicode_FromString allocation failed");
}

pub fn PyUnicode_FromStringAndSize(str: [*]const u8, size: runtime.Py_ssize_t) callconv(.C) *PyObject {
    const allocator = std.heap.page_allocator;
    const len: usize = @intCast(size);
    return PyString.create(allocator, str[0..len]) catch @panic("PyUnicode_FromStringAndSize allocation failed");
}

pub fn PyUnicode_GetLength(obj: *PyObject) callconv(.C) runtime.Py_ssize_t {
    const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
    return str_obj.length;
}

pub fn PyUnicode_AsUTF8(obj: *PyObject) callconv(.C) [*]const u8 {
    const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
    return str_obj.data;
}

pub fn PyUnicode_AsUTF8AndSize(obj: *PyObject, size: *runtime.Py_ssize_t) callconv(.C) [*]const u8 {
    const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
    size.* = str_obj.length;
    return str_obj.data;
}
