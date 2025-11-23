/// JSON parsing and stringification errors
const std = @import("std");

/// JSON-specific errors
pub const JsonError = error{
    UnexpectedEndOfInput,
    UnexpectedToken,
    InvalidNumber,
    InvalidString,
    InvalidEscape,
    InvalidUnicode,
    TrailingComma,
    DuplicateKey,
    NumberOutOfRange,
    NestingTooDeep,
    InvalidUtf8,
    OutOfMemory,
};

/// Error context for better error messages
pub const ErrorContext = struct {
    line: usize,
    column: usize,
    position: usize,
    message: []const u8,

    pub fn init(pos: usize, msg: []const u8) ErrorContext {
        return .{
            .line = 0,
            .column = 0,
            .position = pos,
            .message = msg,
        };
    }

    pub fn format(self: ErrorContext, writer: anytype) !void {
        try writer.print("JSON error at position {}: {s}", .{ self.position, self.message });
    }
};

/// Result type for parsing operations
pub fn ParseResult(comptime T: type) type {
    return struct {
        value: T,
        consumed: usize, // How many bytes were consumed

        pub fn init(val: T, bytes: usize) @This() {
            return .{ .value = val, .consumed = bytes };
        }
    };
}
