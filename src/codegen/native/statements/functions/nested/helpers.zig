/// Helper functions for closure generation - capture struct access
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;

/// Generate statement with captured variable references prefixed with capture param name
pub fn genStmtWithCaptureStruct(
    self: *NativeCodegen,
    stmt: ast.Node,
    captured_vars: [][]const u8,
    capture_param_name: []const u8,
) CodegenError!void {
    switch (stmt) {
        .return_stmt => |ret| {
            try self.emitIndent();
            try self.emit("return ");
            if (ret.value) |val| {
                try genExprWithCaptureStruct(self, val.*, captured_vars, capture_param_name);
            }
            try self.emit(";\n");
        },
        .function_def => |func| {
            // Handle nested function definition within a closure
            // We need to generate this with awareness of the outer capture context
            const closure_gen = @import("closure_gen.zig");
            try closure_gen.genNestedFunctionWithOuterCapture(self, func, captured_vars, capture_param_name);
        },
        .assign => |assign| {
            // For simple name target (single target), emit the name with const
            if (assign.targets.len == 1 and assign.targets[0] == .name) {
                const var_name = assign.targets[0].name.id;
                const is_already_declared = self.isDeclared(var_name);
                try self.emitIndent();
                if (is_already_declared) {
                    // Variable already exists (e.g., function parameter being reassigned)
                    // Just emit assignment without declaration
                    try self.emit(var_name);
                } else {
                    try self.emit("const ");
                    try self.emit(var_name);
                }
                try self.emit(" = ");
                try genExprWithCaptureStruct(self, assign.value.*, captured_vars, capture_param_name);
                try self.emit(";\n");
            } else if (assign.targets.len == 1 and (assign.targets[0] == .tuple or assign.targets[0] == .list)) {
                // Tuple/list unpacking - use regular assignment generation
                try self.generateStmt(stmt);
            } else {
                // Multiple targets or other patterns - fallback to regular generation
                try self.generateStmt(stmt);
            }
        },
        else => {
            // For other statements, use regular generation
            try self.generateStmt(stmt);
        },
    }
}

/// Generate expression with captured variable references prefixed with capture param name
pub fn genExprWithCaptureStruct(
    self: *NativeCodegen,
    node: ast.Node,
    captured_vars: [][]const u8,
    capture_param_name: []const u8,
) CodegenError!void {
    switch (node) {
        .name => |n| {
            // Check if this variable is captured
            for (captured_vars) |captured| {
                if (std.mem.eql(u8, n.id, captured)) {
                    try self.emit(capture_param_name);
                    try self.emit(".");
                    try self.emit(n.id);
                    return;
                }
            }
            try self.emit(n.id);
        },
        .binop => |b| {
            try self.emit("(");
            try genExprWithCaptureStruct(self, b.left.*, captured_vars, capture_param_name);

            const op_str = switch (b.op) {
                .Add => " + ",
                .Sub => " - ",
                .Mult => " * ",
                .MatMul => " @ ", // Matrix multiplication - handled by numpy at runtime
                .Div => " / ",
                .FloorDiv => " / ",
                .Mod => " % ",
                .Pow => " ** ",
                .BitAnd => " & ",
                .BitOr => " | ",
                .BitXor => " ^ ",
                .LShift => " << ",
                .RShift => " >> ",
            };
            try self.emit(op_str);

            try genExprWithCaptureStruct(self, b.right.*, captured_vars, capture_param_name);
            try self.emit(")");
        },
        .constant => |c| {
            const expressions = @import("../../../expressions.zig");
            try expressions.genConstant(self, c);
        },
        .call => |c| {
            // Check if calling a closure variable - need to use .call() syntax
            const is_closure_call = if (c.func.* == .name) blk: {
                const func_name = c.func.name.id;
                break :blk self.closure_vars.contains(func_name);
            } else false;

            if (is_closure_call) {
                try genExprWithCaptureStruct(self, c.func.*, captured_vars, capture_param_name);
                try self.emit(".call(");
            } else {
                try genExprWithCaptureStruct(self, c.func.*, captured_vars, capture_param_name);
                try self.emit("(");
            }
            for (c.args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try genExprWithCaptureStruct(self, arg, captured_vars, capture_param_name);
            }
            try self.emit(")");
        },
        .attribute => |attr| {
            // Handle attribute access like self.foo, rewriting captured var prefix
            try genExprWithCaptureStruct(self, attr.value.*, captured_vars, capture_param_name);
            try self.emit(".");
            try self.emit(attr.attr);
        },
        .subscript => |sub| {
            // Handle subscript like foo[bar], rewriting captured vars in both parts
            try genExprWithCaptureStruct(self, sub.value.*, captured_vars, capture_param_name);
            try self.emit("[");
            switch (sub.slice) {
                .index => |idx| try genExprWithCaptureStruct(self, idx.*, captured_vars, capture_param_name),
                else => {
                    // For slice expressions, fall back to regular generation
                    const expressions = @import("../../../expressions.zig");
                    try expressions.genExpr(self, node);
                    return;
                },
            }
            try self.emit("]");
        },
        else => {
            const expressions = @import("../../../expressions.zig");
            try expressions.genExpr(self, node);
        },
    }
}
