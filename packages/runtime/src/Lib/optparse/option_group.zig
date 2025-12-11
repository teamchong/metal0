//! CPython source: Lib/optparse.py
//!
//! Group of related options for help display.
//! Mirrors: CPython Lib/optparse.py

const std = @import("std");
const option = @import("option.zig");

const Option = option.Option;

// Forward declaration
pub const OptionParser = opaque {};

/// Group of related options for help display
pub const OptionGroup = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    parser: *OptionParser,
    title: []const u8,
    description: ?[]const u8,
    options: std.ArrayList(Option),

    pub fn init(allocator: std.mem.Allocator, parser: *OptionParser, title: []const u8) Self {
        return .{
            .allocator = allocator,
            .parser = parser,
            .title = title,
            .description = null,
            .options = std.ArrayList(Option).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.options.deinit();
    }

    pub fn addOption(self: *Self, opt: Option) !void {
        try self.options.append(opt);
    }
};
