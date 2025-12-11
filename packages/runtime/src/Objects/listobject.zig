/// PyList implementation - Python list type (CPython ABI compatible)
const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const runtime = @import("../runtime.zig");

// Re-export CPython-compatible types
pub const PyObject = runtime.PyObject;
pub const PyListObject = runtime.PyListObject;
pub const PyList_Type = &runtime.cpython.PyList_Type;
const PyLongObject = runtime.PyLongObject;

const incref = runtime.incref;
const decref = runtime.decref;
const PythonError = runtime.PythonError;

/// Python list type - wrapper around CPython-compatible PyListObject
pub const PyList = struct {
    // Legacy fields for backwards compatibility (not used in new layout)
    items: std.ArrayList(*PyObject) = undefined,
    allocator: std.mem.Allocator = undefined,

    /// Create a new empty PyListObject
    pub fn create(allocator: std.mem.Allocator) !*PyObject {
        const list_obj = try allocator.create(PyListObject);

        // Allocate initial item array (start with capacity 4)
        // Use c_allocator for item array - must match append() which uses c_allocator for realloc/free
        const initial_capacity: usize = 4;
        const item_array = try std.heap.c_allocator.alloc(*PyObject, initial_capacity);

        list_obj.* = PyListObject{
            .ob_base = .{
                .ob_base = .{
                    .ob_refcnt = 1,
                    .ob_type = PyList_Type,
                },
                .ob_size = 0, // Empty list
            },
            .ob_item = item_array.ptr,
            .allocated = @intCast(initial_capacity),
        };
        return @ptrCast(list_obj);
    }

    /// Create list from slice of values
    pub fn fromSlice(allocator: std.mem.Allocator, values: []const PyObject.Value) !*PyObject {
        const obj = try create(allocator);

        for (values) |value| {
            const item = try runtime.PyInt.create(allocator, value.int);
            try append(obj, item);
        }

        return obj;
    }

    /// Append item to list
    pub fn append(obj: *PyObject, item: *PyObject) !void {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));

        const size: usize = @intCast(list_obj.ob_base.ob_size);
        const allocated: usize = @intCast(list_obj.allocated);

        // Need to grow?
        if (size >= allocated) {
            const new_capacity = if (allocated == 0) 4 else allocated * 2;
            // Use c_allocator for consistency with rest of runtime
            const allocator = std.heap.c_allocator;
            const new_items = try allocator.alloc(*PyObject, new_capacity);

            // Copy existing items
            if (size > 0) {
                @memcpy(new_items[0..size], list_obj.ob_item[0..size]);
            }

            // Free old array if it exists (also use c_allocator)
            if (allocated > 0) {
                allocator.free(list_obj.ob_item[0..allocated]);
            }

            list_obj.ob_item = new_items.ptr;
            list_obj.allocated = @intCast(new_capacity);
        }

        // Add the item
        list_obj.ob_item[size] = item;
        list_obj.ob_base.ob_size += 1;
        incref(item);
    }

    /// Pop last item from list
    pub fn pop(allocator: std.mem.Allocator, obj: *PyObject) PythonError!*PyObject {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        _ = allocator;

        if (list_obj.ob_base.ob_size == 0) {
            return PythonError.IndexError;
        }

        const size: usize = @intCast(list_obj.ob_base.ob_size);
        const item = list_obj.ob_item[size - 1];
        list_obj.ob_base.ob_size -= 1;

        // Don't decref - transferring ownership to caller
        return item;
    }

    /// Get item at index (no bounds normalization)
    pub fn getItem(obj: *PyObject, idx: usize) PythonError!*PyObject {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(list_obj.ob_base.ob_size);

        if (idx >= size) {
            return PythonError.IndexError;
        }
        return list_obj.ob_item[idx];
    }

    /// Get item at index with negative index support
    pub fn get(obj: *PyObject, index_val: i64) !*PyObject {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        const list_len: i64 = list_obj.ob_base.ob_size;

        // Handle negative indices
        const idx = if (index_val < 0) list_len + index_val else index_val;

        if (idx < 0 or idx >= list_len) {
            return PythonError.IndexError;
        }

        const item = list_obj.ob_item[@intCast(idx)];
        incref(item);
        return item;
    }

    /// Slice list
    pub fn slice(allocator: std.mem.Allocator, obj: *PyObject, start_opt: ?i64, end_opt: ?i64) !*PyObject {
        return sliceWithStep(allocator, obj, start_opt, end_opt, null);
    }

    /// Slice list with step
    pub fn sliceWithStep(allocator: std.mem.Allocator, obj: *PyObject, start_opt: ?i64, end_opt: ?i64, step_opt: ?i64) !*PyObject {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));

        const list_len: i64 = list_obj.ob_base.ob_size;
        const step: i64 = step_opt orelse 1;

        if (step == 0) {
            return PythonError.ValueError;
        }

        // Handle defaults and bounds
        var start: i64 = start_opt orelse (if (step > 0) 0 else list_len - 1);
        var end: i64 = end_opt orelse (if (step > 0) list_len else -list_len - 1);

        // Handle negative indices
        if (start < 0) start = @max(0, list_len + start);
        if (end < 0) {
            const min_end: i64 = if (step < 0) -1 else 0;
            end = @max(min_end, list_len + end);
        }

        // Clamp to valid range
        start = @max(0, @min(start, list_len));
        if (step > 0) {
            end = @max(0, @min(end, list_len));
        } else {
            end = @max(-1, @min(end, list_len));
        }

        // Create new list
        const new_list = try create(allocator);

        // Copy elements with step
        if (step > 0) {
            const start_idx: usize = @intCast(start);
            const end_idx: usize = @intCast(end);
            const step_usize: usize = @intCast(step);
            var i: usize = start_idx;
            while (i < end_idx) : (i += step_usize) {
                const item = list_obj.ob_item[i];
                try append(new_list, item);
            }
        } else {
            const step_neg: i64 = -step;
            var i: i64 = start;
            while (i > end) {
                const idx: usize = @intCast(i);
                const item = list_obj.ob_item[idx];
                try append(new_list, item);
                i -= step_neg;
            }
        }

        return new_list;
    }

    /// Get list length
    pub fn len(obj: *PyObject) usize {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        return @intCast(list_obj.ob_base.ob_size);
    }

    /// Check if list contains value
    pub fn contains(obj: *PyObject, value: *PyObject) bool {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(list_obj.ob_base.ob_size);

        for (0..size) |i| {
            const item = list_obj.ob_item[i];
            // Compare integers
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

    /// Extend list with items from another list
    pub fn extend(obj: *PyObject, other: *PyObject) !void {
        std.debug.assert(runtime.PyList_Check(obj));
        std.debug.assert(runtime.PyList_Check(other));
        const other_obj: *PyListObject = @ptrCast(@alignCast(other));
        const other_size: usize = @intCast(other_obj.ob_base.ob_size);

        for (0..other_size) |i| {
            try append(obj, other_obj.ob_item[i]);
        }
    }

    /// Concatenate two lists into a new list
    pub fn concat(allocator: std.mem.Allocator, obj: *PyObject, other: *PyObject) !*PyObject {
        std.debug.assert(runtime.PyList_Check(obj));
        std.debug.assert(runtime.PyList_Check(other));

        const new_list = try create(allocator);
        try extend(new_list, obj);
        try extend(new_list, other);
        return new_list;
    }

    /// Remove first occurrence of value
    pub fn remove(allocator: std.mem.Allocator, obj: *PyObject, value: *PyObject) !void {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(list_obj.ob_base.ob_size);
        _ = allocator;

        for (0..size) |i| {
            const item = list_obj.ob_item[i];
            if (runtime.PyLong_Check(item) and runtime.PyLong_Check(value)) {
                const item_obj: *PyLongObject = @ptrCast(@alignCast(item));
                const value_obj: *PyLongObject = @ptrCast(@alignCast(value));
                if (item_obj.ob_digit == value_obj.ob_digit) {
                    // Shift remaining items
                    var j: usize = i;
                    while (j < size - 1) : (j += 1) {
                        list_obj.ob_item[j] = list_obj.ob_item[j + 1];
                    }
                    list_obj.ob_base.ob_size -= 1;
                    decref(item, allocator_helper.fast_allocator);
                    return;
                }
            }
        }
    }

    /// Reverse list in place
    pub fn reverse(obj: *PyObject) void {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(list_obj.ob_base.ob_size);

        if (size <= 1) return;

        var i: usize = 0;
        var j: usize = size - 1;
        while (i < j) {
            const temp = list_obj.ob_item[i];
            list_obj.ob_item[i] = list_obj.ob_item[j];
            list_obj.ob_item[j] = temp;
            i += 1;
            j -= 1;
        }
    }

    /// Count occurrences of value
    pub fn count(obj: *PyObject, value: *PyObject) i64 {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(list_obj.ob_base.ob_size);

        var count_val: i64 = 0;
        for (0..size) |i| {
            const item = list_obj.ob_item[i];
            if (runtime.PyLong_Check(item) and runtime.PyLong_Check(value)) {
                const item_obj: *PyLongObject = @ptrCast(@alignCast(item));
                const value_obj: *PyLongObject = @ptrCast(@alignCast(value));
                if (item_obj.ob_digit == value_obj.ob_digit) {
                    count_val += 1;
                }
            }
        }
        return count_val;
    }

    /// Find index of first occurrence of value
    pub fn index(obj: *PyObject, value: *PyObject) i64 {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(list_obj.ob_base.ob_size);

        for (0..size) |i| {
            const item = list_obj.ob_item[i];
            if (runtime.PyLong_Check(item) and runtime.PyLong_Check(value)) {
                const item_obj: *PyLongObject = @ptrCast(@alignCast(item));
                const value_obj: *PyLongObject = @ptrCast(@alignCast(value));
                if (item_obj.ob_digit == value_obj.ob_digit) {
                    return @intCast(i);
                }
            }
        }
        return -1;
    }

    /// Insert value at index
    pub fn insert(allocator: std.mem.Allocator, obj: *PyObject, idx: i64, value: *PyObject) !void {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        _ = allocator;

        const list_len: i64 = list_obj.ob_base.ob_size;
        var index_pos: i64 = idx;

        // Handle negative indices
        if (index_pos < 0) index_pos = @max(0, list_len + index_pos);
        index_pos = @max(0, @min(index_pos, list_len));

        const insert_idx: usize = @intCast(index_pos);
        const size: usize = @intCast(list_obj.ob_base.ob_size);
        const allocated: usize = @intCast(list_obj.allocated);

        // Need to grow?
        if (size >= allocated) {
            const new_capacity = if (allocated == 0) 4 else allocated * 2;
            const alloc = allocator_helper.fast_allocator;
            const new_items = try alloc.alloc(*PyObject, new_capacity);

            if (size > 0) {
                @memcpy(new_items[0..size], list_obj.ob_item[0..size]);
            }

            if (allocated > 0) {
                alloc.free(list_obj.ob_item[0..allocated]);
            }

            list_obj.ob_item = new_items.ptr;
            list_obj.allocated = @intCast(new_capacity);
        }

        // Shift items to make room
        var i: usize = size;
        while (i > insert_idx) {
            list_obj.ob_item[i] = list_obj.ob_item[i - 1];
            i -= 1;
        }

        list_obj.ob_item[insert_idx] = value;
        list_obj.ob_base.ob_size += 1;
        incref(value);
    }

    /// Clear all items from list
    pub fn clear(allocator: std.mem.Allocator, obj: *PyObject) void {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(list_obj.ob_base.ob_size);

        for (0..size) |i| {
            decref(list_obj.ob_item[i], allocator);
        }

        list_obj.ob_base.ob_size = 0;
    }

    /// Sort list (simple bubble sort for integers)
    pub fn sort(obj: *PyObject) void {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(list_obj.ob_base.ob_size);

        if (size <= 1) return;

        var i: usize = 0;
        while (i < size) : (i += 1) {
            var j: usize = 0;
            while (j < size - i - 1) : (j += 1) {
                if (runtime.PyLong_Check(list_obj.ob_item[j]) and runtime.PyLong_Check(list_obj.ob_item[j + 1])) {
                    const obj_j: *PyLongObject = @ptrCast(@alignCast(list_obj.ob_item[j]));
                    const obj_j1: *PyLongObject = @ptrCast(@alignCast(list_obj.ob_item[j + 1]));
                    if (obj_j.ob_digit > obj_j1.ob_digit) {
                        const temp = list_obj.ob_item[j];
                        list_obj.ob_item[j] = list_obj.ob_item[j + 1];
                        list_obj.ob_item[j + 1] = temp;
                    }
                }
            }
        }
    }

    /// Create a shallow copy of the list
    pub fn copy(allocator: std.mem.Allocator, obj: *PyObject) !*PyObject {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(list_obj.ob_base.ob_size);

        const new_list = try create(allocator);

        for (0..size) |i| {
            try append(new_list, list_obj.ob_item[i]);
        }

        return new_list;
    }

    /// Get length (method form)
    pub fn len_method(obj: *PyObject) i64 {
        return @intCast(len(obj));
    }

    /// Get minimum value in list
    pub fn min(obj: *PyObject) i64 {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(list_obj.ob_base.ob_size);

        if (size == 0) return 0;

        var min_val: i64 = std.math.maxInt(i64);
        for (0..size) |i| {
            if (runtime.PyLong_Check(list_obj.ob_item[i])) {
                const long_obj: *PyLongObject = @ptrCast(@alignCast(list_obj.ob_item[i]));
                if (long_obj.ob_digit < min_val) {
                    min_val = long_obj.ob_digit;
                }
            }
        }
        return min_val;
    }

    /// Get maximum value in list
    pub fn max(obj: *PyObject) i64 {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(list_obj.ob_base.ob_size);

        if (size == 0) return 0;

        var max_val: i64 = std.math.minInt(i64);
        for (0..size) |i| {
            if (runtime.PyLong_Check(list_obj.ob_item[i])) {
                const long_obj: *PyLongObject = @ptrCast(@alignCast(list_obj.ob_item[i]));
                if (long_obj.ob_digit > max_val) {
                    max_val = long_obj.ob_digit;
                }
            }
        }
        return max_val;
    }

    /// Sum all values in list
    pub fn sum(obj: *PyObject) i64 {
        std.debug.assert(runtime.PyList_Check(obj));
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        const size: usize = @intCast(list_obj.ob_base.ob_size);

        var total: i64 = 0;
        for (0..size) |i| {
            if (runtime.PyLong_Check(list_obj.ob_item[i])) {
                const long_obj: *PyLongObject = @ptrCast(@alignCast(list_obj.ob_item[i]));
                total += long_obj.ob_digit;
            }
        }
        return total;
    }
};

// CPython-compatible C API functions
pub fn PyList_New(size: runtime.Py_ssize_t) callconv(.C) *PyObject {
    const allocator = allocator_helper.fast_allocator;
    const list_obj = allocator.create(PyListObject) catch @panic("PyList_New allocation failed");

    const capacity: usize = if (size > 0) @intCast(size) else 4;
    const item_array = allocator.alloc(*PyObject, capacity) catch @panic("PyList_New item allocation failed");

    list_obj.* = PyListObject{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1,
                .ob_type = PyList_Type,
            },
            .ob_size = size,
        },
        .ob_item = item_array.ptr,
        .allocated = @intCast(capacity),
    };
    return @ptrCast(list_obj);
}

pub fn PyList_Size(obj: *PyObject) callconv(.C) runtime.Py_ssize_t {
    const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
    return list_obj.ob_base.ob_size;
}

pub fn PyList_GetItem(obj: *PyObject, idx: runtime.Py_ssize_t) callconv(.C) *PyObject {
    const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
    return list_obj.ob_item[@intCast(idx)];
}

pub fn PyList_SetItem(obj: *PyObject, idx: runtime.Py_ssize_t, item: *PyObject) callconv(.C) c_int {
    const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
    const old_item = list_obj.ob_item[@intCast(idx)];
    list_obj.ob_item[@intCast(idx)] = item;
    runtime.Py_DECREF(old_item);
    return 0;
}

// =============================================================================
// NativeList - Unified list type for native codegen (avoids anytype monomorphization)
// =============================================================================
//
// This type wraps ArrayListUnmanaged(PyValue) and provides typed accessors
// for common element types (i64, f64, []const u8, bool) without using anytype.
// This is critical for reducing Zig compilation time.
//
// Usage in codegen:
//   var list = runtime.NativeList.init();
//   try list.appendInt(allocator, 42);
//   try list.appendFloat(allocator, 3.14);
//   try list.appendString(allocator, "hello");
//
// Or from typed slices (no monomorphization):
//   const list = runtime.NativeList.fromIntSlice(allocator, &[_]i64{1, 2, 3});

/// NativeList - Unified Python list for native codegen
/// Stores all elements as PyValue for heterogeneous support
/// Provides typed accessors to avoid anytype monomorphization
pub const NativeList = struct {
    items: std.ArrayListUnmanaged(runtime.PyValue) = .{},

    const Self = @This();

    /// Create empty list
    pub fn init() Self {
        return .{};
    }

    /// Get number of items
    pub fn len(self: *const Self) usize {
        return self.items.items.len;
    }

    /// Check if empty
    pub fn isEmpty(self: *const Self) bool {
        return self.items.items.len == 0;
    }

    /// Get underlying slice
    pub fn slice(self: *const Self) []const runtime.PyValue {
        return self.items.items;
    }

    /// Get mutable slice
    pub fn sliceMut(self: *Self) []runtime.PyValue {
        return self.items.items;
    }

    // =========================================================================
    // Typed append methods (no anytype - concrete types only)
    // =========================================================================

    /// Append an integer
    pub fn appendInt(self: *Self, allocator: std.mem.Allocator, value: i64) !void {
        try self.items.append(allocator, .{ .int = value });
    }

    /// Append a float
    pub fn appendFloat(self: *Self, allocator: std.mem.Allocator, value: f64) !void {
        try self.items.append(allocator, .{ .float = value });
    }

    /// Append a string
    pub fn appendString(self: *Self, allocator: std.mem.Allocator, value: []const u8) !void {
        try self.items.append(allocator, .{ .string = value });
    }

    /// Append a bool
    pub fn appendBool(self: *Self, allocator: std.mem.Allocator, value: bool) !void {
        try self.items.append(allocator, .{ .bool = value });
    }

    /// Append a PyValue directly
    pub fn appendValue(self: *Self, allocator: std.mem.Allocator, value: runtime.PyValue) !void {
        try self.items.append(allocator, value);
    }

    /// Append none
    pub fn appendNone(self: *Self, allocator: std.mem.Allocator) !void {
        try self.items.append(allocator, .none);
    }

    // =========================================================================
    // Typed get methods (no anytype)
    // =========================================================================

    /// Get item at index
    pub fn get(self: *const Self, index: usize) ?runtime.PyValue {
        if (index >= self.items.items.len) return null;
        return self.items.items[index];
    }

    /// Get item as int (returns null if not int or out of bounds)
    pub fn getInt(self: *const Self, index: usize) ?i64 {
        const val = self.get(index) orelse return null;
        return switch (val) {
            .int => |i| i,
            else => null,
        };
    }

    /// Get item as float (returns null if not float or out of bounds)
    pub fn getFloat(self: *const Self, index: usize) ?f64 {
        const val = self.get(index) orelse return null;
        return switch (val) {
            .float => |f| f,
            .int => |i| @as(f64, @floatFromInt(i)), // int->float coercion
            else => null,
        };
    }

    /// Get item as string (returns null if not string or out of bounds)
    pub fn getString(self: *const Self, index: usize) ?[]const u8 {
        const val = self.get(index) orelse return null;
        return switch (val) {
            .string => |s| s,
            else => null,
        };
    }

    /// Get item as bool (returns null if not bool or out of bounds)
    pub fn getBool(self: *const Self, index: usize) ?bool {
        const val = self.get(index) orelse return null;
        return switch (val) {
            .bool => |b| b,
            else => null,
        };
    }

    // =========================================================================
    // Conversion from typed slices (concrete types - no monomorphization)
    // =========================================================================

    /// Create list from i64 slice
    pub fn fromIntSlice(allocator: std.mem.Allocator, values: []const i64) !Self {
        var list = Self{};
        try list.items.ensureTotalCapacity(allocator, values.len);
        for (values) |v| {
            list.items.appendAssumeCapacity(.{ .int = v });
        }
        return list;
    }

    /// Create list from f64 slice
    pub fn fromFloatSlice(allocator: std.mem.Allocator, values: []const f64) !Self {
        var list = Self{};
        try list.items.ensureTotalCapacity(allocator, values.len);
        for (values) |v| {
            list.items.appendAssumeCapacity(.{ .float = v });
        }
        return list;
    }

    /// Create list from string slice
    pub fn fromStringSlice(allocator: std.mem.Allocator, values: []const []const u8) !Self {
        var list = Self{};
        try list.items.ensureTotalCapacity(allocator, values.len);
        for (values) |v| {
            list.items.appendAssumeCapacity(.{ .string = v });
        }
        return list;
    }

    /// Create list from bool slice
    pub fn fromBoolSlice(allocator: std.mem.Allocator, values: []const bool) !Self {
        var list = Self{};
        try list.items.ensureTotalCapacity(allocator, values.len);
        for (values) |v| {
            list.items.appendAssumeCapacity(.{ .bool = v });
        }
        return list;
    }

    /// Create list from PyValue slice
    pub fn fromValueSlice(allocator: std.mem.Allocator, values: []const runtime.PyValue) !Self {
        var list = Self{};
        try list.items.ensureTotalCapacity(allocator, values.len);
        for (values) |v| {
            list.items.appendAssumeCapacity(v);
        }
        return list;
    }

    // =========================================================================
    // List operations
    // =========================================================================

    /// Extend with another NativeList
    pub fn extend(self: *Self, allocator: std.mem.Allocator, other: *const Self) !void {
        try self.items.appendSlice(allocator, other.items.items);
    }

    /// Pop last item
    pub fn pop(self: *Self) ?runtime.PyValue {
        return self.items.popOrNull();
    }

    /// Clear all items
    pub fn clear(self: *Self, allocator: std.mem.Allocator) void {
        self.items.clearAndFree(allocator);
    }

    /// Deinit
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
    }

    /// Convert to bool (Python semantics: empty list is false)
    pub fn toBool(self: *const Self) bool {
        return self.items.items.len > 0;
    }

    /// Iterate over items
    pub fn iterator(self: *const Self) []const runtime.PyValue {
        return self.items.items;
    }
};
