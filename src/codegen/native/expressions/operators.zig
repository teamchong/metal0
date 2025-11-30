/// Operator code generation
/// Handles binary ops, unary ops, comparisons, and boolean operations
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const expressions = @import("../expressions.zig");
const genExpr = expressions.genExpr;

/// Check if an expression is a call to eval()
fn isEvalCall(expr: ast.Node) bool {
    if (expr != .call) return false;
    const call = expr.call;
    if (call.func.* != .name) return false;
    return std.mem.eql(u8, call.func.name.id, "eval");
}

/// Check if an expression produces a Zig block expression that needs parentheses
fn producesBlockExpression(expr: ast.Node) bool {
    return switch (expr) {
        .subscript => true,
        .list => true,
        .dict => true,
        .listcomp => true,
        .dictcomp => true,
        .genexp => true,
        .if_expr => true,
        .call => true,
        .attribute => true, // field access on block expr wraps in block
        .compare => true, // comparisons need parens in arithmetic: (b>a)-(b<a)
        else => false,
    };
}

/// Generate expression, wrapping in parentheses if it's a block expression
fn genExprWrapped(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    if (producesBlockExpression(expr)) {
        try self.emit("(");
        try genExpr(self, expr);
        try self.emit(")");
    } else {
        try genExpr(self, expr);
    }
}

/// Recursively collect all parts of a string concatenation chain
fn collectConcatParts(self: *NativeCodegen, node: ast.Node, parts: *std.ArrayList(ast.Node)) CodegenError!void {
    if (node == .binop and node.binop.op == .Add) {
        const left_type = try self.inferExprScoped(node.binop.left.*);
        const right_type = try self.inferExprScoped(node.binop.right.*);

        // Only flatten if this is string concatenation
        if (left_type == .string or right_type == .string) {
            try collectConcatParts(self, node.binop.left.*, parts);
            try collectConcatParts(self, node.binop.right.*, parts);
            return;
        }
    }

    // Base case: not a string concatenation binop, add to parts
    try parts.append(self.allocator, node);
}

const NativeType = @import("../../../analysis/native_types/core.zig").NativeType;

/// Generate BigInt binary operations using method calls
fn genBigIntBinOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    _ = left_type;
    const alloc_name = "__global_allocator";

    // Helper to wrap right operand in BigInt if needed
    const emitRightOperand = struct {
        fn emit(s: *NativeCodegen, rtype: NativeType, right: *const ast.Node, aname: []const u8) CodegenError!void {
            if (rtype == .bigint) {
                // Already BigInt - pass as pointer
                try s.emit("&");
                try genExpr(s, right.*);
            } else if (rtype == .int) {
                // Small int - convert to BigInt first using a block
                try s.emit("&(runtime.BigInt.fromInt(");
                try s.emit(aname);
                try s.emit(", ");
                try genExpr(s, right.*);
                try s.emit(") catch unreachable)");
            } else {
                // Unknown - try to convert
                try s.emit("&(runtime.BigInt.fromInt(");
                try s.emit(aname);
                try s.emit(", @as(i64, ");
                try genExpr(s, right.*);
                try s.emit(")) catch unreachable)");
            }
        }
    }.emit;

    switch (binop.op) {
        .Add => {
            // bigint.add(&other, allocator)
            // Wrap left in parens for proper precedence: (left_expr).add(...)
            try self.emit("((");
            try genExpr(self, binop.left.*);
            try self.emit(").add(");
            try emitRightOperand(self, right_type, binop.right, alloc_name);
            try self.emit(", ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable)");
        },
        .Sub => {
            try self.emit("((");
            try genExpr(self, binop.left.*);
            try self.emit(").sub(");
            try emitRightOperand(self, right_type, binop.right, alloc_name);
            try self.emit(", ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable)");
        },
        .Mult => {
            try self.emit("((");
            try genExpr(self, binop.left.*);
            try self.emit(").mul(");
            try emitRightOperand(self, right_type, binop.right, alloc_name);
            try self.emit(", ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable)");
        },
        .FloorDiv => {
            try self.emit("((");
            try genExpr(self, binop.left.*);
            try self.emit(").floorDiv(");
            try emitRightOperand(self, right_type, binop.right, alloc_name);
            try self.emit(", ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable)");
        },
        .Mod => {
            try self.emit("((");
            try genExpr(self, binop.left.*);
            try self.emit(").mod(");
            try emitRightOperand(self, right_type, binop.right, alloc_name);
            try self.emit(", ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable)");
        },
        .RShift => {
            // bigint.shr(shift_amount, allocator)
            try self.emit("((");
            try genExpr(self, binop.left.*);
            try self.emit(").shr(@as(usize, @intCast(");
            try genExpr(self, binop.right.*);
            try self.emit(")), ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable)");
        },
        .LShift => {
            try self.emit("((");
            try genExpr(self, binop.left.*);
            try self.emit(").shl(@as(usize, @intCast(");
            try genExpr(self, binop.right.*);
            try self.emit(")), ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable)");
        },
        .BitAnd => {
            try self.emit("((");
            try genExpr(self, binop.left.*);
            try self.emit(").bitAnd(");
            try emitRightOperand(self, right_type, binop.right, alloc_name);
            try self.emit(", ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable)");
        },
        .BitOr => {
            try self.emit("((");
            try genExpr(self, binop.left.*);
            try self.emit(").bitOr(");
            try emitRightOperand(self, right_type, binop.right, alloc_name);
            try self.emit(", ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable)");
        },
        .BitXor => {
            try self.emit("((");
            try genExpr(self, binop.left.*);
            try self.emit(").bitXor(");
            try emitRightOperand(self, right_type, binop.right, alloc_name);
            try self.emit(", ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable)");
        },
        .Pow => {
            // bigint.pow(exp, allocator) - exp must be u32
            try self.emit("((");
            try genExpr(self, binop.left.*);
            try self.emit(").pow(@as(u32, @intCast(");
            try genExpr(self, binop.right.*);
            try self.emit(")), ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable)");
        },
        .Div => {
            // BigInt division - use floorDiv for integer result
            try self.emit("((");
            try genExpr(self, binop.left.*);
            try self.emit(").floorDiv(");
            try emitRightOperand(self, right_type, binop.right, alloc_name);
            try self.emit(", ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable)");
        },
        else => {
            // Unsupported BigInt op - fall back to error
            try self.emit("@compileError(\"Unsupported BigInt operation\")");
        },
    }
}

/// Generate BigInt binary operations when RIGHT operand is BigInt (e.g., 0 - bigint)
/// Converts left to BigInt first, then calls the appropriate method
fn genBigIntBinOpRightBig(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, _: NativeType) CodegenError!void {
    const alloc_name = "__global_allocator";

    // Helper to emit left operand converted to BigInt
    // Always wraps in parens to handle catch precedence: (bigint_expr).method()
    const emitLeftAsBigInt = struct {
        fn emit(s: *NativeCodegen, ltype: NativeType, left: *const ast.Node, aname: []const u8) CodegenError!void {
            if (ltype == .bigint) {
                // Wrap in parens for proper precedence with catch: (expr catch unreachable).method()
                try s.emit("(");
                try genExpr(s, left.*);
                try s.emit(")");
            } else if (ltype == .int or ltype == .usize) {
                try s.emit("(runtime.BigInt.fromInt(");
                try s.emit(aname);
                try s.emit(", ");
                try genExpr(s, left.*);
                try s.emit(") catch unreachable)");
            } else {
                // Unknown - try to convert as i64
                try s.emit("(runtime.BigInt.fromInt(");
                try s.emit(aname);
                try s.emit(", @as(i64, ");
                try genExpr(s, left.*);
                try s.emit(")) catch unreachable)");
            }
        }
    }.emit;

    switch (binop.op) {
        .Add => {
            try emitLeftAsBigInt(self, left_type, binop.left, alloc_name);
            try self.emit(".add(&(");
            try genExpr(self, binop.right.*);
            try self.emit("), ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable");
        },
        .Sub => {
            try emitLeftAsBigInt(self, left_type, binop.left, alloc_name);
            try self.emit(".sub(&(");
            try genExpr(self, binop.right.*);
            try self.emit("), ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable");
        },
        .Mult => {
            try emitLeftAsBigInt(self, left_type, binop.left, alloc_name);
            try self.emit(".mul(&(");
            try genExpr(self, binop.right.*);
            try self.emit("), ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable");
        },
        .FloorDiv => {
            try emitLeftAsBigInt(self, left_type, binop.left, alloc_name);
            try self.emit(".floorDiv(&(");
            try genExpr(self, binop.right.*);
            try self.emit("), ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable");
        },
        .Mod => {
            try emitLeftAsBigInt(self, left_type, binop.left, alloc_name);
            try self.emit(".mod(&(");
            try genExpr(self, binop.right.*);
            try self.emit("), ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable");
        },
        else => {
            // Unsupported - fall back to error
            try self.emit("@compileError(\"Unsupported BigInt operation with right bigint\")");
        },
    }
}

/// Generate binary operations (+, -, *, /, %, //)
pub fn genBinOp(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    // Check for BigInt operations first
    // Use scope-aware type inference to prevent cross-function type pollution
    const bigint_left_type = try self.inferExprScoped(binop.left.*);
    const bigint_right_type = try self.inferExprScoped(binop.right.*);

    // If left operand is BigInt, use BigInt method calls
    if (bigint_left_type == .bigint) {
        try genBigIntBinOp(self, binop, bigint_left_type, bigint_right_type);
        return;
    }

    // If right operand is BigInt (e.g., 0 - bigint), convert left to BigInt and use BigInt ops
    if (bigint_right_type == .bigint) {
        try genBigIntBinOpRightBig(self, binop, bigint_left_type, bigint_right_type);
        return;
    }

    // Check if this is string concatenation
    if (binop.op == .Add) {
        // Use scope-aware type inference to prevent cross-function type pollution
        const left_type = try self.inferExprScoped(binop.left.*);
        const right_type = try self.inferExprScoped(binop.right.*);

        if (left_type == .string or right_type == .string) {
            // Flatten nested concatenations to avoid intermediate allocations
            var parts = std.ArrayList(ast.Node){};
            defer parts.deinit(self.allocator);

            try collectConcatParts(self, ast.Node{ .binop = binop }, &parts);

            // Get allocator name based on scope
            const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

            // Generate single concat call with all parts
            try self.emit("try std.mem.concat(");
            try self.emit(alloc_name);
            try self.emit(", u8, &[_][]const u8{ ");
            for (parts.items, 0..) |part, i| {
                if (i > 0) try self.emit(", ");
                try genExpr(self, part);
            }
            try self.emit(" })");
            return;
        }

        // Check for list concatenation: list + list or array + array
        // Also check AST nodes for list literals since type inference may return .unknown
        if (left_type == .list or right_type == .list or
            binop.left.* == .list or binop.right.* == .list)
        {
            // List/array concatenation: use runtime.concat which handles both
            try self.emit("runtime.concat(");
            try genExpr(self, binop.left.*);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
            return;
        }
    }

    // Check if this is string multiplication (str * n or n * str)
    if (binop.op == .Mult) {
        const left_type = try self.inferExprScoped(binop.left.*);
        const right_type = try self.inferExprScoped(binop.right.*);

        // str * n -> repeat string n times
        if (left_type == .string and (right_type == .int or right_type == .unknown)) {
            const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
            try self.emit("runtime.strRepeat(");
            try self.emit(alloc_name);
            try self.emit(", ");
            try genExpr(self, binop.left.*);
            try self.emit(", @as(usize, @intCast(");
            try genExpr(self, binop.right.*);
            try self.emit(")))");
            return;
        }

        // unknown * int - could be string repeat in inline for context
        // Generate comptime type check
        if (left_type == .unknown and (right_type == .int or right_type == .unknown)) {
            const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
            try self.emit("blk: { const _lhs = ");
            try genExpr(self, binop.left.*);
            try self.emit("; const _rhs = ");
            try genExpr(self, binop.right.*);
            try self.emit("; break :blk if (@TypeOf(_lhs) == []const u8) runtime.strRepeat(");
            try self.emit(alloc_name);
            try self.emit(", _lhs, @as(usize, @intCast(_rhs))) else _lhs * _rhs; }");
            return;
        }
        // n * str -> repeat string n times
        if (right_type == .string and (left_type == .int or left_type == .unknown)) {
            const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
            try self.emit("runtime.strRepeat(");
            try self.emit(alloc_name);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(", @as(usize, @intCast(");
            try genExpr(self, binop.left.*);
            try self.emit(")))");
            return;
        }
    }

    // Regular numeric operations
    // Special handling for modulo / string formatting
    if (binop.op == .Mod) {
        // Check if this is Python string formatting: "%d" % value
        const left_type = try self.inferExprScoped(binop.left.*);
        if (left_type == .string or (binop.left.* == .constant and binop.left.constant.value == .string)) {
            // Python string formatting: "format" % value(s)
            try genStringFormat(self, binop);
            return;
        }
        // Numeric modulo
        try self.emit("@rem(");
        try genExpr(self, binop.left.*);
        try self.emit(", ");
        try genExpr(self, binop.right.*);
        try self.emit(")");
        return;
    }

    // Special handling for floor division
    if (binop.op == .FloorDiv) {
        try self.emit("@divFloor(");
        try genExpr(self, binop.left.*);
        try self.emit(", ");
        try genExpr(self, binop.right.*);
        try self.emit(")");
        return;
    }

    // Special handling for power
    if (binop.op == .Pow) {
        // Check if exponent is large enough to need BigInt
        if (binop.right.* == .constant and binop.right.constant.value == .int) {
            const exp = binop.right.constant.value.int;
            if (exp >= 20) {
                // Use BigInt for large exponents
                const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
                try self.emit("(runtime.BigInt.fromInt(");
                try self.emit(alloc_name);
                try self.emit(", ");
                try genExpr(self, binop.left.*);
                try self.emit(") catch unreachable).pow(@as(u32, @intCast(");
                try genExpr(self, binop.right.*);
                try self.emit(")), ");
                try self.emit(alloc_name);
                try self.emit(") catch unreachable");
                return;
            }
        }
        try self.emit("std.math.pow(i64, ");
        try genExpr(self, binop.left.*);
        try self.emit(", ");
        try genExpr(self, binop.right.*);
        try self.emit(")");
        return;
    }

    // Special handling for division - can throw ZeroDivisionError
    if (binop.op == .Div) {
        // Check if this is Path / string (path join)
        const left_type = try self.inferExprScoped(binop.left.*);
        if (left_type == .path) {
            // Path / "component" -> Path.join("component")
            try genExpr(self, binop.left.*);
            try self.emit(".join(");
            try genExpr(self, binop.right.*);
            try self.emit(")");
            return;
        }

        // True division (/) - always returns float
        // At module level (indent_level == 0), we can't use 'try', so use direct division
        if (self.indent_level == 0) {
            // Direct division for module-level constants (assume no divide-by-zero)
            try self.emit("(@as(f64, @floatFromInt(");
            try genExpr(self, binop.left.*);
            try self.emit(")) / @as(f64, @floatFromInt(");
            try genExpr(self, binop.right.*);
            try self.emit(")))");
        } else {
            try self.emit("try runtime.divideFloat(");
            try genExpr(self, binop.left.*);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
        }
        return;
    }

    // Special handling for floor division - returns int
    if (binop.op == .FloorDiv) {
        // At module level (indent_level == 0), we can't use 'try'
        if (self.indent_level == 0) {
            try self.emit("@divFloor(");
            try genExpr(self, binop.left.*);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
        } else {
            try self.emit("try runtime.divideInt(");
            try genExpr(self, binop.left.*);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
        }
        return;
    }

    // Special handling for modulo - can throw ZeroDivisionError
    if (binop.op == .Mod) {
        // At module level (indent_level == 0), we can't use 'try'
        if (self.indent_level == 0) {
            try self.emit("@mod(");
            try genExpr(self, binop.left.*);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
        } else {
            try self.emit("try runtime.moduloInt(");
            try genExpr(self, binop.left.*);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
        }
        return;
    }

    // Matrix multiplication (@) - call __matmul__ or __rmatmul__ method on object
    if (binop.op == .MatMul) {
        const left_type = try self.inferExprScoped(binop.left.*);
        const right_type = try self.inferExprScoped(binop.right.*);

        if (left_type == .class_instance or left_type == .unknown) {
            // Left is a class, call __matmul__: try left.__matmul__(allocator, right)
            try self.emit("try ");
            try genExpr(self, binop.left.*);
            try self.emit(".__matmul__(__global_allocator, ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
        } else if (right_type == .class_instance or right_type == .unknown) {
            // Right is a class, call __rmatmul__: try right.__rmatmul__(allocator, left)
            try self.emit("try ");
            try genExpr(self, binop.right.*);
            try self.emit(".__rmatmul__(__global_allocator, ");
            try genExpr(self, binop.left.*);
            try self.emit(")");
        } else {
            // For numpy arrays, use numpy.matmulAuto
            try self.emit("try numpy.matmulAuto(");
            try genExpr(self, binop.left.*);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(", allocator)");
        }
        return;
    }

    // Check for large shifts that require BigInt
    // e.g., 1 << 100000 exceeds i64 range, needs BigInt
    // Also need BigInt when RHS is not comptime-known (Zig requires fixed-width int for LHS if RHS unknown)
    if (binop.op == .LShift) {
        const is_comptime_shift = binop.right.* == .constant and binop.right.constant.value == .int;
        const is_large_shift = is_comptime_shift and binop.right.constant.value.int >= 63;

        // Use BigInt for large shifts OR when shift amount is not comptime-known
        if (is_large_shift or !is_comptime_shift) {
            const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
            try self.emit("(runtime.BigInt.fromInt(");
            try self.emit(alloc_name);
            try self.emit(", ");
            try genExpr(self, binop.left.*);
            try self.emit(") catch unreachable).shl(@as(usize, @intCast(");
            try genExpr(self, binop.right.*);
            try self.emit(")), ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable");
            return;
        }
    }

    // Check for type mismatches between usize and i64
    const left_type = try self.inferExprScoped(binop.left.*);
    const right_type = try self.inferExprScoped(binop.right.*);

    const left_is_usize = (left_type == .usize);
    const left_is_int = (left_type == .int);
    const right_is_usize = (right_type == .usize);
    const right_is_int = (right_type == .int);

    // If mixing usize and i64, cast to i64 for the operation
    const needs_cast = (left_is_usize and right_is_int) or (left_is_int and right_is_usize);

    try self.emit("(");

    // Cast left operand if needed
    if (left_is_usize and needs_cast) {
        try self.emit("@as(i64, @intCast(");
    }
    // Use genExprWrapped to add parens around comparisons, etc.
    try genExprWrapped(self, binop.left.*);
    if (left_is_usize and needs_cast) {
        try self.emit("))");
    }

    const op_str = switch (binop.op) {
        .Add => " + ",
        .Sub => " - ",
        .Mult => " * ",
        .BitAnd => " & ",
        .BitOr => " | ",
        .BitXor => " ^ ",
        .LShift => " << ",
        .RShift => " >> ",
        else => " ? ",
    };
    try self.emit(op_str);

    // Cast right operand if needed
    if (right_is_usize and needs_cast) {
        try self.emit("@as(i64, @intCast(");
    }
    // Use genExprWrapped to add parens around comparisons, etc.
    try genExprWrapped(self, binop.right.*);
    if (right_is_usize and needs_cast) {
        try self.emit("))");
    }

    try self.emit(")");
}

/// Generate unary operations (not, -, ~)
pub fn genUnaryOp(self: *NativeCodegen, unaryop: ast.Node.UnaryOp) CodegenError!void {
    switch (unaryop.op) {
        .Not => {
            try self.emit("!(");
            try genExpr(self, unaryop.operand.*);
            try self.emit(")");
        },
        .USub => {
            // In Python, -bool converts to int first: -True = -1, -False = 0
            const operand_type = try self.inferExprScoped(unaryop.operand.*);
            if (operand_type == .bool) {
                try self.emit("-@as(i64, @intFromBool(");
                try genExpr(self, unaryop.operand.*);
                try self.emit("))");
            } else if (operand_type == .bigint) {
                // BigInt negation: clone and negate
                const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
                try self.emit("blk: { var __tmp = (");
                try genExpr(self, unaryop.operand.*);
                try self.emit(").clone(");
                try self.emit(alloc_name);
                try self.emit(") catch unreachable; __tmp.negate(); break :blk __tmp; }");
            } else if (operand_type == .unknown) {
                // Unknown type (e.g., anytype parameter) - use comptime type check
                const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
                try self.emit("blk: { const __v = ");
                try genExpr(self, unaryop.operand.*);
                try self.emit("; const __T = @TypeOf(__v); break :blk if (@typeInfo(__T) == .@\"struct\" and @hasDecl(__T, \"negate\")) val: { var __tmp = __v.clone(");
                try self.emit(alloc_name);
                try self.emit(") catch unreachable; __tmp.negate(); break :val __tmp; } else -__v; }");
            } else {
                try self.emit("-(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(")");
            }
        },
        .UAdd => {
            // In Python, +bool converts to int: +True = 1, +False = 0
            const operand_type = try self.inferExprScoped(unaryop.operand.*);
            if (operand_type == .bool) {
                try self.emit("@as(i64, @intFromBool(");
                try genExpr(self, unaryop.operand.*);
                try self.emit("))");
            } else {
                // Non-bool: unary plus is a no-op
                try self.emit("(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(")");
            }
        },
        .Invert => {
            // Bitwise NOT: ~x in Zig
            // Cast to i64 to handle comptime_int literals
            try self.emit("~@as(i64, ");
            try genExpr(self, unaryop.operand.*);
            try self.emit(")");
        },
    }
}

/// Generate comparison operations (==, !=, <, <=, >, >=)
/// Handles Python chained comparisons: 1 < x < 10 becomes (1 < x) and (x < 10)
pub fn genCompare(self: *NativeCodegen, compare: ast.Node.Compare) CodegenError!void {
    // Check if we're comparing strings (need std.mem.eql instead of ==)
    const left_type = try self.inferExprScoped(compare.left.*);

    // NumPy array comparisons return boolean arrays (element-wise)
    // Only supports single comparison (no chained comparisons for arrays)
    if (left_type == .numpy_array and compare.ops.len == 1) {
        const op = compare.ops[0];
        const op_str = switch (op) {
            .Lt => ".lt",
            .LtEq => ".le",
            .Gt => ".gt",
            .GtEq => ".ge",
            .Eq => ".eq",
            .NotEq => ".ne",
            else => null,
        };

        if (op_str) |op_enum| {
            // Check if right side is a constant (scalar comparison)
            const right = compare.comparators[0];
            const right_type = try self.inferExprScoped(right);

            if (right_type == .int or right_type == .float or
                (right == .constant and (right.constant.value == .int or right.constant.value == .float)))
            {
                // arr > scalar → numpy.compareScalar(arr, scalar, .gt, allocator)
                try self.emit("try numpy.compareScalar(");
                try genExpr(self, compare.left.*);
                try self.emit(", @as(f64, ");
                try genExpr(self, right);
                try self.emit("), ");
                try self.emit(op_enum);
                try self.emit(", allocator)");
            } else {
                // arr1 > arr2 → numpy.compareArrays(arr1, arr2, .gt, allocator)
                try self.emit("try numpy.compareArrays(");
                try genExpr(self, compare.left.*);
                try self.emit(", ");
                try genExpr(self, right);
                try self.emit(", ");
                try self.emit(op_enum);
                try self.emit(", allocator)");
            }
            return;
        }
    }

    // For chained comparisons (more than 1 op), wrap everything in parens
    const is_chained = compare.ops.len > 1;
    if (is_chained) {
        try self.emit("(");
    }

    for (compare.ops, 0..) |op, i| {
        // Add "and" between comparisons for chained comparisons
        if (i > 0) {
            try self.emit(" and ");
        }

        // For chained comparisons, wrap each individual comparison in parens
        if (is_chained) {
            try self.emit("(");
        }

        const right_type = try self.inferExprScoped(compare.comparators[i]);

        // For chained comparisons after the first, left side is the previous comparator
        const current_left = if (i == 0) compare.left.* else compare.comparators[i - 1];
        const current_left_type = if (i == 0) left_type else try self.inferExprScoped(compare.comparators[i - 1]);

        // Special handling for string comparisons
        // Also handle cases where one side is .unknown (e.g., json.loads) comparing to string
        const left_is_string = (current_left_type == .string);
        const right_is_string = (right_type == .string);
        const either_string = left_is_string or right_is_string;
        const neither_unknown = (current_left_type != .unknown and right_type != .unknown);

        if ((left_is_string and right_is_string) or (either_string and !neither_unknown)) {
            switch (op) {
                .Eq => {
                    try self.emit("std.mem.eql(u8, ");
                    try genExpr(self, current_left);
                    try self.emit(", ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(")");
                },
                .NotEq => {
                    try self.emit("!std.mem.eql(u8, ");
                    try genExpr(self, current_left);
                    try self.emit(", ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(")");
                },
                .In => {
                    // String substring check: std.mem.indexOf(u8, haystack, needle) != null
                    try self.emit("(std.mem.indexOf(u8, ");
                    try genExpr(self, compare.comparators[i]); // haystack
                    try self.emit(", ");
                    try genExpr(self, current_left); // needle
                    try self.emit(") != null)");
                },
                .NotIn => {
                    // String substring check (negated)
                    try self.emit("(std.mem.indexOf(u8, ");
                    try genExpr(self, compare.comparators[i]); // haystack
                    try self.emit(", ");
                    try genExpr(self, current_left); // needle
                    try self.emit(") == null)");
                },
                .Is => {
                    // Identity comparison for strings: compare pointer/length
                    try self.emit("(");
                    try genExpr(self, current_left);
                    try self.emit(".ptr == ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(".ptr and ");
                    try genExpr(self, current_left);
                    try self.emit(".len == ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(".len)");
                },
                .IsNot => {
                    // Negated identity comparison for strings
                    try self.emit("(");
                    try genExpr(self, current_left);
                    try self.emit(".ptr != ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(".ptr or ");
                    try genExpr(self, current_left);
                    try self.emit(".len != ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(".len)");
                },
                else => {
                    // String comparison operators other than == and != not supported
                    try genExpr(self, current_left);
                    const op_str = switch (op) {
                        .Lt => " < ",
                        .LtEq => " <= ",
                        .Gt => " > ",
                        .GtEq => " >= ",
                        else => " == ", // Fallback to == for any unknown ops
                    };
                    try self.emit(op_str);
                    try genExpr(self, compare.comparators[i]);
                },
            }
        }
        // Handle 'in' operator for lists
        else if (op == .In or op == .NotIn) {
            if (right_type == .list) {
                // List membership check: std.mem.indexOfScalar(T, slice, value) != null
                const elem_type = right_type.list.*;
                const type_str = elem_type.toSimpleZigType();

                try self.emit("(std.mem.indexOfScalar(");
                try self.emit(type_str);
                try self.emit(", ");
                try genExpr(self, compare.comparators[i]); // list/slice
                try self.emit(", ");
                try genExpr(self, current_left); // item to search for

                if (op == .In) {
                    try self.emit(") != null)");
                } else {
                    try self.emit(") == null)");
                }
            } else if (right_type == .dict) {
                // Dict key check: dict.contains(key)
                // For dict literals, wrap in block to assign to temp var
                const is_literal = compare.comparators[i] == .dict;
                if (is_literal) {
                    try self.emit("(blk: { const __d = ");
                    try genExpr(self, compare.comparators[i]); // dict literal
                    if (op == .In) {
                        try self.emit("; break :blk __d.contains(");
                    } else {
                        try self.emit("; break :blk !__d.contains(");
                    }
                    try genExpr(self, current_left); // key
                    try self.emit("); })");
                } else {
                    if (op == .In) {
                        try genExpr(self, compare.comparators[i]); // dict var
                        try self.emit(".contains(");
                        try genExpr(self, current_left); // key
                        try self.emit(")");
                    } else {
                        try self.emit("!");
                        try genExpr(self, compare.comparators[i]); // dict var
                        try self.emit(".contains(");
                        try genExpr(self, current_left); // key
                        try self.emit(")");
                    }
                }
            } else {
                // Fallback for arrays and unrecognized types
                // Infer element type from the item being searched for

                // String arrays need special handling - can't use indexOfScalar
                // because strings require std.mem.eql for comparison, not ==
                if (current_left_type == .string) {
                    // For 'not in', wrap in negation by emitting ! first
                    if (op == .NotIn) {
                        try self.emit("!");
                    }
                    // Generate inline block expression that loops through array
                    // Use unique label to avoid collisions with nested expressions
                    const in_label_id = self.block_label_counter;
                    self.block_label_counter += 1;
                    try self.output.writer(self.allocator).print("(in_{d}: {{\n", .{in_label_id});
                    try self.emit("for (");
                    try genExpr(self, compare.comparators[i]); // array
                    try self.emit(") |__item| {\n");
                    try self.emit("if (std.mem.eql(u8, __item, ");
                    try genExpr(self, current_left); // search string
                    try self.output.writer(self.allocator).print(")) break :in_{d} true;\n", .{in_label_id});
                    try self.emit("}\n");
                    try self.output.writer(self.allocator).print("break :in_{d} false;\n", .{in_label_id});
                    try self.emit("})");
                } else {
                    // Integer and float arrays use indexOfScalar
                    // Use std.meta.Elem to get element type - works for both arrays and slices
                    // Use unique label to avoid collisions with nested expressions
                    const in_label_id = self.block_label_counter;
                    self.block_label_counter += 1;

                    try self.output.writer(self.allocator).print("in_{d}: {{ const __arr = ", .{in_label_id});
                    try genExpr(self, compare.comparators[i]); // array/container
                    try self.emit("; const __val = ");
                    try genExpr(self, current_left); // item to search for
                    // Use std.meta.Elem which works for arrays, slices, and pointers
                    try self.output.writer(self.allocator).print("; const T = std.meta.Elem(@TypeOf(__arr)); break :in_{d} (std.mem.indexOfScalar(T, __arr, __val)", .{in_label_id});
                    if (op == .In) {
                        try self.emit(" != null); }");
                    } else {
                        try self.emit(" == null); }");
                    }
                }
            }
        }
        // Special handling for None comparisons
        else if (current_left_type == .none or right_type == .none) {
            // Check if this is comparing an optional parameter (e.g., base: ?i64) to None
            // If left side is a name that was renamed (optional param), compare to null instead
            // This handles: "if base is None:" -> "if (base == null)"
            const is_optional_param_check = blk: {
                if (right_type == .none and current_left == .name) {
                    const var_name = current_left.name.id;
                    // Check if this variable was renamed from a parameter with None default
                    if (self.var_renames.get(var_name) != null) {
                        break :blk true;
                    }
                    // Also check if it's a method parameter with optional type
                    // (function_signatures tracks methods with defaults)
                    if (self.current_class_name) |class_name| {
                        if (self.current_function_name) |func_name| {
                            var key_buf: [512]u8 = undefined;
                            const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ class_name, func_name }) catch "";
                            if (self.function_signatures.get(key)) |_| {
                                // This method has optional params - assume the variable could be optional
                                break :blk true;
                            }
                        }
                    }
                }
                break :blk false;
            };

            if (is_optional_param_check) {
                // Generate: var == null (or != null for "is not None")
                try genExpr(self, current_left);
                if (op == .Is or op == .Eq) {
                    try self.emit(" == null");
                } else {
                    try self.emit(" != null");
                }
            }
            // None comparisons with mixed types: result is known at compile time
            // but we must reference the non-None variable to avoid "unused" errors
            else {
                const cleft_tag = @as(std.meta.Tag(@TypeOf(current_left_type)), current_left_type);
                const right_tag = @as(std.meta.Tag(@TypeOf(right_type)), right_type);
                if (cleft_tag != right_tag) {
                    // One is None, other is not - emit block that references the non-None side
                    // The None side (?void) is allowed to be unused
                    const result = switch (op) {
                        .Eq => "false",
                        .NotEq => "true",
                        else => "false",
                    };
                    // Just emit the known result - variables may be used elsewhere so no need to reference them
                    try self.emit(result);
                } else {
                    // Both are None - compare normally
                    try genExpr(self, current_left);
                    const op_str = switch (op) {
                        .Eq => " == ",
                        .NotEq => " != ",
                        else => " == ", // Other comparisons default to ==
                    };
                    try self.emit(op_str);
                    try genExpr(self, compare.comparators[i]);
                }
            }
        }
        // Handle comparisons involving eval() - returns *PyObject which needs special comparison
        else if (isEvalCall(current_left) or isEvalCall(compare.comparators[i])) {
            // eval() returns *PyObject, need to use runtime comparison functions
            const left_is_eval = isEvalCall(current_left);
            const right_is_eval = isEvalCall(compare.comparators[i]);

            // For == and != with eval() result and integer, use pyObjEqInt
            if (op == .Eq or op == .NotEq) {
                if (op == .NotEq) {
                    try self.emit("!");
                }
                if (left_is_eval and !right_is_eval) {
                    // eval(...) == value
                    try self.emit("runtime.pyObjEqInt(");
                    try genExpr(self, current_left);
                    try self.emit(", ");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(")");
                } else if (right_is_eval and !left_is_eval) {
                    // value == eval(...)
                    try self.emit("runtime.pyObjEqInt(");
                    try genExpr(self, compare.comparators[i]);
                    try self.emit(", ");
                    try genExpr(self, current_left);
                    try self.emit(")");
                } else {
                    // Both are eval() calls - compare as PyObject pointers
                    try genExpr(self, current_left);
                    try self.emit(" == ");
                    try genExpr(self, compare.comparators[i]);
                }
            } else {
                // For <, >, <=, >= with eval(), extract int value then compare
                // This is a simplification - full Python would handle more types
                try self.emit("(runtime.pyObjToInt(");
                try genExpr(self, current_left);
                try self.emit(")");
                const op_str = switch (op) {
                    .Lt => " < ",
                    .LtEq => " <= ",
                    .Gt => " > ",
                    .GtEq => " >= ",
                    else => " == ",
                };
                try self.emit(op_str);
                if (right_is_eval) {
                    try self.emit("runtime.pyObjToInt(");
                }
                try genExpr(self, compare.comparators[i]);
                if (right_is_eval) {
                    try self.emit(")");
                }
                try self.emit(")");
            }
        }
        // Handle 'is' and 'is not' identity operators
        else if (op == .Is or op == .IsNot) {
            // For primitives (int, bool, None), identity is same as equality
            // For objects/slices, compare pointer addresses
            try genExpr(self, current_left);
            if (op == .Is) {
                try self.emit(" == ");
            } else {
                try self.emit(" != ");
            }
            try genExpr(self, compare.comparators[i]);
        }
        // Handle BigInt or unknown type comparisons (anytype parameters)
        else if (current_left_type == .bigint or right_type == .bigint or
            current_left_type == .unknown or right_type == .unknown)
        {
            // Use runtime.bigIntCompare for safe comparison
            try self.emit("runtime.bigIntCompare(");
            try genExpr(self, current_left);
            try self.emit(", ");
            try genExpr(self, compare.comparators[i]);
            switch (op) {
                .Eq => try self.emit(", .eq)"),
                .NotEq => try self.emit(", .ne)"),
                .Lt => try self.emit(", .lt)"),
                .LtEq => try self.emit(", .le)"),
                .Gt => try self.emit(", .gt)"),
                .GtEq => try self.emit(", .ge)"),
                else => try self.emit(", .eq)"),
            }
        } else {
            // Regular comparisons for non-strings
            // Check for type mismatches between usize and i64
            const left_is_usize = (current_left_type == .usize);
            const left_is_int = (current_left_type == .int);
            const right_is_usize = (right_type == .usize);
            const right_is_int = (right_type == .int);

            // If mixing usize and i64, cast to i64 for comparison
            const needs_cast = (left_is_usize and right_is_int) or (left_is_int and right_is_usize);

            // Check if either side is a block expression that needs wrapping
            const left_needs_wrap = producesBlockExpression(current_left);
            const right_needs_wrap = producesBlockExpression(compare.comparators[i]);

            // Cast left operand if needed
            if (left_is_usize and needs_cast) {
                try self.emit("@as(i64, @intCast(");
            }
            // Wrap block expressions in parentheses
            if (left_needs_wrap) try self.emit("(");
            try genExpr(self, current_left);
            if (left_needs_wrap) try self.emit(")");
            if (left_is_usize and needs_cast) {
                try self.emit("))");
            }

            const op_str = switch (op) {
                .Eq => " == ",
                .NotEq => " != ",
                .Lt => " < ",
                .LtEq => " <= ",
                .Gt => " > ",
                .GtEq => " >= ",
                .Is => " == ",
                .IsNot => " != ",
                else => " ? ",
            };
            try self.emit(op_str);

            // Cast right operand if needed
            if (right_is_usize and needs_cast) {
                try self.emit("@as(i64, @intCast(");
            }
            // Wrap block expressions in parentheses
            if (right_needs_wrap) try self.emit("(");
            try genExpr(self, compare.comparators[i]);
            if (right_needs_wrap) try self.emit(")");
            if (right_is_usize and needs_cast) {
                try self.emit("))");
            }
        }

        // Close individual comparison paren for chained comparisons
        if (is_chained) {
            try self.emit(")");
        }
    }

    // Close outer paren for chained comparisons
    if (is_chained) {
        try self.emit(")");
    }
}

/// Generate boolean operations (and, or)
/// Python's and/or return the actual values, not booleans:
/// - "a or b" returns a if truthy, else b
/// - "a and b" returns a if falsy, else b
pub fn genBoolOp(self: *NativeCodegen, boolop: ast.Node.BoolOp) CodegenError!void {
    // Check if all values are booleans - can use simple Zig and/or
    var all_bool = true;
    for (boolop.values) |value| {
        const val_type = self.inferExprScoped(value) catch .unknown;
        if (val_type != .bool) {
            all_bool = false;
            break;
        }
    }

    if (all_bool) {
        const op_str = if (boolop.op == .And) " and " else " or ";
        for (boolop.values, 0..) |value, i| {
            if (i > 0) try self.emit(op_str);
            try genExpr(self, value);
        }
        return;
    }

    // Non-boolean types need Python semantics
    // For "a or b": if truthy(a) then a else b
    // For "a and b": if not truthy(a) then a else b
    // We generate nested ternary expressions
    if (boolop.values.len == 2) {
        const a = boolop.values[0];
        const b = boolop.values[1];

        try self.emit("blk: {\n");
        try self.emit("const _a = ");
        try genExpr(self, a);
        try self.emit(";\n");
        try self.emit("const _b = ");
        try genExpr(self, b);
        try self.emit(";\n");

        if (boolop.op == .Or) {
            // "a or b": return a if truthy, else b
            // For strings: len > 0 is truthy
            try self.emit("break :blk if (runtime.pyTruthy(_a)) _a else _b;\n");
        } else {
            // "a and b": return a if falsy, else b
            try self.emit("break :blk if (!runtime.pyTruthy(_a)) _a else _b;\n");
        }
        try self.emit("}");
        return;
    }

    // For more than 2 values, use simple approach (may not be fully correct but handles common cases)
    const op_str = if (boolop.op == .And) " and " else " or ";
    for (boolop.values, 0..) |value, i| {
        if (i > 0) try self.emit(op_str);
        try self.emit("runtime.pyTruthy(");
        try genExpr(self, value);
        try self.emit(")");
    }
}

/// Generate Python-style string formatting: "%d" % value or "%s %s" % (a, b)
/// Handles both single value and tuple of values
fn genStringFormat(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    // Get the format string
    const format_str = if (binop.left.* == .constant and binop.left.constant.value == .string)
        binop.left.constant.value.string
    else
        null;

    // For simple cases like "%d" % n where n is potentially BigInt, use comptime-aware formatting
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    try self.emitFmt("fmt_{d}: {{\n", .{label_id});
    try self.emit("var buf = std.ArrayList(u8){};\n");
    try self.emitFmt("const writer = buf.writer({s});\n", .{alloc_name});

    // Check if right side is a tuple (multiple values)
    if (binop.right.* == .tuple) {
        // Multiple format arguments: "%s %d" % (name, age)
        const tuple = binop.right.tuple;
        if (format_str) |fmt| {
            // Parse format string and match with tuple elements
            try self.emit("try writer.print(\"");
            // Convert Python format to Zig format
            var i: usize = 0;
            while (i < fmt.len) {
                if (fmt[i] == '%' and i + 1 < fmt.len) {
                    const spec = fmt[i + 1];
                    switch (spec) {
                        'd', 'i' => try self.emit("{any}"),
                        's' => try self.emit("{s}"),
                        'f' => try self.emit("{d}"),
                        'x' => try self.emit("{x}"),
                        'X' => try self.emit("{X}"),
                        'o' => try self.emit("{o}"),
                        'r' => try self.emit("{any}"),
                        '%' => try self.emit("%"),
                        else => {
                            try self.emitFmt("{c}", .{fmt[i]});
                            try self.emitFmt("{c}", .{spec});
                        },
                    }
                    i += 2;
                } else {
                    // Escape braces for Zig format string
                    if (fmt[i] == '{') {
                        try self.emit("{{");
                    } else if (fmt[i] == '}') {
                        try self.emit("}}");
                    } else {
                        try self.emitFmt("{c}", .{fmt[i]});
                    }
                    i += 1;
                }
            }
            try self.emit("\", .{");
            for (tuple.elts, 0..) |elem, j| {
                if (j > 0) try self.emit(", ");
                try genExpr(self, elem);
            }
            try self.emit("});\n");
        } else {
            // Format string is a variable - use runtime formatting
            try self.emit("try writer.print(\"{any}\", .{");
            try genExpr(self, binop.right.*);
            try self.emit("});\n");
        }
    } else {
        // Single format argument: "%d" % n
        if (format_str) |fmt| {
            // Parse format string
            try self.emit("try writer.print(\"");
            var i: usize = 0;
            while (i < fmt.len) {
                if (fmt[i] == '%' and i + 1 < fmt.len) {
                    const spec = fmt[i + 1];
                    switch (spec) {
                        'd', 'i' => try self.emit("{any}"),
                        's' => try self.emit("{s}"),
                        'f' => try self.emit("{d}"),
                        'x' => try self.emit("{x}"),
                        'X' => try self.emit("{X}"),
                        'o' => try self.emit("{o}"),
                        'r' => try self.emit("{any}"),
                        '%' => try self.emit("%"),
                        else => {
                            try self.emitFmt("{c}", .{fmt[i]});
                            try self.emitFmt("{c}", .{spec});
                        },
                    }
                    i += 2;
                } else {
                    if (fmt[i] == '{') {
                        try self.emit("{{");
                    } else if (fmt[i] == '}') {
                        try self.emit("}}");
                    } else {
                        try self.emitFmt("{c}", .{fmt[i]});
                    }
                    i += 1;
                }
            }
            try self.emit("\", .{");
            try genExpr(self, binop.right.*);
            try self.emit("});\n");
        } else {
            // Format string is a variable
            try self.emit("try writer.print(\"{any}\", .{");
            try genExpr(self, binop.right.*);
            try self.emit("});\n");
        }
    }

    try self.emitFmt("break :fmt_{d} try buf.toOwnedSlice({s});\n}}", .{ label_id, alloc_name });
}
