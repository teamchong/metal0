/// AST to Bytecode Compiler
///
/// Compiles metal0 AST nodes to bytecode for the runtime VM.
/// This bridges the gap between the parser (src/ast/) and the
/// bytecode VM (packages/runtime/src/bytecode/).
const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("analysis.ast");
const Node = ast.Node;

/// Bytecode types from runtime module
const runtime = @import("runtime");
const bytecode = runtime.bytecode;

/// Compiler error type (explicit to break recursive inference)
pub const CompileError = error{
    OutOfMemory,
    UnsupportedStatement,
    UnsupportedExpression,
    UnsupportedConstant,
    InvalidStoreTarget,
    InvalidDeleteTarget,
    SliceStoreNotSupported,
    SliceDeleteNotSupported,
    BreakOutsideLoop,
    ContinueOutsideLoop,
    TooManyLocals,
    TooManyNames,
    TooManyConstants,
};

/// Scope type for variable resolution
pub const ScopeType = enum {
    module,
    function,
    class,
    comprehension,
};

/// Variable info for scoping
const VarInfo = struct {
    scope: enum { local, global, free, cell },
    index: u8,
};

/// Loop context for break/continue
const LoopContext = struct {
    start: u32,
    break_patches: std.ArrayList(u32),
};

/// AST to Bytecode compiler
pub const AstCompiler = struct {
    allocator: Allocator,

    /// Emitted bytecode
    bytecode: std.ArrayList(u8),

    /// Constant pool
    constants: std.ArrayList(bytecode.PyValue),

    /// Local variable names
    varnames: std.ArrayList([]const u8),

    /// Free variable names (from enclosing scope)
    freevars: std.ArrayList([]const u8),

    /// Cell variable names (captured by nested functions)
    cellvars: std.ArrayList([]const u8),

    /// Global/attribute names
    names: std.ArrayList([]const u8),

    /// Variable lookup map (name -> VarInfo)
    var_map: std.StringHashMap(VarInfo),

    /// Current scope type
    scope_type: ScopeType,

    /// Loop stack for break/continue
    loop_stack: std.ArrayList(LoopContext),

    /// Source filename
    filename: []const u8,

    /// Function name
    name: []const u8,

    /// First line number
    firstlineno: u32,

    /// Code flags
    flags: bytecode.CodeFlags,

    /// Argument count (for functions)
    argcount: u16,

    /// Initialize compiler
    pub fn init(allocator: Allocator) AstCompiler {
        return .{
            .allocator = allocator,
            .bytecode = .{},
            .constants = .{},
            .varnames = .{},
            .freevars = .{},
            .cellvars = .{},
            .names = .{},
            .var_map = std.StringHashMap(VarInfo).init(allocator),
            .scope_type = .module,
            .loop_stack = .{},
            .filename = "<unknown>",
            .name = "<module>",
            .firstlineno = 1,
            .flags = .{},
            .argcount = 0,
        };
    }

    /// Clean up compiler resources
    pub fn deinit(self: *AstCompiler) void {
        self.bytecode.deinit(self.allocator);
        self.constants.deinit(self.allocator);
        self.varnames.deinit(self.allocator);
        self.freevars.deinit(self.allocator);
        self.cellvars.deinit(self.allocator);
        self.names.deinit(self.allocator);
        self.var_map.deinit();
        for (self.loop_stack.items) |*loop| {
            loop.break_patches.deinit(self.allocator);
        }
        self.loop_stack.deinit(self.allocator);
    }

    // ========================================
    // Main compilation entry points
    // ========================================

    /// Compile a module (list of statements)
    pub fn compileModule(self: *AstCompiler, stmts: []const Node) !*const bytecode.CodeObject {
        for (stmts) |stmt| {
            try self.compileStmt(stmt);
        }
        // Implicit return None
        try self.emit(.LOAD_NONE);
        try self.emit(.RETURN);
        return self.finalize();
    }

    /// Compile a single expression (for eval())
    pub fn compileExpr(self: *AstCompiler, expr: Node) !*const bytecode.CodeObject {
        try self.compileExpression(expr);
        try self.emit(.RETURN);
        return self.finalize();
    }

    /// Finalize and return CodeObject
    fn finalize(self: *AstCompiler) !*const bytecode.CodeObject {
        const code = try self.allocator.create(bytecode.CodeObject);
        code.* = .{
            .bytecode = try self.bytecode.toOwnedSlice(self.allocator),
            .constants = try self.constants.toOwnedSlice(self.allocator),
            .varnames = try self.varnames.toOwnedSlice(self.allocator),
            .freevars = try self.freevars.toOwnedSlice(self.allocator),
            .cellvars = try self.cellvars.toOwnedSlice(self.allocator),
            .names = try self.names.toOwnedSlice(self.allocator),
            .nlocals = @intCast(self.varnames.items.len),
            .stacksize = 256,
            .argcount = self.argcount,
            .flags = self.flags,
            .filename = self.filename,
            .name = self.name,
            .firstlineno = self.firstlineno,
        };
        return code;
    }

    // ========================================
    // Statement compilation
    // ========================================

    fn compileStmt(self: *AstCompiler, node: Node) CompileError!void {
        switch (node) {
            .expr_stmt => |e| {
                try self.compileExpression(e.value.*);
                try self.emit(.POP);
            },
            .assign => |a| try self.compileAssign(a),
            .aug_assign => |a| try self.compileAugAssign(a),
            .if_stmt => |i| try self.compileIf(i),
            .while_stmt => |w| try self.compileWhile(w),
            .for_stmt => |f| try self.compileFor(f),
            .function_def => |fd| try self.compileFunctionDef(fd),
            .return_stmt => |r| try self.compileReturn(r),
            .pass => {},
            .break_stmt => try self.compileBreak(),
            .continue_stmt => try self.compileContinue(),
            .raise_stmt => |r| try self.compileRaise(r),
            .try_stmt => |t| try self.compileTry(t),
            .import_stmt => |i| try self.compileImport(i),
            .import_from => |i| try self.compileImportFrom(i),
            .global_stmt, .nonlocal_stmt => {}, // Handled in analysis phase
            .class_def => |c| try self.compileClassDef(c),
            .del_stmt => |d| try self.compileDel(d),
            .assert_stmt => |a| try self.compileAssert(a),
            .with_stmt => |w| try self.compileWith(w),
            else => return error.UnsupportedStatement,
        }
    }

    fn compileAssign(self: *AstCompiler, assign: Node.Assign) CompileError!void {
        // Compile value
        try self.compileExpression(assign.value.*);

        // Store to each target
        for (assign.targets, 0..) |target, i| {
            if (i < assign.targets.len - 1) {
                try self.emit(.DUP);
            }
            try self.compileStore(target);
        }
    }

    fn compileAugAssign(self: *AstCompiler, aug: Node.AugAssign) CompileError!void {
        // Load current value
        try self.compileExpression(aug.target.*);
        // Compile augmented value
        try self.compileExpression(aug.value.*);
        // Apply operator
        try self.emit(operatorToOpcode(aug.op));
        // Store back
        try self.compileStore(aug.target.*);
    }

    fn compileStore(self: *AstCompiler, target: Node) CompileError!void {
        switch (target) {
            .name => |n| {
                const idx = try self.addLocal(n.id);
                try self.emitArg(.STORE_FAST, idx);
            },
            .attribute => |a| {
                try self.compileExpression(a.value.*);
                const idx = try self.addName(a.attr);
                try self.emitArg(.STORE_ATTR, idx);
            },
            .subscript => |s| {
                try self.compileExpression(s.value.*);
                switch (s.slice) {
                    .index => |idx| try self.compileExpression(idx.*),
                    .slice => return error.SliceStoreNotSupported,
                }
                try self.emit(.STORE_SUBSCR);
            },
            .tuple, .list => {
                // Unpack sequence not yet supported
                return error.UnsupportedExpression;
            },
            else => return error.InvalidStoreTarget,
        }
    }

    fn compileIf(self: *AstCompiler, if_stmt: Node.If) CompileError!void {
        // Compile condition
        try self.compileExpression(if_stmt.condition.*);

        // Jump to else if false
        const else_jump = try self.emitJump(.JUMP_IF_FALSE);

        // Compile then body
        for (if_stmt.body) |stmt| {
            try self.compileStmt(stmt);
        }

        if (if_stmt.else_body.len > 0) {
            // Jump over else
            const end_jump = try self.emitJump(.JUMP);
            self.patchJumpHere(else_jump);

            // Compile else body
            for (if_stmt.else_body) |stmt| {
                try self.compileStmt(stmt);
            }
            self.patchJumpHere(end_jump);
        } else {
            self.patchJumpHere(else_jump);
        }
    }

    fn compileWhile(self: *AstCompiler, while_stmt: Node.While) CompileError!void {
        try self.enterLoop();

        const loop_start = self.offset();

        // Compile condition
        try self.compileExpression(while_stmt.condition.*);
        const exit_jump = try self.emitJump(.JUMP_IF_FALSE);

        // Compile body
        for (while_stmt.body) |stmt| {
            try self.compileStmt(stmt);
        }

        // Jump back to condition
        try self.emitJumpTo(.JUMP, loop_start);

        self.patchJumpHere(exit_jump);
        self.exitLoop();
    }

    fn compileFor(self: *AstCompiler, for_stmt: Node.For) CompileError!void {
        // Compile iterator
        try self.compileExpression(for_stmt.iter.*);
        try self.emit(.GET_ITER);

        try self.enterLoop();
        const loop_start = self.offset();

        // FOR_ITER jumps to end when exhausted
        const exit_jump = try self.emitJump(.FOR_ITER);

        // Store loop variable
        try self.compileStore(for_stmt.target.*);

        // Compile body
        for (for_stmt.body) |stmt| {
            try self.compileStmt(stmt);
        }

        // Jump back to FOR_ITER
        try self.emitJumpTo(.JUMP, loop_start);

        self.patchJumpHere(exit_jump);
        self.exitLoop();
    }

    fn compileFunctionDef(self: *AstCompiler, func: Node.FunctionDef) CompileError!void {
        // Create a new compiler for the function body
        var func_compiler = AstCompiler.init(self.allocator);
        defer func_compiler.deinit();

        func_compiler.scope_type = .function;
        func_compiler.name = func.name;
        func_compiler.filename = self.filename;
        func_compiler.argcount = @intCast(func.args.len);

        // Add arguments as locals
        for (func.args) |arg| {
            _ = try func_compiler.addLocal(arg.name);
        }

        // Compile function body
        for (func.body) |stmt| {
            try func_compiler.compileStmt(stmt);
        }

        // Implicit return None if no explicit return
        try func_compiler.emit(.LOAD_NONE);
        try func_compiler.emit(.RETURN);

        // Get the code object
        const code = try func_compiler.finalize();

        // Load code object as constant
        const code_idx = try self.addCodeConstant(code);
        try self.emitArg(.LOAD_CONST, code_idx);

        // Make function
        try self.emitArg(.MAKE_FUNCTION, 0);

        // Store in local/global
        const name_idx = try self.addLocal(func.name);
        try self.emitArg(.STORE_FAST, name_idx);
    }

    fn compileReturn(self: *AstCompiler, ret: Node.Return) CompileError!void {
        if (ret.value) |val| {
            try self.compileExpression(val.*);
        } else {
            try self.emit(.LOAD_NONE);
        }
        try self.emit(.RETURN);
    }

    fn compileBreak(self: *AstCompiler) CompileError!void {
        if (self.loop_stack.items.len == 0) {
            return error.BreakOutsideLoop;
        }
        const patch = try self.emitJump(.JUMP);
        try self.loop_stack.items[self.loop_stack.items.len - 1].break_patches.append(self.allocator, patch);
    }

    fn compileContinue(self: *AstCompiler) CompileError!void {
        if (self.loop_stack.items.len == 0) {
            return error.ContinueOutsideLoop;
        }
        const loop_start = self.loop_stack.items[self.loop_stack.items.len - 1].start;
        try self.emitJumpTo(.JUMP, loop_start);
    }

    fn compileRaise(self: *AstCompiler, raise: Node.Raise) CompileError!void {
        if (raise.exc) |exc| {
            try self.compileExpression(exc.*);
            try self.emit(.RAISE);
        } else {
            try self.emit(.RERAISE);
        }
    }

    fn compileTry(self: *AstCompiler, try_stmt: Node.Try) CompileError!void {
        // Setup exception handler
        const handler_jump = try self.emitJump(.SETUP_FINALLY);

        // Compile try body
        for (try_stmt.body) |stmt| {
            try self.compileStmt(stmt);
        }

        // Pop exception handler
        try self.emit(.POP_EXC_INFO);
        const end_jump = try self.emitJump(.JUMP);

        // Handler target
        self.patchJumpHere(handler_jump);

        // Compile handlers
        for (try_stmt.handlers) |handler| {
            // TODO: Check exception type if specified
            for (handler.body) |stmt| {
                try self.compileStmt(stmt);
            }
        }

        self.patchJumpHere(end_jump);

        // Compile finally if present
        for (try_stmt.finalbody) |stmt| {
            try self.compileStmt(stmt);
        }
    }

    fn compileImport(self: *AstCompiler, import: Node.Import) CompileError!void {
        // Push None (fromlist) and 0 (level)
        try self.emit(.LOAD_NONE);
        try self.emit(.LOAD_ZERO);

        const name_idx = try self.addName(import.module);
        try self.emitArg(.IMPORT_NAME, name_idx);

        // Store as local
        const store_name = import.asname orelse import.module;
        const local_idx = try self.addLocal(store_name);
        try self.emitArg(.STORE_FAST, local_idx);
    }

    fn compileImportFrom(self: *AstCompiler, import: Node.ImportFrom) CompileError!void {
        // Push None (fromlist) and 0 (level)
        try self.emit(.LOAD_NONE);
        try self.emit(.LOAD_ZERO);

        const mod_idx = try self.addName(import.module);
        try self.emitArg(.IMPORT_NAME, mod_idx);

        // Import each name
        for (import.names, 0..) |name, i| {
            const name_idx = try self.addName(name);
            try self.emitArg(.IMPORT_FROM, name_idx);

            const store_name = if (import.asnames.len > i and import.asnames[i] != null)
                import.asnames[i].?
            else
                name;
            const local_idx = try self.addLocal(store_name);
            try self.emitArg(.STORE_FAST, local_idx);
        }

        // Pop the module
        try self.emit(.POP);
    }

    fn compileClassDef(self: *AstCompiler, class: Node.ClassDef) CompileError!void {
        // Simplified: just create a dict for the class namespace
        // Full implementation would need __build_class__

        // Build class dict
        try self.emitArg(.BUILD_DICT, 0);

        // Compile class body into the dict
        for (class.body) |stmt| {
            try self.compileStmt(stmt);
        }

        // Store as local
        const name_idx = try self.addLocal(class.name);
        try self.emitArg(.STORE_FAST, name_idx);
    }

    fn compileDel(self: *AstCompiler, del: Node.Del) CompileError!void {
        for (del.targets) |target| {
            switch (target) {
                .name => |n| {
                    const idx = try self.addLocal(n.id);
                    try self.emitArg(.DELETE_FAST, idx);
                },
                .subscript => |s| {
                    try self.compileExpression(s.value.*);
                    switch (s.slice) {
                        .index => |idx| try self.compileExpression(idx.*),
                        .slice => return error.SliceDeleteNotSupported,
                    }
                    try self.emit(.DELETE_SUBSCR);
                },
                .attribute => |a| {
                    try self.compileExpression(a.value.*);
                    const idx = try self.addName(a.attr);
                    try self.emitArg(.DELETE_ATTR, idx);
                },
                else => return error.InvalidDeleteTarget,
            }
        }
    }

    fn compileAssert(self: *AstCompiler, assert: Node.Assert) CompileError!void {
        // Compile: if not condition: raise AssertionError(msg)
        try self.compileExpression(assert.condition.*);
        const ok_jump = try self.emitJump(.JUMP_IF_TRUE);

        // Raise AssertionError
        if (assert.msg) |msg| {
            try self.compileExpression(msg.*);
        } else {
            const msg_idx = try self.addStringConstant("assertion failed");
            try self.emitArg(.LOAD_CONST, msg_idx);
        }
        try self.emit(.RAISE);

        self.patchJumpHere(ok_jump);
    }

    fn compileWith(self: *AstCompiler, with: Node.With) CompileError!void {
        // Simplified: call __enter__, execute body, call __exit__
        // With statement: with context_expr as optional_vars: body
        try self.compileExpression(with.context_expr.*);
        // TODO: Store __exit__ for cleanup

        // Call __enter__
        const enter_idx = try self.addName("__enter__");
        try self.emitArg(.LOAD_ATTR, enter_idx);
        try self.emitArg(.CALL, 0);

        // Store result if target specified
        if (with.optional_vars) |target| {
            try self.compileStore(target.*);
        } else {
            try self.emit(.POP);
        }

        // Compile body
        for (with.body) |stmt| {
            try self.compileStmt(stmt);
        }

        // TODO: Call __exit__ (needs exception handling)
    }

    // ========================================
    // Expression compilation
    // ========================================

    fn compileExpression(self: *AstCompiler, node: Node) CompileError!void {
        switch (node) {
            .constant => |c| try self.compileConstant(c),
            .name => |n| try self.compileName(n),
            .binop => |b| try self.compileBinOp(b),
            .unaryop => |u| try self.compileUnaryOp(u),
            .compare => |c| try self.compileCompare(c),
            .boolop => |b| try self.compileBoolOp(b),
            .call => |c| try self.compileCall(c),
            .attribute => |a| try self.compileAttribute(a),
            .subscript => |s| try self.compileSubscript(s),
            .list => |l| try self.compileList(l),
            .tuple => |t| try self.compileTuple(t),
            .dict => |d| try self.compileDict(d),
            .set => |s| try self.compileSet(s),
            .if_expr => |i| try self.compileIfExpr(i),
            .lambda => |l| try self.compileLambda(l),
            .listcomp => |lc| try self.compileListComp(lc),
            .await_expr => |a| try self.compileAwait(a),
            else => return error.UnsupportedExpression,
        }
    }

    fn compileConstant(self: *AstCompiler, constant: Node.Constant) CompileError!void {
        switch (constant.value) {
            .int => |i| {
                if (i >= -128 and i <= 127) {
                    try self.emitArg(.LOAD_I8, @bitCast(@as(i8, @intCast(i))));
                } else {
                    const idx = try self.addIntConstant(i);
                    try self.emitArg(.LOAD_CONST, idx);
                }
            },
            .float => |f| {
                const idx = try self.addFloatConstant(f);
                try self.emitArg(.LOAD_CONST, idx);
            },
            .string => |s| {
                const idx = try self.addStringConstant(s);
                try self.emitArg(.LOAD_CONST, idx);
            },
            .bool => |b| {
                try self.emit(if (b) .LOAD_TRUE else .LOAD_FALSE);
            },
            .none => try self.emit(.LOAD_NONE),
            else => return error.UnsupportedConstant,
        }
    }

    fn compileName(self: *AstCompiler, name: Node.Name) CompileError!void {
        // Check if local
        if (self.findLocal(name.id)) |idx| {
            try self.emitArg(.LOAD_FAST, idx);
        } else {
            // Assume global
            const idx = try self.addName(name.id);
            try self.emitArg(.LOAD_GLOBAL, idx);
        }
    }

    fn compileBinOp(self: *AstCompiler, binop: Node.BinOp) CompileError!void {
        try self.compileExpression(binop.left.*);
        try self.compileExpression(binop.right.*);
        try self.emit(operatorToOpcode(binop.op));
    }

    fn compileUnaryOp(self: *AstCompiler, unaryop: Node.UnaryOp) CompileError!void {
        try self.compileExpression(unaryop.operand.*);
        try self.emit(switch (unaryop.op) {
            .Not => .NOT,
            .USub => .NEG,
            .UAdd => .POS,
            .Invert => .INVERT,
        });
    }

    fn compileCompare(self: *AstCompiler, compare: Node.Compare) CompileError!void {
        try self.compileExpression(compare.left.*);

        for (compare.comparators, 0..) |comparator, i| {
            try self.compileExpression(comparator);
            try self.emit(compareOpToOpcode(compare.ops[i]));

            if (i < compare.comparators.len - 1) {
                // Chain: need to keep result and continue
                // Simplified: doesn't handle short-circuit properly
            }
        }
    }

    fn compileBoolOp(self: *AstCompiler, boolop: Node.BoolOp) CompileError!void {
        const jump_op: bytecode.Opcode = switch (boolop.op) {
            .And => .JUMP_IF_FALSE_OR_POP,
            .Or => .JUMP_IF_TRUE_OR_POP,
        };

        var end_patches: std.ArrayList(u32) = .{};
        defer end_patches.deinit(self.allocator);

        for (boolop.values, 0..) |val, i| {
            try self.compileExpression(val);
            if (i < boolop.values.len - 1) {
                const patch = try self.emitJump(jump_op);
                try end_patches.append(self.allocator, patch);
            }
        }

        // Patch all jumps to end
        for (end_patches.items) |patch| {
            self.patchJumpHere(patch);
        }
    }

    fn compileCall(self: *AstCompiler, call: Node.Call) CompileError!void {
        // Compile function
        try self.compileExpression(call.func.*);

        // Compile positional args
        for (call.args) |arg| {
            try self.compileExpression(arg);
        }

        // Emit call
        if (call.keyword_args.len > 0) {
            // Build keyword dict
            for (call.keyword_args) |kw| {
                const key_idx = try self.addStringConstant(kw.name);
                try self.emitArg(.LOAD_CONST, key_idx);
                try self.compileExpression(kw.value);
            }
            try self.emitArg(.BUILD_DICT, @intCast(call.keyword_args.len));
            try self.emitArg(.CALL_KW, @intCast(call.args.len));
        } else {
            try self.emitArg(.CALL, @intCast(call.args.len));
        }
    }

    fn compileAttribute(self: *AstCompiler, attr: Node.Attribute) CompileError!void {
        try self.compileExpression(attr.value.*);
        const idx = try self.addName(attr.attr);
        try self.emitArg(.LOAD_ATTR, idx);
    }

    fn compileSubscript(self: *AstCompiler, sub: Node.Subscript) CompileError!void {
        try self.compileExpression(sub.value.*);
        switch (sub.slice) {
            .index => |idx| {
                try self.compileExpression(idx.*);
                try self.emit(.BINARY_SUBSCR);
            },
            .slice => |s| {
                // Build slice object
                if (s.lower) |l| try self.compileExpression(l.*) else try self.emit(.LOAD_NONE);
                if (s.upper) |u| try self.compileExpression(u.*) else try self.emit(.LOAD_NONE);
                if (s.step) |st| try self.compileExpression(st.*) else try self.emit(.LOAD_NONE);
                try self.emitArg(.BUILD_SLICE, 3);
                try self.emit(.BINARY_SUBSCR);
            },
        }
    }

    fn compileList(self: *AstCompiler, list: Node.List) CompileError!void {
        for (list.elts) |elem| {
            try self.compileExpression(elem);
        }
        try self.emitArg(.BUILD_LIST, @intCast(list.elts.len));
    }

    fn compileTuple(self: *AstCompiler, tuple: Node.Tuple) CompileError!void {
        for (tuple.elts) |elem| {
            try self.compileExpression(elem);
        }
        try self.emitArg(.BUILD_TUPLE, @intCast(tuple.elts.len));
    }

    fn compileDict(self: *AstCompiler, dict: Node.Dict) CompileError!void {
        for (dict.keys, 0..) |key, i| {
            try self.compileExpression(key);
            try self.compileExpression(dict.values[i]);
        }
        try self.emitArg(.BUILD_DICT, @intCast(dict.keys.len));
    }

    fn compileSet(self: *AstCompiler, set: Node.Set) CompileError!void {
        for (set.elts) |elem| {
            try self.compileExpression(elem);
        }
        try self.emitArg(.BUILD_SET, @intCast(set.elts.len));
    }

    fn compileIfExpr(self: *AstCompiler, if_expr: Node.IfExpr) CompileError!void {
        try self.compileExpression(if_expr.condition.*);
        const else_jump = try self.emitJump(.JUMP_IF_FALSE);
        try self.compileExpression(if_expr.body.*);
        const end_jump = try self.emitJump(.JUMP);
        self.patchJumpHere(else_jump);
        try self.compileExpression(if_expr.orelse_value.*);
        self.patchJumpHere(end_jump);
    }

    fn compileLambda(self: *AstCompiler, lambda: Node.Lambda) CompileError!void {
        // Create a new compiler for the lambda body
        var lambda_compiler = AstCompiler.init(self.allocator);
        defer lambda_compiler.deinit();

        lambda_compiler.scope_type = .function;
        lambda_compiler.name = "<lambda>";
        lambda_compiler.filename = self.filename;
        lambda_compiler.argcount = @intCast(lambda.args.len);

        // Add arguments as locals
        for (lambda.args) |arg| {
            _ = try lambda_compiler.addLocal(arg.name);
        }

        // Compile lambda body (single expression)
        try lambda_compiler.compileExpression(lambda.body.*);
        try lambda_compiler.emit(.RETURN);

        // Get the code object
        const code = try lambda_compiler.finalize();

        // Load code object as constant
        const code_idx = try self.addCodeConstant(code);
        try self.emitArg(.LOAD_CONST, code_idx);

        // Make function
        try self.emitArg(.MAKE_FUNCTION, 0);
    }

    fn compileListComp(self: *AstCompiler, comp: Node.ListComp) CompileError!void {
        // Build empty list
        try self.emitArg(.BUILD_LIST, 0);

        // Compile each generator
        for (comp.generators) |gen| {
            try self.compileExpression(gen.iter.*);
            try self.emit(.GET_ITER);

            const loop_start = self.offset();
            const exit_jump = try self.emitJump(.FOR_ITER);

            // Store loop variable
            try self.compileStore(gen.target.*);

            // Check conditions
            var skip_patches: std.ArrayList(u32) = .{};
            defer skip_patches.deinit(self.allocator);

            for (gen.ifs) |cond| {
                try self.compileExpression(cond);
                const skip = try self.emitJump(.JUMP_IF_FALSE);
                try skip_patches.append(self.allocator, skip);
            }

            // Compile element and append
            try self.emit(.DUP); // Dup list
            try self.compileExpression(comp.elt.*);
            try self.emit(.LIST_APPEND);

            // Patch skip jumps
            for (skip_patches.items) |patch| {
                self.patchJumpHere(patch);
            }

            // Loop back
            try self.emitJumpTo(.JUMP, loop_start);
            self.patchJumpHere(exit_jump);
        }
    }

    fn compileAwait(self: *AstCompiler, await_expr: Node.AwaitExpr) CompileError!void {
        try self.compileExpression(await_expr.value.*);
        try self.emit(.AWAIT);
    }

    // ========================================
    // Helper functions
    // ========================================

    fn offset(self: *const AstCompiler) u32 {
        return @intCast(self.bytecode.items.len);
    }

    fn emit(self: *AstCompiler, op: bytecode.Opcode) CompileError!void {
        try self.bytecode.append(self.allocator, @intFromEnum(op));
    }

    fn emitArg(self: *AstCompiler, op: bytecode.Opcode, arg: u8) CompileError!void {
        try self.bytecode.append(self.allocator, @intFromEnum(op));
        try self.bytecode.append(self.allocator, arg);
    }

    fn emitJump(self: *AstCompiler, op: bytecode.Opcode) CompileError!u32 {
        try self.bytecode.append(self.allocator, @intFromEnum(op));
        const patch_offset = self.offset();
        try self.bytecode.append(self.allocator, 0);
        try self.bytecode.append(self.allocator, 0);
        return patch_offset;
    }

    fn emitJumpTo(self: *AstCompiler, op: bytecode.Opcode, target: u32) CompileError!void {
        try self.bytecode.append(self.allocator, @intFromEnum(op));
        // 2-byte varint encoding
        try self.bytecode.append(self.allocator, @intCast((target & 0x7F) | 0x80));
        try self.bytecode.append(self.allocator, @intCast((target >> 7) & 0x7F));
    }

    fn patchJumpHere(self: *AstCompiler, patch_offset: u32) void {
        const target = self.offset();
        self.bytecode.items[patch_offset] = @intCast((target & 0x7F) | 0x80);
        self.bytecode.items[patch_offset + 1] = @intCast((target >> 7) & 0x7F);
    }

    fn enterLoop(self: *AstCompiler) CompileError!void {
        try self.loop_stack.append(self.allocator, .{
            .start = self.offset(),
            .break_patches = .{},
        });
    }

    fn exitLoop(self: *AstCompiler) void {
        if (self.loop_stack.items.len == 0) return;
        var loop = self.loop_stack.pop() orelse return;
        for (loop.break_patches.items) |patch| {
            self.patchJumpHere(patch);
        }
        loop.break_patches.deinit(self.allocator);
    }

    fn findLocal(self: *AstCompiler, name: []const u8) ?u8 {
        for (self.varnames.items, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) {
                return @intCast(i);
            }
        }
        return null;
    }

    fn addLocal(self: *AstCompiler, name: []const u8) CompileError!u8 {
        if (self.findLocal(name)) |idx| return idx;
        if (self.varnames.items.len >= 256) return error.TooManyLocals;
        const idx = self.varnames.items.len;
        try self.varnames.append(self.allocator, name);
        return @intCast(idx);
    }

    fn addName(self: *AstCompiler, name: []const u8) CompileError!u8 {
        for (self.names.items, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) return @intCast(i);
        }
        if (self.names.items.len >= 256) return error.TooManyNames;
        const idx = self.names.items.len;
        try self.names.append(self.allocator, name);
        return @intCast(idx);
    }

    fn addIntConstant(self: *AstCompiler, value: i64) CompileError!u8 {
        return self.addConstant(.{ .int = value });
    }

    fn addFloatConstant(self: *AstCompiler, value: f64) CompileError!u8 {
        return self.addConstant(.{ .float = value });
    }

    fn addStringConstant(self: *AstCompiler, value: []const u8) CompileError!u8 {
        return self.addConstant(.{ .string = value });
    }

    fn addCodeConstant(self: *AstCompiler, code: *const bytecode.CodeObject) CompileError!u8 {
        return self.addConstant(.{ .code = code });
    }

    fn addConstant(self: *AstCompiler, value: bytecode.PyValue) CompileError!u8 {
        for (self.constants.items, 0..) |c, i| {
            if (self.constantsEqual(c, value)) return @intCast(i);
        }
        if (self.constants.items.len >= 256) return error.TooManyConstants;
        const idx = self.constants.items.len;
        try self.constants.append(self.allocator, value);
        return @intCast(idx);
    }

    fn constantsEqual(self: *AstCompiler, a: bytecode.PyValue, b: bytecode.PyValue) bool {
        _ = self;
        return switch (a) {
            .none => b == .none,
            .bool => |av| b == .bool and b.bool == av,
            .int => |av| b == .int and b.int == av,
            .float => |av| b == .float and b.float == av,
            .string => |av| b == .string and std.mem.eql(u8, av, b.string),
            else => false,
        };
    }

    fn operatorToOpcode(op: ast.Operator) bytecode.Opcode {
        return switch (op) {
            .Add => .ADD,
            .Sub => .SUB,
            .Mult => .MUL,
            .Div => .DIV,
            .FloorDiv => .FLOORDIV,
            .Mod => .MOD,
            .Pow => .POW,
            .LShift => .LSHIFT,
            .RShift => .RSHIFT,
            .BitAnd => .AND,
            .BitOr => .OR,
            .BitXor => .XOR,
            .MatMul => .MATMUL,
        };
    }

    fn compareOpToOpcode(op: ast.CompareOp) bytecode.Opcode {
        return switch (op) {
            .Lt => .LT,
            .LtEq => .LE,
            .Eq => .EQ,
            .NotEq => .NE,
            .Gt => .GT,
            .GtEq => .GE,
            .Is => .IS,
            .IsNot => .IS_NOT,
            .In => .IN,
            .NotIn => .NOT_IN,
        };
    }
};
