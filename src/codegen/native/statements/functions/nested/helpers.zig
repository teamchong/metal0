/// Helper functions for closure generation - capture struct access
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const shared = @import("../../../shared_maps.zig");
const BinOpStrings = shared.BinOpStrings;

/// Generate statement with captured variable references prefixed with capture param name
pub fn genStmtWithCaptureStruct(
    self: *NativeCodegen,
    stmt: ast.Node,
    captured_vars: [][]const u8,
    capture_param_name: []const u8,
) CodegenError!void {
    switch (stmt) {
        .return_stmt => |ret| {
            const b = try self.getBuilder();
            try b.writeIndent();
            try b.emitRaw("return ");
            if (ret.value) |val| {
                try genExprWithCaptureStructBuilder(self, b, val.*, captured_vars, capture_param_name);
            }
            try b.emitRaw(";\n");
            const output = try b.getBodyDupe();
            try self.output.appendSlice(self.allocator, output);
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
                const b = try self.getBuilder();
                try b.writeIndent();
                if (is_already_declared) {
                    // Variable already exists (e.g., function parameter being reassigned)
                    // Just emit assignment without declaration
                    try b.emitRaw(var_name);
                } else {
                    try b.emitRaw("const ");
                    try b.emitRaw(var_name);
                }
                try b.emitRaw(" = ");
                try genExprWithCaptureStructBuilder(self, b, assign.value.*, captured_vars, capture_param_name);
                try b.emitRaw(";\n");
                const output = try b.getBodyDupe();
                try self.output.appendSlice(self.allocator, output);
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
/// Legacy wrapper that creates builder and flushes - for external callers
pub fn genExprWithCaptureStruct(
    self: *NativeCodegen,
    node: ast.Node,
    captured_vars: [][]const u8,
    capture_param_name: []const u8,
) CodegenError!void {
    const b = try self.getBuilder();
    try genExprWithCaptureStructBuilder(self, b, node, captured_vars, capture_param_name);
    const output = try b.getBodyDupe();
    try self.output.appendSlice(self.allocator, output);
}

const builder_mod = @import("codegen.builder");

/// Generate expression with captured variable references - builder version for recursion
fn genExprWithCaptureStructBuilder(
    self: *NativeCodegen,
    b: *builder_mod.ZigBuilder,
    node: ast.Node,
    captured_vars: [][]const u8,
    capture_param_name: []const u8,
) CodegenError!void {
    switch (node) {
        .name => |n| {
            // Check if this variable is captured
            for (captured_vars) |captured| {
                if (std.mem.eql(u8, n.id, captured)) {
                    try b.emitRaw(capture_param_name);
                    try b.emitRaw(".");
                    try b.emitRaw(n.id);
                    return;
                }
            }
            try b.emitRaw(n.id);
        },
        .binop => |bin| {
            // Use @mod for modulo to handle signed integers properly
            if (bin.op == .Mod) {
                try b.emitRaw("@mod(");
                try genExprWithCaptureStructBuilder(self, b, bin.left.*, captured_vars, capture_param_name);
                try b.emitRaw(", ");
                try genExprWithCaptureStructBuilder(self, b, bin.right.*, captured_vars, capture_param_name);
                try b.emitRaw(")");
            } else if (bin.op == .Pow) {
                // Zig doesn't have ** operator, use std.math.pow
                try b.emitRaw("std.math.pow(i64, ");
                try genExprWithCaptureStructBuilder(self, b, bin.left.*, captured_vars, capture_param_name);
                try b.emitRaw(", ");
                try genExprWithCaptureStructBuilder(self, b, bin.right.*, captured_vars, capture_param_name);
                try b.emitRaw(")");
            } else if (bin.op == .FloorDiv) {
                // Floor division uses @divFloor for Python semantics
                try b.emitRaw("@divFloor(");
                try genExprWithCaptureStructBuilder(self, b, bin.left.*, captured_vars, capture_param_name);
                try b.emitRaw(", ");
                try genExprWithCaptureStructBuilder(self, b, bin.right.*, captured_vars, capture_param_name);
                try b.emitRaw(")");
            } else {
                try b.emitRaw("(");
                try genExprWithCaptureStructBuilder(self, b, bin.left.*, captured_vars, capture_param_name);
                try b.emitRaw(BinOpStrings.get(@tagName(bin.op)) orelse " ? ");
                try genExprWithCaptureStructBuilder(self, b, bin.right.*, captured_vars, capture_param_name);
                try b.emitRaw(")");
            }
        },
        .constant => |c| {
            // For constants, capture to builder using captureExpr pattern
            const val = try self.captureExpr(node);
            try b.emitValue(val, .{});
            _ = c;
        },
        .call => |c| {
            // Check if calling a closure variable - need to use .call() syntax
            const is_closure_call = if (c.func.* == .name) blk: {
                const func_name = c.func.name.id;
                break :blk self.closure_vars.contains(func_name);
            } else false;

            if (is_closure_call) {
                try genExprWithCaptureStructBuilder(self, b, c.func.*, captured_vars, capture_param_name);
                try b.emitRaw(".call(");
            } else {
                try genExprWithCaptureStructBuilder(self, b, c.func.*, captured_vars, capture_param_name);
                try b.emitRaw("(");
            }
            for (c.args, 0..) |arg, i| {
                if (i > 0) try b.emitRaw(", ");
                try genExprWithCaptureStructBuilder(self, b, arg, captured_vars, capture_param_name);
            }
            try b.emitRaw(")");
        },
        .attribute => |attr| {
            // Handle attribute access like self.foo, rewriting captured var prefix
            try genExprWithCaptureStructBuilder(self, b, attr.value.*, captured_vars, capture_param_name);
            try b.emitRaw(".");
            try b.emitRaw(attr.attr);
        },
        .subscript => |sub| {
            // Handle subscript like foo[bar], rewriting captured vars in both parts
            try genExprWithCaptureStructBuilder(self, b, sub.value.*, captured_vars, capture_param_name);
            try b.emitRaw("[");
            switch (sub.slice) {
                .index => |idx| try genExprWithCaptureStructBuilder(self, b, idx.*, captured_vars, capture_param_name),
                else => {
                    // For slice expressions, capture and emit
                    const val = try self.captureExpr(node);
                    try b.emitValue(val, .{});
                    return;
                },
            }
            try b.emitRaw("]");
        },
        else => {
            // For other expressions, capture and emit
            const val = try self.captureExpr(node);
            try b.emitValue(val, .{});
        },
    }
}
