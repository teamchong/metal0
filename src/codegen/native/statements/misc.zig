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

    // Check if any arg is string concatenation (needs temp var + defer)
    var has_string_concat = false;
    for (args) |arg| {
        if (arg == .binop and arg.binop.op == .Add) {
            const left_type = try self.type_inferrer.inferExpr(arg.binop.left.*);
            const right_type = try self.type_inferrer.inferExpr(arg.binop.right.*);
            if (left_type == .string or right_type == .string) {
                has_string_concat = true;
                break;
            }
        }
    }

    // If we have string concatenation, wrap in block with temp vars
    if (has_string_concat) {
        try self.output.appendSlice(self.allocator, "{\n");
        self.indent();

        // Create temp vars for each concatenation
        var temp_counter: usize = 0;
        for (args) |arg| {
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

        // Generate arguments (use temp vars for concat)
        temp_counter = 0;
        for (args, 0..) |arg, i| {
            if (arg == .binop and arg.binop.op == .Add) {
                const left_type = try self.type_inferrer.inferExpr(arg.binop.left.*);
                const right_type = try self.type_inferrer.inferExpr(arg.binop.right.*);
                if (left_type == .string or right_type == .string) {
                    try self.output.writer(self.allocator).print("_temp{d}", .{temp_counter});
                    temp_counter += 1;
                } else {
                    try self.genExpr(arg);
                }
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
