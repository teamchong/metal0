/// Iterator builtins (range, enumerate, zip, iter, next)
const std = @import("std");
const runtime_core = @import("../../runtime.zig");
const pyint = @import("../../Objects/intobject.zig");
const pylist = @import("../../Objects/listobject.zig");
const pytuple = @import("../../Objects/tupleobject.zig");

const PyObject = runtime_core.PyObject;
const PythonError = runtime_core.PythonError;
const PyInt = pyint.PyInt;
const PyList = pylist.PyList;
const PyTuple = pytuple.PyTuple;
const incref = runtime_core.incref;
const decref = runtime_core.decref;

/// Create a list of integers from start to stop with step
pub fn range(allocator: std.mem.Allocator, start: i64, stop: i64, step: i64) !*PyObject {
    if (step == 0) {
        return PythonError.ValueError;
    }

    const result_list = try PyList.create(allocator);

    if (step > 0) {
        var i = start;
        while (i < stop) : (i += step) {
            const item = try PyInt.create(allocator, i);
            try PyList.append(result_list, item);
            decref(item, allocator);
        }
    } else if (step < 0) {
        var i = start;
        while (i > stop) : (i += step) {
            const item = try PyInt.create(allocator, i);
            try PyList.append(result_list, item);
            decref(item, allocator);
        }
    }

    return result_list;
}

/// Create a list of (index, item) tuples from an iterable
pub fn enumerate(allocator: std.mem.Allocator, iterable: *PyObject, start: i64) !*PyObject {
    std.debug.assert(iterable.type_id == .list);
    const source_list: *PyList = @ptrCast(@alignCast(iterable.data));

    const result = try PyList.create(allocator);

    var index = start;
    for (source_list.items.items) |item| {
        const result_tuple = try PyTuple.create(allocator, 2);
        const idx_obj = try PyInt.create(allocator, index);

        PyTuple.setItem(result_tuple, 0, idx_obj);
        decref(idx_obj, allocator);

        incref(item);
        PyTuple.setItem(result_tuple, 1, item);

        try PyList.append(result, result_tuple);
        decref(result_tuple, allocator);

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
        const result_tuple = try PyTuple.create(allocator, 2);

        incref(list1.items.items[i]);
        PyTuple.setItem(result_tuple, 0, list1.items.items[i]);

        incref(list2.items.items[i]);
        PyTuple.setItem(result_tuple, 1, list2.items.items[i]);

        try PyList.append(result, result_tuple);
        decref(result_tuple, allocator);
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
        const result_tuple = try PyTuple.create(allocator, 3);

        incref(list1.items.items[i]);
        PyTuple.setItem(result_tuple, 0, list1.items.items[i]);

        incref(list2.items.items[i]);
        PyTuple.setItem(result_tuple, 1, list2.items.items[i]);

        incref(list3.items.items[i]);
        PyTuple.setItem(result_tuple, 2, list3.items.items[i]);

        try PyList.append(result, result_tuple);
        decref(result_tuple, allocator);
    }

    return result;
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
pub const StringIterator = struct {
    data: []const u8,
    pos: usize,

    pub const Item = []const u8;

    pub fn init(s: []const u8) StringIterator {
        return .{ .data = s, .pos = 0 };
    }

    /// Get next Unicode character as a string slice
    pub fn next(self: *StringIterator) ?[]const u8 {
        if (self.pos >= self.data.len) return null;

        const byte = self.data[self.pos];
        const cp_len: usize = if (byte < 0x80)
            1
        else if (byte < 0xE0)
            2
        else if (byte < 0xF0)
            3
        else
            4;

        if (self.pos + cp_len > self.data.len) {
            self.pos = self.data.len;
            return null;
        }

        const start = self.pos;
        self.pos += cp_len;
        return self.data[start..self.pos];
    }

    pub fn isExhausted(self: StringIterator) bool {
        return self.pos >= self.data.len;
    }
};

/// iter() for strings - creates a stateful StringIterator
pub fn strIterator(s: []const u8) StringIterator {
    return StringIterator.init(s);
}

/// strIter(s) - creates a stateful string iterator
pub fn strIter(s: []const u8) StringIterator {
    return StringIterator.init(s);
}

/// iter() - return iterator over iterable (identity for already-iterable types)
pub fn iter(iterable: anytype) @TypeOf(iterable) {
    return iterable;
}

/// Generic iterator wrapper
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
            if (self.pos == 0) {
                self.pos = 1;
                return self.data;
            }
            return null;
        }
    };
}

/// Helper to get the item type from an iterator
pub fn IteratorItem(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .pointer) {
        const Child = info.pointer.child;
        const child_info = @typeInfo(Child);
        if (child_info == .@"struct" or child_info == .@"enum" or child_info == .@"union" or child_info == .@"opaque") {
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
        return error{StopIteration, TypeError}!void;
    }
    if (info == .@"struct" or info == .@"enum" or info == .@"union" or info == .@"opaque") {
        if (@hasDecl(T, "Item")) {
            return error{StopIteration}!T.Item;
        }
    }
    if (@hasDecl(T, "Item")) {
        return error{StopIteration}!T.Item;
    }
    return error{StopIteration}!void;
}

/// Get next item from an iterator
pub fn next(iterator: anytype) IteratorItem(@TypeOf(iterator)) {
    const T = @TypeOf(iterator);
    const info = @typeInfo(T);

    if (info == .pointer) {
        const Child = info.pointer.child;
        const child_info = @typeInfo(Child);
        if (child_info == .@"struct" or child_info == .@"enum" or child_info == .@"union" or child_info == .@"opaque") {
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
        return error.TypeError;
    }

    const type_info = @typeInfo(T);
    if (type_info == .@"struct" or type_info == .@"enum" or type_info == .@"union" or type_info == .@"opaque") {
        if (@hasDecl(T, "__next__")) {
            return iterator.__next__();
        }
        if (@hasDecl(T, "next")) {
            if (iterator.next()) |item| {
                return item;
            }
            return error.StopIteration;
        }
    }

    return error.TypeError;
}
