/// Operator comparison functions (eq, ne, lt, le, gt, ge, pyEqual)
const std = @import("std");

/// operator.eq - equality comparison
pub fn operatorEq(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .bool or info == .comptime_int or info == .comptime_float) {
            return a == b;
        }
    }
    return false;
}

/// operator.ne - inequality comparison
pub fn operatorNe(a: anytype, b: anytype) bool {
    return !operatorEq(a, b);
}

/// operator.lt - less than comparison
pub fn operatorLt(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .comptime_int or info == .comptime_float) {
            return a < b;
        }
    }
    return false;
}

/// operator.le - less than or equal comparison
pub fn operatorLe(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .comptime_int or info == .comptime_float) {
            return a <= b;
        }
    }
    return false;
}

/// operator.gt - greater than comparison
pub fn operatorGt(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .comptime_int or info == .comptime_float) {
            return a > b;
        }
    }
    return false;
}

/// operator.ge - greater than or equal comparison
pub fn operatorGe(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .comptime_int or info == .comptime_float) {
            return a >= b;
        }
    }
    return false;
}

/// Class instance equality comparison
pub fn classInstanceEq(a: anytype, b: anytype, allocator: std.mem.Allocator) bool {
    const TypeA = @TypeOf(a);
    const type_info = @typeInfo(TypeA);

    if (type_info == .@"struct" and @hasDecl(TypeA, "__eq__")) {
        const eq_info = @typeInfo(@TypeOf(TypeA.__eq__));
        if (eq_info == .@"fn") {
            const params = eq_info.@"fn".params;
            const result = if (params.len == 3)
                a.__eq__(allocator, b)
            else
                a.__eq__(b);

            const ResultType = @TypeOf(result);
            if (@typeInfo(ResultType) == .error_union) {
                return result catch false;
            } else if (ResultType == bool) {
                return result;
            }
        }
    }
    return false;
}

/// Class instance not-equal comparison
pub fn classInstanceNe(a: anytype, b: anytype, allocator: std.mem.Allocator) bool {
    const TypeA = @TypeOf(a);
    const type_info = @typeInfo(TypeA);

    if (type_info == .@"struct" and @hasDecl(TypeA, "__ne__")) {
        const ne_info = @typeInfo(@TypeOf(TypeA.__ne__));
        if (ne_info == .@"fn") {
            const params = ne_info.@"fn".params;
            const result = if (params.len == 3)
                a.__ne__(allocator, b)
            else
                a.__ne__(b);

            const ResultType = @TypeOf(result);
            if (@typeInfo(ResultType) == .error_union) {
                return result catch true;
            } else if (ResultType == bool) {
                return result;
            }
        }
    }
    return !classInstanceEq(a, b, allocator);
}

/// Generic assertEqual helper
pub fn assertEqualGeneric(a: anytype, b: anytype, allocator: std.mem.Allocator) !bool {
    return pyEqual(allocator, a, b);
}

/// Universal Python-semantic equality comparison
pub fn pyEqual(allocator: std.mem.Allocator, a: anytype, b: anytype) !bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);
    const info_a = @typeInfo(TypeA);
    const info_b = @typeInfo(TypeB);

    // Same type fast path
    if (TypeA == TypeB) {
        if (TypeA == f64) return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
        if (TypeA == f32) return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
        if (info_a == .int or info_a == .comptime_int or info_a == .comptime_float or info_a == .bool) {
            return a == b;
        }
        if (info_a == .pointer and info_a.pointer.size == .slice) {
            if (info_a.pointer.child == u8) {
                return std.mem.eql(u8, a, b);
            }
        }
    }

    // Tagged union handling
    if (info_a == .@"union" and info_a.@"union".tag_type != null) {
        const tag = std.meta.activeTag(a);
        inline for (info_a.@"union".fields) |field| {
            if (tag == @field(std.meta.Tag(TypeA), field.name)) {
                const field_value = @field(a, field.name);
                return pyEqual(allocator, field_value, b);
            }
        }
    }
    if (info_b == .@"union" and info_b.@"union".tag_type != null) {
        const tag = std.meta.activeTag(b);
        inline for (info_b.@"union".fields) |field| {
            if (tag == @field(std.meta.Tag(TypeB), field.name)) {
                const field_value = @field(b, field.name);
                return pyEqual(allocator, a, field_value);
            }
        }
    }

    // Builtin subclass handling
    if (info_a == .@"struct" and @hasField(TypeA, "__base_value__")) {
        return pyEqual(allocator, a.__base_value__, b);
    }
    if (info_b == .@"struct" and @hasField(TypeB, "__base_value__")) {
        return pyEqual(allocator, a, b.__base_value__);
    }

    // ArrayList comparison
    if (info_a == .@"struct" and @hasField(TypeA, "items") and @hasField(TypeA, "capacity") and
        info_b == .@"struct" and @hasField(TypeB, "items") and @hasField(TypeB, "capacity"))
    {
        if (a.items.len != b.items.len) return false;
        for (a.items, b.items) |item_a, item_b| {
            if (!try pyEqual(allocator, item_a, item_b)) return false;
        }
        return true;
    }

    // ArrayList to tuple
    if (info_a == .@"struct" and @hasField(TypeA, "items") and @hasField(TypeA, "capacity")) {
        return pyEqualSliceToTuple(allocator, a.items, b);
    }
    if (info_b == .@"struct" and @hasField(TypeB, "items") and @hasField(TypeB, "capacity")) {
        return pyEqualSliceToTuple(allocator, b.items, a);
    }

    // Tuple element-wise comparison
    if (info_a == .@"struct" and info_b == .@"struct") {
        const a_is_class = @hasDecl(TypeA, "__name__");
        const b_is_class = @hasDecl(TypeB, "__name__");
        if (!a_is_class and !b_is_class) {
            const fields_a = info_a.@"struct".fields;
            const fields_b = info_b.@"struct".fields;
            if (fields_a.len != fields_b.len) return false;
            inline for (fields_a, 0..) |field_a, i| {
                const a_val = @field(a, field_a.name);
                const b_val = @field(b, fields_b[i].name);
                if (!try pyEqual(allocator, a_val, b_val)) return false;
            }
            return true;
        }
    }

    // Custom __eq__ method
    const a_has_eq = info_a == .@"struct" and @hasDecl(TypeA, "__eq__");
    const b_has_eq = info_b == .@"struct" and @hasDecl(TypeB, "__eq__");

    if (a_has_eq) return classInstanceEq(a, b, allocator);
    if (b_has_eq) return classInstanceEq(b, a, allocator);

    // Numeric coercion fallback
    const object = @import("../../Objects/object.zig");
    const a_val = try object.toPyValue(allocator, a);
    const b_val = try object.toPyValue(allocator, b);
    return a_val.eql(b_val);
}

/// Helper to compare slice to tuple
pub fn pyEqualSliceToTuple(allocator: std.mem.Allocator, slice: anytype, tup: anytype) !bool {
    const SliceType = @TypeOf(slice);
    const TupleType = @TypeOf(tup);
    const slice_info = @typeInfo(SliceType);
    const tup_info = @typeInfo(TupleType);

    if (slice_info != .pointer or slice_info.pointer.size != .slice) return false;

    if (tup_info == .array) {
        const arr_info = tup_info.array;
        if (slice.len != arr_info.len) return false;
        for (0..arr_info.len) |i| {
            if (!try pyEqual(allocator, slice[i], tup[i])) return false;
        }
        return true;
    }

    if (tup_info == .@"struct") {
        const fields = tup_info.@"struct".fields;
        if (slice.len != fields.len) return false;
        inline for (fields, 0..) |field, i| {
            const tup_val = @field(tup, field.name);
            if (!try pyEqual(allocator, slice[i], tup_val)) return false;
        }
        return true;
    }

    return false;
}
