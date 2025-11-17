/// Miscellaneous statement code generation (return, print, import, assert)
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

/// Flatten nested string concatenation into a list of parts
/// (s1 + " ") + s2 becomes [s1, " ", s2]
fn flattenConcat(self: *NativeCodegen, node: ast.Node, parts: *std.ArrayList(ast.Node)) CodegenError!void {
    if (node == .binop and node.binop.op == .Add) {
        // Check if this is string concat
        const left_type = try self.type_inferrer.inferExpr(node.binop.left.*);
        const right_type = try self.type_inferrer.inferExpr(node.binop.right.*);

        if (left_type == .string or right_type == .string) {
            // Recursively flatten left side
            try flattenConcat(self, node.binop.left.*, parts);
            // Recursively flatten right side
            try flattenConcat(self, node.binop.right.*, parts);
            return;
        }
    }

    // Not a string concat, just add the node
    try parts.append(self.allocator, node);
}

/// Check if a node is an allocating method call (e.g., "text".upper())
fn isAllocatingMethodCall(self: *NativeCodegen, node: ast.Node) bool {
    if (node != .call) return false;
    const call = node.call;
    if (call.func.* != .attribute) return false;

    const attr = call.func.attribute;
    const obj_type = self.type_inferrer.inferExpr(attr.value.*) catch return false;

    if (obj_type == .string) {
        const allocating_methods = [_][]const u8{
            "upper",
            "lower",
            "strip",
            "lstrip",
            "rstrip",
            "replace",
            "capitalize",
            "title",
            "swapcase",
        };
        for (allocating_methods) |method| {
            if (std.mem.eql(u8, attr.attr, method)) return true;
        }
    }
    return false;
}

/// Generate return statement
pub fn genReturn(self: *NativeCodegen, ret: ast.Node.Return) CodegenError!void {
    try self.emitIndent();
    try self.emit("return ");
    if (ret.value) |value| {
        try self.genExpr(value.*);
    }
    try self.emit(";\n");
}

/// Generate from-import statement: from module import names
/// For MVP, just comment out imports - assume functions are in same file
pub fn genImportFrom(self: *NativeCodegen, import: ast.Node.ImportFrom) CodegenError!void {
    try self.emitIndent();
    try self.emit("// from ");
    try self.emit(import.module);
    try self.emit(" import ");

    for (import.names, 0..) |name, i| {
        if (i > 0) try self.emit(", ");
        try self.emit(name);
        // Handle aliases if present
        if (import.asnames[i]) |asname| {
            try self.emit(" as ");
            try self.emit(asname);
        }
    }
    try self.emit("\n");
}

/// Generate print() function call
pub fn genPrint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.output.appendSlice(self.allocator, "std.debug.print(\"\\n\", .{});\n");
        return;
    }

    // Check if any arg is string concatenation, allocating method call, list, tuple, or bool
    var has_string_concat = false;
    var has_allocating_call = false;
    var has_list = false;
    var has_tuple = false;
    var has_bool = false;
    for (args) |arg| {
        if (arg == .binop and arg.binop.op == .Add) {
            const left_type = try self.type_inferrer.inferExpr(arg.binop.left.*);
            const right_type = try self.type_inferrer.inferExpr(arg.binop.right.*);
            if (left_type == .string or right_type == .string) {
                has_string_concat = true;
                break;
            }
        }
        if (isAllocatingMethodCall(self, arg)) {
            has_allocating_call = true;
        }
        const arg_type = try self.type_inferrer.inferExpr(arg);
        if (arg_type == .list) {
            has_list = true;
        }
        if (arg_type == .tuple) {
            has_tuple = true;
        }
        if (arg_type == .bool) {
            has_bool = true;
        }
    }

    // If we have lists, tuples, or bools, handle them specially with custom formatting
    if (has_list or has_tuple or has_bool) {
        // For lists, we need to print in Python format: [elem1, elem2, ...]
        for (args, 0..) |arg, i| {
            const arg_type = try self.type_inferrer.inferExpr(arg);
            if (arg_type == .list) {
                // Generate loop to print list elements
                try self.output.appendSlice(self.allocator, "{\n");
                try self.output.appendSlice(self.allocator, "    const __list = ");
                try self.genExpr(arg);
                try self.output.appendSlice(self.allocator, ";\n");
                try self.output.appendSlice(self.allocator, "    std.debug.print(\"[\", .{});\n");
                try self.output.appendSlice(self.allocator, "    for (__list, 0..) |__elem, __idx| {\n");
                try self.output.appendSlice(self.allocator, "        if (__idx > 0) std.debug.print(\", \", .{});\n");
                try self.output.appendSlice(self.allocator, "        std.debug.print(\"{d}\", .{__elem});\n");
                try self.output.appendSlice(self.allocator, "    }\n");
                try self.output.appendSlice(self.allocator, "    std.debug.print(\"]\", .{});\n");
                try self.output.appendSlice(self.allocator, "}\n");
            } else if (arg_type == .tuple) {
                // Generate inline print for tuple elements
                try self.output.appendSlice(self.allocator, "{\n");
                try self.output.appendSlice(self.allocator, "    const __tuple = ");
                try self.genExpr(arg);
                try self.output.appendSlice(self.allocator, ";\n");
                try self.output.appendSlice(self.allocator, "    std.debug.print(\"(\", .{});\n");
                // Get tuple type to know how many elements
                if (arg_type.tuple.len > 0) {
                    for (0..arg_type.tuple.len) |elem_idx| {
                        if (elem_idx > 0) {
                            try self.output.appendSlice(self.allocator, "    std.debug.print(\", \", .{});\n");
                        }
                        try self.output.writer(self.allocator).print("    std.debug.print(\"{{d}}\", .{{__tuple.@\"{d}\"}});\n", .{elem_idx});
                    }
                }
                try self.output.appendSlice(self.allocator, "    std.debug.print(\")\", .{});\n");
                try self.output.appendSlice(self.allocator, "}\n");
            } else if (arg_type == .bool) {
                // Print booleans as Python-style True/False
                try self.output.appendSlice(self.allocator, "std.debug.print(\"{s}\", .{if (");
                try self.genExpr(arg);
                try self.output.appendSlice(self.allocator, ") \"True\" else \"False\"});\n");
            } else {
                // For non-list/tuple/bool args in mixed print, use std.debug.print
                try self.output.appendSlice(self.allocator, "std.debug.print(\"");
                const fmt = switch (arg_type) {
                    .int => "{d}",
                    .float => "{d}",
                    .string => "{s}",
                    else => "{any}",
                };
                try self.output.appendSlice(self.allocator, fmt);
                try self.output.appendSlice(self.allocator, "\", .{");
                try self.genExpr(arg);
                try self.output.appendSlice(self.allocator, "});\n");
            }
            // Print space between args (except last)
            if (i < args.len - 1) {
                try self.output.appendSlice(self.allocator, "std.debug.print(\" \", .{});\n");
            }
        }
        // Print newline at end
        try self.output.appendSlice(self.allocator, "std.debug.print(\"\\n\", .{});\n");
        return;
    }

    // If we have string concatenation or allocating calls, wrap in block with temp vars
    if (has_string_concat or has_allocating_call) {
        try self.output.appendSlice(self.allocator, "{\n");
        self.indent();

        // Create temp vars for each concatenation or allocating method call
        var temp_counter: usize = 0;
        for (args) |arg| {
            // Handle string concatenation
            if (arg == .binop and arg.binop.op == .Add) {
                const left_type = try self.type_inferrer.inferExpr(arg.binop.left.*);
                const right_type = try self.type_inferrer.inferExpr(arg.binop.right.*);
                if (left_type == .string or right_type == .string) {
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("const _temp{d} = ", .{temp_counter});

                    // Flatten nested concatenations
                    var parts = std.ArrayList(ast.Node){};
                    defer parts.deinit(self.allocator);
                    try flattenConcat(self, arg, &parts);

                    try self.output.appendSlice(self.allocator, "try std.mem.concat(allocator, u8, &[_][]const u8{ ");
                    for (parts.items, 0..) |part, i| {
                        if (i > 0) try self.output.appendSlice(self.allocator, ", ");
                        try self.genExpr(part);
                    }
                    try self.output.appendSlice(self.allocator, " });\n");

                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("defer allocator.free(_temp{d});\n", .{temp_counter});
                    temp_counter += 1;
                }
            }
            // Handle allocating method calls
            else if (isAllocatingMethodCall(self, arg)) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("const _temp{d}: []const u8 = ", .{temp_counter});
                try self.genExpr(arg);
                try self.output.appendSlice(self.allocator, ";\n");
                try self.emitIndent();
                try self.output.writer(self.allocator).print("defer allocator.free(_temp{d});\n", .{temp_counter});
                temp_counter += 1;
            }
        }

        // Emit print statement
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "std.debug.print(\"");

        // Generate format string
        for (args, 0..) |arg, i| {
            const arg_type = try self.type_inferrer.inferExpr(arg);
            const fmt = switch (arg_type) {
                .int => "{d}",
                .float => "{d}",
                .bool => "{}",
                .string => "{s}",
                else => "{any}",
            };
            try self.output.appendSlice(self.allocator, fmt);

            if (i < args.len - 1) {
                try self.output.appendSlice(self.allocator, " ");
            }
        }

        try self.output.appendSlice(self.allocator, "\\n\", .{");

        // Generate arguments (use temp vars for concat and allocating calls)
        temp_counter = 0;
        for (args, 0..) |arg, i| {
            // Use temp var for string concatenation
            if (arg == .binop and arg.binop.op == .Add) {
                const left_type = try self.type_inferrer.inferExpr(arg.binop.left.*);
                const right_type = try self.type_inferrer.inferExpr(arg.binop.right.*);
                if (left_type == .string or right_type == .string) {
                    try self.output.writer(self.allocator).print("_temp{d}", .{temp_counter});
                    temp_counter += 1;
                } else {
                    try self.genExpr(arg);
                }
            }
            // Use temp var for allocating method calls
            else if (isAllocatingMethodCall(self, arg)) {
                try self.output.writer(self.allocator).print("_temp{d}", .{temp_counter});
                temp_counter += 1;
            } else {
                try self.genExpr(arg);
            }
            if (i < args.len - 1) {
                try self.output.appendSlice(self.allocator, ", ");
            }
        }

        try self.output.appendSlice(self.allocator, "});\n");

        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
    } else {
        // No string concatenation - simple print
        try self.output.appendSlice(self.allocator, "std.debug.print(\"");

        // Generate format string
        for (args, 0..) |arg, i| {
            const arg_type = try self.type_inferrer.inferExpr(arg);
            const fmt = switch (arg_type) {
                .int => "{d}",
                .float => "{d}",
                .bool => "{}",
                .string => "{s}",
                else => "{any}",
            };
            try self.output.appendSlice(self.allocator, fmt);

            if (i < args.len - 1) {
                try self.output.appendSlice(self.allocator, " ");
            }
        }

        try self.output.appendSlice(self.allocator, "\\n\", .{");

        // Generate arguments
        for (args, 0..) |arg, i| {
            try self.genExpr(arg);
            if (i < args.len - 1) {
                try self.output.appendSlice(self.allocator, ", ");
            }
        }

        try self.output.appendSlice(self.allocator, "});\n");
    }
}

/// Generate assert statement
/// Transforms: assert condition or assert condition, message
/// Into: if (!(condition)) { std.debug.panic("Assertion failed", .{}); }
pub fn genAssert(self: *NativeCodegen, assert_node: ast.Node.Assert) CodegenError!void {
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "if (!(");
    try self.genExpr(assert_node.condition.*);
    try self.output.appendSlice(self.allocator, ")) {\n");

    self.indent();
    try self.emitIndent();

    if (assert_node.msg) |msg| {
        // assert x, "message"
        try self.output.appendSlice(self.allocator, "std.debug.panic(\"Assertion failed: {s}\", .{");
        try self.genExpr(msg.*);
        try self.output.appendSlice(self.allocator, "});\n");
    } else {
        // assert x
        try self.output.appendSlice(self.allocator, "std.debug.panic(\"Assertion failed\", .{});\n");
    }

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
}
