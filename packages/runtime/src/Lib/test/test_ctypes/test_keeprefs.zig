//! test.test_ctypes.test_keeprefs - Tests for reference keeping
//! Reference: cpython/Lib/test/test_ctypes/test_keeprefs.py
//!
//! Tests for reference lifetime management in ctypes including
//! preventing premature garbage collection of referenced objects.

const std = @import("std");
const _support = @import("_support.zig");

// ============================================================================
// Reference Keeper
// ============================================================================

/// Keeps references to objects to prevent collection
pub fn RefKeeper(comptime max_refs: usize) type {
    return struct {
        const Self = @This();

        refs: [max_refs]?*anyopaque = [_]?*anyopaque{null} ** max_refs,
        count: usize = 0,

        pub fn init() Self {
            return .{};
        }

        /// Add a reference to keep
        pub fn keep(self: *Self, ptr: *anyopaque) !usize {
            if (self.count >= max_refs) {
                return error.TooManyRefs;
            }

            const idx = self.count;
            self.refs[idx] = ptr;
            self.count += 1;
            return idx;
        }

        /// Release a reference by index
        pub fn release(self: *Self, idx: usize) void {
            if (idx < max_refs) {
                self.refs[idx] = null;
            }
        }

        /// Release all references
        pub fn releaseAll(self: *Self) void {
            @memset(&self.refs, null);
            self.count = 0;
        }

        /// Get reference by index
        pub fn get(self: *const Self, idx: usize) ?*anyopaque {
            if (idx >= max_refs) return null;
            return self.refs[idx];
        }

        /// Check if any references are held
        pub fn hasRefs(self: *const Self) bool {
            for (self.refs) |ref| {
                if (ref != null) return true;
            }
            return false;
        }

        /// Count active references
        pub fn activeCount(self: *const Self) usize {
            var count: usize = 0;
            for (self.refs) |ref| {
                if (ref != null) count += 1;
            }
            return count;
        }
    };
}

// ============================================================================
// Object with Ref Keeping
// ============================================================================

/// A ctypes-like object that keeps references
pub fn ObjectWithRefs(comptime T: type, comptime max_refs: usize) type {
    return struct {
        const Self = @This();

        value: T,
        refs: RefKeeper(max_refs) = RefKeeper(max_refs).init(),

        pub fn init(value: T) Self {
            return .{ .value = value };
        }

        /// Set value and keep reference to source
        pub fn setValue(self: *Self, value: T, source: *anyopaque) !void {
            self.value = value;
            _ = try self.refs.keep(source);
        }

        /// Get the value
        pub fn getValue(self: *const Self) T {
            return self.value;
        }

        /// Release all kept references
        pub fn releaseRefs(self: *Self) void {
            self.refs.releaseAll();
        }
    };
}

// ============================================================================
// Weak Reference
// ============================================================================

/// A weak reference that doesn't prevent collection
pub fn WeakRef(comptime T: type) type {
    return struct {
        const Self = @This();

        ptr: ?*T = null,
        valid: bool = false,

        pub fn init() Self {
            return .{};
        }

        pub fn set(self: *Self, target: *T) void {
            self.ptr = target;
            self.valid = true;
        }

        pub fn get(self: *const Self) ?*T {
            if (!self.valid) return null;
            return self.ptr;
        }

        pub fn invalidate(self: *Self) void {
            self.valid = false;
            self.ptr = null;
        }

        pub fn isValid(self: *const Self) bool {
            return self.valid and self.ptr != null;
        }
    };
}

// ============================================================================
// Pointer Chain
// ============================================================================

/// Chain of pointers with ref keeping
pub const PointerChain = struct {
    const Self = @This();
    const max_depth = 8;

    ptrs: [max_depth]?*anyopaque = [_]?*anyopaque{null} ** max_depth,
    depth: usize = 0,

    pub fn init() Self {
        return .{};
    }

    pub fn push(self: *Self, ptr: *anyopaque) !void {
        if (self.depth >= max_depth) {
            return error.ChainTooDeep;
        }
        self.ptrs[self.depth] = ptr;
        self.depth += 1;
    }

    pub fn pop(self: *Self) ?*anyopaque {
        if (self.depth == 0) return null;
        self.depth -= 1;
        const ptr = self.ptrs[self.depth];
        self.ptrs[self.depth] = null;
        return ptr;
    }

    pub fn top(self: *const Self) ?*anyopaque {
        if (self.depth == 0) return null;
        return self.ptrs[self.depth - 1];
    }

    pub fn isEmpty(self: *const Self) bool {
        return self.depth == 0;
    }
};

// ============================================================================
// Test Cases
// ============================================================================

fn testRefKeeper() !void {
    var keeper = RefKeeper(8).init();
    try std.testing.expect(!keeper.hasRefs());

    var data1: i32 = 42;
    var data2: i32 = 100;

    const idx1 = try keeper.keep(@ptrCast(&data1));
    const idx2 = try keeper.keep(@ptrCast(&data2));

    try std.testing.expect(keeper.hasRefs());
    try std.testing.expectEqual(@as(usize, 2), keeper.activeCount());

    try std.testing.expect(keeper.get(idx1) != null);
    try std.testing.expect(keeper.get(idx2) != null);
}

fn testRefKeeperRelease() !void {
    var keeper = RefKeeper(8).init();
    var data: i32 = 42;

    const idx = try keeper.keep(@ptrCast(&data));
    try std.testing.expectEqual(@as(usize, 1), keeper.activeCount());

    keeper.release(idx);
    try std.testing.expectEqual(@as(usize, 0), keeper.activeCount());
    try std.testing.expect(keeper.get(idx) == null);
}

fn testRefKeeperReleaseAll() !void {
    var keeper = RefKeeper(8).init();
    var data1: i32 = 1;
    var data2: i32 = 2;
    var data3: i32 = 3;

    _ = try keeper.keep(@ptrCast(&data1));
    _ = try keeper.keep(@ptrCast(&data2));
    _ = try keeper.keep(@ptrCast(&data3));

    try std.testing.expectEqual(@as(usize, 3), keeper.activeCount());

    keeper.releaseAll();
    try std.testing.expectEqual(@as(usize, 0), keeper.activeCount());
    try std.testing.expect(!keeper.hasRefs());
}

fn testRefKeeperFull() !void {
    var keeper = RefKeeper(2).init();
    var data: [3]i32 = .{ 1, 2, 3 };

    _ = try keeper.keep(@ptrCast(&data[0]));
    _ = try keeper.keep(@ptrCast(&data[1]));
    try std.testing.expectError(error.TooManyRefs, keeper.keep(@ptrCast(&data[2])));
}

fn testObjectWithRefs() !void {
    var obj = ObjectWithRefs(i32, 4).init(0);
    var source: i32 = 42;

    try obj.setValue(42, @ptrCast(&source));
    try std.testing.expectEqual(@as(i32, 42), obj.getValue());
    try std.testing.expect(obj.refs.hasRefs());

    obj.releaseRefs();
    try std.testing.expect(!obj.refs.hasRefs());
}

fn testWeakRef() !void {
    var target: i32 = 42;
    var weak = WeakRef(i32).init();

    try std.testing.expect(!weak.isValid());

    weak.set(&target);
    try std.testing.expect(weak.isValid());
    try std.testing.expectEqual(&target, weak.get().?);

    weak.invalidate();
    try std.testing.expect(!weak.isValid());
    try std.testing.expect(weak.get() == null);
}

fn testPointerChain() !void {
    var chain = PointerChain.init();
    try std.testing.expect(chain.isEmpty());

    var data: [3]i32 = .{ 10, 20, 30 };

    try chain.push(@ptrCast(&data[0]));
    try chain.push(@ptrCast(&data[1]));
    try chain.push(@ptrCast(&data[2]));

    try std.testing.expectEqual(@as(usize, 3), chain.depth);
    try std.testing.expect(!chain.isEmpty());

    // Pop in reverse order
    const p3 = chain.pop();
    try std.testing.expect(p3 != null);

    const p2 = chain.pop();
    try std.testing.expect(p2 != null);

    try std.testing.expectEqual(@as(usize, 1), chain.depth);
}

fn testPointerChainTooDeep() !void {
    var chain = PointerChain.init();
    var data: [10]i32 = undefined;

    // Fill to capacity
    for (0..8) |i| {
        try chain.push(@ptrCast(&data[i]));
    }

    // Should fail on 9th
    try std.testing.expectError(error.ChainTooDeep, chain.push(@ptrCast(&data[8])));
}

fn testPointerChainTop() !void {
    var chain = PointerChain.init();
    var data: i32 = 42;

    try std.testing.expect(chain.top() == null);

    try chain.push(@ptrCast(&data));
    const top = chain.top();
    try std.testing.expect(top != null);
    try std.testing.expectEqual(@as(*i32, @ptrCast(@alignCast(top.?))).*, 42);
}

fn testRefKeeperOutOfBounds() !void {
    var keeper = RefKeeper(4).init();
    try std.testing.expect(keeper.get(100) == null); // Out of bounds
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "ref_keeper" {
    try testRefKeeper();
}

test "ref_keeper_release" {
    try testRefKeeperRelease();
}

test "ref_keeper_release_all" {
    try testRefKeeperReleaseAll();
}

test "ref_keeper_full" {
    try testRefKeeperFull();
}

test "object_with_refs" {
    try testObjectWithRefs();
}

test "weak_ref" {
    try testWeakRef();
}

test "pointer_chain" {
    try testPointerChain();
}

test "pointer_chain_too_deep" {
    try testPointerChainTooDeep();
}

test "pointer_chain_top" {
    try testPointerChainTop();
}

test "ref_keeper_out_of_bounds" {
    try testRefKeeperOutOfBounds();
}
