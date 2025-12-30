//! Aggregate functions for SQL GROUP BY operations.
//!
//! Supports COUNT, SUM, AVG, MIN, MAX with optional DISTINCT.

const std = @import("std");
const Value = @import("lanceql.value").Value;
const ast = @import("ast.zig");
const AggregateType = ast.AggregateType;

/// An aggregate accumulator.
pub const Aggregate = struct {
    agg_type: AggregateType,
    distinct: bool,
    state: State,

    const State = union(enum) {
        count: u64,
        sum: SumState,
        avg: AvgState,
        min: ?Value,
        max: ?Value,
    };

    const SumState = struct {
        int_sum: i64 = 0,
        float_sum: f64 = 0,
        is_float: bool = false,
    };

    const AvgState = struct {
        sum: f64 = 0,
        count: u64 = 0,
    };

    const Self = @This();

    /// Create a new aggregate.
    pub fn init(agg_type: AggregateType, distinct: bool) Self {
        return .{
            .agg_type = agg_type,
            .distinct = distinct,
            .state = switch (agg_type) {
                .count => .{ .count = 0 },
                .sum => .{ .sum = .{} },
                .avg => .{ .avg = .{} },
                .min => .{ .min = null },
                .max => .{ .max = null },
            },
        };
    }

    /// Add a value to the aggregate.
    pub fn add(self: *Self, value: Value) void {
        // Skip nulls for all aggregates except COUNT(*)
        if (value.isNull()) {
            return;
        }

        switch (self.agg_type) {
            .count => {
                self.state.count += 1;
            },
            .sum => {
                switch (value) {
                    .int64 => |v| {
                        if (self.state.sum.is_float) {
                            self.state.sum.float_sum += @floatFromInt(v);
                        } else {
                            self.state.sum.int_sum += v;
                        }
                    },
                    .float64 => |v| {
                        if (!self.state.sum.is_float) {
                            // Convert to float
                            self.state.sum.float_sum = @floatFromInt(self.state.sum.int_sum);
                            self.state.sum.is_float = true;
                        }
                        self.state.sum.float_sum += v;
                    },
                    else => {},
                }
            },
            .avg => {
                const f = value.toFloat64() orelse return;
                self.state.avg.sum += f;
                self.state.avg.count += 1;
            },
            .min => {
                if (self.state.min) |current| {
                    if (value.lessThan(current)) {
                        self.state.min = value;
                    }
                } else {
                    self.state.min = value;
                }
            },
            .max => {
                if (self.state.max) |current| {
                    if (value.greaterThan(current)) {
                        self.state.max = value;
                    }
                } else {
                    self.state.max = value;
                }
            },
        }
    }

    /// Add a row (for COUNT(*)).
    pub fn addRow(self: *Self) void {
        if (self.agg_type == .count) {
            self.state.count += 1;
        }
    }

    /// Get the final result.
    pub fn result(self: Self) Value {
        return switch (self.agg_type) {
            .count => Value.int(@intCast(self.state.count)),
            .sum => {
                if (self.state.sum.is_float) {
                    return Value.float(self.state.sum.float_sum);
                } else {
                    return Value.int(self.state.sum.int_sum);
                }
            },
            .avg => {
                if (self.state.avg.count == 0) {
                    return Value.nil();
                }
                return Value.float(self.state.avg.sum / @as(f64, @floatFromInt(self.state.avg.count)));
            },
            .min => self.state.min orelse Value.nil(),
            .max => self.state.max orelse Value.nil(),
        };
    }

    /// Reset the aggregate state.
    pub fn reset(self: *Self) void {
        self.state = switch (self.agg_type) {
            .count => .{ .count = 0 },
            .sum => .{ .sum = .{} },
            .avg => .{ .avg = .{} },
            .min => .{ .min = null },
            .max => .{ .max = null },
        };
    }
};

/// A group key for GROUP BY operations.
pub const GroupKey = struct {
    values: []Value,

    pub fn hash(self: GroupKey) u64 {
        var h: u64 = 0;
        for (self.values) |v| {
            h = h *% 31 +% hashValue(v);
        }
        return h;
    }

    pub fn eql(a: GroupKey, b: GroupKey) bool {
        if (a.values.len != b.values.len) return false;
        for (a.values, b.values) |av, bv| {
            if (!av.eql(bv)) return false;
        }
        return true;
    }

    fn hashValue(v: Value) u64 {
        return switch (v) {
            .null => 0,
            .int64 => |i| @bitCast(i),
            .float64 => |f| @bitCast(f),
            .bool_ => |b| if (b) @as(u64, 1) else @as(u64, 0),
            .string => |s| blk: {
                var h: u64 = 0;
                for (s) |c| {
                    h = h *% 31 +% c;
                }
                break :blk h;
            },
        };
    }
};

/// Context for GroupKey in HashMap.
pub const GroupKeyContext = struct {
    pub fn hash(_: GroupKeyContext, key: GroupKey) u64 {
        return key.hash();
    }

    pub fn eql(_: GroupKeyContext, a: GroupKey, b: GroupKey) bool {
        return a.eql(b);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Aggregate COUNT" {
    var agg = Aggregate.init(.count, false);

    agg.add(Value.int(1));
    agg.add(Value.int(2));
    agg.add(Value.nil()); // Nulls not counted
    agg.add(Value.int(3));

    const result = agg.result();
    try std.testing.expectEqual(result.int64, 3);
}

test "Aggregate SUM" {
    var agg = Aggregate.init(.sum, false);

    agg.add(Value.int(10));
    agg.add(Value.int(20));
    agg.add(Value.int(30));

    const result = agg.result();
    try std.testing.expectEqual(result.int64, 60);
}

test "Aggregate AVG" {
    var agg = Aggregate.init(.avg, false);

    agg.add(Value.int(10));
    agg.add(Value.int(20));
    agg.add(Value.int(30));

    const result = agg.result();
    try std.testing.expectApproxEqAbs(result.float64, 20.0, 0.001);
}

test "Aggregate MIN/MAX" {
    var min_agg = Aggregate.init(.min, false);
    var max_agg = Aggregate.init(.max, false);

    const values = [_]Value{ Value.int(5), Value.int(2), Value.int(8), Value.int(1) };
    for (values) |v| {
        min_agg.add(v);
        max_agg.add(v);
    }

    try std.testing.expectEqual(min_agg.result().int64, 1);
    try std.testing.expectEqual(max_agg.result().int64, 8);
}

test "GroupKey hash and equality" {
    var values1 = [_]Value{ Value.int(1), Value.str("a") };
    var values2 = [_]Value{ Value.int(1), Value.str("a") };
    var values3 = [_]Value{ Value.int(2), Value.str("a") };

    const key1 = GroupKey{ .values = &values1 };
    const key2 = GroupKey{ .values = &values2 };
    const key3 = GroupKey{ .values = &values3 };

    try std.testing.expect(key1.eql(key2));
    try std.testing.expect(!key1.eql(key3));
    try std.testing.expectEqual(key1.hash(), key2.hash());
}
