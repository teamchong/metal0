/// constant - Constant Value Types
/// Mirrors cpython/Python/codegen.c constant handling
///
/// Defines the Constant union type for compile-time constant values.

const std = @import("std");

// ============================================================================
// Constant Types
// ============================================================================

/// Constant value
pub const Constant = union(enum) {
    none: void,
    ellipsis: void,
    boolean: bool,
    integer: i64,
    float: f64,
    complex: struct { real: f64, imag: f64 },
    string: []const u8,
    bytes: []const u8,
    tuple: []const Constant,
    frozenset: []const Constant,
    code: *anyopaque,

    pub fn eql(self: Constant, other: Constant) bool {
        return switch (self) {
            .none => other == .none,
            .ellipsis => other == .ellipsis,
            .boolean => |b| other == .boolean and other.boolean == b,
            .integer => |i| other == .integer and other.integer == i,
            .float => |f| other == .float and other.float == f,
            .string => |s| other == .string and std.mem.eql(u8, other.string, s),
            .bytes => |b| other == .bytes and std.mem.eql(u8, other.bytes, b),
            else => false,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "constant equality" {
    const c1 = Constant{ .integer = 42 };
    const c2 = Constant{ .integer = 42 };
    const c3 = Constant{ .integer = 43 };

    try std.testing.expect(c1.eql(c2));
    try std.testing.expect(!c1.eql(c3));

    const s1 = Constant{ .string = "hello" };
    const s2 = Constant{ .string = "hello" };
    const s3 = Constant{ .string = "world" };

    try std.testing.expect(s1.eql(s2));
    try std.testing.expect(!s1.eql(s3));
}
