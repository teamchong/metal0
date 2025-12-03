/// Arithmetic operations: add, sub, mul, div, mod, pow, floor division
/// Handles BigInt operations, string concatenation, list concatenation, string repetition
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;
const producesBlockExpression = expressions.producesBlockExpression;
const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
const shared = @import("../../shared_maps.zig");
const BinaryDunders = shared.BinaryDunders;
const ReverseDunders = shared.ReverseDunders;

/// BigInt method names for standard binary operations (left.method(&right, allocator))
const BigIntStdMethods = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Add", "add" }, .{ "Sub", "sub" }, .{ "Mult", "mul" },
    .{ "FloorDiv", "floorDiv" }, .{ "Mod", "mod" },
    .{ "BitAnd", "bitAnd" }, .{ "BitOr", "bitOr" }, .{ "BitXor", "bitXor" },
});

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
    const alloc_name = "__global_allocator";

    // Helper to emit left operand as BigInt value (for .method() calls)
    const emitLeftOperand = struct {
        fn emit(s: *NativeCodegen, ltype: NativeType, left: *const ast.Node, aname: []const u8) CodegenError!void {
            if (ltype == .bigint) {
                // Already BigInt - wrap in parens for method call
                try s.emit("(");
                try genExpr(s, left.*);
                try s.emit(")");
            } else if (ltype == .int) {
                // Check if unbounded (could be i128) vs bounded (i64)
                if (ltype.int.needsBigInt()) {
                    // Unbounded int (e.g., sys.maxsize) - use fromInt128
                    try s.emit("(runtime.BigInt.fromInt128(");
                    try s.emit(aname);
                    try s.emit(", ");
                    try genExpr(s, left.*);
                    try s.emit(") catch unreachable)");
                } else {
                    // Bounded int - use fromInt (i64)
                    try s.emit("(runtime.BigInt.fromInt(");
                    try s.emit(aname);
                    try s.emit(", ");
                    try genExpr(s, left.*);
                    try s.emit(") catch unreachable)");
                }
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

    // Helper to wrap right operand in BigInt if needed
    const emitRightOperand = struct {
        fn emit(s: *NativeCodegen, rtype: NativeType, right: *const ast.Node, aname: []const u8) CodegenError!void {
            if (rtype == .bigint) {
                // Already BigInt - pass as pointer
                try s.emit("&");
                try genExpr(s, right.*);
            } else if (rtype == .int) {
                // Check if unbounded (could be i128) vs bounded (i64)
                if (rtype.int.needsBigInt()) {
                    // Unbounded int (e.g., sys.maxsize) - use fromInt128
                    try s.emit("&(runtime.BigInt.fromInt128(");
                    try s.emit(aname);
                    try s.emit(", ");
                    try genExpr(s, right.*);
                    try s.emit(") catch unreachable)");
                } else {
                    // Bounded int - use fromInt (i64)
                    try s.emit("&(runtime.BigInt.fromInt(");
                    try s.emit(aname);
                    try s.emit(", ");
                    try genExpr(s, right.*);
                    try s.emit(") catch unreachable)");
                }
            } else {
                // Unknown - try to convert as i64
                try s.emit("&(runtime.BigInt.fromInt(");
                try s.emit(aname);
                try s.emit(", @as(i64, ");
                try genExpr(s, right.*);
                try s.emit(")) catch unreachable)");
            }
        }
    }.emit;

    // Standard BigInt operations: left.method(&right, allocator)
    const op_name = @tagName(binop.op);
    if (BigIntStdMethods.get(op_name)) |method| {
        try self.emit("(");
        try emitLeftOperand(self, left_type, binop.left, alloc_name);
        try self.emit(".");
        try self.emit(method);
        try self.emit("(");
        try emitRightOperand(self, right_type, binop.right, alloc_name);
        try self.emit(", ");
        try self.emit(alloc_name);
        try self.emit(") catch unreachable)");
        return;
    }

    switch (binop.op) {
        .RShift => {
            // bigint.shr(shift_amount, allocator)
            try self.emit("(");
            try emitLeftOperand(self, left_type, binop.left, alloc_name);
            try self.emit(".shr(@as(usize, @intCast(");
            try genExpr(self, binop.right.*);
            try self.emit(")), ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable)");
        },
        .LShift => {
            try self.emit("(");
            try emitLeftOperand(self, left_type, binop.left, alloc_name);
            try self.emit(".shl(@as(usize, @intCast(");
            try genExpr(self, binop.right.*);
            try self.emit(")), ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable)");
        },
        .Pow => {
            // bigint.pow(exp, allocator) - exp must be u32
            try self.emit("(");
            try emitLeftOperand(self, left_type, binop.left, alloc_name);
            try self.emit(".pow(@as(u32, @intCast(");
            try genExpr(self, binop.right.*);
            try self.emit(")), ");
            try self.emit(alloc_name);
            try self.emit(") catch unreachable)");
        },
        .Div => {
            // BigInt division - use floorDiv for integer result
            try self.emit("(");
            try emitLeftOperand(self, left_type, binop.left, alloc_name);
            try self.emit(".floorDiv(");
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
fn genBigIntBinOpRightBig(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
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

    // Helper to emit right operand as BigInt pointer
    const emitRightAsBigInt = struct {
        fn emit(s: *NativeCodegen, rtype: NativeType, right: *const ast.Node, aname: []const u8) CodegenError!void {
            if (rtype == .bigint) {
                // Already BigInt - wrap in pointer
                try s.emit("&(");
                try genExpr(s, right.*);
                try s.emit(")");
            } else if (rtype == .int) {
                // Check if unbounded (could be i128) vs bounded (i64)
                if (rtype.int.needsBigInt()) {
                    // Unbounded int (e.g., sys.maxsize) - use fromInt128
                    try s.emit("&(runtime.BigInt.fromInt128(");
                    try s.emit(aname);
                    try s.emit(", ");
                    try genExpr(s, right.*);
                    try s.emit(") catch unreachable)");
                } else {
                    // Bounded int - use fromInt (i64)
                    try s.emit("&(runtime.BigInt.fromInt(");
                    try s.emit(aname);
                    try s.emit(", ");
                    try genExpr(s, right.*);
                    try s.emit(") catch unreachable)");
                }
            } else {
                // Unknown - try to convert as i64
                try s.emit("&(runtime.BigInt.fromInt(");
                try s.emit(aname);
                try s.emit(", @as(i64, ");
                try genExpr(s, right.*);
                try s.emit(")) catch unreachable)");
            }
        }
    }.emit;

    // Use BigIntStdMethods for standard operations (same as genBigIntBinOp)
    if (BigIntStdMethods.get(@tagName(binop.op))) |method| {
        try emitLeftAsBigInt(self, left_type, binop.left, alloc_name);
        try self.emit(".");
        try self.emit(method);
        try self.emit("(");
        try emitRightAsBigInt(self, right_type, binop.right, alloc_name);
        try self.emit(", ");
        try self.emit(alloc_name);
        try self.emit(") catch unreachable");
        return;
    }
    // Unsupported - fall back to error
    try self.emit("@compileError(\"Unsupported BigInt operation with right bigint\")");
}

/// Check if a type requires BigInt representation (explicit bigint or unbounded int)
fn needsBigInt(t: NativeType) bool {
    return t == .bigint or (t == .int and t.int.needsBigInt());
}

/// Generate complex number binary operations
/// Handles: complex + complex, int/float + complex, complex + int/float
fn genComplexBinOp(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    // Helper to emit a value as the real part of a complex number
    const emitAsComplex = struct {
        fn emit(s: *NativeCodegen, node: ast.Node, t: NativeType) CodegenError!void {
            if (t == .complex) {
                // Already complex
                try genExpr(s, node);
            } else if (t == .float) {
                // float -> complex with real part
                try s.emit("runtime.PyComplex.create(");
                try genExpr(s, node);
                try s.emit(", 0.0)");
            } else {
                // int/bool -> complex with real part
                try s.emit("runtime.PyComplex.create(@as(f64, @floatFromInt(");
                try genExpr(s, node);
                try s.emit(")), 0.0)");
            }
        }
    }.emit;

    switch (binop.op) {
        .Add => {
            // complex.add(other)
            try emitAsComplex(self, binop.left.*, left_type);
            try self.emit(".add(");
            try emitAsComplex(self, binop.right.*, right_type);
            try self.emit(")");
        },
        .Sub => {
            // complex.sub(other)
            try emitAsComplex(self, binop.left.*, left_type);
            try self.emit(".sub(");
            try emitAsComplex(self, binop.right.*, right_type);
            try self.emit(")");
        },
        .Mult => {
            // complex.mul(other)
            try emitAsComplex(self, binop.left.*, left_type);
            try self.emit(".mul(");
            try emitAsComplex(self, binop.right.*, right_type);
            try self.emit(")");
        },
        .Div => {
            // complex.div(other)
            try emitAsComplex(self, binop.left.*, left_type);
            try self.emit(".div(");
            try emitAsComplex(self, binop.right.*, right_type);
            try self.emit(")");
        },
        else => {
            // Unsupported complex operation - fall back to error
            try self.emit("@compileError(\"Unsupported complex operation\")");
        },
    }
}

/// Generate binary operations (+, -, *, /, %, //)
pub fn genBinOp(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    // Check for BigInt operations first
    // Use scope-aware type inference to prevent cross-function type pollution
    const bigint_left_type = try self.inferExprScoped(binop.left.*);
    const bigint_right_type = try self.inferExprScoped(binop.right.*);

    // If left operand needs BigInt (explicit bigint or unbounded int), use BigInt method calls
    if (needsBigInt(bigint_left_type)) {
        try genBigIntBinOp(self, binop, bigint_left_type, bigint_right_type);
        return;
    }

    // If right operand needs BigInt (e.g., 0 - bigint), convert left to BigInt and use BigInt ops
    if (needsBigInt(bigint_right_type)) {
        try genBigIntBinOpRightBig(self, binop, bigint_left_type, bigint_right_type);
        return;
    }

    // Check for custom class with dunder methods (e.g., x + 1 calls x.__add__(1))
    // Must check before other type-specific handling
    // IMPORTANT: Only call dunder methods if the CLASS operand is a KNOWN class instance (not anytype)
    // If left is a KNOWN class instance (e.g., self), call left.__add__(right) regardless of right's type
    const left_is_anytype = if (binop.left.* == .name) self.anytype_params.contains(binop.left.name.id) else false;
    const right_is_anytype = if (binop.right.* == .name) self.anytype_params.contains(binop.right.name.id) else false;

    // If left operand is a known class instance (not anytype), call dunder method on left
    if (bigint_left_type == .class_instance and !left_is_anytype) {
        if (BinaryDunders.get(@tagName(binop.op))) |dunder_method| {
            try self.emit("try ");
            try genExpr(self, binop.left.*);
            try self.emit(".");
            try self.emit(dunder_method);
            try self.emit("(__global_allocator, ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
            return;
        }
    }

    // If right operand is a known class instance (not anytype) and left is not class, call __radd__ etc.
    if (bigint_right_type == .class_instance and !right_is_anytype and bigint_left_type != .class_instance) {
        if (ReverseDunders.get(@tagName(binop.op))) |rdunder_method| {
            try self.emit("try ");
            try genExpr(self, binop.right.*);
            try self.emit(".");
            try self.emit(rdunder_method);
            try self.emit("(__global_allocator, ");
            try genExpr(self, binop.left.*);
            try self.emit(")");
            return;
        }
    }

    // Check for complex number operations
    // Must check BOTH Add and Sub for complex operand type coercion
    if (binop.op == .Add or binop.op == .Sub) {
        const left_type = try self.inferExprScoped(binop.left.*);
        const right_type = try self.inferExprScoped(binop.right.*);

        // Handle complex arithmetic: int/float +/- complex -> complex
        if (left_type == .complex or right_type == .complex) {
            try genComplexBinOp(self, binop, left_type, right_type);
            return;
        }
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

        // Check for complex number addition: int/float + complex -> complex
        if (left_type == .complex or right_type == .complex) {
            try genComplexBinOp(self, binop, left_type, right_type);
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
    // Special handling for floor division (//): use @divFloor for Python semantics
    if (binop.op == .FloorDiv) {
        const left_type = try self.inferExprScoped(binop.left.*);
        const right_type = try self.inferExprScoped(binop.right.*);
        try self.emit("@divFloor(");
        if (left_type == .bool) {
            try self.emit("@as(i64, @intFromBool(");
            try genExpr(self, binop.left.*);
            try self.emit("))");
        } else {
            try genExpr(self, binop.left.*);
        }
        try self.emit(", ");
        if (right_type == .bool) {
            try self.emit("@as(i64, @intFromBool(");
            try genExpr(self, binop.right.*);
            try self.emit("))");
        } else {
            try genExpr(self, binop.right.*);
        }
        try self.emit(")");
        return;
    }

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
        // Numeric modulo - use @mod for Python semantics (sign follows divisor)
        const right_type = try self.inferExprScoped(binop.right.*);
        try self.emit("@mod(");
        if (left_type == .bool) {
            try self.emit("@as(i64, @intFromBool(");
            try genExpr(self, binop.left.*);
            try self.emit("))");
        } else {
            try genExpr(self, binop.left.*);
        }
        try self.emit(", ");
        if (right_type == .bool) {
            try self.emit("@as(i64, @intFromBool(");
            try genExpr(self, binop.right.*);
            try self.emit("))");
        } else {
            try genExpr(self, binop.right.*);
        }
        try self.emit(")");
        return;
    }

    // Special handling for power
    if (binop.op == .Pow) {
        // Check types for bool handling
        const left_type = try self.inferExprScoped(binop.left.*);
        const right_type = try self.inferExprScoped(binop.right.*);
        const left_is_bool = (left_type == .bool);
        const right_is_bool = (right_type == .bool);

        // Helper to emit left operand with possible bool conversion
        const emitLeft = struct {
            fn emit(s: *NativeCodegen, binop_inner: ast.Node.BinOp, is_bool: bool) CodegenError!void {
                if (is_bool) {
                    try s.emit("@as(i64, @intFromBool(");
                    try genExpr(s, binop_inner.left.*);
                    try s.emit("))");
                } else {
                    try genExpr(s, binop_inner.left.*);
                }
            }
        }.emit;

        // Helper to emit right operand with possible bool conversion
        const emitRight = struct {
            fn emit(s: *NativeCodegen, binop_inner: ast.Node.BinOp, is_bool: bool) CodegenError!void {
                if (is_bool) {
                    try s.emit("@as(i64, @intFromBool(");
                    try genExpr(s, binop_inner.right.*);
                    try s.emit("))");
                } else {
                    try genExpr(s, binop_inner.right.*);
                }
            }
        }.emit;

        // Check if exponent is large enough to need BigInt
        if (binop.right.* == .constant and binop.right.constant.value == .int) {
            const exp = binop.right.constant.value.int;
            if (exp >= 20) {
                // Use BigInt for large exponents
                const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
                try self.emit("(runtime.BigInt.fromInt(");
                try self.emit(alloc_name);
                try self.emit(", ");
                try emitLeft(self, binop, left_is_bool);
                try self.emit(") catch unreachable).pow(@as(u32, @intCast(");
                try emitRight(self, binop, right_is_bool);
                try self.emit(")), ");
                try self.emit(alloc_name);
                try self.emit(") catch unreachable");
                return;
            }
            // Small constant positive exponent - use i64
            try self.emit("std.math.pow(i64, ");
            try emitLeft(self, binop, left_is_bool);
            try self.emit(", ");
            try emitRight(self, binop, right_is_bool);
            try self.emit(")");
            return;
        }
        // Runtime exponent (could be negative) - use f64 for safety
        // Python: 10 ** -1 = 0.1 (float), 10 ** random.randint(-100, 100) could be negative
        try self.emit("std.math.pow(f64, @as(f64, @floatFromInt(");
        try emitLeft(self, binop, left_is_bool);
        try self.emit(")), @as(f64, @floatFromInt(");
        try emitRight(self, binop, right_is_bool);
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

        const right_type = try self.inferExprScoped(binop.right.*);
        const left_is_bool = (left_type == .bool);
        const right_is_bool = (right_type == .bool);

        // True division (/) - always returns float
        // At module level (indent_level == 0), we can't use 'try', so use direct division
        if (self.indent_level == 0) {
            // Direct division for module-level constants (assume no divide-by-zero)
            try self.emit("(@as(f64, @floatFromInt(");
            if (left_is_bool) {
                try self.emit("@as(i64, @intFromBool(");
                try genExpr(self, binop.left.*);
                try self.emit("))");
            } else {
                try genExpr(self, binop.left.*);
            }
            try self.emit(")) / @as(f64, @floatFromInt(");
            if (right_is_bool) {
                try self.emit("@as(i64, @intFromBool(");
                try genExpr(self, binop.right.*);
                try self.emit("))");
            } else {
                try genExpr(self, binop.right.*);
            }
            try self.emit(")))");
        } else {
            try self.emit("try runtime.divideFloat(");
            if (left_is_bool) {
                try self.emit("@as(i64, @intFromBool(");
                try genExpr(self, binop.left.*);
                try self.emit("))");
            } else {
                try genExpr(self, binop.left.*);
            }
            try self.emit(", ");
            if (right_is_bool) {
                try self.emit("@as(i64, @intFromBool(");
                try genExpr(self, binop.right.*);
                try self.emit("))");
            } else {
                try genExpr(self, binop.right.*);
            }
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
            // Generic fallback - call __matmul__ on left
            try self.emit("try ");
            try genExpr(self, binop.left.*);
            try self.emit(".__matmul__(__global_allocator, ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
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
    const left_is_bool = (left_type == .bool);
    const right_is_usize = (right_type == .usize);
    const right_is_int = (right_type == .int);
    const right_is_bool = (right_type == .bool);

    // Python: bool & bool = bool, bool | bool = bool, bool ^ bool = bool
    // When both operands are bools and op is bitwise, result is bool
    if (left_is_bool and right_is_bool and
        (binop.op == .BitAnd or binop.op == .BitOr or binop.op == .BitXor))
    {
        try self.emit("(");
        try genExprWrapped(self, binop.left.*);
        const op_str = switch (binop.op) {
            .BitAnd => " and ",
            .BitOr => " or ",
            .BitXor => " != ", // bool ^ bool = (a != b)
            else => unreachable,
        };
        try self.emit(op_str);
        try genExprWrapped(self, binop.right.*);
        try self.emit(")");
        return;
    }

    // If mixing usize and i64, cast to i64 for the operation
    const needs_cast = (left_is_usize and right_is_int) or (left_is_int and right_is_usize);

    // Handle mixed int/float multiplication - convert int to float
    // Note: unknown types (like self.field) that are multiplied with float constants
    // need runtime type dispatch
    const left_is_float = (left_type == .float);
    const right_is_float = (right_type == .float);
    const left_is_unknown = (left_type == .unknown);
    const right_is_unknown = (right_type == .unknown);
    if (binop.op == .Mult and ((left_is_int and right_is_float) or (left_is_float and right_is_int))) {
        try self.emit("(");
        if (left_is_int) {
            try self.emit("@as(f64, @floatFromInt(");
            try genExprWrapped(self, binop.left.*);
            try self.emit("))");
        } else {
            try genExprWrapped(self, binop.left.*);
        }
        try self.emit(" * ");
        if (right_is_int) {
            try self.emit("@as(f64, @floatFromInt(");
            try genExprWrapped(self, binop.right.*);
            try self.emit("))");
        } else {
            try genExprWrapped(self, binop.right.*);
        }
        try self.emit(")");
        return;
    }
    // Handle unknown type * float: use runtime conversion
    // Pattern: self.__num * 1.0 where __num could be int
    if (binop.op == .Mult and ((left_is_unknown and right_is_float) or (left_is_float and right_is_unknown))) {
        try self.emit("(runtime.toFloat(");
        try genExprWrapped(self, binop.left.*);
        try self.emit(") * runtime.toFloat(");
        try genExprWrapped(self, binop.right.*);
        try self.emit("))");
        return;
    }

    try self.emit("(");

    // Cast left operand if needed - bool or usize to i64
    if (left_is_bool) {
        try self.emit("@as(i64, @intFromBool(");
    } else if (left_is_usize and needs_cast) {
        try self.emit("@as(i64, @intCast(");
    }
    // Use genExprWrapped to add parens around comparisons, etc.
    try genExprWrapped(self, binop.left.*);
    if (left_is_bool) {
        try self.emit("))");
    } else if (left_is_usize and needs_cast) {
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

    // Cast right operand if needed - bool or usize to i64
    if (right_is_bool) {
        try self.emit("@as(i64, @intFromBool(");
    } else if (right_is_usize and needs_cast) {
        try self.emit("@as(i64, @intCast(");
    }
    // Use genExprWrapped to add parens around comparisons, etc.
    try genExprWrapped(self, binop.right.*);
    if (right_is_bool) {
        try self.emit("))");
    } else if (right_is_usize and needs_cast) {
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
            } else if (operand_type == .complex) {
                // Complex negation uses .neg() method
                try self.emit("(");
                try genExpr(self, unaryop.operand.*);
                try self.emit(").neg()");
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
            // For booleans, need to convert to int first (Python: ~False = -1, ~True = -2)
            const operand_type = try self.inferExprScoped(unaryop.operand.*);

            // Check if operand is a boolean constant or name (True/False)
            const is_bool = blk: {
                if (operand_type == .bool) break :blk true;
                // Check for True/False names which may not be typed as bool
                if (unaryop.operand.* == .name) {
                    const name = unaryop.operand.name.id;
                    if (std.mem.eql(u8, name, "True") or std.mem.eql(u8, name, "False")) {
                        break :blk true;
                    }
                }
                // Check for bool constants
                if (unaryop.operand.* == .constant) {
                    if (unaryop.operand.constant.value == .bool) {
                        break :blk true;
                    }
                }
                break :blk false;
            };

            if (is_bool) {
                // ~False = ~0 = -1, ~True = ~1 = -2
                try self.emit("~@as(i64, @intFromBool(");
                try genExpr(self, unaryop.operand.*);
                try self.emit("))");
            } else if (operand_type == .bigint) {
                // BigInt bitwise complement: ~n = -(n+1)
                // Implemented as: negate (n+1) -> -(n+1) = -n-1 = ~n
                const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
                try self.emit("blk: { var __bi_tmp = (");
                try genExpr(self, unaryop.operand.*);
                try self.emit(").add(&(runtime.BigInt.fromInt(");
                try self.emit(alloc_name);
                try self.emit(", 1) catch unreachable), ");
                try self.emit(alloc_name);
                try self.emit(") catch unreachable; __bi_tmp.negate(); break :blk __bi_tmp; }");
            } else {
                try self.emit("~@as(i64, ");
                try genExpr(self, unaryop.operand.*);
                try self.emit(")");
            }
        },
    }
}
