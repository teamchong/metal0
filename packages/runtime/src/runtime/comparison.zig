/// Unified Comparison Utility - THE ONE SOURCE OF TRUTH for all comparisons
///
/// This module centralizes ALL comparison logic in metal0:
/// - Python rich comparison protocol (__lt__, __le__, __eq__, __ne__, __gt__, __ge__)
/// - NotImplemented handling and reflected operations
/// - Vtable dispatch for PyValue.object instances
/// - Fast paths for concrete types (i64, f64, string, bool)
/// - Generic anytype fallback with comptime type introspection
///
/// Architecture:
/// 1. Fast paths: Dispatch to comparison_ops.zig for common concrete types
/// 2. PyValue: Use PyValue methods which use vtable for .object
/// 3. Class instances: Use @hasDecl for comptime dispatch to dunder methods
/// 4. Fallback: Use native Zig operators
///
/// Python Rich Comparison Protocol:
/// For each operator op (lt, le, eq, ne, gt, ge):
/// 1. Try a.__op__(b) - if returns non-NotImplemented, use it
/// 2. Try b.__rop__(a) - reflected operation, if returns non-NotImplemented, use it
/// 3. Fall back to defaults (identity for eq/ne, TypeError for ordering)

const std = @import("std");
const PyValue = @import("../Objects/object.zig").PyValue;
const comparison_ops = @import("comparison_ops.zig");

// =============================================================================
// Public API - Universal comparison functions
// =============================================================================

/// Universal equality: a == b
/// Handles all types with Python semantics
pub fn equal(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);

    // Fast paths for common concrete types
    if (T == i64) return comparison_ops.eqI64(a, b);
    if (T == f64) return comparison_ops.eqF64(a, b);
    if (T == bool) return comparison_ops.eqBool(a, b);
    if (T == []const u8) return comparison_ops.eqStr(a, b);
    if (T == PyValue) return comparison_ops.eqPyValue(a, b);

    // Python rich comparison protocol for class instances
    // Note: Only handle *Struct, not *!Struct (error union pointers are codegen bugs)
    if (@typeInfo(T) == .pointer) {
        const Child = @typeInfo(T).pointer.child;
        if (@typeInfo(Child) == .@"struct") {
            return equalClassInstance(a, b);
        }
    }

    // Fallback: native Zig equality (identity for pointers)
    return a == b;
}

/// Universal inequality: a != b
pub fn notEqual(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);

    // Fast paths
    if (T == i64) return comparison_ops.neI64(a, b);
    if (T == f64) return comparison_ops.neF64(a, b);
    if (T == bool) return comparison_ops.neBool(a, b);
    if (T == []const u8) return comparison_ops.neStr(a, b);
    if (T == PyValue) return comparison_ops.nePyValue(a, b);

    // Python rich comparison protocol for class instances
    // Note: Only handle *Struct, not *!Struct (error union pointers are codegen bugs)
    if (@typeInfo(T) == .pointer) {
        const Child = @typeInfo(T).pointer.child;
        if (@typeInfo(Child) == .@"struct") {
            return notEqualClassInstance(a, b);
        }
    }

    // Fallback: identity comparison
    return a != b;
}

/// Universal less than: a < b
pub fn lessThan(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);

    // Fast paths
    if (T == i64) return comparison_ops.ltI64(a, b);
    if (T == f64) return comparison_ops.ltF64(a, b);
    if (T == []const u8) return comparison_ops.ltStr(a, b);
    if (T == PyValue) return comparison_ops.ltPyValue(a, b);

    // Python rich comparison protocol for class instances
    // Note: Only handle *Struct, not *!Struct (error union pointers are codegen bugs)
    if (@typeInfo(T) == .pointer) {
        const Child = @typeInfo(T).pointer.child;
        if (@typeInfo(Child) == .@"struct") {
            return lessThanClassInstance(a, b);
        }
    }

    // Fallback: For incomparable types, Python raises TypeError. We return false.
    // Don't try native Zig operators on arbitrary types as they may not be comparable.
    return false;
}

/// Universal less than or equal: a <= b
pub fn lessThanOrEqual(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);

    // Fast paths
    if (T == i64) return comparison_ops.leI64(a, b);
    if (T == f64) return comparison_ops.leF64(a, b);
    if (T == []const u8) return comparison_ops.leStr(a, b);
    if (T == PyValue) return comparison_ops.lePyValue(a, b);

    // Python rich comparison protocol for class instances
    // Note: Only handle *Struct, not *!Struct (error union pointers are codegen bugs)
    if (@typeInfo(T) == .pointer) {
        const Child = @typeInfo(T).pointer.child;
        if (@typeInfo(Child) == .@"struct") {
            return lessThanOrEqualClassInstance(a, b);
        }
    }

    // Fallback: For incomparable types, return false
    return false;
}

/// Universal greater than: a > b
pub fn greaterThan(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);

    // Fast paths
    if (T == i64) return comparison_ops.gtI64(a, b);
    if (T == f64) return comparison_ops.gtF64(a, b);
    if (T == []const u8) return comparison_ops.gtStr(a, b);
    if (T == PyValue) return comparison_ops.gtPyValue(a, b);

    // Python rich comparison protocol for class instances
    // Note: Only handle *Struct, not *!Struct (error union pointers are codegen bugs)
    if (@typeInfo(T) == .pointer) {
        const Child = @typeInfo(T).pointer.child;
        if (@typeInfo(Child) == .@"struct") {
            return greaterThanClassInstance(a, b);
        }
    }

    // Fallback: For incomparable types, return false
    return false;
}

/// Universal greater than or equal: a >= b
pub fn greaterThanOrEqual(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);

    // Fast paths
    if (T == i64) return comparison_ops.geI64(a, b);
    if (T == f64) return comparison_ops.geF64(a, b);
    if (T == []const u8) return comparison_ops.geStr(a, b);
    if (T == PyValue) return comparison_ops.gePyValue(a, b);

    // Python rich comparison protocol for class instances
    // Note: Only handle *Struct, not *!Struct (error union pointers are codegen bugs)
    if (@typeInfo(T) == .pointer) {
        const Child = @typeInfo(T).pointer.child;
        if (@typeInfo(Child) == .@"struct") {
            return greaterThanOrEqualClassInstance(a, b);
        }
    }

    // Fallback: For incomparable types, return false
    return false;
}

// =============================================================================
// Python Rich Comparison Protocol - Class Instance Implementation
// =============================================================================

/// Helper to extract the actual struct type from pointer-to-struct or pointer-to-error-union-of-struct
fn getStructType(comptime T: type) type {
    const ptr_info = @typeInfo(T).pointer;
    const Child = ptr_info.child;
    const child_info = @typeInfo(Child);

    if (child_info == .@"struct") {
        return Child;
    } else if (child_info == .error_union) {
        const Payload = child_info.error_union.payload;
        if (@typeInfo(Payload) == .@"struct") {
            return Payload;
        }
    }

    @compileError("getStructType: expected pointer to struct or error union of struct");
}

/// Equality for class instances: Try __eq__, then __ne__ (inverted), then identity
fn equalClassInstance(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);
    const StructType = getStructType(T);

    // Try a.__eq__(b)
    if (@hasDecl(StructType, "__eq__")) {
        const a_result = a.__eq__(b);
        const a_result_type = @TypeOf(a_result);
        if (a_result_type == PyValue) {
            if (a_result != .not_implemented) {
                return if (a_result == .bool) a_result.bool else !PyValue.isFalsy(a_result);
            }
        } else if (a_result_type == bool) {
            return a_result;
        }
    }

    // Try b.__eq__(a) (no reflected __req__ in Python)
    if (@hasDecl(StructType, "__eq__")) {
        const b_result = b.__eq__(a);
        const b_result_type = @TypeOf(b_result);
        if (b_result_type == PyValue) {
            if (b_result != .not_implemented) {
                return if (b_result == .bool) b_result.bool else !PyValue.isFalsy(b_result);
            }
        } else if (b_result_type == bool) {
            return b_result;
        }
    }

    // Fall back to identity comparison
    return a == b;
}

/// Inequality for class instances: Try __ne__, then invert __eq__, then identity
fn notEqualClassInstance(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);
    const StructType = getStructType(T);

    // Try a.__ne__(b)
    if (@hasDecl(StructType, "__ne__")) {
        const a_result = a.__ne__(b);
        const a_result_type = @TypeOf(a_result);
        if (a_result_type == PyValue) {
            if (a_result != .not_implemented) {
                return if (a_result == .bool) a_result.bool else !PyValue.isFalsy(a_result);
            }
        } else if (a_result_type == bool) {
            return a_result;
        }
    }

    // Try b.__ne__(a)
    if (@hasDecl(StructType, "__ne__")) {
        const b_result = b.__ne__(a);
        const b_result_type = @TypeOf(b_result);
        if (b_result_type == PyValue) {
            if (b_result != .not_implemented) {
                return if (b_result == .bool) b_result.bool else !PyValue.isFalsy(b_result);
            }
        } else if (b_result_type == bool) {
            return b_result;
        }
    }

    // Fall back to inverted equality
    return !equalClassInstance(a, b);
}

/// Less than for class instances: Try __lt__, then reflected __gt__, then false
fn lessThanClassInstance(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);
    const StructType = getStructType(T);

    // Try a.__lt__(b)
    if (@hasDecl(StructType, "__lt__")) {
        const a_result = a.__lt__(b);
        const a_result_type = @TypeOf(a_result);
        if (a_result_type == PyValue) {
            if (a_result != .not_implemented) {
                return if (a_result == .bool) a_result.bool else !PyValue.isFalsy(a_result);
            }
        } else if (a_result_type == bool) {
            return a_result;
        }
    }

    // Try b.__gt__(a) (reflected operation)
    if (@hasDecl(StructType, "__gt__")) {
        const b_result = b.__gt__(a);
        const b_result_type = @TypeOf(b_result);
        if (b_result_type == PyValue) {
            if (b_result != .not_implemented) {
                return if (b_result == .bool) b_result.bool else !PyValue.isFalsy(b_result);
            }
        } else if (b_result_type == bool) {
            return b_result;
        }
    }

    // No comparison methods available - return false (Python raises TypeError)
    return false;
}

/// Less than or equal for class instances: Try __le__, then reflected __ge__, then __lt__ or __eq__
fn lessThanOrEqualClassInstance(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);
    const StructType = getStructType(T);

    // Try a.__le__(b)
    if (@hasDecl(StructType, "__le__")) {
        const a_result = a.__le__(b);
        const a_result_type = @TypeOf(a_result);
        if (a_result_type == PyValue) {
            if (a_result != .not_implemented) {
                return if (a_result == .bool) a_result.bool else !PyValue.isFalsy(a_result);
            }
        } else if (a_result_type == bool) {
            return a_result;
        }
    }

    // Try b.__ge__(a) (reflected operation)
    if (@hasDecl(StructType, "__ge__")) {
        const b_result = b.__ge__(a);
        const b_result_type = @TypeOf(b_result);
        if (b_result_type == PyValue) {
            if (b_result != .not_implemented) {
                return if (b_result == .bool) b_result.bool else !PyValue.isFalsy(b_result);
            }
        } else if (b_result_type == bool) {
            return b_result;
        }
    }

    // Fallback: __lt__ or __eq__
    return lessThanClassInstance(a, b) or equalClassInstance(a, b);
}

/// Greater than for class instances: Try __gt__, then reflected __lt__, then false
fn greaterThanClassInstance(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);
    const StructType = getStructType(T);

    // Try a.__gt__(b)
    if (@hasDecl(StructType, "__gt__")) {
        const a_result = a.__gt__(b);
        const a_result_type = @TypeOf(a_result);
        if (a_result_type == PyValue) {
            if (a_result != .not_implemented) {
                return if (a_result == .bool) a_result.bool else !PyValue.isFalsy(a_result);
            }
        } else if (a_result_type == bool) {
            return a_result;
        }
    }

    // Try b.__lt__(a) (reflected operation)
    if (@hasDecl(StructType, "__lt__")) {
        const b_result = b.__lt__(a);
        const b_result_type = @TypeOf(b_result);
        if (b_result_type == PyValue) {
            if (b_result != .not_implemented) {
                return if (b_result == .bool) b_result.bool else !PyValue.isFalsy(b_result);
            }
        } else if (b_result_type == bool) {
            return b_result;
        }
    }

    // No comparison methods available
    return false;
}

/// Greater than or equal for class instances: Try __ge__, then reflected __le__, then __gt__ or __eq__
fn greaterThanOrEqualClassInstance(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);
    const StructType = getStructType(T);

    // Try a.__ge__(b)
    if (@hasDecl(StructType, "__ge__")) {
        const a_result = a.__ge__(b);
        const a_result_type = @TypeOf(a_result);
        if (a_result_type == PyValue) {
            if (a_result != .not_implemented) {
                return if (a_result == .bool) a_result.bool else !PyValue.isFalsy(a_result);
            }
        } else if (a_result_type == bool) {
            return a_result;
        }
    }

    // Try b.__le__(a) (reflected operation)
    if (@hasDecl(StructType, "__le__")) {
        const b_result = b.__le__(a);
        const b_result_type = @TypeOf(b_result);
        if (b_result_type == PyValue) {
            if (b_result != .not_implemented) {
                return if (b_result == .bool) b_result.bool else !PyValue.isFalsy(b_result);
            }
        } else if (b_result_type == bool) {
            return b_result;
        }
    }

    // Fallback: __gt__ or __eq__
    return greaterThanClassInstance(a, b) or equalClassInstance(a, b);
}

// =============================================================================
// Tests
// =============================================================================

test "unified comparison - primitives" {
    try std.testing.expect(equal(@as(i64, 42), @as(i64, 42)));
    try std.testing.expect(!equal(@as(i64, 42), @as(i64, 43)));
    try std.testing.expect(notEqual(@as(i64, 42), @as(i64, 43)));
    try std.testing.expect(lessThan(@as(i64, 1), @as(i64, 2)));
    try std.testing.expect(lessThanOrEqual(@as(i64, 1), @as(i64, 1)));
    try std.testing.expect(greaterThan(@as(i64, 2), @as(i64, 1)));
    try std.testing.expect(greaterThanOrEqual(@as(i64, 1), @as(i64, 1)));
}

test "unified comparison - strings" {
    try std.testing.expect(equal("hello", "hello"));
    try std.testing.expect(!equal("hello", "world"));
    try std.testing.expect(lessThan("abc", "abd"));
    try std.testing.expect(greaterThan("z", "a"));
}
