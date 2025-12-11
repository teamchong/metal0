/// Parse JSON strings directly to PyString (optimized with lookup tables)
/// Supports lazy mode: borrows from source when no escapes (zero-copy)
const std = @import("std");
const runtime = @import("../../../runtime.zig");
const JsonError = @import("../errors.zig").JsonError;
const ParseResult = @import("../errors.zig").ParseResult;
const parse_direct = @import("../parse_direct.zig");
const json = @import("json");
const primitives = json.primitives;
const simd = json.simd;

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
            // Has escapes: must unescape (use shared primitives)
            try runtime.PyString.createOwned(allocator, primitives.unescapeString(slice, allocator) catch return JsonError.InvalidEscape);

        return ParseResult(*runtime.PyObject).init(
            py_str,
            i + 1 - pos,
        );
    }

    return JsonError.UnexpectedEndOfInput;
}
