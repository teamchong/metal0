/// Operator comparison functions (eq, ne, lt, le, gt, ge, pyEqual)
///
/// IMPORTANT: This file uses PyValue-First Architecture to prevent monomorphization explosion.
/// All complex type handling is delegated to PyValue.eql() which compiles ONCE.
/// See CLAUDE.md "anytype Guidelines" for rules.
///
/// Architecture:
/// - Same-type comparisons: Delegate to unified comparison utility (comparison.zig)
/// - Cross-type comparisons: Convert to PyValue and compare
const std = @import("std");
const PyValue = @import("../../Objects/object.zig").PyValue;
const comparison = @import("../comparison.zig");

// =============================================================================
// CONCRETE PyValue COMPARISONS (compile ONCE, not per call site)
// =============================================================================

/// PyValue equality - compiles once
pub fn pyEqualPyValue(a: PyValue, b: PyValue) bool {
    return a.eql(b);
}

/// PyValue less-than - compiles once
pub fn pyLtPyValue(a: PyValue, b: PyValue) bool {
    return a.lt(b);
}

/// PyValue less-than-or-equal - compiles once
pub fn pyLePyValue(a: PyValue, b: PyValue) bool {
    return a.le(b);
}

/// PyValue greater-than - compiles once
pub fn pyGtPyValue(a: PyValue, b: PyValue) bool {
    return a.gt(b);
}

/// PyValue greater-than-or-equal - compiles once
pub fn pyGePyValue(a: PyValue, b: PyValue) bool {
    return a.ge(b);
}

// =============================================================================
// OPERATOR COMPARISONS (dispatch to concrete functions)
// =============================================================================

/// operator.eq - equality comparison
/// Two-Flow: Handles PyValue for uncertain types
pub fn operatorEq(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    // Same-type comparison: Delegate to unified comparison utility
    if (TypeA == TypeB) {
        return comparison.equal(a, b);
    }

    // Cross-type comparison: Convert to PyValue
    const a_pv = PyValue.from(a);
    const b_pv = PyValue.from(b);
    return pyEqualPyValue(a_pv, b_pv);
}

/// operator.ne - inequality comparison
pub fn operatorNe(a: anytype, b: anytype) bool {
    return !operatorEq(a, b);
}

/// operator.lt - less than comparison
pub fn operatorLt(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    // Same-type comparison: Delegate to unified comparison utility
    if (TypeA == TypeB) {
        return comparison.lessThan(a, b);
    }

    // Cross-type comparison: Convert to PyValue
    const a_pv = PyValue.from(a);
    const b_pv = PyValue.from(b);
    return pyLtPyValue(a_pv, b_pv);
}

/// operator.le - less than or equal comparison
pub fn operatorLe(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    // Same-type comparison: Delegate to unified comparison utility
    if (TypeA == TypeB) {
        return comparison.lessThanOrEqual(a, b);
    }

    // Cross-type comparison: Convert to PyValue
    const a_pv = PyValue.from(a);
    const b_pv = PyValue.from(b);
    return pyLePyValue(a_pv, b_pv);
}

/// operator.gt - greater than comparison
pub fn operatorGt(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    // Same-type comparison: Delegate to unified comparison utility
    if (TypeA == TypeB) {
        return comparison.greaterThan(a, b);
    }

    // Cross-type comparison: Convert to PyValue
    const a_pv = PyValue.from(a);
    const b_pv = PyValue.from(b);
    return pyGtPyValue(a_pv, b_pv);
}

/// operator.ge - greater than or equal comparison
pub fn operatorGe(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    // Same-type comparison: Delegate to unified comparison utility
    if (TypeA == TypeB) {
        return comparison.greaterThanOrEqual(a, b);
    }

    // Cross-type comparison: Convert to PyValue
    const a_pv = PyValue.from(a);
    const b_pv = PyValue.from(b);
    return pyGePyValue(a_pv, b_pv);
}

// =============================================================================
// CLASS INSTANCE COMPARISONS (for dunder methods)
// These need anytype to access __eq__, __lt__, etc. methods
// =============================================================================

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

// =============================================================================
// PYEQUAL - Simplified to avoid monomorphization explosion
// NO MORE recursive inline for loops!
// =============================================================================

/// Generic assertEqual helper - delegates to centralized equality module
pub fn assertEqualGeneric(a: anytype, b: anytype, allocator: std.mem.Allocator) !bool {
    // Use the centralized pyValueCompare from equality.zig for most cases
    const equality = @import("../equality.zig");

    // Try the non-allocator equality first (handles structs, tuples, numerics, etc.)
    if (equality.pyValueCompare(a, b)) return true;

    // Fall back to allocator-dependent pyEqual only for special cases
    // (PyValue conversion, BigInt, etc.)
    return pyEqual(allocator, a, b);
}

/// Universal Python-semantic equality comparison
/// SIMPLIFIED: No more recursive inline for loops. Complex types convert to PyValue.
pub fn pyEqual(allocator: std.mem.Allocator, a: anytype, b: anytype) !bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    // Fast path: PyValue (already converted)
    if (TypeA == PyValue and TypeB == PyValue) {
        return pyEqualPyValue(a, b);
    }

    // Fast path: same primitive types
    if (TypeA == TypeB) {
        if (TypeA == i64) return a == b;
        if (TypeA == f64) return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
        if (TypeA == f32) return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
        if (TypeA == bool) return a == b;
        if (TypeA == []const u8) return std.mem.eql(u8, a, b);
    }

    // Fast path: cross-type integers
    const info_a = @typeInfo(TypeA);
    const info_b = @typeInfo(TypeB);
    if ((info_a == .int or info_a == .comptime_int) and (info_b == .int or info_b == .comptime_int)) {
        return a == b;
    }

    // Fast path: BigInt (identified by 'managed' field)
    const a_is_bigint = info_a == .@"struct" and @hasField(TypeA, "managed");
    const b_is_bigint = info_b == .@"struct" and @hasField(TypeB, "managed");
    const a_is_int = info_a == .int or info_a == .comptime_int;
    const b_is_int = info_b == .int or info_b == .comptime_int;

    if (a_is_bigint and b_is_int) {
        if (@hasDecl(TypeA, "eqlInt")) {
            return a.eqlInt(@as(i64, @intCast(b)));
        }
        return false;
    }
    if (b_is_bigint and a_is_int) {
        if (@hasDecl(TypeB, "eqlInt")) {
            return b.eqlInt(@as(i64, @intCast(a)));
        }
        return false;
    }
    if (a_is_bigint and b_is_bigint) {
        if (@hasDecl(TypeA, "eql")) {
            return a.eql(&b);
        }
        return false;
    }

    // Fast path: class instance with __eq__
    const a_has_eq = info_a == .@"struct" and @hasDecl(TypeA, "__eq__");
    const b_has_eq = info_b == .@"struct" and @hasDecl(TypeB, "__eq__");
    if (a_has_eq) return classInstanceEq(a, b, allocator);
    if (b_has_eq) return classInstanceEq(b, a, allocator);

    // FALLBACK: Convert both to PyValue and let PyValue.eql() handle complexity
    // This avoids recursive inline for loops that cause monomorphization explosion
    const object = @import("../../Objects/object.zig");
    const a_val = try object.toPyValue(allocator, a);
    const b_val = try object.toPyValue(allocator, b);
    return pyEqualPyValue(a_val, b_val);
}

/// Helper to compare slice to tuple - simplified version
pub fn pyEqualSliceToTuple(allocator: std.mem.Allocator, slice: anytype, tup: anytype) !bool {
    // Convert both to PyValue and compare
    const object = @import("../../Objects/object.zig");
    const slice_val = try object.toPyValue(allocator, slice);
    const tup_val = try object.toPyValue(allocator, tup);
    return pyEqualPyValue(slice_val, tup_val);
}
