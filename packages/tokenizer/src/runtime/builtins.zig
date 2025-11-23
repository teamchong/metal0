/// Built-in Python functions implemented in Zig
const std = @import("std");
const runtime_core = @import("../runtime.zig");
const pyint = @import("../pyint.zig");
const pylist = @import("../pylist.zig");
const pystring = @import("../pystring.zig");
const pytuple = @import("../pytuple.zig");
const dict_module = @import("../dict.zig");

const PyObject = runtime_core.PyObject;
const PythonError = runtime_core.PythonError;
const PyInt = pyint.PyInt;
const PyList = pylist.PyList;
const PyString = pystring.PyString;
const PyTuple = pytuple.PyTuple;
const PyDict = dict_module.PyDict;
const incref = runtime_core.incref;
const decref = runtime_core.decref;

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

/// Absolute value of a number
pub fn abs(value: i64) i64 {
    if (value < 0) {
        return -value;
    }
    return value;
}

/// Minimum value from a list
pub fn minList(iterable: *PyObject) i64 {
    std.debug.assert(iterable.type_id == .list);
    const list: *PyList = @ptrCast(@alignCast(iterable.data));
    std.debug.assert(list.items.items.len > 0);

    var min_val: i64 = std.math.maxInt(i64);
    for (list.items.items) |item| {
        if (item.type_id == .int) {
            const int_obj: *PyInt = @ptrCast(@alignCast(item.data));
            if (int_obj.value < min_val) {
                min_val = int_obj.value;
            }
        }
    }
    return min_val;
}

/// Minimum value from varargs
pub fn minVarArgs(values: []const i64) i64 {
    std.debug.assert(values.len > 0);
    var min_val = values[0];
    for (values[1..]) |value| {
        if (value < min_val) {
            min_val = value;
        }
    }
    return min_val;
}

/// Maximum value from a list
pub fn maxList(iterable: *PyObject) i64 {
    std.debug.assert(iterable.type_id == .list);
    const list: *PyList = @ptrCast(@alignCast(iterable.data));
    std.debug.assert(list.items.items.len > 0);

    var max_val: i64 = std.math.minInt(i64);
    for (list.items.items) |item| {
        if (item.type_id == .int) {
            const int_obj: *PyInt = @ptrCast(@alignCast(item.data));
            if (int_obj.value > max_val) {
                max_val = int_obj.value;
            }
        }
    }
    return max_val;
}

/// Maximum value from varargs
pub fn maxVarArgs(values: []const i64) i64 {
    std.debug.assert(values.len > 0);
    var max_val = values[0];
    for (values[1..]) |value| {
        if (value > max_val) {
            max_val = value;
        }
    }
    return max_val;
}

/// Sum of all numeric values in a list
pub fn sum(iterable: *PyObject) i64 {
    std.debug.assert(iterable.type_id == .list);
    const list: *PyList = @ptrCast(@alignCast(iterable.data));

    var total: i64 = 0;
    for (list.items.items) |item| {
        if (item.type_id == .int) {
            const int_obj: *PyInt = @ptrCast(@alignCast(item.data));
            total += int_obj.value;
        }
    }
    return total;
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
