/// _pylong module runtime - Pure Python long integer implementation
/// Provides fast conversion between large integers and decimal strings
const std = @import("std");
const Allocator = std.mem.Allocator;
const hashmap_helper = @import("hashmap_helper");

/// Log base 256 of 10, used for digit estimation
pub const LOG_10_BASE_256: f64 = 0.4150374992788438;

/// Spread dictionary for diagnostic tracking (test support)
pub const Spread = struct {
    data: std.AutoHashMap(i64, i64),

    pub fn init(allocator: Allocator) Spread {
        return .{ .data = std.AutoHashMap(i64, i64).init(allocator) };
    }

    pub fn deinit(self: *Spread) void {
        self.data.deinit();
    }

    pub fn copy(self: Spread) Spread {
        return self;
    }

    pub fn clear(self: *Spread) void {
        self.data.clearRetainingCapacity();
    }

    pub fn update(self: *Spread, other: Spread) void {
        _ = self;
        _ = other;
    }

    pub fn contains(self: Spread, key: i64) bool {
        return self.data.contains(key);
    }
};

/// Result dict type from compute_powers
pub const PowersDict = struct {
    keys_list: std.ArrayList(i64),
    values_list: std.ArrayList(i64),
    allocator: Allocator,

    pub fn init(allocator: Allocator) PowersDict {
        return .{
            .keys_list = std.ArrayList(i64){},
            .values_list = std.ArrayList(i64){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PowersDict) void {
        self.keys_list.deinit(self.allocator);
        self.values_list.deinit(self.allocator);
    }

    pub fn put(self: *PowersDict, key: i64, value: i64) !void {
        try self.keys_list.append(self.allocator, key);
        try self.values_list.append(self.allocator, value);
    }

    pub fn get(self: PowersDict, key: i64) ?i64 {
        for (self.keys_list.items, 0..) |k, i| {
            if (k == key) return self.values_list.items[i];
        }
        return null;
    }

    pub fn keys(self: PowersDict) []const i64 {
        return self.keys_list.items;
    }

    pub fn items(self: PowersDict) ItemsIterator {
        return .{ .dict = self, .index = 0 };
    }

    pub const ItemsIterator = struct {
        dict: PowersDict,
        index: usize,

        pub fn next(self: *ItemsIterator) ?struct { k: i64, v: i64 } {
            if (self.index >= self.dict.keys_list.items.len) return null;
            const k = self.dict.keys_list.items[self.index];
            const v = self.dict.values_list.items[self.index];
            self.index += 1;
            return .{ .k = k, .v = v };
        }
    };
};

/// compute_powers - Pre-compute required powers of base for divide-and-conquer
/// Returns a dict mapping exponents to base^exponent values
pub fn computePowers(allocator: Allocator, w: i64, base: i64, more_than: i64, need_hi: bool) PowersDict {
    var seen = std.AutoHashMap(i64, void).init(allocator);
    defer seen.deinit();

    var need = std.AutoHashMap(i64, void).init(allocator);
    defer need.deinit();

    var ws = std.ArrayList(i64){};
    defer ws.deinit(allocator);
    ws.append(allocator, w) catch {};

    // Phase 1: Determine which exponents are needed
    while (ws.items.len > 0) {
        const curr_w = ws.pop() orelse break;
        if (curr_w <= more_than or seen.contains(curr_w)) {
            continue;
        }
        seen.put(curr_w, {}) catch {};

        const lo = @divFloor(curr_w, 2);
        const hi = curr_w - lo;
        const which = if (need_hi) hi else lo;
        need.put(which, {}) catch {};
        ws.append(allocator, which) catch {};
        if (lo != hi) {
            ws.append(allocator, curr_w - which) catch {};
        }
    }

    // Phase 2: Add extra exponents for efficient computation
    var cands = std.ArrayList(i64){};
    defer cands.deinit(allocator);

    var extra = std.AutoHashMap(i64, void).init(allocator);
    defer extra.deinit();

    // Copy need to cands
    var need_iter = need.keyIterator();
    while (need_iter.next()) |key| {
        cands.append(allocator, key.*) catch {};
    }

    while (cands.items.len > 0) {
        // Find max
        var max_val: i64 = std.math.minInt(i64);
        var max_idx: usize = 0;
        for (cands.items, 0..) |v, i| {
            if (v > max_val) {
                max_val = v;
                max_idx = i;
            }
        }
        _ = cands.orderedRemove(max_idx);

        const lo = @divFloor(max_val, 2);
        const in_cands = blk: {
            for (cands.items) |c| {
                if (c == max_val - 1 or c == lo) break :blk true;
            }
            break :blk false;
        };
        if (lo > more_than and !in_cands) {
            extra.put(lo, {}) catch {};
            cands.append(allocator, lo) catch {};
        }
    }

    // Phase 3: Compute powers in sorted order
    var all_exponents = std.ArrayList(i64){};
    defer all_exponents.deinit(allocator);

    var need_iter2 = need.keyIterator();
    while (need_iter2.next()) |key| {
        all_exponents.append(allocator, key.*) catch {};
    }
    var extra_iter = extra.keyIterator();
    while (extra_iter.next()) |key| {
        all_exponents.append(allocator, key.*) catch {};
    }

    // Sort
    std.mem.sort(i64, all_exponents.items, {}, std.sort.asc(i64));

    var d = std.AutoHashMap(i64, i64).init(allocator);
    defer d.deinit();

    for (all_exponents.items) |n| {
        const lo = @divFloor(n, 2);
        const hi = n - lo;
        var result: i64 = undefined;

        if (d.get(n - 1)) |prev| {
            result = prev * base;
        } else if (d.get(lo)) |lo_val| {
            result = lo_val * lo_val;
            if (hi != lo) {
                result *= base;
            }
        } else {
            result = std.math.pow(i64, base, @intCast(n));
        }
        d.put(n, result) catch {};
    }

    // Build result dict with only needed exponents
    var result_dict = PowersDict.init(allocator);
    var need_iter3 = need.keyIterator();
    while (need_iter3.next()) |key| {
        if (d.get(key.*)) |val| {
            result_dict.put(key.*, val) catch {};
        }
    }

    return result_dict;
}
