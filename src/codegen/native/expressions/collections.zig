/// List literal code generation
/// Handles list literal expressions with array optimization and comptime/runtime paths
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const expressions = @import("../expressions.zig");
const genExpr = expressions.genExpr;

// Re-export dict generation from dict.zig
const dict = @import("dict.zig");
pub const genDict = dict.genDict;

// Re-export isComptimeConstant for use by other modules
pub const isComptimeConstant = dict.isComptimeConstant;

/// Check if a list contains only literal values (candidates for array optimization)
fn isConstantList(list: ast.Node.List) bool {
    if (list.elts.len == 0) return false; // Empty lists stay dynamic

    for (list.elts) |elem| {
        // Check if element is a literal constant
        const is_literal = switch (elem) {
            .constant => true,
            else => false,
        };
        if (!is_literal) return false;
    }

    return true;
}

/// Check if all elements in a list have the same type (homogeneous)
fn allSameType(elements: []ast.Node) bool {
    if (elements.len == 0) return true;

    // Get type tag of first element
    const first_const = switch (elements[0]) {
        .constant => |c| c,
        else => return false,
    };

    const first_type_tag = @as(std.meta.Tag(@TypeOf(first_const.value)), first_const.value);

    // Check all other elements match
    for (elements[1..]) |elem| {
        const elem_const = switch (elem) {
            .constant => |c| c,
            else => return false,
        };

        const elem_type_tag = @as(std.meta.Tag(@TypeOf(elem_const.value)), elem_const.value);
        if (elem_type_tag != first_type_tag) return false;
    }

    return true;
}

/// Generate fixed-size array literal for constant, homogeneous lists
fn genArrayLiteral(self: *NativeCodegen, list: ast.Node.List) CodegenError!void {
    // Determine element type from first element
    const elem_type_str = switch (list.elts[0].constant.value) {
        .int => "i64",
        .float => "f64",
        .string => "[]const u8",
        .bool => "bool",
        .none => "void",
    };

    // Emit array literal: [_]T{elem1, elem2, ...}
    try self.output.appendSlice(self.allocator, "[_]");
    try self.output.appendSlice(self.allocator, elem_type_str);
    try self.output.appendSlice(self.allocator, "{");

    for (list.elts, 0..) |elem, i| {
        if (i > 0) try self.output.appendSlice(self.allocator, ", ");

        // Emit element value - use genExpr for proper formatting
        try genExpr(self, elem);
    }

    try self.output.appendSlice(self.allocator, "}");
}

/// Generate list literal as ArrayList (Python lists are always mutable)
pub fn genList(self: *NativeCodegen, list: ast.Node.List) CodegenError!void {
    // Empty lists
    if (list.elts.len == 0) {
        try self.output.appendSlice(self.allocator, "std.ArrayList(i64){}");
        return;
    }

    // Check if we can optimize to fixed-size array (constant + homogeneous)
    if (isConstantList(list) and allSameType(list.elts)) {
        return try genArrayLiteral(self, list);
    }

    // Check if all elements are compile-time constants → use comptime optimization!
    var all_comptime = true;
    for (list.elts) |elem| {
        if (!isComptimeConstant(elem)) {
            all_comptime = false;
            break;
        }
    }

    // COMPTIME PATH: All elements known at compile time
    if (all_comptime) {
        try genListComptime(self, list);
        return;
    }

    // RUNTIME PATH: Dynamic list (fallback to current widening approach)
    try genListRuntime(self, list);
}

/// Generate comptime-optimized list literal
fn genListComptime(self: *NativeCodegen, list: ast.Node.List) CodegenError!void {
    // Generate unique block label
    const label = try std.fmt.allocPrint(self.allocator, "list_{d}", .{@intFromPtr(list.elts.ptr)});
    defer self.allocator.free(label);

    try self.output.appendSlice(self.allocator, label);
    try self.output.appendSlice(self.allocator, ": {\n");
    self.indent();
    try self.emitIndent();

    // Generate comptime tuple
    try self.output.appendSlice(self.allocator, "const _values = .{ ");
    for (list.elts, 0..) |elem, i| {
        if (i > 0) try self.output.appendSlice(self.allocator, ", ");
        try genExpr(self, elem);
    }
    try self.output.appendSlice(self.allocator, " };\n");

    // Let Zig's comptime infer the type and generate optimal code
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const T = comptime runtime.InferListType(@TypeOf(_values));\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var _list = std.ArrayList(T){};\n");

    // Inline loop - unrolled at Zig compile time!
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "inline for (_values) |val| {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const cast_val = if (@TypeOf(val) != T) cast_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "if (T == f64 and (@TypeOf(val) == i64 or @TypeOf(val) == comptime_int)) {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :cast_blk @as(f64, @floatFromInt(val));\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "if (T == f64 and @TypeOf(val) == comptime_float) {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :cast_blk @as(f64, val);\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :cast_blk val;\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "} else val;\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "try _list.append(allocator, cast_val);\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :");
    try self.output.appendSlice(self.allocator, label);
    try self.output.appendSlice(self.allocator, " _list;\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Generate runtime list literal (fallback path)
fn genListRuntime(self: *NativeCodegen, list: ast.Node.List) CodegenError!void {
    const runtime_label = try std.fmt.allocPrint(self.allocator, "list_{d}", .{@intFromPtr(list.elts.ptr)});
    defer self.allocator.free(runtime_label);

    try self.output.appendSlice(self.allocator, runtime_label);
    try self.output.appendSlice(self.allocator, ": {\n");
    self.indent();
    try self.emitIndent();

    // Infer element type using type widening
    var elem_type = try self.type_inferrer.inferExpr(list.elts[0]);

    // Widen type to accommodate all elements
    for (list.elts[1..]) |elem| {
        const this_type = try self.type_inferrer.inferExpr(elem);
        elem_type = elem_type.widen(this_type);
    }

    try self.output.appendSlice(self.allocator, "var _list = std.ArrayList(");
    try elem_type.toZigType(self.allocator, &self.output);
    try self.output.appendSlice(self.allocator, "){};\n");

    // Append each element (with type coercion if needed)
    for (list.elts) |elem| {
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "try _list.append(allocator, ");

        // Check if we need to cast this element
        const this_type = try self.type_inferrer.inferExpr(elem);
        const needs_cast = (elem_type == .float and this_type == .int);

        if (needs_cast) {
            try self.output.appendSlice(self.allocator, "@as(f64, @floatFromInt(");
            try genExpr(self, elem);
            try self.output.appendSlice(self.allocator, "))");
        } else {
            try genExpr(self, elem);
        }

        try self.output.appendSlice(self.allocator, ");\n");
    }

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :");
    try self.output.appendSlice(self.allocator, runtime_label);
    try self.output.appendSlice(self.allocator, " _list;\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}
