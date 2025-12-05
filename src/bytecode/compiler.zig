/// Bytecode Compiler - Compiles Python AST to bytecode
///
/// Reuses metal0's existing parser (src/parser/) instead of duplicating.
/// Converts AST nodes to stack-based bytecode instructions.
const std = @import("std");
const opcode = @import("opcode.zig");
const ast = @import("../ast.zig");

const OpCode = opcode.OpCode;
const Instruction = opcode.Instruction;
const Value = opcode.Value;
const Program = opcode.Program;
const SourceLoc = opcode.SourceLoc;

/// Bytecode compiler state
pub const Compiler = struct {
    allocator: std.mem.Allocator,
    /// Emitted instructions
    instructions: std.ArrayList(Instruction),
    /// Constant pool
    constants: std.ArrayList(Value),
    /// Local variable names
    varnames: std.ArrayList([]const u8),
    /// Global/free variable names
    names: std.ArrayList([]const u8),
    /// Source locations for error messages
    source_map: std.ArrayList(SourceLoc),
    /// Current scope depth
    scope_depth: u32,
    /// Loop stack for break/continue
    loop_stack: std.ArrayList(LoopContext),
    /// Try stack for exception handling
    try_stack: std.ArrayList(TryContext),

    const LoopContext = struct {
        start: u32,
        break_jumps: std.ArrayList(u32),
        continue_jumps: std.ArrayList(u32),
    };

    const TryContext = struct {
        handler_addr: u32,
        finally_addr: ?u32,
    };

    pub fn init(allocator: std.mem.Allocator) Compiler {
        return .{
            .allocator = allocator,
            .instructions = std.ArrayList(Instruction).init(allocator),
            .constants = std.ArrayList(Value).init(allocator),
            .varnames = std.ArrayList([]const u8).init(allocator),
            .names = std.ArrayList([]const u8).init(allocator),
            .source_map = std.ArrayList(SourceLoc).init(allocator),
            .scope_depth = 0,
            .loop_stack = std.ArrayList(LoopContext).init(allocator),
            .try_stack = std.ArrayList(TryContext).init(allocator),
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.instructions.deinit();
        // Constants may have allocated strings - handled by Program.deinit
        self.constants.deinit();
        self.varnames.deinit();
        self.names.deinit();
        self.source_map.deinit();
        for (self.loop_stack.items) |*loop| {
            loop.break_jumps.deinit();
            loop.continue_jumps.deinit();
        }
        self.loop_stack.deinit();
        self.try_stack.deinit();
    }

    /// Compile a list of statements (module body)
    pub fn compileModule(self: *Compiler, stmts: []const ast.Node, filename: []const u8) !*Program {
        for (stmts) |stmt| {
            try self.compileStmt(stmt);
        }

        // Add implicit return None at end
        try self.emit(.LOAD_CONST, try self.addConstant(.none));
        try self.emit(.RETURN_VALUE, 0);

        return self.finalize(filename, "<module>");
    }

    /// Compile a single expression (for eval())
    pub fn compileExpr(self: *Compiler, expr: ast.Node, filename: []const u8) !*Program {
        try self.compileExpression(expr);
        try self.emit(.RETURN_VALUE, 0);
        return self.finalize(filename, "<expr>");
    }

    /// Finalize compilation and return Program
    fn finalize(self: *Compiler, filename: []const u8, name: []const u8) !*Program {
        const program = try self.allocator.create(Program);
        program.* = .{
            .instructions = try self.instructions.toOwnedSlice(),
            .constants = try self.constants.toOwnedSlice(),
            .varnames = try self.varnames.toOwnedSlice(),
            .names = try self.names.toOwnedSlice(),
            .cellvars = &.{},
            .freevars = &.{},
            .source_map = try self.source_map.toOwnedSlice(),
            .filename = try self.allocator.dupe(u8, filename),
            .name = try self.allocator.dupe(u8, name),
            .firstlineno = if (self.source_map.items.len > 0) self.source_map.items[0].line else 1,
            .argcount = 0,
            .posonlyargcount = 0,
            .kwonlyargcount = 0,
            .stacksize = 256, // TODO: calculate from stack effects
            .flags = .{},
        };
        return program;
    }

    /// Emit a single instruction
    fn emit(self: *Compiler, op: OpCode, arg: u24) !void {
        try self.instructions.append(self.allocator, Instruction.init(op, arg));
    }

    /// Current instruction offset
    fn currentOffset(self: *Compiler) u32 {
        return @intCast(self.instructions.items.len);
    }

    /// Add source location for current instruction
    fn addSourceLoc(self: *Compiler, line: u32) !void {
        try self.source_map.append(self.allocator, .{
            .line = line,
            .offset = self.currentOffset(),
        });
    }

    /// Add a constant to the pool, return its index
    fn addConstant(self: *Compiler, value: Value) !u24 {
        // Check if constant already exists
        for (self.constants.items, 0..) |c, i| {
            if (valueEqual(c, value)) {
                return @intCast(i);
            }
        }
        const idx = self.constants.items.len;
        try self.constants.append(self.allocator, value);
        return @intCast(idx);
    }

    /// Add a name to the names list, return its index
    fn addName(self: *Compiler, name: []const u8) !u24 {
        for (self.names.items, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) {
                return @intCast(i);
            }
        }
        const idx = self.names.items.len;
        try self.names.append(self.allocator, try self.allocator.dupe(u8, name));
        return @intCast(idx);
    }

    /// Add a local variable name
    fn addVarname(self: *Compiler, name: []const u8) !u24 {
        for (self.varnames.items, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) {
                return @intCast(i);
            }
        }
        const idx = self.varnames.items.len;
        try self.varnames.append(self.allocator, try self.allocator.dupe(u8, name));
        return @intCast(idx);
    }

    // ========== Statement Compilation ==========

    fn compileStmt(self: *Compiler, node: ast.Node) anyerror!void {
        switch (node) {
            .Expr => |expr| {
                try self.compileExpression(expr.expression.*);
                try self.emit(.POP_TOP, 0);
            },
            .Assign => |assign| try self.compileAssign(assign),
            .AugmentedAssign => |aug| try self.compileAugAssign(aug),
            .If => |if_stmt| try self.compileIf(if_stmt),
            .While => |while_stmt| try self.compileWhile(while_stmt),
            .For => |for_stmt| try self.compileFor(for_stmt),
            .FunctionDef => |func| try self.compileFunctionDef(func),
            .Return => |ret| try self.compileReturn(ret),
            .Pass => {}, // No-op
            .Break => try self.compileBreak(),
            .Continue => try self.compileContinue(),
            .Raise => |raise| try self.compileRaise(raise),
            .Try => |try_stmt| try self.compileTry(try_stmt),
            .Import => |imp| try self.compileImport(imp),
            .ImportFrom => |imp| try self.compileImportFrom(imp),
            .Global, .Nonlocal => {}, // Handled during analysis
            .ClassDef => |cls| try self.compileClassDef(cls),
            .Delete => |del| try self.compileDelete(del),
            .Assert => |assert| try self.compileAssert(assert),
            .With => |with| try self.compileWith(with),
            else => return error.UnsupportedStatement,
        }
    }

    fn compileAssign(self: *Compiler, assign: ast.Node.Assign) !void {
        // Compile value
        try self.compileExpression(assign.value.*);

        // Store to each target (may need DUP_TOP for multiple)
        for (assign.targets, 0..) |target, i| {
            if (i < assign.targets.len - 1) {
                try self.emit(.DUP_TOP, 0);
            }
            try self.compileStore(target);
        }
    }

    fn compileAugAssign(self: *Compiler, aug: ast.Node.AugmentedAssign) !void {
        // Load target
        try self.compileExpression(aug.target.*);
        // Load value
        try self.compileExpression(aug.value.*);
        // Apply operator
        const op: OpCode = switch (aug.operator) {
            .Add => .INPLACE_ADD,
            .Sub => .INPLACE_SUBTRACT,
            .Mult => .INPLACE_MULTIPLY,
            .Div => .INPLACE_TRUE_DIVIDE,
            .FloorDiv => .INPLACE_FLOOR_DIVIDE,
            .Mod => .INPLACE_MODULO,
            .Pow => .INPLACE_POWER,
            .LShift => .INPLACE_LSHIFT,
            .RShift => .INPLACE_RSHIFT,
            .BitAnd => .INPLACE_AND,
            .BitOr => .INPLACE_OR,
            .BitXor => .INPLACE_XOR,
            else => return error.UnsupportedOperator,
        };
        try self.emit(op, 0);
        // Store back
        try self.compileStore(aug.target.*);
    }

    fn compileStore(self: *Compiler, target: ast.Node) !void {
        switch (target) {
            .Name => |name| {
                const idx = try self.addName(name.id);
                try self.emit(.STORE_NAME, idx);
            },
            .Attribute => |attr| {
                try self.compileExpression(attr.object.*);
                const idx = try self.addName(attr.attribute);
                try self.emit(.STORE_ATTR, idx);
            },
            .Subscript => |sub| {
                try self.compileExpression(sub.object.*);
                try self.compileExpression(sub.index.*);
                try self.emit(.STORE_SUBSCR, 0);
            },
            .Tuple, .List => |list| {
                // Unpack sequence
                try self.emit(.UNPACK_SEQUENCE, @intCast(list.elements.len));
                for (list.elements) |elem| {
                    try self.compileStore(elem.*);
                }
            },
            else => return error.InvalidStoreTarget,
        }
    }

    fn compileIf(self: *Compiler, if_stmt: ast.Node.If) !void {
        // Compile condition
        try self.compileExpression(if_stmt.condition.*);

        // Jump to else if false
        const else_jump = self.currentOffset();
        try self.emit(.POP_JUMP_IF_FALSE, 0); // Placeholder

        // Compile if body
        for (if_stmt.body) |stmt| {
            try self.compileStmt(stmt);
        }

        if (if_stmt.else_body.len > 0) {
            // Jump over else
            const end_jump = self.currentOffset();
            try self.emit(.JUMP_FORWARD, 0); // Placeholder

            // Patch else jump
            self.instructions.items[else_jump].arg = self.currentOffset();

            // Compile else body
            for (if_stmt.else_body) |stmt| {
                try self.compileStmt(stmt);
            }

            // Patch end jump
            self.instructions.items[end_jump].arg = self.currentOffset() - end_jump - 1;
        } else {
            // Patch else jump to here
            self.instructions.items[else_jump].arg = self.currentOffset();
        }
    }

    fn compileWhile(self: *Compiler, while_stmt: ast.Node.While) !void {
        const loop_start = self.currentOffset();

        // Push loop context
        var loop_ctx = LoopContext{
            .start = loop_start,
            .break_jumps = std.ArrayList(u32).init(self.allocator),
            .continue_jumps = std.ArrayList(u32).init(self.allocator),
        };
        try self.loop_stack.append(self.allocator, loop_ctx);

        // Compile condition
        try self.compileExpression(while_stmt.condition.*);

        // Jump to end if false
        const end_jump = self.currentOffset();
        try self.emit(.POP_JUMP_IF_FALSE, 0);

        // Compile body
        for (while_stmt.body) |stmt| {
            try self.compileStmt(stmt);
        }

        // Jump back to start
        try self.emit(.JUMP_ABSOLUTE, loop_start);

        // Patch end jump
        const end_addr = self.currentOffset();
        self.instructions.items[end_jump].arg = end_addr;

        // Pop loop context and patch break/continue
        _ = self.loop_stack.pop();
        for (loop_ctx.break_jumps.items) |addr| {
            self.instructions.items[addr].arg = end_addr;
        }
        for (loop_ctx.continue_jumps.items) |addr| {
            self.instructions.items[addr].arg = loop_start;
        }
        loop_ctx.break_jumps.deinit();
        loop_ctx.continue_jumps.deinit();
    }

    fn compileFor(self: *Compiler, for_stmt: ast.Node.For) !void {
        // Get iterator
        try self.compileExpression(for_stmt.iterable.*);
        try self.emit(.GET_ITER, 0);

        const loop_start = self.currentOffset();

        // Push loop context
        var loop_ctx = LoopContext{
            .start = loop_start,
            .break_jumps = std.ArrayList(u32).init(self.allocator),
            .continue_jumps = std.ArrayList(u32).init(self.allocator),
        };
        try self.loop_stack.append(self.allocator, loop_ctx);

        // Get next item (jumps to end on StopIteration)
        const iter_jump = self.currentOffset();
        try self.emit(.FOR_ITER, 0);

        // Store to target
        try self.compileStore(for_stmt.target.*);

        // Compile body
        for (for_stmt.body) |stmt| {
            try self.compileStmt(stmt);
        }

        // Jump back
        try self.emit(.JUMP_ABSOLUTE, loop_start);

        // Patch FOR_ITER jump
        const end_addr = self.currentOffset();
        self.instructions.items[iter_jump].arg = end_addr;

        // Pop loop context
        _ = self.loop_stack.pop();
        for (loop_ctx.break_jumps.items) |addr| {
            self.instructions.items[addr].arg = end_addr;
        }
        for (loop_ctx.continue_jumps.items) |addr| {
            self.instructions.items[addr].arg = loop_start;
        }
        loop_ctx.break_jumps.deinit();
        loop_ctx.continue_jumps.deinit();
    }

    fn compileBreak(self: *Compiler) !void {
        if (self.loop_stack.items.len == 0) return error.BreakOutsideLoop;
        const addr = self.currentOffset();
        try self.emit(.JUMP_ABSOLUTE, 0); // Will be patched
        try self.loop_stack.items[self.loop_stack.items.len - 1].break_jumps.append(self.allocator, addr);
    }

    fn compileContinue(self: *Compiler) !void {
        if (self.loop_stack.items.len == 0) return error.ContinueOutsideLoop;
        const addr = self.currentOffset();
        try self.emit(.JUMP_ABSOLUTE, 0); // Will be patched
        try self.loop_stack.items[self.loop_stack.items.len - 1].continue_jumps.append(self.allocator, addr);
    }

    fn compileReturn(self: *Compiler, ret: ast.Node.Return) !void {
        if (ret.value) |val| {
            try self.compileExpression(val.*);
        } else {
            try self.emit(.LOAD_CONST, try self.addConstant(.none));
        }
        try self.emit(.RETURN_VALUE, 0);
    }

    fn compileRaise(self: *Compiler, raise: ast.Node.Raise) !void {
        var argc: u24 = 0;
        if (raise.exception) |exc| {
            try self.compileExpression(exc.*);
            argc = 1;
            if (raise.cause) |cause| {
                try self.compileExpression(cause.*);
                argc = 2;
            }
        }
        try self.emit(.RAISE_VARARGS, argc);
    }

    fn compileTry(self: *Compiler, try_stmt: ast.Node.Try) !void {
        // Setup exception handler
        const handler_jump = self.currentOffset();
        try self.emit(.SETUP_EXCEPT, 0);

        // Compile try body
        for (try_stmt.body) |stmt| {
            try self.compileStmt(stmt);
        }

        // Pop exception block
        try self.emit(.POP_EXCEPT, 0);

        // Jump to end
        const end_jump = self.currentOffset();
        try self.emit(.JUMP_FORWARD, 0);

        // Patch handler jump
        self.instructions.items[handler_jump].arg = self.currentOffset();

        // Compile handlers
        for (try_stmt.handlers) |handler| {
            // TODO: match exception type
            _ = handler;
        }

        // Compile finally if present
        if (try_stmt.finalbody.len > 0) {
            for (try_stmt.finalbody) |stmt| {
                try self.compileStmt(stmt);
            }
        }

        // Patch end jump
        self.instructions.items[end_jump].arg = self.currentOffset() - end_jump - 1;
    }

    fn compileFunctionDef(self: *Compiler, func: ast.Node.FunctionDef) !void {
        _ = self;
        _ = func;
        // TODO: compile function body to nested Program
        // For now, skip function definitions in eval context
        return error.UnsupportedStatement;
    }

    fn compileClassDef(self: *Compiler, cls: ast.Node.ClassDef) !void {
        _ = self;
        _ = cls;
        // TODO: compile class
        return error.UnsupportedStatement;
    }

    fn compileImport(self: *Compiler, imp: ast.Node.Import) !void {
        for (imp.names) |alias| {
            const name_idx = try self.addName(alias.name);
            try self.emit(.IMPORT_NAME, name_idx);
            if (alias.alias) |as_name| {
                const as_idx = try self.addName(as_name);
                try self.emit(.STORE_NAME, as_idx);
            } else {
                try self.emit(.STORE_NAME, name_idx);
            }
        }
    }

    fn compileImportFrom(self: *Compiler, imp: ast.Node.ImportFrom) !void {
        const mod_idx = try self.addName(imp.module orelse "");
        try self.emit(.IMPORT_NAME, mod_idx);
        for (imp.names) |alias| {
            const name_idx = try self.addName(alias.name);
            try self.emit(.IMPORT_FROM, name_idx);
            const store_name = alias.alias orelse alias.name;
            const store_idx = try self.addName(store_name);
            try self.emit(.STORE_NAME, store_idx);
        }
        try self.emit(.POP_TOP, 0);
    }

    fn compileDelete(self: *Compiler, del: ast.Node.Delete) !void {
        for (del.targets) |target| {
            switch (target.*) {
                .Name => |name| {
                    const idx = try self.addName(name.id);
                    try self.emit(.DELETE_NAME, idx);
                },
                .Attribute => |attr| {
                    try self.compileExpression(attr.object.*);
                    const idx = try self.addName(attr.attribute);
                    try self.emit(.DELETE_ATTR, idx);
                },
                .Subscript => |sub| {
                    try self.compileExpression(sub.object.*);
                    try self.compileExpression(sub.index.*);
                    try self.emit(.DELETE_SUBSCR, 0);
                },
                else => return error.InvalidDeleteTarget,
            }
        }
    }

    fn compileAssert(self: *Compiler, assert: ast.Node.Assert) !void {
        try self.compileExpression(assert.condition.*);
        const skip_jump = self.currentOffset();
        try self.emit(.POP_JUMP_IF_TRUE, 0);

        // Raise AssertionError
        const exc_idx = try self.addName("AssertionError");
        try self.emit(.LOAD_NAME, exc_idx);
        if (assert.message) |msg| {
            try self.compileExpression(msg.*);
            try self.emit(.CALL_FUNCTION, 1);
        } else {
            try self.emit(.CALL_FUNCTION, 0);
        }
        try self.emit(.RAISE_VARARGS, 1);

        self.instructions.items[skip_jump].arg = self.currentOffset();
    }

    fn compileWith(self: *Compiler, with: ast.Node.With) !void {
        // Compile context manager
        try self.compileExpression(with.items[0].context.*);
        try self.emit(.SETUP_WITH, 0);

        // Store to target if present
        if (with.items[0].target) |target| {
            try self.compileStore(target.*);
        } else {
            try self.emit(.POP_TOP, 0);
        }

        // Compile body
        for (with.body) |stmt| {
            try self.compileStmt(stmt);
        }

        // Cleanup
        try self.emit(.WITH_CLEANUP_START, 0);
        try self.emit(.WITH_CLEANUP_FINISH, 0);
    }

    // ========== Expression Compilation ==========

    fn compileExpression(self: *Compiler, node: ast.Node) anyerror!void {
        switch (node) {
            .Constant => |c| try self.compileConstant(c),
            .Name => |name| {
                const idx = try self.addName(name.id);
                try self.emit(.LOAD_NAME, idx);
            },
            .BinaryOp => |binop| try self.compileBinaryOp(binop),
            .UnaryOp => |unop| try self.compileUnaryOp(unop),
            .Compare => |cmp| try self.compileCompare(cmp),
            .BoolOp => |boolop| try self.compileBoolOp(boolop),
            .Call => |call| try self.compileCall(call),
            .Attribute => |attr| {
                try self.compileExpression(attr.object.*);
                const idx = try self.addName(attr.attribute);
                try self.emit(.LOAD_ATTR, idx);
            },
            .Subscript => |sub| {
                try self.compileExpression(sub.object.*);
                try self.compileExpression(sub.index.*);
                try self.emit(.BINARY_SUBSCR, 0);
            },
            .List => |list| {
                for (list.elements) |elem| {
                    try self.compileExpression(elem.*);
                }
                try self.emit(.BUILD_LIST, @intCast(list.elements.len));
            },
            .Tuple => |tuple| {
                for (tuple.elements) |elem| {
                    try self.compileExpression(elem.*);
                }
                try self.emit(.BUILD_TUPLE, @intCast(tuple.elements.len));
            },
            .Dict => |dict| {
                for (dict.keys, dict.values) |key, value| {
                    try self.compileExpression(key.*);
                    try self.compileExpression(value.*);
                }
                try self.emit(.BUILD_MAP, @intCast(dict.keys.len));
            },
            .Set => |set| {
                for (set.elements) |elem| {
                    try self.compileExpression(elem.*);
                }
                try self.emit(.BUILD_SET, @intCast(set.elements.len));
            },
            .Lambda => |lambda| try self.compileLambda(lambda),
            .IfExp => |ifexp| try self.compileIfExp(ifexp),
            .ListComp, .SetComp, .DictComp, .GeneratorExp => |_| {
                // TODO: compile comprehensions
                return error.UnsupportedExpression;
            },
            .Slice => |slice| try self.compileSlice(slice),
            .FormattedValue => |fv| try self.compileFormattedValue(fv),
            .JoinedStr => |js| try self.compileJoinedStr(js),
            else => return error.UnsupportedExpression,
        }
    }

    fn compileConstant(self: *Compiler, c: ast.Node.Constant) !void {
        const value: Value = switch (c.value) {
            .None => .none,
            .Bool => |b| .{ .bool = b },
            .Int => |i| .{ .int = i },
            .Float => |f| .{ .float = f },
            .String => |s| .{ .string = try self.allocator.dupe(u8, s) },
            .Bytes => |b| .{ .bytes = try self.allocator.dupe(u8, b) },
            .Ellipsis => .none, // TODO: proper ellipsis
        };
        const idx = try self.addConstant(value);
        try self.emit(.LOAD_CONST, idx);
    }

    fn compileBinaryOp(self: *Compiler, binop: ast.Node.BinaryOp) !void {
        try self.compileExpression(binop.left.*);
        try self.compileExpression(binop.right.*);
        const op: OpCode = switch (binop.operator) {
            .Add => .BINARY_ADD,
            .Sub => .BINARY_SUBTRACT,
            .Mult => .BINARY_MULTIPLY,
            .Div => .BINARY_TRUE_DIVIDE,
            .FloorDiv => .BINARY_FLOOR_DIVIDE,
            .Mod => .BINARY_MODULO,
            .Pow => .BINARY_POWER,
            .LShift => .BINARY_LSHIFT,
            .RShift => .BINARY_RSHIFT,
            .BitAnd => .BINARY_AND,
            .BitOr => .BINARY_OR,
            .BitXor => .BINARY_XOR,
            .MatMul => .BINARY_MATRIX_MULTIPLY,
        };
        try self.emit(op, 0);
    }

    fn compileUnaryOp(self: *Compiler, unop: ast.Node.UnaryOp) !void {
        try self.compileExpression(unop.operand.*);
        const op: OpCode = switch (unop.operator) {
            .UAdd => .UNARY_POSITIVE,
            .USub => .UNARY_NEGATIVE,
            .Not => .UNARY_NOT,
            .Invert => .UNARY_INVERT,
        };
        try self.emit(op, 0);
    }

    fn compileCompare(self: *Compiler, cmp: ast.Node.Compare) !void {
        try self.compileExpression(cmp.left.*);

        for (cmp.comparators, 0..) |comparator, i| {
            if (i < cmp.comparators.len - 1) {
                try self.emit(.DUP_TOP, 0);
                try self.emit(.ROT_THREE, 0);
            }
            try self.compileExpression(comparator.*);
            const op: OpCode = switch (cmp.operators[i]) {
                .Lt => .COMPARE_LT,
                .LtE => .COMPARE_LE,
                .Eq => .COMPARE_EQ,
                .NotEq => .COMPARE_NE,
                .Gt => .COMPARE_GT,
                .GtE => .COMPARE_GE,
                .In => .COMPARE_IN,
                .NotIn => .COMPARE_NOT_IN,
                .Is => .COMPARE_IS,
                .IsNot => .COMPARE_IS_NOT,
            };
            try self.emit(op, 0);
            if (i < cmp.comparators.len - 1) {
                // Short-circuit: if false, skip remaining
                try self.emit(.JUMP_IF_FALSE_OR_POP, @intCast(self.currentOffset() + 10)); // TODO: proper patching
            }
        }
    }

    fn compileBoolOp(self: *Compiler, boolop: ast.Node.BoolOp) !void {
        const is_and = boolop.operator == .And;

        for (boolop.values, 0..) |val, i| {
            try self.compileExpression(val.*);
            if (i < boolop.values.len - 1) {
                const jump_op: OpCode = if (is_and) .JUMP_IF_FALSE_OR_POP else .JUMP_IF_TRUE_OR_POP;
                try self.emit(jump_op, 0); // TODO: patch
            }
        }
    }

    fn compileCall(self: *Compiler, call: ast.Node.Call) !void {
        // Compile function
        try self.compileExpression(call.function.*);

        // Compile positional args
        for (call.arguments) |arg| {
            try self.compileExpression(arg.*);
        }

        // TODO: handle keyword args, *args, **kwargs
        try self.emit(.CALL_FUNCTION, @intCast(call.arguments.len));
    }

    fn compileLambda(self: *Compiler, lambda: ast.Node.Lambda) !void {
        _ = self;
        _ = lambda;
        // TODO: compile lambda to nested Program
        return error.UnsupportedExpression;
    }

    fn compileIfExp(self: *Compiler, ifexp: ast.Node.IfExp) !void {
        try self.compileExpression(ifexp.condition.*);
        const else_jump = self.currentOffset();
        try self.emit(.POP_JUMP_IF_FALSE, 0);

        try self.compileExpression(ifexp.then_expr.*);
        const end_jump = self.currentOffset();
        try self.emit(.JUMP_FORWARD, 0);

        self.instructions.items[else_jump].arg = self.currentOffset();
        try self.compileExpression(ifexp.else_expr.*);

        self.instructions.items[end_jump].arg = self.currentOffset() - end_jump - 1;
    }

    fn compileSlice(self: *Compiler, slice: ast.Node.Slice) !void {
        var count: u24 = 2;
        if (slice.lower) |lower| {
            try self.compileExpression(lower.*);
        } else {
            try self.emit(.LOAD_CONST, try self.addConstant(.none));
        }
        if (slice.upper) |upper| {
            try self.compileExpression(upper.*);
        } else {
            try self.emit(.LOAD_CONST, try self.addConstant(.none));
        }
        if (slice.step) |step| {
            try self.compileExpression(step.*);
            count = 3;
        }
        try self.emit(.BUILD_SLICE, count);
    }

    fn compileFormattedValue(self: *Compiler, fv: ast.Node.FormattedValue) !void {
        try self.compileExpression(fv.value.*);
        var flags: u24 = 0;
        if (fv.format_spec) |spec| {
            try self.compileExpression(spec.*);
            flags |= 0x04;
        }
        try self.emit(.FORMAT_VALUE, flags);
    }

    fn compileJoinedStr(self: *Compiler, js: ast.Node.JoinedStr) !void {
        for (js.values) |val| {
            try self.compileExpression(val.*);
        }
        try self.emit(.BUILD_STRING, @intCast(js.values.len));
    }
};

/// Check if two Values are equal (for constant deduplication)
fn valueEqual(a: Value, b: Value) bool {
    return switch (a) {
        .none => b == .none,
        .bool => |va| switch (b) {
            .bool => |vb| va == vb,
            else => false,
        },
        .int => |va| switch (b) {
            .int => |vb| va == vb,
            else => false,
        },
        .float => |va| switch (b) {
            .float => |vb| va == vb,
            else => false,
        },
        .string => |va| switch (b) {
            .string => |vb| std.mem.eql(u8, va, vb),
            else => false,
        },
        .bytes => |va| switch (b) {
            .bytes => |vb| std.mem.eql(u8, va, vb),
            else => false,
        },
        else => false,
    };
}

/// Compile Python source string to bytecode Program
/// This is the main entry point for eval()/exec()
pub fn compile(allocator: std.mem.Allocator, source: []const u8, filename: []const u8, mode: enum { eval, exec }) !*Program {
    // Import metal0's parser
    const parser = @import("../parser/parser.zig");
    const lexer_mod = @import("../lexer/lexer.zig");

    // Lex and parse
    var lex = try lexer_mod.Lexer.init(allocator, source, filename);
    var p = parser.Parser.init(&lex, allocator);
    const ast_nodes = try p.parse();

    // Compile to bytecode
    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    return switch (mode) {
        .eval => compiler.compileExpr(ast_nodes[0], filename),
        .exec => compiler.compileModule(ast_nodes, filename),
    };
}

test "compile simple expression" {
    const allocator = std.testing.allocator;

    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    // Manually create a constant expression AST node for testing
    const idx = try compiler.addConstant(.{ .int = 42 });
    try compiler.emit(.LOAD_CONST, idx);
    try compiler.emit(.RETURN_VALUE, 0);

    const program = try compiler.finalize("<test>", "<expr>");
    defer {
        var p = @constCast(program);
        p.deinit(allocator);
        allocator.destroy(p);
    }

    try std.testing.expectEqual(@as(usize, 2), program.instructions.len);
    try std.testing.expectEqual(OpCode.LOAD_CONST, program.instructions[0].opcode);
    try std.testing.expectEqual(OpCode.RETURN_VALUE, program.instructions[1].opcode);
}
