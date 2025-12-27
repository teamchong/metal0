/// metal0 unittest assertions - equality helper functions
const std = @import("std");
const runtime = @import("../../../runtime.zig");
const PyValue = runtime.PyValue;

/// Python-compatible value equality check (handles NaN identity, cross-type comparison)
/// Delegates to PyValue.from().eql() for comprehensive Python semantic comparison
pub fn pythonEql(a: anytype, b: anytype) bool {
    return PyValue.from(a).eql(PyValue.from(b));
}

/// Helper to compare two elements - delegates to PyValue.eql() for Python semantics
pub fn elemEql(a: anytype, b: anytype) bool {
    return PyValue.from(a).eql(PyValue.from(b));
}

/// Helper to compare two ArrayList instances element by element
pub fn equalArrayList(a: anytype, b: anytype) bool {
    // Check length first
    if (a.items.len != b.items.len) return false;

    // Compare elements one by one
    const ElemA = @TypeOf(a.items[0]);
    const ElemB = @TypeOf(b.items[0]);
    const a_elem_info = @typeInfo(ElemA);
    const b_elem_info = @typeInfo(ElemB);

    for (a.items, b.items) |a_elem, b_elem| {
        // Compare elements based on their type
        if ((a_elem_info == .@"struct" and a_elem_info.@"struct".is_tuple) or
            (b_elem_info == .@"struct" and b_elem_info.@"struct".is_tuple))
        {
            // Tuple elements - compare field by field
            if (!equalTuples(a_elem, b_elem)) return false;
        } else if (a_elem_info == .@"union") {
            // Union types (like PyValue) - compare using deepEqualUnion
            if (!deepEqualUnion(a_elem, b_elem)) return false;
        } else if (@TypeOf(a_elem) == @TypeOf(b_elem)) {
            // For slices, compare content not pointers
            if (a_elem_info == .pointer and a_elem_info.pointer.size == .slice) {
                if (!std.mem.eql(a_elem_info.pointer.child, a_elem, b_elem)) return false;
            } else if (a_elem_info == .float or a_elem_info == .comptime_float) {
                // Special float handling: NaN == NaN when both are NaN (Python list semantics)
                // In Python, [nan] == [nan] is True when both nans are the same object
                if (std.math.isNan(a_elem) and std.math.isNan(b_elem)) {
                    continue; // Both NaN - consider equal (same object identity)
                }
                if (a_elem != b_elem) return false;
            } else if (!PyValue.from(a_elem).eql(PyValue.from(b_elem))) return false;
        } else {
            // Different types - try string comparison with __base_value__
            if (!equalWithBaseValue(a_elem, b_elem)) return false;
        }
    }
    return true;
}

/// Helper to compare two HashMap instances by iterating their entries
pub fn equalHashMap(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);

    // Get count - use count() method only if it takes no arguments (hashmap style)
    // Otherwise use .len field
    const a_count = blk: {
        if (@hasDecl(A, "count")) {
            const fn_info = @typeInfo(@TypeOf(A.count)).@"fn";
            // If count takes only self parameter (or no params for non-method), use it
            if (fn_info.params.len <= 1) {
                break :blk a.count();
            }
        }
        if (@hasField(A, "len")) break :blk a.len;
        return false;
    };
    const b_count = blk: {
        if (@hasDecl(B, "count")) {
            const fn_info = @typeInfo(@TypeOf(B.count)).@"fn";
            if (fn_info.params.len <= 1) {
                break :blk b.count();
            }
        }
        if (@hasField(B, "len")) break :blk b.len;
        return false;
    };

    // Different sizes mean not equal
    if (a_count != b_count) return false;

    // Empty maps are equal
    if (a_count == 0) return true;

    // Iterate over a and check each entry exists in b with same value
    if (@hasDecl(A, "iterator")) {
        var it = a.iterator();
        while (it.next()) |entry| {
            // Check if b has this key with same value
            if (@hasDecl(B, "get")) {
                const b_val = b.get(entry.key_ptr.*);
                if (b_val == null) return false;
                if (!PyValue.from(entry.value_ptr.*).eql(PyValue.from(b_val.?))) return false;
            } else {
                return false; // b doesn't support get
            }
        }
        return true;
    }

    // Fallback: use PyValue.from().eql() for Python semantics
    return PyValue.from(a).eql(PyValue.from(b));
}

/// Compare PyValue union with another value (tuple, array, int, etc.)
/// Extracts the inner value from PyValue and compares recursively
pub fn equalPyValueWith(pyval: anytype, other: anytype) bool {
    const PyVal = @TypeOf(pyval);
    const Other = @TypeOf(other);
    const other_info = @typeInfo(Other);

    // Get active tag of PyValue union
    const tag = std.meta.activeTag(pyval);

    // Handle each PyValue variant
    if (tag == .int) {
        const val = @field(pyval, "int");
        if (other_info == .int or other_info == .comptime_int) {
            return val == other;
        }
        return false;
    }
    if (tag == .float) {
        const val = @field(pyval, "float");
        if (other_info == .float or other_info == .comptime_float) {
            return val == other; // Use exact equality
        }
        if (other_info == .int or other_info == .comptime_int) {
            return val == @as(f64, @floatFromInt(other)); // Use exact equality
        }
        return false;
    }
    if (tag == .string) {
        const val = @field(pyval, "string");
        if (other_info == .pointer and other_info.pointer.size == .slice and other_info.pointer.child == u8) {
            return std.mem.eql(u8, val, other);
        }
        return false;
    }
    if (tag == .bool) {
        const val = @field(pyval, "bool");
        if (other_info == .bool) {
            return val == other;
        }
        return false;
    }
    if (tag == .none) {
        if (other_info == .optional) {
            return other == null;
        }
        return false;
    }
    if (tag == .list or tag == .tuple) {
        // Handle list field - could be ArrayList (PickleValue) or slice (PyValue)
        const list_field = @field(pyval, "list");
        const list_field_type = @TypeOf(list_field);
        const list_field_info = @typeInfo(list_field_type);
        const items: []const PyVal = if (tag == .list)
            (if (list_field_info == .@"struct" and @hasField(list_field_type, "items"))
                list_field.items
            else
                list_field)
        else
            @field(pyval, "tuple");

        // Compare with Zig tuple
        if (other_info == .@"struct" and other_info.@"struct".is_tuple) {
            const fields = other_info.@"struct".fields;
            if (items.len != fields.len) return false;

            inline for (fields, 0..) |field, i| {
                const other_elem = @field(other, field.name);
                if (!equalPyValueWith(items[i], other_elem)) return false;
            }
            return true;
        }
        // Compare with Zig array
        if (other_info == .array) {
            if (items.len != other.len) return false;
            for (items, 0..) |item, i| {
                if (!equalPyValueWith(item, other[i])) return false;
            }
            return true;
        }
        // Compare with slice
        if (other_info == .pointer and other_info.pointer.size == .slice) {
            if (items.len != other.len) return false;
            for (items, 0..) |item, i| {
                if (!equalPyValueWith(item, other[i])) return false;
            }
            return true;
        }
        // Compare with ArrayList
        if (other_info == .@"struct" and @hasField(Other, "items") and @hasField(Other, "capacity")) {
            if (items.len != other.items.len) return false;
            for (items, 0..) |item, i| {
                if (!equalPyValueWith(item, other.items[i])) return false;
            }
            return true;
        }
        return false;
    }

    // Fallback - try direct comparison if same type
    return false;
}

/// Compare values where one might be a string and the other a str subclass with __base_value__
pub fn equalWithBaseValue(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const a_info = @typeInfo(A);
    const b_info = @typeInfo(B);

    // Helper to check if type is string-like
    const a_is_string = comptime blk: {
        if (A == []const u8 or A == []u8) break :blk true;
        if (a_info == .pointer and a_info.pointer.size == .slice and a_info.pointer.child == u8) break :blk true;
        break :blk false;
    };
    const b_is_string = comptime blk: {
        if (B == []const u8 or B == []u8) break :blk true;
        if (b_info == .pointer and b_info.pointer.size == .slice and b_info.pointer.child == u8) break :blk true;
        break :blk false;
    };

    // Check if a is a string and b has __base_value__
    if (a_is_string and b_info == .@"struct" and @hasField(B, "__base_value__")) {
        const b_str: []const u8 = b.__base_value__;
        return std.mem.eql(u8, a, b_str);
    }
    // Check if b is a string and a has __base_value__
    if (b_is_string and a_info == .@"struct" and @hasField(A, "__base_value__")) {
        const a_str: []const u8 = a.__base_value__;
        return std.mem.eql(u8, a_str, b);
    }
    return false;
}

/// Deep equality for union types
/// Uses PyValue comparison to avoid O(n²) monomorphization from inline for over fields
pub fn deepEqualUnion(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    if (A != B) return false;

    const info = @typeInfo(A);
    if (info != .@"union") return false;

    // Quick check: different tags means not equal
    const a_tag = std.meta.activeTag(a);
    const b_tag = std.meta.activeTag(b);
    if (a_tag != b_tag) return false;

    // Use PyValue comparison to reduce monomorphization
    // Instead of inline for over union fields, delegate to PyValue.eql
    const allocator = @import("utils.allocator_helper").fast_allocator;
    return runtime.equality_ops.equalViaPyValue(allocator, a, b);
}

/// Helper to compare two tuple structs
/// Uses PyValue comparison to avoid O(n²) monomorphization from inline for + @field
pub fn equalTuples(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const a_info = @typeInfo(A);
    const b_info = @typeInfo(B);

    if (a_info != .@"struct" or b_info != .@"struct") return false;

    const a_fields = a_info.@"struct".fields;
    const b_fields = b_info.@"struct".fields;

    if (a_fields.len != b_fields.len) return false;

    // Use PyValue comparison to reduce monomorphization
    // O(n) conversions + O(1) comparison instead of O(n²) inline field iteration
    const allocator = @import("utils.allocator_helper").fast_allocator;
    return runtime.equality_ops.equalViaPyValue(allocator, a, b);
}

/// Check if a type is a string-like type (slice or string literal pointer)
pub fn isStringType(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info == .pointer) {
        if (info.pointer.size == .slice and info.pointer.child == u8) return true;
        if (info.pointer.size == .one) {
            const child_info = @typeInfo(info.pointer.child);
            if (child_info == .array and child_info.array.child == u8) return true;
        }
    }
    return false;
}

/// Helper to compare two float values, handling special cases (inf, nan)
pub fn floatsEqual(a: f64, b: f64) bool {
    // Use exact equality (IEEE 754 semantics)
    return a == b;
}

/// Helper to compare two values of potentially different but compatible types
pub fn equalValues(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const a_info = @typeInfo(A);
    const b_info = @typeInfo(B);

    // String comparisons - handle []const u8 vs *const [N:0]u8
    if (comptime isStringType(A) and isStringType(B)) {
        const a_slice: []const u8 = a;
        const b_slice: []const u8 = b;
        return std.mem.eql(u8, a_slice, b_slice);
    }

    // Handle optional string types
    if (comptime a_info == .optional and b_info == .optional) {
        const AChild = a_info.optional.child;
        const BChild = b_info.optional.child;
        if (comptime isStringType(AChild) and isStringType(BChild)) {
            if (a == null and b == null) return true;
            if (a == null or b == null) return false;
            const a_slice: []const u8 = a.?;
            const b_slice: []const u8 = b.?;
            return std.mem.eql(u8, a_slice, b_slice);
        }
    }

    // Same type - use PyValue.eql() for Python semantics (handles NaN, structs, etc.)
    if (A == B) {
        return PyValue.from(a).eql(PyValue.from(b));
    }

    // Integer type coercion - comptime_int vs i64/i32/etc
    if (comptime (a_info == .int or a_info == .comptime_int) and (b_info == .int or b_info == .comptime_int)) {
        return a == b;
    }

    // Float type coercion - comptime_float vs f64/f32
    if (comptime (a_info == .float or a_info == .comptime_float) and (b_info == .float or b_info == .comptime_float)) {
        return floatsEqual(@as(f64, a), @as(f64, b));
    }

    // PyPowResult vs float comparison - extract float_val
    if (comptime a_info == .@"union" and @hasField(A, "float_val") and @hasField(A, "complex_val")) {
        // a is PyPowResult
        switch (a) {
            .float_val => |fv| {
                if (comptime b_info == .float or b_info == .comptime_float) {
                    return floatsEqual(fv, b);
                }
            },
            .complex_val => |cv| {
                if (cv.imag == 0.0) {
                    if (comptime b_info == .float or b_info == .comptime_float) {
                        return floatsEqual(cv.real, b);
                    }
                }
            },
        }
    }
    if (comptime b_info == .@"union" and @hasField(B, "float_val") and @hasField(B, "complex_val")) {
        // b is PyPowResult
        switch (b) {
            .float_val => |fv| {
                if (comptime a_info == .float or a_info == .comptime_float) {
                    return floatsEqual(a, fv);
                }
            },
            .complex_val => |cv| {
                if (cv.imag == 0.0) {
                    if (comptime a_info == .float or a_info == .comptime_float) {
                        return floatsEqual(a, cv.real);
                    }
                }
            },
        }
    }

    // BigInt vs i64 comparison - convert BigInt to i64 if possible
    if (comptime a_info == .@"struct" and @hasField(A, "managed") and @hasDecl(A, "toInt64")) {
        // a is BigInt
        if (comptime b_info == .int or b_info == .comptime_int) {
            // b is an integer - convert BigInt to i64 and compare
            if (a.toInt64()) |a_i64| {
                return a_i64 == @as(i64, @intCast(b));
            }
            return false; // BigInt doesn't fit in i64, can't be equal
        }
    }
    if (comptime b_info == .@"struct" and @hasField(B, "managed") and @hasDecl(B, "toInt64")) {
        // b is BigInt
        if (comptime a_info == .int or a_info == .comptime_int) {
            // a is an integer - convert BigInt to i64 and compare
            if (b.toInt64()) |b_i64| {
                return @as(i64, @intCast(a)) == b_i64;
            }
            return false; // BigInt doesn't fit in i64, can't be equal
        }
    }

    // Tuple/struct comparison - use PyValue to avoid O(n²) inline for monomorphization
    // Handles (BigInt, BigInt) vs (i64, i64) and similar cases
    if (comptime a_info == .@"struct" and b_info == .@"struct") {
        const a_fields = a_info.@"struct".fields;
        const b_fields = b_info.@"struct".fields;
        if (a_fields.len == b_fields.len) {
            // Use PyValue comparison instead of inline for over fields
            const allocator = @import("utils.allocator_helper").fast_allocator;
            return runtime.equality_ops.equalViaPyValue(allocator, a, b);
        }
    }

    return false;
}
