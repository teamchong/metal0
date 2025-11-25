/// Conditional statement code generation (if, pass, break, continue)
const std = @import("std");
const ast = @import("../../../../ast.zig");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const CodeBuilder = @import("../../code_builder.zig").CodeBuilder;

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
                        try type_buf.appendSlice(self.allocator, "i64");
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
    var builder = CodeBuilder.init(self);

    // Pre-scan condition for walrus operators and emit variable declarations
    try emitWalrusDeclarations(self, if_stmt.condition.*);

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
