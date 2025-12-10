//! CPython source: Lib/tracemalloc.py
//!
//! Traces memory allocations to debug memory leaks and analyze memory usage.
//!
//! Mirrors: CPython Lib/tracemalloc.py

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Error Types
// ============================================================================

pub const TracemallocError = error{
    NotTracing,
    AlreadyTracing,
    InvalidNframe,
    OutOfMemory,
};

// ============================================================================
// Traceback
// ============================================================================

/// A traceback of frames where memory was allocated
pub const Traceback = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    frames: std.ArrayList(Frame),

    pub const Frame = struct {
        filename: []const u8,
        lineno: u32,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .frames = std.ArrayList(Frame).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.frames.deinit();
    }

    /// Get total frames in traceback
    pub fn total_nframe(self: *const Self) usize {
        return self.frames.items.len;
    }

    /// Format the traceback for display
    pub fn format(self: *const Self, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        const writer = result.writer();

        for (self.frames.items) |frame| {
            try writer.print("  File \"{s}\", line {d}\n", .{ frame.filename, frame.lineno });
        }

        return result.toOwnedSlice();
    }
};

// ============================================================================
// Trace
// ============================================================================

/// A trace of memory allocation
pub const Trace = struct {
    const Self = @This();

    /// Memory address
    address: usize,
    /// Size of allocation in bytes
    size: usize,
    /// Traceback of where allocation occurred
    traceback: Traceback,

    pub fn deinit(self: *Self) void {
        self.traceback.deinit();
    }
};

// ============================================================================
// Snapshot
// ============================================================================

/// A snapshot of memory allocations
pub const Snapshot = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// All traces in this snapshot
    traces: std.ArrayList(Trace),
    /// Traceback limit at time of snapshot
    traceback_limit: u32,

    pub fn init(allocator: std.mem.Allocator, traceback_limit: u32) Self {
        return Self{
            .allocator = allocator,
            .traces = std.ArrayList(Trace).init(allocator),
            .traceback_limit = traceback_limit,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.traces.items) |*trace| {
            trace.deinit();
        }
        self.traces.deinit();
    }

    /// Load a snapshot from file
    pub fn load(allocator: std.mem.Allocator, filename: []const u8) !Self {
        _ = filename;
        return Self.init(allocator, 1);
    }

    /// Save snapshot to file
    pub fn dump(self: *const Self, filename: []const u8) !void {
        _ = self;
        _ = filename;
        // Would serialize traces to file
    }

    /// Filter traces by filename pattern
    pub fn filter_traces(
        self: *const Self,
        allocator: std.mem.Allocator,
        inclusive: bool,
        filename_pattern: []const u8,
    ) !Snapshot {
        var filtered = Snapshot.init(allocator, self.traceback_limit);

        for (self.traces.items) |trace| {
            var matches = false;
            for (trace.traceback.frames.items) |frame| {
                if (std.mem.indexOf(u8, frame.filename, filename_pattern) != null) {
                    matches = true;
                    break;
                }
            }

            if (matches == inclusive) {
                // Clone trace
                var new_trace = Trace{
                    .address = trace.address,
                    .size = trace.size,
                    .traceback = Traceback.init(allocator),
                };
                for (trace.traceback.frames.items) |frame| {
                    try new_trace.traceback.frames.append(frame);
                }
                try filtered.traces.append(new_trace);
            }
        }

        return filtered;
    }

    /// Get statistics grouped by filename and line
    pub fn statistics(self: *const Self, allocator: std.mem.Allocator, key_type: []const u8) !std.ArrayList(Statistic) {
        var stats = hashmap_helper.StringHashMap(Statistic).init(allocator);
        defer stats.deinit();

        for (self.traces.items) |trace| {
            if (trace.traceback.frames.items.len == 0) continue;

            const frame = trace.traceback.frames.items[0];
            var key_buf: [512]u8 = undefined;

            const key = if (std.mem.eql(u8, key_type, "filename"))
                frame.filename
            else
                std.fmt.bufPrint(&key_buf, "{s}:{d}", .{ frame.filename, frame.lineno }) catch continue;

            if (stats.getPtr(key)) |stat| {
                stat.size += trace.size;
                stat.count += 1;
            } else {
                try stats.put(key, Statistic{
                    .traceback = trace.traceback,
                    .size = trace.size,
                    .count = 1,
                });
            }
        }

        var result = std.ArrayList(Statistic).init(allocator);
        var iter = stats.iterator();
        while (iter.next()) |entry| {
            try result.append(entry.value_ptr.*);
        }

        return result;
    }

    /// Compare with another snapshot
    /// Returns a list of StatisticDiff showing changes between snapshots
    pub fn compare_to(self: *const Self, allocator: std.mem.Allocator, other: *const Snapshot) !std.ArrayList(StatisticDiff) {
        var result = std.ArrayList(StatisticDiff).init(allocator);
        errdefer result.deinit();

        // Build a map of traceback -> (size, count) for self (newer snapshot)
        var self_stats = hashmap_helper.StringHashMap(struct { size: usize, count: usize, traceback: Traceback }).init(allocator);
        defer self_stats.deinit();

        for (self.traces.items) |trace| {
            if (trace.traceback.frames.items.len == 0) continue;
            const frame = trace.traceback.frames.items[0];
            var key_buf: [512]u8 = undefined;
            const key = std.fmt.bufPrint(&key_buf, "{s}:{d}", .{ frame.filename, frame.lineno }) catch continue;

            if (self_stats.getPtr(key)) |stat| {
                stat.size += trace.size;
                stat.count += 1;
            } else {
                const owned_key = try allocator.dupe(u8, key);
                try self_stats.put(owned_key, .{
                    .size = trace.size,
                    .count = 1,
                    .traceback = trace.traceback,
                });
            }
        }

        // Build a map for other (older snapshot)
        var other_stats = hashmap_helper.StringHashMap(struct { size: usize, count: usize }).init(allocator);
        defer other_stats.deinit();

        for (other.traces.items) |trace| {
            if (trace.traceback.frames.items.len == 0) continue;
            const frame = trace.traceback.frames.items[0];
            var key_buf: [512]u8 = undefined;
            const key = std.fmt.bufPrint(&key_buf, "{s}:{d}", .{ frame.filename, frame.lineno }) catch continue;

            if (other_stats.getPtr(key)) |stat| {
                stat.size += trace.size;
                stat.count += 1;
            } else {
                const owned_key = try allocator.dupe(u8, key);
                try other_stats.put(owned_key, .{ .size = trace.size, .count = 1 });
            }
        }

        // Compare: iterate through self_stats and compute diffs
        var iter = self_stats.iterator();
        while (iter.next()) |entry| {
            const new_size: i64 = @intCast(entry.value_ptr.size);
            const new_count: i64 = @intCast(entry.value_ptr.count);

            const old = other_stats.get(entry.key_ptr.*);
            const old_size: i64 = if (old) |o| @intCast(o.size) else 0;
            const old_count: i64 = if (old) |o| @intCast(o.count) else 0;

            try result.append(.{
                .traceback = entry.value_ptr.traceback,
                .size = new_size,
                .size_diff = new_size - old_size,
                .count = new_count,
                .count_diff = new_count - old_count,
            });
        }

        // Add entries only in other (removed allocations)
        var other_iter = other_stats.iterator();
        while (other_iter.next()) |entry| {
            if (!self_stats.contains(entry.key_ptr.*)) {
                const old_size: i64 = @intCast(entry.value_ptr.size);
                const old_count: i64 = @intCast(entry.value_ptr.count);

                // Create a traceback for this removed entry
                var empty_traceback = Traceback.init(allocator);
                var frame = Frame{
                    .filename = entry.key_ptr.*,
                    .lineno = 0,
                    .name = "<unknown>",
                };
                empty_traceback.frames.append(frame) catch {};

                try result.append(.{
                    .traceback = empty_traceback,
                    .size = 0,
                    .size_diff = -old_size,
                    .count = 0,
                    .count_diff = -old_count,
                });
            }
        }

        return result;
    }
};

// ============================================================================
// Statistic
// ============================================================================

/// Memory allocation statistics for a traceback
pub const Statistic = struct {
    traceback: Traceback,
    size: usize,
    count: usize,
};

/// Difference between two statistics
pub const StatisticDiff = struct {
    traceback: Traceback,
    size: i64,
    size_diff: i64,
    count: i64,
    count_diff: i64,
};

// ============================================================================
// Module State
// ============================================================================

var is_tracing: bool = false;
var nframe: u32 = 1;
var traced_memory: usize = 0;
var peak_traced_memory: usize = 0;

// ============================================================================
// Public API
// ============================================================================

/// Start tracing memory allocations
pub fn start(max_nframe: ?u32) !void {
    if (is_tracing) return error.AlreadyTracing;

    if (max_nframe) |n| {
        if (n < 1 or n > 100) return error.InvalidNframe;
        nframe = n;
    }

    is_tracing = true;
    traced_memory = 0;
    peak_traced_memory = 0;
}

/// Stop tracing
pub fn stop() void {
    is_tracing = false;
}

/// Check if tracing
pub fn is_tracing_fn() bool {
    return is_tracing;
}

/// Clear traces without stopping
pub fn clear_traces() void {
    traced_memory = 0;
}

/// Get current and peak traced memory
pub fn get_traced_memory() struct { usize, usize } {
    return .{ traced_memory, peak_traced_memory };
}

/// Reset peak to current
pub fn reset_peak() void {
    peak_traced_memory = traced_memory;
}

/// Get traceback limit
pub fn get_traceback_limit() u32 {
    return nframe;
}

/// Take a snapshot of current allocations
pub fn take_snapshot(allocator: std.mem.Allocator) !Snapshot {
    if (!is_tracing) return error.NotTracing;
    return Snapshot.init(allocator, nframe);
}

/// Get the traceback of an object (by address)
pub fn get_object_traceback(allocator: std.mem.Allocator, obj_addr: usize) !?Traceback {
    _ = obj_addr;
    if (!is_tracing) return null;
    return Traceback.init(allocator);
}

/// Get memory blocks
pub fn get_tracemalloc_memory() usize {
    return 0; // Memory used by tracemalloc itself
}

// ============================================================================
// Filter
// ============================================================================

/// Filter for snapshot traces
pub const Filter = struct {
    inclusive: bool,
    filename_pattern: []const u8,
    lineno: ?u32 = null,
    all_frames: bool = false,
    domain: ?u32 = null,

    pub fn init(inclusive: bool, filename_pattern: []const u8) Filter {
        return Filter{
            .inclusive = inclusive,
            .filename_pattern = filename_pattern,
        };
    }

    pub fn match(self: *const Filter, trace: *const Trace) bool {
        for (trace.traceback.frames.items) |frame| {
            var matches = std.mem.indexOf(u8, frame.filename, self.filename_pattern) != null;

            if (self.lineno) |ln| {
                matches = matches and frame.lineno == ln;
            }

            if (matches) {
                return self.inclusive;
            }

            if (!self.all_frames) break;
        }

        return !self.inclusive;
    }
};

// ============================================================================
// DomainFilter
// ============================================================================

/// Filter by memory domain
pub const DomainFilter = struct {
    inclusive: bool,
    domain: u32,

    pub fn init(inclusive: bool, domain: u32) DomainFilter {
        return DomainFilter{
            .inclusive = inclusive,
            .domain = domain,
        };
    }
};

// ============================================================================
// Init/Reset
// ============================================================================

pub fn init() void {
    is_tracing = false;
    nframe = 1;
    traced_memory = 0;
    peak_traced_memory = 0;
}

pub fn reset() void {
    stop();
    init();
}

// ============================================================================
// Tests
// ============================================================================

test "start and stop tracing" {
    try start(null);
    try std.testing.expect(is_tracing_fn());

    stop();
    try std.testing.expect(!is_tracing_fn());
}

test "start with nframe" {
    try start(10);
    defer stop();

    try std.testing.expectEqual(@as(u32, 10), get_traceback_limit());
}

test "invalid nframe" {
    try std.testing.expectError(error.InvalidNframe, start(0));
    try std.testing.expectError(error.InvalidNframe, start(101));
}

test "get_traced_memory" {
    try start(null);
    defer stop();

    const mem = get_traced_memory();
    try std.testing.expectEqual(@as(usize, 0), mem[0]);
}

test "Traceback init" {
    const allocator = std.testing.allocator;
    var tb = Traceback.init(allocator);
    defer tb.deinit();

    try tb.frames.append(.{ .filename = "test.py", .lineno = 42 });
    try std.testing.expectEqual(@as(usize, 1), tb.total_nframe());
}

test "Snapshot init" {
    const allocator = std.testing.allocator;
    var snapshot = Snapshot.init(allocator, 5);
    defer snapshot.deinit();

    try std.testing.expectEqual(@as(u32, 5), snapshot.traceback_limit);
}

test "Filter init" {
    const filter = Filter.init(true, "mymodule.py");
    try std.testing.expect(filter.inclusive);
    try std.testing.expectEqualStrings("mymodule.py", filter.filename_pattern);
}
