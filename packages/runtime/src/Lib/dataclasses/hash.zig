//! Hashing operations for dataclasses
//!
//! Generates __hash__ methods for dataclass instances
//! and related field hashing utilities.

const std = @import("std");

/// Generate hash for a dataclass instance
pub fn instanceHash(comptime T: type, self: anytype) u64 {
    var h: u64 = 0;
    const fields = @typeInfo(T).@"struct".fields;
    inline for (fields) |fld| {
        const field_value = @field(self.data, fld.name);
        h = hashCombine(h, hashField(field_value));
    }
    return h;
}

/// Generate hash for a single field value
fn hashField(value: anytype) u64 {
    const VT = @TypeOf(value);
    const vt_info = @typeInfo(VT);

    switch (vt_info) {
        .int, .comptime_int => return @as(u64, @intCast(@abs(value))),
        .float => return @as(u64, @bitCast(@as(i64, @intFromFloat(value * 1000000)))),
        .bool => return if (value) 1 else 0,
        .pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) {
                var h: u64 = 0;
                for (value) |c| {
                    h = hashCombine(h, c);
                }
                return h;
            }
            return @intFromPtr(value);
        },
        .optional => {
            if (value) |v| {
                return hashField(v);
            }
            return 0;
        },
        else => return 0,
    }
}

/// Combine two hash values
fn hashCombine(h1: u64, h2: u64) u64 {
    return h1 ^ (h2 +% 0x9e3779b9 +% (h1 << 6) +% (h1 >> 2));
}
