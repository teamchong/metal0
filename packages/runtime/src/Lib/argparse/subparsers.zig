//! Subparsers support
//!
//! Provides SubparserGroup for handling subcommands.

const std = @import("std");
const hashmap_helper = @import("utils.hashmap_helper");

// Forward declare ArgumentParser to avoid circular dependency
// The type will be provided by the caller
pub const SubparserGroup = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    parsers: hashmap_helper.StringHashMap(*anyopaque), // Store as anyopaque to avoid circular dependency
    dest: []const u8,
    title: []const u8 = "subcommands",
    description: ?[]const u8 = null,
    required: bool = true,

    pub fn init(allocator: std.mem.Allocator, dest: []const u8) Self {
        return .{
            .allocator = allocator,
            .parsers = hashmap_helper.StringHashMap(*anyopaque).init(allocator),
            .dest = dest,
        };
    }

    pub fn deinit(self: *Self) void {
        self.parsers.deinit();
    }

    pub fn addParser(self: *Self, name: []const u8, parser: anytype) !void {
        try self.parsers.put(name, @ptrCast(parser));
    }

    pub fn getParser(self: Self, comptime T: type, name: []const u8) ?*T {
        if (self.parsers.get(name)) |ptr| {
            return @ptrCast(@alignCast(ptr));
        }
        return null;
    }
};
