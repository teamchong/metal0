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
