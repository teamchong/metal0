/// Conditional statement code generation (if, pass, break, continue)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const CodeBuilder = @import("../../code_builder.zig").CodeBuilder;

/// Check if a condition is a comptime constant and return its boolean value
/// Returns null if not comptime constant, true/false otherwise
fn isComptimeConstantCondition(node: ast.Node) ?bool {
    switch (node) {
        // Literal True/False
        .constant => |c| {
            switch (c.value) {
                .bool => |b| return b,
                else => return null,
            }
        },
        // isinstance() always returns true at compile time for typed variables
        .call => |call| {
            if (call.func.* == .name) {
                const func_name = call.func.name.id;
                if (std.mem.eql(u8, func_name, "isinstance")) {
                    return true;
                }
            }
            return null;
        },
        // not <expr> - negate the inner value
        .unaryop => |u| {
            if (u.op == .Not) {
                if (isComptimeConstantCondition(u.operand.*)) |inner| {
                    return !inner;
                }
            }
            return null;
        },
        else => return null,
    }
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

/// Generate if statement
pub fn genIf(self: *NativeCodegen, if_stmt: ast.Node.If) CodegenError!void {
    // Check for comptime constant conditions - eliminate dead branches
    if (isComptimeConstantCondition(if_stmt.condition.*)) |comptime_value| {
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

    try self.emitIndent();
    _ = try builder.write("if (");

    // Check condition type - need to handle PyObject truthiness
    const cond_type = self.type_inferrer.inferExpr(if_stmt.condition.*) catch .unknown;
    if (cond_type == .unknown) {
        // Unknown type (PyObject) - use runtime truthiness check
        _ = try builder.write("runtime.pyTruthy(");
        try self.genExpr(if_stmt.condition.*);
        _ = try builder.write(")");
    } else if (cond_type == .optional) {
        // Optional type - check for non-null
        try self.genExpr(if_stmt.condition.*);
        _ = try builder.write(" != null");
    } else {
        // Boolean or other type - use directly
        try self.genExpr(if_stmt.condition.*);
    }
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
