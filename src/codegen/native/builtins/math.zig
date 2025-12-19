/// Math builtins: abs(), min(), max(), round(), pow(), chr(), ord()
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const builder_mod = @import("codegen.builder");

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
        const b = try self.getBuilder();
        try b.write("(error.TypeError)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    // Two-Flow: Check if argument is uncertain
    if (isExprUncertain(self, args[0])) {
        // Route to PyValue.pyAbs() for runtime type safety
        try self.genExpr(args[0]);
        const b = try self.getBuilder();
        try b.write(".pyAbs()");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    // Check if arg is a bool - need to cast to int first since @abs doesn't work on bool
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;
    if (type_traits.isBoolean(arg_type)) {
        // abs(True) = 1, abs(False) = 0
        // Just convert bool to int: @intFromBool(...)
        {
            const b = try self.getBuilder();
            try b.write("@as(i64, @intFromBool(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write("))");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        return;
    }

    // Generate: @abs(n)
    {
        const b = try self.getBuilder();
        try b.write("@abs(");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]);
    {
        const b = try self.getBuilder();
        try b.write(")");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

/// Generate code for min(a, b, ...)
/// Returns minimum value
/// Two-Flow: routes uncertain operands to PyValue.pyMin()
pub fn genMin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.write("(error.TypeError)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    if (args.len == 1) {
        // Single argument - iterable case: min([1, 2, 3]) or min(some_sequence)
        // Use runtime function that handles any iterable
        {
            const b = try self.getBuilder();
            try b.write("runtime.builtins.minIterable(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(")");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
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
            {
                const b = try self.getBuilder();
                try b.write(".pyMin(");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
            try self.genExpr(arg);
            {
                const b = try self.getBuilder();
                try b.write(")");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
        }
        return;
    }

    // Generate: @min(a, @min(b, c))
    {
        const b = try self.getBuilder();
        try b.write("@min(");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]);

    for (args[1..]) |arg| {
        {
            const b = try self.getBuilder();
            try b.write(", ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(arg);
    }
    {
        const b = try self.getBuilder();
        try b.write(")");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

/// Generate code for max(a, b, ...)
/// Returns maximum value
/// Two-Flow: routes uncertain operands to PyValue.pyMax()
pub fn genMax(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.write("(error.TypeError)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    if (args.len == 1) {
        // Single argument - iterable case: max([1, 2, 3]) or max(some_sequence)
        // Use runtime function that handles any iterable
        {
            const b = try self.getBuilder();
            try b.write("runtime.builtins.maxIterable(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(")");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
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
            {
                const b = try self.getBuilder();
                try b.write(".pyMax(");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
            try self.genExpr(arg);
            {
                const b = try self.getBuilder();
                try b.write(")");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
        }
        return;
    }

    // Generate: @max(a, @max(b, c))
    {
        const b = try self.getBuilder();
        try b.write("@max(");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]);

    for (args[1..]) |arg| {
        {
            const b = try self.getBuilder();
            try b.write(", ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(arg);
    }
    {
        const b = try self.getBuilder();
        try b.write(")");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

/// Generate code for round(n) or round(n, ndigits)
/// Rounds to nearest integer or specified decimal places
pub fn genRound(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        const b = try self.getBuilder();
        try b.write("@as(f64, 0.0)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    // round(n) or round(n, None) - round to nearest integer
    if (args.len == 1 or (args.len == 2 and isNoneArg(args[1]))) {
        // Use runtime.builtins.pyRound to handle both int and float
        {
            const b = try self.getBuilder();
            try b.write("runtime.builtins.pyRound(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(")");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        return;
    }

    // round(n, ndigits) - round to ndigits decimal places
    // For ndigits=0, just use @round
    // Otherwise use: @round(n * 10^ndigits) / 10^ndigits
    // Use runtime round function to handle both int and float values
    {
        const b = try self.getBuilder();
        try b.write("(try runtime.builtins.round(");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]);
    {
        const b = try self.getBuilder();
        try b.write(", .{");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[1]);
    {
        const b = try self.getBuilder();
        try b.write("}))");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

/// Generate code for pow(base, exp) or pow(base, exp, mod)
/// Returns base^exp or base^exp % mod (modular exponentiation)
/// Uses runtime.builtins.pow which raises ZeroDivisionError for 0 ** negative
pub fn genPow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("(error.TypeError)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    if (args.len == 3) {
        // pow(base, exp, mod) - modular exponentiation
        // Generate: @rem(@as(i64, @intFromFloat(std.math.pow(f64, base, exp))), mod)
        {
            const b = try self.getBuilder();
            try b.write("@rem(@as(i64, @intFromFloat(std.math.pow(f64, @as(f64, @floatFromInt(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(")), @as(f64, @floatFromInt(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[1]);
        {
            const b = try self.getBuilder();
            try b.write("))))), ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[2]);
        {
            const b = try self.getBuilder();
            try b.write(")");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        // pow(base, exp) - standard power
        // Use runtime.builtins.pow which raises ZeroDivisionError for 0 ** negative
        // Generate: (try runtime.builtins.pow.call(base, exp))
        {
            const b = try self.getBuilder();
            try b.write("(try runtime.builtins.pow.call(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(", ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[1]);
        {
            const b = try self.getBuilder();
            try b.write("))");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    }
}

/// Generate code for chr(n)
/// Converts integer to character
pub fn genChr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        const b = try self.getBuilder();
        try b.write("(error.TypeError)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    // Generate: &[_]u8{@intCast(n)}
    {
        const b = try self.getBuilder();
        try b.write("&[_]u8{@intCast(");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]);
    {
        const b = try self.getBuilder();
        try b.write(")}");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

/// Generate code for ord(c)
/// Converts character to integer
pub fn genOrd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        const b = try self.getBuilder();
        try b.write("(error.TypeError)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    // Generate: @as(i64, str[0])
    // Assumes single-char string
    // Need extra parens when arg is a slice subscript (generates labeled block)
    const needs_parens = args[0] == .subscript and args[0].subscript.slice == .slice;
    {
        const b = try self.getBuilder();
        try b.write("@as(i64, ");
        if (needs_parens) try b.write("(");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    try self.genExpr(args[0]);
    {
        const b = try self.getBuilder();
        if (needs_parens) try b.write(")");
        try b.write("[0])");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

/// Generate code for divmod(a, b)
/// Returns tuple (a // b, a % b)
pub fn genDivmod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 2) {
        const b = try self.getBuilder();
        try b.write("(error.TypeError)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    // Check if either argument is BigInt or unknown (could be anytype)
    const left_type = self.inferExprScoped(args[0]) catch .unknown;
    const right_type = self.inferExprScoped(args[1]) catch .unknown;
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    if (left_type == .bigint or right_type == .bigint or left_type == .unknown or right_type == .unknown) {
        // BigInt or unknown type - use runtime.bigIntDivmod
        {
            const b = try self.getBuilder();
            try b.write("runtime.bigIntDivmod(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(", ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[1]);
        {
            const b = try self.getBuilder();
            try b.write(", ");
            try b.write(alloc_name);
            try b.write(")");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        // Generate: .{ @divFloor(a, b), @mod(a, b) }
        {
            const b = try self.getBuilder();
            try b.write(".{ @divFloor(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(", ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[1]);
        {
            const b = try self.getBuilder();
            try b.write("), @mod(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(", ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[1]);
        {
            const b = try self.getBuilder();
            try b.write(") }");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    }
}

/// Generate code for hash(obj)
/// Returns integer hash of object
/// Two-Flow: always uses runtime.pyHash() which handles all types (including PyValue, tuples, etc.)
pub fn genHash(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        const b = try self.getBuilder();
        try b.write("(error.TypeError)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    // Check the type of the argument to generate appropriate code
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    switch (arg_type) {
        .bool => {
            // For bools: 1 for True, 0 for False (fast path)
            {
                const b = try self.getBuilder();
                try b.write("@as(i64, if (");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
            try self.genExpr(args[0]);
            {
                const b = try self.getBuilder();
                try b.write(") 1 else 0)");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
        },
        .string => {
            // For strings: use std.hash.Wyhash (fast path)
            {
                const b = try self.getBuilder();
                try b.write("@as(i64, @bitCast(std.hash.Wyhash.hash(0, ");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
            try self.genExpr(args[0]);
            {
                const b = try self.getBuilder();
                try b.write(")))");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
        },
        else => {
            // For all other types (int, float, tuple, PyValue, unknown, etc.):
            // use runtime.pyHash which handles all types including tuples and PyValue
            {
                const b = try self.getBuilder();
                try b.write("runtime.pyHash(");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
            try self.genExpr(args[0]);
            {
                const b = try self.getBuilder();
                try b.write(")");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
        },
    }
}
