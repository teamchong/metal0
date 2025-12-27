/// Container operations for Python semantics
/// Handles set equality, generic contains, concatenation, repetition
const std = @import("std");
const PyValue = @import("../Objects/object.zig").PyValue;

/// Compare two sets for equality
/// Sets are equal if they have the same elements (order doesn't matter)
pub fn setEqual(a: anytype, b: anytype) bool {
    // If they're the same pointer, they're equal (identity)
    if (@intFromPtr(&a) == @intFromPtr(&b)) return true;

    // Check if they have the same count
    if (a.count() != b.count()) return false;

    // Check if all elements in a are in b
    var iter = a.iterator();
    while (iter.next()) |entry| {
        if (b.get(entry.key_ptr.*) == null) return false;
    }

    return true;
}

/// Generic 'in' operator for any type - works with ArrayLists, slices, etc.
/// Uses pyValueCompare for comparison (unified PyValue-based equality)
/// Two-Flow: Handles PyValue containers for uncertain types
pub fn containsGeneric(comptime NativeList: type, eqlFn: anytype, container: anytype, item: anytype) bool {
    const T = @TypeOf(container);
    const info = @typeInfo(T);

    // Two-Flow: Handle PyValue (uncertain type wrapper)
    if (T == PyValue) {
        return switch (container) {
            .list => |list| blk: {
                for (list.items) |elem| {
                    // For PyValue items, use PyValue comparison
                    const ItemT = @TypeOf(item);
                    if (ItemT == PyValue) {
                        if (elem.eql(item)) break :blk true;
                    } else if (eqlFn(elem, item)) {
                        break :blk true;
                    }
                }
                break :blk false;
            },
            .tuple => |tuple_items| blk: {
                for (tuple_items) |elem| {
                    const ItemT = @TypeOf(item);
                    if (ItemT == PyValue) {
                        if (elem.eql(item)) break :blk true;
                    } else if (eqlFn(elem, item)) {
                        break :blk true;
                    }
                }
                break :blk false;
            },
            .string => |s| blk: {
                const ItemT = @TypeOf(item);
                if (ItemT == []const u8 or ItemT == []u8) {
                    break :blk std.mem.indexOf(u8, s, item) != null;
                }
                break :blk false;
            },
            else => false,
        };
    }

    // Check for NativeList type first (has .items which is an ArrayList, not a slice)
    if (T == NativeList) {
        for (container.items.items) |elem| {
            if (eqlFn(elem, item)) return true;
        }
        return false;
    }

    // ArrayList: check .items (items is a slice)
    if (info == .@"struct" and @hasField(T, "items")) {
        for (container.items) |elem| {
            if (eqlFn(elem, item)) return true;
        }
        return false;
    }

    // Array: iterate and compare (e.g., [_]i64{1, 2, 3})
    if (info == .array) {
        for (container) |elem| {
            if (eqlFn(elem, item)) return true;
        }
        return false;
    }

    // Slice: iterate and compare
    if (info == .pointer and info.pointer.size == .slice) {
        for (container) |elem| {
            if (eqlFn(elem, item)) return true;
        }
        return false;
    }

    // Empty list []
    if (info == .pointer and info.pointer.size == .one) {
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .array and child_info.array.len == 0) {
            return false;
        }
    }

    return false;
}

/// Compare arrays/slices lexicographically for less-than
pub fn arrayLessThan(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);

    // Get the element count for each operand
    const a_len = if (@typeInfo(A) == .array)
        @typeInfo(A).array.len
    else if (@typeInfo(A) == .pointer and @typeInfo(A).pointer.size == .slice)
        a.len
    else
        @compileError("arrayLessThan expects array or slice");

    const b_len = if (@typeInfo(B) == .array)
        @typeInfo(B).array.len
    else if (@typeInfo(B) == .pointer and @typeInfo(B).pointer.size == .slice)
        b.len
    else
        @compileError("arrayLessThan expects array or slice");

    // Compare element by element
    const min_len = @min(a_len, b_len);
    for (0..min_len) |i| {
        const a_elem = if (@typeInfo(A) == .array) a[i] else a[i];
        const b_elem = if (@typeInfo(B) == .array) b[i] else b[i];
        if (a_elem < b_elem) return true;
        if (a_elem > b_elem) return false;
    }
    // If all elements equal, shorter array is less
    return a_len < b_len;
}
