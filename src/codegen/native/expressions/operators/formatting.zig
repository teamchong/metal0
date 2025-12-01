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

    // Get the format string
    const format_str = if (binop.left.* == .constant and binop.left.constant.value == .string)
        binop.left.constant.value.string
    else
        null;

    // For simple cases like "%d" % n where n is potentially BigInt, use comptime-aware formatting
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    try self.emitFmt("fmt_{d}: {{\n", .{label_id});
    try self.emit("var buf = std.ArrayList(u8){};\n");
    try self.emitFmt("const writer = buf.writer({s});\n", .{alloc_name});

    // Check if right side is a tuple (multiple values)
    if (binop.right.* == .tuple) {
        // Multiple format arguments: "%s %d" % (name, age)
        const tuple = binop.right.tuple;
        if (format_str) |fmt| {
            // Parse format string and match with tuple elements
            try self.emit("try writer.print(\"");
            // Convert Python format to Zig format
            var i: usize = 0;
            while (i < fmt.len) {
                if (fmt[i] == '%' and i + 1 < fmt.len) {
                    const spec = fmt[i + 1];
                    switch (spec) {
                        'd', 'i' => try self.emit("{any}"),
                        's' => try self.emit("{s}"),
                        'f' => try self.emit("{d}"),
                        'x' => try self.emit("{x}"),
                        'X' => try self.emit("{X}"),
                        'o' => try self.emit("{o}"),
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
            for (tuple.elts, 0..) |elem, j| {
                if (j > 0) try self.emit(", ");
                try genExpr(self, elem);
            }
            try self.emit("});\n");
        } else {
            // Format string is a variable - use runtime formatting
            try self.emit("try writer.print(\"{any}\", .{");
            try genExpr(self, binop.right.*);
            try self.emit("});\n");
        }
    } else {
        // Single format argument: "%d" % n
        if (format_str) |fmt| {
            // Parse format string
            try self.emit("try writer.print(\"");
            var i: usize = 0;
            while (i < fmt.len) {
                if (fmt[i] == '%' and i + 1 < fmt.len) {
                    const spec = fmt[i + 1];
                    switch (spec) {
                        'd', 'i' => try self.emit("{any}"),
                        's' => try self.emit("{s}"),
                        'f' => try self.emit("{d}"),
                        'x' => try self.emit("{x}"),
                        'X' => try self.emit("{X}"),
                        'o' => try self.emit("{o}"),
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
            try genExpr(self, binop.right.*);
            try self.emit("});\n");
        } else {
            // Format string is a variable
            try self.emit("try writer.print(\"{any}\", .{");
            try genExpr(self, binop.right.*);
            try self.emit("});\n");
        }
    }

    try self.emitFmt("break :fmt_{d} try buf.toOwnedSlice({s});\n}}", .{ label_id, alloc_name });
}
