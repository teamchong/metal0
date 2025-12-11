/// PyTuple implementation - Python tuple type (CPython ABI compatible)
const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const runtime = @import("../runtime.zig");

const PyObject = runtime.PyObject;
const PyTupleObject = runtime.PyTupleObject;
const PyTuple_Type = &runtime.cpython.PyTuple_Type;
const PyLongObject = runtime.PyLongObject;
const PyUnicodeObject = runtime.PyUnicodeObject;
const incref = runtime.incref;
const PythonError = runtime.PythonError;

/// Python tuple type (CPython ABI compatible)
pub const PyTuple = struct {
    // Legacy fields for backwards compatibility
    items: []*PyObject = undefined,
    allocator: std.mem.Allocator = undefined,

    pub fn create(allocator: std.mem.Allocator, size: usize) !*PyObject {
        const tuple_obj = try allocator.create(PyTupleObject);

        // Allocate fixed-size array for items
        const items = try allocator.alloc(*PyObject, size);

        tuple_obj.* = PyTupleObject{
            .ob_base = .{
                .ob_base = .{
                    .ob_refcnt = 1,
                    .ob_type = PyTuple_Type,
                },
                .ob_size = @intCast(size),
            },
            .ob_item = items.ptr,
        };
        return @ptrCast(tuple_obj);
    }

    /// Create tuple from array of PyObjects (takes ownership of items)
    pub fn createFromArray(allocator: std.mem.Allocator, items: []const *PyObject) !*PyObject {
        const obj = try create(allocator, items.len);
        const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));

        for (items, 0..) |item, i| {
            tuple_obj.ob_item[i] = item;
        }

        return obj;
    }

    pub fn fromSlice(allocator: std.mem.Allocator, values: []const PyObject.Value) !*PyObject {
        const obj = try create(allocator, values.len);
        const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));

        for (values, 0..) |value, i| {
            const item = try runtime.PyInt.create(allocator, value.int);
            tuple_obj.ob_item[i] = item;
        }

        return obj;
    }

    pub fn setItem(obj: *PyObject, idx: usize, item: *PyObject) void {
        std.debug.assert(runtime.PyTuple_Check(obj));
        const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(tuple_obj.ob_base.ob_size);
        std.debug.assert(idx < size);
        tuple_obj.ob_item[idx] = item;
        // Note: Caller transfers ownership, no incref needed
    }

    pub fn getItem(obj: *PyObject, idx: usize) PythonError!*PyObject {
        std.debug.assert(runtime.PyTuple_Check(obj));
        const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(tuple_obj.ob_base.ob_size);
        if (idx >= size) {
            return PythonError.IndexError;
        }
        const item = tuple_obj.ob_item[idx];
        incref(item);
        return item;
    }

    pub fn len(obj: *PyObject) usize {
        std.debug.assert(runtime.PyTuple_Check(obj));
        const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
        return @intCast(tuple_obj.ob_base.ob_size);
    }

    pub fn len_method(obj: *PyObject) i64 {
        std.debug.assert(runtime.PyTuple_Check(obj));
        const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
        return tuple_obj.ob_base.ob_size;
    }

    pub fn contains(obj: *PyObject, value: *PyObject) bool {
        std.debug.assert(runtime.PyTuple_Check(obj));
        const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(tuple_obj.ob_base.ob_size);

        // Check each item in the tuple
        for (0..size) |i| {
            const item = tuple_obj.ob_item[i];
            if (pyObjectEqual(item, value)) {
                return true;
            }
        }
        return false;
    }

    /// Compare two PyObjects for equality
    fn pyObjectEqual(a: *PyObject, b: *PyObject) bool {
        // Same object - always equal
        if (a == b) return true;

        // Must be same type for equality
        if (a.ob_type != b.ob_type) {
            // Special case: int and bool can compare
            const a_is_numeric = runtime.PyLong_Check(a) or runtime.PyBool_Check(a);
            const b_is_numeric = runtime.PyLong_Check(b) or runtime.PyBool_Check(b);
            if (!(a_is_numeric and b_is_numeric)) return false;
        }

        // Compare by type
        if (runtime.PyLong_Check(a) or runtime.PyBool_Check(a)) {
            const a_obj: *PyLongObject = @ptrCast(@alignCast(a));
            const b_obj: *PyLongObject = @ptrCast(@alignCast(b));
            return a_obj.ob_digit == b_obj.ob_digit;
        }

        if (runtime.PyFloat_Check(a)) {
            const a_obj: *runtime.PyFloatObject = @ptrCast(@alignCast(a));
            const b_obj: *runtime.PyFloatObject = @ptrCast(@alignCast(b));
            return a_obj.ob_fval == b_obj.ob_fval;
        }

        if (runtime.PyUnicode_Check(a)) {
            const a_obj: *PyUnicodeObject = @ptrCast(@alignCast(a));
            const b_obj: *PyUnicodeObject = @ptrCast(@alignCast(b));
            if (a_obj.length != b_obj.length) return false;
            const a_len: usize = @intCast(a_obj.length);
            const b_len: usize = @intCast(b_obj.length);
            return std.mem.eql(u8, a_obj.data[0..a_len], b_obj.data[0..b_len]);
        }

        if (runtime.PyBytes_Check(a)) {
            const a_obj: *runtime.PyBytesObject = @ptrCast(@alignCast(a));
            const b_obj: *runtime.PyBytesObject = @ptrCast(@alignCast(b));
            const a_size: usize = @intCast(a_obj.ob_base.ob_size);
            const b_size: usize = @intCast(b_obj.ob_base.ob_size);
            if (a_size != b_size) return false;
            const a_ptr: [*]const u8 = @ptrCast(&a_obj.ob_sval);
            const b_ptr: [*]const u8 = @ptrCast(&b_obj.ob_sval);
            return std.mem.eql(u8, a_ptr[0..a_size], b_ptr[0..b_size]);
        }

        if (runtime.Py_IS_TYPE(a, &runtime.cpython.PyNone_Type)) {
            return runtime.Py_IS_TYPE(b, &runtime.cpython.PyNone_Type);
        }

        // For other types, use identity comparison
        return false;
    }

    /// Print tuple in Python format: (1, 2, 3)
    pub fn print(obj: *PyObject) void {
        std.debug.assert(runtime.PyTuple_Check(obj));
        const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(tuple_obj.ob_base.ob_size);

        std.debug.print("(", .{});
        for (0..size) |i| {
            const item = tuple_obj.ob_item[i];
            if (runtime.PyLong_Check(item)) {
                const long_obj: *PyLongObject = @ptrCast(@alignCast(item));
                std.debug.print("{d}", .{long_obj.ob_digit});
            } else if (runtime.PyUnicode_Check(item)) {
                const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(item));
                const str_len: usize = @intCast(str_obj.length);
                std.debug.print("'{s}'", .{str_obj.data[0..str_len]});
            } else {
                std.debug.print("{any}", .{item});
            }
            if (i < size - 1) {
                std.debug.print(", ", .{});
            }
        }
        std.debug.print(")", .{});
    }
};

// CPython-compatible C API functions
pub fn PyTuple_New(size: runtime.Py_ssize_t) callconv(.C) *PyObject {
    const allocator = allocator_helper.fast_allocator;
    return PyTuple.create(allocator, @intCast(size)) catch @panic("PyTuple_New allocation failed");
}

pub fn PyTuple_Size(obj: *PyObject) callconv(.C) runtime.Py_ssize_t {
    const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
    return tuple_obj.ob_base.ob_size;
}

pub fn PyTuple_GetItem(obj: *PyObject, idx: runtime.Py_ssize_t) callconv(.C) *PyObject {
    const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
    return tuple_obj.ob_item[@intCast(idx)];
}

pub fn PyTuple_SetItem(obj: *PyObject, idx: runtime.Py_ssize_t, item: *PyObject) callconv(.C) c_int {
    const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
    tuple_obj.ob_item[@intCast(idx)] = item;
    return 0;
}
