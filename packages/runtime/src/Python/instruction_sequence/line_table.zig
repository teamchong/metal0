/// Line number table builder
/// Maps bytecode offsets to source line numbers for debugging

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Line number table builder
pub const LineNumberTable = struct {
    const Self = @This();

    /// Entries: (instruction offset, line number)
    entries: std.ArrayList(struct { offset: usize, line: u32 }),
    /// Last line recorded
    last_line: u32 = 0,
    /// Allocator
    allocator: Allocator,

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .entries = std.ArrayList(struct { offset: usize, line: u32 }).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entries.deinit();
    }

    /// Add line number entry
    pub fn addEntry(self: *Self, offset: usize, line: u32) !void {
        if (line != self.last_line) {
            try self.entries.append(.{ .offset = offset, .line = line });
            self.last_line = line;
        }
    }

    /// Find line number for offset
    pub fn findLine(self: *const Self, offset: usize) u32 {
        var line: u32 = 0;
        for (self.entries.items) |entry| {
            if (entry.offset > offset) break;
            line = entry.line;
        }
        return line;
    }
};
