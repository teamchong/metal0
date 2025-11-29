/// metal0 unittest assertions - basic comparison assertions
const std = @import("std");
const runner = @import("runner.zig");

/// Assertion: assertEqual(a, b) - values must be equal
pub fn assertEqual(a: anytype, b: anytype) void {
    const runtime = @import("../runtime.zig");
    const A = @TypeOf(a);
    const B = @TypeOf(b);

    const equal = blk: {
        const a_info = @typeInfo(A);
        const b_info = @typeInfo(B);

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
            break :blk a == b;
        }

        // Integer comparisons (handle i64 vs comptime_int)
        if ((a_info == .int or a_info == .comptime_int) and (b_info == .int or b_info == .comptime_int)) {
            break :blk a == b;
        }

        // Float comparisons
        if ((a_info == .float or a_info == .comptime_float) and (b_info == .float or b_info == .comptime_float)) {
            break :blk @abs(@as(f64, a) - @as(f64, b)) < 0.0001;
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
                if (b_info == .int or b_info == .comptime_int) {
                    // Compare PyObject with integer
                    if (a.type_id == .int) {
                        const pyint = runtime.PyInt.getValue(a);
                        break :blk pyint == @as(i64, b);
                    } else if (a.type_id == .bool) {
                        const pybool = runtime.PyBool.getValue(a);
                        break :blk @as(i64, if (pybool) 1 else 0) == @as(i64, b);
                    }
                    break :blk false;
                } else if (b_info == .bool) {
                    // Compare PyObject with bool
                    if (a.type_id == .bool) {
                        const pybool = runtime.PyBool.getValue(a);
                        break :blk pybool == b;
                    }
                    break :blk false;
                } else if (b_info == .pointer and b_info.pointer.size == .slice) {
                    // Compare PyObject with string slice
                    if (a.type_id == .string) {
                        const pystr: *runtime.pystring.PyString = @ptrCast(@alignCast(a.data));
                        break :blk std.mem.eql(u8, pystr.data, b);
                    }
                    break :blk false;
                } else if (b_info == .pointer and b_info.pointer.size == .one) {
                    // Check if b is a pointer to array (string literal *const [N:0]u8)
                    const b_child_info = @typeInfo(b_info.pointer.child);
                    if (b_child_info == .array and b_child_info.array.child == u8) {
                        if (a.type_id == .string) {
                            const pystr: *runtime.pystring.PyString = @ptrCast(@alignCast(a.data));
                            const b_slice: []const u8 = b;
                            break :blk std.mem.eql(u8, pystr.data, b_slice);
                        }
                    }
                    break :blk false;
                } else if (b_info == .array) {
                    const arr = b_info.array;
                    // Compare PyObject (string) with byte array [N]u8
                    if (arr.child == u8 and a.type_id == .string) {
                        const pystr: *runtime.pystring.PyString = @ptrCast(@alignCast(a.data));
                        break :blk std.mem.eql(u8, pystr.data, &b);
                    }
                    // Compare PyObject (list) with Zig array of strings
                    if (a.type_id == .list) {
                        const list_len = runtime.PyList.len(a);
                        if (list_len != b.len) break :blk false;
                        for (0..list_len) |i| {
                            const elem = runtime.PyList.getItem(a, i) catch break :blk false;
                            // Get element type
                            const ElemType = @TypeOf(b[0]);
                            if (@typeInfo(ElemType) == .pointer and @typeInfo(ElemType).pointer.child == u8) {
                                // Compare list element with string
                                if (elem.type_id == .string) {
                                    const pystr: *runtime.pystring.PyString = @ptrCast(@alignCast(elem.data));
                                    if (!std.mem.eql(u8, pystr.data, b[i])) break :blk false;
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
                break :blk value.type_id == .none;
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
        for (container) |elem| {
            if (elem == item) break :elem_blk true;
        }
        break :elem_blk false;
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
        for (container) |elem| {
            if (elem == item) break :elem_blk true;
        }
        break :elem_blk false;
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
