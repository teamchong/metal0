//! Comparison operations for dataclasses
//!
//! Generates __eq__, __lt__, __le__, __gt__, __ge__ methods
//! and related field comparison utilities.

const std = @import("std");

/// Check equality between two dataclass instances
pub fn instancesEqual(comptime T: type, self: anytype, other: anytype, options: anytype) bool {
    if (!options.eq) return false;

    const fields = @typeInfo(T).@"struct".fields;
    inline for (fields) |fld| {
        const a = @field(self.data, fld.name);
        const b = @field(other.data, fld.name);
        if (!fieldsEqual(a, b)) return false;
    }
    return true;
}

/// Compare two field values for equality
fn fieldsEqual(a: anytype, b: @TypeOf(a)) bool {
    const AT = @TypeOf(a);
    const at_info = @typeInfo(AT);

    switch (at_info) {
        .pointer => |ptr| {
            if (ptr.size == .Slice) {
                return std.mem.eql(ptr.child, a, b);
            }
            return a == b;
        },
        .optional => {
            if (a == null and b == null) return true;
            if (a == null or b == null) return false;
            return fieldsEqual(a.?, b.?);
        },
        else => return a == b,
    }
}

/// Check if one dataclass instance is less than another
pub fn instanceLessThan(comptime T: type, self: anytype, other: anytype, options: anytype) bool {
    if (!options.order) return false;

    const fields = @typeInfo(T).@"struct".fields;
    inline for (fields) |fld| {
        const a = @field(self.data, fld.name);
        const b = @field(other.data, fld.name);
        if (compareFields(a, b)) |cmp| {
            if (cmp < 0) return true;
            if (cmp > 0) return false;
        }
    }
    return false;
}

/// Compare two field values with ordering
fn compareFields(a: anytype, b: @TypeOf(a)) ?i32 {
    const AT = @TypeOf(a);
    const at_info = @typeInfo(AT);

    switch (at_info) {
        .int, .comptime_int, .float, .comptime_float => {
            if (a < b) return -1;
            if (a > b) return 1;
            return 0;
        },
        .pointer => |ptr| {
            if (ptr.size == .Slice and ptr.child == u8) {
                return switch (std.mem.order(u8, a, b)) {
                    .lt => -1,
                    .gt => 1,
                    .eq => 0,
                };
            }
            return null;
        },
        else => return null,
    }
}

/// Check if one dataclass instance is less than or equal to another
pub fn instanceLessThanOrEqual(comptime T: type, self: anytype, other: anytype, options: anytype) bool {
    return instanceLessThan(T, self, other, options) or instancesEqual(T, self, other, options);
}

/// Check if one dataclass instance is greater than another
pub fn instanceGreaterThan(comptime T: type, self: anytype, other: anytype, options: anytype) bool {
    return instanceLessThan(T, other, self, options);
}

/// Check if one dataclass instance is greater than or equal to another
pub fn instanceGreaterThanOrEqual(comptime T: type, self: anytype, other: anytype, options: anytype) bool {
    return !instanceLessThan(T, self, other, options);
}
