/// String formatting operations
/// Handles Python % operator for string formatting: "%d" % value
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;

/// Generate Python-style string formatting: "%d" % value or "%s %s" % (a, b)
/// Handles both single value and tuple of values
pub fn genStringFormat(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    // Get the format string (strip Python quotes)
    const format_str = if (binop.left.* == .constant and binop.left.constant.value == .string) blk: {
        const raw = binop.left.constant.value.string;
        // Strip Python quotes: 'x' or "x" -> x
        break :blk if (raw.len >= 2) raw[1 .. raw.len - 1] else raw;
    } else null;

    // For simple cases like "%d" % n where n is potentially BigInt, use comptime-aware formatting
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Use unique buf name to avoid shadowing in nested format expressions
    // e.g., "%s" % repr(x) where repr(x) generates another format block
    try self.emitFmt("fmt_{d}: {{\n", .{label_id});
    try self.emitFmt("var __fmt_buf_{d} = std.ArrayList(u8){{}};\n", .{label_id});
    try self.emitFmt("const writer = __fmt_buf_{d}.writer({s});\n", .{ label_id, alloc_name });

    // Check if right side is a tuple (multiple values)
    if (binop.right.* == .tuple) {
        // Multiple format arguments: "%s %d" % (name, age)
        const tuple = binop.right.tuple;
        if (format_str) |fmt| {
            // Parse format string and match with tuple elements
            // Use catch unreachable since we're often inside non-error contexts like panic args
            try self.emit("writer.print(\"");
            // Convert Python format to Zig format
            var i: usize = 0;
            while (i < fmt.len) {
                if (fmt[i] == '%' and i + 1 < fmt.len) {
                    const spec = fmt[i + 1];
                    switch (spec) {
                        'd', 'i' => try self.emit("{any}"),
                        's' => try self.emit("{s}"),
                        'f' => try self.emit("{d}"),
                        'x' => try self.emit("{s}"), // Use {s} for hex - formatInt returns string
                        'X' => try self.emit("{s}"), // Use {s} for hex - formatInt returns string
                        'o' => try self.emit("{s}"), // Use {s} for octal - formatInt returns string
                        'r' => try self.emit("{any}"),
                        '%' => try self.emit("%"),
                        else => {
                            try self.emitFmt("{c}", .{fmt[i]});
                            try self.emitFmt("{c}", .{spec});
                        },
                    }
                    i += 2;
                } else {
                    // Escape special chars for Zig format string
                    if (fmt[i] == '{') {
                        try self.emit("{{");
                    } else if (fmt[i] == '}') {
                        try self.emit("}}");
                    } else if (fmt[i] == '"') {
                        try self.emit("\\\"");
                    } else if (fmt[i] == '\\') {
                        try self.emit("\\\\");
                    } else {
                        try self.emitFmt("{c}", .{fmt[i]});
                    }
                    i += 1;
                }
            }
            try self.emit("\", .{");
            // Track which format specs need special handling
            var elem_idx: usize = 0;
            var fmt_idx: usize = 0;
            while (fmt_idx < fmt.len) : (fmt_idx += 1) {
                if (fmt[fmt_idx] == '%' and fmt_idx + 1 < fmt.len) {
                    const spec = fmt[fmt_idx + 1];
                    // Skip %% - it's an escaped literal % and doesn't consume a tuple element
                    if (spec == '%') {
                        fmt_idx += 1;
                        continue;
                    }
                    if (elem_idx > 0) try self.emit(", ");
                    if (elem_idx < tuple.elts.len) {
                        // For hex/octal formats, wrap in runtime.formatInt to handle bool
                        if (spec == 'x' or spec == 'X' or spec == 'o') {
                            try self.emit("runtime.formatInt(");
                            try genExpr(self, tuple.elts[elem_idx]);
                            if (spec == 'x') {
                                try self.emit(", .hex_lower)");
                            } else if (spec == 'X') {
                                try self.emit(", .hex_upper)");
                            } else {
                                try self.emit(", .octal)");
                            }
                        } else {
                            try genExpr(self, tuple.elts[elem_idx]);
                        }
                        elem_idx += 1;
                    }
                    fmt_idx += 1; // Skip the spec char
                }
            }
            try self.emit("}) catch unreachable;\n");
        } else {
            // Format string is a variable - use runtime formatting
            try self.emit("writer.print(\"{any}\", .{");
            try genExpr(self, binop.right.*);
            try self.emit("}) catch unreachable;\n");
        }
    } else {
        // Single format argument: "%d" % n
        if (format_str) |fmt| {
            // Find the format specifier for special handling
            var format_spec: u8 = 0;
            var i: usize = 0;
            while (i < fmt.len) {
                if (fmt[i] == '%' and i + 1 < fmt.len) {
                    format_spec = fmt[i + 1];
                    break;
                }
                i += 1;
            }

            // Parse format string for output
            try self.emit("writer.print(\"");
            i = 0;
            while (i < fmt.len) {
                if (fmt[i] == '%' and i + 1 < fmt.len) {
                    const spec = fmt[i + 1];
                    switch (spec) {
                        'd', 'i' => try self.emit("{any}"),
                        's' => try self.emit("{s}"),
                        'f' => try self.emit("{d}"),
                        'x' => try self.emit("{s}"), // Use {s} for hex - formatInt returns string
                        'X' => try self.emit("{s}"), // Use {s} for hex - formatInt returns string
                        'o' => try self.emit("{s}"), // Use {s} for octal - formatInt returns string
                        'r' => try self.emit("{any}"),
                        '%' => try self.emit("%"),
                        else => {
                            try self.emitFmt("{c}", .{fmt[i]});
                            try self.emitFmt("{c}", .{spec});
                        },
                    }
                    i += 2;
                } else {
                    // Escape special chars for Zig format string
                    if (fmt[i] == '{') {
                        try self.emit("{{");
                    } else if (fmt[i] == '}') {
                        try self.emit("}}");
                    } else if (fmt[i] == '"') {
                        try self.emit("\\\"");
                    } else if (fmt[i] == '\\') {
                        try self.emit("\\\\");
                    } else {
                        try self.emitFmt("{c}", .{fmt[i]});
                    }
                    i += 1;
                }
            }
            try self.emit("\", .{");
            // For hex/octal formats, wrap value in runtime.formatInt
            if (format_spec == 'x' or format_spec == 'X' or format_spec == 'o') {
                try self.emit("runtime.formatInt(");
                try genExpr(self, binop.right.*);
                if (format_spec == 'x') {
                    try self.emit(", .hex_lower)");
                } else if (format_spec == 'X') {
                    try self.emit(", .hex_upper)");
                } else {
                    try self.emit(", .octal)");
                }
            } else if (format_spec == 'd' or format_spec == 'i') {
                // For %d/%i with bool, convert to int
                const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
                const right_type = self.inferExprScoped(binop.right.*) catch NativeType.unknown;
                if (right_type == .bool) {
                    try self.emit("@as(i64, @intFromBool(");
                    try genExpr(self, binop.right.*);
                    try self.emit("))");
                } else {
                    try genExpr(self, binop.right.*);
                }
            } else {
                try genExpr(self, binop.right.*);
            }
            try self.emit("}) catch unreachable;\n");
        } else {
            // Format string is a variable
            try self.emit("writer.print(\"{any}\", .{");
            try genExpr(self, binop.right.*);
            try self.emit("}) catch unreachable;\n");
        }
    }

    // Use catch unreachable since print/toOwnedSlice won't fail with valid allocator in most cases
    try self.emitFmt("break :fmt_{d} __fmt_buf_{d}.toOwnedSlice({s}) catch unreachable;\n}}", .{ label_id, label_id, alloc_name });
}
