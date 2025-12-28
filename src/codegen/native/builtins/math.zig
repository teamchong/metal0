/// Math builtins: abs(), min(), max(), round(), pow(), chr(), ord()
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const builder_mod = @import("codegen.builder");

// MIGRATED TO ZIGBUILDER

// ============================================
// Math helpers - auto-closing patterns
// ============================================

/// Emit method call suffix: .methodName(
fn emitMethodStart(self: *NativeCodegen, method: []const u8) CodegenError!void {
    try self.emit(".");
    try self.emit(method);
    try self.emit("(");
}

/// Emit @builtin call start: @builtinName(
fn emitBuiltinStart(self: *NativeCodegen, builtin: []const u8) CodegenError!void {
    try self.emit("@");
    try self.emit(builtin);
    try self.emit("(");
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

/// Check if an expression is uncertain (needs PyValue)
/// Two-Flow: routes uncertain types to PyValue methods
/// CONSERVATIVE: Only returns true for explicitly PyValue or unknown typed variables
/// Does NOT use confidence fallback to avoid false positives on unset confidence
fn isExprUncertain(self: *NativeCodegen, expr: ast.Node) bool {
    if (expr == .name) {
        const name = expr.name.id;
        // Check scoped vars first (for loop variables, function params)
        // then fall back to global var_types
        const var_type = self.type_inferrer.getScopedVar(name) orelse
            self.type_inferrer.var_types.get(name);
        if (var_type) |vt| {
            return vt == .pyvalue or vt == .unknown;
        }
        // Variable not in type map - it's likely a local with inferred type
        // Don't assume uncertain - let Zig compiler catch type mismatches
        return false;
    }
    return false;
}

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
    if (isExprUncertain(self, args[0])) {
        // Route to PyValue.pyAbs() for runtime type safety
        try self.genExpr(args[0]);
        try self.emit(".pyAbs()");
        return;
    }

    // Check if arg is a bool - need to cast to int first since @abs doesn't work on bool
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    if (type_traits.isBoolean(arg_type)) {
        // abs(True) = 1, abs(False) = 0
        // Just convert bool to int: @intFromBool(...)
        try self.emit("@as(i64, @intFromBool(");
        try self.genExpr(args[0]);
        try self.emit("))");
        return;
    }

    // Generate: @abs(n)
    try emitBuiltinStart(self, "abs");
    try self.genExpr(args[0]);
    try self.emit(")");
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
        try self.emit("runtime.builtins.minIterable(");
        try self.genExpr(args[0]);
        try self.emit(")");
        return;
    }

    // Two-Flow: Check if any argument is uncertain
    var any_uncertain = false;
    for (args) |arg| {
        if (isExprUncertain(self, arg)) {
            any_uncertain = true;
            break;
        }
    }

    if (any_uncertain) {
        // Route to PyValue.pyMin() chained for runtime type safety
        // min(a, b, c) => a.pyMin(b).pyMin(c)
        try self.genExpr(args[0]);
        for (args[1..]) |arg| {
            try emitMethodStart(self, "pyMin");
            try self.genExpr(arg);
            try self.emit(")");
        }
        return;
    }

    // Generate: @min(a, @min(b, c))
    try emitBuiltinStart(self, "min");
    try self.genExpr(args[0]);

    for (args[1..]) |arg| {
        try self.emit(", ");
        try self.genExpr(arg);
    }
    try self.emit(")");
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
        try self.emit("runtime.builtins.maxIterable(");
        try self.genExpr(args[0]);
        try self.emit(")");
        return;
    }

    // Two-Flow: Check if any argument is uncertain
    var any_uncertain = false;
    for (args) |arg| {
        if (isExprUncertain(self, arg)) {
            any_uncertain = true;
            break;
        }
    }

    if (any_uncertain) {
        // Route to PyValue.pyMax() chained for runtime type safety
        // max(a, b, c) => a.pyMax(b).pyMax(c)
        try self.genExpr(args[0]);
        for (args[1..]) |arg| {
            try emitMethodStart(self, "pyMax");
            try self.genExpr(arg);
            try self.emit(")");
        }
        return;
    }

    // Generate: @max(a, @max(b, c))
    try emitBuiltinStart(self, "max");
    try self.genExpr(args[0]);

    for (args[1..]) |arg| {
        try self.emit(", ");
        try self.genExpr(arg);
    }
    try self.emit(")");
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
        try self.emit("runtime.builtins.pyRound(");
        try self.genExpr(args[0]);
        try self.emit(")");
        return;
    }

    // round(n, ndigits) - round to ndigits decimal places
    // Use runtime round function to handle both int and float values
    try self.emit("(try runtime.builtins.round(");
    try self.genExpr(args[0]);
    try self.emit(", .{");
    try self.genExpr(args[1]);
    try self.emit("}))");
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
        // pow(base, exp, mod) - modular exponentiation
        // Result is always integer, no complex support needed
        // Generate: @rem(@as(i64, @intFromFloat(std.math.pow(f64, base, exp))), mod)
        try self.emit("@rem(@as(i64, @intFromFloat(std.math.pow(f64, @as(f64, @floatFromInt(");
        try self.genExpr(args[0]);
        try self.emit(")), @as(f64, @floatFromInt(");
        try self.genExpr(args[1]);
        try self.emit("))))), ");
        try self.genExpr(args[2]);
        try self.emit(")");
    } else {
        // pow(base, exp) - standard power
        // Get types to determine which codepath to use
        const base_type = self.inferExprScoped(args[0]) catch .unknown;
        const exp_type = self.inferExprScoped(args[1]) catch .unknown;
        const base_is_int = type_traits.isIntegral(base_type) or type_traits.isBoolean(base_type);
        const exp_is_int = type_traits.isIntegral(exp_type) or type_traits.isBoolean(exp_type);

        // Check if we need pyPowAsPyValue (returns PyValue) or can use std.math.pow (returns f64)
        // pyPowAsPyValue is needed for:
        // 1. Negative exponents (ZeroDivisionError for base=0)
        // 2. Negative base with non-integer exponent (complex result)
        // 3. Non-constant exponent (type inference returns pow_result for safety)
        // 4. When result type inference says .pyvalue or .pow_result
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
                    // Negative base with float exp - only safe if exp is integer value
                    if (args[1] == .constant and args[1].constant.value == .float) {
                        const exp = args[1].constant.value.float;
                        if (exp != @trunc(exp)) break :blk true;
                    }
                }
            }
            // If exponent is a variable (not constant), use pyPowAsPyValue for consistency
            // with type inference which returns pow_result for non-constant exponents
            // This handles cases like pow(1.0, NAN) where NAN is a float variable
            if (args[1] != .constant and !exp_is_int) {
                // Exponent is a variable with float type - need PyValue for type consistency
                break :blk true;
            }
            break :blk false;
        };

        if (needs_pyvalue) {
            // Use pyPowAsPyValue which returns PyValue directly
            // This handles complex results, ZeroDivisionError, and IEEE 754 edge cases
            try self.emit("(try runtime.builtins.pyPowAsPyValue(");
        } else {
            // Simple float pow - use std.math.pow directly for f64 return type
            try self.emit("std.math.pow(f64, ");
        }

        // Convert base to f64
        // Check if base is a type conversion call (type(x) where type is an anytype param)
        const base_is_type_call = isTypeConversionCall(args[0]);
        if (base_is_type_call) {
            // Use typeConvertFloat which handles both int and float target types
            try self.emit("runtime.builtins.typeConvertFloat(");
            try self.genExpr(args[0].call.func.*);
            try self.emit(", ");
            try self.genExpr(args[0].call.args[0]);
            try self.emit(")");
        } else if (base_is_int) {
            try self.emit("@as(f64, @floatFromInt(");
            try self.genExpr(args[0]);
            try self.emit("))");
        } else {
            // Unknown type - use numericToFloat which handles both int and float
            try self.emit("runtime.builtins.numericToFloat(");
            try self.genExpr(args[0]);
            try self.emit(")");
        }

        try self.emit(", ");

        // Convert exp to f64
        // Check if exp is a type conversion call
        const exp_is_type_call = isTypeConversionCall(args[1]);
        if (exp_is_type_call) {
            // Use typeConvertFloat which handles both int and float target types
            try self.emit("runtime.builtins.typeConvertFloat(");
            try self.genExpr(args[1].call.func.*);
            try self.emit(", ");
            try self.genExpr(args[1].call.args[0]);
            try self.emit(")");
        } else if (exp_is_int) {
            try self.emit("@as(f64, @floatFromInt(");
            try self.genExpr(args[1]);
            try self.emit("))");
        } else {
            // Unknown type - use numericToFloat which handles both int and float
            try self.emit("runtime.builtins.numericToFloat(");
            try self.genExpr(args[1]);
            try self.emit(")");
        }

        if (needs_pyvalue) {
            try self.emit("))");
        } else {
            try self.emit(")");
        }
    }
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
    try self.emit("(try runtime.builtins.chr(__global_allocator, ");
    try self.genExpr(args[0]);
    try self.emit("))");
}

/// Generate code for ord(c)
/// Converts character to integer
pub fn genOrd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("(error.TypeError)");
        return;
    }

    // Generate: @as(i64, str[0])
    // Assumes single-char string
    // Need extra parens when arg is a slice subscript (generates labeled block)
    // Uses emitParens for auto-close when needed
    const needs_parens = args[0] == .subscript and args[0].subscript.slice == .slice;
    try self.emit("@as(i64, ");
    if (needs_parens) {
        try self.emitParens(args[0]);
    } else {
        try self.genExpr(args[0]);
    }
    try self.emit("[0])");
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
    const alloc_name = "__global_allocator";

    if (left_type == .bigint or right_type == .bigint or left_type == .unknown or right_type == .unknown) {
        // BigInt or unknown type - use runtime.bigIntDivmod
        try self.emit("runtime.bigIntDivmod(");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(", ");
        try self.emit(alloc_name);
        try self.emit(")");
    } else {
        // Generate: .{ @divFloor(a, b), @mod(a, b) }
        try self.emit(".{ @divFloor(");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit("), @mod(");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(") }");
    }
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

    switch (arg_type) {
        .bool => {
            // For bools: 1 for True, 0 for False (fast path)
            try self.emit("@as(i64, if (");
            try self.genExpr(args[0]);
            try self.emit(") 1 else 0)");
        },
        .string => {
            // For strings: use std.hash.Wyhash (fast path)
            try self.emit("@as(i64, @bitCast(std.hash.Wyhash.hash(0, ");
            try self.genExpr(args[0]);
            try self.emit(")))");
        },
        else => {
            // For all other types (int, float, tuple, PyValue, unknown, etc.):
            // use runtime.pyHash which handles all types including tuples and PyValue
            try self.emit("runtime.pyHash(");
            try self.genExpr(args[0]);
            try self.emit(")");
        },
    }
}
