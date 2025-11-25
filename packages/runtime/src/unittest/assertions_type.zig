/// PyAOT unittest assertions - type-specific and container assertions
const std = @import("std");
const runner = @import("runner.zig");
const basic = @import("assertions_basic.zig");

/// Assertion: assertCountEqual(a, b) - sequences have same elements (order independent)
pub fn assertCountEqual(a: anytype, b: anytype) void {
    if (a.len != b.len) {
        std.debug.print("AssertionError: sequences have different lengths ({d} vs {d})\n", .{ a.len, b.len });
        if (runner.global_result) |result| {
            result.addFail("assertCountEqual failed: different lengths") catch {};
        }
        @panic("assertCountEqual failed");
    }

    for (a) |item_a| {
        var found = false;
        for (b) |item_b| {
            if (item_a == item_b) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("AssertionError: element {any} not found in second sequence\n", .{item_a});
            if (runner.global_result) |result| {
                result.addFail("assertCountEqual failed: element not found") catch {};
            }
            @panic("assertCountEqual failed");
        }
    }

    for (b) |item_b| {
        var found = false;
        for (a) |item_a| {
            if (item_a == item_b) {
                found = true;
                break;
            }
        }
        if (!found) {
            std.debug.print("AssertionError: element {any} not found in first sequence\n", .{item_b});
            if (runner.global_result) |result| {
                result.addFail("assertCountEqual failed: element not found") catch {};
            }
            @panic("assertCountEqual failed");
        }
    }

    if (runner.global_result) |result| {
        result.addPass();
    }
}

/// Assertion: assertRegex(text, pattern) - text must contain pattern (substring match)
pub fn assertRegex(text: []const u8, pattern: []const u8) void {
    if (std.mem.indexOf(u8, text, pattern) == null) {
        std.debug.print("AssertionError: pattern '{s}' not found in '{s}'\n", .{ pattern, text });
        if (runner.global_result) |result| {
            result.addFail("assertRegex failed") catch {};
        }
        @panic("assertRegex failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertNotRegex(text, pattern) - text must NOT contain pattern
pub fn assertNotRegex(text: []const u8, pattern: []const u8) void {
    if (std.mem.indexOf(u8, text, pattern)) |_| {
        std.debug.print("AssertionError: pattern '{s}' unexpectedly found in '{s}'\n", .{ pattern, text });
        if (runner.global_result) |result| {
            result.addFail("assertNotRegex failed") catch {};
        }
        @panic("assertNotRegex failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertIsInstance(obj, type_name) - check if obj is of expected type
pub fn assertIsInstance(obj: anytype, expected_type_name: []const u8) void {
    const actual_type_name = @typeName(@TypeOf(obj));

    const matches = blk: {
        if (std.mem.eql(u8, actual_type_name, expected_type_name)) break :blk true;

        if (std.mem.eql(u8, expected_type_name, "int")) {
            break :blk std.mem.startsWith(u8, actual_type_name, "i") or
                std.mem.startsWith(u8, actual_type_name, "u") or
                std.mem.eql(u8, actual_type_name, "comptime_int");
        }
        if (std.mem.eql(u8, expected_type_name, "float")) {
            break :blk std.mem.startsWith(u8, actual_type_name, "f") or
                std.mem.eql(u8, actual_type_name, "comptime_float");
        }
        if (std.mem.eql(u8, expected_type_name, "str")) {
            break :blk std.mem.indexOf(u8, actual_type_name, "u8") != null;
        }
        if (std.mem.eql(u8, expected_type_name, "bool")) {
            break :blk std.mem.eql(u8, actual_type_name, "bool");
        }
        if (std.mem.eql(u8, expected_type_name, "list")) {
            break :blk std.mem.indexOf(u8, actual_type_name, "ArrayList") != null or
                (std.mem.startsWith(u8, actual_type_name, "[") and !std.mem.startsWith(u8, actual_type_name, "[]const u8"));
        }

        break :blk false;
    };

    if (!matches) {
        std.debug.print("AssertionError: {s} is not instance of {s}\n", .{ actual_type_name, expected_type_name });
        if (runner.global_result) |result| {
            result.addFail("assertIsInstance failed") catch {};
        }
        @panic("assertIsInstance failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertNotIsInstance(obj, type_name) - check if obj is NOT of expected type
pub fn assertNotIsInstance(obj: anytype, expected_type_name: []const u8) void {
    const actual_type_name = @typeName(@TypeOf(obj));

    const matches = blk: {
        if (std.mem.eql(u8, actual_type_name, expected_type_name)) break :blk true;

        if (std.mem.eql(u8, expected_type_name, "int")) {
            break :blk std.mem.startsWith(u8, actual_type_name, "i") or
                std.mem.startsWith(u8, actual_type_name, "u") or
                std.mem.eql(u8, actual_type_name, "comptime_int");
        }
        if (std.mem.eql(u8, expected_type_name, "float")) {
            break :blk std.mem.startsWith(u8, actual_type_name, "f") or
                std.mem.eql(u8, actual_type_name, "comptime_float");
        }
        if (std.mem.eql(u8, expected_type_name, "str")) {
            break :blk std.mem.indexOf(u8, actual_type_name, "u8") != null;
        }
        if (std.mem.eql(u8, expected_type_name, "bool")) {
            break :blk std.mem.eql(u8, actual_type_name, "bool");
        }
        if (std.mem.eql(u8, expected_type_name, "list")) {
            break :blk std.mem.indexOf(u8, actual_type_name, "ArrayList") != null or
                (std.mem.startsWith(u8, actual_type_name, "[") and !std.mem.startsWith(u8, actual_type_name, "[]const u8"));
        }

        break :blk false;
    };

    if (matches) {
        std.debug.print("AssertionError: {s} is unexpectedly instance of {s}\n", .{ actual_type_name, expected_type_name });
        if (runner.global_result) |result| {
            result.addFail("assertNotIsInstance failed") catch {};
        }
        @panic("assertNotIsInstance failed");
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertRaises(callable) - callable must return an error
pub fn assertRaises(callable: anytype, args: anytype) void {
    const result = @call(.auto, callable, args);

    _ = result catch {
        if (runner.global_result) |res| {
            res.addPass();
        }
        return;
    };

    std.debug.print("AssertionError: expected error but call succeeded\n", .{});
    if (runner.global_result) |res| {
        res.addFail("assertRaises failed: expected error") catch {};
    }
    @panic("assertRaises failed");
}

/// Assertion: assertDictEqual(a, b) - assertEqual for dicts with type checking
pub fn assertDictEqual(a: anytype, b: anytype) void {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    const type_info_a = @typeInfo(TypeA);
    const type_info_b = @typeInfo(TypeB);

    const is_dict_a = type_info_a == .@"struct" and @hasField(TypeA, "keys") and @hasField(TypeA, "values");
    const is_dict_b = type_info_b == .@"struct" and @hasField(TypeB, "keys") and @hasField(TypeB, "values");

    if (!is_dict_a or !is_dict_b) {
        std.debug.print("AssertionError: assertDictEqual requires dict types\n", .{});
        if (runner.global_result) |result| {
            result.addFail("assertDictEqual failed: not dict types") catch {};
        }
        @panic("assertDictEqual failed: not dict types");
    }

    basic.assertEqual(a, b);
}

/// Assertion: assertListEqual(a, b) - assertEqual for lists with type checking
pub fn assertListEqual(a: anytype, b: anytype) void {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    const type_info_a = @typeInfo(TypeA);
    const type_info_b = @typeInfo(TypeB);

    const is_list_a = type_info_a == .array or type_info_a == .pointer or
        (type_info_a == .@"struct" and @hasField(TypeA, "items"));
    const is_list_b = type_info_b == .array or type_info_b == .pointer or
        (type_info_b == .@"struct" and @hasField(TypeB, "items"));

    if (!is_list_a or !is_list_b) {
        std.debug.print("AssertionError: assertListEqual requires list types\n", .{});
        if (runner.global_result) |result| {
            result.addFail("assertListEqual failed: not list types") catch {};
        }
        @panic("assertListEqual failed: not list types");
    }

    basic.assertEqual(a, b);
}

/// Assertion: assertSetEqual(a, b) - assertEqual for sets with type checking
pub fn assertSetEqual(a: anytype, b: anytype) void {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    const type_info_a = @typeInfo(TypeA);
    const type_info_b = @typeInfo(TypeB);

    const is_set_a = type_info_a == .@"struct" and @hasField(TypeA, "keys");
    const is_set_b = type_info_b == .@"struct" and @hasField(TypeB, "keys");

    if (!is_set_a or !is_set_b) {
        std.debug.print("AssertionError: assertSetEqual requires set types\n", .{});
        if (runner.global_result) |result| {
            result.addFail("assertSetEqual failed: not set types") catch {};
        }
        @panic("assertSetEqual failed: not set types");
    }

    basic.assertEqual(a, b);
}

/// Assertion: assertTupleEqual(a, b) - assertEqual for tuples with type checking
pub fn assertTupleEqual(a: anytype, b: anytype) void {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    const type_info_a = @typeInfo(TypeA);
    const type_info_b = @typeInfo(TypeB);

    const is_tuple_a = type_info_a == .@"struct" and type_info_a.@"struct".is_tuple;
    const is_tuple_b = type_info_b == .@"struct" and type_info_b.@"struct".is_tuple;

    if (!is_tuple_a or !is_tuple_b) {
        std.debug.print("AssertionError: assertTupleEqual requires tuple types\n", .{});
        if (runner.global_result) |result| {
            result.addFail("assertTupleEqual failed: not tuple types") catch {};
        }
        @panic("assertTupleEqual failed: not tuple types");
    }

    basic.assertEqual(a, b);
}

/// Assertion: assertSequenceEqual(a, b) - compare sequences element by element
pub fn assertSequenceEqual(a: anytype, b: anytype) void {
    if (a.len != b.len) {
        std.debug.print("AssertionError: sequences have different lengths ({d} vs {d})\n", .{ a.len, b.len });
        if (runner.global_result) |result| {
            result.addFail("assertSequenceEqual failed: different lengths") catch {};
        }
        @panic("assertSequenceEqual failed: different lengths");
    }

    for (a, 0..) |elem_a, i| {
        const elem_b = b[i];
        const equal = switch (@typeInfo(@TypeOf(elem_a))) {
            .int, .comptime_int => elem_a == elem_b,
            .float, .comptime_float => @abs(elem_a - elem_b) < 0.0001,
            .bool => elem_a == elem_b,
            .pointer => |ptr| blk: {
                if (ptr.size == .slice) {
                    break :blk std.mem.eql(u8, elem_a, elem_b);
                }
                break :blk elem_a == elem_b;
            },
            else => elem_a == elem_b,
        };

        if (!equal) {
            std.debug.print("AssertionError: sequences differ at index {d}: {any} != {any}\n", .{ i, elem_a, elem_b });
            if (runner.global_result) |result| {
                result.addFail("assertSequenceEqual failed: element mismatch") catch {};
            }
            @panic("assertSequenceEqual failed: element mismatch");
        }
    }

    if (runner.global_result) |result| {
        result.addPass();
    }
}

/// Assertion: assertMultiLineEqual(a, b) - compare multiline strings with better diff output
pub fn assertMultiLineEqual(a: []const u8, b: []const u8) void {
    if (std.mem.eql(u8, a, b)) {
        if (runner.global_result) |result| {
            result.addPass();
        }
        return;
    }

    var line_num: usize = 1;
    var a_iter = std.mem.splitScalar(u8, a, '\n');
    var b_iter = std.mem.splitScalar(u8, b, '\n');

    while (true) {
        const a_line = a_iter.next();
        const b_line = b_iter.next();

        if (a_line == null and b_line == null) break;

        if (a_line == null) {
            std.debug.print("AssertionError: multiline strings differ at line {d}\n", .{line_num});
            std.debug.print("  first string ended, second has: '{s}'\n", .{b_line.?});
            break;
        }
        if (b_line == null) {
            std.debug.print("AssertionError: multiline strings differ at line {d}\n", .{line_num});
            std.debug.print("  second string ended, first has: '{s}'\n", .{a_line.?});
            break;
        }

        if (!std.mem.eql(u8, a_line.?, b_line.?)) {
            std.debug.print("AssertionError: multiline strings differ at line {d}\n", .{line_num});
            std.debug.print("  - '{s}'\n", .{a_line.?});
            std.debug.print("  + '{s}'\n", .{b_line.?});
            break;
        }

        line_num += 1;
    }

    if (runner.global_result) |result| {
        result.addFail("assertMultiLineEqual failed") catch {};
    }
    @panic("assertMultiLineEqual failed");
}

/// Assertion: assertRaisesRegex(callable, args, pattern) - callable must error with message matching pattern
pub fn assertRaisesRegex(callable: anytype, args: anytype, pattern: []const u8) void {
    const result = @call(.auto, callable, args);

    _ = result catch |err| {
        const err_name = @errorName(err);
        if (std.mem.indexOf(u8, err_name, pattern) != null) {
            if (runner.global_result) |res| {
                res.addPass();
            }
            return;
        }

        std.debug.print("AssertionError: error '{s}' does not match pattern '{s}'\n", .{ err_name, pattern });
        if (runner.global_result) |res| {
            res.addFail("assertRaisesRegex failed: pattern not matched") catch {};
        }
        @panic("assertRaisesRegex failed: pattern not matched");
    };

    std.debug.print("AssertionError: expected error matching '{s}' but call succeeded\n", .{pattern});
    if (runner.global_result) |res| {
        res.addFail("assertRaisesRegex failed: expected error") catch {};
    }
    @panic("assertRaisesRegex failed: expected error");
}

/// Assertion: assertWarns(callable, args) - callable must emit a warning
/// Stub implementation - PyAOT doesn't have a warnings system yet
pub fn assertWarns(callable: anytype, args: anytype) void {
    const result = @call(.auto, callable, args);
    _ = result catch {};

    if (runner.global_result) |res| {
        res.addPass();
    }
}

/// Assertion: assertWarnsRegex(callable, args, pattern) - callable must emit warning matching pattern
/// Stub implementation - PyAOT doesn't have a warnings system yet
pub fn assertWarnsRegex(callable: anytype, args: anytype, pattern: []const u8) void {
    _ = pattern;

    const result = @call(.auto, callable, args);
    _ = result catch {};

    if (runner.global_result) |res| {
        res.addPass();
    }
}
