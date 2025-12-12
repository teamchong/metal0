/// Operator comparison functions (eq, ne, lt, le, gt, ge, pyEqual)
const std = @import("std");
const PyValue = @import("../../Objects/object.zig").PyValue;

/// operator.eq - equality comparison
/// Two-Flow: Handles PyValue for uncertain types
pub fn operatorEq(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    // Two-Flow: Handle PyValue comparisons
    if (TypeA == PyValue and TypeB == PyValue) {
        return a.eql(b);
    }

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
/// Two-Flow: Handles PyValue for uncertain types
pub fn operatorLt(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    // Two-Flow: Handle PyValue comparisons
    if (TypeA == PyValue and TypeB == PyValue) {
        return a.lt(b);
    }

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .comptime_int or info == .comptime_float) {
            return a < b;
        }
    }
    return false;
}

/// operator.le - less than or equal comparison
/// Two-Flow: Handles PyValue for uncertain types
pub fn operatorLe(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    // Two-Flow: Handle PyValue comparisons
    if (TypeA == PyValue and TypeB == PyValue) {
        return a.le(b);
    }

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .comptime_int or info == .comptime_float) {
            return a <= b;
        }
    }
    return false;
}

/// operator.gt - greater than comparison
/// Two-Flow: Handles PyValue for uncertain types
pub fn operatorGt(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    // Two-Flow: Handle PyValue comparisons
    if (TypeA == PyValue and TypeB == PyValue) {
        return a.gt(b);
    }

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .comptime_int or info == .comptime_float) {
            return a > b;
        }
    }
    return false;
}

/// operator.ge - greater than or equal comparison
/// Two-Flow: Handles PyValue for uncertain types
pub fn operatorGe(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    // Two-Flow: Handle PyValue comparisons
    if (TypeA == PyValue and TypeB == PyValue) {
        return a.ge(b);
    }

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

/// Class instance less-than comparison
/// The result can be any type (e.g., SymbolicBool) - caller must handle __bool__ conversion
pub fn classInstanceLt(a: anytype, b: anytype, allocator: std.mem.Allocator) bool {
    const TypeA = @TypeOf(a);
    const type_info = @typeInfo(TypeA);

    if (type_info == .@"struct" and @hasDecl(TypeA, "__lt__")) {
        const lt_info = @typeInfo(@TypeOf(TypeA.__lt__));
        if (lt_info == .@"fn") {
            const params = lt_info.@"fn".params;
            const result = if (params.len == 3)
                a.__lt__(allocator, b)
            else
                a.__lt__(b);

            const ResultType = @TypeOf(result);
            if (@typeInfo(ResultType) == .error_union) {
                const payload = result catch return false;
                const PayloadType = @TypeOf(payload);
                if (PayloadType == bool) {
                    return payload;
                } else {
                    return toBoolFromResult(payload);
                }
            } else if (ResultType == bool) {
                return result;
            } else {
                return toBoolFromResult(result);
            }
        }
    } else if (type_info == .pointer and @typeInfo(type_info.pointer.child) == .@"struct") {
        const ChildType = type_info.pointer.child;
        if (@hasDecl(ChildType, "__lt__")) {
            const lt_info = @typeInfo(@TypeOf(ChildType.__lt__));
            if (lt_info == .@"fn") {
                const params = lt_info.@"fn".params;
                const result = if (params.len == 3)
                    a.__lt__(allocator, b)
                else
                    a.__lt__(b);

                const ResultType = @TypeOf(result);
                if (@typeInfo(ResultType) == .error_union) {
                    const payload = result catch return false;
                    const PayloadType = @TypeOf(payload);
                    if (PayloadType == bool) {
                        return payload;
                    } else {
                        return toBoolFromResult(payload);
                    }
                } else if (ResultType == bool) {
                    return result;
                } else {
                    return toBoolFromResult(result);
                }
            }
        }
    }
    return false;
}

/// Class instance less-than-or-equal comparison
pub fn classInstanceLe(a: anytype, b: anytype, allocator: std.mem.Allocator) bool {
    const TypeA = @TypeOf(a);
    const type_info = @typeInfo(TypeA);

    if (type_info == .@"struct" and @hasDecl(TypeA, "__le__")) {
        const le_info = @typeInfo(@TypeOf(TypeA.__le__));
        if (le_info == .@"fn") {
            const params = le_info.@"fn".params;
            const result = if (params.len == 3)
                a.__le__(allocator, b)
            else
                a.__le__(b);

            const ResultType = @TypeOf(result);
            if (@typeInfo(ResultType) == .error_union) {
                const payload = result catch return false;
                const PayloadType = @TypeOf(payload);
                if (PayloadType == bool) {
                    return payload;
                } else {
                    return toBoolFromResult(payload);
                }
            } else if (ResultType == bool) {
                return result;
            } else {
                return toBoolFromResult(result);
            }
        }
    } else if (type_info == .pointer and @typeInfo(type_info.pointer.child) == .@"struct") {
        const ChildType = type_info.pointer.child;
        if (@hasDecl(ChildType, "__le__")) {
            const le_info = @typeInfo(@TypeOf(ChildType.__le__));
            if (le_info == .@"fn") {
                const params = le_info.@"fn".params;
                const result = if (params.len == 3)
                    a.__le__(allocator, b)
                else
                    a.__le__(b);

                const ResultType = @TypeOf(result);
                if (@typeInfo(ResultType) == .error_union) {
                    const payload = result catch return false;
                    const PayloadType = @TypeOf(payload);
                    if (PayloadType == bool) {
                        return payload;
                    } else {
                        return toBoolFromResult(payload);
                    }
                } else if (ResultType == bool) {
                    return result;
                } else {
                    return toBoolFromResult(result);
                }
            }
        }
    }
    // Fallback: a <= b is a < b or a == b
    return classInstanceLt(a, b, allocator) or classInstanceEq(a, b, allocator);
}

/// Class instance greater-than comparison
pub fn classInstanceGt(a: anytype, b: anytype, allocator: std.mem.Allocator) bool {
    const TypeA = @TypeOf(a);
    const type_info = @typeInfo(TypeA);

    if (type_info == .@"struct" and @hasDecl(TypeA, "__gt__")) {
        const gt_info = @typeInfo(@TypeOf(TypeA.__gt__));
        if (gt_info == .@"fn") {
            const params = gt_info.@"fn".params;
            const result = if (params.len == 3)
                a.__gt__(allocator, b)
            else
                a.__gt__(b);

            const ResultType = @TypeOf(result);
            if (@typeInfo(ResultType) == .error_union) {
                // Result is error union - unwrap and check payload type
                const payload = result catch return false;
                const PayloadType = @TypeOf(payload);
                if (PayloadType == bool) {
                    return payload;
                } else {
                    // Payload is a class instance (like *SymbolicBool) - call __bool__
                    return toBoolFromResult(payload);
                }
            } else if (ResultType == bool) {
                return result;
            } else {
                return toBoolFromResult(result);
            }
        }
    } else if (type_info == .pointer and @typeInfo(type_info.pointer.child) == .@"struct") {
        const ChildType = type_info.pointer.child;
        if (@hasDecl(ChildType, "__gt__")) {
            const gt_info = @typeInfo(@TypeOf(ChildType.__gt__));
            if (gt_info == .@"fn") {
                const params = gt_info.@"fn".params;
                const result = if (params.len == 3)
                    a.__gt__(allocator, b)
                else
                    a.__gt__(b);

                const ResultType = @TypeOf(result);
                if (@typeInfo(ResultType) == .error_union) {
                    // Result is error union - unwrap and check payload type
                    const payload = result catch return false;
                    const PayloadType = @TypeOf(payload);
                    if (PayloadType == bool) {
                        return payload;
                    } else {
                        // Payload is a class instance (like *SymbolicBool) - call __bool__
                        return toBoolFromResult(payload);
                    }
                } else if (ResultType == bool) {
                    return result;
                } else {
                    return toBoolFromResult(result);
                }
            }
        }
    }
    return false;
}

/// Class instance greater-than-or-equal comparison
pub fn classInstanceGe(a: anytype, b: anytype, allocator: std.mem.Allocator) bool {
    const TypeA = @TypeOf(a);
    const type_info = @typeInfo(TypeA);

    if (type_info == .@"struct" and @hasDecl(TypeA, "__ge__")) {
        const ge_info = @typeInfo(@TypeOf(TypeA.__ge__));
        if (ge_info == .@"fn") {
            const params = ge_info.@"fn".params;
            const result = if (params.len == 3)
                a.__ge__(allocator, b)
            else
                a.__ge__(b);

            const ResultType = @TypeOf(result);
            if (@typeInfo(ResultType) == .error_union) {
                const payload = result catch return false;
                const PayloadType = @TypeOf(payload);
                if (PayloadType == bool) {
                    return payload;
                } else {
                    return toBoolFromResult(payload);
                }
            } else if (ResultType == bool) {
                return result;
            } else {
                return toBoolFromResult(result);
            }
        }
    } else if (type_info == .pointer and @typeInfo(type_info.pointer.child) == .@"struct") {
        const ChildType = type_info.pointer.child;
        if (@hasDecl(ChildType, "__ge__")) {
            const ge_info = @typeInfo(@TypeOf(ChildType.__ge__));
            if (ge_info == .@"fn") {
                const params = ge_info.@"fn".params;
                const result = if (params.len == 3)
                    a.__ge__(allocator, b)
                else
                    a.__ge__(b);

                const ResultType = @TypeOf(result);
                if (@typeInfo(ResultType) == .error_union) {
                    const payload = result catch return false;
                    const PayloadType = @TypeOf(payload);
                    if (PayloadType == bool) {
                        return payload;
                    } else {
                        return toBoolFromResult(payload);
                    }
                } else if (ResultType == bool) {
                    return result;
                } else {
                    return toBoolFromResult(result);
                }
            }
        }
    }
    // Fallback: a >= b is a > b or a == b
    return classInstanceGt(a, b, allocator) or classInstanceEq(a, b, allocator);
}

/// Helper to convert comparison result to bool (handles SymbolicBool with __bool__)
fn toBoolFromResult(result: anytype) bool {
    const ResultType = @TypeOf(result);
    const result_info = @typeInfo(ResultType);

    // Handle pointer to struct (like *SymbolicBool)
    if (result_info == .pointer and result_info.pointer.size == .one) {
        const ChildType = result_info.pointer.child;
        if (@typeInfo(ChildType) == .@"struct" and @hasDecl(ChildType, "__bool__")) {
            const bool_result = result.__bool__();
            const BoolResultType = @TypeOf(bool_result);
            if (@typeInfo(BoolResultType) == .error_union) {
                // __bool__ raised an error (like TypeError) - propagate as false
                // In assertRaises context, this would be caught
                return bool_result catch false;
            } else {
                return bool_result;
            }
        }
    }
    // Handle struct directly
    if (result_info == .@"struct" and @hasDecl(ResultType, "__bool__")) {
        const bool_result = result.__bool__();
        const BoolResultType = @TypeOf(bool_result);
        if (@typeInfo(BoolResultType) == .error_union) {
            return bool_result catch false;
        } else {
            return bool_result;
        }
    }
    // Can't convert - return false
    return false;
}

/// Generic assertEqual helper - delegates to centralized equality module
pub fn assertEqualGeneric(a: anytype, b: anytype, allocator: std.mem.Allocator) !bool {
    // Use the centralized pyAnyEql from equality.zig for most cases
    const equality = @import("../equality.zig");

    // Try the non-allocator equality first (handles structs, tuples, numerics, etc.)
    if (equality.pyAnyEql(a, b)) return true;

    // Fall back to allocator-dependent pyEqual only for special cases
    // (PyValue conversion, BigInt, etc.)
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
        // Check for BigInt (struct with managed field containing std.math.big.int.Managed)
        // This is more specific than checking for eql method since other types may have eql
        if (info_a == .@"struct" and @hasField(TypeA, "managed")) {
            // BigInt has a managed field and eql method
            if (@hasDecl(TypeA, "eql")) {
                return a.eql(&b);
            }
        }
    }

    // Cross-type integer comparison (e.g., i64 vs comptime_int)
    if ((info_a == .int or info_a == .comptime_int) and (info_b == .int or info_b == .comptime_int)) {
        return a == b;
    }

    // Cross-type BigInt comparison (BigInt vs int)
    // BigInt is identified by having a 'managed' field
    const a_is_bigint = info_a == .@"struct" and @hasField(TypeA, "managed");
    const b_is_bigint = info_b == .@"struct" and @hasField(TypeB, "managed");
    const a_is_int = info_a == .int or info_a == .comptime_int;
    const b_is_int = info_b == .int or info_b == .comptime_int;

    if (a_is_bigint and b_is_int) {
        // Compare BigInt a with int b using eqlInt method
        if (@hasDecl(TypeA, "eqlInt")) {
            return a.eqlInt(@as(i64, @intCast(b)));
        }
        // Fallback: try toInt64 comparison
        if (@hasDecl(TypeA, "toInt64")) {
            if (a.toInt64()) |a_i64| {
                return a_i64 == b;
            }
        }
        return false;
    }
    if (b_is_bigint and a_is_int) {
        // Compare int a with BigInt b using eqlInt method
        if (@hasDecl(TypeB, "eqlInt")) {
            return b.eqlInt(@as(i64, @intCast(a)));
        }
        // Fallback: try toInt64 comparison
        if (@hasDecl(TypeB, "toInt64")) {
            if (b.toInt64()) |b_i64| {
                return a == b_i64;
            }
        }
        return false;
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
