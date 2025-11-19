/// Control flow statement code generation (if, while, for, range, enumerate, zip)
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const CodeBuilder = @import("../code_builder.zig").CodeBuilder;

/// Generate if statement
pub fn genIf(self: *NativeCodegen, if_stmt: ast.Node.If) CodegenError!void {
    var builder = CodeBuilder.init(self);

    try self.emitIndent();
    _ = try builder.write("if (");
    try self.genExpr(if_stmt.condition.*);
    _ = try builder.write(")");
    _ = try builder.beginBlock();

    for (if_stmt.body) |stmt| {
        try self.generateStmt(stmt);
    }

    if (if_stmt.else_body.len > 0) {
        _ = try builder.elseClause();
        _ = try builder.beginBlock();
        for (if_stmt.else_body) |stmt| {
            try self.generateStmt(stmt);
        }
        _ = try builder.endBlock();
    } else {
        _ = try builder.endBlock();
    }
}

/// Generate while loop
pub fn genWhile(self: *NativeCodegen, while_stmt: ast.Node.While) CodegenError!void {
    var builder = CodeBuilder.init(self);

    try self.emitIndent();
    _ = try builder.write("while (");
    try self.genExpr(while_stmt.condition.*);
    _ = try builder.write(")");
    _ = try builder.beginBlock();

    // Push new scope for loop body
    try self.pushScope();

    for (while_stmt.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting loop
    self.popScope();

    _ = try builder.endBlock();
}

/// Generate tuple unpacking loop
/// Transforms: for x, y in iterable_of_tuples into:
/// for (iterable.items) |__tuple__| {
///     const x = __tuple__[0];
///     const y = __tuple__[1];
///     // body
/// }
fn genTupleUnpackLoop(self: *NativeCodegen, target: ast.Node, iter: ast.Node, body: []ast.Node) CodegenError!void {
    // Validate target is a list (parser uses list node for tuple unpacking)
    if (target != .list) {
        @panic("Tuple unpacking requires list target");
    }
    const target_elts = target.list.elts;
    if (target_elts.len == 0) {
        @panic("Tuple unpacking requires at least one variable");
    }

    // Extract variable names
    var var_names = try self.allocator.alloc([]const u8, target_elts.len);
    defer self.allocator.free(var_names);
    for (target_elts, 0..) |elt, i| {
        if (elt != .name) {
            @panic("Tuple unpacking target must be names");
        }
        var_names[i] = elt.name.id;
    }

    // Generate for loop over iterable
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "for (");

    // Check if we need to add .items for ArrayList
    const iter_type = try self.type_inferrer.inferExpr(iter);

    // Check if this is a method call like dict.items()
    const is_method_call = iter == .call and iter.call.func.* == .attribute;

    // If iterating over list (including method calls that return lists), add .items
    if (iter_type == .list) {
        if (is_method_call) {
            // Method call returns ArrayList - wrap in parens for .items
            try self.output.appendSlice(self.allocator, "(");
            try self.genExpr(iter);
            try self.output.appendSlice(self.allocator, ").items");
        } else if (iter == .list) {
            // Inline list literal
            try self.output.appendSlice(self.allocator, "(");
            try self.genExpr(iter);
            try self.output.appendSlice(self.allocator, ").items");
        } else {
            // Variable that holds ArrayList
            try self.genExpr(iter);
            try self.output.appendSlice(self.allocator, ".items");
        }
    } else {
        // Not a list type - iterate directly
        try self.genExpr(iter);
    }

    // Use unique temp variable for tuple
    const unique_id = self.output.items.len;
    try self.output.writer(self.allocator).print(") |__tuple_{d}__| {{\n", .{unique_id});

    self.indent();
    try self.pushScope();

    // Unpack tuple elements: const x = __tuple__[0]; const y = __tuple__[1];
    for (var_names, 0..) |var_name, i| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const {s} = __tuple_{d}__[{d}];\n", .{ var_name, unique_id, i });
    }

    // Generate body statements
    for (body) |stmt| {
        try self.generateStmt(stmt);
    }

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

    // Check if target is tuple unpacking (e.g., for k, v in dict.items())
    if (for_stmt.target.* == .list) {
        try genTupleUnpackLoop(self, for_stmt.target.*, for_stmt.iter.*, for_stmt.body);
        return;
    }

    // Regular iteration over collection - requires single target variable
    const var_name = for_stmt.target.name.id;

    // Check iter type first (needed for tuple special case)
    const iter_type = try self.type_inferrer.inferExpr(for_stmt.iter.*);

    // Special case: tuple iteration requires inline for (comptime)
    if (iter_type == .tuple) {
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "inline for (");
        try self.genExpr(for_stmt.iter.*);
        try self.output.appendSlice(self.allocator, ") |");
        try self.output.appendSlice(self.allocator, var_name);
        try self.output.appendSlice(self.allocator, "| {\n");

        self.indent();
        try self.pushScope();

        for (for_stmt.body) |stmt| {
            try self.generateStmt(stmt);
        }

        self.popScope();
        self.dedent();

        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
        return;
    }

    // Regular iteration over collection
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "for (");

    // Check if this is a constant list (will be compiled to array, not ArrayList)
    const is_constant_array = blk: {
        if (for_stmt.iter.* == .list) {
            const list = for_stmt.iter.list;
            // Check if it's a constant homogeneous list (becomes array)
            if (list.elts.len > 0) {
                var all_constants = true;
                for (list.elts) |elem| {
                    if (elem != .constant) {
                        all_constants = false;
                        break;
                    }
                }
                if (all_constants) {
                    // Check if all same type
                    const first_type = @as(std.meta.Tag(@TypeOf(list.elts[0].constant.value)), list.elts[0].constant.value);
                    var all_same = true;
                    for (list.elts[1..]) |elem| {
                        const elem_type = @as(std.meta.Tag(@TypeOf(elem.constant.value)), elem.constant.value);
                        if (elem_type != first_type) {
                            all_same = false;
                            break;
                        }
                    }
                    break :blk all_same;
                }
            }
        }
        break :blk false;
    };

    // Check if we're iterating over a variable that holds a constant array
    const is_array_var = blk: {
        if (for_stmt.iter.* == .name) {
            const iter_var_name = for_stmt.iter.name.id;
            break :blk self.isArrayVar(iter_var_name);
        }
        break :blk false;
    };

    // If iterating over constant array literal or array variable, no .items needed
    // If iterating over ArrayList (variable or inline), add .items
    if (is_constant_array or is_array_var) {
        // Constant array or array variable - iterate directly
        try self.genExpr(for_stmt.iter.*);
    } else if (iter_type == .list and for_stmt.iter.* == .list) {
        // Inline ArrayList literal - wrap in parens for .items access
        try self.output.appendSlice(self.allocator, "(");
        try self.genExpr(for_stmt.iter.*);
        try self.output.appendSlice(self.allocator, ").items");
    } else if (iter_type == .list and for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .attribute) {
        // Method call that returns ArrayList - wrap in parens for .items access
        try self.output.appendSlice(self.allocator, "(");
        try self.genExpr(for_stmt.iter.*);
        try self.output.appendSlice(self.allocator, ").items");
    } else {
        try self.genExpr(for_stmt.iter.*);
        if (iter_type == .list) {
            try self.output.appendSlice(self.allocator, ".items");
        }
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

    // Wrap range loop in block scope to prevent variable shadowing
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "{\n");
    self.indent();

    // Generate initialization (always declare as new variable in block scope)
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var ");
    try self.output.appendSlice(self.allocator, var_name);
    try self.output.appendSlice(self.allocator, ": usize = ");
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

    // Close block scope
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

    // Generate index counter: var __enum_idx_N: usize = start;
    // Use output buffer length as unique ID to avoid shadowing in nested loops
    const unique_id = self.output.items.len;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var __enum_idx_{d}: usize = ", .{unique_id});
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

    // Check if we need to add .items for ArrayList
    const iter_type = try self.type_inferrer.inferExpr(iterable);

    // If iterating over list literal, wrap in parens for .items access
    if (iter_type == .list and iterable == .list) {
        try self.output.appendSlice(self.allocator, "(");
        try self.genExpr(iterable);
        try self.output.appendSlice(self.allocator, ").items");
    } else {
        try self.genExpr(iterable);
        if (iter_type == .list) {
            try self.output.appendSlice(self.allocator, ".items");
        }
    }

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

    // Check type of each iterable to determine if we need .items
    var iter_is_list = try self.allocator.alloc(bool, args.len);
    defer self.allocator.free(iter_is_list);

    for (args, 0..) |iterable, i| {
        const iter_type = try self.type_inferrer.inferExpr(iterable);
        iter_is_list[i] = (iter_type == .list);
    }

    // Store each iterable in a temporary variable: const __zip_iter_N = ...
    for (args, 0..) |iterable, i| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __zip_iter_{d} = ", .{i});
        try self.genExpr(iterable);
        try self.output.appendSlice(self.allocator, ";\n");
    }

    // Generate: var __zip_idx: usize = 0;
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var __zip_idx: usize = 0;\n");

    // Generate: const __zip_len = @min(iter0.len, @min(iter1.len, ...));
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const __zip_len = ");

    // Build nested @min calls - use .items.len for lists, .len for arrays
    if (args.len == 2) {
        try self.output.appendSlice(self.allocator, "@min(__zip_iter_0");
        if (iter_is_list[0]) try self.output.appendSlice(self.allocator, ".items");
        try self.output.appendSlice(self.allocator, ".len, __zip_iter_1");
        if (iter_is_list[1]) try self.output.appendSlice(self.allocator, ".items");
        try self.output.appendSlice(self.allocator, ".len)");
    } else {
        // For 3+ iterables: @min(iter0.len, @min(iter1.len, @min(iter2.len, ...)))
        try self.output.appendSlice(self.allocator, "@min(__zip_iter_0");
        if (iter_is_list[0]) try self.output.appendSlice(self.allocator, ".items");
        try self.output.appendSlice(self.allocator, ".len, ");
        for (1..args.len - 1) |_| {
            try self.output.appendSlice(self.allocator, "@min(");
        }
        for (1..args.len) |i| {
            try self.output.writer(self.allocator).print("__zip_iter_{d}", .{i});
            if (iter_is_list[i]) try self.output.appendSlice(self.allocator, ".items");
            try self.output.appendSlice(self.allocator, ".len");
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
    // Use .items for lists, direct indexing for arrays
    for (target.list.elts, 0..) |elt, i| {
        const var_name = elt.name.id;
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "const ");
        try self.output.appendSlice(self.allocator, var_name);
        try self.output.writer(self.allocator).print(" = __zip_iter_{d}", .{i});
        if (iter_is_list[i]) try self.output.appendSlice(self.allocator, ".items");
        try self.output.appendSlice(self.allocator, "[__zip_idx];\n");
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

/// Generate pass statement (no-op)
pub fn genPass(self: *NativeCodegen) CodegenError!void {
    var builder = CodeBuilder.init(self);
    _ = try builder.line("// pass");
}

/// Generate break statement
pub fn genBreak(self: *NativeCodegen) CodegenError!void {
    var builder = CodeBuilder.init(self);
    _ = try builder.line("break;");
}

/// Generate continue statement
pub fn genContinue(self: *NativeCodegen) CodegenError!void {
    var builder = CodeBuilder.init(self);
    _ = try builder.line("continue;");
}
