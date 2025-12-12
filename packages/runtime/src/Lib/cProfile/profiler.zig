//! Core profiler implementation
//!
//! Deterministic profiler that tracks function calls and timing.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");
const types = @import("types.zig");
const Stats = @import("stats.zig").Stats;
const SortKey = @import("sort.zig").SortKey;

const ProfileEntry = types.ProfileEntry;
const CallStackEntry = types.CallStackEntry;

// ============================================================================
// Profile
// ============================================================================

/// Deterministic profiler
pub const Profile = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Profile statistics by function key
    stats: hashmap_helper.StringHashMap(ProfileEntry),
    /// Call stack for tracking nested calls
    call_stack: std.ArrayList(CallStackEntry),
    /// Whether profiler is enabled
    enabled: bool = false,
    /// Total time spent profiling
    total_time: f64 = 0.0,
    /// Timer function
    timer: *const fn () i128,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .stats = hashmap_helper.StringHashMap(ProfileEntry).init(allocator),
            .call_stack = .{},
            .timer = defaultTimer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.stats.deinit();
        self.call_stack.deinit(self.allocator);
    }

    fn defaultTimer() i128 {
        return std.time.nanoTimestamp();
    }

    /// Enable the profiler
    pub fn enable(self: *Self) void {
        self.enabled = true;
    }

    /// Disable the profiler
    pub fn disable(self: *Self) void {
        self.enabled = false;
    }

    /// Clear all statistics
    pub fn clear(self: *Self) void {
        self.stats.clearRetainingCapacity();
        self.call_stack.clearRetainingCapacity();
        self.total_time = 0.0;
    }

    /// Record function entry
    pub fn callEnter(self: *Self, name: []const u8) void {
        if (!self.enabled) return;

        const now = self.timer();
        self.call_stack.append(self.allocator, .{
            .name = name,
            .start_time = now,
            .subcall_time = 0.0,
        }) catch return;
    }

    /// Record function exit
    pub fn callExit(self: *Self, name: []const u8, filename: []const u8, lineno: usize) void {
        if (!self.enabled) return;

        const now = self.timer();

        // Pop from call stack
        if (self.call_stack.items.len == 0) return;
        const entry = self.call_stack.pop();

        const elapsed_ns = now - entry.start_time;
        const elapsed = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        const own_time = elapsed - entry.subcall_time;

        // Update stats
        const key = name;
        if (self.stats.getPtr(key)) |stat| {
            stat.ncalls += 1;
            stat.tottime += own_time;
            stat.cumtime += elapsed;
        } else {
            var new_entry = ProfileEntry.init(name, filename, lineno);
            new_entry.ncalls = 1;
            new_entry.tottime = own_time;
            new_entry.cumtime = elapsed;
            self.stats.put(key, new_entry) catch return;
        }

        // Update parent's subcall time
        if (self.call_stack.items.len > 0) {
            self.call_stack.items[self.call_stack.items.len - 1].subcall_time += elapsed;
        }

        self.total_time += own_time;
    }

    /// High-level method to record a function call
    /// Combines callEnter with caller/callee tracking
    pub fn recordCall(self: *Self, name: []const u8, filename: []const u8, lineno: usize) !void {
        if (!self.enabled) return;

        // Track caller->callee relationship
        if (self.call_stack.items.len > 0) {
            const caller_name = self.call_stack.items[self.call_stack.items.len - 1].name;
            // Get or create callee entry to record caller
            const callee_result = try self.stats.getOrPut(name);
            if (!callee_result.found_existing) {
                callee_result.value_ptr.* = ProfileEntry.initWithAllocator(self.allocator, name, filename, lineno);
            }
            callee_result.value_ptr.recordCaller(caller_name);

            // Get or create caller entry to record callee
            if (self.stats.getPtr(caller_name)) |caller_entry| {
                caller_entry.recordCallee(name);
            }
        }

        self.callEnter(name);
    }

    /// High-level method to record a function return
    /// Combines callExit with any additional tracking
    pub fn recordReturn(self: *Self, name: []const u8) !void {
        if (!self.enabled) return;

        // Find the filename/lineno from the call stack or stats
        var filename: []const u8 = "<unknown>";
        var lineno: usize = 0;
        if (self.stats.get(name)) |entry| {
            filename = entry.filename;
            lineno = entry.lineno;
        }

        self.callExit(name, filename, lineno);
    }

    /// Create stats summary
    pub fn createStats(self: *Self) Stats {
        return Stats.init(self.allocator, &self.stats);
    }

    /// Print statistics
    pub fn printStats(self: *Self, sort: SortKey) !void {
        var stats = self.createStats();
        try stats.sortStats(sort);
        try stats.printStats();
    }

    /// Dump stats to file
    pub fn dumpStats(self: *Self, filename: []const u8) !void {
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        var writer = file.writer();
        var iter = self.stats.iterator();
        while (iter.next()) |entry| {
            try writer.print("{s},{d},{d:.6},{d:.6}\n", .{
                entry.key_ptr.*,
                entry.value_ptr.ncalls,
                entry.value_ptr.tottime,
                entry.value_ptr.cumtime,
            });
        }
    }

    /// Run a callable under the profiler
    pub fn runcall(self: *Self, comptime func: anytype, args: anytype) @TypeOf(@call(.auto, func, args)) {
        self.enable();
        defer self.disable();
        return @call(.auto, func, args);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Profile init" {
    const allocator = std.testing.allocator;
    var profiler = Profile.init(allocator);
    defer profiler.deinit();

    try std.testing.expect(!profiler.enabled);
    try std.testing.expectEqual(@as(f64, 0.0), profiler.total_time);
}

test "Profile enable/disable" {
    const allocator = std.testing.allocator;
    var profiler = Profile.init(allocator);
    defer profiler.deinit();

    try std.testing.expect(!profiler.enabled);
    profiler.enable();
    try std.testing.expect(profiler.enabled);
    profiler.disable();
    try std.testing.expect(!profiler.enabled);
}

test "Profile clear" {
    const allocator = std.testing.allocator;
    var profiler = Profile.init(allocator);
    defer profiler.deinit();

    profiler.total_time = 1.0;
    profiler.clear();
    try std.testing.expectEqual(@as(f64, 0.0), profiler.total_time);
}
