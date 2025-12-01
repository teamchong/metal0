/// Arithmetic operations: add, sub, mul, div, mod, pow, floor division
/// Handles BigInt operations, string concatenation, list concatenation, string repetition
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;
const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;

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
        .attribute => true,
        .compare => true,
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
            const genStringFormat = @import("./formatting.zig").genStringFormat;
            try genStringFormat(self, binop);
            return;
        }
        // If type is unknown (e.g., anytype parameter), use runtime dispatch
        if (left_type == .unknown) {
            // Generate runtime type check: if type is string, do formatting; else do modulo
            try self.emit("runtime.pyMod(__global_allocator, ");
            try genExpr(self, binop.left.*);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
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
            // Small constant positive exponent - use i64
            try self.emit("std.math.pow(i64, ");
            try genExpr(self, binop.left.*);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
            return;
        }
        // Runtime exponent (could be negative) - use f64 for safety
        // Python: 10 ** -1 = 0.1 (float), 10 ** random.randint(-100, 100) could be negative
        try self.emit("std.math.pow(f64, @as(f64, @floatFromInt(");
        try genExpr(self, binop.left.*);
        try self.emit(")), @as(f64, @floatFromInt(");
        try genExpr(self, binop.right.*);
        try self.emit(")))");
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
            // Python `not x` semantics depend on type:
            // - strings: empty string is falsy -> x.len == 0
            // - lists: empty list is falsy -> x.items.len == 0
            // - int/float: 0 is falsy -> x == 0
            // - bool: just negate
            const operand_type = try self.inferExprScoped(unaryop.operand.*);
            if (@as(std.meta.Tag(@TypeOf(operand_type)), operand_type) == .string) {
                // not string -> string.len == 0
                try self.emit("(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(").len == 0");
            } else if (operand_type == .list) {
                // not list -> list.items.len == 0
                try self.emit("(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(").items.len == 0");
            } else {
                try self.emit("!(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(")");
            }
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
