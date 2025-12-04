/// Core types and helper functions for compile-time evaluation
const std = @import("std");
const ast = @import("ast");

/// Check if a list contains only literal values
pub fn isConstantList(list: []ast.Node) bool {
    if (list.len == 0) return false;

    for (list) |elem| {
        const is_literal = switch (elem) {
            .constant => true,
            else => false,
        };
        if (!is_literal) return false;
    }

    return true;
}

/// Check if all elements have the same type
pub fn allSameType(elements: []ast.Node) bool {
    if (elements.len == 0) return true;

    const first_const = switch (elements[0]) {
        .constant => |c| c,
        else => return false,
    };

    const first_type_tag = @as(std.meta.Tag(@TypeOf(first_const.value)), first_const.value);

    for (elements[1..]) |elem| {
        const elem_const = switch (elem) {
            .constant => |c| c,
            else => return false,
        };

        const elem_type_tag = @as(std.meta.Tag(@TypeOf(elem_const.value)), elem_const.value);
        if (elem_type_tag != first_type_tag) return false;
    }

    return true;
}

/// Compile-time value representation
pub const ComptimeValue = union(enum) {
    int: i64,
    float: f64,
    bool: bool,
    string: []const u8,
    list: []const ComptimeValue,
    // Owned variants - these need to be freed
    owned_string: []const u8,
    owned_list: []const ComptimeValue,

    /// Free any owned memory
    pub fn deinit(self: ComptimeValue, allocator: std.mem.Allocator) void {
        switch (self) {
            .owned_string => |s| allocator.free(s),
            .owned_list => |l| {
                for (l) |item| item.deinit(allocator);
                allocator.free(l);
            },
            else => {}, // Non-owned values don't need cleanup
        }
    }

    /// Get the string value regardless of ownership
    pub fn getString(self: ComptimeValue) ?[]const u8 {
        return switch (self) {
            .string => |s| s,
            .owned_string => |s| s,
            else => null,
        };
    }

    /// Check if this is a string (owned or borrowed)
    pub fn isString(self: ComptimeValue) bool {
        return self == .string or self == .owned_string;
    }

    /// Format the value as a string for debugging
    pub fn format(
        self: ComptimeValue,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .int => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .bool => |b| try writer.print("{}", .{b}),
            .string, .owned_string => |s| try writer.print("\"{s}\"", .{s}),
            .list, .owned_list => |l| {
                try writer.writeAll("[");
                for (l, 0..) |item, idx| {
                    if (idx > 0) try writer.writeAll(", ");
                    try writer.print("{}", .{item});
                }
                try writer.writeAll("]");
            },
        }
    }
};
