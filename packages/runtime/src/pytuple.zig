/// PyTuple implementation - Python tuple type (CPython ABI compatible)
const std = @import("std");
const runtime = @import("runtime.zig");

const PyObject = runtime.PyObject;
const PyTupleObject = runtime.PyTupleObject;
const PyTuple_Type = &runtime.PyTuple_Type;
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
            // For now, only support comparing integers
            if (runtime.PyLong_Check(item) and runtime.PyLong_Check(value)) {
                const item_obj: *PyLongObject = @ptrCast(@alignCast(item));
                const value_obj: *PyLongObject = @ptrCast(@alignCast(value));
                if (item_obj.ob_digit == value_obj.ob_digit) {
                    return true;
                }
            }
        }
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
    const allocator = std.heap.page_allocator;
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
