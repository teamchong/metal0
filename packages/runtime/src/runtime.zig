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

    /// Value type for initializing lists/tuples from literals
    pub const Value = struct {
        int: i64,
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

/// Convert primitive i64 to PyString
pub fn intToString(allocator: std.mem.Allocator, value: i64) !*PyObject {
    const str = try std.fmt.allocPrint(allocator, "{}", .{value});
    return try PyString.create(allocator, str);
}

/// Create a list of integers from start to stop with step
pub fn range(allocator: std.mem.Allocator, start: i64, stop: i64, step: i64) !*PyObject {
    if (step == 0) {
        return PythonError.ValueError;
    }

    const list = try PyList.create(allocator);

    if (step > 0) {
        var i = start;
        while (i < stop) : (i += step) {
            const item = try PyInt.create(allocator, i);
            try PyList.append(list, item);
            decref(item, allocator); // List takes ownership
        }
    } else if (step < 0) {
        var i = start;
        while (i > stop) : (i += step) {
            const item = try PyInt.create(allocator, i);
            try PyList.append(list, item);
            decref(item, allocator); // List takes ownership
        }
    }

    return list;
}

/// Create a list of (index, item) tuples from an iterable
pub fn enumerate(allocator: std.mem.Allocator, iterable: *PyObject, start: i64) !*PyObject {
    std.debug.assert(iterable.type_id == .list);
    const source_list: *PyList = @ptrCast(@alignCast(iterable.data));

    const result = try PyList.create(allocator);

    var index = start;
    for (source_list.items.items) |item| {
        // Create tuple (index, item)
        const tuple = try PyTuple.create(allocator, 2);
        const idx_obj = try PyInt.create(allocator, index);

        PyTuple.setItem(tuple, 0, idx_obj);
        decref(idx_obj, allocator); // Tuple takes ownership

        incref(item); // Tuple needs ownership
        PyTuple.setItem(tuple, 1, item);

        try PyList.append(result, tuple);
        decref(tuple, allocator); // List takes ownership

        index += 1;
    }

    return result;
}

/// Zip two lists into a list of tuples
pub fn zip2(allocator: std.mem.Allocator, iter1: *PyObject, iter2: *PyObject) !*PyObject {
    std.debug.assert(iter1.type_id == .list);
    std.debug.assert(iter2.type_id == .list);

    const list1: *PyList = @ptrCast(@alignCast(iter1.data));
    const list2: *PyList = @ptrCast(@alignCast(iter2.data));

    const result = try PyList.create(allocator);
    const min_len = @min(list1.items.items.len, list2.items.items.len);

    var i: usize = 0;
    while (i < min_len) : (i += 1) {
        const tuple = try PyTuple.create(allocator, 2);

        incref(list1.items.items[i]);
        PyTuple.setItem(tuple, 0, list1.items.items[i]);

        incref(list2.items.items[i]);
        PyTuple.setItem(tuple, 1, list2.items.items[i]);

        try PyList.append(result, tuple);
        decref(tuple, allocator); // List takes ownership
    }

    return result;
}

/// Zip three lists into a list of tuples
pub fn zip3(allocator: std.mem.Allocator, iter1: *PyObject, iter2: *PyObject, iter3: *PyObject) !*PyObject {
    std.debug.assert(iter1.type_id == .list);
    std.debug.assert(iter2.type_id == .list);
    std.debug.assert(iter3.type_id == .list);

    const list1: *PyList = @ptrCast(@alignCast(iter1.data));
    const list2: *PyList = @ptrCast(@alignCast(iter2.data));
    const list3: *PyList = @ptrCast(@alignCast(iter3.data));

    const result = try PyList.create(allocator);
    const min_len = @min(@min(list1.items.items.len, list2.items.items.len), list3.items.items.len);

    var i: usize = 0;
    while (i < min_len) : (i += 1) {
        const tuple = try PyTuple.create(allocator, 3);

        incref(list1.items.items[i]);
        PyTuple.setItem(tuple, 0, list1.items.items[i]);

        incref(list2.items.items[i]);
        PyTuple.setItem(tuple, 1, list2.items.items[i]);

        incref(list3.items.items[i]);
        PyTuple.setItem(tuple, 2, list3.items.items[i]);

        try PyList.append(result, tuple);
        decref(tuple, allocator); // List takes ownership
    }

    return result;
}

/// Check if all elements in iterable are truthy
pub fn all(iterable: *PyObject) bool {
    std.debug.assert(iterable.type_id == .list);
    const list: *PyList = @ptrCast(@alignCast(iterable.data));

    for (list.items.items) |item| {
        // Check if item is truthy
        if (item.type_id == .int) {
            const int_obj: *PyInt = @ptrCast(@alignCast(item.data));
            if (int_obj.value == 0) return false;
        } else if (item.type_id == .string) {
            const str_obj: *PyString = @ptrCast(@alignCast(item.data));
            if (str_obj.data.len == 0) return false;
        } else if (item.type_id == .list) {
            const list_obj: *PyList = @ptrCast(@alignCast(item.data));
            if (list_obj.items.items.len == 0) return false;
        } else if (item.type_id == .dict) {
            if (PyDict.len(item) == 0) return false;
        }
        // For other types, assume truthy
    }
    return true;
}

/// Check if any element in iterable is truthy
pub fn any(iterable: *PyObject) bool {
    std.debug.assert(iterable.type_id == .list);
    const list: *PyList = @ptrCast(@alignCast(iterable.data));

    for (list.items.items) |item| {
        // Check if item is truthy
        if (item.type_id == .int) {
            const int_obj: *PyInt = @ptrCast(@alignCast(item.data));
            if (int_obj.value != 0) return true;
        } else if (item.type_id == .string) {
            const str_obj: *PyString = @ptrCast(@alignCast(item.data));
            if (str_obj.data.len > 0) return true;
        } else if (item.type_id == .list) {
            const list_obj: *PyList = @ptrCast(@alignCast(item.data));
            if (list_obj.items.items.len > 0) return true;
        } else if (item.type_id == .dict) {
            if (PyDict.len(item) > 0) return true;
        }
        // For other types, assume truthy
    }
    return false;
}

/// Return a new sorted list from an iterable
pub fn sorted(iterable: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    std.debug.assert(iterable.type_id == .list);
    const source_list: *PyList = @ptrCast(@alignCast(iterable.data));

    // Create new list
    const result = try PyList.create(allocator);

    // Copy all items
    for (source_list.items.items) |item| {
        incref(item);
        try PyList.append(result, item);
    }

    // Sort in place using PyList.sort
    PyList.sort(result);

    return result;
}

/// Return a new reversed list from an iterable
pub fn reversed(iterable: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    std.debug.assert(iterable.type_id == .list);
    const source_list: *PyList = @ptrCast(@alignCast(iterable.data));

    const result = try PyList.create(allocator);

    // Append items in reverse order
    var i: usize = source_list.items.items.len;
    while (i > 0) {
        i -= 1;
        incref(source_list.items.items[i]);
        try PyList.append(result, source_list.items.items[i]);
    }

    return result;
}

/// Filter out falsy values from an iterable
pub fn filterTruthy(iterable: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    std.debug.assert(iterable.type_id == .list);
    const source_list: *PyList = @ptrCast(@alignCast(iterable.data));

    const result = try PyList.create(allocator);

    for (source_list.items.items) |item| {
        var is_truthy = true;

        // Check if item is truthy
        if (item.type_id == .int) {
            const int_obj: *PyInt = @ptrCast(@alignCast(item.data));
            is_truthy = int_obj.value != 0;
        } else if (item.type_id == .string) {
            const str_obj: *PyString = @ptrCast(@alignCast(item.data));
            is_truthy = str_obj.data.len > 0;
        } else if (item.type_id == .list) {
            const list_obj: *PyList = @ptrCast(@alignCast(item.data));
            is_truthy = list_obj.items.items.len > 0;
        } else if (item.type_id == .dict) {
            is_truthy = PyDict.len(item) > 0;
        }

        if (is_truthy) {
            incref(item);
            try PyList.append(result, item);
        }
    }

    return result;
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
