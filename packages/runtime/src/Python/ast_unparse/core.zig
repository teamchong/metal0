/// AST Unparse Core
/// Core unparsing state and basic operations

const std = @import("std");
const Allocator = std.mem.Allocator;

const types = @import("types.zig");
const ConstantValue = types.ConstantValue;

// ============================================================================
// AST Unparser
// ============================================================================

/// AST Unparser state
pub const Unparser = struct {
    const Self = @This();

    allocator: Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .buffer = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit(self.allocator);
    }

    /// Reset buffer for reuse
    pub fn reset(self: *Self) void {
        self.buffer.clearRetainingCapacity();
    }

    /// Get the result string
    pub fn getResult(self: *const Self) []const u8 {
        return self.buffer.items;
    }

    /// Append a character
    pub fn appendChar(self: *Self, ch: u8) !void {
        try self.buffer.append(self.allocator, ch);
    }

    /// Append a string
    pub fn appendStr(self: *Self, str: []const u8) !void {
        try self.buffer.appendSlice(self.allocator, str);
    }

    /// Append string representation of an integer
    pub fn appendInt(self: *Self, value: i64) !void {
        var buf: [32]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return error.FormatError;
        try self.appendStr(str);
    }

    /// Append string representation of a float
    pub fn appendFloat(self: *Self, value: f64) !void {
        var buf: [64]u8 = undefined;

        // Handle infinity
        if (std.math.isInf(value)) {
            if (value < 0) {
                try self.appendStr("-1e309");
            } else {
                try self.appendStr("1e309");
            }
            return;
        }

        const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return error.FormatError;
        try self.appendStr(str);
    }

    /// Append a repr-style string
    pub fn appendRepr(self: *Self, str: []const u8) !void {
        try self.appendChar('\'');
        for (str) |c| {
            switch (c) {
                '\'' => try self.appendStr("\\'"),
                '\\' => try self.appendStr("\\\\"),
                '\n' => try self.appendStr("\\n"),
                '\r' => try self.appendStr("\\r"),
                '\t' => try self.appendStr("\\t"),
                else => {
                    if (c < 32 or c >= 127) {
                        var buf: [8]u8 = undefined;
                        const hex = std.fmt.bufPrint(&buf, "\\x{x:0>2}", .{c}) catch return error.FormatError;
                        try self.appendStr(hex);
                    } else {
                        try self.appendChar(c);
                    }
                },
            }
        }
        try self.appendChar('\'');
    }

    /// Unparse a constant value
    pub fn unparseConstant(self: *Self, value: ConstantValue) !void {
        switch (value) {
            .none => try self.appendStr("None"),
            .true_val => try self.appendStr("True"),
            .false_val => try self.appendStr("False"),
            .ellipsis => try self.appendStr("..."),
            .int_val => |v| try self.appendInt(v),
            .float_val => |v| try self.appendFloat(v),
            .str_val => |v| try self.appendRepr(v),
            .bytes_val => |v| {
                try self.appendStr("b");
                try self.appendRepr(v);
            },
        }
    }

    /// Unparse a name
    pub fn unparseName(self: *Self, name: []const u8) !void {
        try self.appendStr(name);
    }
};
