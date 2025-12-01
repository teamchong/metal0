/// Built-in Python functions implemented in Zig
const std = @import("std");
const runtime_core = @import("../runtime.zig");
const pyint = @import("../pyint.zig");
const pylist = @import("../pylist.zig");
const pystring = @import("../pystring.zig");
const pytuple = @import("../pytuple.zig");
const dict_module = @import("../dict.zig");
const BigInt = @import("bigint").BigInt;

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

/// Minimum value from any iterable (generic)
pub fn minIterable(iterable: anytype) i64 {
    const T = @TypeOf(iterable);
    if (T == *PyObject) {
        return minList(iterable);
    } else if (comptime std.meta.hasFn(T, "__getitem__")) {
        // Custom sequence class with __getitem__ method
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
        // Struct with items field (tuples, arrays)
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
    // Fallback for slices
    var min_val: i64 = std.math.maxInt(i64);
    for (iterable) |item| {
        if (item < min_val) {
            min_val = item;
        }
    }
    return min_val;
}

/// Get next item from an iterator (takes pointer for mutation)
pub fn next(iterator: anytype) IteratorItem(@TypeOf(iterator)) {
    const T = @TypeOf(iterator);
    const info = @typeInfo(T);

    // Handle pointer to iterator struct
    if (info == .pointer) {
        const Child = info.pointer.child;
        if (@hasDecl(Child, "next")) {
            if (iterator.next()) |item| {
                return item;
            }
            return error.StopIteration;
        }
        if (@hasDecl(Child, "__next__")) {
            return iterator.__next__();
        }
    }

    // Handle iterator struct directly (legacy)
    if (@hasDecl(T, "__next__")) {
        return iterator.__next__();
    }
    if (@hasDecl(T, "next")) {
        if (iterator.next()) |item| {
            return item;
        }
        return error.StopIteration;
    }

    @compileError("Type does not have next() or __next__() method");
}

/// Helper to get the item type from an iterator
fn IteratorItem(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .pointer) {
        const Child = info.pointer.child;
        if (@hasDecl(Child, "Item")) {
            return error{StopIteration}!Child.Item;
        }
        if (@hasDecl(Child, "next")) {
            const next_fn = @typeInfo(@TypeOf(@field(Child, "next")));
            if (next_fn == .@"fn") {
                const ReturnType = next_fn.@"fn".return_type.?;
                if (@typeInfo(ReturnType) == .optional) {
                    return error{StopIteration}!@typeInfo(ReturnType).optional.child;
                }
            }
        }
    }
    if (@hasDecl(T, "Item")) {
        return error{StopIteration}!T.Item;
    }
    return error{StopIteration}!void;
}

/// iter() for strings - creates a stateful StringIterator
pub fn strIterator(s: []const u8) StringIterator {
    return StringIterator.init(s);
}

/// iter() - return iterator over iterable (identity for already-iterable types)
pub fn iter(iterable: anytype) @TypeOf(iterable) {
    return iterable;
}

/// RangeIterator struct - lightweight lazy range iterator
pub const RangeIterator = struct {
    start: i64,
    stop: i64,
    step: i64,
    current: i64,

    pub fn init(start: i64, stop: i64, step: i64) RangeIterator {
        return .{ .start = start, .stop = stop, .step = step, .current = start };
    }

    pub fn next(self: *RangeIterator) ?i64 {
        if (self.step > 0) {
            if (self.current >= self.stop) return null;
        } else {
            if (self.current <= self.stop) return null;
        }
        const result = self.current;
        self.current += self.step;
        return result;
    }

    pub fn len(self: RangeIterator) usize {
        if (self.step > 0) {
            if (self.stop <= self.start) return 0;
            return @intCast(@divFloor(self.stop - self.start + self.step - 1, self.step));
        } else {
            if (self.stop >= self.start) return 0;
            return @intCast(@divFloor(self.start - self.stop - self.step - 1, -self.step));
        }
    }
};

/// rangeLazy(start, stop, step) - creates a lightweight range iterator
pub fn rangeLazy(start: i64, stop: i64, step: i64) RangeIterator {
    return RangeIterator.init(start, stop, step);
}

/// StringIterator struct - stateful iterator over string characters (Unicode codepoints)
/// This matches Python's iter(str) behavior where the iterator tracks its position
pub const StringIterator = struct {
    data: []const u8,
    pos: usize,

    pub const Item = []const u8;

    pub fn init(s: []const u8) StringIterator {
        return .{ .data = s, .pos = 0 };
    }

    /// Get next Unicode character as a string slice
    /// Returns null when exhausted (signals StopIteration)
    pub fn next(self: *StringIterator) ?[]const u8 {
        if (self.pos >= self.data.len) return null;

        // Decode UTF-8 codepoint length
        const byte = self.data[self.pos];
        const cp_len: usize = if (byte < 0x80)
            1
        else if (byte < 0xE0)
            2
        else if (byte < 0xF0)
            3
        else
            4;

        // Safety check
        if (self.pos + cp_len > self.data.len) {
            self.pos = self.data.len;
            return null;
        }

        const start = self.pos;
        self.pos += cp_len;
        return self.data[start..self.pos];
    }

    /// Check if iterator is exhausted
    pub fn isExhausted(self: StringIterator) bool {
        return self.pos >= self.data.len;
    }
};

/// strIter(s) - creates a stateful string iterator
pub fn strIter(s: []const u8) StringIterator {
    return StringIterator.init(s);
}

/// Generic iterator wrapper that can wrap different types
/// This provides a uniform interface for iter() on various types
pub fn GenericIterator(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const Item = switch (@typeInfo(T)) {
            .pointer => |ptr| if (ptr.size == .slice) ptr.child else T,
            else => T,
        };

        data: T,
        pos: usize,

        pub fn init(data: T) Self {
            return .{ .data = data, .pos = 0 };
        }

        pub fn next(self: *Self) ?Item {
            const info = @typeInfo(T);
            if (info == .pointer and info.pointer.size == .slice) {
                if (self.pos >= self.data.len) return null;
                const item = self.data[self.pos];
                self.pos += 1;
                return item;
            }
            // For other types, just return the data once
            if (self.pos == 0) {
                self.pos = 1;
                return self.data;
            }
            return null;
        }
    };
}

/// Maximum value from any iterable (generic)
pub fn maxIterable(iterable: anytype) i64 {
    const T = @TypeOf(iterable);
    if (T == *PyObject) {
        return maxList(iterable);
    } else if (comptime std.meta.hasFn(T, "__getitem__")) {
        // Custom sequence class with __getitem__ method
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
        // Struct with items field (tuples, arrays)
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
    // Fallback for slices
    var max_val: i64 = std.math.minInt(i64);
    for (iterable) |item| {
        if (item > max_val) {
            max_val = item;
        }
    }
    return max_val;
}

/// Python round() - rounds a number to given precision
/// For integers, returns the integer unchanged
/// For floats, returns @round result
pub fn pyRound(value: anytype) i64 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);
    if (info == .int or info == .comptime_int) {
        return @as(i64, @intCast(value));
    } else if (info == .float or info == .comptime_float) {
        return @intFromFloat(@round(value));
    }
    // For other types (structs with __round__ method), not handled here
    return 0;
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

/// callable() builtin - returns true if object is callable
/// Works with: functions, function pointers, PyObjects with __call__
pub fn callable(obj: anytype) bool {
    const T = @TypeOf(obj);
    // Check if it's a function type
    if (@typeInfo(T) == .@"fn") return true;
    if (@typeInfo(T) == .pointer) {
        const child = @typeInfo(T).pointer.child;
        if (@typeInfo(child) == .@"fn") return true;
    }
    // Check for PyObject with __call__
    if (T == *PyObject) {
        // For now, return false for PyObjects (no callable detection yet)
        // TODO: check for __call__ attribute
        return false;
    }
    return false;
}

/// len() builtin as a first-class function value
/// For use in contexts like callable(len)
pub fn len(obj: anytype) usize {
    const T = @TypeOf(obj);
    if (T == *PyObject) {
        return runtime_core.pyLen(obj);
    } else if (@typeInfo(T) == .pointer) {
        const Child = @typeInfo(T).pointer.child;
        if (@hasField(Child, "items")) {
            return obj.items.len;
        } else if (@hasDecl(Child, "len")) {
            return obj.len;
        }
    } else if (@typeInfo(T) == .array) {
        return @typeInfo(T).array.len;
    } else if (comptime isSlice(T)) {
        return obj.len;
    }
    return 0;
}

/// id() builtin - returns object identity (pointer address)
pub fn id(obj: anytype) usize {
    const T = @TypeOf(obj);
    if (@typeInfo(T) == .pointer) {
        return @intFromPtr(obj);
    }
    return 0;
}

/// hash() builtin - returns hash of object
pub fn hash(obj: anytype) i64 {
    const T = @TypeOf(obj);
    if (T == *PyObject) {
        return @intCast(runtime_core.pyHash(obj));
    } else if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
        return @intCast(obj);
    } else if (T == []const u8 or T == []u8) {
        var h: u64 = 0;
        for (obj) |c| h = h *% 31 +% c;
        return @intCast(h);
    }
    return 0;
}

/// Helper to check if type is a slice
fn isSlice(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |p| p.size == .Slice,
        else => false,
    };
}

/// compile() builtin - compile source code
/// In AOT context, this raises an error since we can't compile at runtime
pub fn compile(source: []const u8, filename: []const u8, mode: []const u8) PythonError!void {
    _ = source;
    _ = filename;
    _ = mode;
    // In AOT context, compile() is not supported - it requires runtime compilation
    return PythonError.ValueError;
}

/// exec() builtin - execute compiled code
/// In AOT context, this raises an error
pub fn exec(code: anytype) PythonError!void {
    _ = code;
    return PythonError.ValueError;
}

/// int(string, base) with runtime base validation
/// Used in assertRaises context where base might be invalid (negative, > 36, etc.)
pub fn intWithBase(allocator: std.mem.Allocator, string: anytype, base: anytype) PythonError!i128 {
    _ = allocator;

    // Get string value
    const str_val: []const u8 = blk: {
        const T = @TypeOf(string);
        if (T == []const u8 or T == []u8) break :blk string;
        if (@typeInfo(T) == .pointer) {
            const child = @typeInfo(T).pointer.child;
            if (@typeInfo(child) == .array) {
                const arr_info = @typeInfo(child).array;
                if (arr_info.child == u8) break :blk string;
            }
        }
        // For pointer to array type like *const [N:0]u8
        break :blk string;
    };

    // Validate base at runtime
    const base_int: i64 = switch (@typeInfo(@TypeOf(base))) {
        .int, .comptime_int => @intCast(base),
        // Float base is TypeError in Python
        .float, .comptime_float => return PythonError.TypeError,
        .@"struct" => blk: {
            // Check if it's a BigInt - try to convert to i64
            if (@hasDecl(@TypeOf(base), "toInt64")) {
                // It's a BigInt - try to get as i64
                if (base.toInt64()) |val| {
                    break :blk val;
                } else {
                    // BigInt too large for base - definitely out of range
                    return PythonError.ValueError;
                }
            }
            return PythonError.TypeError;
        },
        else => return PythonError.TypeError,
    };

    // Valid bases are 0 or 2-36
    if (base_int != 0 and (base_int < 2 or base_int > 36)) {
        return PythonError.ValueError;
    }

    // Use the validated base
    const actual_base: u8 = if (base_int == 0) 10 else @intCast(base_int);
    return std.fmt.parseInt(i128, str_val, actual_base) catch PythonError.ValueError;
}

// Type factory functions - callable versions of Python types
// These allow types like bytes, str to be used as first-class values

/// str() type factory - converts value to string (generic version)
pub fn str(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8 or T == [:0]const u8) {
        return value;
    }
    // For other types, return empty string (proper implementation would format)
    return "";
}

/// bytes() type factory - converts value to bytes (generic version)
pub fn bytes(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8 or T == [:0]const u8) {
        return value;
    }
    return "";
}

/// bytearray() type factory - converts value to bytearray (mutable bytes)
pub fn bytearray(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8 or T == [:0]const u8) {
        return value;
    }
    return "";
}

/// memoryview() type factory - creates a memoryview of the value (generic version)
pub fn memoryview(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8 or T == [:0]const u8) {
        return value;
    }
    return "";
}

/// PyCallable - Type-erased callable wrapper for storing heterogeneous callables in lists
/// Used when Python code creates lists of mixed callable types (functions, lambdas, type constructors)
pub const PyCallable = struct {
    /// Type-erased function pointer that takes bytes and returns bytes
    call_fn: *const fn ([]const u8) []const u8,
    /// Optional context for closures (null for simple functions)
    context: ?*anyopaque,

    /// Call this callable with the given argument
    pub fn call(self: PyCallable, arg: []const u8) []const u8 {
        return self.call_fn(arg);
    }

    /// Create a PyCallable from a function pointer
    pub fn fromFn(func: *const fn ([]const u8) []const u8) PyCallable {
        return .{ .call_fn = func, .context = null };
    }

    /// Create a PyCallable from any callable (type-erased)
    /// For class constructors that return structs with __base_value__, extracts the bytes
    pub fn fromAny(comptime T: type, comptime func: T) PyCallable {
        const type_info = @typeInfo(T);

        // Handle function pointers
        if (type_info == .pointer and @typeInfo(type_info.pointer.child) == .@"fn") {
            const fn_info = @typeInfo(type_info.pointer.child).@"fn";
            const ReturnType = fn_info.return_type orelse void;

            const Wrapper = struct {
                fn thunk(arg: []const u8) []const u8 {
                    // Check number of parameters
                    if (fn_info.params.len == 1) {
                        // Single arg function (like lambda b: ...)
                        const result = func(arg);
                        return extractBytes(ReturnType, result);
                    } else if (fn_info.params.len == 2) {
                        // Two arg function (like CustomClass.init(allocator, bytes))
                        // Use global allocator - this is safe because we're in runtime context
                        const result = func(std.heap.page_allocator, arg);
                        return extractBytes(ReturnType, result);
                    }
                    return arg;
                }

                fn extractBytes(comptime R: type, value: R) []const u8 {
                    const r_info = @typeInfo(R);
                    // If return type is []const u8, return as-is
                    if (R == []const u8 or R == []u8) {
                        return value;
                    }
                    // If return type is a struct with __base_value__, extract it
                    if (r_info == .@"struct" and @hasField(R, "__base_value__")) {
                        return value.__base_value__;
                    }
                    // If return type is pointer to struct with __base_value__
                    if (r_info == .pointer and r_info.pointer.size == .one) {
                        const child_info = @typeInfo(r_info.pointer.child);
                        if (child_info == .@"struct" and @hasField(r_info.pointer.child, "__base_value__")) {
                            return value.__base_value__;
                        }
                    }
                    // Fallback - return empty
                    return "";
                }
            };
            return .{ .call_fn = &Wrapper.thunk, .context = null };
        }

        // Handle bound methods / struct functions
        if (type_info == .@"fn") {
            const fn_info = type_info.@"fn";
            const ReturnType = fn_info.return_type orelse void;

            const Wrapper = struct {
                fn thunk(arg: []const u8) []const u8 {
                    if (fn_info.params.len == 1) {
                        const result = func(arg);
                        return extractBytesFromResult(ReturnType, result);
                    } else if (fn_info.params.len == 2) {
                        const result = func(std.heap.page_allocator, arg);
                        return extractBytesFromResult(ReturnType, result);
                    }
                    return arg;
                }

                fn extractBytesFromResult(comptime R: type, value: R) []const u8 {
                    const r_info = @typeInfo(R);
                    if (R == []const u8 or R == []u8) {
                        return value;
                    }
                    if (r_info == .@"struct" and @hasField(R, "__base_value__")) {
                        return value.__base_value__;
                    }
                    if (r_info == .pointer and r_info.pointer.size == .one) {
                        const child_info = @typeInfo(r_info.pointer.child);
                        if (child_info == .@"struct" and @hasField(r_info.pointer.child, "__base_value__")) {
                            return value.__base_value__;
                        }
                    }
                    return "";
                }
            };
            return .{ .call_fn = &Wrapper.thunk, .context = null };
        }

        // Fallback - identity function
        const Wrapper = struct {
            fn thunk(arg: []const u8) []const u8 {
                return arg;
            }
        };
        return .{ .call_fn = &Wrapper.thunk, .context = null };
    }
};

// Concrete wrapper functions with fixed signatures for use in heterogeneous lists
// These can be stored as function pointers

/// bytes() as a concrete callable (fixed signature for list storage)
pub fn bytes_callable(value: []const u8) []const u8 {
    return value;
}

/// bytearray() as a concrete callable (fixed signature for list storage)
pub fn bytearray_callable(value: []const u8) []const u8 {
    return value;
}

/// str() as a concrete callable (fixed signature for list storage)
pub fn str_callable(value: []const u8) []const u8 {
    return value;
}

/// memoryview() as a concrete callable (fixed signature for list storage)
pub fn memoryview_callable(value: []const u8) []const u8 {
    return value;
}

/// BigInt-aware divmod - returns tuple of (quotient, remainder)
/// Handles BigInt, i64, and anytype parameters via comptime dispatch
pub fn bigIntDivmod(a: anytype, b: anytype, allocator: std.mem.Allocator) struct { @TypeOf(a), @TypeOf(a) } {
    const AT = @TypeOf(a);
    const BT = @TypeOf(b);

    // Both are BigInt
    if (@typeInfo(AT) == .@"struct" and @hasDecl(AT, "floorDiv") and
        @typeInfo(BT) == .@"struct" and @hasDecl(BT, "floorDiv"))
    {
        const q = a.floorDiv(&b, allocator) catch unreachable;
        const r = a.mod(&b, allocator) catch unreachable;
        return .{ q, r };
    }
    // a is BigInt, b is integer
    else if (@typeInfo(AT) == .@"struct" and @hasDecl(AT, "floorDiv")) {
        const b_big = BigInt.fromInt(allocator, @as(i64, @intCast(b))) catch unreachable;
        const q = a.floorDiv(&b_big, allocator) catch unreachable;
        const r = a.mod(&b_big, allocator) catch unreachable;
        return .{ q, r };
    }
    // Both are regular integers - use Zig builtins
    else {
        return .{ @divFloor(a, b), @rem(a, b) };
    }
}

/// Comparison operation enum for bigIntCompare
pub const CompareOp = enum { eq, ne, lt, le, gt, ge };

/// BigInt-aware comparison - handles BigInt vs BigInt, BigInt vs int, int vs int
pub fn bigIntCompare(a: anytype, b: anytype, op: CompareOp) bool {
    const AT = @TypeOf(a);
    const BT = @TypeOf(b);

    const a_is_bigint = @typeInfo(AT) == .@"struct" and @hasDecl(AT, "compare");
    const b_is_bigint = @typeInfo(BT) == .@"struct" and @hasDecl(BT, "compare");

    if (a_is_bigint and b_is_bigint) {
        // Both BigInt - use compare method
        const cmp = a.compare(&b);
        return switch (op) {
            .eq => cmp == 0,
            .ne => cmp != 0,
            .lt => cmp < 0,
            .le => cmp <= 0,
            .gt => cmp > 0,
            .ge => cmp >= 0,
        };
    } else if (a_is_bigint) {
        // a is BigInt, b is integer - compare by trying to convert BigInt to i128
        if (a.toInt128()) |a_val| {
            const b_val: i128 = @intCast(b);
            return switch (op) {
                .eq => a_val == b_val,
                .ne => a_val != b_val,
                .lt => a_val < b_val,
                .le => a_val <= b_val,
                .gt => a_val > b_val,
                .ge => a_val >= b_val,
            };
        } else {
            // BigInt too large for i128 - compare by sign
            // A huge positive is > any i128, huge negative is < any i128
            const is_neg = a.isNegative();
            return switch (op) {
                .eq => false,
                .ne => true,
                .lt => is_neg,
                .le => is_neg,
                .gt => !is_neg,
                .ge => !is_neg,
            };
        }
    } else if (b_is_bigint) {
        // b is BigInt, a is integer
        if (b.toInt128()) |b_val| {
            const a_val: i128 = @intCast(a);
            return switch (op) {
                .eq => a_val == b_val,
                .ne => a_val != b_val,
                .lt => a_val < b_val,
                .le => a_val <= b_val,
                .gt => a_val > b_val,
                .ge => a_val >= b_val,
            };
        } else {
            // BigInt too large for i128
            const is_neg = b.isNegative();
            return switch (op) {
                .eq => false,
                .ne => true,
                .lt => !is_neg,
                .le => !is_neg,
                .gt => is_neg,
                .ge => is_neg,
            };
        }
    } else {
        // Check if these are complex types (ArrayList, tuple, HashMap, etc.)
        const a_is_complex = @typeInfo(AT) == .@"struct";
        const b_is_complex = @typeInfo(BT) == .@"struct";

        if (a_is_complex or b_is_complex) {
            // For complex types, only eq and ne are supported
            // If types don't match, they can't be equal
            if (AT != BT) {
                return switch (op) {
                    .eq => false,
                    .ne => true,
                    .lt, .le, .gt, .ge => false, // Not comparable
                };
            }
            const equal = std.meta.eql(a, b);
            return switch (op) {
                .eq => equal,
                .ne => !equal,
                .lt, .le, .gt, .ge => false, // Not comparable
            };
        }

        // Both are regular integers
        return switch (op) {
            .eq => a == b,
            .ne => a != b,
            .lt => a < b,
            .le => a <= b,
            .gt => a > b,
            .ge => a >= b,
        };
    }
}

// PyCallable instances for built-in type factories
pub const bytes_factory: PyCallable = PyCallable.fromFn(&bytes_callable);
pub const bytearray_factory: PyCallable = PyCallable.fromFn(&bytearray_callable);
pub const str_factory: PyCallable = PyCallable.fromFn(&str_callable);
pub const memoryview_factory: PyCallable = PyCallable.fromFn(&memoryview_callable);

// Operator module callable structs - these can be stored as values and called later
// Example: mod = operator.mod; mod(-1.0, 1.0)

/// operator.mod callable - Python modulo operation
/// Called as: OperatorMod{}.call(a, b) where self is ignored
/// Named 'call' to match callable_vars system
pub const OperatorMod = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        const T = @TypeOf(a);
        const BT = @TypeOf(b);
        // For floats, use @rem (Zig's floating-point remainder)
        // For ints, use @mod
        if (@typeInfo(T) == .float or @typeInfo(T) == .comptime_float) {
            return @rem(a, if (@typeInfo(BT) == .float) b else @as(T, @floatFromInt(b)));
        } else if (@typeInfo(BT) == .float or @typeInfo(BT) == .comptime_float) {
            return @rem(@as(BT, @floatFromInt(a)), b);
        } else {
            return @mod(a, b);
        }
    }
};

/// operator.pow callable - Python power operation
/// Called as: OperatorPow{}.call(a, b) where self is ignored
/// Named 'call' to match callable_vars system
pub const OperatorPow = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) f64 {
        const af: f64 = switch (@typeInfo(@TypeOf(a))) {
            .float, .comptime_float => @as(f64, a),
            .int, .comptime_int => @as(f64, @floatFromInt(a)),
            else => 0.0,
        };
        const bf: f64 = switch (@typeInfo(@TypeOf(b))) {
            .float, .comptime_float => @as(f64, b),
            .int, .comptime_int => @as(f64, @floatFromInt(b)),
            else => 0.0,
        };
        return std.math.pow(f64, af, bf);
    }
};

/// Builtin pow callable - for when pow is used as first-class value
/// This is the same as OperatorPow but named 'pow' for direct access
/// e.g., `for pow_op in pow, operator.pow:`
pub const pow = OperatorPow{};

/// operator.concat callable - sequence concatenation
/// Called as: OperatorConcat{}.call(a, b)
pub const OperatorConcat = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, a: anytype, b: anytype) ![]const u8 {
        // For strings, concatenate
        const T = @TypeOf(a);
        if (T == []const u8 or T == []u8) {
            return std.fmt.allocPrint(allocator, "{s}{s}", .{ a, b });
        }
        // For other sequences, we'd need list concatenation
        return std.fmt.allocPrint(allocator, "{any}{any}", .{ a, b });
    }
};

/// operator.lt callable - less than comparison
pub const OperatorLt = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) bool {
        return a < b;
    }
};

/// operator.le callable - less than or equal comparison
pub const OperatorLe = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) bool {
        return a <= b;
    }
};

/// operator.eq callable - equality comparison
pub const OperatorEq = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) bool {
        return std.meta.eql(a, b);
    }
};

/// operator.ne callable - inequality comparison
pub const OperatorNe = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) bool {
        return !std.meta.eql(a, b);
    }
};

/// operator.ge callable - greater than or equal comparison
pub const OperatorGe = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) bool {
        return a >= b;
    }
};

/// operator.gt callable - greater than comparison
pub const OperatorGt = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) bool {
        return a > b;
    }
};

/// operator.abs callable - absolute value
pub const OperatorAbs = struct {
    pub fn call(_: @This(), a: anytype) @TypeOf(a) {
        return if (a < 0) -a else a;
    }
};

/// operator.add callable - addition
pub const OperatorAdd = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        return a + b;
    }
};

/// operator.and_ callable - bitwise and
pub const OperatorAnd = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        return a & b;
    }
};

/// operator.or_ callable - bitwise or
pub const OperatorOr = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        return a | b;
    }
};

/// operator.xor callable - bitwise xor
pub const OperatorXor = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        return a ^ b;
    }
};

/// operator.neg callable - negation
pub const OperatorNeg = struct {
    pub fn call(_: @This(), a: anytype) @TypeOf(a) {
        return -a;
    }
};

/// operator.pos callable - positive (identity for numbers)
pub const OperatorPos = struct {
    pub fn call(_: @This(), a: anytype) @TypeOf(a) {
        return a;
    }
};

/// operator.sub callable - subtraction
pub const OperatorSub = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        return a - b;
    }
};

/// operator.mul callable - multiplication
pub const OperatorMul = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        return a * b;
    }
};

/// operator.truediv callable - true division
pub const OperatorTruediv = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) f64 {
        const af: f64 = switch (@typeInfo(@TypeOf(a))) {
            .float, .comptime_float => @as(f64, a),
            .int, .comptime_int => @as(f64, @floatFromInt(a)),
            else => 0.0,
        };
        const bf: f64 = switch (@typeInfo(@TypeOf(b))) {
            .float, .comptime_float => @as(f64, b),
            .int, .comptime_int => @as(f64, @floatFromInt(b)),
            else => 1.0,
        };
        return af / bf;
    }
};

/// operator.floordiv callable - floor division
pub const OperatorFloordiv = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        return @divFloor(a, b);
    }
};

/// operator.lshift callable - left shift
pub const OperatorLshift = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        const shift: std.math.Log2Int(@TypeOf(a)) = @intCast(b);
        return a << shift;
    }
};

/// operator.rshift callable - right shift
pub const OperatorRshift = struct {
    pub fn call(_: @This(), a: anytype, b: anytype) @TypeOf(a) {
        const shift: std.math.Log2Int(@TypeOf(a)) = @intCast(b);
        return a >> shift;
    }
};

/// operator.invert callable - bitwise inversion
pub const OperatorInvert = struct {
    pub fn call(_: @This(), a: anytype) @TypeOf(a) {
        return ~a;
    }
};

/// Python type name constants for type() comparisons
/// These are used when comparing `type(x) == complex`, `type(x) == int`, etc.
/// They need to match the Zig type names returned by @typeName
pub const complex = "complex"; // Note: Zig doesn't have native complex; this is for API compatibility
pub const int = "i64";
pub const float = "f64";
pub const @"bool" = "bool";
pub const @"type" = "type";

/// Builtin format callable - for when format is used as first-class value
/// format(value, format_spec) -> str
pub const FormatBuiltin = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, value: anytype, format_spec: anytype) PythonError![]const u8 {
        // Convert format_spec to slice if it's a single char
        const spec_slice: []const u8 = blk: {
            const SpecType = @TypeOf(format_spec);
            if (SpecType == []const u8 or SpecType == []u8) {
                break :blk format_spec;
            } else if (SpecType == u8) {
                // Single char - create a slice
                const buf = allocator.alloc(u8, 1) catch return PythonError.TypeError;
                buf[0] = format_spec;
                break :blk buf;
            } else {
                return PythonError.TypeError;
            }
        };

        // Check if format_spec is "s" but value is not a string
        // Python raises TypeError for format(3.0, "s")
        const T = @TypeOf(value);
        if (std.mem.eql(u8, spec_slice, "s")) {
            // "s" format is only valid for strings
            if (T != []const u8 and T != []u8) {
                return PythonError.TypeError;
            }
            return value;
        }
        // For numbers, format as string
        return std.fmt.allocPrint(allocator, "{any}", .{value}) catch return PythonError.TypeError;
    }
};
pub const format = FormatBuiltin{};

/// Python round() builtin - rounds a float to the nearest integer or to ndigits
/// For infinity or NaN, raises OverflowError like Python does
/// round(x) -> int, round(x, ndigits) -> float
/// This version handles both 1 and 2 argument cases via variadic args tuple
pub fn round(value: anytype, args: anytype) PythonError!f64 {
    const T = @TypeOf(value);
    const ArgsT = @TypeOf(args);

    // Get ndigits from args tuple (if provided)
    const digits: i64 = blk: {
        // Check if args is a tuple type with fields
        if (@typeInfo(ArgsT) == .@"struct" and @typeInfo(ArgsT).@"struct".fields.len > 0) {
            // Get the first field (ndigits)
            const ndigits = args.@"0";
            const NdigitsT = @TypeOf(ndigits);
            if (@typeInfo(NdigitsT) == .float) {
                break :blk @as(i64, @intFromFloat(ndigits));
            } else if (@typeInfo(NdigitsT) == .int or @typeInfo(NdigitsT) == .comptime_int) {
                break :blk @as(i64, @intCast(ndigits));
            } else {
                break :blk 0;
            }
        } else {
            // No ndigits provided
            break :blk 0;
        }
    };

    // Check if ndigits was explicitly provided
    const has_ndigits = @typeInfo(ArgsT) == .@"struct" and @typeInfo(ArgsT).@"struct".fields.len > 0;

    if (@typeInfo(T) == .float or @typeInfo(T) == .comptime_float) {
        // Check for special float values
        if (std.math.isNan(value)) {
            return PythonError.ValueError;
        }
        if (std.math.isInf(value)) {
            return PythonError.OverflowError;
        }

        if (!has_ndigits or digits == 0) {
            // Round to nearest integer
            return @round(value);
        } else {
            // Round to ndigits decimal places
            const multiplier = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(digits)));
            return @round(value * multiplier) / multiplier;
        }
    } else if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
        return @as(f64, @floatFromInt(value));
    } else {
        return PythonError.TypeError;
    }
}
