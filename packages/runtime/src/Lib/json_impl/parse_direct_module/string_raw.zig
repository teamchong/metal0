/// Parse JSON string directly to raw []const u8 (for dict keys - no PyObject wrapper)
const std = @import("std");
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;
const json = @import("json");
const primitives = json.primitives;
const simd = json.simd;

/// Parse JSON string directly to raw string (no PyObject wrapper, single SIMD pass!)
/// This is used for dict keys where we don't need the PyString overhead
pub fn parseStringRaw(data: []const u8, pos: usize, allocator: std.mem.Allocator) JsonError!ParseResult([]const u8) {
    if (pos >= data.len or data[pos] != '"') return JsonError.UnexpectedToken;

    const start = pos + 1; // Skip opening quote

    // Single-pass SIMD: find closing quote AND check for escapes simultaneously
    if (simd.findClosingQuoteAndEscapes(data[start..])) |result| {
        const i = start + result.quote_pos;

        const str_data: []const u8 = if (!result.has_escapes)
            // Fast path: No escapes, just copy once
            try allocator.dupe(u8, data[start..i])
        else
            // Slow path: Need to unescape (use shared optimized primitives)
            primitives.unescapeString(data[start..i], allocator) catch return JsonError.InvalidEscape;

        return ParseResult([]const u8).init(
            str_data,
            i + 1 - pos,
        );
    }

    return JsonError.UnexpectedEndOfInput;
}
