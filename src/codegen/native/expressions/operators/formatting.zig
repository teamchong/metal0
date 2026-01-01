/// String formatting operations
/// Handles Python % operator for string formatting: "%d" % value
///
/// MIGRATION STATUS: Fully migrated to ZigBuilder pattern
/// - Uses captureExpr() to bridge AST expressions to ZigValue
/// - Uses builder.write() for all output
/// - Uses self.emitZigValue() for ZigValue emission
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const expr_emitter = @import("../../expr_emitter.zig");
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;
const ZigBuilder = builder_mod.ZigBuilder;

// ============================================
// Format operation helpers - builder pattern
// ============================================

/// Emit format block open: fmt_N: { var __fmt_buf_N = ...; const __writer_N = ...;
fn emitFormatBlockOpen(_: *NativeCodegen, b: *ZigBuilder, label_id: usize, alloc_name: []const u8) CodegenError!void {
    try b.writeFmt("fmt_{d}: {{\n", .{label_id});
    try b.writeFmt("var __fmt_buf_{d} = std.ArrayListUnmanaged(u8)", .{label_id});
    try b.emitRaw("{};\n");
    try b.writeFmt("const __writer_{d} = __fmt_buf_{d}.writer({s});\n", .{ label_id, label_id, alloc_name });
}

/// Emit format block close: break :fmt_N __fmt_buf_N.toOwnedSlice(alloc) catch unreachable; }
fn emitFormatBlockClose(b: *ZigBuilder, label_id: usize, alloc_name: []const u8) CodegenError!void {
    try b.writeFmt("break :fmt_{d} __fmt_buf_{d}.toOwnedSlice({s}) catch unreachable;\n}}", .{ label_id, label_id, alloc_name });
}

/// Emit runtime.formatInt(expr, base) using builder
fn emitFormatInt(self: *NativeCodegen, b: *ZigBuilder, expr_val: ZigValue, spec_char: u8) CodegenError!void {
    try b.emitRaw("runtime.formatInt(");
    try self.emitZigValue(expr_val);
    switch (spec_char) {
        'x' => try b.emitRaw(", .hex_lower)"),
        'X' => try b.emitRaw(", .hex_upper)"),
        else => try b.emitRaw(", .octal)"), // 'o'
    }
}

/// Emit runtime.builtins.pyRepr(alloc, expr) catch unreachable using builder
fn emitPyRepr(self: *NativeCodegen, b: *ZigBuilder, expr_val: ZigValue, alloc_name: []const u8) CodegenError!void {
    try b.writeFmt("(runtime.builtins.pyRepr({s}, ", .{alloc_name});
    try self.emitZigValue(expr_val);
    try b.emitRaw(") catch unreachable)");
}

/// Emit @as(i64, @intFromBool(expr)) using builder
fn emitBoolToI64(self: *NativeCodegen, b: *ZigBuilder, expr_val: ZigValue) CodegenError!void {
    try b.emitRaw("@as(i64, @intFromBool(");
    try self.emitZigValue(expr_val);
    try b.emitRaw("))");
}

/// Emit runtime pyStringFormat for variable format strings using builder
fn emitRuntimePyStringFormat(self: *NativeCodegen, b: *ZigBuilder, label_id: usize, alloc_name: []const u8, left_val: ZigValue, right_val: ZigValue) CodegenError!void {
    try b.writeFmt("fmt_{d}: {{\n", .{label_id});
    try b.writeFmt("break :fmt_{d} try runtime.pyStringFormat({s}, ", .{ label_id, alloc_name });
    try self.emitZigValue(left_val);
    try b.emitRaw(", ");
    try self.emitZigValue(right_val);
    try b.emitRaw(");\n}");
}

/// Emit escaped character for Zig format string using builder
fn emitEscapedChar(b: *ZigBuilder, c: u8) CodegenError!void {
    switch (c) {
        '{' => try b.emitRaw("{{"),
        '}' => try b.emitRaw("}}"),
        '"' => try b.emitRaw("\\\""),
        '\\' => try b.emitRaw("\\\\"),
        '\n' => try b.emitRaw("\\n"),
        '\r' => try b.emitRaw("\\r"),
        '\t' => try b.emitRaw("\\t"),
        else => try b.writeFmt("{c}", .{c}),
    }
}

/// Emit Zig format specifier for Python format spec using builder
fn emitZigFormatSpec(b: *ZigBuilder, fspec: FormatSpec, fallback_fmt_char: u8) CodegenError!void {
    switch (fspec.spec_char) {
        'd', 'i' => try b.emitRaw("{}"),
        's' => try b.emitRaw("{s}"),
        'f' => {
            if (fspec.precision) |p| {
                try b.writeFmt("{{d:.{d}}}", .{p});
            } else {
                try b.emitRaw("{d}");
            }
        },
        'g', 'G' => try b.emitRaw("{d}"),
        'e', 'E' => try b.emitRaw("{e}"),
        'x', 'X', 'o' => try b.emitRaw("{s}"),
        'r' => try b.emitRaw("{s}"),
        '%' => try b.emitRaw("%"),
        else => {
            try b.writeFmt("{c}", .{fallback_fmt_char});
            try b.writeFmt("{c}", .{fspec.spec_char});
        },
    }
}

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
    const alloc_name = "__global_allocator";
    const b = try self.getBuilder();

    // Capture operands as ZigValues
    const left_val = try self.captureExpr(binop.left.*);
    const right_val = try self.captureExpr(binop.right.*);

    // Get the format string (parser already strips quotes)
    const format_str = if (binop.left.* == .constant and binop.left.constant.value == .string)
        binop.left.constant.value.string
    else
        null;

    // For simple cases like "%d" % n where n is potentially BigInt, use comptime-aware formatting
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // If format string is a variable (not literal), use runtime formatting
    // This must be checked BEFORE creating the buffer/writer
    if (format_str == null) {
        try emitRuntimePyStringFormat(self, b, label_id, alloc_name, left_val, right_val);
        try self.flushBuilder();
        return;
    }

    // For formats that need special handling, use runtime.pyStringFormat:
    // - %f/%e/%g: Banker's rounding and proper semantics
    // - %d/%i/%s: Avoid Zig format ambiguity with types that have format() methods (UnifiedInt, PyValue)
    // This must be checked BEFORE creating the buffer/writer
    if (format_str) |fmt| {
        var fi: usize = 0;
        while (fi < fmt.len) {
            if (fmt[fi] == '%' and fi + 1 < fmt.len) {
                const fspec = parseFormatSpec(fmt, fi);
                // Route all common formats to runtime for safety:
                // - 'd', 'i': integers (avoids {} ambiguity with UnifiedInt)
                // - 's': strings (avoids {} ambiguity with PyValue)
                // - 'f', 'e', 'E', 'g', 'G': floats (banker's rounding)
                if (fspec.spec_char == 'f' or fspec.spec_char == 'e' or fspec.spec_char == 'E' or
                    fspec.spec_char == 'g' or fspec.spec_char == 'G' or
                    fspec.spec_char == 'd' or fspec.spec_char == 'i' or fspec.spec_char == 's')
                {
                    try emitRuntimePyStringFormat(self, b, label_id, alloc_name, left_val, right_val);
                    try self.flushBuilder();
                    return;
                }
                break; // Only check first format specifier
            }
            fi += 1;
        }
    }

    // Use unique buf AND writer names to avoid shadowing in nested format expressions
    // e.g., "%s" % repr(x) where repr(x) generates another format block
    try emitFormatBlockOpen(self, b, label_id, alloc_name);

    // Check if right side is a tuple (multiple values)
    if (binop.right.* == .tuple) {
        // Multiple format arguments: "%s %d" % (name, age)
        const tuple = binop.right.tuple;
        if (format_str) |fmt| {
            // Parse format string and match with tuple elements
            // Use catch unreachable since we're often inside non-error contexts like panic args
            try b.writeFmt("__writer_{d}.print(\"", .{label_id});
            // Convert Python format to Zig format
            var i: usize = 0;
            while (i < fmt.len) {
                if (fmt[i] == '%' and i + 1 < fmt.len) {
                    const fspec = parseFormatSpec(fmt, i);
                    try emitZigFormatSpec(b, fspec, fmt[i]);
                    i += fspec.consumed;
                } else {
                    try emitEscapedChar(b, fmt[i]);
                    i += 1;
                }
            }
            try b.emitRaw("\", .{");
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
                    if (elem_idx > 0) try b.emitRaw(", ");
                    if (elem_idx < tuple.elts.len) {
                        // Capture tuple element
                        const elem_val = try self.captureExpr(tuple.elts[elem_idx]);
                        // For hex/octal formats, wrap in runtime.formatInt to handle bool
                        if (fspec2.spec_char == 'x' or fspec2.spec_char == 'X' or fspec2.spec_char == 'o') {
                            try emitFormatInt(self, b, elem_val, fspec2.spec_char);
                        } else if (fspec2.spec_char == 'r') {
                            try emitPyRepr(self, b, elem_val, alloc_name);
                        } else if (fspec2.spec_char == 's') {
                            // For %s, check if argument is a string type
                            // If not, use pyRepr to convert to string (Python's str() behavior)
                            const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
                            const string_traits = @import("../../../../analysis/traits/string_traits.zig");
                            const elem_type = self.inferExprScoped(tuple.elts[elem_idx]) catch NativeType.unknown;
                            if (string_traits.isString(elem_type)) {
                                try self.emitZigValue(elem_val);
                            } else {
                                // Non-string: use pyRepr for str() conversion
                                try emitPyRepr(self, b, elem_val, alloc_name);
                            }
                        } else {
                            try self.emitZigValue(elem_val);
                        }
                        elem_idx += 1;
                    }
                    fmt_idx += fspec2.consumed;
                } else {
                    fmt_idx += 1;
                }
            }
            try b.emitRaw("}) catch unreachable;\n");
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
            try b.writeFmt("__writer_{d}.print(\"", .{label_id});
            i = 0;
            while (i < fmt.len) {
                if (fmt[i] == '%' and i + 1 < fmt.len) {
                    const fspec = parseFormatSpec(fmt, i);
                    try emitZigFormatSpec(b, fspec, fmt[i]);
                    i += fspec.consumed;
                } else {
                    try emitEscapedChar(b, fmt[i]);
                    i += 1;
                }
            }
            try b.emitRaw("\", .{");
            // For hex/octal formats, wrap value in runtime.formatInt
            if (main_fspec.spec_char == 'x' or main_fspec.spec_char == 'X' or main_fspec.spec_char == 'o') {
                try emitFormatInt(self, b, right_val, main_fspec.spec_char);
            } else if (main_fspec.spec_char == 'd' or main_fspec.spec_char == 'i') {
                // For %d/%i with bool, convert to int
                const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
                const right_type = self.inferExprScoped(binop.right.*) catch NativeType.unknown;
                if (type_traits.isBoolean(right_type)) {
                    try emitBoolToI64(self, b, right_val);
                } else {
                    try self.emitZigValue(right_val);
                }
            } else if (main_fspec.spec_char == 'r') {
                try emitPyRepr(self, b, right_val, alloc_name);
            } else if (main_fspec.spec_char == 's') {
                // For %s, check if argument is a string type
                // If not, use pyRepr to convert to string (Python's str() behavior)
                const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
                const string_traits = @import("../../../../analysis/traits/string_traits.zig");
                const right_type = self.inferExprScoped(binop.right.*) catch NativeType.unknown;
                if (string_traits.isString(right_type)) {
                    try self.emitZigValue(right_val);
                } else {
                    // Non-string: use pyRepr for str() conversion
                    try emitPyRepr(self, b, right_val, alloc_name);
                }
            } else {
                try self.emitZigValue(right_val);
            }
            try b.emitRaw("}) catch unreachable;\n");
        }
        // Note: else case (variable format string) is handled early with return
    }

    // Use catch unreachable since print/toOwnedSlice won't fail with valid allocator in most cases
    try emitFormatBlockClose(b, label_id, alloc_name);
    try self.flushBuilder();
}
