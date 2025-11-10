/// Zyth Runtime Library
/// Core runtime support for compiled Python code
const std = @import("std");
const pyint = @import("pyint.zig");
const pylist = @import("pylist.zig");
const pystring = @import("pystring.zig");
const pytuple = @import("pytuple.zig");

/// Python exception types mapped to Zig errors
pub const PythonError = error{
    ZeroDivisionError,
    IndexError,
    ValueError,
    TypeError,
    KeyError,
};

/// Python object representation
pub const PyObject = struct {
    ref_count: usize,
    type_id: TypeId,
    data: *anyopaque,

    pub const TypeId = enum {
        int,
        float,
        bool,
        string,
        list,
        tuple,
        dict,
        none,
    };
};

/// Reference counting
pub fn incref(obj: *PyObject) void {
    obj.ref_count += 1;
}

pub fn decref(obj: *PyObject, allocator: std.mem.Allocator) void {
    obj.ref_count -= 1;
    if (obj.ref_count == 0) {
        // Free internal data based on type
        switch (obj.type_id) {
            .int => {
                const data: *PyInt = @ptrCast(@alignCast(obj.data));
                allocator.destroy(data);
            },
            .list => {
                const data: *PyList = @ptrCast(@alignCast(obj.data));
                // Decref all items
                for (data.items.items) |item| {
                    decref(item, allocator);
                }
                data.items.deinit(data.allocator);
                allocator.destroy(data);
            },
            .tuple => {
                const data: *PyTuple = @ptrCast(@alignCast(obj.data));
                // Decref all items
                for (data.items) |item| {
                    decref(item, allocator);
                }
                allocator.free(data.items);
                allocator.destroy(data);
            },
            .string => {
                const data: *PyString = @ptrCast(@alignCast(obj.data));
                allocator.free(data.data);
                allocator.destroy(data);
            },
            .dict => {
                const data: *PyDict = @ptrCast(@alignCast(obj.data));
                // Decref all values
                var it = data.map.valueIterator();
                while (it.next()) |value| {
                    decref(value.*, allocator);
                }
                data.map.deinit();
                allocator.destroy(data);
            },
            else => {},
        }
        allocator.destroy(obj);
    }
}

/// Helper function to print PyObject based on runtime type
pub fn printPyObject(obj: *PyObject) void {
    switch (obj.type_id) {
        .int => {
            const data: *PyInt = @ptrCast(@alignCast(obj.data));
            std.debug.print("{}", .{data.value});
        },
        .string => {
            const data: *PyString = @ptrCast(@alignCast(obj.data));
            std.debug.print("{s}", .{data.data});
        },
        else => {
            // For other types, print the pointer (fallback)
            std.debug.print("{*}", .{obj});
        },
    }
}

/// Helper function to print a list in Python format: [elem1, elem2, elem3]
pub fn printList(obj: *PyObject) void {
    std.debug.assert(obj.type_id == .list);
    const data: *PyList = @ptrCast(@alignCast(obj.data));

    std.debug.print("[", .{});
    for (data.items.items, 0..) |item, i| {
        if (i > 0) {
            std.debug.print(", ", .{});
        }
        // Print each element based on its type
        switch (item.type_id) {
            .int => {
                const int_data: *PyInt = @ptrCast(@alignCast(item.data));
                std.debug.print("{}", .{int_data.value});
            },
            .string => {
                const str_data: *PyString = @ptrCast(@alignCast(item.data));
                std.debug.print("'{s}'", .{str_data.data});
            },
            else => {
                std.debug.print("{*}", .{item});
            },
        }
    }
    std.debug.print("]", .{});
}

/// Python integer type - re-exported from pyint.zig
pub const PyInt = pyint.PyInt;

/// Helper functions for operations that can raise exceptions

/// Integer division with zero check
pub fn divideInt(a: i64, b: i64) PythonError!i64 {
    if (b == 0) {
        return PythonError.ZeroDivisionError;
    }
    return @divTrunc(a, b);
}

/// Modulo with zero check
pub fn moduloInt(a: i64, b: i64) PythonError!i64 {
    if (b == 0) {
        return PythonError.ZeroDivisionError;
    }
    return @mod(a, b);
}

/// Python list type - re-exported from pylist.zig
pub const PyList = pylist.PyList;

/// Python tuple type - re-exported from pytuple.zig
pub const PyTuple = pytuple.PyTuple;

/// Python string type - re-exported from pystring.zig
pub const PyString = pystring.PyString;


// Import PyDict from separate file
const dict_module = @import("dict.zig");
pub const PyDict = dict_module.PyDict;


// Tests
test "PyInt creation and retrieval" {
    const allocator = std.testing.allocator;
    const obj = try PyInt.create(allocator, 42);
    defer decref(obj, allocator);

    try std.testing.expectEqual(@as(i64, 42), PyInt.getValue(obj));
    try std.testing.expectEqual(@as(usize, 1), obj.ref_count);
}

test "PyList append and retrieval" {
    const allocator = std.testing.allocator;
    const list = try PyList.create(allocator);
    defer decref(list, allocator);

    const item1 = try PyInt.create(allocator, 10);
    const item2 = try PyInt.create(allocator, 20);

    try PyList.append(list, item1);
    try PyList.append(list, item2);

    // Transfer ownership to list (decref our references)
    decref(item1, allocator);
    decref(item2, allocator);

    try std.testing.expectEqual(@as(usize, 2), PyList.len(list));
    try std.testing.expectEqual(@as(i64, 10), PyInt.getValue(try PyList.getItem(list, 0)));
    try std.testing.expectEqual(@as(i64, 20), PyInt.getValue(try PyList.getItem(list, 1)));
}

test "PyString creation" {
    const allocator = std.testing.allocator;
    const obj = try PyString.create(allocator, "hello");
    defer decref(obj, allocator);

    const value = PyString.getValue(obj);
    try std.testing.expectEqualStrings("hello", value);
}

test "PyDict set and get" {
    const allocator = std.testing.allocator;
    const dict = try PyDict.create(allocator);
    defer decref(dict, allocator);

    const value = try PyInt.create(allocator, 100);
    try PyDict.set(dict, "key", value);

    // Transfer ownership to dict
    decref(value, allocator);

    const retrieved = PyDict.get(dict, "key");
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(@as(i64, 100), PyInt.getValue(retrieved.?));
}

test "reference counting" {
    const allocator = std.testing.allocator;
    const obj = try PyInt.create(allocator, 42);

    try std.testing.expectEqual(@as(usize, 1), obj.ref_count);

    incref(obj);
    try std.testing.expectEqual(@as(usize, 2), obj.ref_count);

    decref(obj, allocator);
    try std.testing.expectEqual(@as(usize, 1), obj.ref_count);

    decref(obj, allocator);
    // Object should be destroyed here
}
