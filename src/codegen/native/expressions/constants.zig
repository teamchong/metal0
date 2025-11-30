/// Constant value code generation
/// Handles Python literals: int, float, bool, string, none
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

/// Generate constant values (int, float, bool, string, none)
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
        .string => |s| {
            // Strip Python quotes
            const content = if (s.len >= 2) s[1 .. s.len - 1] else s;

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
                            // \xNN - hex escape sequence
                            if (i + 3 < content.len) {
                                const hex = content[i + 2 .. i + 4];
                                const byte_val = std.fmt.parseInt(u8, hex, 16) catch {
                                    // Invalid hex, emit as-is
                                    try self.emit("\\\\x");
                                    i += 1; // Skip the backslash
                                    continue;
                                };
                                // Emit the byte value directly as Zig hex escape
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
    }
}

/// Convert Unicode character name to codepoint
/// Supports common names used in Python tests
fn unicodeNameToCodepoint(name: []const u8) ?u21 {
    // Common Unicode names - add more as needed
    const mappings = [_]struct { name: []const u8, codepoint: u21 }{
        .{ .name = "EM SPACE", .codepoint = 0x2003 },
        .{ .name = "EN SPACE", .codepoint = 0x2002 },
        .{ .name = "FIGURE SPACE", .codepoint = 0x2007 },
        .{ .name = "NO-BREAK SPACE", .codepoint = 0x00A0 },
        .{ .name = "NARROW NO-BREAK SPACE", .codepoint = 0x202F },
        .{ .name = "THIN SPACE", .codepoint = 0x2009 },
        .{ .name = "HAIR SPACE", .codepoint = 0x200A },
        .{ .name = "ZERO WIDTH SPACE", .codepoint = 0x200B },
        .{ .name = "ZERO WIDTH NON-JOINER", .codepoint = 0x200C },
        .{ .name = "ZERO WIDTH JOINER", .codepoint = 0x200D },
        .{ .name = "LINE SEPARATOR", .codepoint = 0x2028 },
        .{ .name = "PARAGRAPH SEPARATOR", .codepoint = 0x2029 },
        .{ .name = "IDEOGRAPHIC SPACE", .codepoint = 0x3000 },
        .{ .name = "FULLWIDTH DIGIT ZERO", .codepoint = 0xFF10 },
        .{ .name = "FULLWIDTH DIGIT ONE", .codepoint = 0xFF11 },
        .{ .name = "FULLWIDTH DIGIT TWO", .codepoint = 0xFF12 },
        .{ .name = "FULLWIDTH DIGIT THREE", .codepoint = 0xFF13 },
        .{ .name = "FULLWIDTH DIGIT FOUR", .codepoint = 0xFF14 },
        .{ .name = "FULLWIDTH DIGIT FIVE", .codepoint = 0xFF15 },
        .{ .name = "FULLWIDTH DIGIT SIX", .codepoint = 0xFF16 },
        .{ .name = "FULLWIDTH DIGIT SEVEN", .codepoint = 0xFF17 },
        .{ .name = "FULLWIDTH DIGIT EIGHT", .codepoint = 0xFF18 },
        .{ .name = "FULLWIDTH DIGIT NINE", .codepoint = 0xFF19 },
        .{ .name = "DIGIT ZERO", .codepoint = 0x0030 },
        .{ .name = "DIGIT ONE", .codepoint = 0x0031 },
        .{ .name = "MATHEMATICAL BOLD DIGIT ZERO", .codepoint = 0x1D7CE },
        .{ .name = "MATHEMATICAL BOLD DIGIT ONE", .codepoint = 0x1D7CF },
        .{ .name = "SUBSCRIPT ZERO", .codepoint = 0x2080 },
        .{ .name = "SUBSCRIPT ONE", .codepoint = 0x2081 },
        .{ .name = "SUPERSCRIPT ZERO", .codepoint = 0x2070 },
        .{ .name = "SUPERSCRIPT ONE", .codepoint = 0x00B9 },
    };

    for (mappings) |m| {
        if (std.mem.eql(u8, name, m.name)) {
            return m.codepoint;
        }
    }
    return null;
}
