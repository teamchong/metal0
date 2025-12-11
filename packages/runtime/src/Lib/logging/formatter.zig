//! Log record formatting
//!
//! Formatters convert LogRecord instances into formatted text strings
//! using Python-style format strings like "%(levelname)s:%(name)s:%(message)s".

const std = @import("std");
const types = @import("types.zig");
const LogRecord = types.LogRecord;

// ============================================================================
// Formatter - Formats LogRecords
// ============================================================================

/// Formats LogRecord instances into text
pub const Formatter = struct {
    const Self = @This();

    format_str: []const u8,
    datefmt: ?[]const u8,
    allocator: std.mem.Allocator,

    /// Default format: "%(levelname)s:%(name)s:%(message)s"
    pub const DEFAULT_FORMAT = "%(levelname)s:%(name)s:%(message)s";

    pub fn init(allocator: std.mem.Allocator, fmt: ?[]const u8, datefmt: ?[]const u8) Self {
        return .{
            .allocator = allocator,
            .format_str = fmt orelse DEFAULT_FORMAT,
            .datefmt = datefmt,
        };
    }

    /// Format the specified record
    pub fn format(self: *Self, record: LogRecord) ![]u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        errdefer result.deinit();

        var i: usize = 0;
        const fmt = self.format_str;

        while (i < fmt.len) {
            if (i + 1 < fmt.len and fmt[i] == '%' and fmt[i + 1] == '(') {
                // Find the closing )s
                const start = i + 2;
                var end = start;
                while (end < fmt.len and fmt[end] != ')') : (end += 1) {}

                if (end + 1 < fmt.len and fmt[end] == ')' and fmt[end + 1] == 's') {
                    const field_name = fmt[start..end];
                    const value = self.getField(record, field_name);
                    try result.appendSlice(value);
                    i = end + 2;
                    continue;
                }
            }
            try result.append(fmt[i]);
            i += 1;
        }

        return result.toOwnedSlice();
    }

    fn getField(self: *Self, record: LogRecord, field: []const u8) []const u8 {
        _ = self;
        if (std.mem.eql(u8, field, "name")) return record.name;
        if (std.mem.eql(u8, field, "levelname")) return record.levelname;
        if (std.mem.eql(u8, field, "message")) return record.msg;
        if (std.mem.eql(u8, field, "pathname")) return record.pathname;
        if (std.mem.eql(u8, field, "filename")) return record.filename;
        if (std.mem.eql(u8, field, "module")) return record.module_name;
        if (std.mem.eql(u8, field, "funcName")) return record.funcname;
        return "";
    }

    /// Format the time
    pub fn formatTime(self: *Self, record: LogRecord) ![]u8 {
        _ = record;
        // Simplified time formatting
        var buf: [32]u8 = undefined;
        const now = std.time.timestamp();
        const len = std.fmt.formatIntBuf(&buf, now, 10, .lower, .{});
        return try self.allocator.dupe(u8, buf[0..len]);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Formatter" {
    const allocator = std.testing.allocator;

    var formatter = Formatter.init(allocator, "%(levelname)s - %(message)s", null);
    const record = LogRecord.init("test", types.INFO, "test message");

    const formatted = try formatter.format(record);
    defer allocator.free(formatted);

    try std.testing.expectEqualStrings("INFO - test message", formatted);
}
