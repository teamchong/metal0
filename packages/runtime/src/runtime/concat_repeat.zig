/// Runtime-friendly list concatenation and repetition
const std = @import("std");

// Import from parent Objects
const object = @import("../Objects/object.zig");
const PyValue = object.PyValue;

// Import iterSlice from equality module
const equality_mod = @import("equality.zig");
const iterSlice = equality_mod.iterSlice;

/// Runtime-friendly list concatenation that handles PyValue types
/// Use this when values might not be comptime-known
/// Returns PyValue (list variant) for Python semantic compatibility
pub fn concatRuntime(allocator: std.mem.Allocator, a: anytype, b: anytype) !PyValue {
    var result = std.ArrayList(PyValue){};

    // Add elements from a
    const AType = @TypeOf(a);
    const a_is_pyvalue = @typeInfo(AType) == .@"union" and @hasField(AType, "list");
    const a_is_arraylist = @typeInfo(AType) == .@"struct" and @hasField(AType, "items") and @hasField(AType, "capacity");
    if (a_is_pyvalue) {
        const a_list = if (a == .list) a.list else if (a == .tuple) a.tuple else &[_]PyValue{};
        try result.appendSlice(allocator, a_list);
    } else if (a_is_arraylist) {
        // ArrayList - iterate over items and convert each to PyValue
        for (a.items) |item| {
            try result.append(allocator, try PyValue.fromAlloc(allocator, item));
        }
    } else {
        const a_slice = iterSlice(a);
        for (a_slice) |item| {
            try result.append(allocator, try PyValue.fromAlloc(allocator, item));
        }
    }

    // Add elements from b
    const BType = @TypeOf(b);
    const b_is_pyvalue = @typeInfo(BType) == .@"union" and @hasField(BType, "list");
    const b_is_arraylist = @typeInfo(BType) == .@"struct" and @hasField(BType, "items") and @hasField(BType, "capacity");
    if (b_is_pyvalue) {
        const b_list = if (b == .list) b.list else if (b == .tuple) b.tuple else &[_]PyValue{};
        try result.appendSlice(allocator, b_list);
    } else if (b_is_arraylist) {
        // ArrayList - iterate over items and convert each to PyValue
        for (b.items) |item| {
            try result.append(allocator, try PyValue.fromAlloc(allocator, item));
        }
    } else {
        const b_slice = iterSlice(b);
        for (b_slice) |item| {
            try result.append(allocator, try PyValue.fromAlloc(allocator, item));
        }
    }

    return PyValue{ .list = result.items };
}

/// Python list repetition: [1, 2] * 3 = [1, 2, 1, 2, 1, 2]
/// Returns a new list with elements repeated n times
pub fn repeatRuntime(allocator: std.mem.Allocator, a: anytype, n: anytype) !PyValue {
    var result = std.ArrayList(PyValue){};

    // Convert count to usize
    const count: usize = if (n < 0) 0 else @intCast(n);

    // Get the source elements
    const AType = @TypeOf(a);
    const a_is_pyvalue = @typeInfo(AType) == .@"union" and @hasField(AType, "list");
    const a_is_arraylist = @typeInfo(AType) == .@"struct" and @hasField(AType, "items") and @hasField(AType, "capacity");

    // Repeat n times
    for (0..count) |_| {
        if (a_is_pyvalue) {
            const a_list = if (a == .list) a.list else if (a == .tuple) a.tuple else &[_]PyValue{};
            try result.appendSlice(allocator, a_list);
        } else if (a_is_arraylist) {
            for (a.items) |item| {
                try result.append(allocator, try PyValue.fromAlloc(allocator, item));
            }
        } else {
            const a_slice = iterSlice(a);
            for (a_slice) |item| {
                try result.append(allocator, try PyValue.fromAlloc(allocator, item));
            }
        }
    }

    return PyValue{ .list = result.items };
}

/// Repeat an array n times - returns a new array with elements repeated
/// This is Python list multiplication: [1,2] * 3 = [1,2,1,2,1,2]
pub inline fn listRepeat(arr: anytype, n: anytype) @TypeOf(arr ** @as(usize, @intCast(n))) {
    return arr ** @as(usize, @intCast(n));
}
