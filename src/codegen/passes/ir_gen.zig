//! Pass 1: IR Generation
//!
//! Converts Python AST to Zig IR. This is the bridge between the parser
//! and the multi-pass code generation system.
//!
//! Currently supports:
//! - Variable assignments (simple names)
//! - Return statements
//! - Expression statements
//! - If statements
//! - While loops
//! - For loops (basic)
//! - Function definitions (basic)
//!
//! Unsupported constructs fall back to `raw` IR nodes.

const std = @import("std");
const ir = @import("../ir.zig");
const ast = @import("analysis.ast");

pub const ZigIR = ir.ZigIR;
pub const ZigIRExpr = ir.ZigIRExpr;
pub const ZigIRType = ir.ZigIRType;

/// Error type for IR generation
pub const IRGenError = std.mem.Allocator.Error;

/// IR generation context
pub const IRGenerator = struct {
    allocator: std.mem.Allocator,
    /// Track variables that have been declared
    declared_vars: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator) IRGenerator {
        return .{
            .allocator = allocator,
            .declared_vars = std.StringHashMap(void).init(allocator),
        };
    }

    pub fn deinit(self: *IRGenerator) void {
        self.declared_vars.deinit();
    }

    /// Generate IR for a module
    pub fn generateModule(self: *IRGenerator, module: ast.Node.Module) IRGenError![]ZigIR {
        var stmts: std.ArrayList(ZigIR) = .{};
        errdefer stmts.deinit(self.allocator);

        for (module.body) |stmt| {
            const ir_stmt = try self.generateStmt(stmt);
            try stmts.append(self.allocator, ir_stmt);
        }

        return stmts.toOwnedSlice(self.allocator);
    }

    /// Generate IR for a statement
    pub fn generateStmt(self: *IRGenerator, stmt: ast.Node) IRGenError!ZigIR {
        return switch (stmt) {
            .assign => |a| try self.generateAssign(a),
            .aug_assign => |aa| try self.generateAugAssign(aa),
            .return_stmt => |r| try self.generateReturn(r),
            .if_stmt => |i| try self.generateIf(i),
            .while_stmt => |w| try self.generateWhile(w),
            .for_stmt => |f| try self.generateFor(f),
            .function_def => |fd| try self.generateFunctionDef(fd),
            .expr_stmt => |e| try self.generateExprStmt(e),
            .pass => .blank,
            else => .{ .raw = "(unsupported stmt)" },
        };
    }

    /// Generate IR for assignment: x = value
    fn generateAssign(self: *IRGenerator, assign: ast.Node.Assign) IRGenError!ZigIR {
        // Only handle single target for now
        if (assign.targets.len != 1) {
            return .{ .raw = "multi-target assign (unsupported)" };
        }

        const target = assign.targets[0];
        if (target != .name) {
            // Complex target (subscript, attribute, etc.)
            const target_expr = try self.generateExpr(target);
            const value_expr = try self.generateExpr(assign.value.*);
            return .{ .assign = .{
                .target = target_expr,
                .value = value_expr,
            } };
        }

        const var_name = target.name.id;
        const value_expr = try self.generateExpr(assign.value.*);

        // First assignment = declaration, subsequent = reassignment
        if (self.declared_vars.contains(var_name)) {
            const target_expr = try self.allocator.create(ZigIRExpr);
            target_expr.* = .{ .name = var_name };
            return .{ .assign = .{
                .target = target_expr,
                .value = value_expr,
            } };
        } else {
            try self.declared_vars.put(var_name, {});
            return .{ .var_decl = .{
                .name = var_name,
                .init = value_expr,
            } };
        }
    }

    /// Generate IR for augmented assignment: x += value
    fn generateAugAssign(self: *IRGenerator, aug_assign: ast.Node.AugAssign) IRGenError!ZigIR {
        const target_expr = try self.generateExpr(aug_assign.target.*);
        const value_expr = try self.generateExpr(aug_assign.value.*);

        const op: ir.AugOp = switch (aug_assign.op) {
            .Add => .add,
            .Sub => .sub,
            .Mult => .mul,
            .Div, .FloorDiv => .div,
            .Mod => .mod,
            .BitAnd => .bit_and,
            .BitOr => .bit_or,
            .BitXor => .bit_xor,
            .LShift => .lshift,
            .RShift => .rshift,
            else => return .{ .raw = "unsupported aug_assign op" },
        };

        return .{ .aug_assign = .{
            .target = target_expr,
            .op = op,
            .value = value_expr,
        } };
    }

    /// Generate IR for return statement
    fn generateReturn(self: *IRGenerator, ret: ast.Node.Return) IRGenError!ZigIR {
        const value = if (ret.value) |v|
            try self.generateExpr(v.*)
        else
            null;

        return .{ .return_ = .{ .value = value } };
    }

    /// Generate IR for if statement
    fn generateIf(self: *IRGenerator, if_stmt: ast.Node.If) IRGenError!ZigIR {
        const condition = try self.generateExpr(if_stmt.condition.*);

        // Generate then body
        var then_body: std.ArrayList(ZigIR) = .{};
        for (if_stmt.body) |stmt| {
            try then_body.append(self.allocator, try self.generateStmt(stmt));
        }

        // Generate else body if present
        var else_body: ?[]ZigIR = null;
        if (if_stmt.else_body.len > 0) {
            var else_stmts: std.ArrayList(ZigIR) = .{};
            for (if_stmt.else_body) |stmt| {
                try else_stmts.append(self.allocator, try self.generateStmt(stmt));
            }
            else_body = try else_stmts.toOwnedSlice(self.allocator);
        }

        return .{ .if_stmt = .{
            .condition = condition,
            .then_body = try then_body.toOwnedSlice(self.allocator),
            .else_body = else_body,
        } };
    }

    /// Generate IR for while loop
    fn generateWhile(self: *IRGenerator, while_stmt: ast.Node.While) IRGenError!ZigIR {
        const condition = try self.generateExpr(while_stmt.condition.*);

        var body: std.ArrayList(ZigIR) = .{};
        for (while_stmt.body) |stmt| {
            try body.append(self.allocator, try self.generateStmt(stmt));
        }

        return .{ .while_loop = .{
            .condition = condition,
            .body = try body.toOwnedSlice(self.allocator),
        } };
    }

    /// Generate IR for for loop
    fn generateFor(self: *IRGenerator, for_stmt: ast.Node.For) IRGenError!ZigIR {
        // Only handle simple name target
        if (for_stmt.target.* != .name) {
            return .{ .raw = "for with complex target (unsupported)" };
        }

        const target_name = for_stmt.target.name.id;
        const iter_expr = try self.generateExpr(for_stmt.iter.*);

        // Mark target as declared
        try self.declared_vars.put(target_name, {});

        var body: std.ArrayList(ZigIR) = .{};
        for (for_stmt.body) |stmt| {
            try body.append(self.allocator, try self.generateStmt(stmt));
        }

        return .{ .for_loop = .{
            .target = target_name,
            .iter = iter_expr,
            .body = try body.toOwnedSlice(self.allocator),
        } };
    }

    /// Generate IR for function definition
    fn generateFunctionDef(self: *IRGenerator, func: ast.Node.FunctionDef) IRGenError!ZigIR {
        // Create new scope for function body
        var func_gen = IRGenerator.init(self.allocator);
        defer func_gen.deinit();

        // Generate parameters
        var params: std.ArrayList(ir.FunctionParam) = .{};
        for (func.args) |arg| {
            try func_gen.declared_vars.put(arg.name, {});
            try params.append(self.allocator, .{ .name = arg.name });
        }

        // Generate body
        var body: std.ArrayList(ZigIR) = .{};
        for (func.body) |stmt| {
            try body.append(self.allocator, try func_gen.generateStmt(stmt));
        }

        return .{ .function = .{
            .name = func.name,
            .params = try params.toOwnedSlice(self.allocator),
            .body = try body.toOwnedSlice(self.allocator),
        } };
    }

    /// Generate IR for expression statement
    fn generateExprStmt(self: *IRGenerator, expr_stmt: ast.Node.ExprStmt) IRGenError!ZigIR {
        const expr = try self.generateExpr(expr_stmt.value.*);
        return .{ .expr_stmt = .{ .expr = expr } };
    }

    /// Generate IR for an expression
    pub fn generateExpr(self: *IRGenerator, expr: ast.Node) IRGenError!*const ZigIRExpr {
        const ptr = try self.allocator.create(ZigIRExpr);
        errdefer self.allocator.destroy(ptr);

        ptr.* = switch (expr) {
            .constant => |c| try self.generateConstant(c),
            .name => |n| .{ .name = n.id },
            .binop => |b| try self.generateBinOp(b),
            .unaryop => |u| try self.generateUnaryOp(u),
            .compare => |c| try self.generateCompare(c),
            .call => |c| try self.generateCall(c),
            .attribute => |a| try self.generateAttribute(a),
            .subscript => |s| try self.generateSubscript(s),
            .list => |l| try self.generateList(l),
            .tuple => |t| try self.generateTuple(t),
            .if_expr => |i| try self.generateIfExpr(i),
            else => .{ .raw = "(unsupported expr)" },
        };

        return ptr;
    }

    /// Generate IR for constant
    fn generateConstant(self: *IRGenerator, constant: ast.Node.Constant) IRGenError!ZigIRExpr {
        _ = self;
        return switch (constant.value) {
            .int => |i| .{ .int = i },
            .float => |f| .{ .float = f },
            .bool => |b| .{ .bool_ = b },
            .string => |s| .{ .string = s },
            .none => .null_,
            else => .{ .raw = "unsupported constant type" },
        };
    }

    /// Generate IR for binary operation
    fn generateBinOp(self: *IRGenerator, binop: ast.Node.BinOp) IRGenError!ZigIRExpr {
        const left = try self.generateExpr(binop.left.*);
        const right = try self.generateExpr(binop.right.*);

        const op: ir.BinOpKind = switch (binop.op) {
            .Add => .add,
            .Sub => .sub,
            .Mult => .mul,
            .Div, .FloorDiv => .div,
            .Mod => .mod,
            .BitAnd => .bit_and,
            .BitOr => .bit_or,
            .BitXor => .bit_xor,
            .LShift => .lshift,
            .RShift => .rshift,
            else => return .{ .raw = "unsupported binop" },
        };

        return .{ .binop = .{
            .left = left,
            .op = op,
            .right = right,
        } };
    }

    /// Generate IR for unary operation
    fn generateUnaryOp(self: *IRGenerator, unaryop: ast.Node.UnaryOp) IRGenError!ZigIRExpr {
        const operand = try self.generateExpr(unaryop.operand.*);

        const op: ir.UnaryOpKind = switch (unaryop.op) {
            .USub => .neg,
            .UAdd => {
                // +x is just x - return the operand expression directly
                const result = try self.generateExpr(unaryop.operand.*);
                return result.*;
            },
            .Invert => .bit_not,
            .Not => .logic_not,
        };

        return .{ .unaryop = .{
            .op = op,
            .operand = operand,
        } };
    }

    /// Generate IR for comparison
    fn generateCompare(self: *IRGenerator, compare: ast.Node.Compare) IRGenError!ZigIRExpr {
        // Only handle single comparison for now
        if (compare.ops.len != 1) {
            return .{ .raw = "chained comparison (unsupported)" };
        }

        const left = try self.generateExpr(compare.left.*);
        const right = try self.generateExpr(compare.comparators[0]); // Not a pointer

        const op: ir.BinOpKind = switch (compare.ops[0]) {
            .Eq => .eq,
            .NotEq => .ne,
            .Lt => .lt,
            .LtEq => .le,
            .Gt => .gt,
            .GtEq => .ge,
            else => return .{ .raw = "unsupported comparison op" },
        };

        return .{ .binop = .{
            .left = left,
            .op = op,
            .right = right,
        } };
    }

    /// Generate IR for function call
    fn generateCall(self: *IRGenerator, call: ast.Node.Call) IRGenError!ZigIRExpr {
        const func = try self.generateExpr(call.func.*);

        var args: std.ArrayList(*const ZigIRExpr) = .{};
        for (call.args) |arg| {
            try args.append(self.allocator, try self.generateExpr(arg)); // Not a pointer
        }

        return .{ .call = .{
            .func = func,
            .args = try args.toOwnedSlice(self.allocator),
        } };
    }

    /// Generate IR for attribute access
    fn generateAttribute(self: *IRGenerator, attr: ast.Node.Attribute) IRGenError!ZigIRExpr {
        const object = try self.generateExpr(attr.value.*);
        return .{ .field_access = .{
            .object = object,
            .field = attr.attr,
        } };
    }

    /// Generate IR for subscript
    fn generateSubscript(self: *IRGenerator, subscript: ast.Node.Subscript) IRGenError!ZigIRExpr {
        const object = try self.generateExpr(subscript.value.*);
        // Handle both index access and slice
        switch (subscript.slice) {
            .index => |idx| {
                const index = try self.generateExpr(idx.*);
                return .{ .subscript = .{
                    .object = object,
                    .index = index,
                } };
            },
            .slice => |s| {
                // Slice access: obj[start:end]
                const start = if (s.lower) |l| try self.generateExpr(l.*) else null;
                const end = if (s.upper) |u| try self.generateExpr(u.*) else null;
                return .{ .slice = .{
                    .object = object,
                    .start = start,
                    .end = end,
                } };
            },
        }
    }

    /// Generate IR for list literal
    fn generateList(self: *IRGenerator, list: ast.Node.List) IRGenError!ZigIRExpr {
        var elements: std.ArrayList(*const ZigIRExpr) = .{};
        for (list.elts) |elt| {
            try elements.append(self.allocator, try self.generateExpr(elt)); // Not a pointer
        }
        return .{ .array = .{
            .elements = try elements.toOwnedSlice(self.allocator),
        } };
    }

    /// Generate IR for tuple literal
    fn generateTuple(self: *IRGenerator, tuple: ast.Node.Tuple) IRGenError!ZigIRExpr {
        var elements: std.ArrayList(*const ZigIRExpr) = .{};
        for (tuple.elts) |elt| {
            try elements.append(self.allocator, try self.generateExpr(elt)); // Not a pointer
        }
        return .{ .tuple = .{
            .elements = try elements.toOwnedSlice(self.allocator),
        } };
    }

    /// Generate IR for conditional expression
    fn generateIfExpr(self: *IRGenerator, if_expr: ast.Node.IfExpr) IRGenError!ZigIRExpr {
        const condition = try self.generateExpr(if_expr.condition.*);
        const then_expr = try self.generateExpr(if_expr.body.*);
        const else_expr = try self.generateExpr(if_expr.orelse_value.*);

        return .{ .ternary = .{
            .condition = condition,
            .then_expr = then_expr,
            .else_expr = else_expr,
        } };
    }
};

/// Generate IR from Python AST module
pub fn generateIR(module: ast.Node.Module, allocator: std.mem.Allocator) ![]ZigIR {
    var gen = IRGenerator.init(allocator);
    defer gen.deinit();
    return gen.generateModule(module);
}
