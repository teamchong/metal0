//! Shared JSON library for PyAOT
//! Portable JSON parser/stringifier with no SIMD dependencies
//!
//! Usage:
//!   const json = @import("json");
//!   var parsed = try json.parse(allocator, input);
//!   defer parsed.deinit(allocator);
//!   var output = try json.stringify(allocator, value);

const std = @import("std");

pub const Value = @import("value.zig").Value;
pub const ParseError = @import("parse.zig").ParseError;
pub const StringifyError = @import("stringify.zig").StringifyError;

// Re-export utility functions from value.zig
pub const isWhitespace = @import("value.zig").isWhitespace;
pub const skipWhitespace = @import("value.zig").skipWhitespace;
pub const isEof = @import("value.zig").isEof;
pub const peek = @import("value.zig").peek;
pub const consume = @import("value.zig").consume;
pub const expect = @import("value.zig").expect;

/// Parse JSON string into Value
pub fn parse(allocator: std.mem.Allocator, input: []const u8) ParseError!Value {
    return @import("parse.zig").parse(allocator, input);
}

/// Stringify Value to JSON string (caller owns returned memory)
pub fn stringify(allocator: std.mem.Allocator, value: Value) StringifyError![]u8 {
    return @import("stringify.zig").stringify(allocator, value);
}

test {
    _ = @import("value.zig");
    _ = @import("parse.zig");
    _ = @import("stringify.zig");
}
