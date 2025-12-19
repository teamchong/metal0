/// Collection operations: string concatenation, list concatenation, repetition
/// Handles string, bytes, list, tuple, and array operations
///
/// MIGRATION STATUS: Using ZigBuilder for structured code generation
/// - Uses captureExpr() to bridge AST expressions to ZigValue
/// - Emits using emitZigValue() for type-safe output
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;
const producesBlockExpression = expressions.producesBlockExpression;
const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
const string_traits = @import("../../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../../analysis/traits/container_traits.zig");
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;

// MIGRATED TO ZIGBUILDER

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// ============================================
// Collection operation helpers - auto-closing patterns
// ============================================

/// Emit runtime function call with allocator: runtime.func(alloc, arg1, arg2)
fn emitRuntimeCall2(self: *NativeCodegen, func: []const u8, arg1: builder_mod.ZigValue, arg2: builder_mod.ZigValue) CodegenError!void {
    try emitConst(self, func);
    try emitConst(self, "(__global_allocator, ");
    try self.emitZigValue(arg1);
    try emitConst(self, ", ");
    try self.emitZigValue(arg2);
    try emitConst(self, ")");
}

/// Emit runtime function call: runtime.func(arg1, arg2)
fn emitCall2(self: *NativeCodegen, func: []const u8, arg1: builder_mod.ZigValue, arg2: builder_mod.ZigValue) CodegenError!void {
    try emitConst(self, func);
    try emitConst(self, "(");
    try self.emitZigValue(arg1);
    try emitConst(self, ", ");
    try self.emitZigValue(arg2);
    try emitConst(self, ")");
}

/// Emit count as usize cast: @as(usize, @intCast(count))
fn emitCountAsUsize(self: *NativeCodegen, count: builder_mod.ZigValue) CodegenError!void {
    try emitConst(self, "@as(usize, @intCast(");
    try self.emitZigValue(count);
    try emitConst(self, "))");
}

/// Check if a list will be generated as a fixed array (constant + homogeneous)
pub fn willGenerateAsFixedArray(list_node: ast.Node) bool {
    if (list_node != .list) return false;
    const list = list_node.list;
    if (list.elts.len == 0) return false;
    // Check all elements are constants
    for (list.elts) |elem| {
        if (elem != .constant) return false;
    }
    // Check all elements are same type
    return allConstantsSameType(list.elts);
}

fn allConstantsSameType(elements: []ast.Node) bool {
    if (elements.len == 0) return true;
    const first_const = elements[0].constant;
    const first_type_tag: std.meta.Tag(@TypeOf(first_const.value)) = first_const.value;
    for (elements[1..]) |elem| {
        const elem_const = elem.constant;
        const elem_type_tag: std.meta.Tag(@TypeOf(elem_const.value)) = elem_const.value;
        if (elem_type_tag != first_type_tag) return false;
    }
    return true;
}

/// Generate expression, wrapping in parentheses if it's a block expression
pub fn genExprWrapped(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    if (producesBlockExpression(expr)) {
        try emitConst(self, "(");
        try genExpr(self, expr);
        try emitConst(self, ")");
    } else {
        try genExpr(self, expr);
    }
}

/// Recursively collect all parts of a string concatenation chain
pub fn collectConcatParts(self: *NativeCodegen, node: ast.Node, parts: *std.ArrayList(ast.Node)) CodegenError!void {
    if (node == .binop and node.binop.op == .Add) {
        const left_type = try self.inferExprScoped(node.binop.left.*);
        const right_type = try self.inferExprScoped(node.binop.right.*);

        // Only flatten if this is string concatenation
        if (string_traits.isStringLike(left_type) or string_traits.isStringLike(right_type)) {
            try collectConcatParts(self, node.binop.left.*, parts);
            try collectConcatParts(self, node.binop.right.*, parts);
            return;
        }
    }

    // Base case: not a string concatenation binop, add to parts
    try parts.append(self.allocator, node);
}

/// Generate string concatenation: "a" + "b" + "c" -> std.mem.concat(...)
pub fn genStringConcat(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    // Flatten nested concatenations to avoid intermediate allocations
    var parts = std.ArrayList(ast.Node){};
    defer parts.deinit(self.allocator);

    try collectConcatParts(self, ast.Node{ .binop = binop }, &parts);

    // Always use __global_allocator (TryHelper structs can't access outer allocator)
    const alloc_name = "__global_allocator";

    // At module level (scope 0), we can't use 'try' - use 'catch unreachable' instead
    const at_module_level = self.symbol_table.currentScopeLevel() == 0;

    // Generate single concat call with all parts
    if (at_module_level) {
        try emitConst(self, "(std.mem.concat(");
    } else {
        try emitConst(self, "try std.mem.concat(");
    }
    try emitConst(self, alloc_name);
    try emitConst(self, ", u8, &[_][]const u8{ ");
    for (parts.items, 0..) |part, i| {
        if (i > 0) try emitConst(self, ", ");
        try genExpr(self, part);
    }
    if (at_module_level) {
        try emitConst(self, " }) catch unreachable)");
    } else {
        try emitConst(self, " })");
    }
}

/// Generate bytes concatenation: b"a" + b"b"
pub fn genBytesConcat(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    const alloc_name = "__global_allocator";

    // Capture operands as ZigValues
    const left_operand = try self.captureExpr(binop.left.*);
    const right_operand = try self.captureExpr(binop.right.*);

    try emitConst(self, "(runtime.builtins.PyBytes.concat(");
    try emitConst(self, alloc_name);
    try emitConst(self, ", ");
    try self.emitZigValue(left_operand);
    try emitConst(self, ", ");
    try self.emitZigValue(right_operand);
    try emitConst(self, ") catch @panic(\"OOM\"))");
}

/// Generate list/array concatenation
pub fn genListConcat(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    // Check if either operand might produce a runtime value (ArrayList, PyValue)
    // This includes: call expressions, nested binops, and unknown types
    const left_is_call = binop.left.* == .call;
    const right_is_call = binop.right.* == .call;
    const left_is_binop = binop.left.* == .binop;
    const right_is_binop = binop.right.* == .binop;
    const left_is_name = binop.left.* == .name;
    const right_is_name = binop.right.* == .name;
    const left_is_arraylist_var = left_is_name and self.isArrayListVar(binop.left.name.id);
    const right_is_arraylist_var = right_is_name and self.isArrayListVar(binop.right.name.id);

    // Use runtime concatenation for any potentially runtime values
    // This is safer and handles all edge cases (ArrayList, PyValue, etc.)
    const needs_runtime = left_is_call or right_is_call or
        left_is_binop or right_is_binop or
        left_is_name or right_is_name or
        left_type == .unknown or right_type == .unknown or
        left_type == .pyvalue or right_type == .pyvalue or
        left_is_arraylist_var or right_is_arraylist_var;

    // Capture operands as ZigValues
    const left_operand = try self.captureExpr(binop.left.*);
    const right_operand = try self.captureExpr(binop.right.*);

    if (needs_runtime) {
        // Use runtime concatenation for non-comptime values
        try emitConst(self, "try ");
        try emitRuntimeCall2(self, "runtime.concatRuntime", left_operand, right_operand);
    } else {
        // List/array concatenation: use runtime.concat which handles both
        try emitCall2(self, "runtime.concat", left_operand, right_operand);
    }
}

/// Generate tuple concatenation: (1, 2) + (3, 4)
pub fn genTupleConcat(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    // Capture operands as ZigValues
    const left_operand = try self.captureExpr(binop.left.*);
    const right_operand = try self.captureExpr(binop.right.*);

    // Tuple concatenation: use comptime tuple concat (++)
    try self.emitZigValue(left_operand);
    try emitConst(self, " ++ ");
    try self.emitZigValue(right_operand);
}

/// Generate string repetition: "ab" * 3
pub fn genStringRepeat(self: *NativeCodegen, str_expr: ast.Node, count_expr: ast.Node) CodegenError!void {
    // Capture operands as ZigValues
    const str_operand = try self.captureExpr(str_expr);
    const count_operand = try self.captureExpr(count_expr);

    try emitConst(self, "runtime.strRepeat(__global_allocator, ");
    try self.emitZigValue(str_operand);
    try emitConst(self, ", ");
    try emitCountAsUsize(self, count_operand);
    try emitConst(self, ")");
}

/// Generate bytes repetition: b"ab" * 3
pub fn genBytesRepeat(self: *NativeCodegen, bytes_expr: ast.Node, count_expr: ast.Node) CodegenError!void {
    // Capture operands as ZigValues
    const bytes_operand = try self.captureExpr(bytes_expr);
    const count_operand = try self.captureExpr(count_expr);

    try emitConst(self, "(runtime.builtins.PyBytes.repeat(__global_allocator, ");
    try self.emitZigValue(bytes_operand);
    try emitConst(self, ", ");
    try emitCountAsUsize(self, count_operand);
    try emitConst(self, ") catch @panic(\"OOM\"))");
}

/// Generate list repetition: [1, 2] * 3
pub fn genListRepeat(self: *NativeCodegen, list_expr: ast.Node, count_expr: ast.Node) CodegenError!void {
    // Capture operands as ZigValues
    const list_operand = try self.captureExpr(list_expr);
    const count_operand = try self.captureExpr(count_expr);

    try emitConst(self, "try ");
    try emitRuntimeCall2(self, "runtime.repeatRuntime", list_operand, count_operand);
}

/// Generate tuple repetition: (1, 2) * 3
pub fn genTupleRepeat(self: *NativeCodegen, tuple_expr: ast.Node, count_expr: ast.Node) CodegenError!void {
    // Capture operands as ZigValues
    const tuple_operand = try self.captureExpr(tuple_expr);
    const count_operand = try self.captureExpr(count_expr);

    try emitConst(self, "runtime.tupleRepeat(__global_allocator, ");
    try self.emitZigValue(tuple_operand);
    try emitConst(self, ", ");
    try emitCountAsUsize(self, count_operand);
    try emitConst(self, ")");
}

/// Generate slice/list repetition with dynamic count
pub fn genSliceRepeatDynamic(self: *NativeCodegen, list_expr: ast.Node, count_expr: ast.Node) CodegenError!void {
    // Capture count operand as ZigValue
    const count_operand = try self.captureExpr(count_expr);

    try emitConst(self, "runtime.sliceRepeatDynamic(__global_allocator, ");
    // Constant homogeneous list literals produce fixed arrays - use & to coerce to slice
    // Complex or dynamic lists produce ArrayList - use .items
    if (willGenerateAsFixedArray(list_expr)) {
        // Fixed array literal - use & to get slice
        const list_operand = try self.captureExpr(list_expr);
        try emitConst(self, "&");
        try self.emitZigValue(list_operand);
    } else if (producesBlockExpression(list_expr)) {
        const list_operand = try self.captureExpr(list_expr);
        try emitConst(self, "(");
        try self.emitZigValue(list_operand);
        try emitConst(self, ").items");
    } else {
        const list_operand = try self.captureExpr(list_expr);
        try self.emitZigValue(list_operand);
        try emitConst(self, ".items");
    }
    try emitConst(self, ", ");
    try emitCountAsUsize(self, count_operand);
    try emitConst(self, ")");
}

/// Generate unknown type * int multiplication with type dispatch
pub fn genUnknownMultiply(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    const alloc_name = "__global_allocator";
    var em = self.exprEmitter();
    var blk = try em.labeledBlock("mul", "_lhs", binop.left.*);
    try blk.emit("const _rhs = ");
    try genExpr(self, binop.right.*);
    // For string * n with n < 0, return empty string; for numeric types, just multiply
    try blk.emit("; ");
    try blk.startBreak();
    try emitConst(self, "if (@TypeOf(_lhs) == []const u8) (if (_rhs < 0) \"\" else runtime.strRepeat(");
    try emitConst(self, alloc_name);
    try emitConst(self, ", _lhs, @as(usize, @intCast(_rhs)))) else _lhs * _rhs");
    try blk.close();
}
