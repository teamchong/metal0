//! Core types for profile statistics
//!
//! Provides fundamental data structures for representing profiling data:
//! - SortKey: Enumeration of available sort criteria
//! - FuncId: Function identifier (filename, line, name)
//! - CallerInfo: Information about a function caller
//! - FuncStat: Statistics for a single function

const std = @import("std");

// ============================================================================
// Sort Keys
// ============================================================================

/// Sort keys for profile statistics
pub const SortKey = enum {
    calls,
    cumulative,
    cumtime,
    file,
    filename,
    module,
    ncalls,
    pcalls,
    line,
    name,
    nfl,
    stdname,
    time,
    tottime,

    /// Convert string to sort key
    pub fn fromString(s: []const u8) ?SortKey {
        const mapping = .{
            .{ "calls", .calls },
            .{ "cumulative", .cumulative },
            .{ "cumtime", .cumtime },
            .{ "file", .file },
            .{ "filename", .filename },
            .{ "module", .module },
            .{ "ncalls", .ncalls },
            .{ "pcalls", .pcalls },
            .{ "line", .line },
            .{ "name", .name },
            .{ "nfl", .nfl },
            .{ "stdname", .stdname },
            .{ "time", .time },
            .{ "tottime", .tottime },
        };

        inline for (mapping) |pair| {
            if (std.mem.eql(u8, s, pair[0])) {
                return pair[1];
            }
        }
        return null;
    }
};

// ============================================================================
// Function Identifier
// ============================================================================

/// Function identifier
pub const FuncId = struct {
    filename: []const u8,
    lineno: usize,
    name: []const u8,

    pub fn format(self: FuncId, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "{s}:{d}({s})", .{
            self.filename,
            self.lineno,
            self.name,
        });
    }
};

// ============================================================================
// Caller Information
// ============================================================================

/// Caller information
pub const CallerInfo = struct {
    calls: usize,
    total_time: f64,
    cumulative_time: f64,
};

// ============================================================================
// Function Statistics
// ============================================================================

/// Statistics for a single function
pub const FuncStat = struct {
    /// (filename, line, function)
    func_id: FuncId,
    /// Number of primitive calls (not recursive)
    primitive_calls: usize,
    /// Total calls (including recursive)
    total_calls: usize,
    /// Total time spent in function (excluding subcalls)
    total_time: f64,
    /// Cumulative time (including subcalls)
    cumulative_time: f64,
    /// Callers info
    callers: std.AutoHashMap(FuncId, CallerInfo),

    pub fn init(allocator: std.mem.Allocator, func_id: FuncId) FuncStat {
        return .{
            .func_id = func_id,
            .primitive_calls = 0,
            .total_calls = 0,
            .total_time = 0.0,
            .cumulative_time = 0.0,
            .callers = std.AutoHashMap(FuncId, CallerInfo).init(allocator),
        };
    }

    pub fn deinit(self: *FuncStat) void {
        self.callers.deinit();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "SortKey fromString" {
    try std.testing.expectEqual(SortKey.calls, SortKey.fromString("calls").?);
    try std.testing.expectEqual(SortKey.cumulative, SortKey.fromString("cumulative").?);
    try std.testing.expectEqual(SortKey.time, SortKey.fromString("time").?);
    try std.testing.expect(SortKey.fromString("invalid") == null);
}

test "FuncStat init" {
    const allocator = std.testing.allocator;
    const func_id = FuncId{
        .filename = "test.py",
        .lineno = 10,
        .name = "test_func",
    };

    var stat = FuncStat.init(allocator, func_id);
    defer stat.deinit();

    try std.testing.expectEqual(@as(usize, 0), stat.total_calls);
    try std.testing.expectEqual(@as(f64, 0.0), stat.total_time);
}

test "FuncId format" {
    const allocator = std.testing.allocator;
    const func_id = FuncId{
        .filename = "test.py",
        .lineno = 10,
        .name = "test_func",
    };

    const formatted = try func_id.format(allocator);
    defer allocator.free(formatted);

    try std.testing.expectEqualStrings("test.py:10(test_func)", formatted);
}
