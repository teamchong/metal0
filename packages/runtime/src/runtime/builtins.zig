/// Built-in Python functions implemented in Zig
/// This module re-exports from specialized submodules for better organization.
const std = @import("std");

// =============================================================================
// PyCallable - Generic callable wrapper for heterogeneous callable lists
// =============================================================================

/// A type-erased wrapper for any callable (function, lambda, class)
/// Used by codegen for lists like [bool, int, float, str]
pub const PyCallable = struct {
    /// The wrapped function pointer (type-erased)
    ptr: *const anyopaque,
    /// Type identifier for runtime dispatch (comptime hash of type name)
    type_id: usize,

    /// Create a PyCallable from any function/callable type
    pub fn fromAny(comptime T: type, func: *const T) PyCallable {
        return .{
            .ptr = @ptrCast(func),
            .type_id = comptime typeHash(T),
        };
    }

    /// Comptime type hash from type name
    fn typeHash(comptime T: type) usize {
        const name = @typeName(T);
        var h: usize = 5381;
        for (name) |c| {
            h = ((h << 5) +% h) +% c;
        }
        return h;
    }

    /// Check equality (by pointer and type)
    pub fn eql(a: PyCallable, b: PyCallable) bool {
        return a.ptr == b.ptr and a.type_id == b.type_id;
    }
};

// =============================================================================
// Re-exports from submodules
// =============================================================================

/// Power function (pow)
pub const pow_mod = @import("builtins/pow.zig");
pub const PyPowResult = pow_mod.PyPowResult;
pub const pyPow = pow_mod.pyPow;
pub const pow = pow_mod.pyPow; // Alias for Python's pow() builtin

/// String representation (repr, str)
pub const repr_mod = @import("builtins/repr.zig");
pub const PyBytes = repr_mod.PyBytes;
pub const bytesLiteral = repr_mod.bytesLiteral;
pub const strLiteral = repr_mod.strLiteral;
pub const bytesRepr = repr_mod.bytesRepr;
pub const stringRepr = repr_mod.stringRepr;
pub const tupleRepr = repr_mod.tupleRepr;
pub const pyRepr = repr_mod.pyRepr;
pub const pyStr = repr_mod.pyStr;
pub const valueRepr = repr_mod.valueRepr;
pub const valueStr = repr_mod.valueStr;

/// Iterator functions (range, enumerate, zip, iter, next)
pub const iter_mod = @import("builtins/iterators.zig");
pub const range = iter_mod.range;
pub const enumerate = iter_mod.enumerate;
pub const zip2 = iter_mod.zip2;
pub const zip3 = iter_mod.zip3;
pub const rangeLazy = iter_mod.rangeLazy;
pub const RangeIterator = iter_mod.RangeIterator;
pub const StringIterator = iter_mod.StringIterator;
pub const strIterator = iter_mod.strIterator;
pub const strIter = iter_mod.strIter;
pub const iter = iter_mod.iter;
pub const GenericIterator = iter_mod.GenericIterator;
pub const IteratorItem = iter_mod.IteratorItem;
pub const next = iter_mod.next;

/// Aggregate functions (all, any, sum, min, max, sorted, reversed, filter)
pub const agg_mod = @import("builtins/aggregates.zig");
pub const all = agg_mod.all;
pub const any = agg_mod.any;
pub const abs = agg_mod.abs;
pub const minList = agg_mod.minList;
pub const minVarArgs = agg_mod.minVarArgs;
pub const maxList = agg_mod.maxList;
pub const maxVarArgs = agg_mod.maxVarArgs;
pub const minIterable = agg_mod.minIterable;
pub const maxIterable = agg_mod.maxIterable;
pub const sum = agg_mod.sum;
pub const sorted = agg_mod.sorted;
pub const reversed = agg_mod.reversed;
pub const filterTruthy = agg_mod.filterTruthy;

/// Conversion functions (hex, oct, bin, int with base, round)
pub const conv_mod = @import("builtins/conversion.zig");
pub const hex = conv_mod.hex;
pub const oct = conv_mod.oct;
pub const bin = conv_mod.bin;
pub const intWithBaseOnly = conv_mod.intWithBaseOnly;
pub const intWithBase = conv_mod.intWithBase;
pub const round = conv_mod.round;
pub const bankersRound = conv_mod.bankersRound;
pub const pyRound = conv_mod.pyRound;

/// I/O functions (print, input, breakpoint)
pub const io_mod = @import("builtins/io.zig");
pub const input = io_mod.input;
pub const breakpoint = io_mod.breakpoint;
pub const print = io_mod.print;

/// Introspection functions (callable, len, id, hash)
pub const intro_mod = @import("builtins/introspection.zig");
pub const callable = intro_mod.callable;
pub const isSlice = intro_mod.isSlice;
pub const len = intro_mod.len;
pub const id = intro_mod.id;
pub const hash = intro_mod.hash;
pub const tupleHash = intro_mod.tupleHash;

/// Operator comparison functions (eq, ne, lt, le, gt, ge, pyEqual)
pub const ops_mod = @import("builtins/operators.zig");
pub const operatorEq = ops_mod.operatorEq;
pub const operatorNe = ops_mod.operatorNe;
pub const operatorLt = ops_mod.operatorLt;
pub const operatorLe = ops_mod.operatorLe;
pub const operatorGt = ops_mod.operatorGt;
pub const operatorGe = ops_mod.operatorGe;
pub const classInstanceEq = ops_mod.classInstanceEq;
pub const classInstanceNe = ops_mod.classInstanceNe;
pub const classInstanceLt = ops_mod.classInstanceLt;
pub const classInstanceLe = ops_mod.classInstanceLe;
pub const classInstanceGt = ops_mod.classInstanceGt;
pub const classInstanceGe = ops_mod.classInstanceGe;
pub const assertEqualGeneric = ops_mod.assertEqualGeneric;
pub const pyEqual = ops_mod.pyEqual;
pub const pyEqualSliceToTuple = ops_mod.pyEqualSliceToTuple;

/// Operator callable structs for functional programming (operator.mod, operator.pow, etc.)
/// These allow passing operators as first-class functions: mod = operator.mod; mod(a, b)
/// Called as: OperatorMod{}.call(a, b) - self is the struct instance
pub const OperatorMod = struct {
    pub fn call(_: @This(), a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        const T = @TypeOf(a);
        if (@typeInfo(T) == .float) {
            // Python floored modulo semantics for floats
            const result = @mod(a, b);
            // Handle sign correction for Python semantics
            if ((result > 0 and b < 0) or (result < 0 and b > 0)) {
                return result + b;
            }
            return result;
        }
        return @mod(a, b);
    }
};

pub const OperatorPow = struct {
    pub fn call(_: @This(), base: anytype, exp: @TypeOf(base)) @TypeOf(base) {
        const T = @TypeOf(base);
        if (@typeInfo(T) == .float) {
            return std.math.pow(T, base, exp);
        }
        // For integers, use std.math.pow with conversion
        const base_f: f64 = @floatFromInt(base);
        const exp_f: f64 = @floatFromInt(exp);
        const result = std.math.pow(f64, base_f, exp_f);
        return @intFromFloat(result);
    }
};

pub const OperatorTruediv = struct {
    pub fn call(_: @This(), a: anytype, b: @TypeOf(a)) f64 {
        const T = @TypeOf(a);
        if (@typeInfo(T) == .float) {
            return a / b;
        }
        // Integer true division returns float
        const a_f: f64 = @floatFromInt(a);
        const b_f: f64 = @floatFromInt(b);
        return a_f / b_f;
    }
};

pub const OperatorFloordiv = struct {
    pub fn call(_: @This(), a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        const T = @TypeOf(a);
        if (@typeInfo(T) == .float) {
            return @floor(a / b);
        }
        return @divFloor(a, b);
    }
};

/// Type functions (str, bytes, bytearray, memoryview, bigint)
pub const types_mod = @import("builtins/types.zig");
pub const str = types_mod.str;
pub const bytes = types_mod.bytes;
pub const bytearray = types_mod.bytearray;
pub const memoryview = types_mod.memoryview;
pub const bytes_callable = types_mod.bytes_callable;
pub const bytearray_callable = types_mod.bytearray_callable;
pub const str_callable = types_mod.str_callable;
pub const memoryview_callable = types_mod.memoryview_callable;
pub const compile = types_mod.compile;
pub const exec = types_mod.exec;
pub const structPackNoArgs = types_mod.structPackNoArgs;
pub const structPackIntoNoArgs = types_mod.structPackIntoNoArgs;
pub const CompareOp = types_mod.CompareOp;
pub const bigIntDivmod = types_mod.bigIntDivmod;
pub const bigIntCompare = types_mod.bigIntCompare;

/// Type constructor callables (list, tuple, set, frozenset, deque, complex)
pub const cons_mod = @import("builtins/constructors.zig");
pub const list = cons_mod.list;
pub const tuple = cons_mod.tuple;
pub const set = cons_mod.set;
pub const frozenset = cons_mod.frozenset;
pub const deque = cons_mod.deque;

/// Complex number type constructor
pub const pycomplex_mod = @import("pycomplex.zig");
pub const complex = pycomplex_mod.PyComplex.create;
