/// Collection literal code generation
/// Handles list and dict literal expressions
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const expressions = @import("../expressions.zig");
const genExpr = expressions.genExpr;

/// Check if a node is a compile-time constant (can use comptime)
fn isComptimeConstant(node: ast.Node) bool {
    return switch (node) {
        .constant => true,
        .unaryop => |u| isComptimeConstant(u.operand.*),
        .binop => |b| isComptimeConstant(b.left.*) and isComptimeConstant(b.right.*),
        else => false,
    };
}

/// Generate list literal as ArrayList (Python lists are always mutable)
pub fn genList(self: *NativeCodegen, list: ast.Node.List) CodegenError!void {
    // ALL Python lists must be ArrayList for mutability
    // Empty lists
    if (list.elts.len == 0) {
        try self.output.appendSlice(self.allocator, "std.ArrayList(i64){}");
        return;
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
        return;
    }

    // RUNTIME PATH: Dynamic list (fallback to current widening approach)
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

/// Generate dict literal as StringHashMap
pub fn genDict(self: *NativeCodegen, dict: ast.Node.Dict) CodegenError!void {
    // Infer value type - check if all values have same type
    var val_type: @import("../../../analysis/native_types.zig").NativeType = .unknown;
    if (dict.values.len > 0) {
        val_type = try self.type_inferrer.inferExpr(dict.values[0]);

        // Check if all values have consistent type
        var all_same = true;
        for (dict.values[1..]) |value| {
            const this_type = try self.type_inferrer.inferExpr(value);
            // Simple type equality check
            if (@as(std.meta.Tag(@TypeOf(val_type)), val_type) != @as(std.meta.Tag(@TypeOf(this_type)), this_type)) {
                all_same = false;
                break;
            }
        }

        // If mixed types, convert all to strings (Python's str())
        if (!all_same) {
            val_type = .string;
        }
    }

    // Generate: cast_blk: {
    //   var map = std.StringHashMap(T).init(allocator);
    //   try map.put("key", value);
    //   break :blk map;
    // }

    try self.output.appendSlice(self.allocator, "blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var map = std.StringHashMap(");
    try val_type.toZigType(self.allocator, &self.output);
    try self.output.appendSlice(self.allocator, ").init(allocator);\n");

    // Track if we need to convert values to strings
    const need_str_conversion = val_type == .string;

    // Check if we have mixed types (need memory management)
    var has_mixed_types = false;
    if (need_str_conversion and dict.values.len > 0) {
        const first_type = try self.type_inferrer.inferExpr(dict.values[0]);
        for (dict.values[1..]) |value| {
            const this_type = try self.type_inferrer.inferExpr(value);
            if (@as(std.meta.Tag(@TypeOf(first_type)), first_type) != @as(std.meta.Tag(@TypeOf(this_type)), this_type)) {
                has_mixed_types = true;
                break;
            }
        }
    }

    // Add all key-value pairs
    for (dict.keys, dict.values) |key, value| {
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "try map.put(");
        try genExpr(self, key);
        try self.output.appendSlice(self.allocator, ", ");

        // If dict values are string type and this value isn't string, convert it
        if (need_str_conversion) {
            const value_type = try self.type_inferrer.inferExpr(value);
            if (value_type != .string) {
                // Convert to string using std.fmt.allocPrint
                try self.output.appendSlice(self.allocator, "try std.fmt.allocPrint(allocator, ");
                switch (value_type) {
                    .int => try self.output.appendSlice(self.allocator, "\"{d}\""),
                    .float => try self.output.appendSlice(self.allocator, "\"{d}\""),
                    .bool => try self.output.appendSlice(self.allocator, "\"{any}\""),
                    else => try self.output.appendSlice(self.allocator, "\"{any}\""),
                }
                try self.output.appendSlice(self.allocator, ", .{");
                try genExpr(self, value);
                try self.output.appendSlice(self.allocator, "})");
            } else if (has_mixed_types) {
                // For mixed-type dicts, duplicate ALL strings so we can free uniformly
                try self.output.appendSlice(self.allocator, "try allocator.dupe(u8, ");
                try genExpr(self, value);
                try self.output.appendSlice(self.allocator, ")");
            } else {
                try genExpr(self, value);
            }
        } else {
            try genExpr(self, value);
        }

        try self.output.appendSlice(self.allocator, ");\n");
    }

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :blk map;\n");
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}
