//! Message generation
//!
//! Provides generator classes for converting messages to strings.

const std = @import("std");
const Message = @import("message.zig").Message;

/// Message generator
pub const Generator = struct {
    allocator: std.mem.Allocator,
    max_header_len: usize,

    pub fn init(allocator: std.mem.Allocator, max_header_len: usize) Generator {
        return .{
            .allocator = allocator,
            .max_header_len = max_header_len,
        };
    }

    pub fn flatten(self: *Generator, msg: *Message) ![]u8 {
        _ = self;
        return msg.asString();
    }
};

/// Bytes generator (alias for Generator)
pub const BytesGenerator = Generator;
