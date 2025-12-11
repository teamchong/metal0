/// syntax_errors - Syntax Error Handling
/// Mirrors cpython/Python/errors.c syntax error functions
///
/// This module provides functions for creating syntax errors with location information.

const formatting = @import("formatting.zig");

const format = formatting.format;

/// Set syntax error with location info
/// Mirrors: PyErr_SyntaxLocationObject
pub fn syntaxLocation(filename: ?[]const u8, lineno: i32, col_offset: i32) void {
    const fname = filename orelse "<unknown>";
    if (col_offset >= 0) {
        format("SyntaxError", "invalid syntax ({s}, line {d}, column {d})", .{ fname, lineno, col_offset });
    } else {
        format("SyntaxError", "invalid syntax ({s}, line {d})", .{ fname, lineno });
    }
}

/// Raise a SyntaxError with full location
/// Mirrors: _PyErr_RaiseSyntaxError
pub fn raiseSyntaxError(msg: []const u8, filename: ?[]const u8, lineno: i32, col_offset: i32, end_lineno: i32, end_col_offset: i32) void {
    _ = end_lineno;
    _ = end_col_offset;
    const fname = filename orelse "<unknown>";
    format("SyntaxError", "{s} ({s}, line {d}, col {d})", .{ msg, fname, lineno, col_offset });
}
