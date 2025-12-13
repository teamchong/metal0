/// metal0 unittest assertions - basic assertions (assertTrue, assertFalse, comparison)
const std = @import("std");
const runner = @import("../../unittest/runner.zig");
const runtime = @import("../../../runtime.zig");
const helpers = @import("equality_helpers.zig");

const equalArrayList = helpers.equalArrayList;
const equalHashMap = helpers.equalHashMap;

/// Assertion: assertTrue(x) - value must be truthy
pub fn assertTrue(value: anytype) !void {
    const is_truthy = runtime.toBool(value);

    if (!is_truthy) {
        std.debug.print("AssertionError: expected True, got False\n", .{});
        if (runner.global_result) |result| {
            result.addFail("assertTrue failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertFalse(x) - value must be falsy
pub fn assertFalse(value: anytype) !void {
    const is_truthy = runtime.toBool(value);

    if (is_truthy) {
        std.debug.print("AssertionError: expected False, got True\n", .{});
        if (runner.global_result) |result| {
            result.addFail("assertFalse failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertIsNone(x) - value must be None/null
pub fn assertIsNone(value: anytype) !void {
    _ = runtime; // Mark as used
    const T = @TypeOf(value);
    const is_none = switch (@typeInfo(T)) {
        .null => true,
        .optional => value == null,
        .pointer => |ptr| blk: {
            if (ptr.size == .one and ptr.child == runtime.PyObject) {
                break :blk runtime.getTypeId(value) == .none;
            }
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

    if (!is_none) {
        std.debug.print("AssertionError: expected None\n", .{});
        if (runner.global_result) |result| {
            result.addFail("assertIsNone failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertGreater(a, b) - a > b
pub fn assertGreater(a: anytype, b: anytype) !void {
    if (!(a > b)) {
        std.debug.print("AssertionError: {any} is not greater than {any}\n", .{ a, b });
        if (runner.global_result) |result| {
            result.addFail("assertGreater failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertLess(a, b) - a < b
pub fn assertLess(a: anytype, b: anytype) !void {
    const AType = @TypeOf(a);
    const BType = @TypeOf(b);
    const a_info = @typeInfo(AType);
    const b_info = @typeInfo(BType);
    const PyValue = @import("../../../Objects/object.zig").PyValue;

    const is_less = blk: {
        // Handle PyValue (Two-Flow uncertain types)
        if (AType == PyValue and BType == PyValue) {
            break :blk a.lt(b);
        } else if (AType == PyValue) {
            break :blk a.lt(PyValue.from(b));
        } else if (BType == PyValue) {
            break :blk PyValue.from(a).lt(b);
        } else if ((a_info == .array or (a_info == .pointer and a_info.pointer.size == .slice)) and
            (b_info == .array or (b_info == .pointer and b_info.pointer.size == .slice)))
        {
            const rt = @import("../../../runtime.zig");
            break :blk rt.arrayLessThan(a, b);
        } else {
            break :blk a < b;
        }
    };

    if (!is_less) {
        std.debug.print("AssertionError: {any} is not less than {any}\n", .{ a, b });
        if (runner.global_result) |result| {
            result.addFail("assertLess failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertGreaterEqual(a, b) - a >= b
pub fn assertGreaterEqual(a: anytype, b: anytype) !void {
    if (!(a >= b)) {
        std.debug.print("AssertionError: {any} is not >= {any}\n", .{ a, b });
        if (runner.global_result) |result| {
            result.addFail("assertGreaterEqual failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertLessEqual(a, b) - a <= b
pub fn assertLessEqual(a: anytype, b: anytype) !void {
    if (!(a <= b)) {
        std.debug.print("AssertionError: {any} is not <= {any}\n", .{ a, b });
        if (runner.global_result) |result| {
            result.addFail("assertLessEqual failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}

/// Assertion: assertNotEqual(a, b) - values must NOT be equal
pub fn assertNotEqual(a: anytype, b: anytype) !void {
    const A = @TypeOf(a);
    const B = @TypeOf(b);

    if (A != B) {
        if (runner.global_result) |result| {
            result.addPass();
        }
        return;
    }

    const a_info = @typeInfo(A);
    const equal = switch (a_info) {
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
        .@"struct" => blk: {
            if (@hasField(A, "items") and @hasField(A, "capacity")) {
                break :blk equalArrayList(a, b);
            }
            if (@hasField(A, "entries") or @hasDecl(A, "count")) {
                break :blk equalHashMap(a, b);
            }
            if (@hasDecl(A, "eql")) {
                break :blk a.eql(b);
            }
            break :blk runtime.pyAnyEql(a, b);
        },
        else => blk: {
            break :blk runtime.pyAnyEql(a, b);
        },
    };

    if (equal) {
        std.debug.print("AssertionError: {any} == {any} (expected not equal)\n", .{ a, b });
        if (runner.global_result) |result| {
            result.addFail("assertNotEqual failed") catch {};
        }
        return error.AssertionFailed;
    } else {
        if (runner.global_result) |result| {
            result.addPass();
        }
    }
}
