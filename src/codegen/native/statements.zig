/// Statement-level code generation
/// Handles Python statements: assignments, if/while/for loops, functions, returns, print
const std = @import("std");
const ast = @import("../../ast.zig");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

/// Generate function definition
pub fn genFunctionDef(self: *NativeCodegen, func: ast.Node.FunctionDef) CodegenError!void {
    // Generate function signature: fn name(param: type, ...) return_type {
    try self.emit("fn ");
    try self.emit(func.name);
    try self.emit("(");

    // Generate parameters
    for (func.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try self.emit(arg.name);
        try self.emit(": ");
        // Convert Python type hint to Zig type
        const zig_type = pythonTypeToZig(arg.type_annotation);
        try self.emit(zig_type);
    }

    try self.emit(") ");

    // Return type - for now assume i64 if not void
    // TODO: Proper return type inference
    try self.emit("i64 {\n");

    self.indent();

    // Push new scope for function body
    try self.pushScope();

    // Generate function body
    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting function
    self.popScope();

    self.dedent();
    try self.emit("}\n");
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

/// Convert Python type hint to Zig type
fn pythonTypeToZig(type_hint: ?[]const u8) []const u8 {
    if (type_hint) |hint| {
        if (std.mem.eql(u8, hint, "int")) return "i64";
        if (std.mem.eql(u8, hint, "float")) return "f64";
        if (std.mem.eql(u8, hint, "bool")) return "bool";
        if (std.mem.eql(u8, hint, "str")) return "[]const u8";
    }
    return "anytype"; // fallback
}

/// Generate assignment statement with automatic defer cleanup
pub fn genAssign(self: *NativeCodegen, assign: ast.Node.Assign) CodegenError!void {
    const value_type = try self.type_inferrer.inferExpr(assign.value.*);

    for (assign.targets) |target| {
        if (target == .name) {
            const var_name = target.name.id;

            // ArrayLists and dicts need var instead of const for mutation
            const is_arraylist = (assign.value.* == .list and assign.value.list.elts.len == 0);
            const is_dict = (assign.value.* == .dict);

            // Check if value allocates memory
            const is_allocated_string = blk: {
                if (assign.value.* == .call) {
                    // Method calls that allocate: upper(), lower(), replace()
                    if (assign.value.call.func.* == .attribute) {
                        const method_name = assign.value.call.func.attribute.attr;
                        if (std.mem.eql(u8, method_name, "upper") or
                            std.mem.eql(u8, method_name, "lower") or
                            std.mem.eql(u8, method_name, "replace"))
                        {
                            break :blk true;
                        }
                    }
                    // Built-in functions that allocate: sorted(), reversed()
                    if (assign.value.call.func.* == .name) {
                        const func_name = assign.value.call.func.name.id;
                        if (std.mem.eql(u8, func_name, "sorted") or
                            std.mem.eql(u8, func_name, "reversed"))
                        {
                            break :blk true;
                        }
                    }
                }
                break :blk false;
            };

            // Check if this is first assignment or reassignment
            const is_first_assignment = !self.isDeclared(var_name);

            try self.emitIndent();
            if (is_first_assignment) {
                // First assignment: decide between const and var
                // Use var for:
                // - Mutable collections (ArrayLists, dicts)
                // - Simple literals that are likely accumulators (0, 1, true, false)
                // Use const for:
                // - Function call results
                // - Complex expressions
                // - Strings and arrays
                const is_simple_literal = switch (assign.value.*) {
                    .constant => true,
                    .binop => false, // Expressions like (a + b)
                    .call => false,   // Function calls
                    else => false,
                };
                const needs_var = is_arraylist or is_dict or
                                 (is_simple_literal and (value_type == .int or value_type == .float or value_type == .bool));

                if (needs_var) {
                    try self.output.appendSlice(self.allocator, "var ");
                } else {
                    try self.output.appendSlice(self.allocator, "const ");
                }
                try self.output.appendSlice(self.allocator, var_name);

                // Only emit type annotation for known types that aren't dicts, lists, or ArrayLists
                // For lists/ArrayLists/dicts, let Zig infer the type from the initializer
                // For unknown types (json.loads, etc.), let Zig infer
                const is_list = (value_type == .list);
                if (value_type != .unknown and !is_dict and !is_arraylist and !is_list) {
                    try self.output.appendSlice(self.allocator, ": ");
                    try value_type.toZigType(self.allocator, &self.output);
                }

                try self.output.appendSlice(self.allocator, " = ");

                // Mark as declared
                try self.declareVar(var_name);
            } else {
                // Reassignment: x = value (no var/const keyword!)
                try self.output.appendSlice(self.allocator, var_name);
                try self.output.appendSlice(self.allocator, " = ");
                // No type annotation on reassignment
            }

            // Emit value
            try self.genExpr(assign.value.*);

            try self.output.appendSlice(self.allocator, ";\n");

            // Add defer cleanup for ArrayLists and Dicts (only on first assignment)
            if (is_first_assignment and is_arraylist) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("defer {s}.deinit(allocator);\n", .{var_name});
            }
            if (is_first_assignment and is_dict) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("defer {s}.deinit();\n", .{var_name});
            }
            // Add defer cleanup for allocated strings (upper/lower/replace/sorted/reversed - only on first assignment)
            if (is_first_assignment and is_allocated_string) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("defer allocator.free({s});\n", .{var_name});
            }
        }
    }
}

/// Generate expression statement (expression with semicolon)
pub fn genExprStmt(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    try self.emitIndent();

    // Special handling for print()
    if (expr == .call and expr.call.func.* == .name) {
        const func_name = expr.call.func.name.id;
        if (std.mem.eql(u8, func_name, "print")) {
            try genPrint(self, expr.call.args);
            return;
        }
    }

    try self.genExpr(expr);
    try self.output.appendSlice(self.allocator, ";\n");
}

/// Generate print() function call
pub fn genPrint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.output.appendSlice(self.allocator, "std.debug.print(\"\\n\", .{});\n");
        return;
    }

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

/// Generate if statement
pub fn genIf(self: *NativeCodegen, if_stmt: ast.Node.If) CodegenError!void {
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "if (");
    try self.genExpr(if_stmt.condition.*);
    try self.output.appendSlice(self.allocator, ") {\n");

    self.indent();
    for (if_stmt.body) |stmt| {
        try self.generateStmt(stmt);
    }
    self.dedent();

    if (if_stmt.else_body.len > 0) {
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "} else {\n");
        self.indent();
        for (if_stmt.else_body) |stmt| {
            try self.generateStmt(stmt);
        }
        self.dedent();
    }

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
}

/// Generate while loop
pub fn genWhile(self: *NativeCodegen, while_stmt: ast.Node.While) CodegenError!void {
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "while (");
    try self.genExpr(while_stmt.condition.*);
    try self.output.appendSlice(self.allocator, ") {\n");

    self.indent();

    // Push new scope for loop body
    try self.pushScope();

    for (while_stmt.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting loop
    self.popScope();

    self.dedent();

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
}

/// Generate for loop
pub fn genFor(self: *NativeCodegen, for_stmt: ast.Node.For) CodegenError!void {
    // Check if iterating over a function call (range, enumerate, etc.)
    if (for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .name) {
        const func_name = for_stmt.iter.call.func.name.id;

        // Handle range() loops
        if (std.mem.eql(u8, func_name, "range")) {
            // range() requires single target variable
            const var_name = for_stmt.target.name.id;
            try genRangeLoop(self, var_name, for_stmt.iter.call.args, for_stmt.body);
            return;
        }

        // Handle enumerate() loops
        if (std.mem.eql(u8, func_name, "enumerate")) {
            // enumerate() requires tuple target (idx, item)
            try genEnumerateLoop(self, for_stmt.target.*, for_stmt.iter.call.args, for_stmt.body);
            return;
        }

        // Handle zip() loops
        if (std.mem.eql(u8, func_name, "zip")) {
            try genZipLoop(self, for_stmt.target.*, for_stmt.iter.call.args, for_stmt.body);
            return;
        }
    }

    // Regular iteration over collection - requires single target variable
    const var_name = for_stmt.target.name.id;

    // Regular iteration over collection
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "for (");
    try self.genExpr(for_stmt.iter.*);

    // Add .items if it's an ArrayList
    const iter_type = try self.type_inferrer.inferExpr(for_stmt.iter.*);
    if (iter_type == .list) {
        try self.output.appendSlice(self.allocator, ".items");
    }

    try self.output.appendSlice(self.allocator, ") |");
    try self.output.appendSlice(self.allocator, var_name);
    try self.output.appendSlice(self.allocator, "| {\n");

    self.indent();

    // Push new scope for loop body
    try self.pushScope();

    for (for_stmt.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting loop
    self.popScope();

    self.dedent();

    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
}

/// Generate range() loop as Zig while loop
fn genRangeLoop(self: *NativeCodegen, var_name: []const u8, args: []ast.Node, body: []ast.Node) CodegenError!void {
    // range(stop) or range(start, stop) or range(start, stop, step)
    var start_expr: ?ast.Node = null;
    var stop_expr: ast.Node = undefined;
    var step_expr: ?ast.Node = null;

    if (args.len == 1) {
        stop_expr = args[0];
    } else if (args.len == 2) {
        start_expr = args[0];
        stop_expr = args[1];
    } else if (args.len == 3) {
        start_expr = args[0];
        stop_expr = args[1];
        step_expr = args[2];
    } else {
        return; // Invalid range() call
    }

    // Generate initialization (check if already declared)
    const is_first_assignment = !self.isDeclared(var_name);

    try self.emitIndent();
    if (is_first_assignment) {
        try self.output.appendSlice(self.allocator, "var ");
        try self.output.appendSlice(self.allocator, var_name);
        try self.output.appendSlice(self.allocator, ": i64 = ");
        // Mark as declared
        try self.declareVar(var_name);
    } else {
        try self.output.appendSlice(self.allocator, var_name);
        try self.output.appendSlice(self.allocator, " = ");
    }
    if (start_expr) |start| {
        try self.genExpr(start);
    } else {
        try self.output.appendSlice(self.allocator, "0");
    }
    try self.output.appendSlice(self.allocator, ";\n");

    // Generate while loop
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "while (");
    try self.output.appendSlice(self.allocator, var_name);
    try self.output.appendSlice(self.allocator, " < ");
    try self.genExpr(stop_expr);
    try self.output.appendSlice(self.allocator, ") {\n");

    self.indent();

    // Push new scope for loop body
    try self.pushScope();

    for (body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Increment
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, var_name);
    try self.output.appendSlice(self.allocator, " += ");
    if (step_expr) |step| {
        try self.genExpr(step);
    } else {
        try self.output.appendSlice(self.allocator, "1");
    }
    try self.output.appendSlice(self.allocator, ";\n");

    // Pop scope when exiting loop
    self.popScope();

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
}

/// Generate enumerate() loop
/// Transforms: for i, item in enumerate(items, start=0) into:
/// {
///     var __enum_idx: i64 = start;
///     for (items) |item| {
///         const i = __enum_idx;
///         __enum_idx += 1;
///         // body
///     }
/// }
fn genEnumerateLoop(self: *NativeCodegen, target: ast.Node, args: []ast.Node, body: []ast.Node) CodegenError!void {
    // Validate target is a list (parser uses list node for tuple unpacking) with exactly 2 elements (idx, item)
    if (target != .list) {
        @panic("enumerate() requires tuple unpacking: for i, item in enumerate(...)");
    }
    const target_elts = target.list.elts;
    if (target_elts.len != 2) {
        @panic("enumerate() requires exactly 2 variables: for i, item in enumerate(...)");
    }

    // Extract variable names
    const idx_var = target_elts[0].name.id;
    const item_var = target_elts[1].name.id;

    // Extract iterable (first argument to enumerate)
    if (args.len == 0) {
        @panic("enumerate() requires at least 1 argument");
    }
    const iterable = args[0];

    // Extract start parameter (default 0)
    var start_value: i64 = 0;
    if (args.len >= 2) {
        // Check if it's a keyword argument "start=N"
        // For now, assume positional: enumerate(items, start)
        // TODO: Handle keyword args properly
        if (args[1] == .constant and args[1].constant.value == .int) {
            start_value = args[1].constant.value.int;
        }
    }

    // Generate block scope
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "{\n");
    self.indent();

    // Generate index counter: var __enum_idx_N: i64 = start;
    // Use output buffer length as unique ID to avoid shadowing in nested loops
    const unique_id = self.output.items.len;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var __enum_idx_{d}: i64 = ", .{unique_id});
    if (start_value != 0) {
        const start_str = try std.fmt.allocPrint(self.allocator, "{d}", .{start_value});
        try self.output.appendSlice(self.allocator, start_str);
    } else {
        try self.output.appendSlice(self.allocator, "0");
    }
    try self.output.appendSlice(self.allocator, ";\n");

    // Generate for loop over iterable
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "for (");
    try self.genExpr(iterable);

    // NOTE: Don't add .items for enumerate loops
    // In PyAOT, list variables are typically slices (from literals), not ArrayLists
    // The caller (enumerate) handles the iterable directly
    // If we need ArrayList support in the future, check the AST structure properly

    try self.output.appendSlice(self.allocator, ") |");
    try self.output.appendSlice(self.allocator, item_var);
    try self.output.appendSlice(self.allocator, "| {\n");

    self.indent();

    // Push new scope for loop body
    try self.pushScope();

    // Generate: const idx = __enum_idx_N;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = __enum_idx_{d};\n", .{ idx_var, unique_id });

    // Generate: __enum_idx_N += 1;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("__enum_idx_{d} += 1;\n", .{unique_id});

    // Generate body statements
    for (body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting loop
    self.popScope();

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");

    // Close block scope
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
}

/// Generate zip() loop
/// Transforms: for x, y in zip(list1, list2) into:
/// {
///     const __zip_iter_0 = list1.items;
///     const __zip_iter_1 = list2.items;
///     var __zip_idx: usize = 0;
///     const __zip_len = @min(__zip_iter_0.len, __zip_iter_1.len);
///     while (__zip_idx < __zip_len) : (__zip_idx += 1) {
///         const x = __zip_iter_0[__zip_idx];
///         const y = __zip_iter_1[__zip_idx];
///         // body
///     }
/// }
fn genZipLoop(self: *NativeCodegen, target: ast.Node, args: []ast.Node, body: []ast.Node) CodegenError!void {
    // Validate target is a list (parser uses list node for tuple unpacking in for-loops)
    if (target != .list) {
        @panic("zip() requires tuple unpacking: for x, y in zip(...)");
    }

    const num_vars = target.list.elts.len;

    // Verify number of variables matches number of iterables
    if (num_vars != args.len) {
        @panic("zip() variable count must match number of iterables");
    }

    // zip() requires at least 2 iterables
    if (args.len < 2) {
        @panic("zip() requires at least 2 iterables");
    }

    // Open block for scoping
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "{\n");
    self.indent();

    // Store each iterable in a temporary variable: const __zip_iter_N = ...
    for (args, 0..) |iterable, i| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __zip_iter_{d} = ", .{i});
        try self.genExpr(iterable);

        // NOTE: Don't add .items for zip loops
        // In PyAOT, list variables are typically slices (from literals or params), not ArrayLists
        // zip() works directly with slices
        try self.output.appendSlice(self.allocator, ";\n");
    }

    // Generate: var __zip_idx: usize = 0;
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var __zip_idx: usize = 0;\n");

    // Generate: const __zip_len = @min(iter0.len, @min(iter1.len, ...));
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const __zip_len = ");

    // Build nested @min calls
    if (args.len == 2) {
        try self.output.appendSlice(self.allocator, "@min(__zip_iter_0.len, __zip_iter_1.len)");
    } else {
        // For 3+ iterables: @min(iter0.len, @min(iter1.len, @min(iter2.len, ...)))
        try self.output.appendSlice(self.allocator, "@min(__zip_iter_0.len, ");
        for (1..args.len - 1) |_| {
            try self.output.appendSlice(self.allocator, "@min(");
        }
        for (1..args.len) |i| {
            try self.output.writer(self.allocator).print("__zip_iter_{d}.len", .{i});
            if (i < args.len - 1) {
                try self.output.appendSlice(self.allocator, ", ");
            }
        }
        for (1..args.len - 1) |_| {
            try self.output.appendSlice(self.allocator, ")");
        }
        try self.output.appendSlice(self.allocator, ")");
    }
    try self.output.appendSlice(self.allocator, ";\n");

    // Generate: while (__zip_idx < __zip_len) : (__zip_idx += 1) {
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "while (__zip_idx < __zip_len) : (__zip_idx += 1) {\n");
    self.indent();

    // Push new scope for loop body
    try self.pushScope();

    // Generate: const var1 = __zip_iter_0[__zip_idx]; const var2 = __zip_iter_1[__zip_idx]; ...
    for (target.list.elts, 0..) |elt, i| {
        const var_name = elt.name.id;
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "const ");
        try self.output.appendSlice(self.allocator, var_name);
        try self.output.writer(self.allocator).print(" = __zip_iter_{d}[__zip_idx];\n", .{i});
    }

    // Generate body statements
    for (body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting loop
    self.popScope();

    // Close while loop
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");

    // Close block scope
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
}
