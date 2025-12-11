/// UserString - Wrapper around string for easier subclassing
const std = @import("std");
const Allocator = std.mem.Allocator;

/// UserString - A wrapper around string objects for easier subclassing
pub const UserString = struct {
    data: []const u8,
    allocator: Allocator,
    owned: bool = false,

    const Self = @This();

    pub fn init(allocator: Allocator, str: []const u8) Self {
        return .{
            .data = str,
            .allocator = allocator,
            .owned = false,
        };
    }

    pub fn initOwned(allocator: Allocator, str: []const u8) !Self {
        const owned_str = try allocator.dupe(u8, str);
        return .{
            .data = owned_str,
            .allocator = allocator,
            .owned = true,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.owned) {
            self.allocator.free(@constCast(self.data));
        }
    }

    pub fn len(self: Self) usize {
        return self.data.len;
    }

    pub fn get(self: Self, index: usize) ?u8 {
        if (index >= self.data.len) return null;
        return self.data[index];
    }

    pub fn slice(self: Self, start: usize, end: usize) []const u8 {
        const s = @min(start, self.data.len);
        const e = @min(end, self.data.len);
        return self.data[s..e];
    }

    pub fn contains(self: Self, substr: []const u8) bool {
        return std.mem.indexOf(u8, self.data, substr) != null;
    }

    pub fn startswith(self: Self, prefix: []const u8) bool {
        return std.mem.startsWith(u8, self.data, prefix);
    }

    pub fn endswith(self: Self, suffix: []const u8) bool {
        return std.mem.endsWith(u8, self.data, suffix);
    }

    pub fn find(self: Self, substr: []const u8) ?usize {
        return std.mem.indexOf(u8, self.data, substr);
    }

    pub fn rfind(self: Self, substr: []const u8) ?usize {
        return std.mem.lastIndexOf(u8, self.data, substr);
    }

    pub fn count(self: Self, substr: []const u8) usize {
        var c: usize = 0;
        var i: usize = 0;
        while (std.mem.indexOfPos(u8, self.data, i, substr)) |pos| {
            c += 1;
            i = pos + substr.len;
        }
        return c;
    }

    pub fn upper(self: *Self) !Self {
        var result = try self.allocator.alloc(u8, self.data.len);
        for (self.data, 0..) |c, i| {
            result[i] = std.ascii.toUpper(c);
        }
        return .{
            .data = result,
            .allocator = self.allocator,
            .owned = true,
        };
    }

    pub fn lower(self: *Self) !Self {
        var result = try self.allocator.alloc(u8, self.data.len);
        for (self.data, 0..) |c, i| {
            result[i] = std.ascii.toLower(c);
        }
        return .{
            .data = result,
            .allocator = self.allocator,
            .owned = true,
        };
    }

    pub fn strip(self: Self) []const u8 {
        return std.mem.trim(u8, self.data, " \t\n\r");
    }

    pub fn lstrip(self: Self) []const u8 {
        return std.mem.trimLeft(u8, self.data, " \t\n\r");
    }

    pub fn rstrip(self: Self) []const u8 {
        return std.mem.trimRight(u8, self.data, " \t\n\r");
    }

    pub fn isalpha(self: Self) bool {
        if (self.data.len == 0) return false;
        for (self.data) |c| {
            if (!std.ascii.isAlphabetic(c)) return false;
        }
        return true;
    }

    pub fn isdigit(self: Self) bool {
        if (self.data.len == 0) return false;
        for (self.data) |c| {
            if (!std.ascii.isDigit(c)) return false;
        }
        return true;
    }

    pub fn isalnum(self: Self) bool {
        if (self.data.len == 0) return false;
        for (self.data) |c| {
            if (!std.ascii.isAlphanumeric(c)) return false;
        }
        return true;
    }

    pub fn isspace(self: Self) bool {
        if (self.data.len == 0) return false;
        for (self.data) |c| {
            if (!std.ascii.isWhitespace(c)) return false;
        }
        return true;
    }

    pub fn replace(self: *Self, old: []const u8, new: []const u8) !Self {
        var result = std.ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var i: usize = 0;
        while (i < self.data.len) {
            if (i + old.len <= self.data.len and std.mem.eql(u8, self.data[i .. i + old.len], old)) {
                try result.appendSlice(self.allocator, new);
                i += old.len;
            } else {
                try result.append(self.allocator, self.data[i]);
                i += 1;
            }
        }

        const owned = try self.allocator.dupe(u8, result.items);
        return .{
            .data = owned,
            .allocator = self.allocator,
            .owned = true,
        };
    }

    pub fn toString(self: Self) []const u8 {
        return self.data;
    }
};
