/// StatementBuilder - High-level API for structured Zig code generation
///
/// This abstraction provides the primary interface for codegen, working with
/// structured types (ZigStatement, ZigExpr) rather than raw strings.
///
/// Key responsibilities:
/// - Convert ZigStatement/ZigExpr to ZigBuilder output
/// - Unified comparison dispatch (ALL comparisons flow through same path)
/// - Arena allocation for expression tree management
/// - Type confidence tracking for native vs runtime dispatch
///
/// Integration:
/// - ZigBuilder: Handles actual string emission
/// - ZigStatement: Statement-level constructs (declarations, control flow)
/// - ZigExpr: Expression-level constructs (operations, calls, access)
/// - TypeConfidence: Determines native Zig vs runtime.py* dispatch
///
/// Usage:
///   var sb = try StatementBuilder.init(allocator, builder);
///   defer sb.deinit();
///
///   // Create expressions
///   const left = sb.int(42);
///   const right = sb.name("x");
///
///   // Create comparison (unified path)
///   const cmp = try sb.compare(.eq, left, right);
///
///   // Emit statement
///   try sb.emitStmt(zig_statement.constDecl("result", &cmp));
///
const std = @import("std");
const Allocator = std.mem.Allocator;

const zig_builder = @import("zig_builder.zig");
const zig_statement = @import("zig_statement.zig");
const zig_expr = @import("zig_expr.zig");
const zig_value = @import("zig_value.zig");
const zig_type = @import("zig_type.zig");
const zig_keywords = @import("utils.zig_keywords");

pub const ZigBuilder = zig_builder.ZigBuilder;
pub const ZigStatement = zig_statement.ZigStatement;
pub const ZigExpr = zig_expr.ZigExpr;
pub const ZigValue = zig_value.ZigValue;
pub const ZigType = zig_type.ZigType;
pub const TypeConfidence = zig_value.TypeConfidence;
pub const CertainType = zig_value.CertainType;
pub const CompOp = zig_value.CompOp;
pub const BinOp = zig_value.BinOp;

// Re-export expression types
pub const Binary = zig_expr.Binary;
pub const Unary = zig_expr.Unary;
pub const UnaryOp = zig_expr.UnaryOp;
pub const BinaryOpKind = zig_expr.BinaryOpKind;
pub const ResultType = zig_expr.ResultType;

/// StatementBuilder provides structured codegen through ZigStatement/ZigExpr
pub const StatementBuilder = struct {
    allocator: Allocator,
    builder: *ZigBuilder,
    arena: std.heap.ArenaAllocator,

    /// Initialize with existing ZigBuilder
    pub fn init(allocator: Allocator, builder: *ZigBuilder) StatementBuilder {
        return .{
            .allocator = allocator,
            .builder = builder,
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    /// Initialize standalone (creates internal ZigBuilder)
    pub fn initStandalone(allocator: Allocator) !StatementBuilder {
        const builder = try allocator.create(ZigBuilder);
        builder.* = try ZigBuilder.init(allocator);
        return .{
            .allocator = allocator,
            .builder = builder,
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *StatementBuilder) void {
        self.arena.deinit();
    }

    /// Get arena allocator for expression tree allocation
    fn arenaAlloc(self: *StatementBuilder) Allocator {
        return self.arena.allocator();
    }

    /// Allocate an expression in the arena (returns pointer for tree construction)
    pub fn alloc(self: *StatementBuilder, expr: ZigExpr) !*const ZigExpr {
        const ptr = try self.arenaAlloc().create(ZigExpr);
        ptr.* = expr;
        return ptr;
    }

    /// Allocate a type in the arena
    pub fn allocType(self: *StatementBuilder, ty: ZigType) !*const ZigType {
        const ptr = try self.arenaAlloc().create(ZigType);
        ptr.* = ty;
        return ptr;
    }

    // ========================================================================
    // UNIFIED COMPARISON DISPATCH (Critical Path)
    // ========================================================================
    //
    // ALL comparisons (==, !=, <, <=, >, >=) flow through createComparison().
    // This ensures consistent behavior and proper runtime/native dispatch.
    //
    // Dispatch table:
    // | Left Conf | Right Conf | Same Type | Dispatch |
    // |-----------|------------|-----------|----------|
    // | certain   | certain    | yes       | native   |
    // | certain   | certain    | no        | runtime  |
    // | uncertain | any        | -         | runtime  |
    // | any       | uncertain  | -         | runtime  |

    /// Create a comparison expression with unified dispatch
    /// This is the SINGLE entry point for all comparisons
    pub fn createComparison(
        self: *StatementBuilder,
        op: BinOp,
        left: ZigExpr,
        right: ZigExpr,
    ) !ZigExpr {
        const left_conf = left.confidence();
        const right_conf = right.confidence();
        const left_type = left.certainType();
        const right_type = right.certainType();

        // Determine dispatch path
        const use_native = (left_conf == .certain and
            right_conf == .certain and
            left_type == right_type and
            left_type != .other);

        const dispatch: ResultType = if (use_native) .native else .runtime;

        return .{ .binary = .{
            .op = op,
            .left = try self.alloc(left),
            .right = try self.alloc(right),
            .result_confidence = .certain, // Comparison always returns bool
            .result_type = .bool_,
            .dispatch = dispatch,
        } };
    }

    /// Create an equality comparison (== or !=)
    pub fn eq(self: *StatementBuilder, left: ZigExpr, right: ZigExpr) !ZigExpr {
        return self.createComparison(.eq, left, right);
    }

    pub fn ne(self: *StatementBuilder, left: ZigExpr, right: ZigExpr) !ZigExpr {
        return self.createComparison(.ne, left, right);
    }

    /// Create ordering comparisons
    pub fn lt(self: *StatementBuilder, left: ZigExpr, right: ZigExpr) !ZigExpr {
        return self.createComparison(.lt, left, right);
    }

    pub fn le(self: *StatementBuilder, left: ZigExpr, right: ZigExpr) !ZigExpr {
        return self.createComparison(.le, left, right);
    }

    pub fn gt(self: *StatementBuilder, left: ZigExpr, right: ZigExpr) !ZigExpr {
        return self.createComparison(.gt, left, right);
    }

    pub fn ge(self: *StatementBuilder, left: ZigExpr, right: ZigExpr) !ZigExpr {
        return self.createComparison(.ge, left, right);
    }

    // ========================================================================
    // Expression Builders
    // ========================================================================

    /// Create an integer literal expression
    pub fn int(self: *StatementBuilder, v: i64) ZigExpr {
        _ = self;
        return ZigExpr.int(v);
    }

    /// Create a float literal expression
    pub fn float(self: *StatementBuilder, v: f64) ZigExpr {
        _ = self;
        return ZigExpr.float(v);
    }

    /// Create a string literal expression
    pub fn string(self: *StatementBuilder, v: []const u8) ZigExpr {
        _ = self;
        return ZigExpr.string(v);
    }

    /// Create a boolean literal expression
    pub fn boolean(self: *StatementBuilder, v: bool) ZigExpr {
        _ = self;
        return ZigExpr.boolean(v);
    }

    /// Create a null literal expression
    pub fn null_(self: *StatementBuilder) ZigExpr {
        _ = self;
        return ZigExpr.null_();
    }

    /// Create a name reference expression
    pub fn name(self: *StatementBuilder, n: []const u8) ZigExpr {
        _ = self;
        return ZigExpr.fromName(n);
    }

    /// Create a raw expression (escape hatch)
    pub fn raw(self: *StatementBuilder, code: []const u8) ZigExpr {
        _ = self;
        return ZigExpr.rawExpr(code);
    }

    /// Create a binary operation expression
    pub fn binary(self: *StatementBuilder, op: BinOp, left: ZigExpr, right: ZigExpr) !ZigExpr {
        return .{ .binary = .{
            .op = op,
            .left = try self.alloc(left),
            .right = try self.alloc(right),
        } };
    }

    /// Create a unary operation expression
    pub fn unary(self: *StatementBuilder, op: UnaryOp, operand: ZigExpr) !ZigExpr {
        return .{ .unary = .{
            .op = op,
            .operand = try self.alloc(operand),
        } };
    }

    /// Create a field access expression
    pub fn field(self: *StatementBuilder, obj: ZigExpr, field_name: []const u8) !ZigExpr {
        return .{ .field = .{
            .obj = try self.alloc(obj),
            .field = field_name,
        } };
    }

    /// Create a subscript expression
    pub fn subscript(self: *StatementBuilder, container: ZigExpr, index: ZigExpr) !ZigExpr {
        return .{ .subscript = .{
            .container = try self.alloc(container),
            .index = try self.alloc(index),
        } };
    }

    /// Create a function call expression
    pub fn call(self: *StatementBuilder, func: ZigExpr, args: []const ZigExpr) !ZigExpr {
        const alloc_args = try self.arenaAlloc().alloc(*const ZigExpr, args.len);
        for (args, 0..) |arg, i| {
            alloc_args[i] = try self.alloc(arg);
        }
        return .{ .call = .{
            .func = try self.alloc(func),
            .args = alloc_args,
        } };
    }

    /// Create a method call expression
    pub fn methodCall(self: *StatementBuilder, receiver: ZigExpr, method: []const u8, args: []const ZigExpr) !ZigExpr {
        const alloc_args = try self.arenaAlloc().alloc(*const ZigExpr, args.len);
        for (args, 0..) |arg, i| {
            alloc_args[i] = try self.alloc(arg);
        }
        return .{ .method_call = .{
            .receiver = try self.alloc(receiver),
            .method = method,
            .args = alloc_args,
        } };
    }

    /// Create a try expression
    pub fn try_(self: *StatementBuilder, expr: ZigExpr) !ZigExpr {
        return .{ .try_ = .{
            .expr = try self.alloc(expr),
        } };
    }

    /// Create an orelse expression
    pub fn orelse_(self: *StatementBuilder, expr: ZigExpr, default: ZigExpr) !ZigExpr {
        return .{ .orelse_ = .{
            .expr = try self.alloc(expr),
            .default = try self.alloc(default),
        } };
    }

    /// Create a ternary expression
    pub fn ternary(self: *StatementBuilder, cond: ZigExpr, then_expr: ZigExpr, else_expr: ZigExpr) !ZigExpr {
        return .{ .ternary = .{
            .condition = try self.alloc(cond),
            .then_expr = try self.alloc(then_expr),
            .else_expr = try self.alloc(else_expr),
        } };
    }

    /// Create an address-of expression
    pub fn addressOf(self: *StatementBuilder, expr: ZigExpr) !ZigExpr {
        return .{ .address_of = .{
            .expr = try self.alloc(expr),
        } };
    }

    /// Shorthand: create negation
    pub fn neg(self: *StatementBuilder, expr: ZigExpr) !ZigExpr {
        return self.unary(.neg, expr);
    }

    /// Shorthand: create logical not
    pub fn not_(self: *StatementBuilder, expr: ZigExpr) !ZigExpr {
        return self.unary(.not_, expr);
    }

    /// Shorthand: create bitwise not
    pub fn bitNot(self: *StatementBuilder, expr: ZigExpr) !ZigExpr {
        return self.unary(.bit_not, expr);
    }

    /// Shorthand: arithmetic operations
    pub fn add(self: *StatementBuilder, left: ZigExpr, right: ZigExpr) !ZigExpr {
        return self.binary(.add, left, right);
    }

    pub fn sub(self: *StatementBuilder, left: ZigExpr, right: ZigExpr) !ZigExpr {
        return self.binary(.sub, left, right);
    }

    pub fn mul(self: *StatementBuilder, left: ZigExpr, right: ZigExpr) !ZigExpr {
        return self.binary(.mul, left, right);
    }

    pub fn div(self: *StatementBuilder, left: ZigExpr, right: ZigExpr) !ZigExpr {
        return self.binary(.div, left, right);
    }

    pub fn mod(self: *StatementBuilder, left: ZigExpr, right: ZigExpr) !ZigExpr {
        return self.binary(.mod, left, right);
    }

    // ========================================================================
    // Statement Emission
    // ========================================================================

    /// Emit a ZigStatement to the builder
    pub fn emitStmt(self: *StatementBuilder, stmt: ZigStatement) !void {
        switch (stmt) {
            .const_decl => |d| try self.emitConstDecl(d),
            .var_decl => |d| try self.emitVarDecl(d),
            .var_undef => |d| try self.emitVarUndef(d),
            .assign => |a| try self.emitAssign(a),
            .aug_assign => |a| try self.emitAugAssign(a),
            .field_assign => |a| try self.emitFieldAssign(a),
            .subscript_assign => |a| try self.emitSubscriptAssign(a),
            .if_stmt => |s| try self.emitIfStmt(s),
            .while_loop => |s| try self.emitWhileLoop(s),
            .for_loop => |s| try self.emitForLoop(s),
            .for_indexed => |s| try self.emitForIndexed(s),
            .break_ => |b| try self.emitBreak(b),
            .continue_ => |c| try self.emitContinue(c),
            .return_ => |r| try self.emitReturn(r),
            .defer_ => |d| try self.emitDefer(d),
            .errdefer_ => |e| try self.emitErrdefer(e),
            .switch_ => |s| try self.emitSwitch(s),
            .expr_stmt => |e| try self.emitExprStmt(e),
            .discard_stmt => |d| try self.emitDiscardStmt(d),
            .block => |b| try self.emitBlock(b),
            .inline_for => |f| try self.emitInlineFor(f),
            .comment => |c| try self.emitComment(c),
            .blank => try self.builder.emitBlankLine(),
            .raw => |r| try self.emitRaw(r),
        }
    }

    /// Emit a ZigExpr to the builder (expression position)
    pub fn emitExpr(self: *StatementBuilder, expr: ZigExpr) !void {
        switch (expr) {
            .value => |v| try self.builder.emitValueCore(v),
            .name => |n| {
                // Escape Zig keywords like 'const', 'type', 'test', etc.
                const escaped = try zig_keywords.escapeIfKeyword(self.arena.allocator(), n);
                try self.builder.write(escaped);
            },
            .raw => |r| try self.builder.write(r),
            .binary => |b| try self.emitBinary(b),
            .unary => |u| try self.emitUnary(u),
            .field => |f| try self.emitField(f),
            .subscript => |s| try self.emitSubscript(s),
            .slice => |s| try self.emitSlice(s),
            .call => |c| try self.emitCall(c),
            .method_call => |m| try self.emitMethodCallExpr(m),
            .builtin_call => |b| try self.emitBuiltinCall(b),
            .struct_literal => |s| try self.emitStructLiteral(s),
            .array_literal => |a| try self.emitArrayLiteral(a),
            .ternary => |t| try self.emitTernary(t),
            .labeled_block => |lb| try self.emitLabeledBlockExpr(lb),
            .try_ => |t| try self.emitTry(t),
            .catch_ => |c| try self.emitCatch(c),
            .orelse_ => |o| try self.emitOrelse(o),
            .address_of => |a| try self.emitAddressOf(a),
            .deref => |d| try self.emitDeref(d),
            .cast => |c| try self.emitCast(c),
            .coerce => |c| try self.emitCoerce(c),
        }
    }

    // ========== Declaration Emission ==========

    fn emitConstDecl(self: *StatementBuilder, d: zig_statement.ConstDecl) !void {
        try self.builder.writeIndent();
        try self.builder.writeFmt("const {s}", .{d.name});
        if (d.type_) |ty| {
            try self.builder.write(": ");
            try self.emitType(ty);
        }
        try self.builder.write(" = ");
        try self.emitExpr(d.init.*);
        try self.builder.write(";\n");

        if (d.add_discard) {
            try self.builder.writeIndent();
            try self.builder.writeFmt("_ = &{s};\n", .{d.name});
        }
    }

    fn emitVarDecl(self: *StatementBuilder, d: zig_statement.VarDecl) !void {
        try self.builder.writeIndent();
        try self.builder.writeFmt("var {s}", .{d.name});
        if (d.type_) |ty| {
            try self.builder.write(": ");
            try self.emitType(ty);
        }
        try self.builder.write(" = ");
        try self.emitExpr(d.init.*);
        try self.builder.write(";\n");

        if (d.add_discard) {
            try self.builder.writeIndent();
            try self.builder.writeFmt("_ = &{s};\n", .{d.name});
        }
    }

    fn emitVarUndef(self: *StatementBuilder, d: zig_statement.VarUndef) !void {
        try self.builder.writeIndent();
        try self.builder.writeFmt("var {s}: ", .{d.name});
        try self.emitType(d.type_);
        try self.builder.write(" = undefined;\n");

        if (d.add_discard) {
            try self.builder.writeIndent();
            try self.builder.writeFmt("_ = &{s};\n", .{d.name});
        }
    }

    // ========== Assignment Emission ==========

    fn emitAssign(self: *StatementBuilder, a: zig_statement.Assign) !void {
        try self.builder.writeIndent();
        try self.emitExpr(a.target.*);
        try self.builder.write(" = ");
        try self.emitExpr(a.value.*);
        try self.builder.write(";\n");
    }

    fn emitAugAssign(self: *StatementBuilder, a: zig_statement.AugAssign) !void {
        try self.builder.writeIndent();
        try self.emitExpr(a.target.*);
        try self.builder.writeFmt(" {s} ", .{a.op.toOperator()});
        try self.emitExpr(a.value.*);
        try self.builder.write(";\n");
    }

    fn emitFieldAssign(self: *StatementBuilder, a: zig_statement.FieldAssign) !void {
        try self.builder.writeIndent();
        try self.emitExpr(a.obj.*);
        try self.builder.writeFmt(".{s} = ", .{a.field});
        try self.emitExpr(a.value.*);
        try self.builder.write(";\n");
    }

    fn emitSubscriptAssign(self: *StatementBuilder, a: zig_statement.SubscriptAssign) !void {
        try self.builder.writeIndent();
        try self.emitExpr(a.container.*);
        try self.builder.write("[");
        try self.emitExpr(a.index.*);
        try self.builder.write("] = ");
        try self.emitExpr(a.value.*);
        try self.builder.write(";\n");
    }

    // ========== Control Flow Emission ==========

    fn emitIfStmt(self: *StatementBuilder, s: zig_statement.IfStmt) !void {
        try self.builder.writeIndent();
        try self.builder.write("if (");
        try self.emitExpr(s.condition.*);
        try self.builder.write(") {\n");
        self.builder.indent();

        for (s.then_body) |stmt| {
            try self.emitStmt(stmt);
        }

        // Else-if branches
        for (s.else_ifs) |elif| {
            self.builder.dedent();
            try self.builder.writeIndent();
            try self.builder.write("} else if (");
            try self.emitExpr(elif.condition.*);
            try self.builder.write(") {\n");
            self.builder.indent();

            for (elif.body) |stmt| {
                try self.emitStmt(stmt);
            }
        }

        // Else branch
        if (s.else_body) |else_body| {
            self.builder.dedent();
            try self.builder.writeIndent();
            try self.builder.write("} else {\n");
            self.builder.indent();

            for (else_body) |stmt| {
                try self.emitStmt(stmt);
            }
        }

        self.builder.dedent();
        try self.builder.writeIndent();
        try self.builder.write("}\n");
    }

    fn emitWhileLoop(self: *StatementBuilder, s: zig_statement.WhileLoop) !void {
        try self.builder.writeIndent();
        if (s.label) |label| {
            try self.builder.writeFmt("{s}: ", .{label});
        }
        try self.builder.write("while (");
        try self.emitExpr(s.condition.*);
        try self.builder.write(") {\n");
        self.builder.indent();

        for (s.body) |stmt| {
            try self.emitStmt(stmt);
        }

        self.builder.dedent();
        try self.builder.writeIndent();
        try self.builder.write("}\n");
    }

    fn emitForLoop(self: *StatementBuilder, s: zig_statement.ForLoop) !void {
        try self.builder.writeIndent();
        if (s.label) |label| {
            try self.builder.writeFmt("{s}: ", .{label});
        }
        try self.builder.write("for (");
        try self.emitExpr(s.iter.*);
        try self.builder.writeFmt(") |{s}| {{\n", .{s.capture});
        self.builder.indent();

        for (s.body) |stmt| {
            try self.emitStmt(stmt);
        }

        self.builder.dedent();
        try self.builder.writeIndent();
        try self.builder.write("}\n");
    }

    fn emitForIndexed(self: *StatementBuilder, s: zig_statement.ForIndexed) !void {
        try self.builder.writeIndent();
        if (s.label) |label| {
            try self.builder.writeFmt("{s}: ", .{label});
        }
        try self.builder.write("for (");
        try self.emitExpr(s.iter.*);
        try self.builder.writeFmt(", 0..) |{s}, {s}| {{\n", .{ s.capture, s.index });
        self.builder.indent();

        for (s.body) |stmt| {
            try self.emitStmt(stmt);
        }

        self.builder.dedent();
        try self.builder.writeIndent();
        try self.builder.write("}\n");
    }

    fn emitBreak(self: *StatementBuilder, b: zig_statement.Break) !void {
        try self.builder.writeIndent();
        try self.builder.write("break");
        if (b.label) |label| {
            try self.builder.writeFmt(" :{s}", .{label});
        }
        if (b.value) |val| {
            try self.builder.write(" ");
            try self.emitExpr(val.*);
        }
        try self.builder.write(";\n");
    }

    fn emitContinue(self: *StatementBuilder, c: zig_statement.Continue) !void {
        try self.builder.writeIndent();
        try self.builder.write("continue");
        if (c.label) |label| {
            try self.builder.writeFmt(" :{s}", .{label});
        }
        try self.builder.write(";\n");
    }

    fn emitReturn(self: *StatementBuilder, r: zig_statement.Return) !void {
        try self.builder.writeIndent();
        try self.builder.write("return");
        if (r.value) |val| {
            try self.builder.write(" ");
            try self.emitExpr(val.*);
        }
        try self.builder.write(";\n");
    }

    // ========== Error Handling Emission ==========

    fn emitDefer(self: *StatementBuilder, d: zig_statement.Defer) !void {
        try self.builder.writeIndent();
        try self.builder.write("defer ");
        try self.emitExpr(d.expr.*);
        try self.builder.write(";\n");
    }

    fn emitErrdefer(self: *StatementBuilder, e: zig_statement.Errdefer) !void {
        try self.builder.writeIndent();
        try self.builder.write("errdefer ");
        if (e.capture) |cap| {
            try self.builder.writeFmt("|{s}| ", .{cap});
        }
        try self.emitExpr(e.expr.*);
        try self.builder.write(";\n");
    }

    fn emitSwitch(self: *StatementBuilder, s: zig_statement.Switch) !void {
        try self.builder.writeIndent();
        try self.builder.write("switch (");
        try self.emitExpr(s.value.*);
        try self.builder.write(") {\n");
        self.builder.indent();

        for (s.prongs) |prong| {
            try self.builder.writeIndent();
            for (prong.cases, 0..) |case, i| {
                if (i > 0) try self.builder.write(", ");
                try self.emitExpr(case.*);
            }
            if (prong.capture) |cap| {
                try self.builder.writeFmt(" => |{s}| {{\n", .{cap});
            } else {
                try self.builder.write(" => {\n");
            }
            self.builder.indent();

            for (prong.body) |stmt| {
                try self.emitStmt(stmt);
            }

            self.builder.dedent();
            try self.builder.writeIndent();
            try self.builder.write("},\n");
        }

        if (s.else_prong) |else_body| {
            try self.builder.writeIndent();
            try self.builder.write("else => {\n");
            self.builder.indent();

            for (else_body) |stmt| {
                try self.emitStmt(stmt);
            }

            self.builder.dedent();
            try self.builder.writeIndent();
            try self.builder.write("},\n");
        }

        self.builder.dedent();
        try self.builder.writeIndent();
        try self.builder.write("}\n");
    }

    // ========== Expression Statement Emission ==========

    fn emitExprStmt(self: *StatementBuilder, e: zig_statement.ExprStmt) !void {
        try self.builder.writeIndent();
        if (e.use_try) {
            try self.builder.write("try ");
        }
        try self.emitExpr(e.expr.*);
        try self.builder.write(";\n");
    }

    fn emitDiscardStmt(self: *StatementBuilder, d: zig_statement.DiscardStmt) !void {
        try self.builder.writeIndent();
        try self.builder.write("_ = ");
        if (d.use_try) {
            try self.builder.write("try ");
        }
        try self.emitExpr(d.expr.*);
        try self.builder.write(";\n");
    }

    // ========== Scope Emission ==========

    fn emitBlock(self: *StatementBuilder, b: zig_statement.Block) !void {
        try self.builder.writeIndent();
        if (b.label) |label| {
            try self.builder.writeFmt("{s}: ", .{label});
        }
        try self.builder.write("{\n");
        self.builder.indent();

        for (b.body) |stmt| {
            try self.emitStmt(stmt);
        }

        self.builder.dedent();
        try self.builder.writeIndent();
        try self.builder.write("}\n");
    }

    fn emitInlineFor(self: *StatementBuilder, f: zig_statement.InlineFor) !void {
        try self.builder.writeIndent();
        try self.builder.write("inline for (");
        try self.emitExpr(f.iter.*);
        if (f.index) |idx| {
            try self.builder.writeFmt(", 0..) |{s}, {s}| {{\n", .{ f.capture, idx });
        } else {
            try self.builder.writeFmt(") |{s}| {{\n", .{f.capture});
        }
        self.builder.indent();

        for (f.body) |stmt| {
            try self.emitStmt(stmt);
        }

        self.builder.dedent();
        try self.builder.writeIndent();
        try self.builder.write("}\n");
    }

    // ========== Meta Emission ==========

    fn emitComment(self: *StatementBuilder, c: zig_statement.Comment) !void {
        try self.builder.writeIndent();
        if (c.is_doc) {
            try self.builder.write("/// ");
        } else {
            try self.builder.write("// ");
        }
        try self.builder.write(c.text);
        try self.builder.write("\n");
    }

    fn emitRaw(self: *StatementBuilder, r: zig_statement.Raw) !void {
        try self.builder.writeIndent();
        try self.builder.write(r.code);
        if (r.add_newline) {
            try self.builder.write("\n");
        }
    }

    // ========== Expression Emission Helpers ==========

    fn emitBinary(self: *StatementBuilder, b: Binary) !void {
        // Check for unified comparison dispatch
        if (b.isComparison()) {
            if (b.useRuntime()) {
                // Runtime dispatch
                try self.emitRuntimeComparison(b);
            } else {
                // Native dispatch
                try self.emitNativeComparison(b);
            }
            return;
        }

        // Non-comparison binary
        if (b.toOperator()) |op_str| {
            try self.builder.write("(");
            try self.emitExpr(b.left.*);
            try self.builder.writeFmt(" {s} ", .{op_str});
            try self.emitExpr(b.right.*);
            try self.builder.write(")");
        } else {
            // Operators without direct Zig equivalent need runtime helpers
            try self.emitRuntimeBinary(b);
        }
    }

    fn emitNativeComparison(self: *StatementBuilder, b: Binary) !void {
        const left_type = b.left.certainType();

        if (left_type == .string) {
            // String comparison uses std.mem.eql
            if (b.op == .ne) try self.builder.write("!");
            try self.builder.write("std.mem.eql(u8, ");
            try self.emitExpr(b.left.*);
            try self.builder.write(", ");
            try self.emitExpr(b.right.*);
            try self.builder.write(")");
        } else {
            // Numeric/bool comparison uses direct operators
            try self.builder.write("(");
            try self.emitExpr(b.left.*);
            try self.builder.writeFmt(" {s} ", .{b.toOperator().?});
            try self.emitExpr(b.right.*);
            try self.builder.write(")");
        }
    }

    fn emitRuntimeComparison(self: *StatementBuilder, b: Binary) !void {
        switch (b.op) {
            .eq => {
                try self.builder.write("runtime.PyValue.from(");
                try self.emitExpr(b.left.*);
                try self.builder.write(").eql(runtime.PyValue.from(");
                try self.emitExpr(b.right.*);
                try self.builder.write("))");
            },
            .ne => {
                try self.builder.write("!runtime.PyValue.from(");
                try self.emitExpr(b.left.*);
                try self.builder.write(").eql(runtime.PyValue.from(");
                try self.emitExpr(b.right.*);
                try self.builder.write("))");
            },
            .lt, .le, .gt, .ge => {
                const method = switch (b.op) {
                    .lt => "lt",
                    .le => "le",
                    .gt => "gt",
                    .ge => "ge",
                    else => unreachable,
                };
                try self.builder.write("runtime.PyValue.from(");
                try self.emitExpr(b.left.*);
                try self.builder.writeFmt(").{s}(runtime.PyValue.from(", .{method});
                try self.emitExpr(b.right.*);
                try self.builder.write("))");
            },
            else => {}, // Other comparisons handled elsewhere
        }
    }

    fn emitRuntimeBinary(self: *StatementBuilder, b: Binary) !void {
        const helper = switch (b.op) {
            .floor_div => "runtime.pyFloorDiv",
            .pow => "runtime.pyPow",
            .in => "runtime.pyContains",
            .not_in => "!runtime.pyContains",
            .is => "runtime.pyIdentical",
            .is_not => "!runtime.pyIdentical",
            else => {
                // Fallback to operator emission
                try self.builder.write("(");
                try self.emitExpr(b.left.*);
                try self.builder.writeFmt(" {s} ", .{b.toOperator() orelse "?"});
                try self.emitExpr(b.right.*);
                try self.builder.write(")");
                return;
            },
        };
        try self.builder.writeFmt("{s}(", .{helper});
        try self.emitExpr(b.left.*);
        try self.builder.write(", ");
        try self.emitExpr(b.right.*);
        try self.builder.write(")");
    }

    fn emitUnary(self: *StatementBuilder, u: Unary) !void {
        try self.builder.writeFmt("{s}(", .{u.op.toOperator()});
        try self.emitExpr(u.operand.*);
        try self.builder.write(")");
    }

    fn emitField(self: *StatementBuilder, f: zig_expr.Field) !void {
        try self.emitExpr(f.obj.*);
        try self.builder.writeFmt(".{s}", .{f.field});
    }

    fn emitSubscript(self: *StatementBuilder, s: zig_expr.Subscript) !void {
        try self.emitExpr(s.container.*);
        try self.builder.write("[");
        try self.emitExpr(s.index.*);
        try self.builder.write("]");
    }

    fn emitSlice(self: *StatementBuilder, s: zig_expr.Slice) !void {
        try self.emitExpr(s.container.*);
        try self.builder.write("[");
        if (s.start) |start| {
            try self.emitExpr(start.*);
        }
        try self.builder.write("..");
        if (s.end) |end| {
            try self.emitExpr(end.*);
        }
        try self.builder.write("]");
    }

    fn emitCall(self: *StatementBuilder, c: zig_expr.Call) !void {
        try self.emitExpr(c.func.*);
        try self.builder.write("(");
        for (c.args, 0..) |arg, i| {
            if (i > 0) try self.builder.write(", ");
            try self.emitExpr(arg.*);
        }
        try self.builder.write(")");
    }

    fn emitMethodCallExpr(self: *StatementBuilder, m: zig_expr.MethodCall) !void {
        try self.emitExpr(m.receiver.*);
        try self.builder.writeFmt(".{s}(", .{m.method});
        for (m.args, 0..) |arg, i| {
            if (i > 0) try self.builder.write(", ");
            try self.emitExpr(arg.*);
        }
        try self.builder.write(")");
    }

    fn emitBuiltinCall(self: *StatementBuilder, b: zig_expr.BuiltinCall) !void {
        try self.builder.writeFmt("@{s}(", .{b.builtin});
        if (b.type_arg) |ty| {
            try self.emitType(ty);
            if (b.args.len > 0) {
                try self.builder.write(", ");
            }
        }
        for (b.args, 0..) |arg, i| {
            if (i > 0) try self.builder.write(", ");
            try self.emitExpr(arg.*);
        }
        try self.builder.write(")");
    }

    fn emitStructLiteral(self: *StatementBuilder, s: zig_expr.StructLiteral) !void {
        if (s.type_name) |tn| {
            try self.builder.write(tn);
        }
        try self.builder.write(".{ ");
        for (s.fields, 0..) |f, i| {
            if (i > 0) try self.builder.write(", ");
            try self.builder.writeFmt(".{s} = ", .{f.name});
            try self.emitExpr(f.value.*);
        }
        try self.builder.write(" }");
    }

    fn emitArrayLiteral(self: *StatementBuilder, a: zig_expr.ArrayLiteral) !void {
        try self.builder.write(".{ ");
        for (a.elements, 0..) |elem, i| {
            if (i > 0) try self.builder.write(", ");
            try self.emitExpr(elem.*);
        }
        try self.builder.write(" }");
    }

    fn emitTernary(self: *StatementBuilder, t: zig_expr.Ternary) !void {
        try self.builder.write("if (");
        try self.emitExpr(t.condition.*);
        try self.builder.write(") ");
        try self.emitExpr(t.then_expr.*);
        try self.builder.write(" else ");
        try self.emitExpr(t.else_expr.*);
    }

    fn emitLabeledBlockExpr(self: *StatementBuilder, lb: zig_expr.LabeledBlock) !void {
        try self.builder.writeFmt("{s}: {{ ", .{lb.label});
        try self.builder.write(lb.body); // TODO: Use []const ZigStatement when integrated
        if (lb.break_value) |val| {
            try self.builder.writeFmt("break :{s} ", .{lb.label});
            try self.emitExpr(val.*);
            try self.builder.write("; ");
        }
        try self.builder.write("}");
    }

    fn emitTry(self: *StatementBuilder, t: zig_expr.Try) !void {
        try self.builder.write("try ");
        try self.emitExpr(t.expr.*);
    }

    fn emitCatch(self: *StatementBuilder, c: zig_expr.Catch) !void {
        try self.emitExpr(c.expr.*);
        try self.builder.write(" catch ");
        if (c.capture) |cap| {
            try self.builder.writeFmt("|{s}| ", .{cap});
        }
        try self.emitExpr(c.handler.*);
    }

    fn emitOrelse(self: *StatementBuilder, o: zig_expr.Orelse) !void {
        try self.emitExpr(o.expr.*);
        try self.builder.write(" orelse ");
        try self.emitExpr(o.default.*);
    }

    fn emitAddressOf(self: *StatementBuilder, a: zig_expr.AddressOf) !void {
        try self.builder.write("&");
        try self.emitExpr(a.expr.*);
    }

    fn emitDeref(self: *StatementBuilder, d: zig_expr.Deref) !void {
        try self.emitExpr(d.expr.*);
        try self.builder.write(".*");
    }

    fn emitCast(self: *StatementBuilder, c: zig_expr.Cast) !void {
        switch (c.kind) {
            .as => {
                try self.builder.write("@as(");
                try self.emitType(c.target_type);
                try self.builder.write(", ");
                try self.emitExpr(c.expr.*);
                try self.builder.write(")");
            },
            .int_cast => {
                try self.builder.write("@intCast(");
                try self.emitExpr(c.expr.*);
                try self.builder.write(")");
            },
            .float_cast => {
                try self.builder.write("@floatCast(");
                try self.emitExpr(c.expr.*);
                try self.builder.write(")");
            },
            .int_from_float => {
                try self.builder.write("@intFromFloat(");
                try self.emitExpr(c.expr.*);
                try self.builder.write(")");
            },
            .float_from_int => {
                try self.builder.write("@floatFromInt(");
                try self.emitExpr(c.expr.*);
                try self.builder.write(")");
            },
            .ptr_cast => {
                try self.builder.write("@ptrCast(");
                try self.emitExpr(c.expr.*);
                try self.builder.write(")");
            },
            .align_cast => {
                try self.builder.write("@alignCast(");
                try self.emitExpr(c.expr.*);
                try self.builder.write(")");
            },
            .truncate => {
                try self.builder.write("@truncate(");
                try self.emitExpr(c.expr.*);
                try self.builder.write(")");
            },
            .bit_cast => {
                try self.builder.write("@bitCast(");
                try self.emitExpr(c.expr.*);
                try self.builder.write(")");
            },
        }
    }

    fn emitCoerce(self: *StatementBuilder, c: zig_expr.Coerce) !void {
        try self.emitExpr(c.expr.*);
    }

    fn emitType(self: *StatementBuilder, ty: *const ZigType) !void {
        var buf: std.ArrayList(u8) = .{};
        defer buf.deinit(self.allocator);
        try ty.emit(buf.writer(self.allocator));
        try self.builder.write(buf.items);
    }

    // ========================================================================
    // Assertion Helpers (use unified comparison internally)
    // ========================================================================

    /// Emit assertEqual using unified comparison dispatch
    pub fn emitAssertEqual(self: *StatementBuilder, left: ZigExpr, right: ZigExpr) !void {
        const cmp = try self.createComparison(.eq, left, right);
        try self.builder.writeIndent();
        try self.builder.write("if (!");
        try self.emitExpr(cmp);
        try self.builder.write(") return error.AssertionFailed;\n");
    }

    /// Emit assertNotEqual using unified comparison dispatch
    pub fn emitAssertNotEqual(self: *StatementBuilder, left: ZigExpr, right: ZigExpr) !void {
        const cmp = try self.createComparison(.eq, left, right);
        try self.builder.writeIndent();
        try self.builder.write("if (");
        try self.emitExpr(cmp);
        try self.builder.write(") return error.AssertionFailed;\n");
    }

    /// Emit assertTrue
    pub fn emitAssertTrue(self: *StatementBuilder, value: ZigExpr) !void {
        try self.builder.writeIndent();
        try self.builder.write("if (!");
        try self.emitToBool(value);
        try self.builder.write(") return error.AssertionFailed;\n");
    }

    /// Emit assertFalse
    pub fn emitAssertFalse(self: *StatementBuilder, value: ZigExpr) !void {
        try self.builder.writeIndent();
        try self.builder.write("if (");
        try self.emitToBool(value);
        try self.builder.write(") return error.AssertionFailed;\n");
    }

    fn emitToBool(self: *StatementBuilder, expr: ZigExpr) !void {
        switch (expr) {
            .value => |v| switch (v) {
                .certain_bool => |b| try self.builder.writeFmt("{}", .{b}),
                .certain_int => |i| try self.builder.writeFmt("({d} != 0)", .{i}),
                .certain_float => |f| try self.builder.writeFmt("({d} != 0.0)", .{f}),
                .certain_str => |s| try self.builder.writeFmt("({d} > 0)", .{s.len}),
                .certain_bytes => |s| try self.builder.writeFmt("({d} > 0)", .{s.len}),
                .certain_null => try self.builder.write("false"),
                else => {
                    try self.builder.write("runtime.toBool(");
                    try self.emitExpr(expr);
                    try self.builder.write(")");
                },
            },
            else => {
                try self.builder.write("runtime.toBool(");
                try self.emitExpr(expr);
                try self.builder.write(")");
            },
        }
    }
};

// ========================================================================
// Tests
// ========================================================================

test "StatementBuilder basic expressions" {
    const testing = std.testing;
    var builder = try ZigBuilder.init(testing.allocator);
    defer builder.deinit();

    var sb = StatementBuilder.init(testing.allocator, &builder);
    defer sb.deinit();

    // Test integer literal
    const int_expr = sb.int(42);
    try testing.expectEqual(TypeConfidence.certain, int_expr.confidence());

    // Test name reference
    const name_expr = sb.name("x");
    try testing.expect(name_expr.isName());
}

test "StatementBuilder unified comparison dispatch - native" {
    const testing = std.testing;
    var builder = try ZigBuilder.init(testing.allocator);
    defer builder.deinit();

    var sb = StatementBuilder.init(testing.allocator, &builder);
    defer sb.deinit();

    // Same type, both certain -> native dispatch
    const left = sb.int(1);
    const right = sb.int(2);
    const cmp = try sb.createComparison(.eq, left, right);

    try testing.expect(cmp == .binary);
    try testing.expectEqual(ResultType.native, cmp.binary.dispatch);
    try testing.expect(!cmp.binary.useRuntime());
}

test "StatementBuilder unified comparison dispatch - runtime" {
    const testing = std.testing;
    var builder = try ZigBuilder.init(testing.allocator);
    defer builder.deinit();

    var sb = StatementBuilder.init(testing.allocator, &builder);
    defer sb.deinit();

    // Different types -> runtime dispatch
    const left = sb.int(1);
    const right = sb.string("hello");
    const cmp = try sb.createComparison(.eq, left, right);

    try testing.expect(cmp == .binary);
    try testing.expectEqual(ResultType.runtime, cmp.binary.dispatch);
    try testing.expect(cmp.binary.useRuntime());
}

test "StatementBuilder expression emission" {
    const testing = std.testing;
    var builder = try ZigBuilder.init(testing.allocator);
    defer builder.deinit();

    var sb = StatementBuilder.init(testing.allocator, &builder);
    defer sb.deinit();

    // Test binary expression emission
    const left = sb.int(1);
    const right = sb.int(2);
    const add_expr = try sb.add(left, right);

    try sb.emitExpr(add_expr);

    const output = builder.getBody();
    try testing.expect(std.mem.indexOf(u8, output, "(1 + 2)") != null);
}

test "StatementBuilder const declaration emission" {
    const testing = std.testing;
    var builder = try ZigBuilder.init(testing.allocator);
    defer builder.deinit();

    var sb = StatementBuilder.init(testing.allocator, &builder);
    defer sb.deinit();

    const init_expr = sb.int(42);
    const stmt = zig_statement.constDecl("x", try sb.alloc(init_expr));

    try sb.emitStmt(stmt);

    const output = builder.getBody();
    try testing.expect(std.mem.indexOf(u8, output, "const x = 42;") != null);
}

test "StatementBuilder assertEqual uses unified comparison" {
    const testing = std.testing;
    var builder = try ZigBuilder.init(testing.allocator);
    defer builder.deinit();

    var sb = StatementBuilder.init(testing.allocator, &builder);
    defer sb.deinit();

    // Same type int comparison -> native
    try sb.emitAssertEqual(sb.int(1), sb.int(2));

    const output = builder.getBody();
    // Should use native comparison
    try testing.expect(std.mem.indexOf(u8, output, "((1) == (2))") != null);
}

test "StatementBuilder if statement emission" {
    const testing = std.testing;
    var builder = try ZigBuilder.init(testing.allocator);
    defer builder.deinit();

    var sb = StatementBuilder.init(testing.allocator, &builder);
    defer sb.deinit();

    const cond = sb.boolean(true);
    const body_stmt = zig_statement.ret(null);

    const if_stmt = ZigStatement{ .if_stmt = .{
        .condition = try sb.alloc(cond),
        .then_body = &[_]ZigStatement{body_stmt},
    } };

    try sb.emitStmt(if_stmt);

    const output = builder.getBody();
    try testing.expect(std.mem.indexOf(u8, output, "if (true)") != null);
    try testing.expect(std.mem.indexOf(u8, output, "return;") != null);
}
