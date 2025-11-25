/// Print statement code generation (starred, concat, lists, dicts, tuples, bools, None, PyObject)
const std = @import("std");
const ast = @import("../../../ast.zig");
const main = @import("../main.zig");
const NativeCodegen = main.NativeCodegen;
const CodegenError = main.CodegenError;

/// Flatten nested string concat: (s1 + " ") + s2 => [s1, " ", s2]
fn flattenConcat(self: *NativeCodegen, node: ast.Node, parts: *std.ArrayList(ast.Node)) CodegenError!void {
    if (node == .binop and node.binop.op == .Add) {
        const left_type = try self.type_inferrer.inferExpr(node.binop.left.*);
        const right_type = try self.type_inferrer.inferExpr(node.binop.right.*);
        if (left_type == .string or right_type == .string) {
            try flattenConcat(self, node.binop.left.*, parts);
            try flattenConcat(self, node.binop.right.*, parts);
            return;
        }
    }
    try parts.append(self.allocator, node);
}

/// Check if expression is an array slice (subscript slice of constant array var)
fn isArraySlice(self: *NativeCodegen, node: ast.Node) bool {
    if (node != .subscript) return false;
    if (node.subscript.slice != .slice) return false;
    const value_node = node.subscript.value.*;
    return if (value_node == .name) self.isArrayVar(value_node.name.id) else false;
}

/// Check if node is an allocating method call (e.g., "text".upper())
fn isAllocatingMethodCall(self: *NativeCodegen, node: ast.Node) bool {
    if (node != .call) return false;
    if (node.call.func.* != .attribute) return false;
    const attr = node.call.func.attribute;
    const obj_type = self.type_inferrer.inferExpr(attr.value.*) catch return false;
    if (obj_type != .string) return false;
    const allocating_methods = [_][]const u8{ "upper", "lower", "strip", "lstrip", "rstrip", "replace", "capitalize", "title", "swapcase" };
    for (allocating_methods) |method| {
        if (std.mem.eql(u8, attr.attr, method)) return true;
    }
    return false;
}

/// Generate print() function call
pub fn genPrint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.output.appendSlice(self.allocator, "std.debug.print(\"\\n\", .{});\n");
        return;
    }

    // Check if any arg is a starred expression (print(*x))
    var has_starred = false;
    for (args) |arg| {
        if (arg == .starred) {
            has_starred = true;
            break;
        }
    }

    // Handle starred expressions: print(*x) -> iterate and print each element
    if (has_starred) {
        try self.output.appendSlice(self.allocator, "{\n");
        try self.output.appendSlice(self.allocator, "    var __print_first = true;\n");

        for (args) |arg| {
            if (arg == .starred) {
                // Unpack starred argument
                const starred_value = arg.starred.value.*;
                const value_type = try self.type_inferrer.inferExpr(starred_value);

                try self.output.appendSlice(self.allocator, "    const __starred = ");
                try self.genExpr(starred_value);
                try self.output.appendSlice(self.allocator, ";\n");

                // Determine if we need .items or direct iteration
                const needs_items = if (starred_value == .name)
                    self.arraylist_vars.contains(starred_value.name.id)
                else
                    value_type == .list;

                if (needs_items) {
                    try self.output.appendSlice(self.allocator, "    for (__starred.items) |__elem| {\n");
                } else {
                    try self.output.appendSlice(self.allocator, "    for (__starred) |__elem| {\n");
                }
                try self.output.appendSlice(self.allocator, "        if (!__print_first) std.debug.print(\" \", .{});\n");
                try self.output.appendSlice(self.allocator, "        __print_first = false;\n");
                try self.output.appendSlice(self.allocator, "        std.debug.print(\"{d}\", .{__elem});\n");
                try self.output.appendSlice(self.allocator, "    }\n");
            } else {
                // Regular argument
                try self.output.appendSlice(self.allocator, "    if (!__print_first) std.debug.print(\" \", .{});\n");
                try self.output.appendSlice(self.allocator, "    __print_first = false;\n");

                const arg_type = try self.type_inferrer.inferExpr(arg);
                // Note: bool uses {s} because we wrap with "True"/"False" string
                const fmt = if (arg_type == .bool) "{s}" else arg_type.getPrintFormat();

                if (arg_type == .bool) {
                    try self.output.appendSlice(self.allocator, "    std.debug.print(\"{s}\", .{if (");
                    try self.genExpr(arg);
                    try self.output.appendSlice(self.allocator, ") \"True\" else \"False\"});\n");
                } else {
                    try self.output.appendSlice(self.allocator, "    std.debug.print(\"");
                    try self.output.appendSlice(self.allocator, fmt);
                    try self.output.appendSlice(self.allocator, "\", .{");
                    try self.genExpr(arg);
                    try self.output.appendSlice(self.allocator, "});\n");
                }
            }
        }

        try self.output.appendSlice(self.allocator, "    std.debug.print(\"\\n\", .{});\n");
        try self.output.appendSlice(self.allocator, "}\n");
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
        try genPrintComplex(self, args);
        return;
    }

    // If we have string concatenation or allocating calls, wrap in block with temp vars
    // Note: floats are now printed directly with {d} format
    if (has_string_concat or has_allocating_call) {
        try genPrintWithTempVars(self, args);
    } else {
        // No string concatenation - simple print
        try genPrintSimple(self, args);
    }
}

/// Generate print for complex types (lists, dicts, tuples, bools, none, unknown)
fn genPrintComplex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // For lists and arrays, we need to print in Python format: [elem1, elem2, ...]
    for (args, 0..) |arg, i| {
        const arg_type = try self.type_inferrer.inferExpr(arg);
        if (arg_type == .list or arg_type == .array) {
            try genPrintList(self, arg, arg_type);
        } else if (arg_type == .tuple) {
            try genPrintTuple(self, arg, arg_type);
        } else if (arg_type == .dict) {
            try genPrintDict(self, arg);
        } else if (arg_type == .unknown) {
            // Unknown types are typically *PyObject from eval() or dynamic calls
            // Use runtime.printPyObject for proper formatting
            try self.output.appendSlice(self.allocator, "runtime.printPyObject(");
            try self.genExpr(arg);
            try self.output.appendSlice(self.allocator, ");\n");
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
            // Note: unknown types try {s} (works for string constants)
            const fmt = if (arg_type == .unknown) "{s}" else arg_type.getPrintFormat();
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
}

/// Generate print for list/array types
fn genPrintList(self: *NativeCodegen, arg: ast.Node, arg_type: anytype) CodegenError!void {
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
}

/// Generate print for tuple types
fn genPrintTuple(self: *NativeCodegen, arg: ast.Node, arg_type: anytype) CodegenError!void {
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
            // Note: bool uses {s} because we wrap with "True"/"False" string
            const fmt = if (elem_type == .bool) "{s}" else elem_type.getPrintFormat();
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
}

/// Generate print for dict types
fn genPrintDict(self: *NativeCodegen, arg: ast.Node) CodegenError!void {
    // Format native dict (HashMap) in Python format: {'key': value, ...}
    // Use comptime to detect key type and format appropriately
    try self.output.appendSlice(self.allocator, "{\n");
    try self.output.appendSlice(self.allocator, "    const __dict = ");
    try self.genExpr(arg);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    var __dict_iter = __dict.iterator();\n");
    try self.output.appendSlice(self.allocator, "    var __dict_idx: usize = 0;\n");
    try self.output.appendSlice(self.allocator, "    std.debug.print(\"{{\", .{});\n");
    try self.output.appendSlice(self.allocator, "    while (__dict_iter.next()) |__entry| {\n");
    try self.output.appendSlice(self.allocator, "        if (__dict_idx > 0) std.debug.print(\", \", .{});\n");
    // Use comptime to detect key type: string keys get 'quotes', int keys don't
    try self.output.appendSlice(self.allocator, "        const __key = __entry.key_ptr.*;\n");
    try self.output.appendSlice(self.allocator, "        if (comptime @typeInfo(@TypeOf(__key)) == .pointer) {\n");
    try self.output.appendSlice(self.allocator, "            std.debug.print(\"'{s}': \", .{__key});\n");
    try self.output.appendSlice(self.allocator, "        } else {\n");
    try self.output.appendSlice(self.allocator, "            std.debug.print(\"{d}: \", .{__key});\n");
    try self.output.appendSlice(self.allocator, "        }\n");
    try self.output.appendSlice(self.allocator, "        runtime.printValue(__entry.value_ptr.*);\n");
    try self.output.appendSlice(self.allocator, "        __dict_idx += 1;\n");
    try self.output.appendSlice(self.allocator, "    }\n");
    try self.output.appendSlice(self.allocator, "    std.debug.print(\"}}\", .{});\n");
    try self.output.appendSlice(self.allocator, "}\n");
}

/// Generate print with temp vars for string concatenation or allocating calls
fn genPrintWithTempVars(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
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
                for (parts.items, 0..) |part, j| {
                    if (j > 0) try self.output.appendSlice(self.allocator, ", ");
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
        try self.output.appendSlice(self.allocator, arg_type.getPrintFormat());

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
}

/// Generate simple print (no string concatenation or complex types)
fn genPrintSimple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "std.debug.print(\"");

    // Generate format string
    for (args, 0..) |arg, i| {
        const arg_type = try self.type_inferrer.inferExpr(arg);
        // Note: bool uses {s} because formatAny() returns string
        // Note: unknown uses {s} - works for string constants
        const fmt = if (arg_type == .bool or arg_type == .unknown) "{s}" else arg_type.getPrintFormat();
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
