/// SIMD vectorization and parallelization analysis for list comprehensions
const std = @import("std");
const ast = @import("analysis.ast");

/// SIMD vectorization info for list comprehensions
pub const SimdInfo = struct {
    /// Can this comprehension be vectorized?
    vectorizable: bool = false,
    /// Element type (i64, f64)
    element_type: SimdElementType = .i64,
    /// The vectorizable operation
    op: SimdOp = .none,
    /// Vector width to use (4, 8, 16)
    vector_width: u8 = 8,
    /// Is the source a contiguous range?
    is_range: bool = false,
    /// Static range bounds (if known)
    range_start: ?i64 = null,
    range_end: ?i64 = null,
};

pub const SimdElementType = enum { i64, f64, i32, f32 };

pub const SimdOp = enum {
    none,
    // Arithmetic
    add, // x + c or c + x
    sub, // x - c or c - x
    mul, // x * c or c * x
    div, // x / c
    neg, // -x
    // Bitwise
    bit_and,
    bit_or,
    bit_xor,
    shl, // x << c
    shr, // x >> c
    // Compound
    mul_add, // x * a + b (FMA)
    square, // x * x
};

/// Analyze a list comprehension for SIMD vectorization potential
pub fn analyzeListCompForSimd(listcomp: ast.Node.ListComp) SimdInfo {
    var info = SimdInfo{};

    // Must have exactly one generator with no conditions
    if (listcomp.generators.len != 1) return info;
    const gen = listcomp.generators[0];
    if (gen.ifs.len > 0) return info; // Conditionals break vectorization

    // Check if iterating over range()
    if (gen.iter.* == .call and gen.iter.call.func.* == .name) {
        if (std.mem.eql(u8, gen.iter.call.func.name.id, "range")) {
            info.is_range = true;
            const args = gen.iter.call.args;
            // Extract static bounds if possible
            if (args.len >= 1 and args[0] == .constant and args[0].constant.value == .int) {
                if (args.len == 1) {
                    info.range_start = 0;
                    info.range_end = args[0].constant.value.int;
                } else if (args.len >= 2 and args[1] == .constant and args[1].constant.value == .int) {
                    info.range_start = args[0].constant.value.int;
                    info.range_end = args[1].constant.value.int;
                }
            }
        }
    }

    // Target must be a simple name
    if (gen.target.* != .name) return info;
    const loop_var = gen.target.name.id;

    // Analyze the element expression
    const elt = listcomp.elt.*;
    const op_info = analyzeSimdExpr(elt, loop_var);
    if (op_info.op == .none) return info;

    info.vectorizable = true;
    info.op = op_info.op;
    info.element_type = op_info.element_type;

    // Choose vector width based on element type
    info.vector_width = switch (info.element_type) {
        .i64, .f64 => 4, // 256-bit vectors / 64-bit = 4 elements
        .i32, .f32 => 8, // 256-bit vectors / 32-bit = 8 elements
    };

    return info;
}

const SimdExprInfo = struct {
    op: SimdOp = .none,
    element_type: SimdElementType = .i64,
    constant: ?i64 = null,
};

/// Analyze expression to determine if it's a simple vectorizable op
fn analyzeSimdExpr(expr: ast.Node, loop_var: []const u8) SimdExprInfo {
    var info = SimdExprInfo{};

    switch (expr) {
        .name => |n| {
            // Just the loop variable: identity (can still vectorize as copy)
            if (std.mem.eql(u8, n.id, loop_var)) {
                info.op = .add; // x + 0 is identity
                info.constant = 0;
                return info;
            }
        },
        .binop => |b| {
            // Check for simple patterns: x op const, const op x
            const left_is_var = b.left.* == .name and std.mem.eql(u8, b.left.name.id, loop_var);
            const right_is_var = b.right.* == .name and std.mem.eql(u8, b.right.name.id, loop_var);
            const left_is_const = b.left.* == .constant and b.left.constant.value == .int;
            const right_is_const = b.right.* == .constant and b.right.constant.value == .int;

            // x * x pattern (square)
            if (left_is_var and right_is_var and b.op == .Mult) {
                info.op = .square;
                return info;
            }

            // x op const or const op x
            if ((left_is_var and right_is_const) or (left_is_const and right_is_var)) {
                const c = if (right_is_const) b.right.constant.value.int else b.left.constant.value.int;
                info.constant = c;

                info.op = switch (b.op) {
                    .Add => .add,
                    .Sub => if (left_is_var) .sub else .none, // const - x not simple
                    .Mult => .mul,
                    .Div, .FloorDiv => if (left_is_var) .div else .none,
                    .BitOr => .bit_or,
                    .BitAnd => .bit_and,
                    .BitXor => .bit_xor,
                    .LShift => if (left_is_var) .shl else .none,
                    .RShift => if (left_is_var) .shr else .none,
                    else => .none,
                };
                return info;
            }
        },
        .unaryop => |u| {
            // -x pattern
            if (u.op == .USub and u.operand.* == .name and std.mem.eql(u8, u.operand.name.id, loop_var)) {
                info.op = .neg;
                return info;
            }
        },
        else => {},
    }

    return info;
}

/// Info about whether a list comprehension can be parallelized
pub const ParallelInfo = struct {
    /// Can this be safely parallelized?
    parallelizable: bool = false,
    /// Is it a large enough workload to benefit from parallelization?
    worth_parallelizing: bool = false,
    /// Minimum threshold for parallel (smaller runs sequentially)
    min_parallel_size: usize = 1024,
    /// Operation type (for runtime.parallel)
    op: SimdOp = .none,
};

/// Check if a list comprehension can be safely parallelized
/// Requires: pure element expression, no loop-carried dependencies
pub fn analyzeListCompForParallel(listcomp: ast.Node.ListComp) ParallelInfo {
    var info = ParallelInfo{};

    // Must have exactly one generator
    if (listcomp.generators.len != 1) return info;
    const gen = listcomp.generators[0];

    // Conditionals make parallelization complex (varying output size)
    if (gen.ifs.len > 0) return info;

    // Target must be simple name
    if (gen.target.* != .name) return info;
    const loop_var = gen.target.name.id;

    // Check if element expression is pure and parallelizable
    if (!isParallelizableExpr(listcomp.elt.*, loop_var)) return info;

    // Check for large range (worth parallelizing)
    if (gen.iter.* == .call and gen.iter.call.func.* == .name) {
        if (std.mem.eql(u8, gen.iter.call.func.name.id, "range")) {
            const args = gen.iter.call.args;
            if (args.len >= 1 and args[0] == .constant and args[0].constant.value == .int) {
                const end_val = if (args.len == 1)
                    args[0].constant.value.int
                else if (args.len >= 2 and args[1] == .constant and args[1].constant.value == .int)
                    args[1].constant.value.int
                else
                    0;
                const start_val: i64 = if (args.len >= 2 and args[0] == .constant and args[0].constant.value == .int)
                    args[0].constant.value.int
                else
                    0;

                const size = end_val - start_val;
                info.worth_parallelizing = size >= info.min_parallel_size;
            }
        }
    }

    // Get the operation type
    const simd_info = analyzeSimdExpr(listcomp.elt.*, loop_var);
    info.op = simd_info.op;
    info.parallelizable = simd_info.op != .none;

    return info;
}

/// Check if expression is safe to parallelize (no side effects, no shared state)
fn isParallelizableExpr(expr: ast.Node, loop_var: []const u8) bool {
    return switch (expr) {
        .name => |n| std.mem.eql(u8, n.id, loop_var), // Only loop var is safe
        .constant => true,
        .binop => |b| isParallelizableExpr(b.left.*, loop_var) and isParallelizableExpr(b.right.*, loop_var),
        .unaryop => |u| isParallelizableExpr(u.operand.*, loop_var),
        // Function calls are NOT parallelizable (might have side effects)
        .call => false,
        // Attribute access might access shared state
        .attribute => false,
        // Subscript might access shared state
        .subscript => false,
        else => false,
    };
}
