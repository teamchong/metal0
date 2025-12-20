/// Aggregate builtins (all, any, sum, min, max, sorted, reversed, filter)
const std = @import("std");
const runtime_core = @import("../../runtime.zig");
const cpython = @import("../../cpython.zig");
const pyint = @import("../../Objects/intobject.zig");
const pylist = @import("../../Objects/listobject.zig");
const pystring = @import("../../Objects/unicodeobject.zig");
const dict_module = @import("../../Objects/dictobject.zig");

const PyObject = runtime_core.PyObject;

/// Check if a type is a PyObject by looking for CPython struct fields
fn isPyObjectType(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .pointer or info.pointer.size != .one) return false;
    const ChildT = info.pointer.child;
    const child_info = @typeInfo(ChildT);
    return child_info == .@"struct" and
        @hasField(ChildT, "ob_refcnt") and
        @hasField(ChildT, "ob_type");
}
const PyInt = pyint.PyInt;
const PyList = pylist.PyList;
const PyString = pystring.PyString;
const PyDict = dict_module.PyDict;
const incref = runtime_core.incref;

/// Check if all elements in iterable are truthy
pub fn all(iterable: *PyObject) bool {
    std.debug.assert(iterable.type_id == .list);
    const src_list: *PyList = @ptrCast(@alignCast(iterable.data));

    for (src_list.items.items) |item| {
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
    }
    return true;
}

/// Check if any element in iterable is truthy
pub fn any(iterable: *PyObject) bool {
    std.debug.assert(iterable.type_id == .list);
    const src_list: *PyList = @ptrCast(@alignCast(iterable.data));

    for (src_list.items.items) |item| {
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
    }
    return false;
}

/// Absolute value of a number
pub fn abs(value: i64) i64 {
    if (value < 0) return -value;
    return value;
}

/// Minimum value from a list
pub fn minList(iterable: *PyObject) i64 {
    std.debug.assert(iterable.type_id == .list);
    const src_list: *PyList = @ptrCast(@alignCast(iterable.data));

    var min_val: i64 = std.math.maxInt(i64);
    for (src_list.items.items) |item| {
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
    const src_list: *PyList = @ptrCast(@alignCast(iterable.data));

    var max_val: i64 = std.math.minInt(i64);
    for (src_list.items.items) |item| {
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

/// Minimum value from any iterable (generic)
pub fn minIterable(iterable: anytype) i64 {
    const T = @TypeOf(iterable);
    if (comptime isPyObjectType(T)) {
        return minList(iterable);
    } else if (comptime std.meta.hasFn(T, "__getitem__")) {
        var min_val: i64 = std.math.maxInt(i64);
        var i: i64 = 0;
        while (true) {
            const item = iterable.__getitem__(i) catch break;
            if (item < min_val) {
                min_val = item;
            }
            i += 1;
        }
        return min_val;
    } else if (@typeInfo(T) == .pointer and @typeInfo(std.meta.Child(T)) == .@"struct") {
        if (@hasField(std.meta.Child(T), "items")) {
            var min_val: i64 = std.math.maxInt(i64);
            for (iterable.items) |item| {
                if (item < min_val) {
                    min_val = item;
                }
            }
            return min_val;
        }
    }
    const PyValue = @import("../../Objects/object.zig").PyValue;
    const IterType = @TypeOf(iterable);
    const ElemType = std.meta.Elem(IterType);

    // Handle PyValue slices
    if (ElemType == PyValue) {
        var min_val: ?PyValue = null;
        for (iterable) |item| {
            if (min_val) |mv| {
                if (item.lt(mv)) {
                    min_val = item;
                }
            } else {
                min_val = item;
            }
        }
        if (min_val) |mv| {
            return mv.toInt() orelse 0;
        }
        return std.math.maxInt(i64);
    }

    var min_val: i64 = std.math.maxInt(i64);
    for (iterable) |item| {
        if (item < min_val) {
            min_val = item;
        }
    }
    return min_val;
}

/// Maximum value from any iterable (generic)
pub fn maxIterable(iterable: anytype) i64 {
    const T = @TypeOf(iterable);
    if (comptime isPyObjectType(T)) {
        return maxList(iterable);
    } else if (comptime std.meta.hasFn(T, "__getitem__")) {
        var max_val: i64 = std.math.minInt(i64);
        var i: i64 = 0;
        while (true) {
            const item = iterable.__getitem__(i) catch break;
            if (item > max_val) {
                max_val = item;
            }
            i += 1;
        }
        return max_val;
    } else if (@typeInfo(T) == .pointer and @typeInfo(std.meta.Child(T)) == .@"struct") {
        if (@hasField(std.meta.Child(T), "items")) {
            var max_val: i64 = std.math.minInt(i64);
            for (iterable.items) |item| {
                if (item > max_val) {
                    max_val = item;
                }
            }
            return max_val;
        }
    }
    const rt = @import("../../runtime.zig");
    const PyValue = @import("../../Objects/object.zig").PyValue;
    const slice = rt.iterSlice(iterable);
    const SliceType = @TypeOf(slice);
    const ElemType = std.meta.Elem(SliceType);

    // Handle PyValue slices
    if (ElemType == PyValue) {
        var max_val: ?PyValue = null;
        for (slice) |item| {
            if (max_val) |mv| {
                if (item.gt(mv)) {
                    max_val = item;
                }
            } else {
                max_val = item;
            }
        }
        if (max_val) |mv| {
            return mv.toInt() orelse 0;
        }
        return std.math.minInt(i64);
    }

    var max_val: i64 = std.math.minInt(i64);
    for (slice) |item| {
        if (item > max_val) {
            max_val = item;
        }
    }
    return max_val;
}

/// Sum of all numeric values in a list
pub fn sum(iterable: *PyObject) i64 {
    std.debug.assert(iterable.type_id == .list);
    const src_list: *PyList = @ptrCast(@alignCast(iterable.data));

    var total: i64 = 0;
    for (src_list.items.items) |item| {
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

    const result = try PyList.create(allocator);

    for (source_list.items.items) |item| {
        incref(item);
        try PyList.append(result, item);
    }

    PyList.sort(result);

    return result;
}

/// Return a new reversed list from an iterable
pub fn reversed(iterable: *PyObject, allocator: std.mem.Allocator) !*PyObject {
    std.debug.assert(iterable.type_id == .list);
    const source_list: *PyList = @ptrCast(@alignCast(iterable.data));

    const result = try PyList.create(allocator);

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
