/// Fast path: Try to parse source as a simple Python literal
/// Returns PyObject if successful, null if not a simple literal
/// Handles: numeric literals (with underscores), bools, None, string literals
const std = @import("std");
const PyObject = @import("../../runtime.zig").PyObject;

/// Fast path: Try to parse source as a simple Python literal
/// Returns PyObject if successful, null if not a simple literal
/// Handles: numeric literals (with underscores), bools, None, string literals
pub fn tryParseLiteral(allocator: std.mem.Allocator, source: []const u8) ?*PyObject {
    const PyInt = @import("../../Objects/intobject.zig").PyInt;
    const PyFloat = @import("../../Objects/floatobject.zig").PyFloat;
    const PyBool = @import("../../Objects/boolobject.zig").PyBool;
    const PyString = @import("../../Objects/stringlib/core.zig").PyString;
    const runtime = @import("../../runtime.zig");

    // Trim whitespace
    const trimmed = std.mem.trim(u8, source, " \t\n\r");
    if (trimmed.len == 0) return null;

    // Try bool literals
    if (std.mem.eql(u8, trimmed, "True")) {
        return PyBool.create(allocator, true) catch return null;
    }
    if (std.mem.eql(u8, trimmed, "False")) {
        return PyBool.create(allocator, false) catch return null;
    }

    // Try None (Py_None is a singleton, no allocation needed)
    if (std.mem.eql(u8, trimmed, "None")) {
        return runtime.Py_None;
    }

    // Try float literal (handles underscores, inf, nan)
    if (tryParseFloatLiteral(trimmed)) |f| {
        return PyFloat.create(allocator, f) catch return null;
    }

    // Try int literal (handles underscores)
    if (tryParseIntLiteral(trimmed)) |i| {
        return PyInt.create(allocator, i) catch return null;
    }

    // Try string literal ('...' or "...")
    if (tryParseStringLiteral(allocator, trimmed)) |s| {
        return PyString.create(allocator, s) catch return null;
    }

    return null;
}

/// Validate underscore placement in Python numeric literal
/// Returns false if:
/// - starts with underscore
/// - ends with underscore
/// - has consecutive underscores
/// - underscore adjacent to . or e/E without digit in between
fn validateUnderscores(s: []const u8) bool {
    if (s.len == 0) return true;
    // Can't start with underscore (after optional sign)
    var start: usize = 0;
    if (s[0] == '-' or s[0] == '+') start = 1;
    if (start < s.len and s[start] == '_') return false;
    // Can't end with underscore
    if (s[s.len - 1] == '_') return false;
    // Check for consecutive underscores and underscore adjacent to special chars
    var prev: u8 = 0;
    for (s) |c| {
        if (c == '_') {
            // Consecutive underscores
            if (prev == '_') return false;
            // Underscore after . or e/E
            if (prev == '.' or prev == 'e' or prev == 'E') return false;
        } else if (c == '.' or c == 'e' or c == 'E') {
            // These chars after underscore is invalid
            if (prev == '_') return false;
        }
        prev = c;
    }
    return true;
}

/// Parse float literal with underscore support
/// "1_000.0" → 1000.0, "inf" → inf, "nan" → nan
fn tryParseFloatLiteral(s: []const u8) ?f64 {
    // Handle special values first
    if (std.mem.eql(u8, s, "inf") or std.mem.eql(u8, s, "Infinity")) {
        return std.math.inf(f64);
    }
    if (std.mem.eql(u8, s, "-inf") or std.mem.eql(u8, s, "-Infinity")) {
        return -std.math.inf(f64);
    }
    if (std.mem.eql(u8, s, "nan") or std.mem.eql(u8, s, "NaN")) {
        return std.math.nan(f64);
    }

    // Must contain a decimal point, 'e', or 'E' to be a float
    var has_float_char = false;
    for (s) |c| {
        if (c == '.' or c == 'e' or c == 'E') {
            has_float_char = true;
            break;
        }
    }
    if (!has_float_char) return null;

    // Validate underscore placement (Python rules)
    if (!validateUnderscores(s)) return null;

    // Strip underscores and parse
    var buf: [256]u8 = undefined;
    var len: usize = 0;
    for (s) |c| {
        if (c != '_') {
            if (len >= buf.len) return null;
            buf[len] = c;
            len += 1;
        }
    }
    if (len == 0) return null;

    return std.fmt.parseFloat(f64, buf[0..len]) catch null;
}

/// Validate underscore placement in int literal (after base prefix)
/// Note: In Python, underscore CAN appear right after base prefix (0b_0, 0x_f, 0o_5)
/// So we only check: no trailing underscore, no consecutive underscores, must have digits
fn validateIntUnderscores(s: []const u8) bool {
    if (s.len == 0) return true;
    // Can't end with underscore
    if (s[s.len - 1] == '_') return false;
    // Check for consecutive underscores and ensure at least one digit
    var prev: u8 = 0;
    var has_digit = false;
    for (s) |c| {
        if (c == '_' and prev == '_') return false;
        if (c != '_') has_digit = true;
        prev = c;
    }
    // Must have at least one digit
    return has_digit;
}

/// Parse int literal with underscore support
/// "1_000" → 1000, "0x1_000" → 4096, "0b1010" → 10
fn tryParseIntLiteral(s: []const u8) ?i64 {
    if (s.len == 0) return null;

    // Determine base and skip prefix
    var base: u8 = 10;
    var start: usize = 0;
    var negative = false;

    if (s[0] == '-') {
        negative = true;
        start = 1;
    } else if (s[0] == '+') {
        start = 1;
    }

    if (start < s.len and s[start] == '0' and start + 1 < s.len) {
        const next = s[start + 1];
        if (next == 'x' or next == 'X') {
            base = 16;
            start += 2;
        } else if (next == 'o' or next == 'O') {
            base = 8;
            start += 2;
        } else if (next == 'b' or next == 'B') {
            base = 2;
            start += 2;
        }
    }

    // Validate underscore placement in the number part
    const num_part = s[start..];
    if (!validateIntUnderscores(num_part)) return null;

    // Strip underscores and parse
    var buf: [256]u8 = undefined;
    var len: usize = 0;
    for (num_part) |c| {
        if (c != '_') {
            if (len >= buf.len) return null;
            buf[len] = c;
            len += 1;
        }
    }
    if (len == 0) return null;

    const value = std.fmt.parseInt(i64, buf[0..len], base) catch return null;
    return if (negative) -value else value;
}

/// Parse string literal ('...' or "...")
fn tryParseStringLiteral(allocator: std.mem.Allocator, s: []const u8) ?[]const u8 {
    if (s.len < 2) return null;

    const quote = s[0];
    if (quote != '\'' and quote != '"') return null;
    if (s[s.len - 1] != quote) return null;

    // Extract content between quotes (simple case, no escape handling for now)
    const content = s[1 .. s.len - 1];
    return allocator.dupe(u8, content) catch null;
}
