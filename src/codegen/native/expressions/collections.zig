/// Collection literal code generation
/// Handles list and dict literal expressions
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const expressions = @import("../expressions.zig");
const genExpr = expressions.genExpr;

/// Generate list literal as ArrayList (Python lists are always mutable)
pub fn genList(self: *NativeCodegen, list: ast.Node.List) CodegenError!void {
    // ALL Python lists must be ArrayList for mutability
    // Empty lists
    if (list.elts.len == 0) {
        try self.output.appendSlice(self.allocator, "std.ArrayList(i64){}");
        return;
    }

    // Non-empty lists: create ArrayList and append elements
    try self.output.appendSlice(self.allocator, "blk: {\n");
    self.indent();
    try self.emitIndent();

    // Infer element type
    const elem_type = try self.type_inferrer.inferExpr(list.elts[0]);

    try self.output.appendSlice(self.allocator, "var _list = std.ArrayList(");
    try elem_type.toZigType(self.allocator, &self.output);
    try self.output.appendSlice(self.allocator, "){};\n");

    // Append each element
    for (list.elts) |elem| {
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "try _list.append(allocator, ");
        try genExpr(self, elem);
        try self.output.appendSlice(self.allocator, ");\n");
    }

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :blk _list;\n");
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

    // Generate: blk: {
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
