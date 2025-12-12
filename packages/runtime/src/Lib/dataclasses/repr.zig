//! String representation for dataclasses
//!
//! Generates __repr__ methods and related formatting utilities
//! for converting dataclass instances to human-readable strings.

const std = @import("std");

/// Generated __repr__ method for a dataclass
/// Formats the dataclass instance as "ClassName(field1=value1, field2=value2, ...)"
pub fn generateRepr(comptime T: type, self: anytype, options: anytype, allocator: std.mem.Allocator) ![]u8 {
    if (!options.repr) {
        return allocator.dupe(u8, @typeName(T));
    }

    var result: std.ArrayList(u8) = .{};
    errdefer result.deinit(allocator);

    try result.appendSlice(allocator, @typeName(T));
    try result.append(allocator, '(');

    const fields = @typeInfo(T).@"struct".fields;
    inline for (fields, 0..) |fld, i| {
        if (i > 0) {
            try result.appendSlice(allocator, ", ");
        }
        try result.appendSlice(allocator, fld.name);
        try result.append(allocator, '=');

        const field_value = @field(self.data, fld.name);
        try formatField(allocator, &result, field_value);
    }

    try result.append(allocator, ')');
    return result.toOwnedSlice(allocator);
}

/// Format a single field value for display
fn formatField(allocator: std.mem.Allocator, result: *std.ArrayList(u8), value: anytype) !void {
    const VT = @TypeOf(value);
    const vt_info = @typeInfo(VT);

    switch (vt_info) {
        .int, .comptime_int => {
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
            try result.appendSlice(allocator, str);
        },
        .float, .comptime_float => {
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
            try result.appendSlice(allocator, str);
        },
        .bool => {
            try result.appendSlice(allocator, if (value) "True" else "False");
        },
        .pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) {
                try result.append(allocator, '\'');
                try result.appendSlice(allocator, value);
                try result.append(allocator, '\'');
            } else {
                try result.appendSlice(allocator, "<pointer>");
            }
        },
        .optional => {
            if (value) |v| {
                try formatField(allocator, result, v);
            } else {
                try result.appendSlice(allocator, "None");
            }
        },
        else => {
            try result.appendSlice(allocator, "<...>");
        },
    }
}
