/// Constant value code generation
/// Handles Python literals: int, float, bool, string, none
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// ============================================
// Constant helpers - auto-closing patterns
// ============================================

/// Emit quoted string: "content"
fn emitQuotedString(self: *NativeCodegen, content: []const u8, ctx: StringContext) CodegenError!void {
    try emitConst(self, "\"");
    try emitZigStringContent(self, content, ctx);
    try emitConst(self, "\"");
}

/// Emit bytes literal: runtime.builtins.bytesLiteral("content")
fn emitBytesLiteral(self: *NativeCodegen, content: []const u8) CodegenError!void {
    try emitConst(self, "runtime.builtins.bytesLiteral(\"");
    try emitZigStringContent(self, content, StringContext.bytes);
    try emitConst(self, "\")");
}

/// Emit PyComplex.create(real, imag)
fn emitComplexCreate(self: *NativeCodegen, real: f64, imag: f64) CodegenError!void {
    try emitConst(self, "runtime.PyComplex.create(");
    try self.output.writer(self.allocator).print("{d}", .{real});
    try emitConst(self, ", ");
    if (std.math.isInf(imag)) {
        try emitConst(self, if (imag < 0) "-std.math.inf(f64)" else "std.math.inf(f64)");
    } else if (std.math.isNan(imag)) {
        try emitConst(self, "std.math.nan(f64)");
    } else {
        try self.output.writer(self.allocator).print("{d}", .{imag});
    }
    try emitConst(self, ")");
}



/// String context for unified escape handling
pub const StringContext = struct {
    is_bytes: bool = false, // b"..." - \x is raw byte, no Unicode escapes
    escape_braces: bool = false, // For Zig format strings: { -> {{, } -> }}

    pub const default = StringContext{};
    pub const bytes = StringContext{ .is_bytes = true };
    pub const format_string = StringContext{ .escape_braces = true };
};

/// Generate constant values (int, float, bool, string, none)
pub fn genConstant(self: *NativeCodegen, constant: ast.Node.Constant) CodegenError!void {
    switch (constant.value) {
        .int => try self.output.writer(self.allocator).print("{d}", .{constant.value.int}),
        .bigint => |s| {
            // Large integers are now represented as UnifiedInt (auto-promotes i64 to BigInt)
            // Use unified_int_ops.fromBigIntVal to convert BigInt value to UnifiedInt
            // fromBigIntVal demotes to i64 if it fits, otherwise allocates BigInt on heap
            try self.output.writer(self.allocator).print("runtime.unified_int_ops.fromBigIntVal(__global_allocator, (runtime.parseIntToBigInt(__global_allocator, \"{s}\", 10) catch unreachable))", .{s});
        },
        .float => |f| {
            if (std.math.isInf(f)) {
                try emitConst(self, if (f < 0) "-std.math.inf(f64)" else "std.math.inf(f64)");
            } else if (std.math.isNan(f)) {
                try emitConst(self, "std.math.nan(f64)");
            } else if (@mod(f, 1.0) == 0.0) {
                try self.output.writer(self.allocator).print("@as(f64, {d:.1})", .{f});
            } else {
                try self.output.writer(self.allocator).print("@as(f64, {d})", .{f});
            }
        },
        .bool => try emitConst(self, if (constant.value.bool) "true" else "false"),
        .none => try emitConst(self, "null"),
        .complex => |imag| {
            // Handle inf/nan in imaginary part like we do for floats
            try emitComplexCreate(self, 0.0, imag);
        },
        .string => |s| {
            // String content already has quotes stripped by parser
            try emitQuotedString(self, s, StringContext.default);
        },
        .bytes => |s| {
            // Bytes content: use runtime helper to preserve Python bytes type
            // This enables repr() to correctly output b'...' format
            try emitBytesLiteral(self, s);
        },
    }
}

/// Strip Python quotes from string literal (handles single, double, triple quotes)
pub fn stripPythonQuotes(s: []const u8) []const u8 {
    if (s.len >= 6 and (std.mem.startsWith(u8, s, "'''") or std.mem.startsWith(u8, s, "\"\"\""))) {
        var inner = s[3 .. s.len - 3];
        // Handle line continuation: '''\<newline>
        if (inner.len > 0 and inner[0] == '\\') {
            if (inner.len > 1 and inner[1] == '\n') {
                inner = inner[2..];
            } else if (inner.len > 2 and inner[1] == '\r' and inner[2] == '\n') {
                inner = inner[3..];
            }
        }
        return inner;
    } else if (s.len >= 2) {
        return s[1 .. s.len - 1];
    }
    return s;
}

/// Unified string content emitter - handles ALL Python string escapes
/// This is the SINGLE source of truth for string escape handling
pub fn emitZigStringContent(self: *NativeCodegen, content: []const u8, ctx: StringContext) CodegenError!void {
    var i: usize = 0;
    while (i < content.len) : (i += 1) {
        const c = content[i];

        // Handle escape sequences
        if (c == '\\' and i + 1 < content.len) {
            const next = content[i + 1];
            switch (next) {
                // Standard escapes - same for all string types
                'n' => {
                    try emitConst(self, "\\n");
                    i += 1;
                },
                'r' => {
                    try emitConst(self, "\\r");
                    i += 1;
                },
                't' => {
                    try emitConst(self, "\\t");
                    i += 1;
                },
                '\\' => {
                    try emitConst(self, "\\\\");
                    i += 1;
                },
                '\'' => {
                    try emitConst(self, "'");
                    i += 1;
                },
                '"' => {
                    try emitConst(self, "\\\"");
                    i += 1;
                },
                '0' => {
                    try emitConst(self, "\\x00");
                    i += 1;
                },
                'a' => {
                    try emitConst(self, "\\x07"); // Bell
                    i += 1;
                },
                'b' => {
                    try emitConst(self, "\\x08"); // Backspace
                    i += 1;
                },
                'f' => {
                    try emitConst(self, "\\x0c"); // Form feed
                    i += 1;
                },
                'v' => {
                    try emitConst(self, "\\x0b"); // Vertical tab
                    i += 1;
                },

                // Hex escape - behavior differs for strings vs bytes
                'x' => {
                    if (i + 3 < content.len) {
                        const hex = content[i + 2 .. i + 4];
                        const byte_val = std.fmt.parseInt(u8, hex, 16) catch {
                            try emitConst(self, "\\\\x");
                            i += 1;
                            continue;
                        };
                        if (ctx.is_bytes) {
                            // Bytes: raw byte value
                            try self.output.writer(self.allocator).print("\\x{x:0>2}", .{byte_val});
                        } else {
                            // String: UTF-8 encode the codepoint
                            var buf: [4]u8 = undefined;
                            const len = std.unicode.utf8Encode(@intCast(byte_val), &buf) catch 0;
                            for (buf[0..len]) |b| {
                                try self.output.writer(self.allocator).print("\\x{x:0>2}", .{b});
                            }
                        }
                        i += 3;
                    } else {
                        try emitConst(self, "\\\\x");
                        i += 1;
                    }
                },

                // Unicode escapes - only for strings, not bytes
                'u' => {
                    if (ctx.is_bytes) {
                        try emitConst(self, "\\\\u");
                        i += 1;
                    } else if (i + 5 < content.len) {
                        const hex = content[i + 2 .. i + 6];
                        const codepoint = std.fmt.parseInt(u21, hex, 16) catch {
                            try emitConst(self, "\\\\u");
                            i += 1;
                            continue;
                        };
                        try emitUtf8Bytes(self, codepoint);
                        i += 5;
                    } else {
                        try emitConst(self, "\\\\u");
                        i += 1;
                    }
                },
                'U' => {
                    if (ctx.is_bytes) {
                        try emitConst(self, "\\\\U");
                        i += 1;
                    } else if (i + 9 < content.len) {
                        const hex = content[i + 2 .. i + 10];
                        const codepoint = std.fmt.parseInt(u21, hex, 16) catch {
                            try emitConst(self, "\\\\U");
                            i += 1;
                            continue;
                        };
                        try emitUtf8Bytes(self, codepoint);
                        i += 9;
                    } else {
                        try emitConst(self, "\\\\U");
                        i += 1;
                    }
                },
                'N' => {
                    if (ctx.is_bytes) {
                        try emitConst(self, "\\\\N");
                        i += 1;
                    } else if (i + 2 < content.len and content[i + 2] == '{') {
                        var end_idx = i + 3;
                        while (end_idx < content.len and content[end_idx] != '}') : (end_idx += 1) {}
                        if (end_idx < content.len) {
                            const name = content[i + 3 .. end_idx];
                            if (unicodeNameToCodepoint(name)) |cp| {
                                try emitUtf8Bytes(self, cp);
                                i = end_idx;
                            } else {
                                try emitConst(self, "\\\\N");
                                i += 1;
                            }
                        } else {
                            try emitConst(self, "\\\\N");
                            i += 1;
                        }
                    } else {
                        try emitConst(self, "\\\\N");
                        i += 1;
                    }
                },

                // Brace escapes - for fstrings
                '{' => {
                    if (ctx.escape_braces) {
                        try emitConst(self, "{{");
                    } else {
                        try emitConst(self, "{");
                    }
                    i += 1;
                },
                '}' => {
                    if (ctx.escape_braces) {
                        try emitConst(self, "}}");
                    } else {
                        try emitConst(self, "}");
                    }
                    i += 1;
                },

                // Octal escapes \0-\7, \00-\77, \000-\377
                '1', '2', '3', '4', '5', '6', '7' => {
                    // Parse octal escape (1-3 digits)
                    var octal_end = i + 2;
                    while (octal_end < content.len and octal_end < i + 4 and
                        content[octal_end] >= '0' and content[octal_end] <= '7') : (octal_end += 1)
                    {}
                    const octal_str = content[i + 1 .. octal_end];
                    const byte_val = std.fmt.parseInt(u8, octal_str, 8) catch {
                        try emitConst(self, "\\\\");
                        continue;
                    };
                    try self.output.writer(self.allocator).print("\\x{x:0>2}", .{byte_val});
                    i = octal_end - 1;
                },

                // Line continuation - \<newline> is removed entirely in Python
                '\n' => {
                    // Skip both the backslash and the newline
                    i += 1;
                },
                '\r' => {
                    // Handle \r\n (Windows) or just \r
                    if (i + 2 < content.len and content[i + 2] == '\n') {
                        i += 2; // Skip \, \r, and \n
                    } else {
                        i += 1; // Skip \ and \r
                    }
                },

                // Unknown escape - emit literal backslash + char
                else => {
                    try emitConst(self, "\\\\");
                },
            }
        }
        // Handle raw characters that need escaping in Zig
        else if (c == '\\') {
            // Raw backslash (not part of escape sequence) needs escaping in Zig
            try emitConst(self, "\\\\");
        } else if (c == '"') {
            try emitConst(self, "\\\"");
        } else if (c == '\n') {
            try emitConst(self, "\\n");
        } else if (c == '\r') {
            try emitConst(self, "\\r");
        } else if (c == '\t') {
            try emitConst(self, "\\t");
        }
        // Brace handling for format strings (unescaped braces)
        else if (ctx.escape_braces and (c == '{' or c == '}')) {
            try self.output.writer(self.allocator).print("{c}{c}", .{ c, c });
        }
        // Regular character
        else {
            try self.output.append(self.allocator, c);
        }
    }
}

/// Helper to emit a Unicode codepoint as UTF-8 hex bytes
fn emitUtf8Bytes(self: *NativeCodegen, codepoint: u21) CodegenError!void {
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(codepoint, &buf) catch 0;
    for (buf[0..len]) |b| {
        try self.output.writer(self.allocator).print("\\x{x:0>2}", .{b});
    }
}

/// Unicode name to codepoint mapping (O(1) lookup)
const UnicodeNames = std.StaticStringMap(u21).initComptime(.{
    // Spaces
    .{ "SPACE", 0x0020 },
    .{ "EM SPACE", 0x2003 },
    .{ "EN SPACE", 0x2002 },
    .{ "FIGURE SPACE", 0x2007 },
    .{ "NO-BREAK SPACE", 0x00A0 },
    .{ "NARROW NO-BREAK SPACE", 0x202F },
    .{ "THIN SPACE", 0x2009 },
    .{ "HAIR SPACE", 0x200A },
    .{ "ZERO WIDTH SPACE", 0x200B },
    .{ "ZERO WIDTH NON-JOINER", 0x200C },
    .{ "ZERO WIDTH JOINER", 0x200D },
    .{ "LINE SEPARATOR", 0x2028 },
    .{ "PARAGRAPH SEPARATOR", 0x2029 },
    .{ "IDEOGRAPHIC SPACE", 0x3000 },
    // Digits
    .{ "FULLWIDTH DIGIT ZERO", 0xFF10 },
    .{ "FULLWIDTH DIGIT ONE", 0xFF11 },
    .{ "FULLWIDTH DIGIT TWO", 0xFF12 },
    .{ "FULLWIDTH DIGIT THREE", 0xFF13 },
    .{ "FULLWIDTH DIGIT FOUR", 0xFF14 },
    .{ "FULLWIDTH DIGIT FIVE", 0xFF15 },
    .{ "FULLWIDTH DIGIT SIX", 0xFF16 },
    .{ "FULLWIDTH DIGIT SEVEN", 0xFF17 },
    .{ "FULLWIDTH DIGIT EIGHT", 0xFF18 },
    .{ "FULLWIDTH DIGIT NINE", 0xFF19 },
    .{ "DIGIT ZERO", 0x0030 },
    .{ "DIGIT ONE", 0x0031 },
    .{ "MATHEMATICAL BOLD DIGIT ZERO", 0x1D7CE },
    .{ "MATHEMATICAL BOLD DIGIT ONE", 0x1D7CF },
    .{ "SUBSCRIPT ZERO", 0x2080 },
    .{ "SUBSCRIPT ONE", 0x2081 },
    .{ "SUPERSCRIPT ZERO", 0x2070 },
    .{ "SUPERSCRIPT ONE", 0x00B9 },
    // Common punctuation and symbols
    .{ "AMPERSAND", 0x0026 },
    .{ "OX", 0x1F402 },
    .{ "SNAKE", 0x1F40D },
    .{ "LEFT CURLY BRACKET", 0x007B },
    .{ "RIGHT CURLY BRACKET", 0x007D },
    .{ "EURO SIGN", 0x20AC },
    .{ "COPYRIGHT SIGN", 0x00A9 },
    .{ "SOFT HYPHEN", 0x00AD },
    .{ "NOT SIGN", 0x00AC },
    .{ "CEDILLA", 0x00B8 },
    .{ "CANCEL TAG", 0xE007F },
    .{ "KEYCAP NUMBER SIGN", 0x20E3 },
    // Greek letters
    .{ "GREEK CAPITAL LETTER DELTA", 0x0394 },
    .{ "GREEK SMALL LETTER ZETA", 0x03B6 },
    // Cyrillic
    .{ "CYRILLIC SMALL LETTER ZHE", 0x0436 },
    // Hiragana
    .{ "HIRAGANA LETTER A", 0x3042 },
    // Ethiopic
    .{ "ETHIOPIC SYLLABLE SEE", 0x1234 },
    // Arabic
    .{ "ARABIC LIGATURE UIGHUR KIRGHIZ YEH WITH HAMZA ABOVE WITH ALEF MAKSURA ISOLATED FORM", 0xFBF9 },
});

fn unicodeNameToCodepoint(name: []const u8) ?u21 {
    return UnicodeNames.get(name);
}

// Legacy compatibility wrappers - will be removed after refactoring call sites
pub fn emitPythonEscapedString(self: *NativeCodegen, content: []const u8) CodegenError!void {
    return emitZigStringContent(self, content, StringContext.default);
}

pub fn emitPythonEscapedStringExt(self: *NativeCodegen, content: []const u8, escape_braces: bool) CodegenError!void {
    return emitZigStringContent(self, content, if (escape_braces) StringContext.format_string else StringContext.default);
}
