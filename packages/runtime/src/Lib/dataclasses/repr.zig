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

    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try result.appendSlice(@typeName(T));
    try result.append('(');

    const fields = @typeInfo(T).@"struct".fields;
    inline for (fields, 0..) |fld, i| {
        if (i > 0) {
            try result.appendSlice(", ");
        }
        try result.appendSlice(fld.name);
        try result.append('=');

        const field_value = @field(self.data, fld.name);
        try formatField(&result, field_value);
    }

    try result.append(')');
    return result.toOwnedSlice();
}

/// Format a single field value for display
fn formatField(result: *std.ArrayList(u8), value: anytype) !void {
    const VT = @TypeOf(value);
    const vt_info = @typeInfo(VT);

    switch (vt_info) {
        .int, .comptime_int => {
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
            try result.appendSlice(str);
        },
        .float, .comptime_float => {
            var buf: [32]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return;
            try result.appendSlice(str);
        },
        .bool => {
            try result.appendSlice(if (value) "True" else "False");
        },
        .pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) {
                try result.append('\'');
                try result.appendSlice(value);
                try result.append('\'');
            } else {
                try result.appendSlice("<pointer>");
            }
        },
        .optional => {
            if (value) |v| {
                try formatField(result, v);
            } else {
                try result.appendSlice("None");
            }
        },
        else => {
            try result.appendSlice("<...>");
        },
    }
}
