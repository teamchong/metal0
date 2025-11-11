/// PyList implementation - Python list type
const std = @import("std");
const runtime = @import("runtime.zig");

const PyObject = runtime.PyObject;
const PyInt = runtime.PyInt;
const incref = runtime.incref;
const decref = runtime.decref;
const PythonError = runtime.PythonError;

/// Python list type
pub const PyList = struct {
    items: std.ArrayList(*PyObject),
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator) !*PyObject {
        const obj = try allocator.create(PyObject);
        const list_data = try allocator.create(PyList);

        // Initialize ArrayList using 0.15.x unmanaged pattern
        list_data.* = PyList{
            .items = .{}, // Empty unmanaged ArrayList
            .allocator = allocator,
        };

        obj.* = PyObject{
            .ref_count = 1,
            .type_id = .list,
            .data = list_data,
        };
        return obj;
    }

    pub fn append(obj: *PyObject, item: *PyObject) !void {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        try data.items.append(data.allocator, item);
        incref(item);
    }

    pub fn pop(allocator: std.mem.Allocator, obj: *PyObject) PythonError!*PyObject {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        if (data.items.items.len == 0) {
            return PythonError.IndexError;
        }
        // pop() returns the last element and removes it
        const item = data.items.items[data.items.items.len - 1];
        _ = data.items.pop(); // Remove it from the list
        // Don't decref - we're transferring ownership to caller
        _ = allocator; // Unused but kept for consistency
        return item;
    }

    pub fn getItem(obj: *PyObject, idx: usize) PythonError!*PyObject {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        if (idx >= data.items.items.len) {
            return PythonError.IndexError;
        }
        return data.items.items[idx];
    }

    pub fn len(obj: *PyObject) usize {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        return data.items.items.len;
    }

    pub fn contains(obj: *PyObject, value: *PyObject) bool {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        // Check each item in the list
        for (data.items.items) |item| {
            // For now, only support comparing integers
            if (item.type_id == .int and value.type_id == .int) {
                const item_data: *PyInt = @ptrCast(@alignCast(item.data));
                const value_data: *PyInt = @ptrCast(@alignCast(value.data));
                if (item_data.value == value_data.value) {
                    return true;
                }
            }
            // Could add string comparison here later
        }
        return false;
    }

    pub fn slice(allocator: std.mem.Allocator, obj: *PyObject, start_opt: ?i64, end_opt: ?i64, step_opt: ?i64) !*PyObject {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        const list_len: i64 = @intCast(data.items.items.len);
        const step: i64 = step_opt orelse 1;

        if (step == 0) {
            return PythonError.ValueError; // Step cannot be zero
        }

        // Handle defaults and bounds
        var start: i64 = start_opt orelse (if (step > 0) 0 else list_len - 1);
        var end: i64 = end_opt orelse (if (step > 0) list_len else -list_len - 1);

        // Handle negative indices
        if (start < 0) start = @max(0, list_len + start);
        if (end < 0) end = @max(0, list_len + end);

        // Clamp to valid range
        start = @max(0, @min(start, list_len));
        end = @max(0, @min(end, list_len));

        // Create new list
        const new_list = try create(allocator);
        const new_data: *PyList = @ptrCast(@alignCast(new_list.data));

        // Copy elements with step
        if (step > 0) {
            const start_idx: usize = @intCast(start);
            const end_idx: usize = @intCast(end);
            const step_usize: usize = @intCast(step);
            var i: usize = start_idx;
            while (i < end_idx) : (i += step_usize) {
                const item = data.items.items[i];
                try new_data.items.append(allocator, item);
                incref(item);
            }
        } else {
            // Negative step - iterate backwards
            const start_idx: usize = @intCast(start);
            const end_idx: usize = @intCast(end);
            const step_neg: usize = @intCast(-step);
            var i: usize = start_idx;
            while (i > end_idx) {
                const item = data.items.items[i];
                try new_data.items.append(allocator, item);
                incref(item);
                if (i < step_neg) break;
                i -= step_neg;
            }
        }

        return new_list;
    }

    pub fn extend(obj: *PyObject, other: *PyObject) !void {
        std.debug.assert(obj.type_id == .list);
        std.debug.assert(other.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        const other_data: *PyList = @ptrCast(@alignCast(other.data));

        // Append all items from other list
        for (other_data.items.items) |item| {
            try data.items.append(data.allocator, item);
            incref(item);
        }
    }

    pub fn remove(allocator: std.mem.Allocator, obj: *PyObject, value: *PyObject) !void {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        const alloc = allocator; // Use passed allocator for consistency
        _ = alloc;

        // Find and remove first occurrence
        for (data.items.items, 0..) |item, i| {
            if (item.type_id == .int and value.type_id == .int) {
                const item_data: *PyInt = @ptrCast(@alignCast(item.data));
                const value_data: *PyInt = @ptrCast(@alignCast(value.data));
                if (item_data.value == value_data.value) {
                    // Found it - remove and decref
                    const removed = data.items.orderedRemove(i);
                    decref(removed, data.allocator);
                    return;
                }
            }
        }
        // If not found, Python raises ValueError, but we'll silently ignore for now
    }

    pub fn reverse(obj: *PyObject) void {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        std.mem.reverse(*PyObject, data.items.items);
    }

    pub fn count(obj: *PyObject, value: *PyObject) i64 {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        var count_val: i64 = 0;
        for (data.items.items) |item| {
            if (item.type_id == .int and value.type_id == .int) {
                const item_data: *PyInt = @ptrCast(@alignCast(item.data));
                const value_data: *PyInt = @ptrCast(@alignCast(value.data));
                if (item_data.value == value_data.value) {
                    count_val += 1;
                }
            }
        }
        return count_val;
    }

    pub fn index(obj: *PyObject, value: *PyObject) i64 {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        // Find first occurrence
        for (data.items.items, 0..) |item, i| {
            if (item.type_id == .int and value.type_id == .int) {
                const item_data: *PyInt = @ptrCast(@alignCast(item.data));
                const value_data: *PyInt = @ptrCast(@alignCast(value.data));
                if (item_data.value == value_data.value) {
                    return @intCast(i);
                }
            }
        }
        // If not found, Python raises ValueError, but we'll return -1 for now
        return -1;
    }

    pub fn insert(allocator: std.mem.Allocator, obj: *PyObject, idx: i64, value: *PyObject) !void {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        const alloc = allocator; // Use passed allocator for consistency
        _ = alloc;

        const list_len: i64 = @intCast(data.items.items.len);
        var index_pos: i64 = idx;

        // Handle negative indices
        if (index_pos < 0) index_pos = @max(0, list_len + index_pos);

        // Clamp to valid range
        index_pos = @max(0, @min(index_pos, list_len));

        const insert_idx: usize = @intCast(index_pos);
        try data.items.insert(data.allocator, insert_idx, value);
        incref(value);
    }

    pub fn clear(allocator: std.mem.Allocator, obj: *PyObject) void {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        _ = allocator;

        // Decref all items
        for (data.items.items) |item| {
            decref(item, data.allocator);
        }

        data.items.clearAndFree(data.allocator);
    }

    pub fn sort(obj: *PyObject) void {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        // Simple bubble sort for integer lists
        const items = data.items.items;
        if (items.len <= 1) return;

        var i: usize = 0;
        while (i < items.len) : (i += 1) {
            var j: usize = 0;
            while (j < items.len - i - 1) : (j += 1) {
                if (items[j].type_id == .int and items[j + 1].type_id == .int) {
                    const val_j = PyInt.getValue(items[j]);
                    const val_j1 = PyInt.getValue(items[j + 1]);
                    if (val_j > val_j1) {
                        // Swap
                        const temp = items[j];
                        items[j] = items[j + 1];
                        items[j + 1] = temp;
                    }
                }
            }
        }
    }

    pub fn copy(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        const new_list = try create(allocator);
        const new_data: *PyList = @ptrCast(@alignCast(new_list.data));

        // Copy all items and incref
        for (data.items.items) |item| {
            try new_data.items.append(allocator, item);
            incref(item);
        }

        return new_list;
    }

    pub fn len_method(obj: *PyObject) i64 {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));
        return @intCast(data.items.items.len);
    }

    pub fn min(obj: *PyObject) i64 {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        if (data.items.items.len == 0) return 0;

        var min_val: i64 = std.math.maxInt(i64);
        for (data.items.items) |item| {
            if (item.type_id == .int) {
                const val = PyInt.getValue(item);
                if (val < min_val) {
                    min_val = val;
                }
            }
        }

        return min_val;
    }

    pub fn max(obj: *PyObject) i64 {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        if (data.items.items.len == 0) return 0;

        var max_val: i64 = std.math.minInt(i64);
        for (data.items.items) |item| {
            if (item.type_id == .int) {
                const val = PyInt.getValue(item);
                if (val > max_val) {
                    max_val = val;
                }
            }
        }

        return max_val;
    }

    pub fn sum(obj: *PyObject) i64 {
        std.debug.assert(obj.type_id == .list);
        const data: *PyList = @ptrCast(@alignCast(obj.data));

        var total: i64 = 0;
        for (data.items.items) |item| {
            if (item.type_id == .int) {
                total += PyInt.getValue(item);
            }
        }

        return total;
    }
};
