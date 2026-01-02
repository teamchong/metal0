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
const PyPowResult = @import("builtins/pow.zig").PyPowResult;
const UnifiedInt = @import("../Objects/pyint.zig").UnifiedInt;
const type_predicates = @import("type_predicates.zig");
const exceptions_mod = @import("exceptions.zig");
const PyException = exceptions_mod.PyException;

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

/// Unified Python-style equality using PyValue.from().eql()
/// This is the preferred comparison method - compiles once, handles all types
/// Use this as a drop-in replacement for the legacy pyAnyEql
pub fn pyValueCompare(a: anytype, b: anytype) bool {
    return PyValue.from(a).eql(PyValue.from(b));
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
    // Delegate to PyValue.eql() (SINGLE SOURCE OF TRUTH in object.zig)
    // PyValue.eql() handles:
    // - All PyValue variants including VM-specific types (dict, code, function, etc.)
    // - Cross-type numeric comparison (int/float/bool/complex/bigint)
    // - Class instances with __eq__ dunder methods
    // - NaN identity semantics for containers
    return a.eql(b);
}

// =============================================================================
// PyValue-First Comparison Operators (compile ONCE - no monomorphization)
// All delegate to PyValue methods (SINGLE SOURCE OF TRUTH in object.zig)
// =============================================================================

/// PyValue less-than comparison - compiles ONCE
pub fn pyValueLt(a: PyValue, b: PyValue) bool {
    // Delegate to PyValue.lt() (SINGLE SOURCE OF TRUTH in object.zig)
    return a.lt(b);
}

/// PyValue less-than-or-equal comparison - compiles ONCE
pub fn pyValueLe(a: PyValue, b: PyValue) bool {
    // Delegate to PyValue.le() (SINGLE SOURCE OF TRUTH in object.zig)
    return a.le(b);
}

/// PyValue greater-than comparison - compiles ONCE
pub fn pyValueGt(a: PyValue, b: PyValue) bool {
    // Delegate to PyValue.gt() (SINGLE SOURCE OF TRUTH in object.zig)
    return a.gt(b);
}

/// PyValue greater-than-or-equal comparison - compiles ONCE
pub fn pyValueGe(a: PyValue, b: PyValue) bool {
    // Delegate to PyValue.ge() (SINGLE SOURCE OF TRUTH in object.zig)
    return a.ge(b);
}

/// PyValue not-equal comparison - compiles ONCE
pub fn pyValueNe(a: PyValue, b: PyValue) bool {
    return !a.eql(b);
}

// =============================================================================
// Identity Comparison (for 'is' operator)
// =============================================================================

/// Python identity comparison - handles different types for pointer/value comparison
/// Checks if two values are the same object (same memory location)
/// For containers (list, dict, set), compares pointer addresses
/// For primitives, identity == equality
pub fn pyIdentical(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const a_info = @typeInfo(A);
    const b_info = @typeInfo(B);

    // Same type case
    if (A == B) {
        return pyIdenticalSameType(A, a, b);
    }

    // Handle pointer to value comparison: a is *T, b is T
    if (a_info == .pointer and a_info.pointer.size == .one) {
        if (a_info.pointer.child == B) {
            // a is *T, b is T - check if a points to b's address
            // For ArrayList, compare items.ptr
            if (b_info == .@"struct" and @hasField(B, "items") and @hasField(B, "capacity")) {
                return a.items.ptr == b.items.ptr;
            }
            return a == &b;
        }
    }

    // Handle value to pointer comparison: a is T, b is *T
    if (b_info == .pointer and b_info.pointer.size == .one) {
        if (b_info.pointer.child == A) {
            // a is T, b is *T - check if b points to a's address
            // For ArrayList, compare items.ptr
            if (a_info == .@"struct" and @hasField(A, "items") and @hasField(A, "capacity")) {
                return a.items.ptr == b.items.ptr;
            }
            return &a == b;
        }
    }

    // Handle PyValue vs primitive type comparison
    // For Python singletons (True, False, None), identity == equality
    if (A == PyValue) {
        // a is PyValue, b is primitive - extract a's value and compare
        return switch (a) {
            .bool => |av| if (B == bool) av == b else false,
            .int => |av| if (B == i64 or B == comptime_int) av == @as(i64, @intCast(b)) else false,
            .float => |av| if (B == f64 or B == comptime_float) av == @as(f64, @floatCast(b)) else false,
            .string => |av| if (B == []const u8) std.mem.eql(u8, av, b) else false,
            .none => if (b_info == .null) true else false,
            else => false,
        };
    }
    if (B == PyValue) {
        // b is PyValue, a is primitive - extract b's value and compare
        return switch (b) {
            .bool => |bv| if (A == bool) a == bv else false,
            .int => |bv| if (A == i64 or A == comptime_int) @as(i64, @intCast(a)) == bv else false,
            .float => |bv| if (A == f64 or A == comptime_float) @as(f64, @floatCast(a)) == bv else false,
            .string => |bv| if (A == []const u8) std.mem.eql(u8, a, bv) else false,
            .none => if (a_info == .null) true else false,
            else => false,
        };
    }

    // Handle *PyObject vs bool comparison (for pickle.loads returning Py_True/Py_False)
    if (a_info == .pointer and a_info.pointer.child == CpythonPyObject and B == bool) {
        // a is *PyObject, b is bool - compare against singleton
        const runtime_mod = @import("../runtime.zig");
        if (b) {
            return a == runtime_mod.Py_True;
        } else {
            return a == runtime_mod.Py_False;
        }
    }
    if (b_info == .pointer and b_info.pointer.child == CpythonPyObject and A == bool) {
        // b is *PyObject, a is bool - compare against singleton
        const runtime_mod = @import("../runtime.zig");
        if (a) {
            return b == runtime_mod.Py_True;
        } else {
            return b == runtime_mod.Py_False;
        }
    }

    // Different incompatible types - not identical
    return false;
}

/// Helper for same-type identity comparison
fn pyIdenticalSameType(comptime T: type, a: T, b: T) bool {
    const info = @typeInfo(T);

    // Handle optional types by unwrapping
    if (info == .optional) {
        if (a == null and b == null) return true;
        if (a == null or b == null) return false;
        return pyIdenticalSameType(info.optional.child, a.?, b.?);
    }

    // Pointers: compare addresses directly
    if (info == .pointer) {
        return a == b;
    }

    // Slices: compare ptr addresses (same backing array)
    if (info == .pointer and info.pointer.size == .slice) {
        return a.ptr == b.ptr;
    }

    // ArrayList: compare by pointer to items buffer
    if (info == .@"struct" and @hasField(T, "items") and @hasField(T, "capacity")) {
        return a.items.ptr == b.items.ptr;
    }

    // AutoArrayHashMap (managed): compare by unmanaged.entries.bytes
    // The managed variant has an 'unmanaged' field with 'entries' (MultiArrayList)
    // MultiArrayList uses 'bytes' field as the backing memory pointer
    if (info == .@"struct" and @hasField(T, "unmanaged")) {
        const Unmanaged = @TypeOf(@field(a, "unmanaged"));
        if (@hasField(Unmanaged, "entries")) {
            return a.unmanaged.entries.bytes == b.unmanaged.entries.bytes;
        }
    }

    // ArrayHashMapUnmanaged: compare by entries.bytes directly
    // entries is a MultiArrayList with a 'bytes' field for the backing storage
    if (info == .@"struct" and @hasField(T, "entries") and @hasField(T, "index_header")) {
        return a.entries.bytes == b.entries.bytes;
    }

    // Structs (tuples, class instances): compare addresses
    // Special case: PyException - compare by exception_id for Python identity semantics
    if (info == .@"struct") {
        if (T == PyException) {
            // Python exception identity is tracked by exception_id
            // Same ID means same exception object (for assertIs in re-raises)
            return a.exception_id != 0 and a.exception_id == b.exception_id;
        }
        return &a == &b;
    }

    // Arrays: compare addresses (same backing storage means identity)
    if (info == .array) {
        return &a == &b;
    }

    // Unions: use .eql if available
    if (info == .@"union") {
        if (@hasDecl(T, "eql")) {
            return a.eql(b);
        }
        // For unions without eql, fall back to byte comparison
        return @as([@sizeOf(T)]u8, @bitCast(a)) == @as([@sizeOf(T)]u8, @bitCast(b));
    }

    // Primitives: identity == equality
    return a == b;
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
        // Special case: *CpythonPyObject - compare actual values, not pointer addresses
        if (A == *CpythonPyObject) {
            // Both are floats
            if (cpython.PyFloat_Check(a) and cpython.PyFloat_Check(b)) {
                const a_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(a));
                const b_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(b));
                // Use bit-level comparison for NaN identity semantics
                return @as(u64, @bitCast(a_obj.ob_fval)) == @as(u64, @bitCast(b_obj.ob_fval));
            }
            // Both are ints
            if (cpython.PyLong_Check(a) and cpython.PyLong_Check(b)) {
                const a_obj: *cpython.PyLongObject = @ptrCast(@alignCast(a));
                const b_obj: *cpython.PyLongObject = @ptrCast(@alignCast(b));
                return a_obj.getValue() == b_obj.getValue();
            }
            // Both are bools
            if (cpython.PyBool_Check(a) and cpython.PyBool_Check(b)) {
                const a_obj: *cpython.PyBoolObject = @ptrCast(@alignCast(a));
                const b_obj: *cpython.PyBoolObject = @ptrCast(@alignCast(b));
                return a_obj.getValue() == b_obj.getValue();
            }
            // Both are strings
            if (cpython.PyUnicode_Check(a) and cpython.PyUnicode_Check(b)) {
                const a_obj: *cpython.PyUnicodeObject = @ptrCast(@alignCast(a));
                const b_obj: *cpython.PyUnicodeObject = @ptrCast(@alignCast(b));
                const a_len: usize = @intCast(a_obj.length);
                const b_len: usize = @intCast(b_obj.length);
                return std.mem.eql(u8, a_obj.data[0..a_len], b_obj.data[0..b_len]);
            }
            // Cross-type: float vs int
            if (cpython.PyFloat_Check(a) and cpython.PyLong_Check(b)) {
                const a_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(a));
                const b_obj: *cpython.PyLongObject = @ptrCast(@alignCast(b));
                return a_obj.ob_fval == @as(f64, @floatFromInt(b_obj.getValue()));
            }
            if (cpython.PyLong_Check(a) and cpython.PyFloat_Check(b)) {
                const a_obj: *cpython.PyLongObject = @ptrCast(@alignCast(a));
                const b_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(b));
                return @as(f64, @floatFromInt(a_obj.getValue())) == b_obj.ob_fval;
            }
            // Different types or unsupported - not equal
            return false;
        }
        // Special case: UnifiedInt - use eqlSimple which doesn't need allocator
        if (A == @import("../Objects/pyint.zig").UnifiedInt) {
            return a.eqlSimple(b);
        }
        // Special case: slices need element-wise comparison with NaN identity handling
        if (a_info == .pointer and a_info.pointer.size == .slice) {
            const ElemT = a_info.pointer.child;
            if (a.len != b.len) return false;
            // For float elements, use identity-based NaN comparison (Python semantics)
            if (ElemT == f64) {
                for (a, b) |a_item, b_item| {
                    const a_bits: u64 = @bitCast(a_item);
                    const b_bits: u64 = @bitCast(b_item);
                    if (a_bits != b_bits) return false;
                }
                return true;
            } else if (ElemT == f32) {
                for (a, b) |a_item, b_item| {
                    const a_bits: u32 = @bitCast(a_item);
                    const b_bits: u32 = @bitCast(b_item);
                    if (a_bits != b_bits) return false;
                }
                return true;
            }
            return std.mem.eql(ElemT, a, b);
        }
        // Special case: ArrayLists need items comparison with NaN identity handling
        if (a_info == .@"struct" and @hasField(A, "items") and @hasField(A, "capacity")) {
            const ElemT = std.meta.Elem(@TypeOf(a.items));
            if (a.items.len != b.items.len) return false;
            // For float elements, use identity-based NaN comparison (Python semantics: nan in [nan] == True)
            if (ElemT == f64) {
                for (a.items, b.items) |a_item, b_item| {
                    const a_bits: u64 = @bitCast(a_item);
                    const b_bits: u64 = @bitCast(b_item);
                    if (a_bits != b_bits) return false;
                }
                return true;
            } else if (ElemT == f32) {
                for (a.items, b.items) |a_item, b_item| {
                    const a_bits: u32 = @bitCast(a_item);
                    const b_bits: u32 = @bitCast(b_item);
                    if (a_bits != b_bits) return false;
                }
                return true;
            }
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

    // Handle optional types: ?T == T or T == ?T
    if (comptime a_info == .optional) {
        // Unwrap optional a and compare
        if (a) |unwrapped_a| {
            return pyAnyEql(unwrapped_a, b);
        }
        // a is null - only equal if b is also null
        if (comptime b_info == .optional) {
            return b == null;
        }
        return false;
    }
    if (comptime b_info == .optional) {
        // Unwrap optional b and compare
        if (b) |unwrapped_b| {
            return pyAnyEql(a, unwrapped_b);
        }
        // b is null, a is not optional, so not equal
        return false;
    }

    // Handle type name comparison: pyTypeName(x) == SomeType
    // When comparing a string (type name) with a type,
    // compare the string with the type's name
    const a_is_string = a_info == .pointer and a_info.pointer.size == .slice and a_info.pointer.child == u8;
    const b_is_type = b_info == .type;
    if (a_is_string and b_is_type) {
        // a is a string, b is a type - compare with type name
        // The type is passed as a value, so we use b directly
        const TypeT = b;
        // Check for PyComplex (complex type) - compare with "complex"
        if (@hasDecl(TypeT, "real") and @hasDecl(TypeT, "imag")) {
            return std.mem.eql(u8, a, "complex");
        }
        // Check common type patterns in type name
        const type_name = @typeName(TypeT);
        if (std.mem.indexOf(u8, type_name, "PyComplex") != null) {
            return std.mem.eql(u8, a, "complex");
        }
        if (std.mem.indexOf(u8, type_name, "float") != null or std.mem.eql(u8, type_name, "f64") or std.mem.eql(u8, type_name, "f32")) {
            return std.mem.eql(u8, a, "float");
        }
        if (std.mem.indexOf(u8, type_name, "int") != null or std.mem.eql(u8, type_name, "i64") or std.mem.eql(u8, type_name, "i32")) {
            return std.mem.eql(u8, a, "int");
        }
        if (std.mem.indexOf(u8, type_name, "bool") != null) {
            return std.mem.eql(u8, a, "bool");
        }
        return false;
    }

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

    // ArrayList vs ArrayList - element-wise comparison (handles NaN correctly)
    if (a_is_arraylist and b_is_arraylist) {
        const AElem = std.meta.Elem(@TypeOf(a.items));
        const BElem = std.meta.Elem(@TypeOf(b.items));
        if (a.items.len != b.items.len) return false;
        // Same element type with f64 (floats) - use identity for NaN comparison
        if (AElem == f64 and BElem == f64) {
            for (a.items, b.items) |a_item, b_item| {
                const a_nan = std.math.isNan(a_item);
                const b_nan = std.math.isNan(b_item);
                if (a_nan and b_nan) {
                    // Both NaN - check identity via bitcast
                    if (@as(u64, @bitCast(a_item)) != @as(u64, @bitCast(b_item))) return false;
                } else if (a_nan or b_nan) {
                    return false; // One is NaN, other is not
                } else if (a_item != b_item) {
                    return false;
                }
            }
            return true;
        }
        // Same element type - use std.mem.eql
        if (AElem == BElem) {
            return std.mem.eql(AElem, a.items, b.items);
        }
        // Different element types - compare element by element recursively
        for (a.items, b.items) |a_item, b_item| {
            if (!pyAnyEql(a_item, b_item)) return false;
        }
        return true;
    }

    // Numeric coercion: int vs comptime_int, float vs comptime_float
    const a_is_int = type_predicates.isIntInfo(a_info);
    const b_is_int = type_predicates.isIntInfo(b_info);
    if (a_is_int and b_is_int) {
        return @as(i64, a) == @as(i64, b);
    }

    const a_is_float = type_predicates.isFloatInfo(a_info);
    const b_is_float = type_predicates.isFloatInfo(b_info);
    if (a_is_float and b_is_float) {
        // Use bitwise comparison to handle NaN identity (NaN == NaN should be true for containment)
        // This matches Python's behavior where `nan in [nan]` is True (identity check)
        return @as(u64, @bitCast(@as(f64, a))) == @as(u64, @bitCast(@as(f64, b)));
    }
    // Cross-type: float vs int (Python: 1.0 == 1 is True)
    if (a_is_float and b_is_int) {
        return @as(f64, a) == @as(f64, @floatFromInt(@as(i64, b)));
    }
    if (a_is_int and b_is_float) {
        return @as(f64, @floatFromInt(@as(i64, a))) == @as(f64, b);
    }

    // PyPowResult vs float comparison
    // Extract float value from PyPowResult and compare
    const a_is_pow_result = A == PyPowResult;
    const b_is_pow_result = B == PyPowResult;
    if (a_is_pow_result and b_is_float) {
        const a_float = a.toFloat();
        return @as(u64, @bitCast(a_float)) == @as(u64, @bitCast(@as(f64, b)));
    }
    if (b_is_pow_result and a_is_float) {
        const b_float = b.toFloat();
        return @as(u64, @bitCast(@as(f64, a))) == @as(u64, @bitCast(b_float));
    }
    if (a_is_pow_result and b_is_pow_result) {
        // Both are PyPowResult - compare float values or both complex
        if (a.isFloat() and b.isFloat()) {
            return @as(u64, @bitCast(a.toFloat())) == @as(u64, @bitCast(b.toFloat()));
        }
        if (a.isComplex() and b.isComplex()) {
            const ac = a.asComplex();
            const bc = b.asComplex();
            return ac.real == bc.real and ac.imag == bc.imag;
        }
        return false; // Different types
    }

    // String slices (handles []const u8 vs []const u8 and []const u8 vs *const [N]u8)
    if (a_info == .pointer and a_info.pointer.size == .slice and a_info.pointer.child == u8) {
        // []const u8 vs []const u8
        if (b_info == .pointer and b_info.pointer.size == .slice and b_info.pointer.child == u8) {
            return std.mem.eql(u8, a, b);
        }
        // []const u8 vs *const [N]u8 (string literal)
        if (b_info == .pointer and b_info.pointer.size == .one) {
            const child_info = @typeInfo(b_info.pointer.child);
            if (child_info == .array and child_info.array.child == u8) {
                return std.mem.eql(u8, a, b[0..child_info.array.len]);
            }
        }
    }
    // *const [N]u8 (string literal) vs []const u8
    if (a_info == .pointer and a_info.pointer.size == .one) {
        const a_child_info = @typeInfo(a_info.pointer.child);
        if (a_child_info == .array and a_child_info.array.child == u8) {
            if (b_info == .pointer and b_info.pointer.size == .slice and b_info.pointer.child == u8) {
                return std.mem.eql(u8, a[0..a_child_info.array.len], b);
            }
        }
    }

    // PyValue comparisons (without recursion)
    if (A == PyValue) {
        return switch (a) {
            .int => |v| if (b_info == .comptime_int or b_info == .int) v == @as(i64, b) else if (B == UnifiedInt) b.eqlInt(v) else false,
            // Use bit-level comparison for floats to preserve signed zero and NaN identity
            .float => |v| if (b_info == .comptime_float or b_info == .float) @as(u64, @bitCast(v)) == @as(u64, @bitCast(@as(f64, b))) else false,
            .bool => |v| if (B == bool) v == b else false,
            .ptr => |p| blk: {
                // PyValue.ptr contains a *anyopaque - cast to *PyObject for type checks
                const pyobj: *cpython.PyObject = @ptrCast(@alignCast(p));
                // Compare with UnifiedInt if it's an int
                if (B == UnifiedInt) {
                    // Check PyBigIntObject first (arbitrary precision)
                    if (cpython.PyBigInt_Check(pyobj)) {
                        const bigint_obj: *cpython.PyBigIntObject = @ptrCast(@alignCast(p));
                        // Compare BigInt vs UnifiedInt
                        switch (b) {
                            .small => |small_val| break :blk bigint_obj.value.eqlInt(small_val),
                            .big => |big_ptr| break :blk bigint_obj.value.eql(big_ptr),
                        }
                    }
                    // Then check PyLongObject (small integers)
                    if (cpython.PyLong_Check(pyobj)) {
                        const int_obj: *cpython.PyLongObject = @ptrCast(@alignCast(p));
                        const int_val: i64 = int_obj.getValue();
                        break :blk b.eqlInt(int_val);
                    }
                }
                break :blk false;
            },
            .string => |v| blk: {
                // Handle []const u8 (slice)
                if (b_info == .pointer and b_info.pointer.size == .slice and b_info.pointer.child == u8) {
                    break :blk std.mem.eql(u8, v, b);
                }
                // Handle *const [N:0]u8 (string literal / pointer to array)
                if (b_info == .pointer and b_info.pointer.size == .one) {
                    const child_info = @typeInfo(b_info.pointer.child);
                    if (child_info == .array and child_info.array.child == u8) {
                        break :blk std.mem.eql(u8, v, b[0..child_info.array.len]);
                    }
                }
                break :blk false;
            },
            else => false,
        };
    }
    if (B == PyValue) {
        return switch (b) {
            .int => |v| if (a_info == .comptime_int or a_info == .int) @as(i64, a) == v else false,
            // Use bit-level comparison for floats to preserve signed zero and NaN identity
            .float => |v| if (a_info == .comptime_float or a_info == .float) @as(u64, @bitCast(@as(f64, a))) == @as(u64, @bitCast(v)) else false,
            .bool => |v| if (A == bool) a == v else false,
            .string => |v| blk: {
                // Handle []const u8 (slice)
                if (a_info == .pointer and a_info.pointer.size == .slice and a_info.pointer.child == u8) {
                    break :blk std.mem.eql(u8, a, v);
                }
                // Handle *const [N:0]u8 (string literal / pointer to array)
                if (a_info == .pointer and a_info.pointer.size == .one) {
                    const child_info = @typeInfo(a_info.pointer.child);
                    if (child_info == .array and child_info.array.child == u8) {
                        break :blk std.mem.eql(u8, a[0..child_info.array.len], v);
                    }
                }
                break :blk false;
            },
            else => false,
        };
    }

    // CPython PyObject comparisons
    // Case 1: Both are *CpythonPyObject - compare actual values
    if (A == *CpythonPyObject and B == *CpythonPyObject) {
        // Both are floats
        if (cpython.PyFloat_Check(a) and cpython.PyFloat_Check(b)) {
            const a_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(a));
            const b_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(b));
            // Use bit-level comparison for NaN identity semantics
            return @as(u64, @bitCast(a_obj.ob_fval)) == @as(u64, @bitCast(b_obj.ob_fval));
        }
        // Both are ints
        if (cpython.PyLong_Check(a) and cpython.PyLong_Check(b)) {
            const a_obj: *cpython.PyLongObject = @ptrCast(@alignCast(a));
            const b_obj: *cpython.PyLongObject = @ptrCast(@alignCast(b));
            return a_obj.getValue() == b_obj.getValue();
        }
        // Both are bools
        if (cpython.PyBool_Check(a) and cpython.PyBool_Check(b)) {
            const a_obj: *cpython.PyBoolObject = @ptrCast(@alignCast(a));
            const b_obj: *cpython.PyBoolObject = @ptrCast(@alignCast(b));
            return a_obj.getValue() == b_obj.getValue();
        }
        // Both are strings
        if (cpython.PyUnicode_Check(a) and cpython.PyUnicode_Check(b)) {
            const a_obj: *cpython.PyUnicodeObject = @ptrCast(@alignCast(a));
            const b_obj: *cpython.PyUnicodeObject = @ptrCast(@alignCast(b));
            const a_len: usize = @intCast(a_obj.length);
            const b_len: usize = @intCast(b_obj.length);
            return std.mem.eql(u8, a_obj.data[0..a_len], b_obj.data[0..b_len]);
        }
        // Cross-type: float vs int
        if (cpython.PyFloat_Check(a) and cpython.PyLong_Check(b)) {
            const a_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(a));
            const b_obj: *cpython.PyLongObject = @ptrCast(@alignCast(b));
            return a_obj.ob_fval == @as(f64, @floatFromInt(b_obj.getValue()));
        }
        if (cpython.PyLong_Check(a) and cpython.PyFloat_Check(b)) {
            const a_obj: *cpython.PyLongObject = @ptrCast(@alignCast(a));
            const b_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(b));
            return @as(f64, @floatFromInt(a_obj.getValue())) == b_obj.ob_fval;
        }
        // Different types or unsupported - not equal
        return false;
    }

    // Case 2: *CpythonPyObject vs primitive
    if (A == *CpythonPyObject) {
        if (cpython.PyFloat_Check(a)) {
            const float_obj: *cpython.PyFloatObject = @ptrCast(@alignCast(a));
            const fval = float_obj.ob_fval;
            if (b_info == .comptime_float or b_info == .float) {
                return fval == @as(f64, b);
            }
        } else if (cpython.PyBigInt_Check(a)) {
            // PyBigIntObject - arbitrary precision integer
            const bigint_obj: *cpython.PyBigIntObject = @ptrCast(@alignCast(a));
            if (B == UnifiedInt) {
                return switch (b) {
                    .small => |small_val| bigint_obj.value.eqlInt(small_val),
                    .big => |big_ptr| bigint_obj.value.eql(big_ptr),
                };
            } else if (b_info == .comptime_int or b_info == .int) {
                return bigint_obj.value.eqlInt(@as(i64, b));
            }
        } else if (cpython.PyLong_Check(a)) {
            const int_obj: *cpython.PyLongObject = @ptrCast(@alignCast(a));
            if (b_info == .comptime_int or b_info == .int) {
                return int_obj.getValue() == @as(i64, b);
            } else if (b_info == .comptime_float or b_info == .float) {
                // Cross-type comparison: PyLongObject vs f64
                // Python: 0 == 0.0 returns True
                const int_val: i64 = int_obj.getValue();
                return @as(f64, @floatFromInt(int_val)) == @as(f64, b);
            } else if (B == UnifiedInt) {
                // Cross-type comparison: PyLongObject vs UnifiedInt
                // Both represent Python integers, compare their values
                const int_val: i64 = int_obj.getValue();
                return b.eqlInt(int_val);
            }
        } else if (cpython.PyBool_Check(a)) {
            const bool_obj: *cpython.PyBoolObject = @ptrCast(@alignCast(a));
            if (B == bool) {
                return bool_obj.getValue() == b;
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
        } else if (cpython.PyBigInt_Check(b)) {
            // PyBigIntObject - arbitrary precision integer
            const bigint_obj: *cpython.PyBigIntObject = @ptrCast(@alignCast(b));
            if (A == UnifiedInt) {
                return switch (a) {
                    .small => |small_val| bigint_obj.value.eqlInt(small_val),
                    .big => |big_ptr| bigint_obj.value.eql(big_ptr),
                };
            } else if (a_info == .comptime_int or a_info == .int) {
                return bigint_obj.value.eqlInt(@as(i64, a));
            }
        } else if (cpython.PyLong_Check(b)) {
            const int_obj: *cpython.PyLongObject = @ptrCast(@alignCast(b));
            if (a_info == .comptime_int or a_info == .int) {
                return @as(i64, a) == int_obj.getValue();
            } else if (a_info == .comptime_float or a_info == .float) {
                // Cross-type comparison: f64 vs PyLongObject
                // Python: 0.0 == 0 returns True
                const int_val: i64 = int_obj.getValue();
                return @as(f64, a) == @as(f64, @floatFromInt(int_val));
            } else if (A == UnifiedInt) {
                // Cross-type comparison: UnifiedInt vs PyLongObject
                // Both represent Python integers, compare their values
                const int_val: i64 = int_obj.getValue();
                return a.eqlInt(int_val);
            }
        } else if (cpython.PyBool_Check(b)) {
            const bool_obj: *cpython.PyBoolObject = @ptrCast(@alignCast(b));
            if (A == bool) {
                return a == bool_obj.getValue();
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
