//! Log record filtering
//!
//! Filters control which log records are output based on criteria such as
//! logger name hierarchy.

const std = @import("std");
const types = @import("types.zig");
const LogRecord = types.LogRecord;

// ============================================================================
// Filter - Controls which log records are output
// ============================================================================

/// Filters LogRecords based on criteria
pub const Filter = struct {
    const Self = @This();

    name: []const u8,
    nlen: usize,

    pub fn init(name: []const u8) Self {
        return .{
            .name = name,
            .nlen = name.len,
        };
    }

    /// Determine if the record should be logged
    pub fn filter(self: *Self, record: LogRecord) bool {
        if (self.nlen == 0) return true;
        if (std.mem.eql(u8, record.name, self.name)) return true;
        if (std.mem.startsWith(u8, record.name, self.name) and
            record.name.len > self.nlen and record.name[self.nlen] == '.')
        {
            return true;
        }
        return false;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Filter" {
    var f = Filter.init("myapp");

    const record1 = LogRecord.init("myapp", types.INFO, "msg");
    const record2 = LogRecord.init("myapp.sub", types.INFO, "msg");
    const record3 = LogRecord.init("other", types.INFO, "msg");

    try std.testing.expect(f.filter(record1));
    try std.testing.expect(f.filter(record2));
    try std.testing.expect(!f.filter(record3));
}
