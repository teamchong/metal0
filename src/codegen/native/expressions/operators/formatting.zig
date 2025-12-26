/// String formatting operations
/// Handles Python % operator for string formatting: "%d" % value
///
/// MIGRATION STATUS: Prepared for ZigBuilder - imports added
/// - Uses labeled blocks heavily, migration deferred
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

// MIGRATED TO ZIGBUILDER

// ============================================
// Format operation helpers - auto-closing patterns
// ============================================

/// Emit format block open: fmt_N: { var __fmt_buf_N = ...; const __writer_N = ...;
fn emitFormatBlockOpen(self: *NativeCodegen, label_id: usize, alloc_name: []const u8) CodegenError!void {
    try self.emitFmt("fmt_{d}: {{\n", .{label_id});
    try self.emitFmt("var __fmt_buf_{d} = std.ArrayListUnmanaged(u8)", .{label_id});
    try self.emit("{};\n");
    try self.emitFmt("const __writer_{d} = __fmt_buf_{d}.writer({s});\n", .{ label_id, label_id, alloc_name });
}

/// Emit format block close: break :fmt_N __fmt_buf_N.toOwnedSlice(alloc) catch unreachable; }
fn emitFormatBlockClose(self: *NativeCodegen, label_id: usize, alloc_name: []const u8) CodegenError!void {
    try self.emitFmt("break :fmt_{d} __fmt_buf_{d}.toOwnedSlice({s}) catch unreachable;\n}}", .{ label_id, label_id, alloc_name });
}

/// Emit runtime.formatInt(expr, base)
fn emitFormatInt(self: *NativeCodegen, expr: ast.Node, spec_char: u8) CodegenError!void {
    try self.emit("runtime.formatInt(");
    try genExpr(self, expr);
    switch (spec_char) {
        'x' => try self.emit(", .hex_lower)"),
        'X' => try self.emit(", .hex_upper)"),
        else => try self.emit(", .octal)"), // 'o'
    }
}

/// Emit runtime.builtins.pyRepr(alloc, expr) catch unreachable
fn emitPyRepr(self: *NativeCodegen, expr: ast.Node, alloc_name: []const u8) CodegenError!void {
    try self.emitFmt("(runtime.builtins.pyRepr({s}, ", .{alloc_name});
    try genExpr(self, expr);
    try self.emit(") catch unreachable)");
}

/// Emit @as(i64, @intFromBool(expr))
fn emitBoolToI64(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    try self.emit("@as(i64, @intFromBool(");
    try genExpr(self, expr);
    try self.emit("))");
}

/// Emit runtime pyStringFormat for variable format strings
fn emitRuntimePyStringFormat(self: *NativeCodegen, label_id: usize, alloc_name: []const u8, left: ast.Node, right: ast.Node) CodegenError!void {
    try self.emitFmt("fmt_{d}: {{\n", .{label_id});
    try self.emitFmt("break :fmt_{d} try runtime.pyStringFormat({s}, ", .{ label_id, alloc_name });
    try genExpr(self, left);
    try self.emit(", ");
    try genExpr(self, right);
    try self.emit(");\n}");
}

/// Emit escaped character for Zig format string
fn emitEscapedChar(self: *NativeCodegen, c: u8) CodegenError!void {
    switch (c) {
        '{' => try self.emit("{{"),
        '}' => try self.emit("}}"),
        '"' => try self.emit("\\\""),
        '\\' => try self.emit("\\\\"),
        '\n' => try self.emit("\\n"),
        '\r' => try self.emit("\\r"),
        '\t' => try self.emit("\\t"),
        else => try self.emitFmt("{c}", .{c}),
    }
}

/// Emit Zig format specifier for Python format spec
fn emitZigFormatSpec(self: *NativeCodegen, fspec: FormatSpec, fallback_fmt_char: u8) CodegenError!void {
    switch (fspec.spec_char) {
        'd', 'i' => try self.emit("{any}"),
        's' => try self.emit("{s}"),
        'f' => {
            if (fspec.precision) |p| {
                try self.emitFmt("{{d:.{d}}}", .{p});
            } else {
                try self.emit("{d}");
            }
        },
        'g', 'G' => try self.emit("{d}"),
        'e', 'E' => try self.emit("{e}"),
        'x', 'X', 'o' => try self.emit("{s}"),
        'r' => try self.emit("{s}"),
        '%' => try self.emit("%"),
        else => {
            try self.emitFmt("{c}", .{fallback_fmt_char});
            try self.emitFmt("{c}", .{fspec.spec_char});
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
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

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
        try emitRuntimePyStringFormat(self, label_id, alloc_name, binop.left.*, binop.right.*);
        return;
    }

    // For %f/%e/%g formats (float formatting), use runtime.pyStringFormat for banker's rounding
    // This must be checked BEFORE creating the buffer/writer
    if (format_str) |fmt| {
        var fi: usize = 0;
        while (fi < fmt.len) {
            if (fmt[fi] == '%' and fi + 1 < fmt.len) {
                const fspec = parseFormatSpec(fmt, fi);
                if (fspec.spec_char == 'f' or fspec.spec_char == 'e' or fspec.spec_char == 'E' or
                    fspec.spec_char == 'g' or fspec.spec_char == 'G')
                {
                    // Use runtime formatting for banker's rounding and proper %g semantics
                    try emitRuntimePyStringFormat(self, label_id, alloc_name, binop.left.*, binop.right.*);
                    return;
                }
                break; // Only check first format specifier
            }
            fi += 1;
        }
    }

    // Use unique buf AND writer names to avoid shadowing in nested format expressions
    // e.g., "%s" % repr(x) where repr(x) generates another format block
    try emitFormatBlockOpen(self, label_id, alloc_name);

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
                    try emitZigFormatSpec(self, fspec, fmt[i]);
                    i += fspec.consumed;
                } else {
                    try emitEscapedChar(self, fmt[i]);
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
                            try emitFormatInt(self, tuple.elts[elem_idx], fspec2.spec_char);
                        } else if (fspec2.spec_char == 'r') {
                            try emitPyRepr(self, tuple.elts[elem_idx], alloc_name);
                        } else if (fspec2.spec_char == 's') {
                            // For %s, check if argument is a string type
                            // If not, use pyRepr to convert to string (Python's str() behavior)
                            const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
                            const string_traits = @import("../../../../analysis/traits/string_traits.zig");
                            const elem_type = self.inferExprScoped(tuple.elts[elem_idx]) catch NativeType.unknown;
                            if (string_traits.isString(elem_type)) {
                                try genExpr(self, tuple.elts[elem_idx]);
                            } else {
                                // Non-string: use pyRepr for str() conversion
                                try emitPyRepr(self, tuple.elts[elem_idx], alloc_name);
                            }
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
                    try emitZigFormatSpec(self, fspec, fmt[i]);
                    i += fspec.consumed;
                } else {
                    try emitEscapedChar(self, fmt[i]);
                    i += 1;
                }
            }
            try self.emit("\", .{");
            // For hex/octal formats, wrap value in runtime.formatInt
            if (main_fspec.spec_char == 'x' or main_fspec.spec_char == 'X' or main_fspec.spec_char == 'o') {
                try emitFormatInt(self, binop.right.*, main_fspec.spec_char);
            } else if (main_fspec.spec_char == 'd' or main_fspec.spec_char == 'i') {
                // For %d/%i with bool, convert to int
                const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
                const right_type = self.inferExprScoped(binop.right.*) catch NativeType.unknown;
                if (type_traits.isBoolean(right_type)) {
                    try emitBoolToI64(self, binop.right.*);
                } else {
                    try genExpr(self, binop.right.*);
                }
            } else if (main_fspec.spec_char == 'r') {
                try emitPyRepr(self, binop.right.*, alloc_name);
            } else if (main_fspec.spec_char == 's') {
                // For %s, check if argument is a string type
                // If not, use pyRepr to convert to string (Python's str() behavior)
                const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
                const string_traits = @import("../../../../analysis/traits/string_traits.zig");
                const right_type = self.inferExprScoped(binop.right.*) catch NativeType.unknown;
                if (string_traits.isString(right_type)) {
                    try genExpr(self, binop.right.*);
                } else {
                    // Non-string: use pyRepr for str() conversion
                    try emitPyRepr(self, binop.right.*, alloc_name);
                }
            } else {
                try genExpr(self, binop.right.*);
            }
            try self.emit("}) catch unreachable;\n");
        }
        // Note: else case (variable format string) is handled early with return
    }

    // Use catch unreachable since print/toOwnedSlice won't fail with valid allocator in most cases
    try emitFormatBlockClose(self, label_id, alloc_name);
}
