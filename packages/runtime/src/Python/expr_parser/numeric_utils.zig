/// Numeric utility functions for parsing numbers
const std = @import("std");

/// Validate underscore placement in Python numeric literal
/// Returns error.InvalidNumber if:
/// - starts with underscore
/// - ends with underscore
/// - has consecutive underscores
/// - underscore adjacent to . or e/E without digit in between
fn validateNumericUnderscores(s: []const u8) error{InvalidNumber}!void {
    if (s.len == 0) return;
    // Can't start with underscore
    if (s[0] == '_') return error.InvalidNumber;
    // Can't end with underscore
    if (s[s.len - 1] == '_') return error.InvalidNumber;
    // Check for consecutive underscores and underscore adjacent to special chars
    var prev: u8 = 0;
    for (s) |c| {
        if (c == '_') {
            // Consecutive underscores
            if (prev == '_') return error.InvalidNumber;
            // Underscore after . or e/E
            if (prev == '.' or prev == 'e' or prev == 'E') return error.InvalidNumber;
        } else if (c == '.' or c == 'e' or c == 'E') {
            // These chars after underscore is invalid
            if (prev == '_') return error.InvalidNumber;
        }
        prev = c;
    }
}

/// Strip underscores from numeric literal (Python 3.6+ feature)
/// Uses a static buffer to avoid allocation and lifetime issues
var strip_buf: [64]u8 = undefined;

pub fn stripUnderscores(input: []const u8) error{ OutOfMemory, InvalidNumber }![]const u8 {
    // First validate underscore placement
    try validateNumericUnderscores(input);

    // Fast path: no underscores
    if (std.mem.indexOfScalar(u8, input, '_') == null) {
        return input;
    }
    // Use static buffer for small numbers
    var len: usize = 0;
    for (input) |c| {
        if (c != '_') {
            if (len >= strip_buf.len) return error.OutOfMemory; // Number too large for buffer
            strip_buf[len] = c;
            len += 1;
        }
    }
    // Handle case where result is empty (e.g., just "_")
    if (len == 0) return error.OutOfMemory;
    return strip_buf[0..len];
}
