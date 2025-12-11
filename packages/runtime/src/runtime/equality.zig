/// Python-style equality operations
/// Handles NaN identity semantics, container comparison, etc.
/// Extracted from runtime.zig to reduce file size
const std = @import("std");

const object_zig = @import("../Objects/object.zig");
const PyValue = object_zig.PyValue;
const pylist = @import("../Objects/listobject.zig");
const NativeList = pylist.NativeList;

/// Python-style containment check for slices
/// Handles NaN specially: both sides being NaN counts as a match (identity semantics)
pub fn pyContains(comptime T: type, slice: []const T, value: T) bool {
    // For floats, check NaN identity
    if (@typeInfo(T) == .float) {
        const value_is_nan = std.math.isNan(value);
        for (slice) |item| {
            if (value_is_nan and std.math.isNan(item)) return true;
            if (item == value) return true;
        }
        return false;
    }
    // For slice types (like strings), use std.mem.eql
    if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice) {
        for (slice) |item| {
            if (std.mem.eql(@typeInfo(T).pointer.child, item, value)) return true;
        }
        return false;
    }
    // For other types, use standard equality
    return std.mem.indexOfScalar(T, slice, value) != null;
}

/// Python-style count for slices
/// Handles NaN specially: both sides being NaN counts as a match (identity semantics)
pub fn pyCount(comptime T: type, slice: []const T, value: T) usize {
    var count: usize = 0;
    // For floats, check NaN identity
    if (@typeInfo(T) == .float) {
        const value_is_nan = std.math.isNan(value);
        for (slice) |item| {
            if ((value_is_nan and std.math.isNan(item)) or item == value) count += 1;
        }
    } else {
        // For other types, use standard equality
        for (slice) |item| {
            if (item == value) count += 1;
        }
    }
    return count;
}

/// Python-style slice equality
/// Handles NaN specially: two NaN values are considered equal (identity semantics)
pub fn pySliceEql(comptime T: type, a: []const T, b: []const T) bool {
    if (a.len != b.len) return false;
    // For floats, use NaN-aware comparison
    if (@typeInfo(T) == .float) {
        for (a, b) |a_item, b_item| {
            const a_nan = std.math.isNan(a_item);
            const b_nan = std.math.isNan(b_item);
            // Both NaN -> equal (identity), otherwise use value comparison
            if (a_nan and b_nan) continue;
            if (a_nan or b_nan) return false; // One NaN, one not
            if (a_item != b_item) return false;
        }
        return true;
    }
    // For other types, use standard equality
    return std.mem.eql(T, a, b);
}

/// Python-style tuple/array equality
/// Handles NaN specially: two NaN values are considered equal (identity semantics)
pub fn pyTupleEql(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);
    const info = @typeInfo(T);

    // Handle arrays
    if (info == .array) {
        const ElemT = info.array.child;
        if (@typeInfo(ElemT) == .float) {
            for (a, b) |a_item, b_item| {
                const a_nan = std.math.isNan(a_item);
                const b_nan = std.math.isNan(b_item);
                if (a_nan and b_nan) continue;
                if (a_nan or b_nan) return false;
                if (a_item != b_item) return false;
            }
            return true;
        }
    }

    // Handle structs (tuples are anonymous structs in Zig)
    if (info == .@"struct") {
        inline for (info.@"struct".fields) |field| {
            const a_field = @field(a, field.name);
            const b_field = @field(b, field.name);
            const FieldT = field.type;

            if (@typeInfo(FieldT) == .float) {
                const a_nan = std.math.isNan(a_field);
                const b_nan = std.math.isNan(b_field);
                // Both NaN -> equal (identity), skip to next field
                // Only one NaN or different values -> not equal
                if (!(a_nan and b_nan)) {
                    if (a_nan or b_nan) return false;
                    if (a_field != b_field) return false;
                }
            } else {
                if (!pyAnyEql(a_field, b_field)) return false;
            }
        }
        return true;
    }

    // Fallback to pyAnyEql for Python semantics
    return pyAnyEql(a, b);
}

/// Python-style generic equality for any two types
/// SIMPLIFIED VERSION: Avoids recursive calls to prevent comptime explosion
/// For complex types, use type-specific comparisons at codegen time instead
pub fn pyAnyEql(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const a_info = @typeInfo(A);
    const b_info = @typeInfo(B);

    // Same type: use std.meta.eql (single instantiation per type, not per pair)
    if (A == B) {
        // Special case: floats need bit-level identity for NaN (Python container semantics)
        // In Python, [nan] == [nan] returns True when nan is the same object (identity check)
        // We simulate this by comparing bit patterns - same bits = same identity
        if (A == f64) {
            return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
        }
        if (A == f32) {
            return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
        }
        // Special case: slices need std.mem.eql
        if (a_info == .pointer and a_info.pointer.size == .slice) {
            return std.mem.eql(a_info.pointer.child, a, b);
        }
        // Special case: ArrayLists need items comparison
        if (a_info == .@"struct" and @hasField(A, "items") and @hasField(A, "capacity")) {
            const ElemT = std.meta.Elem(@TypeOf(a.items));
            return std.mem.eql(ElemT, a.items, b.items);
        }
        // Special case: structs (tuples) need element-wise pyAnyEql for NaN handling
        // std.meta.eql uses == which fails for NaN
        if (a_info == .@"struct") {
            inline for (a_info.@"struct".fields) |field| {
                if (!pyAnyEql(@field(a, field.name), @field(b, field.name))) {
                    return false;
                }
            }
            return true;
        }
        return std.meta.eql(a, b);
    }

    // Different types: handle common cases without recursion
    // ArrayList vs fixed array
    const a_is_arraylist = a_info == .@"struct" and @hasField(A, "items") and @hasField(A, "capacity");
    const b_is_arraylist = b_info == .@"struct" and @hasField(B, "items") and @hasField(B, "capacity");

    if (a_is_arraylist and b_info == .array) {
        const AElem = std.meta.Elem(@TypeOf(a.items));
        const BElem = b_info.array.child;
        if (AElem != BElem) return false;
        if (a.items.len != b.len) return false;
        return std.mem.eql(AElem, a.items, &b);
    }
    if (a_info == .array and b_is_arraylist) {
        const AElem = a_info.array.child;
        const BElem = std.meta.Elem(@TypeOf(b.items));
        if (AElem != BElem) return false;
        if (a.len != b.items.len) return false;
        return std.mem.eql(AElem, &a, b.items);
    }

    // Numeric coercion: int vs comptime_int, float vs comptime_float
    const a_is_int = a_info == .int or a_info == .comptime_int;
    const b_is_int = b_info == .int or b_info == .comptime_int;
    if (a_is_int and b_is_int) {
        return @as(i64, a) == @as(i64, b);
    }

    const a_is_float = a_info == .float or a_info == .comptime_float;
    const b_is_float = b_info == .float or b_info == .comptime_float;
    if (a_is_float and b_is_float) {
        return @as(f64, a) == @as(f64, b);
    }

    // String slices
    if (a_info == .pointer and a_info.pointer.size == .slice and a_info.pointer.child == u8) {
        if (b_info == .pointer and b_info.pointer.size == .slice and b_info.pointer.child == u8) {
            return std.mem.eql(u8, a, b);
        }
    }

    // PyValue comparisons (without recursion)
    if (A == PyValue) {
        return switch (a) {
            .int => |v| if (b_info == .comptime_int or b_info == .int) v == @as(i64, b) else false,
            .float => |v| if (b_info == .comptime_float or b_info == .float) v == @as(f64, b) else false,
            .bool => |v| if (B == bool) v == b else false,
            .string => |v| if (b_info == .pointer and b_info.pointer.size == .slice and b_info.pointer.child == u8) std.mem.eql(u8, v, b) else false,
            else => false,
        };
    }
    if (B == PyValue) {
        return switch (b) {
            .int => |v| if (a_info == .comptime_int or a_info == .int) @as(i64, a) == v else false,
            .float => |v| if (a_info == .comptime_float or a_info == .float) @as(f64, a) == v else false,
            .bool => |v| if (A == bool) a == v else false,
            .string => |v| if (a_info == .pointer and a_info.pointer.size == .slice and a_info.pointer.child == u8) std.mem.eql(u8, a, v) else false,
            else => false,
        };
    }

    return false;
}

/// Python-style generic equality for any type (same type required)
/// Handles: lists (ArrayList), tuples (structs), sets (AutoHashMap with void value), dicts (AutoHashMap)
/// Uses NaN identity semantics for floats
pub fn pyAnyEqlSameType(comptime T: type, a: T, b: T) bool {
    const info = @typeInfo(T);

    // Handle NativeList first (has .items which is ArrayList, not slice)
    if (T == NativeList) {
        return pySliceEql(PyValue, a.items.items, b.items.items);
    }

    // ArrayList (Python list) - compare items with NaN semantics
    if (info == .@"struct" and @hasField(T, "items") and @hasField(T, "capacity")) {
        const ItemT = std.meta.Elem(@TypeOf(a.items));
        return pySliceEql(ItemT, a.items, b.items);
    }

    // AutoHashMap (Python set or dict) - compare by count and key/value match
    if (info == .@"struct" and @hasField(T, "entries") and @hasDecl(T, "count")) {
        if (a.count() != b.count()) return false;
        var it = a.iterator();
        while (it.next()) |entry| {
            if (!b.contains(entry.key_ptr.*)) return false;
            // For dicts, also compare values
            if (@hasDecl(T, "get")) {
                const ValT = @TypeOf(entry.value_ptr.*);
                if (ValT != void) {
                    // This is a dict (value type is not void)
                    if (b.get(entry.key_ptr.*)) |bv| {
                        if (!pyAnyEql(entry.value_ptr.*, bv)) return false;
                    } else {
                        return false;
                    }
                }
            }
        }
        return true;
    }

    // Tuples/structs - use pyTupleEql for NaN semantics
    if (info == .@"struct") {
        return pyTupleEql(a, b);
    }

    // Arrays - use pyTupleEql which handles arrays
    if (info == .array) {
        return pyTupleEql(a, b);
    }

    // Floats - handle NaN identity
    if (info == .float) {
        const a_nan = std.math.isNan(a);
        const b_nan = std.math.isNan(b);
        if (a_nan and b_nan) return true;
        if (a_nan or b_nan) return false;
        return a == b;
    }

    // Slices
    if (info == .pointer and info.pointer.size == .slice) {
        const ElemT = std.meta.Elem(T);
        return pySliceEql(ElemT, a, b);
    }

    // Fallback: simple types can use direct comparison
    // For primitive types that reach here, std.meta.eql is fine
    return std.meta.eql(a, b);
}

/// Convert ArrayList or other container types to a slice for iteration
/// This is a comptime function that normalizes different container types to slices
pub inline fn iterSlice(value: anytype) IterSliceType(@TypeOf(value)) {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Handle NativeList first (has .items which is ArrayList, not slice)
    if (T == NativeList) {
        return value.items.items;
    }

    // Handle ArrayList - extract .items slice
    if (info == .@"struct" and @hasField(T, "items") and @hasField(T, "capacity")) {
        return value.items;
    }

    // Handle pointer to ArrayList - dereference and extract .items
    if (info == .pointer and info.pointer.size == .one) {
        const Child = info.pointer.child;
        const child_info = @typeInfo(Child);
        if (child_info == .@"struct" and @hasField(Child, "items") and @hasField(Child, "capacity")) {
            return value.items;
        }
    }

    // Handle PyValue - extract list slice
    if (T == PyValue) {
        return switch (value) {
            .list => |l| l,
            .tuple => |t| t,
            else => &[_]PyValue{},
        };
    }

    // Array - convert to slice
    if (info == .array) {
        return &value;
    }

    // Already a slice - return as-is
    return value;
}

/// Helper to determine return type for iterSlice
fn IterSliceType(comptime T: type) type {
    const info = @typeInfo(T);

    // ArrayList -> slice of its item type
    if (info == .@"struct" and @hasField(T, "items") and @hasField(T, "capacity")) {
        // ArrayList.items is a slice, return that slice type directly
        return @TypeOf(@as(T, undefined).items);
    }

    // Pointer to ArrayList -> slice of its item type
    if (info == .pointer and info.pointer.size == .one) {
        const Child = info.pointer.child;
        const child_info = @typeInfo(Child);
        if (child_info == .@"struct" and @hasField(Child, "items") and @hasField(Child, "capacity")) {
            return @TypeOf(@as(Child, undefined).items);
        }
    }

    // PyValue -> []const PyValue
    if (T == PyValue) {
        return []const PyValue;
    }

    // Already a slice - return same type
    if (info == .pointer and info.pointer.size == .slice) {
        return T;
    }

    // Array - return as slice
    if (info == .array) {
        return []const info.array.child;
    }

    // Fallback
    return T;
}
