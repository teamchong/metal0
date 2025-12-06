/// String formatting operations
/// Handles Python % operator for string formatting: "%d" % value
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;

/// Parse a Python format specifier like "%.0f", "%5.2f", "%d"
/// Returns the format type char and the number of characters consumed
const FormatSpec = struct {
    spec_char: u8, // 'd', 'f', 's', etc.
    precision: ?u32, // precision after the dot
    width: ?u32, // minimum field width
    consumed: usize, // total chars consumed including %
};

fn parseFormatSpec(fmt: []const u8, start: usize) FormatSpec {
    var i = start + 1; // skip %
    var width: ?u32 = null;
    var precision: ?u32 = null;

    // Skip flags: -, +, space, #, 0
    while (i < fmt.len and (fmt[i] == '-' or fmt[i] == '+' or fmt[i] == ' ' or fmt[i] == '#' or fmt[i] == '0')) {
        i += 1;
    }

    // Parse width
    if (i < fmt.len and fmt[i] >= '1' and fmt[i] <= '9') {
        var w: u32 = 0;
        while (i < fmt.len and fmt[i] >= '0' and fmt[i] <= '9') {
            w = w * 10 + @as(u32, fmt[i] - '0');
            i += 1;
        }
        width = w;
    }

    // Parse precision
    if (i < fmt.len and fmt[i] == '.') {
        i += 1;
        var p: u32 = 0;
        while (i < fmt.len and fmt[i] >= '0' and fmt[i] <= '9') {
            p = p * 10 + @as(u32, fmt[i] - '0');
            i += 1;
        }
        precision = p;
    }

    // Get format character
    const spec_char = if (i < fmt.len) fmt[i] else 's';
    const consumed = i + 1 - start;

    return FormatSpec{
        .spec_char = spec_char,
        .precision = precision,
        .width = width,
        .consumed = consumed,
    };
}

/// Generate Python-style string formatting: "%d" % value or "%s %s" % (a, b)
/// Handles both single value and tuple of values
pub fn genStringFormat(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    // Get the format string (parser already strips quotes)
    const format_str = if (binop.left.* == .constant and binop.left.constant.value == .string)
        binop.left.constant.value.string
    else
        null;

    // For simple cases like "%d" % n where n is potentially BigInt, use comptime-aware formatting
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // If format string is a variable (not literal), use runtime formatting
    // This must be checked BEFORE creating the buffer/writer
    if (format_str == null) {
        try self.emitFmt("fmt_{d}: {{\n", .{label_id});
        try self.emitFmt("break :fmt_{d} try runtime.pyStringFormat({s}, ", .{ label_id, alloc_name });
        try genExpr(self, binop.left.*);
        try self.emit(", ");
        try genExpr(self, binop.right.*);
        try self.emit(");\n}");
        return;
    }

    // Use unique buf AND writer names to avoid shadowing in nested format expressions
    // e.g., "%s" % repr(x) where repr(x) generates another format block
    try self.emitFmt("fmt_{d}: {{\n", .{label_id});
    try self.emitFmt("var __fmt_buf_{d} = std.ArrayListUnmanaged(u8){{}};\n", .{label_id});
    try self.emitFmt("const __writer_{d} = __fmt_buf_{d}.writer({s});\n", .{ label_id, label_id, alloc_name });

    // Check if right side is a tuple (multiple values)
    if (binop.right.* == .tuple) {
        // Multiple format arguments: "%s %d" % (name, age)
        const tuple = binop.right.tuple;
        if (format_str) |fmt| {
            // Parse format string and match with tuple elements
            // Use catch unreachable since we're often inside non-error contexts like panic args
            try self.emitFmt("__writer_{d}.print(\"", .{label_id});
            // Convert Python format to Zig format
            var i: usize = 0;
            while (i < fmt.len) {
                if (fmt[i] == '%' and i + 1 < fmt.len) {
                    const fspec = parseFormatSpec(fmt, i);
                    switch (fspec.spec_char) {
                        'd', 'i' => try self.emit("{any}"),
                        's' => try self.emit("{s}"),
                        'f' => {
                            // Handle precision for floats: %.0f -> {d:.0}, %.2f -> {d:.2}
                            if (fspec.precision) |p| {
                                try self.emitFmt("{{d:.{d}}}", .{p});
                            } else {
                                try self.emit("{d}");
                            }
                        },
                        'g', 'G' => try self.emit("{d}"), // general format
                        'e', 'E' => try self.emit("{e}"), // scientific notation
                        'x' => try self.emit("{s}"), // Use {s} for hex - formatInt returns string
                        'X' => try self.emit("{s}"), // Use {s} for hex - formatInt returns string
                        'o' => try self.emit("{s}"), // Use {s} for octal - formatInt returns string
                        'r' => try self.emit("{s}"), // Use {s} for repr - pyRepr returns string
                        '%' => try self.emit("%"),
                        else => {
                            try self.emitFmt("{c}", .{fmt[i]});
                            try self.emitFmt("{c}", .{fspec.spec_char});
                        },
                    }
                    i += fspec.consumed;
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
                    } else if (fmt[i] == '\n') {
                        try self.emit("\\n");
                    } else if (fmt[i] == '\r') {
                        try self.emit("\\r");
                    } else if (fmt[i] == '\t') {
                        try self.emit("\\t");
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
            while (fmt_idx < fmt.len) {
                if (fmt[fmt_idx] == '%' and fmt_idx + 1 < fmt.len) {
                    const fspec2 = parseFormatSpec(fmt, fmt_idx);
                    // Skip %% - it's an escaped literal % and doesn't consume a tuple element
                    if (fspec2.spec_char == '%') {
                        fmt_idx += fspec2.consumed;
                        continue;
                    }
                    if (elem_idx > 0) try self.emit(", ");
                    if (elem_idx < tuple.elts.len) {
                        // For hex/octal formats, wrap in runtime.formatInt to handle bool
                        if (fspec2.spec_char == 'x' or fspec2.spec_char == 'X' or fspec2.spec_char == 'o') {
                            try self.emit("runtime.formatInt(");
                            try genExpr(self, tuple.elts[elem_idx]);
                            if (fspec2.spec_char == 'x') {
                                try self.emit(", .hex_lower)");
                            } else if (fspec2.spec_char == 'X') {
                                try self.emit(", .hex_upper)");
                            } else {
                                try self.emit(", .octal)");
                            }
                        } else if (fspec2.spec_char == 'r') {
                            // For %r, wrap in runtime.pyRepr for Python repr() output
                            try self.emitFmt("(runtime.builtins.pyRepr({s}, ", .{alloc_name});
                            try genExpr(self, tuple.elts[elem_idx]);
                            try self.emit(") catch unreachable)");
                        } else {
                            try genExpr(self, tuple.elts[elem_idx]);
                        }
                        elem_idx += 1;
                    }
                    fmt_idx += fspec2.consumed;
                } else {
                    fmt_idx += 1;
                }
            }
            try self.emit("}) catch unreachable;\n");
        }
        // Note: else case (variable format string) is handled early with return
    } else {
        // Single format argument: "%d" % n
        if (format_str) |fmt| {
            // Find the format specifier for special handling
            var main_fspec: FormatSpec = .{ .spec_char = 's', .precision = null, .width = null, .consumed = 0 };
            var i: usize = 0;
            while (i < fmt.len) {
                if (fmt[i] == '%' and i + 1 < fmt.len) {
                    main_fspec = parseFormatSpec(fmt, i);
                    break;
                }
                i += 1;
            }

            // Parse format string for output
            try self.emitFmt("__writer_{d}.print(\"", .{label_id});
            i = 0;
            while (i < fmt.len) {
                if (fmt[i] == '%' and i + 1 < fmt.len) {
                    const fspec = parseFormatSpec(fmt, i);
                    switch (fspec.spec_char) {
                        'd', 'i' => try self.emit("{any}"),
                        's' => try self.emit("{s}"),
                        'f' => {
                            // Handle precision for floats: %.0f -> {d:.0}, %.2f -> {d:.2}
                            if (fspec.precision) |p| {
                                try self.emitFmt("{{d:.{d}}}", .{p});
                            } else {
                                try self.emit("{d}");
                            }
                        },
                        'g', 'G' => try self.emit("{d}"), // general format
                        'e', 'E' => try self.emit("{e}"), // scientific notation
                        'x' => try self.emit("{s}"), // Use {s} for hex - formatInt returns string
                        'X' => try self.emit("{s}"), // Use {s} for hex - formatInt returns string
                        'o' => try self.emit("{s}"), // Use {s} for octal - formatInt returns string
                        'r' => try self.emit("{s}"), // Use {s} for repr - pyRepr returns string
                        '%' => try self.emit("%"),
                        else => {
                            try self.emitFmt("{c}", .{fmt[i]});
                            try self.emitFmt("{c}", .{fspec.spec_char});
                        },
                    }
                    i += fspec.consumed;
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
                    } else if (fmt[i] == '\n') {
                        try self.emit("\\n");
                    } else if (fmt[i] == '\r') {
                        try self.emit("\\r");
                    } else if (fmt[i] == '\t') {
                        try self.emit("\\t");
                    } else {
                        try self.emitFmt("{c}", .{fmt[i]});
                    }
                    i += 1;
                }
            }
            try self.emit("\", .{");
            // For hex/octal formats, wrap value in runtime.formatInt
            if (main_fspec.spec_char == 'x' or main_fspec.spec_char == 'X' or main_fspec.spec_char == 'o') {
                try self.emit("runtime.formatInt(");
                try genExpr(self, binop.right.*);
                if (main_fspec.spec_char == 'x') {
                    try self.emit(", .hex_lower)");
                } else if (main_fspec.spec_char == 'X') {
                    try self.emit(", .hex_upper)");
                } else {
                    try self.emit(", .octal)");
                }
            } else if (main_fspec.spec_char == 'd' or main_fspec.spec_char == 'i') {
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
            } else if (main_fspec.spec_char == 'r') {
                // For %r, wrap in runtime.pyRepr for Python repr() output
                try self.emitFmt("(runtime.builtins.pyRepr({s}, ", .{alloc_name});
                try genExpr(self, binop.right.*);
                try self.emit(") catch unreachable)");
            } else {
                try genExpr(self, binop.right.*);
            }
            try self.emit("}) catch unreachable;\n");
        }
        // Note: else case (variable format string) is handled early with return
    }

    // Use catch unreachable since print/toOwnedSlice won't fail with valid allocator in most cases
    try self.emitFmt("break :fmt_{d} __fmt_buf_{d}.toOwnedSlice({s}) catch unreachable;\n}}", .{ label_id, label_id, alloc_name });
}
