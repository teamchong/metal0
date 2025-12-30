/// Math builtins: abs(), min(), max(), round(), pow(), chr(), ord()
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;
const CallArg = builder_mod.ZigBuilder.CallArg;

// MIGRATED TO ZIGBUILDER

// ============================================
// Math helpers - callback patterns for auto-closing
// ============================================

/// Emit @builtin(args) with auto-closing using builder callback
fn emitBuiltinCall(self: *NativeCodegen, builtin: []const u8, args: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    const builtin_name = try std.fmt.allocPrint(self.arena.allocator(), "@{s}", .{builtin});
    try b.withCall(builtin_name, struct {
        fn f(builder: *builder_mod.ZigBuilder, ctx: anytype) !void {
            for (ctx.args, 0..) |arg, i| {
                if (i > 0) try builder.write(", ");
                const val = try ctx.self.captureExpr(arg);
                try builder.emitValueCore(val);
            }
        }
    }.f, .{ .self = self, .args = args });
    try self.flushBuilder();
}

/// Emit expr.method(args) with auto-closing using builder callback
fn emitMethodCall(self: *NativeCodegen, expr: ast.Node, method: []const u8, args: []ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    const expr_val = try self.captureExpr(expr);
    try b.emitValueCore(expr_val);
    try b.write(".");
    try b.withCall(method, struct {
        fn f(builder: *builder_mod.ZigBuilder, ctx: anytype) !void {
            for (ctx.args, 0..) |arg, i| {
                if (i > 0) try builder.write(", ");
                const val = try ctx.self.captureExpr(arg);
                try builder.emitValueCore(val);
            }
        }
    }.f, .{ .self = self, .args = args });
    try self.flushBuilder();
}

/// Check if an expression is a type conversion call pattern: type(x), cls(x), etc.
/// These are calls where the function name is a parameter that could hold a Zig type (i64, f64)
fn isTypeConversionCall(node: ast.Node) bool {
    if (node != .call) return false;
    const call = node.call;
    if (call.func.* != .name) return false;
    if (call.args.len != 1) return false;
    const func_name = call.func.name.id;
    // Type-like parameter names that could hold Zig types (i64, f64)
    return std.mem.eql(u8, func_name, "type") or
        std.mem.eql(u8, func_name, "cls") or
        std.mem.eql(u8, func_name, "klass") or
        std.mem.eql(u8, func_name, "class_") or
        std.mem.eql(u8, func_name, "typ");
}

/// Check if argument is None constant
fn isNoneArg(arg: ast.Node) bool {
    if (arg == .constant) {
        if (arg.constant.value == .none) return true;
    }
    if (arg == .name) {
        if (std.mem.eql(u8, arg.name.id, "None")) return true;
    }
    return false;
}

// isExprUncertain replaced by self.isExprUncertain() (DRY consolidation)

/// Generate code for abs(n)
/// Returns absolute value
/// Two-Flow: routes uncertain operands to PyValue.pyAbs()
pub fn genAbs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // abs() requires exactly one argument - generate an error union for assertRaises
        try self.emit("(error.TypeError)");
        return;
    }

    // Two-Flow: Check if argument is uncertain
    if (self.isExprUncertain( args[0])) {
        // Route to PyValue.pyAbs() for runtime type safety
        try emitMethodCall(self, args[0], "pyAbs", &.{});
        return;
    }

    // Check if arg is a bool - need to cast to int first since @abs doesn't work on bool
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    if (type_traits.isBoolean(arg_type)) {
        // abs(True) = 1, abs(False) = 0 - use builder callback for safe brackets
        const b = try self.getBuilder();
        try b.withCall("@as", struct {
            fn f(builder: *builder_mod.ZigBuilder, ctx: anytype) !void {
                try builder.write("i64, @intFromBool(");
                const val = try ctx.self.captureExpr(ctx.arg);
                try builder.emitValueCore(val);
                try builder.write(")");
            }
        }.f, .{ .self = self, .arg = args[0] });
        try self.flushBuilder();
        return;
    }

    // Generate: @abs(n) using callback pattern
    try emitBuiltinCall(self, "abs", args);
}

/// Generate code for min(a, b, ...)
/// Returns minimum value
/// Two-Flow: routes uncertain operands to PyValue.pyMin()
pub fn genMin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("(error.TypeError)");
        return;
    }

    if (args.len == 1) {
        // Single argument - iterable case: min([1, 2, 3]) or min(some_sequence)
        // Use runtime function that handles any iterable
        try emitRuntimeMinIterable(self, args[0]);
        return;
    }

    // Two-Flow: Check if any argument is uncertain
    var any_uncertain = false;
    for (args) |arg| {
        if (self.isExprUncertain( arg)) {
            any_uncertain = true;
            break;
        }
    }

    if (any_uncertain) {
        // Route to PyValue.pyMin() chained for runtime type safety
        // min(a, b, c) => a.pyMin(b).pyMin(c)
        const b = try self.getBuilder();
        const first_val = try self.captureExpr(args[0]);
        try b.emitValueCore(first_val);
        for (args[1..]) |arg| {
            const arg_val = try self.captureExpr(arg);
            try b.write(".pyMin(");
            try b.emitValueCore(arg_val);
            try b.write(")");
        }
        try self.flushBuilder();
        return;
    }

    // Generate: @min(a, b, c, ...) using builder callback
    const b = try self.getBuilder();
    try b.withCall("@min", struct {
        fn f(builder: *builder_mod.ZigBuilder, ctx: anytype) !void {
            for (ctx.args, 0..) |arg, i| {
                if (i > 0) try builder.write(", ");
                const val = try ctx.self.captureExpr(arg);
                try builder.emitValueCore(val);
            }
        }
    }.f, .{ .self = self, .args = args });
    try self.flushBuilder();
}

/// Generate code for max(a, b, ...)
/// Returns maximum value
/// Two-Flow: routes uncertain operands to PyValue.pyMax()
pub fn genMax(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("(error.TypeError)");
        return;
    }

    if (args.len == 1) {
        // Single argument - iterable case: max([1, 2, 3]) or max(some_sequence)
        // Use runtime function that handles any iterable
        try emitRuntimeMaxIterable(self, args[0]);
        return;
    }

    // Two-Flow: Check if any argument is uncertain
    var any_uncertain = false;
    for (args) |arg| {
        if (self.isExprUncertain( arg)) {
            any_uncertain = true;
            break;
        }
    }

    if (any_uncertain) {
        // Route to PyValue.pyMax() chained for runtime type safety
        // max(a, b, c) => a.pyMax(b).pyMax(c)
        const b = try self.getBuilder();
        const first_val = try self.captureExpr(args[0]);
        try b.emitValueCore(first_val);
        for (args[1..]) |arg| {
            const arg_val = try self.captureExpr(arg);
            try b.write(".pyMax(");
            try b.emitValueCore(arg_val);
            try b.write(")");
        }
        try self.flushBuilder();
        return;
    }

    // Generate: @max(a, b, c, ...) using builder callback
    const b = try self.getBuilder();
    try b.withCall("@max", struct {
        fn f(builder: *builder_mod.ZigBuilder, ctx: anytype) !void {
            for (ctx.args, 0..) |arg, i| {
                if (i > 0) try builder.write(", ");
                const val = try ctx.self.captureExpr(arg);
                try builder.emitValueCore(val);
            }
        }
    }.f, .{ .self = self, .args = args });
    try self.flushBuilder();
}

/// Generate code for round(n) or round(n, ndigits)
/// Rounds to nearest integer or specified decimal places
pub fn genRound(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@as(f64, 0.0)");
        return;
    }

    // round(n) or round(n, None) - round to nearest integer
    if (args.len == 1 or (args.len == 2 and isNoneArg(args[1]))) {
        // Use runtime.builtins.pyRound to handle both int and float
        try emitRuntimePyRound(self, args[0]);
        return;
    }

    // round(n, ndigits) - round to ndigits decimal places using builder pattern
    const b = try self.getBuilder();
    const num_val = try self.captureExpr(args[0]);
    const ndigits_val = try self.captureExpr(args[1]);

    // Generate: (try runtime.builtins.round(num, .{ndigits}))
    try b.withParen(struct {
        fn f(builder: *builder_mod.ZigBuilder, ctx: anytype) !void {
            try builder.write("try runtime.builtins.round(");
            try builder.emitValueCore(ctx.num_val);
            try builder.write(", .{");
            try builder.emitValueCore(ctx.ndigits_val);
            try builder.write("})");
        }
    }.f, .{ .num_val = num_val, .ndigits_val = ndigits_val });
    try self.flushBuilder();
}

/// Emit value converted to f64 (for pow args) using builder pattern
fn emitAsF64(self: *NativeCodegen, arg: ast.Node, is_int: bool) CodegenError!void {
    const b = try self.getBuilder();
    const is_type_call = isTypeConversionCall(arg);

    if (is_type_call) {
        // Use typeConvertFloat which handles both int and float target types
        const func_val = try self.captureExpr(arg.call.func.*);
        const arg_val = try self.captureExpr(arg.call.args[0]);
        try b.withCall("runtime.builtins.typeConvertFloat", struct {
            fn f(builder: *builder_mod.ZigBuilder, ctx: anytype) !void {
                try builder.emitValueCore(ctx.func_val);
                try builder.write(", ");
                try builder.emitValueCore(ctx.arg_val);
            }
        }.f, .{ .func_val = func_val, .arg_val = arg_val });
    } else if (is_int) {
        // @as(f64, @floatFromInt(value))
        const val = try self.captureExpr(arg);
        try b.withCall("@as", struct {
            fn f(builder: *builder_mod.ZigBuilder, ctx: anytype) !void {
                try builder.write("f64, @floatFromInt(");
                try builder.emitValueCore(ctx.val);
                try builder.write(")");
            }
        }.f, .{ .val = val });
    } else {
        // runtime.builtins.numericToFloat(value)
        const val = try self.captureExpr(arg);
        try b.emitCallExpr("runtime.builtins.numericToFloat", &[_]CallArg{.{ .value = val }});
    }
}

/// Generate code for pow(base, exp) or pow(base, exp, mod)
/// Returns base^exp or base^exp % mod (modular exponentiation)
/// Python semantics: pow(-2, 0.5) returns complex number
/// Uses pyPow/pyPowAsPyValue for complex/error cases, std.math.pow for simple float cases
pub fn genPow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("(error.TypeError)");
        return;
    }

    if (args.len == 3) {
        // pow(base, exp, mod) - modular exponentiation using builder pattern
        // Result is always integer, no complex support needed
        // Generate: @rem(@as(i64, @intFromFloat(std.math.pow(f64, base, exp))), mod)
        const b = try self.getBuilder();
        const base_val = try self.captureExpr(args[0]);
        const exp_val = try self.captureExpr(args[1]);
        const mod_val = try self.captureExpr(args[2]);

        try b.withCall("@rem", struct {
            fn f(builder: *builder_mod.ZigBuilder, ctx: anytype) !void {
                try builder.write("@as(i64, @intFromFloat(std.math.pow(f64, @as(f64, @floatFromInt(");
                try builder.emitValueCore(ctx.base_val);
                try builder.write(")), @as(f64, @floatFromInt(");
                try builder.emitValueCore(ctx.exp_val);
                try builder.write("))))), ");
                try builder.emitValueCore(ctx.mod_val);
            }
        }.f, .{ .base_val = base_val, .exp_val = exp_val, .mod_val = mod_val });
        try self.flushBuilder();
        return;
    }

    // pow(base, exp) - standard power
    // Get types to determine which codepath to use
    const base_type = self.inferExprScoped(args[0]) catch .unknown;
    const exp_type = self.inferExprScoped(args[1]) catch .unknown;
    const base_is_int = type_traits.isIntegral(base_type) or type_traits.isBoolean(base_type);
    const exp_is_int = type_traits.isIntegral(exp_type) or type_traits.isBoolean(exp_type);

    // Check if we need pyPowAsPyValue (returns PyValue) or can use std.math.pow (returns f64)
    const needs_pyvalue = blk: {
        // Check for explicitly negative exponent
        if (args[1] == .unaryop and args[1].unaryop.op == .USub) {
            break :blk true;
        }
        if (args[1] == .constant and args[1].constant.value == .int) {
            if (args[1].constant.value.int < 0) break :blk true;
        }
        if (args[1] == .constant and args[1].constant.value == .float) {
            if (args[1].constant.value.float < 0) break :blk true;
        }
        // Check if base is negative with non-integer exponent (could produce complex)
        if (!exp_is_int) {
            if (args[0] == .unaryop and args[0].unaryop.op == .USub) {
                if (args[1] == .constant and args[1].constant.value == .float) {
                    const exp = args[1].constant.value.float;
                    if (exp != @trunc(exp)) break :blk true;
                }
            }
        }
        // If exponent is a variable (not constant), use pyPowAsPyValue for consistency
        if (args[1] != .constant and !exp_is_int) {
            break :blk true;
        }
        break :blk false;
    };

    const b = try self.getBuilder();

    if (needs_pyvalue) {
        // (try runtime.builtins.pyPowAsPyValue(base_as_f64, exp_as_f64))
        try b.write("(try runtime.builtins.pyPowAsPyValue(");
        try emitAsF64(self, args[0], base_is_int);
        try b.write(", ");
        try emitAsF64(self, args[1], exp_is_int);
        try b.write("))");
    } else {
        // std.math.pow(f64, base_as_f64, exp_as_f64)
        try b.write("std.math.pow(f64, ");
        try emitAsF64(self, args[0], base_is_int);
        try b.write(", ");
        try emitAsF64(self, args[1], exp_is_int);
        try b.write(")");
    }
    try self.flushBuilder();
}

/// Generate code for chr(n)
/// Converts integer to character
pub fn genChr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("(error.TypeError)");
        return;
    }

    // Check if argument is a small integer literal (ASCII range)
    if (args[0] == .constant and args[0].constant.value == .int) {
        const val = args[0].constant.value.int;
        if (val >= 0 and val <= 127) {
            // Fast path for ASCII: inline single-byte array
            try self.emitFmt("&[_]u8{{{d}}}", .{@as(u8, @intCast(val))});
            return;
        }
    }

    // Full Unicode support via runtime (handles UTF-8 encoding)
    try emitRuntimeChr(self, args[0]);
}

/// Generate code for ord(c)
/// Converts character to integer
pub fn genOrd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("(error.TypeError)");
        return;
    }

    // Generate: @as(i64, str[0]) using builder pattern
    const b = try self.getBuilder();
    const needs_parens = args[0] == .subscript and args[0].subscript.slice == .slice;
    const val = try self.captureExpr(args[0]);

    try b.withCall("@as", struct {
        fn f(builder: *builder_mod.ZigBuilder, ctx: anytype) !void {
            try builder.write("i64, ");
            if (ctx.needs_parens) {
                try builder.write("(");
                try builder.emitValueCore(ctx.val);
                try builder.write(")");
            } else {
                try builder.emitValueCore(ctx.val);
            }
            try builder.write("[0]");
        }
    }.f, .{ .val = val, .needs_parens = needs_parens });
    try self.flushBuilder();
}

/// Generate code for divmod(a, b)
/// Returns tuple (a // b, a % b)
pub fn genDivmod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 2) {
        try self.emit("(error.TypeError)");
        return;
    }

    // Check if either argument is BigInt or unknown (could be anytype)
    const left_type = self.inferExprScoped(args[0]) catch .unknown;
    const right_type = self.inferExprScoped(args[1]) catch .unknown;

    const b = try self.getBuilder();
    const left_val = try self.captureExpr(args[0]);
    const right_val = try self.captureExpr(args[1]);

    // Check for UnifiedInt or BigInt - use unified_int_ops.divmod for both
    // This avoids type mismatches when variables are declared as UnifiedInt but inferred as bigint
    const needs_unified_divmod = left_type == .bigint or right_type == .bigint or
        left_type == .unified_int or right_type == .unified_int or
        left_type == .unknown or right_type == .unknown;

    if (needs_unified_divmod) {
        // BigInt/UnifiedInt/unknown type - use runtime.unified_int_ops.divmod
        // which accepts UnifiedInt and handles conversions
        try b.emitCallExpr("runtime.unified_int_ops.divmod", &[_]CallArg{
            .{ .value = left_val },
            .{ .value = right_val },
            .allocator,
        });
    } else {
        // Generate: .{ @divFloor(a, b), @mod(a, b) }
        try b.withAnonLiteral(struct {
            fn f(builder: *builder_mod.ZigBuilder, ctx: anytype) !void {
                try builder.write("@divFloor(");
                try builder.emitValueCore(ctx.left_val);
                try builder.write(", ");
                try builder.emitValueCore(ctx.right_val);
                try builder.write("), @mod(");
                try builder.emitValueCore(ctx.left_val);
                try builder.write(", ");
                try builder.emitValueCore(ctx.right_val);
                try builder.write(")");
            }
        }.f, .{ .left_val = left_val, .right_val = right_val });
    }
    try self.flushBuilder();
}

/// Generate code for hash(obj)
/// Returns integer hash of object
/// Two-Flow: always uses runtime.pyHash() which handles all types (including PyValue, tuples, etc.)
pub fn genHash(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("(error.TypeError)");
        return;
    }

    // Check the type of the argument to generate appropriate code
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    const b = try self.getBuilder();
    const val = try self.captureExpr(args[0]);

    switch (arg_type) {
        .bool => {
            // For bools: 1 for True, 0 for False (fast path)
            try b.withCall("@as", struct {
                fn f(builder: *builder_mod.ZigBuilder, ctx: anytype) !void {
                    try builder.write("i64, if (");
                    try builder.emitValueCore(ctx.val);
                    try builder.write(") 1 else 0");
                }
            }.f, .{ .val = val });
            try self.flushBuilder();
        },
        .string => {
            // For strings: use std.hash.Wyhash (fast path)
            try b.withCall("@as", struct {
                fn f(builder: *builder_mod.ZigBuilder, ctx: anytype) !void {
                    try builder.write("i64, @bitCast(std.hash.Wyhash.hash(0, ");
                    try builder.emitValueCore(ctx.val);
                    try builder.write("))");
                }
            }.f, .{ .val = val });
            try self.flushBuilder();
        },
        else => {
            // For all other types (int, float, tuple, PyValue, unknown, etc.):
            // use runtime.pyHash which handles all types including tuples and PyValue
            try emitRuntimePyHash(self, args[0]);
        },
    }
}

// ============================================
// Builder-based helper functions (auto-close)
// ============================================

/// Emit runtime.builtins.minIterable(arg) using builder pattern
fn emitRuntimeMinIterable(self: *NativeCodegen, arg: ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    const arg_val = try self.captureExpr(arg);
    try b.emitCallExpr("runtime.builtins.minIterable", &[_]CallArg{
        .{ .value = arg_val },
    });
    const result = try b.getBodyDupe();
    try self.emitZigValue(ZigValue.raw(result));
}

/// Emit runtime.builtins.maxIterable(arg) using builder pattern
fn emitRuntimeMaxIterable(self: *NativeCodegen, arg: ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    const arg_val = try self.captureExpr(arg);
    try b.emitCallExpr("runtime.builtins.maxIterable", &[_]CallArg{
        .{ .value = arg_val },
    });
    const result = try b.getBodyDupe();
    try self.emitZigValue(ZigValue.raw(result));
}

/// Emit runtime.builtins.pyRound(arg) using builder pattern
fn emitRuntimePyRound(self: *NativeCodegen, arg: ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    const arg_val = try self.captureExpr(arg);
    try b.emitCallExpr("runtime.builtins.pyRound", &[_]CallArg{
        .{ .value = arg_val },
    });
    const result = try b.getBodyDupe();
    try self.emitZigValue(ZigValue.raw(result));
}

/// Emit (try runtime.builtins.chr(__global_allocator, arg)) using builder pattern
fn emitRuntimeChr(self: *NativeCodegen, arg: ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    const arg_val = try self.captureExpr(arg);
    try b.emitTryCallExpr("runtime.builtins.chr", &[_]CallArg{
        .allocator,
        .{ .value = arg_val },
    });
    const result = try b.getBodyDupe();
    try self.emitZigValue(ZigValue.raw(result));
}

/// Emit runtime.pyHash(arg) using builder pattern
fn emitRuntimePyHash(self: *NativeCodegen, arg: ast.Node) CodegenError!void {
    const b = try self.getBuilder();
    const arg_val = try self.captureExpr(arg);
    try b.emitCallExpr("runtime.pyHash", &[_]CallArg{
        .{ .value = arg_val },
    });
    const result = try b.getBodyDupe();
    try self.emitZigValue(ZigValue.raw(result));
}
