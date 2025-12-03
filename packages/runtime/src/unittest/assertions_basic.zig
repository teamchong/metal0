/// metal0 unittest assertions - basic comparison assertions
const std = @import("std");
const runner = @import("runner.zig");

/// Helper to compare two ArrayList instances element by element
fn equalArrayList(a: anytype, b: anytype) bool {
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
            } else if (!std.meta.eql(a_elem, b_elem)) return false;
        } else {
            // Different types - try string comparison with __base_value__
            if (!equalWithBaseValue(a_elem, b_elem)) return false;
        }
    }
    return true;
}

/// Compare values where one might be a string and the other a str subclass with __base_value__
fn equalWithBaseValue(a: anytype, b: anytype) bool {
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
fn deepEqualUnion(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    if (A != B) return false;

    const info = @typeInfo(A);
    if (info != .@"union") return false;

    const a_tag = std.meta.activeTag(a);
    const b_tag = std.meta.activeTag(b);
    if (a_tag != b_tag) return false;

    // Compare payload based on active tag
    inline for (info.@"union".fields) |field| {
        if (a_tag == @field(std.meta.Tag(A), field.name)) {
            const a_payload = @field(a, field.name);
            const b_payload = @field(b, field.name);
            const PayloadType = @TypeOf(a_payload);
            const payload_info = @typeInfo(PayloadType);

            // Handle slices specially - compare contents not pointers
            if (payload_info == .pointer and payload_info.pointer.size == .slice) {
                if (a_payload.len != b_payload.len) return false;
                const ChildType = payload_info.pointer.child;
                const child_info = @typeInfo(ChildType);
                // For slices of unions (like []const PyValue), recursively compare
                if (child_info == .@"union") {
                    for (a_payload, b_payload) |a_item, b_item| {
                        if (!deepEqualUnion(a_item, b_item)) return false;
                    }
                    return true;
                }
                // For simple slices, use mem.eql
                if (ChildType == u8) {
                    return std.mem.eql(u8, a_payload, b_payload);
                }
                // For other types, compare element by element
                for (a_payload, b_payload) |a_item, b_item| {
                    if (!std.meta.eql(a_item, b_item)) return false;
                }
                return true;
            }
            return std.meta.eql(a_payload, b_payload);
        }
    }
    return false;
}

/// Helper to compare two tuple structs
fn equalTuples(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const a_info = @typeInfo(A);
    const b_info = @typeInfo(B);

    if (a_info != .@"struct" or b_info != .@"struct") return false;

    const a_fields = a_info.@"struct".fields;
    const b_fields = b_info.@"struct".fields;

    if (a_fields.len != b_fields.len) return false;

    inline for (0..a_fields.len) |i| {
        const a_field = @field(a, a_fields[i].name);
        const b_field = @field(b, b_fields[i].name);

        const FA = @TypeOf(a_field);
        const FB = @TypeOf(b_field);
        const fa_info = @typeInfo(FA);
        const fb_info = @typeInfo(FB);

        // Handle optional types - use comptime if for type-based decisions
        const field_equal = comptime if (fa_info == .optional and fb_info == .optional) blk: {
            // Both optional
            break :blk true;
        } else if (fa_info == .optional) blk: {
            // a optional, b not
            break :blk false;
        } else if (fb_info == .optional) blk: {
            // b optional, a not
            break :blk false;
        } else blk: {
            // Neither optional
            break :blk false;
        };

        _ = field_equal; // silence unused

        // Runtime comparison
        // Handle bare null type (@Type(.null).null) - it's always null
        const a_is_bare_null = comptime fa_info == .null;
        const b_is_bare_null = comptime fb_info == .null;

        if (comptime fa_info == .optional and fb_info == .optional) {
            // Both optional
            const a_null = a_field == null;
            const b_null = b_field == null;
            if (a_null and b_null) {
                // Both null, this field matches, check next
            } else if (a_null or b_null) {
                return false;
            } else {
                // Both non-null, compare inner values
                if (!equalValues(a_field.?, b_field.?)) return false;
            }
        } else if (comptime fa_info == .optional and b_is_bare_null) {
            // a is optional, b is bare null - a must be null to match
            if (a_field != null) return false;
        } else if (comptime a_is_bare_null and fb_info == .optional) {
            // a is bare null, b is optional - b must be null to match
            if (b_field != null) return false;
        } else if (comptime a_is_bare_null and b_is_bare_null) {
            // Both are bare null - they match
        } else if (comptime fa_info == .optional) {
            // a is optional, b is not - check if a is null or if values match
            if (a_field) |a_val| {
                if (!equalValues(a_val, b_field)) return false;
            } else {
                return false;
            }
        } else if (comptime fb_info == .optional) {
            // b is optional, a is not
            if (b_field) |b_val| {
                if (!equalValues(a_field, b_val)) return false;
            } else {
                return false;
            }
        } else {
            // For non-optional fields, use equalValues which handles string type coercion
            if (!equalValues(a_field, b_field)) return false;
        }
    }
    return true;
}

/// Check if a type is a string-like type (slice or string literal pointer)
fn isStringType(comptime T: type) bool {
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

/// Helper to compare two values of potentially different but compatible types
fn equalValues(a: anytype, b: anytype) bool {
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

    // Same type - direct compare
    if (A == B) {
        if (comptime a_info == .@"struct") {
            return std.meta.eql(a, b);
        }
        return a == b;
    }

    return false;
}

/// Assertion: assertEqual(a, b) - values must be equal
pub fn assertEqual(a: anytype, b: anytype) void {
    const runtime = @import("../runtime.zig");
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const a_info = @typeInfo(A);
    const b_info = @typeInfo(B);

    // Unwrap error unions before comparison
    if (a_info == .error_union) {
        const unwrapped = a catch {
            std.debug.print("AssertionError: first argument is error\n", .{});
            if (runner.global_result) |result| {
                result.addFail("assertEqual failed - error value") catch {};
            }
            @panic("assertEqual failed");
        };
        return assertEqual(unwrapped, b);
    }
    if (b_info == .error_union) {
        const unwrapped = b catch {
            std.debug.print("AssertionError: second argument is error\n", .{});
            if (runner.global_result) |result| {
                result.addFail("assertEqual failed - error value") catch {};
            }
            @panic("assertEqual failed");
        };
        return assertEqual(a, unwrapped);
    }

    // Unwrap PyObject pointers before comparison
    if (A == *runtime.PyObject) {
        const py_val = runtime.pyObjectToValue(a);
        return assertEqual(py_val, b);
    }
    if (B == *runtime.PyObject) {
        const py_val = runtime.pyObjectToValue(b);
        return assertEqual(a, py_val);
    }

    const equal = blk: {

        // Same type - direct comparison
        if (A == B) {
            if (a_info == .float or a_info == .comptime_float) {
                break :blk @abs(a - b) < 0.0001;
            }
            if (a_info == .array) {
                break :blk std.mem.eql(@TypeOf(a[0]), &a, &b);
            }
            if (a_info == .pointer and a_info.pointer.size == .slice) {
                break :blk std.mem.eql(u8, a, b);
            }
            // Struct with eql method - use it for comparison
            if (a_info == .@"struct" and @hasDecl(A, "eql")) {
                // Check if eql takes pointer or value - BigInt takes pointer, PyComplex takes value
                const EqlFn = @TypeOf(A.eql);
                const eql_params = @typeInfo(EqlFn).@"fn".params;
                if (eql_params.len >= 2) {
                    const second_param_type = eql_params[1].type orelse break :blk a.eql(b);
                    if (@typeInfo(second_param_type) == .pointer) {
                        // BigInt style - takes pointer
                        break :blk a.eql(&b);
                    }
                }
                // PyComplex style - takes value or anytype
                break :blk a.eql(b);
            }
            // ArrayList comparison - compare items element by element
            if (a_info == .@"struct" and @hasField(A, "items") and @hasField(A, "capacity")) {
                break :blk equalArrayList(a, b);
            }
            // Generic struct comparison using std.meta.eql
            if (a_info == .@"struct") {
                break :blk std.meta.eql(a, b);
            }
            break :blk a == b;
        }

        // ArrayList comparison - different ArrayList types but same-structured items
        if (a_info == .@"struct" and b_info == .@"struct") {
            if (@hasField(A, "items") and @hasField(A, "capacity") and
                @hasField(B, "items") and @hasField(B, "capacity"))
            {
                break :blk equalArrayList(a, b);
            }
        }

        // ArrayList vs array comparison - compare ArrayList.items with array
        if (a_info == .@"struct" and @hasField(A, "items") and @hasField(A, "capacity") and b_info == .array) {
            if (a.items.len != b.len) break :blk false;
            for (a.items, 0..) |a_elem, i| {
                if (a_elem != b[i]) break :blk false;
            }
            break :blk true;
        }
        if (b_info == .@"struct" and @hasField(B, "items") and @hasField(B, "capacity") and a_info == .array) {
            if (b.items.len != a.len) break :blk false;
            for (b.items, 0..) |b_elem, i| {
                if (b_elem != a[i]) break :blk false;
            }
            break :blk true;
        }

        // Struct with eql method - only call if types are compatible
        // BigInt.eql expects *const BigInt, not i64
        if (a_info == .@"struct" and @hasDecl(A, "eql")) {
            // Check if eql method accepts type B
            const eql_info = @typeInfo(@TypeOf(A.eql));
            if (eql_info == .@"fn" and eql_info.@"fn".params.len >= 2) {
                const expected_param = eql_info.@"fn".params[1].type;
                if (expected_param) |param_type| {
                    // Only call eql if B is the expected type or can be converted
                    if (param_type == B or param_type == *const B) {
                        break :blk a.eql(b);
                    }
                } else {
                    // param_type is null means anytype - call eql directly
                    break :blk a.eql(b);
                }
            }
        }
        if (b_info == .@"struct" and @hasDecl(B, "eql")) {
            const eql_info = @typeInfo(@TypeOf(B.eql));
            if (eql_info == .@"fn" and eql_info.@"fn".params.len >= 2) {
                const expected_param = eql_info.@"fn".params[1].type;
                if (expected_param) |param_type| {
                    if (param_type == A or param_type == *const A) {
                        break :blk b.eql(a);
                    }
                } else {
                    // param_type is null means anytype - call eql directly
                    break :blk b.eql(a);
                }
            }
        }

        // Python class struct with __eq__ method (for custom __eq__ implementations)
        // NOTE: Some Python __eq__ methods take allocator as first arg, some don't
        // The result can be bool, NotImplemented (struct), or error union of either
        if (a_info == .@"struct" and @hasDecl(A, "__eq__")) {
            const eq_info = @typeInfo(@TypeOf(A.__eq__));
            if (eq_info == .@"fn") {
                const params = eq_info.@"fn".params;
                // Check arg count: self + allocator + other = 3, or self + other = 2
                const result = if (params.len == 3)
                    a.__eq__(std.heap.page_allocator, b)
                else
                    a.__eq__(b);
                // Handle error union
                const ResultType = @TypeOf(result);
                if (@typeInfo(ResultType) == .error_union) {
                    const eq_result = result catch break :blk false;
                    // Check if result is bool or NotImplemented (struct)
                    if (@TypeOf(eq_result) == bool) {
                        break :blk eq_result;
                    }
                    // NotImplemented means comparison not supported
                    break :blk false;
                } else if (ResultType == bool) {
                    break :blk result;
                }
                // Result is NotImplemented type or other - treat as not equal
            }
            break :blk false;
        }
        if (b_info == .@"struct" and @hasDecl(B, "__eq__")) {
            const eq_info = @typeInfo(@TypeOf(B.__eq__));
            if (eq_info == .@"fn") {
                const params = eq_info.@"fn".params;
                const result = if (params.len == 3)
                    b.__eq__(std.heap.page_allocator, a)
                else
                    b.__eq__(a);
                const ResultType = @TypeOf(result);
                if (@typeInfo(ResultType) == .error_union) {
                    const eq_result = result catch break :blk false;
                    if (@TypeOf(eq_result) == bool) {
                        break :blk eq_result;
                    }
                    break :blk false;
                } else if (ResultType == bool) {
                    break :blk result;
                }
            }
            break :blk false;
        }

        // Integer comparisons (handle i64 vs comptime_int)
        if ((a_info == .int or a_info == .comptime_int) and (b_info == .int or b_info == .comptime_int)) {
            break :blk a == b;
        }

        // BigInt vs int comparisons
        if (a_info == .@"struct" and @hasDecl(A, "toInt128") and (b_info == .int or b_info == .comptime_int)) {
            // BigInt compared to int - try to convert BigInt to i128
            if (a.toInt128()) |a_val| {
                break :blk a_val == @as(i128, b);
            }
            break :blk false; // BigInt too large to compare with int literal
        }
        if (b_info == .@"struct" and @hasDecl(B, "toInt128") and (a_info == .int or a_info == .comptime_int)) {
            // int compared to BigInt
            if (b.toInt128()) |b_val| {
                break :blk @as(i128, a) == b_val;
            }
            break :blk false;
        }

        // Float comparisons
        if ((a_info == .float or a_info == .comptime_float) and (b_info == .float or b_info == .comptime_float)) {
            break :blk @abs(@as(f64, a) - @as(f64, b)) < 0.0001;
        }

        // Float to int comparisons (for eval() results converted via pyObjectToValue)
        if ((a_info == .float or a_info == .comptime_float) and (b_info == .int or b_info == .comptime_int)) {
            break :blk @abs(@as(f64, a) - @as(f64, @floatFromInt(b))) < 0.0001;
        }
        if ((a_info == .int or a_info == .comptime_int) and (b_info == .float or b_info == .comptime_float)) {
            break :blk @abs(@as(f64, @floatFromInt(a)) - @as(f64, b)) < 0.0001;
        }

        // Bool comparisons
        if (a_info == .bool and b_info == .bool) {
            break :blk a == b;
        }

        // Pointer handling (slices and string literals)
        if (a_info == .pointer) {
            const ptr = a_info.pointer;
            if (ptr.size == .slice and ptr.child == u8) {
                // a is []u8 or []const u8
                if (b_info == .pointer) {
                    if (b_info.pointer.size == .slice and b_info.pointer.child == u8) {
                        // Both are slices - direct comparison
                        break :blk std.mem.eql(u8, a, b);
                    }
                    if (b_info.pointer.size == .one) {
                        // b might be a pointer to array (string literal *const [N:0]u8)
                        const child_info = @typeInfo(b_info.pointer.child);
                        if (child_info == .array and child_info.array.child == u8) {
                            // Coerce to slice and compare
                            const b_slice: []const u8 = b;
                            break :blk std.mem.eql(u8, a, b_slice);
                        }
                    }
                }
                break :blk false;
            }
            if (ptr.size == .slice) {
                if (b_info == .pointer and b_info.pointer.size == .slice) {
                    break :blk std.mem.eql(u8, a, b);
                }
                break :blk false;
            }
            // Check if a is a PyObject* - compare based on type
            if (ptr.size == .one and ptr.child == runtime.PyObject) {
                const a_type = runtime.getTypeId(a);
                if (b_info == .int or b_info == .comptime_int) {
                    // Compare PyObject with integer
                    if (a_type == .int) {
                        const pyint = runtime.PyInt.getValue(a);
                        break :blk pyint == @as(i64, b);
                    } else if (a_type == .bool) {
                        const pybool = runtime.PyBool.getValue(a);
                        break :blk @as(i64, if (pybool) 1 else 0) == @as(i64, b);
                    }
                    break :blk false;
                } else if (b_info == .bool) {
                    // Compare PyObject with bool
                    if (a_type == .bool) {
                        const pybool = runtime.PyBool.getValue(a);
                        break :blk pybool == b;
                    }
                    break :blk false;
                } else if (b_info == .pointer and b_info.pointer.size == .slice) {
                    // Compare PyObject with string slice
                    if (a_type == .string) {
                        const pystr = runtime.PyString.getValue(a);
                        break :blk std.mem.eql(u8, pystr, b);
                    }
                    break :blk false;
                } else if (b_info == .pointer and b_info.pointer.size == .one) {
                    // Check if b is a pointer to array (string literal *const [N:0]u8)
                    const b_child_info = @typeInfo(b_info.pointer.child);
                    if (b_child_info == .array and b_child_info.array.child == u8) {
                        if (a_type == .string) {
                            const pystr = runtime.PyString.getValue(a);
                            const b_slice: []const u8 = b;
                            break :blk std.mem.eql(u8, pystr, b_slice);
                        }
                    }
                    break :blk false;
                } else if (b_info == .array) {
                    const arr = b_info.array;
                    // Compare PyObject (string) with byte array [N]u8
                    if (arr.child == u8 and a_type == .string) {
                        const pystr = runtime.PyString.getValue(a);
                        break :blk std.mem.eql(u8, pystr, &b);
                    }
                    // Compare PyObject (list) with Zig array of strings
                    if (a_type == .list) {
                        const list_len = runtime.PyList.len(a);
                        if (list_len != b.len) break :blk false;
                        for (0..list_len) |i| {
                            const elem = runtime.PyList.getItem(a, i) catch break :blk false;
                            // Get element type
                            const ElemType = @TypeOf(b[0]);
                            if (@typeInfo(ElemType) == .pointer and @typeInfo(ElemType).pointer.child == u8) {
                                // Compare list element with string
                                const elem_type = runtime.getTypeId(elem);
                                if (elem_type == .string) {
                                    const elem_str = runtime.PyString.getValue(elem);
                                    if (!std.mem.eql(u8, elem_str, b[i])) break :blk false;
                                } else {
                                    break :blk false;
                                }
                            } else {
                                break :blk false;
                            }
                        }
                        break :blk true;
                    }
                    break :blk false;
                }
            }
        }

        // Check if b is a PyObject* and a is an integer
        // Use structural check for PyObject (has ob_refcnt and ob_type fields)
        if (b_info == .pointer and b_info.pointer.size == .one) {
            const child = b_info.pointer.child;
            const child_info = @typeInfo(child);
            if (child_info == .@"struct" and @hasField(child, "ob_refcnt") and @hasField(child, "ob_type")) {
                if (a_info == .int or a_info == .comptime_int) {
                    // Compare integer with PyObject
                    const b_type = runtime.getTypeId(b);
                    if (b_type == .int) {
                        const pyint = runtime.PyInt.getValue(b);
                        break :blk @as(i64, @intCast(a)) == pyint;
                    } else if (b_type == .bool) {
                        const pybool = runtime.PyBool.getValue(b);
                        break :blk @as(i64, @intCast(a)) == @as(i64, if (pybool) 1 else 0);
                    }
                    break :blk false;
                }
            }
        }

        // Incompatible types - always false
        break :blk false;
    };

    if (!equal) {
        std.debug.print("AssertionError: {any} != {any}\n", .{ a, b });
        if (runner.global_result) |result| {
            result.addFail("assertEqual failed") catch {};
        }
        @panic("assertEqual failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertTrue(x) - value must be true
pub fn assertTrue(value: bool) void {
    if (!value) {
        std.debug.print("AssertionError: expected True, got False\n", .{});
        if (runner.global_result) |result| {
            result.addFail("assertTrue failed") catch {};
        }
        @panic("assertTrue failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertFalse(x) - value must be false
pub fn assertFalse(value: bool) void {
    if (value) {
        std.debug.print("AssertionError: expected False, got True\n", .{});
        if (runner.global_result) |result| {
            result.addFail("assertFalse failed") catch {};
        }
        @panic("assertFalse failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertIsNone(x) - value must be None/null
pub fn assertIsNone(value: anytype) void {
    const runtime = @import("../runtime.zig");
    const T = @TypeOf(value);
    const is_none = switch (@typeInfo(T)) {
        .optional => value == null,
        .pointer => |ptr| blk: {
            // Check if it's a PyObject pointer
            if (ptr.size == .one and ptr.child == runtime.PyObject) {
                break :blk runtime.getTypeId(value) == .none;
            }
            // Check if it's a PyMatch pointer (has is_match field)
            if (ptr.size == .one and @hasField(ptr.child, "is_match")) {
                break :blk !value.is_match;
            }
            // For slices, check if empty
            if (ptr.size != .one) {
                break :blk value.len == 0;
            }
            break :blk false;
        },
        else => false,
    };

    if (!is_none) {
        std.debug.print("AssertionError: expected None\n", .{});
        if (runner.global_result) |result| {
            result.addFail("assertIsNone failed") catch {};
        }
        @panic("assertIsNone failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertGreater(a, b) - a > b
pub fn assertGreater(a: anytype, b: anytype) void {
    if (!(a > b)) {
        std.debug.print("AssertionError: {any} is not greater than {any}\n", .{ a, b });
        if (runner.global_result) |result| {
            result.addFail("assertGreater failed") catch {};
        }
        @panic("assertGreater failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertLess(a, b) - a < b
pub fn assertLess(a: anytype, b: anytype) void {
    if (!(a < b)) {
        std.debug.print("AssertionError: {any} is not less than {any}\n", .{ a, b });
        if (runner.global_result) |result| {
            result.addFail("assertLess failed") catch {};
        }
        @panic("assertLess failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertGreaterEqual(a, b) - a >= b
pub fn assertGreaterEqual(a: anytype, b: anytype) void {
    if (!(a >= b)) {
        std.debug.print("AssertionError: {any} is not >= {any}\n", .{ a, b });
        if (runner.global_result) |result| {
            result.addFail("assertGreaterEqual failed") catch {};
        }
        @panic("assertGreaterEqual failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertLessEqual(a, b) - a <= b
pub fn assertLessEqual(a: anytype, b: anytype) void {
    if (!(a <= b)) {
        std.debug.print("AssertionError: {any} is not <= {any}\n", .{ a, b });
        if (runner.global_result) |result| {
            result.addFail("assertLessEqual failed") catch {};
        }
        @panic("assertLessEqual failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertNotEqual(a, b) - values must NOT be equal
pub fn assertNotEqual(a: anytype, b: anytype) void {
    const equal = switch (@typeInfo(@TypeOf(a))) {
        .int, .comptime_int => a == b,
        .float, .comptime_float => @abs(a - b) < 0.0001,
        .bool => a == b,
        .pointer => |ptr| blk: {
            if (ptr.size == .slice) {
                break :blk std.mem.eql(u8, a, b);
            }
            break :blk a == b;
        },
        .array => std.mem.eql(@TypeOf(a[0]), &a, &b),
        else => a == b,
    };

    if (equal) {
        std.debug.print("AssertionError: {any} == {any} (expected not equal)\n", .{ a, b });
        if (runner.global_result) |result| {
            result.addFail("assertNotEqual failed") catch {};
        }
        @panic("assertNotEqual failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertIs(a, b) - pointer identity check (a is b)
pub fn assertIs(a: anytype, b: anytype) void {
    const runtime = @import("../runtime.zig");
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const same = blk: {
        const a_info = @typeInfo(A);
        const b_info = @typeInfo(B);

        // Pointers - compare addresses
        if (a_info == .pointer and b_info == .pointer) {
            break :blk @intFromPtr(a) == @intFromPtr(b);
        }

        // Same primitive type - compare values (for bool, int, etc.)
        if (A == B) {
            break :blk a == b;
        }

        // PyObject compared with bool - extract bool from PyObject
        // This handles eval("True") is True, eval("False") is False
        if (A == *runtime.PyObject and B == bool) {
            if (runtime.PyBool_Check(a)) {
                // Extract bool value from PyBoolObject
                const bool_obj: *runtime.PyBoolObject = @ptrCast(@alignCast(a));
                const py_bool = bool_obj.ob_digit != 0;
                break :blk py_bool == b;
            }
            break :blk false;
        }
        if (B == *runtime.PyObject and A == bool) {
            if (runtime.PyBool_Check(b)) {
                // Extract bool value from PyBoolObject
                const bool_obj: *runtime.PyBoolObject = @ptrCast(@alignCast(b));
                const py_bool = bool_obj.ob_digit != 0;
                break :blk a == py_bool;
            }
            break :blk false;
        }

        // Different types - can never be the same object
        break :blk false;
    };

    if (!same) {
        std.debug.print("AssertionError: not the same object (expected identity)\n", .{});
        if (runner.global_result) |result| {
            result.addFail("assertIs failed") catch {};
        }
        @panic("assertIs failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertTypeIs(actual_type, expected_type) - compile-time type comparison
/// Used for type(x) is int style assertions
pub fn assertTypeIs(comptime actual_type: type, comptime expected_type: type) void {
    // Check for type equivalence, considering comptime types
    const matches = comptime blk: {
        if (actual_type == expected_type) break :blk true;
        // comptime_int is compatible with i64 (Python int)
        if (expected_type == i64 and actual_type == comptime_int) break :blk true;
        if (actual_type == i64 and expected_type == comptime_int) break :blk true;
        // comptime_float is compatible with f64 (Python float)
        if (expected_type == f64 and actual_type == comptime_float) break :blk true;
        if (actual_type == f64 and expected_type == comptime_float) break :blk true;
        break :blk false;
    };

    if (matches) {
        if (runner.global_result) |result| {
            result.addPass();
        }
    } else {
        std.debug.print("AssertionError: type mismatch (expected {s}, got {s})\n", .{ @typeName(expected_type), @typeName(actual_type) });
        if (runner.global_result) |result| {
            result.addFail("assertTypeIs failed") catch {};
        }
        @panic("assertTypeIs failed");
    }
}

/// Assertion: assertTypeIsStr(value, type_name_str) - runtime type check using string
/// Used for assertIs(type(x), dict) style assertions where dict is a collection type
pub fn assertTypeIsStr(value: anytype, comptime expected_type_str: []const u8) void {
    const T = @TypeOf(value);
    const type_name = @typeName(T);

    // Check if actual type matches expected
    const matches = comptime blk: {
        // dict -> StringHashMap or PyDict
        if (std.mem.eql(u8, expected_type_str, "dict")) {
            if (std.mem.indexOf(u8, type_name, "StringHashMap") != null) break :blk true;
            if (std.mem.indexOf(u8, type_name, "PyDict") != null) break :blk true;
            if (std.mem.indexOf(u8, type_name, "HashMap") != null) break :blk true;
        }
        // list -> ArrayList or PyList
        if (std.mem.eql(u8, expected_type_str, "list")) {
            if (std.mem.indexOf(u8, type_name, "ArrayList") != null) break :blk true;
            if (std.mem.indexOf(u8, type_name, "PyList") != null) break :blk true;
        }
        // set -> AutoHashMap or PySet
        if (std.mem.eql(u8, expected_type_str, "set")) {
            if (std.mem.indexOf(u8, type_name, "AutoHashMap") != null) break :blk true;
            if (std.mem.indexOf(u8, type_name, "PySet") != null) break :blk true;
        }
        // tuple -> struct with indexed fields
        if (std.mem.eql(u8, expected_type_str, "tuple")) {
            if (std.mem.indexOf(u8, type_name, "struct") != null) break :blk true;
        }
        // bytes -> []const u8
        if (std.mem.eql(u8, expected_type_str, "bytes")) {
            if (T == []const u8 or T == []u8) break :blk true;
        }
        break :blk false;
    };

    if (matches) {
        if (runner.global_result) |result| {
            result.addPass();
        }
    } else {
        std.debug.print("AssertionError: type mismatch (expected {s}, got {s})\n", .{ expected_type_str, type_name });
        if (runner.global_result) |result| {
            result.addFail("assertTypeIsStr failed") catch {};
        }
        @panic("assertTypeIsStr failed");
    }
}

/// Assertion: assertIsNot(a, b) - pointer identity check (a is not b)
pub fn assertIsNot(a: anytype, b: anytype) void {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const same = blk: {
        const a_info = @typeInfo(A);
        const b_info = @typeInfo(B);

        // Pointers - compare addresses
        if (a_info == .pointer and b_info == .pointer) {
            break :blk @intFromPtr(a) == @intFromPtr(b);
        }

        // Same primitive type - compare values
        if (A == B) {
            break :blk a == b;
        }

        // Different types - can never be the same object
        break :blk false;
    };

    if (same) {
        std.debug.print("AssertionError: same object (expected different identity)\n", .{});
        if (runner.global_result) |result| {
            result.addFail("assertIsNot failed") catch {};
        }
        @panic("assertIsNot failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertIsNotNone(x) - value must not be None/null
pub fn assertIsNotNone(value: anytype) void {
    const T = @TypeOf(value);
    const is_none = switch (@typeInfo(T)) {
        .optional => value == null,
        .pointer => |ptr| blk: {
            // Check if it's a PyMatch pointer (has is_match field)
            if (ptr.size == .one and @hasField(ptr.child, "is_match")) {
                break :blk !value.is_match;
            }
            // For slices, check if empty
            if (ptr.size != .one) {
                break :blk value.len == 0;
            }
            break :blk false;
        },
        else => false,
    };

    if (is_none) {
        std.debug.print("AssertionError: expected not None\n", .{});
        if (runner.global_result) |result| {
            result.addFail("assertIsNotNone failed") catch {};
        }
        @panic("assertIsNotNone failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Helper to check if a type is string-like ([]const u8, *const [N]u8, *const [N:0]u8)
/// Must be called in a comptime context
inline fn isStringLikeInline(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .pointer) return false;
    const ptr = info.pointer;
    // Slice of u8
    if (ptr.size == .slice and ptr.child == u8) return true;
    // Pointer to array of u8
    if (ptr.size == .one) {
        const child_info = @typeInfo(ptr.child);
        if (child_info == .array and child_info.array.child == u8) return true;
    }
    return false;
}

/// Assertion: assertIn(item, container) - item must be in container
/// For string-in-string checks, this performs substring search
pub fn assertIn(item: anytype, container: anytype) void {
    const ItemType = @TypeOf(item);
    const ContainerType = @TypeOf(container);

    // Check if both are string-like types - use substring search
    // Inline the check to ensure comptime evaluation
    const is_string_in_string = comptime blk: {
        const item_is_str = isStringLikeInline(ItemType);
        const container_is_str = isStringLikeInline(ContainerType);
        break :blk item_is_str and container_is_str;
    };

    const found = if (comptime is_string_in_string) string_blk: {
        // Coerce pointer types to slices for std.mem.indexOf
        const container_slice: []const u8 = container;
        const item_slice: []const u8 = item;
        break :string_blk std.mem.indexOf(u8, container_slice, item_slice) != null;
    } else elem_blk: {
        // Element search for other containers
        // Handle different container types at comptime
        const container_info = @typeInfo(ContainerType);

        // Check for struct types (ArrayList, HashMap, etc.)
        if (comptime container_info == .@"struct") {
            // ArrayList: use .items slice
            if (comptime @hasField(ContainerType, "items")) {
                for (container.items) |elem| {
                    if (std.meta.eql(elem, item)) break :elem_blk true;
                }
                break :elem_blk false;
            }
            // HashMap: check keys using contains()
            else if (comptime @hasDecl(ContainerType, "contains")) {
                // For float key hashmaps (u64 bit representation), convert item to bits
                // Get the key type from the contains() function signature
                const contains_info = @typeInfo(@TypeOf(ContainerType.contains));
                const KeyType = if (contains_info == .@"fn" and contains_info.@"fn".params.len >= 2)
                    contains_info.@"fn".params[1].type orelse void
                else
                    void;
                if (comptime @TypeOf(item) == f64 and KeyType == u64) {
                    break :elem_blk container.contains(@bitCast(item));
                } else {
                    // Try direct contains (may fail at compile time if types don't match)
                    break :elem_blk container.contains(item);
                }
            }
            // Tuple: use inline for
            else if (comptime container_info.@"struct".is_tuple) {
                inline for (container) |elem| {
                    if (std.meta.eql(elem, item)) break :elem_blk true;
                }
                break :elem_blk false;
            }
            // User-defined class with __contains__ method (Python dunder)
            else if (comptime @hasDecl(ContainerType, "__contains__")) {
                break :elem_blk container.__contains__(item);
            }
            // Fallback for other structs - just return false (item not found)
            else {
                break :elem_blk false;
            }
        }
        // Pointer types - cannot iterate directly, return false
        else if (comptime container_info == .pointer) {
            // For opaque pointers (like *runtime.PyObject), we can't determine membership
            // Just return false and let the test fail gracefully
            break :elem_blk false;
        }
        // Arrays and slices - iterate directly
        else {
            for (container) |elem| {
                if (std.meta.eql(elem, item)) break :elem_blk true;
            }
            break :elem_blk false;
        }
    };

    if (!found) {
        std.debug.print("AssertionError: {any} not in container\n", .{item});
        if (runner.global_result) |result| {
            result.addFail("assertIn failed") catch {};
        }
        @panic("assertIn failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertNotIn(item, container) - item must not be in container
/// For string-in-string checks, this performs substring search
pub fn assertNotIn(item: anytype, container: anytype) void {
    const ItemType = @TypeOf(item);
    const ContainerType = @TypeOf(container);

    // Check if both are string-like types - use substring search
    // Inline the check to ensure comptime evaluation
    const is_string_in_string = comptime blk: {
        const item_is_str = isStringLikeInline(ItemType);
        const container_is_str = isStringLikeInline(ContainerType);
        break :blk item_is_str and container_is_str;
    };

    const found = if (comptime is_string_in_string) string_blk: {
        // Coerce pointer types to slices for std.mem.indexOf
        const container_slice: []const u8 = container;
        const item_slice: []const u8 = item;
        break :string_blk std.mem.indexOf(u8, container_slice, item_slice) != null;
    } else elem_blk: {
        // Element search for other containers
        // Handle different container types at comptime
        const container_info = @typeInfo(ContainerType);

        // Check for struct types (ArrayList, HashMap, etc.)
        if (comptime container_info == .@"struct") {
            // ArrayList: use .items slice
            if (comptime @hasField(ContainerType, "items")) {
                for (container.items) |elem| {
                    if (std.meta.eql(elem, item)) break :elem_blk true;
                }
                break :elem_blk false;
            }
            // HashMap: check keys using contains()
            else if (comptime @hasDecl(ContainerType, "contains")) {
                // For float key hashmaps (u64 bit representation), convert item to bits
                // Get the key type from the contains() function signature
                const contains_info = @typeInfo(@TypeOf(ContainerType.contains));
                const KeyType = if (contains_info == .@"fn" and contains_info.@"fn".params.len >= 2)
                    contains_info.@"fn".params[1].type orelse void
                else
                    void;
                if (comptime @TypeOf(item) == f64 and KeyType == u64) {
                    break :elem_blk container.contains(@bitCast(item));
                } else {
                    // Try direct contains (may fail at compile time if types don't match)
                    break :elem_blk container.contains(item);
                }
            }
            // Tuple: use inline for
            else if (comptime container_info.@"struct".is_tuple) {
                inline for (container) |elem| {
                    if (std.meta.eql(elem, item)) break :elem_blk true;
                }
                break :elem_blk false;
            }
            // User-defined class with __contains__ method (Python dunder)
            else if (comptime @hasDecl(ContainerType, "__contains__")) {
                break :elem_blk container.__contains__(item);
            }
            // Fallback for other structs - just return false (item not found)
            else {
                break :elem_blk false;
            }
        }
        // Pointer types - cannot iterate directly, return false
        else if (comptime container_info == .pointer) {
            // For opaque pointers (like *runtime.PyObject), we can't determine membership
            // Just return false and let the test fail gracefully
            break :elem_blk false;
        }
        // Arrays and slices - iterate directly
        else {
            for (container) |elem| {
                if (std.meta.eql(elem, item)) break :elem_blk true;
            }
            break :elem_blk false;
        }
    };

    if (found) {
        std.debug.print("AssertionError: {any} unexpectedly in container\n", .{item});
        if (runner.global_result) |result| {
            result.addFail("assertNotIn failed") catch {};
        }
        @panic("assertNotIn failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertHasAttr(obj, attr_name) - check if object has attribute
/// Note: In AOT compilation, we use @hasField to check struct fields at comptime
pub fn assertHasAttr(obj: anytype, attr_name: []const u8) void {
    const T = @TypeOf(obj);
    const type_info = @typeInfo(T);

    // For structs, check if field exists at comptime
    const has_attr = switch (type_info) {
        .@"struct" => |s| blk: {
            inline for (s.fields) |field| {
                if (std.mem.eql(u8, field.name, attr_name)) {
                    break :blk true;
                }
            }
            break :blk false;
        },
        .pointer => |ptr| inner_blk: {
            if (ptr.size == .one) {
                const child_info = @typeInfo(ptr.child);
                if (child_info == .@"struct") {
                    inline for (child_info.@"struct".fields) |field| {
                        if (std.mem.eql(u8, field.name, attr_name)) {
                            break :inner_blk true;
                        }
                    }
                }
            }
            break :inner_blk false;
        },
        else => false,
    };

    if (!has_attr) {
        std.debug.print("AssertionError: object has no attribute '{s}'\n", .{attr_name});
        if (runner.global_result) |result| {
            result.addFail("assertHasAttr failed") catch {};
        }
        @panic("assertHasAttr failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertNotHasAttr(obj, attr_name) - check if object does NOT have attribute
pub fn assertNotHasAttr(obj: anytype, attr_name: []const u8) void {
    const T = @TypeOf(obj);
    const type_info = @typeInfo(T);

    // For structs, check if field exists at comptime
    const has_attr = switch (type_info) {
        .@"struct" => |s| blk: {
            inline for (s.fields) |field| {
                if (std.mem.eql(u8, field.name, attr_name)) {
                    break :blk true;
                }
            }
            break :blk false;
        },
        .pointer => |ptr| inner_blk: {
            if (ptr.size == .one) {
                const child_info = @typeInfo(ptr.child);
                if (child_info == .@"struct") {
                    inline for (child_info.@"struct".fields) |field| {
                        if (std.mem.eql(u8, field.name, attr_name)) {
                            break :inner_blk true;
                        }
                    }
                }
            }
            break :inner_blk false;
        },
        else => false,
    };

    if (has_attr) {
        std.debug.print("AssertionError: object unexpectedly has attribute '{s}'\n", .{attr_name});
        if (runner.global_result) |result| {
            result.addFail("assertNotHasAttr failed") catch {};
        }
        @panic("assertNotHasAttr failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertStartsWith(text, prefix) - string must start with prefix
pub fn assertStartsWith(text: []const u8, prefix: []const u8) void {
    if (!std.mem.startsWith(u8, text, prefix)) {
        std.debug.print("AssertionError: '{s}' does not start with '{s}'\n", .{ text, prefix });
        if (runner.global_result) |result| {
            result.addFail("assertStartsWith failed") catch {};
        }
        @panic("assertStartsWith failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertNotStartsWith(text, prefix) - string must not start with prefix
pub fn assertNotStartsWith(text: []const u8, prefix: []const u8) void {
    if (std.mem.startsWith(u8, text, prefix)) {
        std.debug.print("AssertionError: '{s}' starts with '{s}'\n", .{ text, prefix });
        if (runner.global_result) |result| {
            result.addFail("assertNotStartsWith failed") catch {};
        }
        @panic("assertNotStartsWith failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertEndsWith(text, suffix) - string must end with suffix
pub fn assertEndsWith(text: []const u8, suffix: []const u8) void {
    if (!std.mem.endsWith(u8, text, suffix)) {
        std.debug.print("AssertionError: '{s}' does not end with '{s}'\n", .{ text, suffix });
        if (runner.global_result) |result| {
            result.addFail("assertEndsWith failed") catch {};
        }
        @panic("assertEndsWith failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertAlmostEqual(a, b) - floats must be equal within 7 decimal places
pub fn assertAlmostEqual(a: anytype, b: anytype) void {
    const diff = @abs(a - b);
    const tolerance: f64 = 0.0000001;

    if (diff >= tolerance) {
        std.debug.print("AssertionError: {d} !~= {d} (diff={d})\n", .{ a, b, diff });
        if (runner.global_result) |result| {
            result.addFail("assertAlmostEqual failed") catch {};
        }
        @panic("assertAlmostEqual failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertNotAlmostEqual(a, b) - floats must NOT be equal within 7 decimal places
pub fn assertNotAlmostEqual(a: anytype, b: anytype) void {
    const diff = @abs(a - b);
    const tolerance: f64 = 0.0000001;

    if (diff < tolerance) {
        std.debug.print("AssertionError: {d} ~= {d} (expected not almost equal)\n", .{ a, b });
        if (runner.global_result) |result| {
            result.addFail("assertNotAlmostEqual failed") catch {};
        }
        @panic("assertNotAlmostEqual failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertFloatsAreIdentical(a, b) - floats must be identical (same value and same sign for zeros)
/// This is stricter than assertEqual - it distinguishes between +0.0 and -0.0
pub fn assertFloatsAreIdentical(a: f64, b: f64) void {
    // Check for identical values including NaN and signed zeros
    // Two floats are identical if their bit representations are equal
    const a_bits = @as(u64, @bitCast(a));
    const b_bits = @as(u64, @bitCast(b));

    if (a_bits != b_bits) {
        std.debug.print("AssertionError: {d} is not identical to {d}\n", .{ a, b });
        if (runner.global_result) |result| {
            result.addFail("assertFloatsAreIdentical failed") catch {};
        }
        @panic("assertFloatsAreIdentical failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}
