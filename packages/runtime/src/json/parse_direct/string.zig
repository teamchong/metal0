/// Parse JSON strings directly to PyString (optimized with lookup tables)
/// Supports lazy mode: borrows from source when no escapes (zero-copy)
const std = @import("std");
const runtime = @import("../../runtime.zig");
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;
const simd = @import("json_simd");
const parse_direct = @import("../parse_direct.zig");

/// Comptime hex digit lookup table (like Rust serde_json)
/// Returns 0-15 for valid hex, 255 for invalid
const HEX_TABLE: [256]u8 = blk: {
    var table: [256]u8 = [_]u8{255} ** 256;
    for ('0'..'9' + 1) |c| table[c] = @intCast(c - '0');
    for ('a'..'f' + 1) |c| table[c] = @intCast(c - 'a' + 10);
    for ('A'..'F' + 1) |c| table[c] = @intCast(c - 'A' + 10);
    break :blk table;
};

/// Parse 4 hex digits to u16 using lookup table (no branching)
inline fn parseHex4(hex: *const [4]u8) ?u16 {
    const a = HEX_TABLE[hex[0]];
    const b = HEX_TABLE[hex[1]];
    const c = HEX_TABLE[hex[2]];
    const d = HEX_TABLE[hex[3]];
    // Single check: if any is 255, result will overflow
    if ((a | b | c | d) > 15) return null;
    return (@as(u16, a) << 12) | (@as(u16, b) << 8) | (@as(u16, c) << 4) | @as(u16, d);
}

/// Parse JSON string directly to PyString (single SIMD pass for speed!)
/// If lazy_source is set and no escapes, borrows from source (zero-copy)
pub fn parseString(data: []const u8, pos: usize, allocator: std.mem.Allocator) JsonError!ParseResult(*runtime.PyObject) {
    if (pos >= data.len or data[pos] != '"') return JsonError.UnexpectedToken;

    const start = pos + 1; // Skip opening quote

    // Single-pass SIMD: find closing quote AND check for escapes simultaneously
    if (simd.findClosingQuoteAndEscapes(data[start..])) |result| {
        const i = start + result.quote_pos;
        const slice = data[start..i];

        // Check if we can use lazy/borrowed string
        const lazy_source = parse_direct.getLazySource();

        const py_str = if (!result.has_escapes and lazy_source != null)
            // Lazy path: borrow from source (zero-copy!)
            try runtime.PyString.createBorrowed(allocator, lazy_source.?, slice)
        else if (!result.has_escapes)
            // Eager path: copy the string
            try runtime.PyString.createOwned(allocator, try allocator.dupe(u8, slice))
        else
            // Has escapes: must unescape (always copies)
            try runtime.PyString.createOwned(allocator, try unescapeString(slice, allocator));

        return ParseResult(*runtime.PyObject).init(
            py_str,
            i + 1 - pos,
        );
    }

    return JsonError.UnexpectedEndOfInput;
}

/// Comptime escape character lookup table
const ESCAPE_CHARS: [256]u8 = blk: {
    var table: [256]u8 = [_]u8{0} ** 256;
    table['"'] = '"';
    table['\\'] = '\\';
    table['/'] = '/';
    table['b'] = '\x08';
    table['f'] = '\x0C';
    table['n'] = '\n';
    table['r'] = '\r';
    table['t'] = '\t';
    table['u'] = 'u'; // Special marker for unicode
    break :blk table;
};

/// Unescape a JSON string with escape sequences (optimized with bulk copy)
fn unescapeString(escaped: []const u8, allocator: std.mem.Allocator) JsonError![]const u8 {
    // Pre-allocate: result is at most same length as input (escapes shrink)
    var result = try allocator.alloc(u8, escaped.len);
    errdefer allocator.free(result);

    var write_pos: usize = 0;
    var read_pos: usize = 0;

    while (read_pos < escaped.len) {
        // Find next backslash using SIMD-friendly scan
        const chunk_start = read_pos;
        while (read_pos < escaped.len and escaped[read_pos] != '\\') : (read_pos += 1) {}

        // Bulk copy non-escaped chunk
        const chunk_len = read_pos - chunk_start;
        if (chunk_len > 0) {
            @memcpy(result[write_pos..][0..chunk_len], escaped[chunk_start..][0..chunk_len]);
            write_pos += chunk_len;
        }

        // Handle escape sequence
        if (read_pos < escaped.len and escaped[read_pos] == '\\') {
            read_pos += 1;
            if (read_pos >= escaped.len) {
                allocator.free(result);
                return JsonError.InvalidEscape;
            }

            const c = escaped[read_pos];
            const replacement = ESCAPE_CHARS[c];

            if (replacement == 'u') {
                // Unicode escape: \uXXXX
                if (read_pos + 4 >= escaped.len) {
                    allocator.free(result);
                    return JsonError.InvalidUnicode;
                }
                const hex = escaped[read_pos + 1 ..][0..4];
                const codepoint = parseHex4(hex) orelse {
                    allocator.free(result);
                    return JsonError.InvalidUnicode;
                };

                // Convert codepoint to UTF-8
                var utf8_buf: [4]u8 = undefined;
                const utf8_len = std.unicode.utf8Encode(@as(u21, codepoint), &utf8_buf) catch {
                    allocator.free(result);
                    return JsonError.InvalidUnicode;
                };
                @memcpy(result[write_pos..][0..utf8_len], utf8_buf[0..utf8_len]);
                write_pos += utf8_len;
                read_pos += 5; // Skip uXXXX
            } else if (replacement != 0) {
                result[write_pos] = replacement;
                write_pos += 1;
                read_pos += 1;
            } else {
                allocator.free(result);
                return JsonError.InvalidEscape;
            }
        }
    }

    // Shrink to actual size
    if (write_pos < result.len) {
        result = allocator.realloc(result, write_pos) catch result[0..write_pos];
    }
    return result[0..write_pos];
}
