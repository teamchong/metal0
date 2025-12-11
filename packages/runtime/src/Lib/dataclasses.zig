//\! CPython source: Lib/dataclasses.py
//\!
//\! Provides a decorator and functions for automatically adding generated
//\! special methods to classes.
//\!
//\! Mirrors: CPython Lib/dataclasses.py

pub const types = @import("dataclasses/types.zig");
pub const field_mod = @import("dataclasses/field.zig");
pub const error_mod = @import("dataclasses/error.zig");
pub const repr = @import("dataclasses/repr.zig");
pub const comparison = @import("dataclasses/comparison.zig");
pub const hash = @import("dataclasses/hash.zig");
pub const utilities = @import("dataclasses/utilities.zig");
pub const dataclass_mod = @import("dataclasses/dataclass.zig");

// Re-export commonly used items at module level
pub const MISSING = types.MISSING;
pub const KW_ONLY = types.KW_ONLY;
pub const DataclassOptions = types.DataclassOptions;

pub const Field = field_mod.Field;
pub const field = field_mod.field;

pub const FrozenInstanceError = error_mod.FrozenInstanceError;

pub const Dataclass = dataclass_mod.Dataclass;
pub const dataclass = dataclass_mod.dataclass;

pub const getFields = utilities.getFields;
pub const isDataclass = utilities.isDataclass;
pub const asdict = utilities.asdict;
pub const replace = utilities.replace;
pub const copy = utilities.copy;

const std = @import("std");

// ============================================================================
// Tests
// ============================================================================

test "basic dataclass" {
    const Point = struct {
        x: i32,
        y: i32,
    };

    const DataPoint = dataclass(Point);

    const p = DataPoint.init(.{ .x = 10, .y = 20 });
    try std.testing.expectEqual(@as(i32, 10), p.get("x"));
    try std.testing.expectEqual(@as(i32, 20), p.get("y"));
}

test "dataclass equality" {
    const Point = struct {
        x: i32,
        y: i32,
    };

    const DataPoint = dataclass(Point);

    const p1 = DataPoint.init(.{ .x = 10, .y = 20 });
    const p2 = DataPoint.init(.{ .x = 10, .y = 20 });
    const p3 = DataPoint.init(.{ .x = 5, .y = 20 });

    try std.testing.expect(p1.eql(p2));
    try std.testing.expect(\!p1.eql(p3));
}

test "dataclass repr" {
    const allocator = std.testing.allocator;

    const Point = struct {
        x: i32,
        y: i32,
    };

    const DataPoint = dataclass(Point);
    const p = DataPoint.init(.{ .x = 10, .y = 20 });

    const r = try p.reprStr(allocator);
    defer allocator.free(r);

    try std.testing.expect(std.mem.indexOf(u8, r, "x=10") \!= null);
    try std.testing.expect(std.mem.indexOf(u8, r, "y=20") \!= null);
}

test "dataclass with ordering" {
    const Item = struct {
        priority: i32,
        name: []const u8,
    };

    const OrderedItem = Dataclass(Item, .{ .order = true });

    const a = OrderedItem.init(.{ .priority = 1, .name = "first" });
    const b = OrderedItem.init(.{ .priority = 2, .name = "second" });

    try std.testing.expect(a.lessThan(b));
    try std.testing.expect(\!b.lessThan(a));
}

test "dataclass hash" {
    const Point = struct {
        x: i32,
        y: i32,
    };

    const DataPoint = dataclass(Point);

    const p1 = DataPoint.init(.{ .x = 10, .y = 20 });
    const p2 = DataPoint.init(.{ .x = 10, .y = 20 });
    const p3 = DataPoint.init(.{ .x = 5, .y = 20 });

    try std.testing.expectEqual(p1.hashValue(), p2.hashValue());
    try std.testing.expect(p1.hashValue() \!= p3.hashValue());
}

test "replace" {
    const Point = struct {
        x: i32,
        y: i32,
    };

    const p = Point{ .x = 10, .y = 20 };
    const p2 = replace(Point, p, .{ .x = 100 });

    try std.testing.expectEqual(@as(i32, 100), p2.x);
    try std.testing.expectEqual(@as(i32, 20), p2.y);
}

test "getFields" {
    const Point = struct {
        x: i32,
        y: i32,
    };

    const fields = getFields(Point);
    try std.testing.expectEqual(@as(usize, 2), fields.len);
}

test "astuple" {
    const Point = struct {
        x: i32,
        y: i32,
    };

    const DataPoint = dataclass(Point);
    const p = DataPoint.init(.{ .x = 10, .y = 20 });

    const tuple = p.astuple();
    try std.testing.expectEqual(@as(i32, 10), tuple[0]);
    try std.testing.expectEqual(@as(i32, 20), tuple[1]);
}
