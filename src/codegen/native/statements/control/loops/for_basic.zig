/// For loop code generation (basic, range, tuple unpacking)
const std = @import("std");
const ast = @import("../../../../../ast.zig");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const for_special = @import("for_special.zig");
const genEnumerateLoop = for_special.genEnumerateLoop;
const genZipLoop = for_special.genZipLoop;

/// Sanitize Python variable name for Zig (e.g., "_" -> "_unused")
fn sanitizeVarName(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "_")) return "_unused";
    return name;
}

/// Generate while loop
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
    try self.emit("for (");

    // Check if we need to add .items for ArrayList
    const iter_type = try self.type_inferrer.inferExpr(iter);

    // Check if this is a method call like dict.items()
    const is_method_call = iter == .call and iter.call.func.* == .attribute;

    // If iterating over list (including method calls that return lists), add .items
    if (iter_type == .list) {
        if (is_method_call) {
            // Method call returns ArrayList - wrap in parens for .items
            try self.emit("(");
            try self.genExpr(iter);
            try self.emit(").items");
        } else if (iter == .list) {
            // Inline list literal
            try self.emit("(");
            try self.genExpr(iter);
            try self.emit(").items");
        } else {
            // Variable that holds ArrayList
            try self.genExpr(iter);
            try self.emit(".items");
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

    // Unpack tuple elements using struct field access: const x = __tuple__.@"0"; const y = __tuple__.@"1";
    for (var_names, 0..) |var_name, i| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const {s} = __tuple_{d}__.@\"{d}\";\n", .{ var_name, unique_id, i });
    }

    // Generate body statements
    for (body) |stmt| {
        try self.generateStmt(stmt);
    }

    self.popScope();
    self.dedent();

    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate for loop
pub fn genFor(self: *NativeCodegen, for_stmt: ast.Node.For) CodegenError!void {
    // Check if iterating over a function call (range, enumerate, etc.)
    if (for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .name) {
        const func_name = for_stmt.iter.call.func.name.id;

        // Handle range() loops
        if (std.mem.eql(u8, func_name, "range")) {
            // range() requires single target variable
            const var_name = sanitizeVarName(for_stmt.target.name.id);
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
    const var_name = sanitizeVarName(for_stmt.target.name.id);

    // Check iter type first (needed for tuple special case)
    const iter_type = try self.type_inferrer.inferExpr(for_stmt.iter.*);

    // Special case: tuple iteration requires inline for (comptime)
    if (iter_type == .tuple) {
        try self.emitIndent();
        try self.emit("inline for (");
        try self.genExpr(for_stmt.iter.*);
        try self.emit(") |");
        try self.emit(var_name);
        try self.emit("| {\n");

        self.indent();
        try self.pushScope();

        for (for_stmt.body) |stmt| {
            try self.generateStmt(stmt);
        }

        self.popScope();
        self.dedent();

        try self.emitIndent();
        try self.emit("}\n");
        return;
    }

    // Regular iteration over collection
    try self.emitIndent();
    try self.emit("for (");

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
        try self.emit("(");
        try self.genExpr(for_stmt.iter.*);
        try self.emit(").items");
    } else if (iter_type == .list and for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .attribute) {
        // Method call that returns ArrayList - wrap in parens for .items access
        try self.emit("(");
        try self.genExpr(for_stmt.iter.*);
        try self.emit(").items");
    } else {
        try self.genExpr(for_stmt.iter.*);
        if (iter_type == .list) {
            try self.emit(".items");
        }
    }

    try self.emit(") |");
    try self.emit(var_name);
    try self.emit("| {\n");

    self.indent();

    // Push new scope for loop body
    try self.pushScope();

    // If iterating over a vararg param (e.g., args in *args), register loop var as i64
    // This enables correct type inference for print(x) inside the loop
    if (for_stmt.iter.* == .name) {
        const iter_var_name = for_stmt.iter.name.id;
        if (self.vararg_params.contains(iter_var_name)) {
            // Register loop variable as i64 type
            try self.type_inferrer.var_types.put(var_name, .int);
        }
    }

    for (for_stmt.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting loop
    self.popScope();

    self.dedent();

    try self.emitIndent();
    try self.emit("}\n");
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
    try self.emit("{\n");
    self.indent();

    // Generate initialization (always declare as new variable in block scope)
    try self.emitIndent();
    try self.emit("var ");
    try self.emit(var_name);
    try self.emit(": usize = ");
    if (start_expr) |start| {
        try self.genExpr(start);
    } else {
        try self.emit("0");
    }
    try self.emit(";\n");

    // Generate while loop
    try self.emitIndent();
    try self.emit("while (");
    try self.emit(var_name);
    try self.emit(" < ");
    try self.genExpr(stop_expr);
    try self.emit(") {\n");

    self.indent();

    // Push new scope for loop body
    try self.pushScope();

    for (body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Increment
    try self.emitIndent();
    try self.emit(var_name);
    try self.emit(" += ");
    if (step_expr) |step| {
        try self.genExpr(step);
    } else {
        try self.emit("1");
    }
    try self.emit(";\n");

    // Pop scope when exiting loop
    self.popScope();

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // Close block scope
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

