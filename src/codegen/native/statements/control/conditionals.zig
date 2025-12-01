/// Conditional statement code generation (if, pass, break, continue)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const CodeBuilder = @import("../../code_builder.zig").CodeBuilder;

/// Information about a variable to be hoisted
const HoistedVar = struct {
    name: []const u8,
    node: ast.Node,
};

/// Check if a condition is a comptime constant and return its boolean value
/// Returns null if not comptime constant, true/false otherwise
/// anytype_params: set of parameter names that are anytype (cannot be comptime evaluated)
fn isComptimeConstantCondition(node: ast.Node, anytype_params: anytype) ?bool {
    switch (node) {
        // Literal True/False or numeric constants
        .constant => |c| {
            switch (c.value) {
                .bool => |b| return b,
                // Python truthy: 0 is False, any other int is True
                .int => |i| return i != 0,
                .float => |f| return f != 0.0,
                // Empty string is falsy
                .string => |s| return s.len > 0,
                .none => return false,
                else => return null,
            }
        },
        // isinstance() returns true at compile time ONLY for non-anytype typed variables
        // NOTE: User-defined type check functions (isint, isnum, isRat) are NOT comptime constant
        // because they call isinstance internally which may have runtime behavior for anytype
        .call => |call| {
            if (call.func.* == .name) {
                const func_name = call.func.name.id;
                // Only isinstance itself can be comptime evaluated, not user wrappers
                if (std.mem.eql(u8, func_name, "isinstance")) {
                    // Check if the argument is an anytype parameter
                    if (call.args.len > 0 and call.args[0] == .name) {
                        const arg_name = call.args[0].name.id;
                        if (anytype_params.contains(arg_name)) {
                            // Cannot evaluate at comptime for anytype params
                            return null;
                        }
                    }
                    return true;
                }
            }
            return null;
        },
        // not <expr> - negate the inner value
        .unaryop => |u| {
            if (u.op == .Not) {
                if (isComptimeConstantCondition(u.operand.*, anytype_params)) |inner| {
                    return !inner;
                }
            }
            return null;
        },
        else => return null,
    }
}

/// Info about a type check pattern: if not isint(x): raise TypeError
const TypeCheckRaiseInfo = struct {
    param_name: []const u8,
    check_type: []const u8, // "int", "float", etc.
};

/// Check if an if statement is a type-check-then-raise pattern for an anytype param
/// Pattern: if not isinstance(x, int): raise TypeError  OR  if not isint(x): raise TypeError
fn isTypeCheckRaisePattern(if_stmt: ast.Node.If, anytype_params: anytype) ?TypeCheckRaiseInfo {
    // Body must be a single raise TypeError
    if (if_stmt.body.len != 1) return null;
    if (if_stmt.body[0] != .raise_stmt) return null;
    const raise = if_stmt.body[0].raise_stmt;
    if (raise.exc == null) return null;

    // Check the exception is TypeError
    const is_type_error = blk: {
        if (raise.exc.?.* == .call) {
            const call = raise.exc.?.call;
            if (call.func.* == .name) {
                break :blk std.mem.eql(u8, call.func.name.id, "TypeError");
            }
        } else if (raise.exc.?.* == .name) {
            break :blk std.mem.eql(u8, raise.exc.?.name.id, "TypeError");
        }
        break :blk false;
    };
    if (!is_type_error) return null;

    // Condition must be: not isint(x) or not isinstance(x, type)
    if (if_stmt.condition.* != .unaryop) return null;
    const unary = if_stmt.condition.unaryop;
    if (unary.op != .Not) return null;
    if (unary.operand.* != .call) return null;

    const call = unary.operand.call;
    if (call.func.* != .name) return null;
    const func_name = call.func.name.id;

    // Check for isint(x) pattern
    if (std.mem.eql(u8, func_name, "isint")) {
        if (call.args.len >= 1 and call.args[0] == .name) {
            const arg_name = call.args[0].name.id;
            if (anytype_params.contains(arg_name)) {
                return TypeCheckRaiseInfo{ .param_name = arg_name, .check_type = "int" };
            }
        }
    }
    // Check for isinstance(x, int) pattern
    else if (std.mem.eql(u8, func_name, "isinstance")) {
        if (call.args.len >= 2 and call.args[0] == .name and call.args[1] == .name) {
            const arg_name = call.args[0].name.id;
            const type_name = call.args[1].name.id;
            if (anytype_params.contains(arg_name)) {
                return TypeCheckRaiseInfo{ .param_name = arg_name, .check_type = type_name };
            }
        }
    }

    return null;
}

/// Pre-scan an expression for walrus operators (named_expr) and emit variable declarations
fn emitWalrusDeclarations(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    switch (node) {
        .named_expr => |ne| {
            // Found a walrus operator - declare the variable if not already declared
            if (ne.target.* == .name) {
                const var_name = ne.target.name.id;
                if (!self.isDeclared(var_name)) {
                    // Infer the type from the value
                    const value_type = try self.type_inferrer.inferExpr(ne.value.*);

                    // Get the Zig type string
                    var type_buf = std.ArrayList(u8){};
                    defer type_buf.deinit(self.allocator);
                    value_type.toZigType(self.allocator, &type_buf) catch {
                        try type_buf.writer(self.allocator).writeAll("i64");
                    };

                    try self.emitIndent();
                    try self.emit("var ");
                    try self.emit(var_name);
                    try self.emit(": ");
                    try self.emit(type_buf.items);
                    try self.emit(" = undefined;\n");
                    try self.declareVar(var_name);
                }
            }
            // Also scan the value expression for nested walrus operators
            try emitWalrusDeclarations(self, ne.value.*);
        },
        .binop => |b| {
            try emitWalrusDeclarations(self, b.left.*);
            try emitWalrusDeclarations(self, b.right.*);
        },
        .compare => |c| {
            try emitWalrusDeclarations(self, c.left.*);
            for (c.comparators) |comp| {
                try emitWalrusDeclarations(self, comp);
            }
        },
        .boolop => |b| {
            for (b.values) |val| {
                try emitWalrusDeclarations(self, val);
            }
        },
        .call => |c| {
            try emitWalrusDeclarations(self, c.func.*);
            for (c.args) |arg| {
                try emitWalrusDeclarations(self, arg);
            }
        },
        .unaryop => |u| {
            try emitWalrusDeclarations(self, u.operand.*);
        },
        else => {}, // Other node types don't contain expressions we need to scan
    }
}

/// Collect variables assigned in a statement body that are not yet declared
/// These need to be hoisted before the if statement
fn collectAssignedVars(self: *NativeCodegen, stmts: []const ast.Node, vars: *std.ArrayList(HoistedVar)) CodegenError!void {
    for (stmts) |stmt| {
        switch (stmt) {
            .assign => |assign| {
                // Check each target for simple variable assignments
                for (assign.targets) |target| {
                    if (target == .name) {
                        const var_name = target.name.id;
                        if (!self.isDeclared(var_name)) {
                            // Check if already in our list
                            var found = false;
                            for (vars.items) |v| {
                                if (std.mem.eql(u8, v.name, var_name)) {
                                    found = true;
                                    break;
                                }
                            }
                            if (!found) {
                                try vars.append(self.allocator, HoistedVar{ .name = var_name, .node = assign.value.* });
                            }
                        }
                    }
                }
            },
            .if_stmt => |nested_if| {
                // Recursively scan nested if statements
                try collectAssignedVars(self, nested_if.body, vars);
                try collectAssignedVars(self, nested_if.else_body, vars);
            },
            else => {},
        }
    }
}

/// Generate if statement
pub fn genIf(self: *NativeCodegen, if_stmt: ast.Node.If) CodegenError!void {
    return genIfImpl(self, if_stmt, false, true);
}

/// Internal if generation with option to skip initial indent (for elif chains)
/// hoist_vars: whether to pre-scan and hoist variable declarations (only for top-level if)
fn genIfImpl(self: *NativeCodegen, if_stmt: ast.Node.If, skip_indent: bool, hoist_vars: bool) CodegenError!void {
    // NOTE: Type-check-raise patterns (if not isint(x): raise TypeError) are now handled
    // at the function level in function_gen.zig using comptime branching that wraps the
    // entire function body. This ensures gcd(x, y) calls are only analyzed for valid types.

    // Check for comptime constant conditions - eliminate dead branches
    if (isComptimeConstantCondition(if_stmt.condition.*, self.anytype_params)) |comptime_value| {
        // Even though condition is comptime constant, we still need to "evaluate" it
        // to mark any variables it uses as referenced (e.g., isinstance(x, T) uses x)
        // Generate: _ = (condition); before the body
        try self.emitIndent();
        try self.emit("_ = ");
        try self.genExpr(if_stmt.condition.*);
        try self.emit(";\n");

        if (comptime_value) {
            // Condition is comptime True - only emit if body
            for (if_stmt.body) |stmt| {
                try self.generateStmt(stmt);
            }
            return;
        } else {
            // Condition is comptime False - only emit else body
            for (if_stmt.else_body) |stmt| {
                try self.generateStmt(stmt);
            }
            return;
        }
    }

    var builder = CodeBuilder.init(self);

    // Pre-scan condition for walrus operators and emit variable declarations
    try emitWalrusDeclarations(self, if_stmt.condition.*);

    // For top-level if, hoist variables assigned in any branch
    if (hoist_vars) {
        var assigned_vars = std.ArrayList(HoistedVar){};
        defer assigned_vars.deinit(self.allocator);

        // Collect variables from all branches
        try collectAssignedVars(self, if_stmt.body, &assigned_vars);
        try collectAssignedVars(self, if_stmt.else_body, &assigned_vars);

        // Emit declarations for variables that will be assigned in branches
        for (assigned_vars.items) |v| {
            const var_type = self.type_inferrer.inferExpr(v.node) catch .unknown;
            var type_buf = std.ArrayList(u8){};
            defer type_buf.deinit(self.allocator);
            var_type.toZigType(self.allocator, &type_buf) catch {
                try type_buf.writer(self.allocator).writeAll("i64");
            };

            try self.emitIndent();
            try self.emit("var ");
            try self.emit(v.name);
            try self.emit(": ");
            try self.emit(type_buf.items);
            try self.emit(" = undefined;\n");
            try self.declareVar(v.name);
        }
    }

    if (!skip_indent) {
        try self.emitIndent();
    }
    _ = try builder.write("if (");

    // Check condition type - need to handle PyObject truthiness
    const cond_type = self.type_inferrer.inferExpr(if_stmt.condition.*) catch .unknown;
    const cond_tag = @as(std.meta.Tag(@TypeOf(cond_type)), cond_type);
    if (cond_type == .unknown) {
        // Unknown type (PyObject) - use runtime truthiness check
        _ = try builder.write("runtime.pyTruthy(");
        try self.genExpr(if_stmt.condition.*);
        _ = try builder.write(")");
    } else if (cond_type == .optional) {
        // Optional type - check for non-null
        try self.genExpr(if_stmt.condition.*);
        _ = try builder.write(" != null");
    } else if (cond_type == .bool) {
        // Boolean - use directly
        try self.genExpr(if_stmt.condition.*);
    } else if (cond_tag == .class_instance) {
        // Class instance - use runtime.toBool for duck typing (__bool__ support)
        _ = try builder.write("runtime.toBool(");
        try self.genExpr(if_stmt.condition.*);
        _ = try builder.write(")");
    } else {
        // Other types (int, float, string, etc.) - use runtime.toBool
        // This handles Python truthiness semantics (0 is false, "" is false, etc.)
        _ = try builder.write("runtime.toBool(");
        try self.genExpr(if_stmt.condition.*);
        _ = try builder.write(")");
    }
    _ = try builder.write(")");
    _ = try builder.beginBlock();

    for (if_stmt.body) |stmt| {
        try self.generateStmt(stmt);
    }

    if (if_stmt.else_body.len > 0) {
        // Check if else_body is a single If statement (elif pattern)
        const is_elif = if_stmt.else_body.len == 1 and if_stmt.else_body[0] == .if_stmt;
        if (is_elif) {
            // elif: emit "} else " then recursively generate the nested if (without indent)
            self.dedent();
            try self.emitIndent();
            try self.emit("} else ");
            // Recursively generate the elif chain (skip_indent=true avoids double indentation)
            // hoist_vars=false since top-level if already hoisted all variables
            try genIfImpl(self, if_stmt.else_body[0].if_stmt, true, false);
        } else {
            // Regular else block
            // elseClause() now handles dedent internally
            _ = try builder.elseClause();
            _ = try builder.beginBlock();
            for (if_stmt.else_body) |stmt| {
                try self.generateStmt(stmt);
            }
            _ = try builder.endBlock();
        }
    } else {
        _ = try builder.endBlock();
    }
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
