/// metal0 unittest assertions - type and identity assertions
const std = @import("std");
const runner = @import("../../unittest/runner.zig");
const runtime = @import("../../../runtime.zig");

/// Assertion: assertIs(a, b) - pointer identity check (a is b)
/// Python's `is` operator checks object identity (same memory address)
pub fn assertIs(a: anytype, b: anytype) !void {
    _ = runtime;
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const same = blk: {
        const a_info = @typeInfo(A);
        const b_info = @typeInfo(B);

        // Pointer types: compare addresses directly
        if (a_info == .pointer and b_info == .pointer) {
            break :blk @intFromPtr(a) == @intFromPtr(b);
        }

        // Same type comparison
        if (A == B) {
            // For primitive types, identity == equality (they're value types)
            if (a_info == .int or a_info == .float or a_info == .bool or
                a_info == .comptime_int or a_info == .comptime_float or
                a_info == .null or a_info == .void or a_info == .@"enum")
            {
                break :blk a == b;
            }
            // For single pointer type (caught above should handle, but be safe)
            if (a_info == .pointer) {
                break :blk @intFromPtr(a) == @intFromPtr(b);
            }
            // For optional pointers, compare the underlying pointers
            if (a_info == .optional) {
                const child_info = @typeInfo(a_info.optional.child);
                if (child_info == .pointer) {
                    if (a == null and b == null) break :blk true;
                    if (a == null or b == null) break :blk false;
                    break :blk @intFromPtr(a.?) == @intFromPtr(b.?);
                }
            }
            // For structs/unions containing an 'object' or pointer field, compare those
            if (a_info == .@"struct" and @hasField(A, "object")) {
                const obj_a = @field(a, "object");
                const obj_b = @field(b, "object");
                if (@typeInfo(@TypeOf(obj_a)) == .pointer) {
                    break :blk @intFromPtr(obj_a) == @intFromPtr(obj_b);
                }
            }
            // For unions (like PyValue), use direct equality which compares tag + value
            // This is closer to identity for value types within the union
            if (a_info == .@"union") {
                break :blk a == b;
            }
            // Fallback: use direct comparison (better than .eql() which converts to PyValue)
            break :blk a == b;
        }

        if (A == *runtime.PyObject and B == bool) {
            if (runtime.PyBool_Check(a)) {
                const bool_obj: *runtime.PyBoolObject = @ptrCast(@alignCast(a));
                const py_bool = bool_obj.getValue();
                break :blk py_bool == b;
            }
            break :blk false;
        }
        if (B == *runtime.PyObject and A == bool) {
            if (runtime.PyBool_Check(b)) {
                const bool_obj: *runtime.PyBoolObject = @ptrCast(@alignCast(b));
                const py_bool = bool_obj.getValue();
                break :blk a == py_bool;
            }
            break :blk false;
        }

        if (@typeInfo(A) == .@"union" and @hasField(A, "bool") and B == bool) {
            if (a == .bool) {
                break :blk a.bool == b;
            }
            break :blk false;
        }
        if (@typeInfo(B) == .@"union" and @hasField(B, "bool") and A == bool) {
            if (b == .bool) {
                break :blk a == b.bool;
            }
            break :blk false;
        }

        break :blk false;
    };

    if (!same) {
        std.debug.print("AssertionError: not the same object (expected identity)\n", .{});
        if (runner.global_result) |result| {
            result.addFail("assertIs failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertTypeIs(actual_type, expected_type) - compile-time type comparison
pub fn assertTypeIs(comptime actual_type: type, comptime expected_type: type) !void {
    const matches = comptime blk: {
        if (actual_type == expected_type) break :blk true;
        if (expected_type == i64 and actual_type == comptime_int) break :blk true;
        if (actual_type == i64 and expected_type == comptime_int) break :blk true;
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
        return error.AssertionFailed;
    }
}

/// Assertion: assertTypeIsStr(value, type_name_str) - runtime type check using string
pub fn assertTypeIsStr(value: anytype, comptime expected_type_str: []const u8) !void {
    const T = @TypeOf(value);
    const type_name = @typeName(T);

    const matches = comptime blk: {
        if (std.mem.eql(u8, expected_type_str, "dict")) {
            if (std.mem.indexOf(u8, type_name, "StringHashMap") != null) break :blk true;
            if (std.mem.indexOf(u8, type_name, "PyDict") != null) break :blk true;
            if (std.mem.indexOf(u8, type_name, "HashMap") != null) break :blk true;
        }
        if (std.mem.eql(u8, expected_type_str, "list")) {
            if (std.mem.indexOf(u8, type_name, "ArrayList") != null) break :blk true;
            if (std.mem.indexOf(u8, type_name, "PyList") != null) break :blk true;
        }
        if (std.mem.eql(u8, expected_type_str, "set")) {
            if (std.mem.indexOf(u8, type_name, "AutoHashMap") != null) break :blk true;
            if (std.mem.indexOf(u8, type_name, "PySet") != null) break :blk true;
        }
        if (std.mem.eql(u8, expected_type_str, "tuple")) {
            if (std.mem.indexOf(u8, type_name, "struct") != null) break :blk true;
        }
        if (std.mem.eql(u8, expected_type_str, "bytes")) {
            if (T == []const u8 or T == []u8) break :blk true;
        }
        const class_name = extractClassName(type_name);
        if (std.mem.eql(u8, expected_type_str, class_name)) break :blk true;
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
        return error.AssertionFailed;
    }
}

/// Extract the class name from a full qualified Zig type name
fn extractClassName(comptime type_name: []const u8) []const u8 {
    var name = type_name;
    if (name.len > 0 and name[0] == '*') {
        name = name[1..];
    }
    if (name.len >= 6 and std.mem.eql(u8, name[0..6], "const ")) {
        name = name[6..];
    }
    var last_dot: usize = 0;
    for (name, 0..) |c, i| {
        if (c == '.') last_dot = i + 1;
    }
    if (last_dot > 0 and last_dot < name.len) {
        return name[last_dot..];
    }
    return name;
}

/// Assertion: assertIsNot(a, b) - pointer identity check (a is not b)
pub fn assertIsNot(a: anytype, b: anytype) !void {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const same = blk: {
        const a_info = @typeInfo(A);
        const b_info = @typeInfo(B);

        if (a_info == .pointer and b_info == .pointer) {
            break :blk @intFromPtr(a) == @intFromPtr(b);
        }

        if (A == B) {
            const type_info = @typeInfo(A);
            if (type_info == .@"struct") {
                break :blk @intFromPtr(&a) == @intFromPtr(&b);
            }
            break :blk a == b;
        }

        break :blk false;
    };

    if (same) {
        std.debug.print("AssertionError: same object (expected different identity)\n", .{});
        if (runner.global_result) |result| {
            result.addFail("assertIsNot failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertIsNotNone(x) - value must not be None/null
pub fn assertIsNotNone(value: anytype) !void {
    const T = @TypeOf(value);
    const is_none = switch (@typeInfo(T)) {
        .null => true,
        .optional => value == null,
        .pointer => |ptr| blk: {
            if (ptr.size == .one and @hasField(ptr.child, "is_match")) {
                break :blk !value.is_match;
            }
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
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}
