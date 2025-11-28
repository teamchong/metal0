/// PyAOT unittest assertions - basic comparison assertions
const std = @import("std");
const runner = @import("runner.zig");

/// Assertion: assertEqual(a, b) - values must be equal
pub fn assertEqual(a: anytype, b: anytype) void {
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
        else => a == b,
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
    const is_none = switch (@typeInfo(@TypeOf(value))) {
        .optional => value == null,
        .pointer => |ptr| blk: {
            // Check if it's a PyObject pointer
            if (ptr.size == .one and ptr.child == runtime.PyObject) {
                break :blk value.type_id == .none;
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
    const same = @intFromPtr(a) == @intFromPtr(b);

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
    const same = @intFromPtr(a) == @intFromPtr(b);

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
    const is_none = switch (@typeInfo(@TypeOf(value))) {
        .optional => value == null,
        .pointer => |ptr| if (ptr.size == .one) false else value.len == 0,
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

/// Assertion: assertIn(item, container) - item must be in container
/// For string-in-string checks, this performs substring search
pub fn assertIn(item: anytype, container: anytype) void {
    const ItemType = @TypeOf(item);
    const ContainerType = @TypeOf(container);

    // Check if both are string slices - use substring search
    const is_string_in_string = comptime blk: {
        const item_info = @typeInfo(ItemType);
        const container_info = @typeInfo(ContainerType);
        if (item_info == .pointer and container_info == .pointer) {
            const item_ptr = item_info.pointer;
            const container_ptr = container_info.pointer;
            // Check for []const u8 or *const [N]u8 patterns
            const item_is_string = (item_ptr.size == .slice and item_ptr.child == u8) or
                (item_ptr.size == .one and @typeInfo(item_ptr.child) == .array and @typeInfo(item_ptr.child).array.child == u8);
            const container_is_string = (container_ptr.size == .slice and container_ptr.child == u8) or
                (container_ptr.size == .one and @typeInfo(container_ptr.child) == .array and @typeInfo(container_ptr.child).array.child == u8);
            break :blk item_is_string and container_is_string;
        }
        break :blk false;
    };

    const found = if (comptime is_string_in_string) blk: {
        // Coerce pointer types to slices for std.mem.indexOf
        const container_slice: []const u8 = container;
        const item_slice: []const u8 = item;
        break :blk std.mem.indexOf(u8, container_slice, item_slice) != null;
    } else blk: {
        // Element search for other containers
        for (container) |elem| {
            if (elem == item) break :blk true;
        }
        break :blk false;
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

    // Check if both are string slices - use substring search
    const is_string_in_string = comptime blk: {
        const item_info = @typeInfo(ItemType);
        const container_info = @typeInfo(ContainerType);
        if (item_info == .pointer and container_info == .pointer) {
            const item_ptr = item_info.pointer;
            const container_ptr = container_info.pointer;
            // Check for []const u8 or *const [N]u8 patterns
            const item_is_string = (item_ptr.size == .slice and item_ptr.child == u8) or
                (item_ptr.size == .one and @typeInfo(item_ptr.child) == .array and @typeInfo(item_ptr.child).array.child == u8);
            const container_is_string = (container_ptr.size == .slice and container_ptr.child == u8) or
                (container_ptr.size == .one and @typeInfo(container_ptr.child) == .array and @typeInfo(container_ptr.child).array.child == u8);
            break :blk item_is_string and container_is_string;
        }
        break :blk false;
    };

    const found = if (comptime is_string_in_string) blk: {
        // Coerce pointer types to slices for std.mem.indexOf
        const container_slice: []const u8 = container;
        const item_slice: []const u8 = item;
        break :blk std.mem.indexOf(u8, container_slice, item_slice) != null;
    } else blk: {
        // Element search for other containers
        for (container) |elem| {
            if (elem == item) break :blk true;
        }
        break :blk false;
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
