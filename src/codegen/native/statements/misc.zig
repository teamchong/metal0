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

/// Check if expression results in an array slice (not ArrayList)
/// Returns true if this is a subscript slice of a constant array variable
fn isArraySlice(self: *NativeCodegen, node: ast.Node) bool {
    // Check if this is a subscript with slice
    if (node != .subscript) return false;
    if (node.subscript.slice != .slice) return false;

    // Check if the source is a constant array variable
    const value_node = node.subscript.value.*;
    if (value_node == .name) {
        return self.isArrayVar(value_node.name.id);
    }

    return false;
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

/// Generate import statement: import module
/// Import statements are now handled at module level in main.zig
/// This function is a no-op since imports are collected and generated in PHASE 3
pub fn genImport(self: *NativeCodegen, import: ast.Node.Import) CodegenError!void {
    _ = self;
    _ = import;
    // No-op: imports are handled at module level, not during statement generation
}

/// Generate from-import statement: from module import names
/// Import statements are now handled at module level in main.zig
/// This function is a no-op since imports are collected and generated in PHASE 3
pub fn genImportFrom(self: *NativeCodegen, import: ast.Node.ImportFrom) CodegenError!void {
    _ = self;
    _ = import;
    // No-op: imports are handled at module level, not during statement generation
}

/// Generate print() function call
pub fn genPrint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.output.appendSlice(self.allocator, "std.debug.print(\"\\n\", .{});\n");
        return;
    }

    // Check if any arg is string concatenation, allocating method call, list, array, tuple, dict, bool, float, none, or unknown (PyObject)
    var has_string_concat = false;
    var has_allocating_call = false;
    var has_list = false;
    var has_array = false;
    var has_tuple = false;
    var has_dict = false;
    var has_bool = false;
    var has_float = false;
    var has_none = false;
    var has_unknown = false;
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
        if (arg_type == .array) {
            has_array = true;
        }
        if (arg_type == .tuple) {
            has_tuple = true;
        }
        if (arg_type == .dict) {
            has_dict = true;
        }
        if (arg_type == .bool) {
            has_bool = true;
        }
        if (arg_type == .float) {
            has_float = true;
        }
        if (arg_type == .none) {
            has_none = true;
        }
        if (arg_type == .unknown) {
            has_unknown = true;
        }
    }

    // If we have lists, arrays, tuples, dicts, bools, none, or unknowns (PyObject), handle them specially with custom formatting
    if (has_list or has_array or has_tuple or has_dict or has_bool or has_none or has_unknown) {
        // For lists and arrays, we need to print in Python format: [elem1, elem2, ...]
        for (args, 0..) |arg, i| {
            const arg_type = try self.type_inferrer.inferExpr(arg);
            if (arg_type == .list or arg_type == .array) {
                // Check if this is an array slice vs ArrayList vs plain array
                const is_array_slice = isArraySlice(self, arg);
                const is_plain_array = arg_type == .array;
                // Check if this is a slice from listcomp (not in arraylist_vars)
                const is_slice_var = if (arg == .name) !self.arraylist_vars.contains(arg.name.id) else false;

                // Generate loop to print list/array elements
                try self.output.appendSlice(self.allocator, "{\n");
                try self.output.appendSlice(self.allocator, "    const __list = ");
                try self.genExpr(arg);
                try self.output.appendSlice(self.allocator, ";\n");
                try self.output.appendSlice(self.allocator, "    std.debug.print(\"[\", .{});\n");

                // Plain arrays, array slices, and listcomp slices: iterate directly, ArrayList: use .items
                if (is_plain_array or is_array_slice or is_slice_var) {
                    try self.output.appendSlice(self.allocator, "    for (__list, 0..) |__elem, __idx| {\n");
                } else {
                    try self.output.appendSlice(self.allocator, "    for (__list.items, 0..) |__elem, __idx| {\n");
                }

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
                        // Determine format based on element type
                        const elem_type = arg_type.tuple[elem_idx];
                        const fmt = switch (elem_type) {
                            .int => "{d}",
                            .float => "{d}",
                            .bool => "{s}",
                            .string => "{s}",
                            else => "{any}",
                        };
                        if (elem_type == .bool) {
                            // Boolean elements need conditional formatting
                            try self.output.writer(self.allocator).print("    std.debug.print(\"{{s}}\", .{{if (__tuple.@\"{d}\") \"True\" else \"False\"}});\n", .{elem_idx});
                        } else {
                            try self.output.writer(self.allocator).print("    std.debug.print(\"{s}\", .{{__tuple.@\"{d}\"}});\n", .{ fmt, elem_idx });
                        }
                    }
                }
                try self.output.appendSlice(self.allocator, "    std.debug.print(\")\", .{});\n");
                try self.output.appendSlice(self.allocator, "}\n");
            } else if (arg_type == .dict) {
                // Format native dict (HashMap) in Python format: {'key': value, ...}
                // Use comptime to detect value type and format appropriately
                try self.output.appendSlice(self.allocator, "{\n");
                try self.output.appendSlice(self.allocator, "    const __dict = ");
                try self.genExpr(arg);
                try self.output.appendSlice(self.allocator, ";\n");
                try self.output.appendSlice(self.allocator, "    var __dict_iter = __dict.iterator();\n");
                try self.output.appendSlice(self.allocator, "    var __dict_idx: usize = 0;\n");
                try self.output.appendSlice(self.allocator, "    std.debug.print(\"{{\", .{});\n");
                try self.output.appendSlice(self.allocator, "    while (__dict_iter.next()) |__entry| {\n");
                try self.output.appendSlice(self.allocator, "        if (__dict_idx > 0) std.debug.print(\", \", .{});\n");
                try self.output.appendSlice(self.allocator, "        std.debug.print(\"'{s}': \", .{__entry.key_ptr.*});\n");
                try self.output.appendSlice(self.allocator, "        runtime.printValue(__entry.value_ptr.*);\n");
                try self.output.appendSlice(self.allocator, "        __dict_idx += 1;\n");
                try self.output.appendSlice(self.allocator, "    }\n");
                try self.output.appendSlice(self.allocator, "    std.debug.print(\"}}\", .{});\n");
                try self.output.appendSlice(self.allocator, "}\n");
            } else if (arg_type == .unknown) {
                // Use {any} for unknown types - works for any Zig type
                try self.output.appendSlice(self.allocator, "std.debug.print(\"{any}\", .{");
                try self.genExpr(arg);
                try self.output.appendSlice(self.allocator, "});\n");
            } else if (arg_type == .bool) {
                // Print booleans as Python-style True/False
                try self.output.appendSlice(self.allocator, "std.debug.print(\"{s}\", .{if (");
                try self.genExpr(arg);
                try self.output.appendSlice(self.allocator, ") \"True\" else \"False\"});\n");
            } else if (arg_type == .none) {
                // Print None
                try self.output.appendSlice(self.allocator, "std.debug.print(\"None\", .{});\n");
            } else {
                // For non-list/tuple/bool args in mixed print, use std.debug.print
                const fmt = switch (arg_type) {
                    .int => "{d}",
                    .float => "{d}",
                    .string => "{s}",
                    else => "{s}", // Try string format for unknowns (works for string constants)
                };
                try self.output.appendSlice(self.allocator, "std.debug.print(\"");
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
    // Note: floats are now printed directly with {d} format
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

                    // Get allocator name based on scope
                    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

                    try self.output.appendSlice(self.allocator, "try std.mem.concat(");
                    try self.output.appendSlice(self.allocator, alloc_name);
                    try self.output.appendSlice(self.allocator, ", u8, &[_][]const u8{ ");
                    for (parts.items, 0..) |part, i| {
                        if (i > 0) try self.output.appendSlice(self.allocator, ", ");
                        try self.genExpr(part);
                    }
                    try self.output.appendSlice(self.allocator, " });\n");

                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("defer {s}.free(_temp{d});\n", .{ alloc_name, temp_counter });
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
                .float => "{d}", // Print float directly
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
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "std.debug.print(\"");

        // Generate format string
        for (args, 0..) |arg, i| {
            const arg_type = try self.type_inferrer.inferExpr(arg);
            const fmt = switch (arg_type) {
                .int => "{d}",
                .float => "{d}", // Print float directly
                .bool => "{s}", // formatAny() returns string for bool
                .string => "{s}",
                .unknown => "{s}", // Use {s} - works for string constants, fails for others
                else => "{any}", // Other types - let Zig handle them
            };
            try self.output.appendSlice(self.allocator, fmt);

            if (i < args.len - 1) {
                try self.output.appendSlice(self.allocator, " ");
            }
        }

        try self.output.appendSlice(self.allocator, "\\n\", .{");

        // Generate arguments - wrap bools only, use unknowns/native types directly
        for (args, 0..) |arg, i| {
            const arg_type = try self.type_inferrer.inferExpr(arg);
            if (arg_type == .bool) {
                try self.output.appendSlice(self.allocator, "runtime.formatAny(");
                try self.genExpr(arg);
                try self.output.appendSlice(self.allocator, ")");
            } else {
                // For unknown types (module constants), use directly
                // String literals will coerce to []const u8 with {s}
                // Non-string module constants will cause compile error (limitation)
                try self.genExpr(arg);
            }
            if (i < args.len - 1) {
                try self.output.appendSlice(self.allocator, ", ");
            }
        }

        try self.output.appendSlice(self.allocator, "});\n");
    }
}

/// Generate global statement
/// The global statement itself doesn't emit code - it just marks variables as global
/// so that subsequent assignments reference the outer scope variable instead of creating a new one
pub fn genGlobal(self: *NativeCodegen, global_node: ast.Node.GlobalStmt) CodegenError!void {
    // Mark each variable as global
    for (global_node.names) |name| {
        try self.markGlobalVar(name);
    }
    // No code emitted - this is a directive, not an executable statement
}

/// Generate del statement
/// In Python, del is mostly a memory hint. In AOT compilation, emit as comment.
pub fn genDel(self: *NativeCodegen, del_node: ast.Node.Del) CodegenError!void {
    _ = del_node; // del is a no-op in compiled code
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "// del statement (no-op in AOT)\n");
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
        try self.output.appendSlice(self.allocator, "std.debug.panic(\"AssertionError: {s}\", .{");
        try self.genExpr(msg.*);
        try self.output.appendSlice(self.allocator, "});\n");
    } else {
        // assert x
        try self.output.appendSlice(self.allocator, "std.debug.panic(\"AssertionError\", .{});\n");
    }

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
}

/// Generate raise statement
/// raise ValueError("msg") => std.debug.panic("ValueError: {s}", .{"msg"})
/// raise => std.debug.panic("Unhandled exception", .{})
pub fn genRaise(self: *NativeCodegen, raise_node: ast.Node.Raise) CodegenError!void {
    try self.emitIndent();

    if (raise_node.exc) |exc| {
        // raise Exception("msg")
        // For now, just panic with the exception type
        try self.output.appendSlice(self.allocator, "std.debug.panic(\"Exception: {any}\", .{");
        try self.genExpr(exc.*);
        try self.output.appendSlice(self.allocator, "});\n");
    } else {
        // bare raise
        try self.output.appendSlice(self.allocator, "std.debug.panic(\"Unhandled exception\", .{});\n");
    }
}

