//! CPython source: Lib/trace.py
//!
//! Provides a way to trace program execution and generate coverage reports.
//!
//! Mirrors: CPython Lib/trace.py

const std = @import("std");

// ============================================================================
// CoverageResults
// ============================================================================

/// Results of coverage analysis
pub const CoverageResults = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Map of filename -> set of executed line numbers
    counts: std.StringHashMap(std.AutoHashMap(usize, u64)),
    /// Map of filename -> set of all line numbers in file
    counter: std.StringHashMap(std.AutoHashMap(usize, void)),
    /// Modules to include
    calledfuncs: std.StringHashMap(void),
    /// Modules to exclude
    callers: std.StringHashMap(std.StringHashMap(void)),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .counts = std.StringHashMap(std.AutoHashMap(usize, u64)).init(allocator),
            .counter = std.StringHashMap(std.AutoHashMap(usize, void)).init(allocator),
            .calledfuncs = std.StringHashMap(void).init(allocator),
            .callers = std.StringHashMap(std.StringHashMap(void)).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var counts_iter = self.counts.iterator();
        while (counts_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.counts.deinit();

        var counter_iter = self.counter.iterator();
        while (counter_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.counter.deinit();

        self.calledfuncs.deinit();

        var callers_iter = self.callers.iterator();
        while (callers_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.callers.deinit();
    }

    /// Update with another CoverageResults
    pub fn update(self: *Self, other: *const Self) !void {
        var iter = other.counts.iterator();
        while (iter.next()) |entry| {
            const filename = entry.key_ptr.*;
            if (self.counts.getPtr(filename)) |existing| {
                var other_iter = entry.value_ptr.iterator();
                while (other_iter.next()) |line_entry| {
                    const line = line_entry.key_ptr.*;
                    const count = line_entry.value_ptr.*;
                    if (existing.getPtr(line)) |existing_count| {
                        existing_count.* += count;
                    } else {
                        try existing.put(line, count);
                    }
                }
            } else {
                var new_map = std.AutoHashMap(usize, u64).init(self.allocator);
                var other_iter = entry.value_ptr.iterator();
                while (other_iter.next()) |line_entry| {
                    try new_map.put(line_entry.key_ptr.*, line_entry.value_ptr.*);
                }
                try self.counts.put(filename, new_map);
            }
        }
    }

    /// Write coverage data to file
    pub fn writeCoverageData(self: *Self, filename: []const u8) !void {
        const file = try std.fs.cwd().createFile(filename, .{});
        defer file.close();

        var writer = file.writer();
        var iter = self.counts.iterator();
        while (iter.next()) |entry| {
            const fname = entry.key_ptr.*;
            var line_iter = entry.value_ptr.iterator();
            while (line_iter.next()) |line_entry| {
                try writer.print("{s}:{d}:{d}\n", .{
                    fname,
                    line_entry.key_ptr.*,
                    line_entry.value_ptr.*,
                });
            }
        }
    }

    /// Get coverage statistics
    pub fn getStats(self: *const Self) struct {
        files: usize,
        lines: usize,
        executed: usize,
    } {
        var total_lines: usize = 0;
        var executed_lines: usize = 0;

        var iter = self.counter.iterator();
        while (iter.next()) |entry| {
            total_lines += entry.value_ptr.count();
            if (self.counts.get(entry.key_ptr.*)) |counts| {
                executed_lines += counts.count();
            }
        }

        return .{
            .files = self.counter.count(),
            .lines = total_lines,
            .executed = executed_lines,
        };
    }

    /// Calculate coverage percentage
    pub fn getCoveragePercent(self: *const Self) f64 {
        const stats = self.getStats();
        if (stats.lines == 0) return 100.0;
        return @as(f64, @floatFromInt(stats.executed)) / @as(f64, @floatFromInt(stats.lines)) * 100.0;
    }
};

// ============================================================================
// Trace
// ============================================================================

/// Program execution tracer
pub const Trace = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    /// Count executed lines
    count: bool = true,
    /// Trace executed lines
    trace: bool = false,
    /// Count called functions
    countfuncs: bool = false,
    /// Track caller relationships
    countcallers: bool = false,
    /// Ignore directories
    ignoredirs: std.ArrayList([]const u8),
    /// Ignore modules
    ignoremods: std.ArrayList([]const u8),
    /// Results of tracing
    results: CoverageResults,
    /// Output file for trace
    outfile: ?std.fs.File = null,

    pub fn init(
        allocator: std.mem.Allocator,
        count: bool,
        trace: bool,
        countfuncs: bool,
        countcallers: bool,
    ) Self {
        return .{
            .allocator = allocator,
            .count = count,
            .trace = trace,
            .countfuncs = countfuncs,
            .countcallers = countcallers,
            .ignoredirs = std.ArrayList([]const u8).init(allocator),
            .ignoremods = std.ArrayList([]const u8).init(allocator),
            .results = CoverageResults.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.ignoredirs.deinit();
        self.ignoremods.deinit();
        self.results.deinit();
        if (self.outfile) |*f| {
            f.close();
        }
    }

    /// Record a line being executed
    pub fn recordLine(self: *Self, filename: []const u8, lineno: usize) !void {
        if (!self.count) return;

        // Get or create line counts for this file
        const counts = self.results.counts.getPtr(filename) orelse blk: {
            try self.results.counts.put(filename, std.AutoHashMap(usize, u64).init(self.allocator));
            break :blk self.results.counts.getPtr(filename).?;
        };

        if (counts.getPtr(lineno)) |count| {
            count.* += 1;
        } else {
            try counts.put(lineno, 1);
        }

        // Trace output
        if (self.trace) {
            const stdout = std.io.getStdOut().writer();
            try stdout.print("{s}:{d}\n", .{ filename, lineno });
        }
    }

    /// Record a function call
    pub fn recordCall(self: *Self, filename: []const u8, funcname: []const u8) !void {
        if (!self.countfuncs) return;

        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ filename, funcname });
        try self.results.calledfuncs.put(key, {});
    }

    /// Get the results
    pub fn getResults(self: *Self) *CoverageResults {
        return &self.results;
    }

    /// Run a function under the tracer
    pub fn runfunc(self: *Self, comptime func: anytype, args: anytype) @TypeOf(@call(.auto, func, args)) {
        _ = self;
        return @call(.auto, func, args);
    }

    /// Write results to file
    pub fn writeResults(self: *Self, filename: []const u8) !void {
        try self.results.writeCoverageData(filename);
    }
};

// ============================================================================
// Module Functions
// ============================================================================

/// Create a Trace object
pub fn createTrace(
    allocator: std.mem.Allocator,
    count: bool,
    trace: bool,
    countfuncs: bool,
    countcallers: bool,
) Trace {
    return Trace.init(allocator, count, trace, countfuncs, countcallers);
}

// ============================================================================
// Coverage Ignore Patterns
// ============================================================================

/// Default directories to ignore
pub const default_ignoredirs: []const []const u8 = &.{
    "/usr/lib/python",
    "/usr/local/lib/python",
};

/// Check if a path should be ignored
pub fn shouldIgnore(path: []const u8, ignoredirs: []const []const u8) bool {
    for (ignoredirs) |dir| {
        if (std.mem.startsWith(u8, path, dir)) {
            return true;
        }
    }
    return false;
}

// ============================================================================
// Module State
// ============================================================================

var initialized: bool = false;

/// Initialize the trace module
pub fn init() void {
    if (initialized) return;
    initialized = true;
}

/// Reset module state
pub fn reset() void {
    initialized = false;
}

// ============================================================================
// Tests
// ============================================================================

test "CoverageResults init" {
    const allocator = std.testing.allocator;
    var results = CoverageResults.init(allocator);
    defer results.deinit();

    try std.testing.expectEqual(@as(usize, 0), results.counts.count());
}

test "CoverageResults getStats empty" {
    const allocator = std.testing.allocator;
    var results = CoverageResults.init(allocator);
    defer results.deinit();

    const stats = results.getStats();
    try std.testing.expectEqual(@as(usize, 0), stats.files);
    try std.testing.expectEqual(@as(usize, 0), stats.lines);
    try std.testing.expectEqual(@as(usize, 0), stats.executed);
}

test "CoverageResults getCoveragePercent empty" {
    const allocator = std.testing.allocator;
    var results = CoverageResults.init(allocator);
    defer results.deinit();

    const percent = results.getCoveragePercent();
    try std.testing.expectEqual(@as(f64, 100.0), percent);
}

test "Trace init" {
    const allocator = std.testing.allocator;
    var tracer = Trace.init(allocator, true, false, false, false);
    defer tracer.deinit();

    try std.testing.expect(tracer.count);
    try std.testing.expect(!tracer.trace);
    try std.testing.expect(!tracer.countfuncs);
}

test "Trace recordLine" {
    const allocator = std.testing.allocator;
    var tracer = Trace.init(allocator, true, false, false, false);
    defer tracer.deinit();

    try tracer.recordLine("test.py", 10);
    try tracer.recordLine("test.py", 10);
    try tracer.recordLine("test.py", 11);

    const counts = tracer.results.counts.get("test.py").?;
    try std.testing.expectEqual(@as(u64, 2), counts.get(10).?);
    try std.testing.expectEqual(@as(u64, 1), counts.get(11).?);
}

test "shouldIgnore" {
    const dirs = &[_][]const u8{ "/usr/lib", "/opt" };
    try std.testing.expect(shouldIgnore("/usr/lib/python/test.py", dirs));
    try std.testing.expect(shouldIgnore("/opt/module.py", dirs));
    try std.testing.expect(!shouldIgnore("/home/user/test.py", dirs));
}

test "createTrace" {
    const allocator = std.testing.allocator;
    var tracer = createTrace(allocator, true, true, false, false);
    defer tracer.deinit();

    try std.testing.expect(tracer.count);
    try std.testing.expect(tracer.trace);
}
