/// Arithmetic operations: add, sub, mul, div, mod, pow, floor division
/// Main dispatcher that delegates to specialized modules:
/// - bigint_ops.zig: BigInt arbitrary-precision operations
/// - unified_int_ops.zig: UnifiedInt auto-promoting operations, complex numbers
/// - pyvalue_ops.zig: Two-Flow PyValue operations for uncertain types
/// - collection_ops.zig: String/list/tuple concatenation and repetition
/// - power_div_ops.zig: Power, division, floor division, modulo, matrix mul
/// - unary_ops.zig: Unary operations (not, -, +, ~)
///
/// MIGRATION STATUS: Using ZigBuilder - imports added
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const expressions = @import("../../expressions.zig");
const genExpr = expressions.genExpr;
const NativeType = @import("../../../../analysis/native_types/core.zig").NativeType;
const shared = @import("../../shared_maps.zig");
const BinaryDunders = shared.BinaryDunders;
const ReverseDunders = shared.ReverseDunders;
const string_traits = @import("../../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../../analysis/traits/container_traits.zig");
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const builder_mod = @import("codegen.builder");
const ZigValue = builder_mod.ZigValue;

// Import specialized modules
const bigint_ops = @import("bigint_ops.zig");
const unified_int_ops = @import("unified_int_ops.zig");
const pyvalue_ops = @import("pyvalue_ops.zig");
const collection_ops = @import("collection_ops.zig");
const power_div_ops = @import("power_div_ops.zig");
const unary_ops = @import("unary_ops.zig");

// Re-export for backwards compatibility
pub const genBigIntBinOp = bigint_ops.genBigIntBinOp;
pub const genBigIntBinOpRightBig = bigint_ops.genBigIntBinOpRightBig;
pub const needsBigInt = bigint_ops.needsBigInt;
pub const BigIntInvertCtx = bigint_ops.BigIntInvertCtx;
pub const UnknownNegateCtx = bigint_ops.UnknownNegateCtx;

pub const isUnifiedInt = unified_int_ops.isUnifiedInt;
pub const genUnifiedIntBinOp = unified_int_ops.genUnifiedIntBinOp;
pub const genComplexBinOp = unified_int_ops.genComplexBinOp;

pub const isOperandUncertain = pyvalue_ops.isOperandUncertain;
pub const PyValueMethods = pyvalue_ops.PyValueMethods;

pub const willGenerateAsFixedArray = collection_ops.willGenerateAsFixedArray;
pub const genExprWrapped = collection_ops.genExprWrapped;

pub const genUnaryOp = unary_ops.genUnaryOp;

/// Generate binary operations (+, -, *, /, %, //)
pub fn genBinOp(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
    // Check for BigInt operations first
    // Use scope-aware type inference to prevent cross-function type pollution
    const bigint_left_type = try self.inferExprScoped(binop.left.*);
    const bigint_right_type = try self.inferExprScoped(binop.right.*);

    // TWO-FLOW TYPE SYSTEM: Check if either operand is uncertain (needs PyValue)
    // If so, use safe PyValue arithmetic methods instead of raw Zig operators
    const left_uncertain = pyvalue_ops.isOperandUncertain(self, binop.left.*);
    const right_uncertain = pyvalue_ops.isOperandUncertain(self, binop.right.*);
    if (left_uncertain or right_uncertain) {
        // Only use PyValue ops for supported arithmetic operations
        // EXCEPTION: For Mod operator, check if left is string - that's string formatting, not arithmetic
        if (pyvalue_ops.PyValueMethods.get(@tagName(binop.op)) != null) {
            // Skip PyValue.mod() for string formatting - let the standard handling do it
            if (binop.op == .Mod) {
                const left_type = try self.inferExprScoped(binop.left.*);
                if (string_traits.isString(left_type) or (binop.left.* == .constant and binop.left.constant.value == .string)) {
                    // String formatting - don't use PyValue.mod(), fall through to standard handling
                } else {
                    try pyvalue_ops.genPyValueBinOp(self, binop);
                    return;
                }
            } else {
                try pyvalue_ops.genPyValueBinOp(self, binop);
                return;
            }
        }
    }

    // IMPORTANT: For Mod operator with string/bytes left operand, this is string formatting
    // NOT BigInt modulo. Skip BigInt handling to let the string formatting handler handle it.
    const is_string_formatting = blk: {
        if (binop.op != .Mod) break :blk false;
        // Check if left operand is a string/bytes literal
        if (binop.left.* == .constant) {
            if (binop.left.constant.value == .string) break :blk true;
            if (binop.left.constant.value == .bytes) break :blk true;
        }
        // Check inferred type
        if (string_traits.isString(bigint_left_type) or string_traits.isBytes(bigint_left_type)) break :blk true;
        break :blk false;
    };

    // If left operand needs BigInt (explicit bigint or unbounded int), use BigInt method calls
    // BUT NOT for string formatting operations
    if (bigint_ops.needsBigInt(bigint_left_type) and !is_string_formatting) {
        try bigint_ops.genBigIntBinOp(self, binop, bigint_left_type, bigint_right_type);
        return;
    }

    // If right operand needs BigInt (e.g., 0 - bigint), convert left to BigInt and use BigInt ops
    // BUT NOT for string formatting operations
    if (bigint_ops.needsBigInt(bigint_right_type) and !is_string_formatting) {
        try bigint_ops.genBigIntBinOpRightBig(self, binop, bigint_left_type, bigint_right_type);
        return;
    }

    // If either operand is UnifiedInt, use UnifiedInt method calls
    // BUT NOT for string formatting operations
    if ((unified_int_ops.isUnifiedInt(bigint_left_type) or unified_int_ops.isUnifiedInt(bigint_right_type)) and !is_string_formatting) {
        try unified_int_ops.genUnifiedIntBinOp(self, binop, bigint_left_type, bigint_right_type);
        return;
    }

    // Check for custom class with dunder methods (e.g., x + 1 calls x.__add__(1))
    // Must check before other type-specific handling
    // IMPORTANT: Only call dunder methods if the CLASS operand is a KNOWN class instance (not anytype)
    const left_is_anytype = if (binop.left.* == .name) self.anytype_params.contains(binop.left.name.id) else false;
    const right_is_anytype = if (binop.right.* == .name) self.anytype_params.contains(binop.right.name.id) else false;

    // If left operand is a known class instance (not anytype), call dunder method on left
    if (type_traits.isClassInstance(bigint_left_type) and !left_is_anytype) {
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
    if (type_traits.isClassInstance(bigint_right_type) and !right_is_anytype and !type_traits.isClassInstance(bigint_left_type)) {
        if (ReverseDunders.get(@tagName(binop.op))) |rdunder_method| {
            var em = self.exprEmitter();
            const radd_label = em.reserveLabelId();
            try self.emitFmt("(radd_blk_{d}: {{ const _rhs = ", .{radd_label});
            try genExpr(self, binop.right.*);
            try self.output.writer(self.allocator).print("; if (runtime.container_dispatch.hasPtrChildDecl(@TypeOf(_rhs), \"{s}\")) {{ break :radd_blk_{d} try _rhs.{s}(__global_allocator, ", .{ rdunder_method, radd_label, rdunder_method });
            try genExpr(self, binop.left.*);
            try self.emitFmt("); }} else {{ return error.TypeError; }} }})", .{});
            return;
        }
    }

    // Check for complex number operations and mixed int/float arithmetic
    if (binop.op == .Add or binop.op == .Sub) {
        const left_type = try self.inferExprScoped(binop.left.*);
        const right_type = try self.inferExprScoped(binop.right.*);

        // Handle complex arithmetic: int/float +/- complex -> complex
        if (left_type == .complex or right_type == .complex) {
            try unified_int_ops.genComplexBinOp(self, binop, left_type, right_type);
            return;
        }

        // Handle mixed int/float arithmetic using runtime helper
        const left_is_int = type_traits.isIntegral(left_type);
        const right_is_int = type_traits.isIntegral(right_type);
        const left_is_float = type_traits.isFloating(left_type);
        const right_is_float = type_traits.isFloating(right_type);
        const left_is_unknown = type_traits.isUnknown(left_type);
        const right_is_unknown = type_traits.isUnknown(right_type);

        const needs_runtime_helper = (left_is_int and right_is_float) or
            (left_is_float and right_is_int) or
            (left_is_int and right_is_unknown) or
            (left_is_unknown and right_is_int) or
            (left_is_float and right_is_unknown) or
            (left_is_unknown and right_is_float);

        if (needs_runtime_helper) {
            if (binop.op == .Add) {
                try self.emit("runtime.addNum(");
            } else {
                try self.emit("runtime.subtractNum(");
            }
            try genExpr(self, binop.left.*);
            try self.emit(", ");
            try genExpr(self, binop.right.*);
            try self.emit(")");
            return;
        }
    }

    // Check if this is string concatenation
    if (binop.op == .Add) {
        const left_type = try self.inferExprScoped(binop.left.*);
        const right_type = try self.inferExprScoped(binop.right.*);

        if (string_traits.isString(left_type) or string_traits.isString(right_type)) {
            try collection_ops.genStringConcat(self, binop);
            return;
        }

        if (string_traits.isBytes(left_type) or string_traits.isBytes(right_type)) {
            try collection_ops.genBytesConcat(self, binop);
            return;
        }

        // Check for list concatenation
        const left_is_arraylist_var = binop.left.* == .name and self.isArrayListVar(binop.left.name.id);
        const right_is_arraylist_var = binop.right.* == .name and self.isArrayListVar(binop.right.name.id);
        if (container_traits.isList(left_type) or container_traits.isList(right_type) or
            binop.left.* == .list or binop.right.* == .list or
            left_is_arraylist_var or right_is_arraylist_var)
        {
            try collection_ops.genListConcat(self, binop, left_type, right_type);
            return;
        }

        // Check for tuple concatenation
        const left_is_tuple = binop.left.* == .tuple or container_traits.isTuple(left_type);
        const right_is_tuple = binop.right.* == .tuple or container_traits.isTuple(right_type);
        if (left_is_tuple and right_is_tuple) {
            try collection_ops.genTupleConcat(self, binop);
            return;
        }

        // Check for complex number addition
        if (left_type == .complex or right_type == .complex) {
            try unified_int_ops.genComplexBinOp(self, binop, left_type, right_type);
            return;
        }
    }

    // Check if this is string/collection multiplication
    if (binop.op == .Mult) {
        const left_type = try self.inferExprScoped(binop.left.*);
        const right_type = try self.inferExprScoped(binop.right.*);

        // str * n
        if (string_traits.isString(left_type) and (type_traits.isIntegral(right_type) or type_traits.isUnknown(right_type))) {
            try collection_ops.genStringRepeat(self, binop.left.*, binop.right.*);
            return;
        }
        // n * str
        if (string_traits.isString(right_type) and (type_traits.isIntegral(left_type) or type_traits.isUnknown(left_type))) {
            try collection_ops.genStringRepeat(self, binop.right.*, binop.left.*);
            return;
        }

        // bytes * n
        if (string_traits.isBytes(left_type) and (type_traits.isIntegral(right_type) or type_traits.isUnknown(right_type))) {
            try collection_ops.genBytesRepeat(self, binop.left.*, binop.right.*);
            return;
        }
        // n * bytes
        if (string_traits.isBytes(right_type) and (type_traits.isIntegral(left_type) or type_traits.isUnknown(left_type))) {
            try collection_ops.genBytesRepeat(self, binop.right.*, binop.left.*);
            return;
        }

        // list * n (runtime)
        const left_is_arraylist_var = binop.left.* == .name and self.isArrayListVar(binop.left.name.id);
        if ((container_traits.isList(left_type) or container_traits.isArray(left_type) or binop.left.* == .list or left_is_arraylist_var) and
            (type_traits.isIntegral(right_type) or type_traits.isUnknown(right_type)))
        {
            try collection_ops.genListRepeat(self, binop.left.*, binop.right.*);
            return;
        }
        // n * list (runtime)
        const right_is_arraylist_var = binop.right.* == .name and self.isArrayListVar(binop.right.name.id);
        if ((container_traits.isList(right_type) or container_traits.isArray(right_type) or binop.right.* == .list or right_is_arraylist_var) and
            (type_traits.isIntegral(left_type) or type_traits.isUnknown(left_type)))
        {
            try collection_ops.genListRepeat(self, binop.right.*, binop.left.*);
            return;
        }

        // unknown * int - could be string repeat
        if (type_traits.isUnknown(left_type) and (type_traits.isIntegral(right_type) or type_traits.isUnknown(right_type))) {
            try collection_ops.genUnknownMultiply(self, binop);
            return;
        }

        // tuple * n
        const left_is_tuple = binop.left.* == .tuple or container_traits.isTuple(left_type);
        const right_is_tuple = binop.right.* == .tuple or container_traits.isTuple(right_type);
        if (left_is_tuple and (type_traits.isIntegral(right_type) or type_traits.isUnknown(right_type))) {
            try collection_ops.genTupleRepeat(self, binop.left.*, binop.right.*);
            return;
        }
        if (right_is_tuple and (type_traits.isIntegral(left_type) or type_traits.isUnknown(left_type))) {
            try collection_ops.genTupleRepeat(self, binop.right.*, binop.left.*);
            return;
        }

        // list * n (slice repeat)
        const left_is_list = binop.left.* == .list or container_traits.isList(left_type);
        const right_is_list = binop.right.* == .list or container_traits.isList(right_type);
        if (left_is_list and (type_traits.isIntegral(right_type) or type_traits.isUnknown(right_type))) {
            try collection_ops.genSliceRepeatDynamic(self, binop.left.*, binop.right.*);
            return;
        }
        if (right_is_list and (type_traits.isIntegral(left_type) or type_traits.isUnknown(left_type))) {
            try collection_ops.genSliceRepeatDynamic(self, binop.right.*, binop.left.*);
            return;
        }
    }

    // Delegate remaining operations to specialized handlers
    try genArithmeticCore(self, binop, bigint_left_type, bigint_right_type);
}

/// Core arithmetic operations: floor division, modulo, power, division, matrix multiply, shifts, bitwise
fn genArithmeticCore(self: *NativeCodegen, binop: ast.Node.BinOp, left_type: NativeType, right_type: NativeType) CodegenError!void {
    // Special handling for floor division (//)
    if (binop.op == .FloorDiv) {
        try power_div_ops.genFloorDivOp(self, binop, left_type, right_type);
        return;
    }

    // Special handling for modulo / string formatting
    if (binop.op == .Mod) {
        try power_div_ops.genModOp(self, binop, left_type, right_type);
        return;
    }

    // Special handling for power
    if (binop.op == .Pow) {
        try power_div_ops.genPowOp(self, binop, left_type, right_type);
        return;
    }

    // Special handling for division
    if (binop.op == .Div) {
        try power_div_ops.genDivOp(self, binop, left_type, right_type);
        return;
    }

    // Matrix multiplication (@)
    if (binop.op == .MatMul) {
        try power_div_ops.genMatMulOp(self, binop, left_type, right_type);
        return;
    }

    // Large shifts that require UnifiedInt
    if (binop.op == .LShift) {
        const is_comptime_shift = binop.right.* == .constant and binop.right.constant.value == .int;
        const is_large_shift = is_comptime_shift and binop.right.constant.value.int >= 63;

        if (is_large_shift or !is_comptime_shift) {
            try power_div_ops.genLargeShiftOp(self, binop);
            return;
        }
    }

    // Dict merge (Python 3.9+)
    if (binop.op == .BitOr and container_traits.isDict(left_type) and container_traits.isDict(right_type)) {
        try power_div_ops.genDictMerge(self, binop);
        return;
    }

    // Standard binary operations
    try power_div_ops.genSimpleBinOp(self, binop, left_type, right_type);
}
