/// Constant value code generation
/// Handles Python literals: int, float, bool, string, none
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

/// Minimum string length to consider for interning
/// Short strings are faster to compare inline
const MIN_INTERN_LENGTH = 4;

/// Generate constant values (int, float, bool, string, none)
/// String literals are interned for O(1) equality comparison
pub fn genConstant(self: *NativeCodegen, constant: ast.Node.Constant) CodegenError!void {
    switch (constant.value) {
        .int => try self.output.writer(self.allocator).print("{d}", .{constant.value.int}),
        .bigint => |s| {
            // Generate BigInt from string literal
            try self.output.writer(self.allocator).print("(try runtime.parseIntToBigInt(__global_allocator, \"{s}\", 10))", .{s});
        },
        .float => |f| {
            // Cast to f64 to avoid comptime_float issues with format strings
            // Use Python-style float formatting (always show .0 for whole numbers)
            if (@mod(f, 1.0) == 0.0) {
                try self.output.writer(self.allocator).print("@as(f64, {d:.1})", .{f});
            } else {
                try self.output.writer(self.allocator).print("@as(f64, {d})", .{f});
            }
        },
        .bool => try self.emit(if (constant.value.bool) "true" else "false"),
        .none => try self.emit("null"), // Zig null represents None
        .complex => |imag| {
            // Complex number literal: 0j -> .{.real = 0.0, .imag = 0.0}, 1j -> .{.real = 0.0, .imag = 1.0}
            try self.output.writer(self.allocator).print("runtime.PyComplex.create(0.0, {d})", .{imag});
        },
        .string => |s| {
            // Strip Python quotes (handle both single/double and triple quotes)
            const content = blk: {
                if (s.len >= 6 and (std.mem.startsWith(u8, s, "'''") or std.mem.startsWith(u8, s, "\"\"\""))) {
                    // Triple-quoted string - strip 3 chars from each end
                    var inner = s[3 .. s.len - 3];
                    // Handle line continuation at start: '''\<newline> means content starts on next line
                    if (inner.len > 0 and inner[0] == '\\') {
                        if (inner.len > 1 and inner[1] == '\n') {
                            inner = inner[2..];
                        } else if (inner.len > 2 and inner[1] == '\r' and inner[2] == '\n') {
                            inner = inner[3..];
                        }
                    }
                    break :blk inner;
                } else if (s.len >= 2) {
                    // Single/double quoted - strip 1 char from each end
                    break :blk s[1 .. s.len - 1];
                } else {
                    break :blk s;
                }
            };

            // Process Python escape sequences and emit Zig string
            try self.emit("\"");
            var i: usize = 0;
            while (i < content.len) : (i += 1) {
                const c = content[i];
                if (c == '\\' and i + 1 < content.len) {
                    // Handle Python escape sequences
                    const next = content[i + 1];
                    switch (next) {
                        'x' => {
                            // \xNN - hex escape sequence (represents Unicode codepoint, needs UTF-8 encoding)
                            if (i + 3 < content.len) {
                                const hex = content[i + 2 .. i + 4];
                                const codepoint: u21 = std.fmt.parseInt(u8, hex, 16) catch {
                                    // Invalid hex, emit as-is
                                    try self.emit("\\\\x");
                                    i += 1; // Skip the backslash
                                    continue;
                                };
                                // Encode as UTF-8 bytes
                                var buf: [4]u8 = undefined;
                                const len = std.unicode.utf8Encode(codepoint, &buf) catch 0;
                                for (buf[0..len]) |b| {
                                    try self.output.writer(self.allocator).print("\\x{x:0>2}", .{b});
                                }
                                i += 3; // Skip \xNN
                            } else {
                                try self.emit("\\\\x");
                                i += 1;
                            }
                        },
                        'n' => {
                            try self.emit("\\n");
                            i += 1;
                        },
                        'r' => {
                            try self.emit("\\r");
                            i += 1;
                        },
                        't' => {
                            try self.emit("\\t");
                            i += 1;
                        },
                        '\\' => {
                            try self.emit("\\\\");
                            i += 1;
                        },
                        '\'' => {
                            try self.emit("'");
                            i += 1;
                        },
                        '"' => {
                            try self.emit("\\\"");
                            i += 1;
                        },
                        '0' => {
                            // \0 - null byte
                            try self.emit("\\x00");
                            i += 1;
                        },
                        'N' => {
                            // \N{NAME} - named Unicode escape
                            if (i + 2 < content.len and content[i + 2] == '{') {
                                // Find closing brace
                                var end_idx = i + 3;
                                while (end_idx < content.len and content[end_idx] != '}') : (end_idx += 1) {}
                                if (end_idx < content.len) {
                                    const name = content[i + 3 .. end_idx];
                                    // Convert Unicode name to codepoint
                                    const codepoint = unicodeNameToCodepoint(name);
                                    if (codepoint) |cp| {
                                        // Emit as UTF-8 bytes
                                        var buf: [4]u8 = undefined;
                                        const len = std.unicode.utf8Encode(cp, &buf) catch 0;
                                        for (buf[0..len]) |b| {
                                            try self.output.writer(self.allocator).print("\\x{x:0>2}", .{b});
                                        }
                                        i = end_idx; // Skip to closing brace
                                    } else {
                                        // Unknown name, emit as-is escaped
                                        try self.emit("\\\\N");
                                        i += 1;
                                    }
                                } else {
                                    try self.emit("\\\\N");
                                    i += 1;
                                }
                            } else {
                                try self.emit("\\\\N");
                                i += 1;
                            }
                        },
                        'u' => {
                            // \uNNNN - 4-digit Unicode escape
                            if (i + 5 < content.len) {
                                const hex = content[i + 2 .. i + 6];
                                const codepoint = std.fmt.parseInt(u21, hex, 16) catch {
                                    try self.emit("\\\\u");
                                    i += 1;
                                    continue;
                                };
                                // Emit as UTF-8 bytes
                                var buf: [4]u8 = undefined;
                                const len = std.unicode.utf8Encode(codepoint, &buf) catch 0;
                                for (buf[0..len]) |b| {
                                    try self.output.writer(self.allocator).print("\\x{x:0>2}", .{b});
                                }
                                i += 5; // Skip \uNNNN
                            } else {
                                try self.emit("\\\\u");
                                i += 1;
                            }
                        },
                        else => {
                            // Unknown escape, emit backslash escaped
                            try self.emit("\\\\");
                        },
                    }
                } else if (c == '"') {
                    try self.emit("\\\"");
                } else if (c == '\n') {
                    try self.emit("\\n");
                } else if (c == '\r') {
                    try self.emit("\\r");
                } else if (c == '\t') {
                    try self.emit("\\t");
                } else {
                    try self.output.writer(self.allocator).print("{c}", .{c});
                }
            }
            try self.emit("\"");
        },
        .bytes => |s| {
            // Bytes literal (b"...") - escape sequences are raw bytes, no UTF-8 encoding
            // Strip Python quotes (already stripped 'b' prefix in parser)
            const content = if (s.len >= 2) s[1 .. s.len - 1] else s;

            // Process Python escape sequences and emit Zig string with raw bytes
            try self.emit("\"");
            var i: usize = 0;
            while (i < content.len) : (i += 1) {
                const c = content[i];
                if (c == '\\' and i + 1 < content.len) {
                    // Handle Python escape sequences for bytes
                    const next = content[i + 1];
                    switch (next) {
                        'x' => {
                            // \xNN - hex escape sequence (raw byte, no UTF-8 encoding!)
                            if (i + 3 < content.len) {
                                const hex = content[i + 2 .. i + 4];
                                const byte_val = std.fmt.parseInt(u8, hex, 16) catch {
                                    // Invalid hex, emit as-is
                                    try self.emit("\\\\x");
                                    i += 1;
                                    continue;
                                };
                                // Emit as raw byte (no UTF-8 encoding!)
                                try self.output.writer(self.allocator).print("\\x{x:0>2}", .{byte_val});
                                i += 3; // Skip \xNN
                            } else {
                                try self.emit("\\\\x");
                                i += 1;
                            }
                        },
                        'n' => {
                            try self.emit("\\n");
                            i += 1;
                        },
                        'r' => {
                            try self.emit("\\r");
                            i += 1;
                        },
                        't' => {
                            try self.emit("\\t");
                            i += 1;
                        },
                        '\\' => {
                            try self.emit("\\\\");
                            i += 1;
                        },
                        '\'' => {
                            try self.emit("'");
                            i += 1;
                        },
                        '"' => {
                            try self.emit("\\\"");
                            i += 1;
                        },
                        '0' => {
                            // \0 - null byte
                            try self.emit("\\x00");
                            i += 1;
                        },
                        else => {
                            // Unknown escape, emit backslash escaped
                            try self.emit("\\\\");
                        },
                    }
                } else if (c == '"') {
                    try self.emit("\\\"");
                } else if (c == '\n') {
                    try self.emit("\\n");
                } else if (c == '\r') {
                    try self.emit("\\r");
                } else if (c == '\t') {
                    try self.emit("\\t");
                } else {
                    try self.output.writer(self.allocator).print("{c}", .{c});
                }
            }
            try self.emit("\"");
        },
    }
}

/// Unicode name to codepoint mapping (O(1) lookup)
const UnicodeNames = std.StaticStringMap(u21).initComptime(.{
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
});

/// Convert Unicode character name to codepoint
fn unicodeNameToCodepoint(name: []const u8) ?u21 {
    return UnicodeNames.get(name);
}
