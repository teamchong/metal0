/// Python-style equality operations
/// Handles NaN identity semantics, container comparison, etc.
/// Extracted from runtime.zig to reduce file size
const std = @import("std");

const object_zig = @import("../Objects/object.zig");
const PyValue = object_zig.PyValue;
const pylist = @import("../Objects/listobject.zig");
const NativeList = pylist.NativeList;
const cpython = @import("../cpython.zig");
const CpythonPyObject = cpython.PyObject;
const bigint = @import("bigint");
const BigInt = bigint.BigInt;

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
/// SIMPLIFIED: Uses PyValue conversion for complex types to avoid monomorphization explosion
pub fn pyTupleEql(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);
    const info = @typeInfo(T);

    // Handle arrays - iterate without recursion
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
        // Non-float arrays - use standard comparison
        return std.mem.eql(ElemT, &a, &b);
    }

    // Handle structs (tuples) - check for __eq__ method first
    if (info == .@"struct") {
        // Class instances with __eq__ - call it directly
        if (@hasDecl(T, "__eq__")) {
            return a.__eq__(b);
        }
        // Regular structs/tuples - convert to PyValue to avoid recursive inline for
        // This prevents monomorphization explosion for complex nested types
        const a_pv = PyValue.from(a);
        const b_pv = PyValue.from(b);
        return pyValueEql(a_pv, b_pv);
    }

    // Fallback: use PyValue conversion
    const a_pv = PyValue.from(a);
    const b_pv = PyValue.from(b);
    return pyValueEql(a_pv, b_pv);
}

// =============================================================================
// PyValue-Only Equality Functions (NO MONOMORPHIZATION)
// =============================================================================
// These functions compile ONCE regardless of how many call sites exist.
// Use these for uncertain types where compile time is critical.

/// Typed fast path: integer equality (single copy)
pub fn intEql(a: i64, b: i64) bool {
    return a == b;
}

/// Typed fast path: float equality with bit-level NaN identity (single copy)
pub fn floatEql(a: f64, b: f64) bool {
    return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
}

/// Typed fast path: string equality (single copy)
pub fn stringEql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Typed fast path: boolean equality (single copy)
pub fn boolEql(a: bool, b: bool) bool {
    return a == b;
}

/// PyValue-only equality - compiles ONCE, handles all types at runtime
/// Use this for uncertain types to avoid monomorphization explosion
/// Handles Python cross-type numeric equality: complex(0) == 0 == 0.0 == False
pub fn pyValueEql(a: PyValue, b: PyValue) bool {
    const a_tag = @as(std.meta.Tag(PyValue), a);
    const b_tag = @as(std.meta.Tag(PyValue), b);

    // Same type: direct comparison
    if (a_tag == b_tag) {
        return switch (a) {
            .int => |ai| ai == b.int,
            .float => |af| @as(u64, @bitCast(af)) == @as(u64, @bitCast(b.float)),
            .string => |as| std.mem.eql(u8, as, b.string),
            .bool => |ab| ab == b.bool,
            .none => true,
            .tuple => |at| pyValueTupleEql(at, b.tuple),
            .list => |al| pyValueListEql(al.items, b.list.items),
            .complex => |ac| ac.real == b.complex.real and ac.imag == b.complex.imag,
            .bigint => |ab| ab.eql(&b.bigint),
            else => false, // Other types (ptr, object, etc.) not yet supported
        };
    }

    // Different types: handle Python numeric cross-type equality
    // In Python: complex(0) == 0 == 0.0 == False (all True)
    return switch (a) {
        .complex => |ac| switch (b) {
            // complex(0j) == 0 (int)
            .int => |bi| ac.imag == 0.0 and ac.real == @as(f64, @floatFromInt(bi)),
            // complex(0j) == 0.0 (float)
            .float => |bf| ac.imag == 0.0 and ac.real == bf,
            // complex(0j) == False (bool)
            .bool => |bb| ac.imag == 0.0 and ac.real == @as(f64, if (bb) 1.0 else 0.0),
            else => false,
        },
        .int => |ai| switch (b) {
            .complex => |bc| bc.imag == 0.0 and @as(f64, @floatFromInt(ai)) == bc.real,
            .float => |bf| @as(f64, @floatFromInt(ai)) == bf,
            .bool => |bb| ai == @as(i64, if (bb) 1 else 0),
            .bigint => |bb| blk: {
                // Compare i64 with BigInt: use BigInt's comparison
                const ai_big = BigInt.fromInt(std.heap.page_allocator, ai) catch return false;
                break :blk ai_big.eql(&bb);
            },
            else => false,
        },
        .float => |af| switch (b) {
            .complex => |bc| bc.imag == 0.0 and af == bc.real,
            .int => |bi| af == @as(f64, @floatFromInt(bi)),
            .bool => |bb| af == @as(f64, if (bb) 1.0 else 0.0),
            .bigint => |bb| blk: {
                // Compare float with BigInt: convert BigInt to float (may lose precision)
                // This matches Python semantics where large ints compare with floats
                const bf = bb.toFloat();
                break :blk af == bf;
            },
            else => false,
        },
        .bool => |ab| switch (b) {
            .complex => |bc| bc.imag == 0.0 and bc.real == @as(f64, if (ab) 1.0 else 0.0),
            .int => |bi| @as(i64, if (ab) 1 else 0) == bi,
            .float => |bf| @as(f64, if (ab) 1.0 else 0.0) == bf,
            else => false,
        },
        .bigint => |ab| switch (b) {
            .float => |bf| blk: {
                // Compare BigInt with float: convert BigInt to float (may lose precision)
                // This matches Python semantics where large ints compare with floats
                const af = ab.toFloat();
                break :blk af == bf;
            },
            .int => |bi| blk: {
                // Compare BigInt with i64: use BigInt's comparison
                const bi_big = BigInt.fromInt(std.heap.page_allocator, bi) catch return false;
                break :blk ab.eql(&bi_big);
            },
            .bool => |bb| blk: {
                // Compare BigInt with bool: 0 == False, 1 == True
                const bi = if (bb) @as(i64, 1) else @as(i64, 0);
                const bi_big = BigInt.fromInt(std.heap.page_allocator, bi) catch return false;
                break :blk ab.eql(&bi_big);
            },
            else => false,
        },
        else => false,
    };
}

/// PyValue tuple equality helper
fn pyValueTupleEql(a: []const PyValue, b: []const PyValue) bool {
    if (a.len != b.len) return false;
    for (a, b) |ai, bi| {
        if (!pyValueEql(ai, bi)) return false;
    }
    return true;
}

/// PyValue list equality helper
fn pyValueListEql(a: []const PyValue, b: []const PyValue) bool {
    if (a.len != b.len) return false;
    for (a, b) |ai, bi| {
        if (!pyValueEql(ai, bi)) return false;
    }
    return true;
}

// =============================================================================
// PyValue-First Comparison Operators (compile ONCE - no monomorphization)
// =============================================================================

/// PyValue less-than comparison - compiles ONCE
pub fn pyValueLt(a: PyValue, b: PyValue) bool {
    return switch (a) {
        .int => |ai| switch (b) {
            .int => |bi| ai < bi,
            .float => |bf| @as(f64, @floatFromInt(ai)) < bf,
            else => false,
        },
        .float => |af| switch (b) {
            .int => |bi| af < @as(f64, @floatFromInt(bi)),
            .float => |bf| af < bf,
            else => false,
        },
        .string => |as| switch (b) {
            .string => |bs| std.mem.order(u8, as, bs) == .lt,
            else => false,
        },
        .bool => |ab| switch (b) {
            .bool => |bb| !ab and bb, // false < true
            else => false,
        },
        .tuple => |at| switch (b) {
            .tuple => |bt| pyValueTupleLt(at, bt),
            else => false,
        },
        .list => |al| switch (b) {
            .list => |bl| pyValueTupleLt(al.items, bl.items),
            else => false,
        },
        else => false,
    };
}

/// PyValue less-than-or-equal comparison - compiles ONCE
pub fn pyValueLe(a: PyValue, b: PyValue) bool {
    return pyValueLt(a, b) or pyValueEql(a, b);
}

/// PyValue greater-than comparison - compiles ONCE
pub fn pyValueGt(a: PyValue, b: PyValue) bool {
    return pyValueLt(b, a);
}

/// PyValue greater-than-or-equal comparison - compiles ONCE
pub fn pyValueGe(a: PyValue, b: PyValue) bool {
    return pyValueLe(b, a);
}

/// PyValue not-equal comparison - compiles ONCE
pub fn pyValueNe(a: PyValue, b: PyValue) bool {
    return !pyValueEql(a, b);
}

/// PyValue tuple/list lexicographic less-than helper
fn pyValueTupleLt(a: []const PyValue, b: []const PyValue) bool {
    const min_len = @min(a.len, b.len);
    for (0..min_len) |i| {
        if (pyValueLt(a[i], b[i])) return true;
        if (pyValueLt(b[i], a[i])) return false;
    }
    // Equal prefix - shorter is less
    return a.len < b.len;
}

// =============================================================================
// Anytype Equality Functions (MONOMORPHIZES - use sparingly)
// =============================================================================

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
        // Special case: UnifiedInt - use eqlSimple which doesn't need allocator
        if (A == @import("../Objects/pyint.zig").UnifiedInt) {
            return a.eqlSimple(b);
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
        // Special case: structs (tuples) - check for __eq__ method first
        if (a_info == .@"struct") {
            // Class instances with __eq__ - call it directly and handle result type
            if (@hasDecl(A, "__eq__")) {
                const result = a.__eq__(b);
                const ResultType = @TypeOf(result);
                if (ResultType == PyValue) {
                    if (result == .not_implemented) {
                        // Fallback to identity comparison
                        return &a == &b;
                    }
                    return if (result == .bool) result.bool else !PyValue.isFalsy(result);
                } else if (ResultType == bool) {
                    return result;
                }
            }
            // Regular structs/tuples - use PyValue conversion to avoid recursive inline for
            // This prevents monomorphization explosion for complex nested types
            const a_pv = PyValue.from(a);
            const b_pv = PyValue.from(b);
            return pyValueEql(a_pv, b_pv);
        }
        return std.meta.eql(a, b);
    }

    // Different types: handle common cases without recursion

    // Class instances with __eq__ - call it for cross-type comparison (e.g., Rat == int)
    // Handle both PyValue and bool return types for backward compatibility
    if (a_info == .@"struct" and @hasDecl(A, "__eq__")) {
        const result = a.__eq__(b);
        const ResultType = @TypeOf(result);
        if (ResultType == PyValue) {
            if (result == .not_implemented) {
                // Try b.__eq__(a)
                if (b_info == .@"struct" and @hasDecl(B, "__eq__")) {
                    const b_result = b.__eq__(a);
                    if (@TypeOf(b_result) == PyValue) {
                        if (b_result != .not_implemented) {
                            return if (b_result == .bool) b_result.bool else !PyValue.isFalsy(b_result);
                        }
                    } else if (@TypeOf(b_result) == bool) {
                        return b_result;
                    }
                }
                return false; // Both returned NotImplemented
            }
            return if (result == .bool) result.bool else !PyValue.isFalsy(result);
        } else if (ResultType == bool) {
            return result;
        }
    }
    if (b_info == .@"struct" and @hasDecl(B, "__eq__")) {
        const result = b.__eq__(a);
        const ResultType = @TypeOf(result);
        if (ResultType == PyValue) {
            if (result != .not_implemented) {
                return if (result == .bool) result.bool else !PyValue.isFalsy(result);
            }
        } else if (ResultType == bool) {
            return result;
        }
    }

    // ArrayList vs fixed array
    const a_is_arraylist = a_info == .@"struct" and @hasField(A, "items") and @hasField(A, "capacity");
    const b_is_arraylist = b_info == .@"struct" and @hasField(B, "items") and @hasField(B, "capacity");

    if (a_is_arraylist and b_info == .array) {
        const AElem = std.meta.Elem(@TypeOf(a.items));
        const BElem = b_info.array.child;
        // Same element type: use std.mem.eql
        if (AElem == BElem) {
            if (a.items.len != b.len) return false;
            return std.mem.eql(AElem, a.items, &b);
        }
        // ArrayList(PyValue) vs [N]string: compare PyValue.string to string
        if (AElem == PyValue and BElem == []const u8) {
            if (a.items.len != b.len) return false;
            for (a.items, b) |pv, str| {
                if (pv != .string) return false;
                if (!std.mem.eql(u8, pv.string, str)) return false;
            }
            return true;
        }
        return false;
    }
    if (a_info == .array and b_is_arraylist) {
        const AElem = a_info.array.child;
        const BElem = std.meta.Elem(@TypeOf(b.items));
        // Same element type: use std.mem.eql
        if (AElem == BElem) {
            if (a.len != b.items.len) return false;
            return std.mem.eql(AElem, &a, b.items);
        }
        // [N]string vs ArrayList(PyValue): compare string to PyValue.string
        if (AElem == []const u8 and BElem == PyValue) {
            if (a.len != b.items.len) return false;
            for (a, b.items) |str, pv| {
                if (pv != .string) return false;
                if (!std.mem.eql(u8, str, pv.string)) return false;
            }
            return true;
        }
        return false;
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

    // CPython PyObject comparisons with primitives
    if (A == *CpythonPyObject) {
        if (cpython.PyFloat_Check(a)) {
            const float_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(a));
            const fval = float_obj.ob_fval;
            if (b_info == .comptime_float or b_info == .float) {
                return fval == @as(f64, b);
            }
        } else if (cpython.PyLong_Check(a)) {
            const int_obj: *cpython.PyLongObject = @ptrCast(@alignCast(a));
            if (b_info == .comptime_int or b_info == .int) {
                return int_obj.ob_digit == @as(i64, b);
            }
        } else if (cpython.PyBool_Check(a)) {
            const bool_obj: *cpython.PyBoolObject = @ptrCast(@alignCast(a));
            if (B == bool) {
                return (bool_obj.ob_digit != 0) == b;
            }
        } else if (cpython.PyUnicode_Check(a)) {
            const str_obj: *cpython.PyUnicodeObject = @ptrCast(@alignCast(a));
            const len: usize = @intCast(str_obj.length);
            if (b_info == .pointer and b_info.pointer.size == .slice and b_info.pointer.child == u8) {
                return std.mem.eql(u8, str_obj.data[0..len], b);
            }
        }
        return false;
    }
    if (B == *CpythonPyObject) {
        if (cpython.PyFloat_Check(b)) {
            const float_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(b));
            const fval = float_obj.ob_fval;
            if (a_info == .comptime_float or a_info == .float) {
                return @as(f64, a) == fval;
            }
        } else if (cpython.PyLong_Check(b)) {
            const int_obj: *cpython.PyLongObject = @ptrCast(@alignCast(b));
            if (a_info == .comptime_int or a_info == .int) {
                return @as(i64, a) == int_obj.ob_digit;
            }
        } else if (cpython.PyBool_Check(b)) {
            const bool_obj: *cpython.PyBoolObject = @ptrCast(@alignCast(b));
            if (A == bool) {
                return a == (bool_obj.ob_digit != 0);
            }
        } else if (cpython.PyUnicode_Check(b)) {
            const str_obj: *cpython.PyUnicodeObject = @ptrCast(@alignCast(b));
            const len: usize = @intCast(str_obj.length);
            if (a_info == .pointer and a_info.pointer.size == .slice and a_info.pointer.child == u8) {
                return std.mem.eql(u8, a, str_obj.data[0..len]);
            }
        }
        return false;
    }

    // Fallback: convert structs/unions to PyValue for cross-type comparison
    // This handles cases like PyComplex (struct), IntResult/UnifiedInt (union) vs bool/int/float
    // where the type doesn't have __eq__ but can be converted to PyValue
    if (a_info == .@"struct" or a_info == .@"union") {
        const a_pv = PyValue.from(a);
        const b_pv = PyValue.from(b);
        return pyValueEql(a_pv, b_pv);
    }
    if (b_info == .@"struct" or b_info == .@"union") {
        const a_pv = PyValue.from(a);
        const b_pv = PyValue.from(b);
        return pyValueEql(a_pv, b_pv);
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
            .list => |l| l.items,
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

    // PyValue type returns []const PyValue as element slice type for comparison
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
