/// Built-in Python functions implemented in Zig
/// This module re-exports from specialized submodules for better organization.
const std = @import("std");
const PyValue = @import("../Objects/object.zig").PyValue;
const type_predicates = @import("type_predicates.zig");

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
pub const pyPowAsPyValue = pow_mod.pyPowAsPyValue; // Returns PyValue directly for O(1) type compat

/// Python pow() builtin as a callable struct (for `for pow_op in pow, operator.pow:`)
/// This allows pow to be used identically to operator.pow with .call() syntax
/// Returns error union for compatibility with codegen that emits `try`
/// Note: static call function (no @This() param) for use as type, not instance
pub const pow = struct {
    const op_ops = @import("operator_ops.zig");

    /// Call with complex support - returns PyValue (float or complex)
    /// Python: (-2.0) ** 0.5 returns complex, 4.0 ** 0.5 returns float
    /// NOTE: Returns PyValue (not PyPowResult) for O(1) type compatibility
    pub fn call(base: anytype, exp: @TypeOf(base)) !PyValue {
        const T = @TypeOf(base);

        // Convert to f64 for complex-capable pow
        const base_f: f64 = switch (@typeInfo(T)) {
            .int, .comptime_int => @floatFromInt(base),
            .float, .comptime_float => @floatCast(base),
            else => @compileError("pow requires numeric types"),
        };
        const exp_f: f64 = switch (@typeInfo(T)) {
            .int, .comptime_int => @floatFromInt(exp),
            .float, .comptime_float => @floatCast(exp),
            else => @compileError("pow requires numeric types"),
        };

        return pyPowAsPyValue(base_f, exp_f);
    }

    /// Legacy call returning same type as input (for int**int cases)
    pub fn callTyped(base: anytype, exp: @TypeOf(base)) !@TypeOf(base) {
        const T = @TypeOf(base);
        // Dispatch to concrete functions to reduce monomorphization
        if (T == i64) return op_ops.powI64(base, exp);
        if (T == f64) return op_ops.powF64(base, exp);
        // Fallback for other numeric types
        if (@typeInfo(T) == .float) {
            return @floatCast(try op_ops.powF64(@floatCast(base), @floatCast(exp)));
        }
        // Integer fallback
        const base_f: f64 = @floatFromInt(base);
        const exp_f: f64 = @floatFromInt(exp);
        const result = std.math.pow(f64, base_f, exp_f);
        return @intFromFloat(result);
    }

    /// Alias for backwards compatibility
    pub const callComplex = call;
};

/// String representation (repr, str)
pub const repr_mod = @import("builtins/repr.zig");
pub const PyBytes = repr_mod.PyBytes;
pub const bytesLiteral = repr_mod.bytesLiteral;
pub const strLiteral = repr_mod.strLiteral;
pub const extractBytesData = repr_mod.extractBytesData;
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
pub const filter = agg_mod.filter;
pub const iterBuiltin = agg_mod.iterBuiltin;

/// Conversion functions (hex, oct, bin, int with base, round, ord, chr)
pub const conv_mod = @import("builtins/conversion.zig");
pub const hex = conv_mod.hex;
pub const oct = conv_mod.oct;
pub const bin = conv_mod.bin;
pub const intWithBaseOnly = conv_mod.intWithBaseOnly;
pub const intWithBase = conv_mod.intWithBase;
pub const round = conv_mod.round;
pub const bankersRound = conv_mod.bankersRound;
pub const pyRound = conv_mod.pyRound;
pub const ord = conv_mod.ord;
pub const chr = conv_mod.chr;
// Centralized integer extraction helpers - use these instead of scattered type checks
pub const extractI32Clamped = conv_mod.extractI32Clamped;
pub const extractI64 = conv_mod.extractI64;

/// I/O functions (print, input, breakpoint)
pub const io_mod = @import("builtins/io.zig");
pub const input = io_mod.input;
pub const breakpoint = io_mod.breakpoint;
pub const print = io_mod.print;
pub const printWithOptions = io_mod.printWithOptions;

/// sys module for print() file parameter
pub const sys = @import("../Lib/sys.zig");

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
    const op_ops = @import("operator_ops.zig");

    pub fn call(_: @This(), a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        const T = @TypeOf(a);
        // Dispatch to concrete functions to reduce monomorphization
        if (T == i64) return op_ops.modI64(a, b);
        if (T == f64) return @floatCast(op_ops.modF64(a, b));
        // Fallback for other numeric types
        if (@typeInfo(T) == .float) {
            return @floatCast(op_ops.modF64(@floatCast(a), @floatCast(b)));
        }
        return @mod(a, b);
    }
};

pub const OperatorPow = struct {
    const op_ops = @import("operator_ops.zig");

    /// Legacy call returning same type as input (for backwards compat)
    pub fn call(_: @This(), base: anytype, exp: @TypeOf(base)) !@TypeOf(base) {
        const T = @TypeOf(base);
        // Dispatch to concrete functions to reduce monomorphization
        if (T == i64) return op_ops.powI64(base, exp);
        if (T == f64) return op_ops.powF64(base, exp);
        // Fallback for other numeric types
        if (@typeInfo(T) == .float) {
            return @floatCast(try op_ops.powF64(@floatCast(base), @floatCast(exp)));
        }
        // Integer fallback
        const base_f: f64 = @floatFromInt(base);
        const exp_f: f64 = @floatFromInt(exp);
        const result = std.math.pow(f64, base_f, exp_f);
        return @intFromFloat(result);
    }

    /// Call with complex support - returns PyValue (float or complex)
    /// NOTE: Returns PyValue (not PyPowResult) for O(1) type compatibility
    pub fn callComplex(_: @This(), base: anytype, exp: anytype) !PyValue {
        const BT = @TypeOf(base);
        const ET = @TypeOf(exp);

        const base_f: f64 = switch (@typeInfo(BT)) {
            .int, .comptime_int => @floatFromInt(base),
            .float, .comptime_float => @floatCast(base),
            else => @compileError("pow requires numeric types for base"),
        };

        const exp_f: f64 = switch (@typeInfo(ET)) {
            .int, .comptime_int => @floatFromInt(exp),
            .float, .comptime_float => @floatCast(exp),
            else => @compileError("pow requires numeric types for exp"),
        };

        return pyPowAsPyValue(base_f, exp_f);
    }
};

pub const OperatorTruediv = struct {
    const op_ops = @import("operator_ops.zig");

    pub fn call(_: @This(), a: anytype, b: @TypeOf(a)) f64 {
        const T = @TypeOf(a);
        // Dispatch to concrete functions to reduce monomorphization
        if (T == i64) return op_ops.truedivI64(a, b);
        if (T == f64) return op_ops.truedivF64(a, b);
        // Fallback for other numeric types
        if (@typeInfo(T) == .float) {
            return op_ops.truedivF64(@floatCast(a), @floatCast(b));
        }
        // Integer fallback
        const a_f: f64 = @floatFromInt(a);
        const b_f: f64 = @floatFromInt(b);
        return a_f / b_f;
    }
};

pub const OperatorFloordiv = struct {
    const op_ops = @import("operator_ops.zig");

    pub fn call(_: @This(), a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        const T = @TypeOf(a);
        // Dispatch to concrete functions to reduce monomorphization
        if (T == i64) return op_ops.floordivI64(a, b);
        if (T == f64) return @floatCast(op_ops.floordivF64(a, b));
        // Fallback for other numeric types
        if (@typeInfo(T) == .float) {
            return @floatCast(op_ops.floordivF64(@floatCast(a), @floatCast(b)));
        }
        return @divFloor(a, b);
    }
};

/// Format callable namespace for builtins.format(value, format_spec)
/// Used when format() is passed as a first-class function
/// Called as: runtime.builtins.format.call(allocator, value, format_spec)
pub const format = struct {
    const pyformat = @import("../runtime.zig").pyFormat;
    const PythonError = @import("../runtime.zig").PythonError;

    pub fn call(allocator: std.mem.Allocator, value: anytype, format_spec: []const u8) PythonError![]const u8 {
        return pyformat(allocator, value, format_spec);
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
pub const str_factory = types_mod.str_factory;
pub const memoryview_callable = types_mod.memoryview_callable;
pub const compile = types_mod.compile;
pub const exec = types_mod.exec;
pub const structPackNoArgs = types_mod.structPackNoArgs;
pub const structPackIntoNoArgs = types_mod.structPackIntoNoArgs;
pub const filterNoArgs = types_mod.filterNoArgs;
pub const mapNoArgs = types_mod.mapNoArgs;
pub const CompareOp = types_mod.CompareOp;
pub const bigIntDivmod = types_mod.bigIntDivmod;
pub const bigIntCompare = types_mod.bigIntCompare;

/// Type constructor callables (list, tuple, dict, set, frozenset, deque, defaultdict, complex)
/// Note: int is NOT exported here to avoid conflict with issubclass(x, int)
pub const cons_mod = @import("builtins/constructors.zig");
pub const int_factory = cons_mod.int; // Factory for defaultdict(int), NOT the type
pub const list = cons_mod.list;
pub const tuple = cons_mod.tuple;
pub const dict = cons_mod.dict;
pub const set = cons_mod.set;
pub const frozenset = cons_mod.frozenset;
pub const deque = cons_mod.deque;
pub const defaultdict = cons_mod.defaultdict;

/// Complex number type constructor
pub const pycomplex_mod = @import("pycomplex.zig");
pub const complex = pycomplex_mod.PyComplex.create;

/// Python base 'object' class
/// All classes in Python inherit from object. This type is used in MRO comparisons.
/// Usage: D.__mro__ == (D, A, B, object)
pub const object = struct {
    pub const __name__: []const u8 = "object";
    pub const __doc__: ?[]const u8 = "The most base type";
    pub const __bases__: @TypeOf(.{}) = .{};
    pub const __bases_vtables__: ?[]const *const PyValue.PyObjectVTable = null;
    pub const __vtable__: PyValue.PyObjectVTable = PyValue.generateVTableForType(@This());
    pub const __mro__: @TypeOf(.{@This()}) = .{@This()};
};

/// Python staticmethod wrapper type
/// Used when `staticmethod` is passed as a first-class function
/// Wraps a function to indicate it's a static method (no self parameter)
pub const staticmethod = struct {
    /// The wrapped function pointer (type-erased for heterogeneous storage)
    __func__: *const anyopaque,
    __wrapped__: *const anyopaque,
    /// Function metadata (from wrapped function)
    __name__: []const u8 = "<function>",
    __module__: []const u8 = "__main__",
    __qualname__: []const u8 = "<function>",
    __doc__: ?[]const u8 = null,
    __annotations__: ?*const anyopaque = null,

    /// Create a staticmethod wrapper from any function
    /// Called as staticmethod(func) - no allocator needed
    pub fn init(func: anytype) @This() {
        return .{
            .__func__ = @ptrCast(&func),
            .__wrapped__ = @ptrCast(&func),
        };
    }

    /// Call the wrapped function (staticmethod is callable since Python 3.10)
    pub fn call(self: @This(), arg: anytype) @TypeOf(arg) {
        // For staticmethod, calling it directly just returns the argument
        // (the wrapped function behavior - bpo-43682)
        _ = self;
        return arg;
    }

    /// String representation for repr()
    pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("<staticmethod({s})>", .{self.__name__});
    }
};

/// Python classmethod wrapper type
/// Used when `classmethod` is passed as a first-class function
/// Wraps a function to indicate it's a class method (receives cls as first parameter)
pub const classmethod = struct {
    /// The wrapped function pointer (type-erased for heterogeneous storage)
    __func__: *const anyopaque,
    __wrapped__: *const anyopaque,
    /// Function metadata (from wrapped function)
    __name__: []const u8 = "<function>",
    __module__: []const u8 = "__main__",
    __qualname__: []const u8 = "<function>",
    __doc__: ?[]const u8 = null,
    __annotations__: ?*const anyopaque = null,

    /// Create a classmethod wrapper from any function
    /// Called as classmethod(func) - no allocator needed
    pub fn init(func: anytype) @This() {
        return .{
            .__func__ = @ptrCast(&func),
            .__wrapped__ = @ptrCast(&func),
        };
    }

    /// Calling classmethod directly raises TypeError (needs to be bound to class)
    /// Note: We use noreturn because classmethod always raises TypeError
    pub fn call(self: @This(), _: anytype) !noreturn {
        _ = self;
        return error.TypeError;
    }

    /// String representation for repr()
    pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("<classmethod({s})>", .{self.__name__});
    }
};

// =============================================================================
// Two-Flow List Operations (for uncertain list types)
// =============================================================================

/// Append item to a list (handles both ArrayList and PyValue.list)
/// Two-Flow: runtime helper for uncertain list types
pub fn pyListAppend(allocator: std.mem.Allocator, list_ptr: anytype, item: anytype) void {
    const T = @TypeOf(list_ptr.*);
    const info = @typeInfo(T);

    // Check if it's an ArrayList-like type with append method
    if (info == .@"struct" and @hasField(T, "items") and @hasDecl(T, "append")) {
        // ArrayList - use standard append
        list_ptr.append(allocator, item) catch unreachable;
    } else if (T == PyValue) {
        // PyValue.list is *ArrayListUnmanaged(PyValue) - can mutate via pointer
        if (list_ptr.* == .list) {
            list_ptr.list.append(allocator, PyValue.from(item)) catch unreachable;
        }
    }
}

/// Extend a list with items from another (handles both ArrayList and PyValue.list)
/// Two-Flow: runtime helper for uncertain list types
pub fn pyListExtend(allocator: std.mem.Allocator, list_ptr: anytype, other: anytype) void {
    const T = @TypeOf(list_ptr.*);
    const info = @typeInfo(T);

    // Check if it's an ArrayList-like type with appendSlice method
    if (info == .@"struct" and @hasField(T, "items") and @hasDecl(T, "appendSlice")) {
        const OtherT = @TypeOf(other);
        const other_info = @typeInfo(OtherT);

        if (other_info == .@"struct" and @hasField(OtherT, "items")) {
            list_ptr.appendSlice(allocator, other.items) catch unreachable;
        } else if (other_info == .pointer and other_info.pointer.size == .slice) {
            list_ptr.appendSlice(allocator, other) catch unreachable;
        }
    } else if (T == PyValue) {
        // PyValue.list is *ArrayListUnmanaged(PyValue) - can mutate via pointer
        if (list_ptr.* == .list) {
            const OtherT = @TypeOf(other);
            const other_info = @typeInfo(OtherT);
            if (OtherT == PyValue and other == .list) {
                list_ptr.list.appendSlice(allocator, other.list.items) catch unreachable;
            } else if (other_info == .pointer and other_info.pointer.size == .slice) {
                for (other) |item| {
                    list_ptr.list.append(allocator, PyValue.from(item)) catch unreachable;
                }
            }
        }
    }
}

/// Insert item at index in a list (handles both ArrayList and PyValue.list)
/// Two-Flow: runtime helper for uncertain list types
pub fn pyListInsert(allocator: std.mem.Allocator, list_ptr: anytype, index: anytype, item: anytype) void {
    const T = @TypeOf(list_ptr.*);
    const info = @typeInfo(T);

    // Check if it's an ArrayList-like type with insert method
    if (info == .@"struct" and @hasField(T, "items") and @hasDecl(T, "insert")) {
        const idx: usize = @intCast(index);
        list_ptr.insert(allocator, idx, item) catch unreachable;
    } else if (T == PyValue) {
        // PyValue.list is *ArrayListUnmanaged(PyValue) - can mutate via pointer
        if (list_ptr.* == .list) {
            const idx: usize = @intCast(index);
            list_ptr.list.insert(allocator, idx, PyValue.from(item)) catch unreachable;
        }
    }
}

// =============================================================================
// Dict Two-Flow Runtime Helpers
// =============================================================================

/// Get list of keys from a dict (handles both HashMap and PyValue.dict)
/// Two-Flow: runtime helper for uncertain dict types
pub fn pyDictKeys(allocator: std.mem.Allocator, d: anytype) std.ArrayListUnmanaged([]const u8) {
    var result_keys: std.ArrayListUnmanaged([]const u8) = .{};
    const T = @TypeOf(d);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "keys")) {
        // HashMap-like with keys() method
        for (d.keys()) |key| {
            result_keys.append(allocator, key) catch unreachable;
        }
    } else if (info == .@"struct" and @hasDecl(T, "iterator")) {
        // ArrayHashMap-like with iterator
        var dict_iter = d.iterator();
        while (dict_iter.next()) |entry| {
            result_keys.append(allocator, entry.key_ptr.*) catch unreachable;
        }
    } else if (T == PyValue) {
        // PyValue.dict - extract from ptr
        if (d == .ptr) {
            const hashmap_helper = @import("utils.hashmap_helper");
            const map_ptr: *hashmap_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(d.ptr));
            for (map_ptr.keys()) |key| {
                result_keys.append(allocator, key) catch unreachable;
            }
        }
    }
    return result_keys;
}

/// Get list of values from a dict (handles both HashMap and PyValue.dict)
/// Two-Flow: runtime helper for uncertain dict types
pub fn pyDictValues(allocator: std.mem.Allocator, d: anytype) std.ArrayListUnmanaged(PyValue) {
    var result_values: std.ArrayListUnmanaged(PyValue) = .{};
    const T = @TypeOf(d);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "values")) {
        // HashMap-like with values() method
        for (d.values()) |val| {
            result_values.append(allocator, PyValue.from(val)) catch unreachable;
        }
    } else if (info == .@"struct" and @hasDecl(T, "iterator")) {
        // ArrayHashMap-like with iterator
        var dict_iter = d.iterator();
        while (dict_iter.next()) |entry| {
            result_values.append(allocator, PyValue.from(entry.value_ptr.*)) catch unreachable;
        }
    } else if (T == PyValue) {
        // PyValue.dict - extract from ptr
        if (d == .ptr) {
            const hashmap_helper = @import("utils.hashmap_helper");
            const map_ptr: *hashmap_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(d.ptr));
            for (map_ptr.values()) |val| {
                result_values.append(allocator, val) catch unreachable;
            }
        }
    }
    return result_values;
}

/// Get list of (key, value) tuples from a dict (handles both HashMap and PyValue.dict)
/// Two-Flow: runtime helper for uncertain dict types
pub fn pyDictItems(allocator: std.mem.Allocator, d: anytype) std.ArrayListUnmanaged(std.meta.Tuple(&[_]type{ []const u8, PyValue })) {
    var result_items: std.ArrayListUnmanaged(std.meta.Tuple(&[_]type{ []const u8, PyValue })) = .{};
    const T = @TypeOf(d);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "iterator")) {
        // HashMap-like with iterator
        var dict_iter = d.iterator();
        while (dict_iter.next()) |entry| {
            result_items.append(allocator, .{ entry.key_ptr.*, PyValue.from(entry.value_ptr.*) }) catch unreachable;
        }
    } else if (T == PyValue) {
        // PyValue.dict - extract from ptr
        if (d == .ptr) {
            const hashmap_helper = @import("utils.hashmap_helper");
            const map_ptr: *hashmap_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(d.ptr));
            var map_iter = map_ptr.iterator();
            while (map_iter.next()) |entry| {
                result_items.append(allocator, .{ entry.key_ptr.*, entry.value_ptr.* }) catch unreachable;
            }
        }
    }
    return result_items;
}

/// List.extend() helper for custom iterables with __iter__ method
/// Handles extending ArrayListUnmanaged with items from any iterable
pub fn listExtendIterable(allocator: std.mem.Allocator, arr_list: anytype, iterable: anytype) !void {
    const IterType = @TypeOf(iterable);

    // Check if iterable has __iter__ method (custom Python class)
    if (@hasDecl(IterType, "__iter__")) {
        // Call __iter__ to get iterator result
        // Handle both error-returning and non-error-returning __iter__ methods
        const iter_result = blk: {
            const iter_fn_info = @typeInfo(@TypeOf(IterType.__iter__));
            const return_type = iter_fn_info.@"fn".return_type.?;
            if (@typeInfo(return_type) == .error_union) {
                break :blk try iterable.__iter__();
            } else {
                break :blk iterable.__iter__();
            }
        };
        const IterResultType = @TypeOf(iter_result);

        // Check if result is a slice
        const result_info = @typeInfo(IterResultType);
        if (result_info == .pointer and result_info.pointer.size == .slice) {
            // It's a slice - use appendSlice
            try arr_list.appendSlice(allocator, iter_result);
        } else {
            // Try to iterate it
            for (iter_result) |item| {
                try arr_list.append(allocator, item);
            }
        }
    } else if (@hasField(IterType, "items")) {
        // Has .items field (ArrayList-like)
        try arr_list.appendSlice(allocator, iterable.items);
    } else {
        // Try direct iteration (slice, array, tuple)
        for (iterable) |item| {
            try arr_list.append(allocator, item);
        }
    }
}

/// Pop a key from dict and return its value (handles both HashMap and PyValue.dict)
/// Two-Flow: runtime helper for uncertain dict types
pub fn pyDictPop(allocator: std.mem.Allocator, dict_ptr: anytype, key: []const u8) ?PyValue {
    _ = allocator;
    const T = @TypeOf(dict_ptr.*);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "fetchSwapRemove")) {
        // ArrayHashMap-like with fetchSwapRemove
        if (dict_ptr.fetchSwapRemove(key)) |kv| {
            return PyValue.from(kv.value);
        }
    } else if (T == PyValue) {
        // PyValue.dict - extract from ptr
        if (dict_ptr.* == .ptr) {
            const hashmap_helper = @import("utils.hashmap_helper");
            const map_ptr: *hashmap_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(dict_ptr.ptr));
            if (map_ptr.fetchSwapRemove(key)) |kv| {
                return kv.value;
            }
        }
    }
    return null;
}

/// Update dict with entries from another dict (handles both HashMap and PyValue.dict)
/// Two-Flow: runtime helper for uncertain dict types
pub fn pyDictUpdate(allocator: std.mem.Allocator, dict_ptr: anytype, other: anytype) void {
    _ = allocator;
    const T = @TypeOf(dict_ptr.*);
    const OtherT = @TypeOf(other);
    const info = @typeInfo(T);
    const other_info = @typeInfo(OtherT);

    if (info == .@"struct" and @hasDecl(T, "put")) {
        if (other_info == .@"struct" and @hasDecl(OtherT, "iterator")) {
            var other_iter = other.iterator();
            while (other_iter.next()) |entry| {
                dict_ptr.put(entry.key_ptr.*, entry.value_ptr.*) catch unreachable;
            }
        }
    }
}

/// Clear all entries from dict (handles both HashMap and PyValue.dict)
/// Two-Flow: runtime helper for uncertain dict types
pub fn pyDictClear(dict_ptr: anytype) void {
    const T = @TypeOf(dict_ptr.*);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "clearRetainingCapacity")) {
        dict_ptr.clearRetainingCapacity();
    } else if (T == PyValue) {
        if (dict_ptr.* == .ptr) {
            const hashmap_helper = @import("utils.hashmap_helper");
            const map_ptr: *hashmap_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(dict_ptr.ptr));
            map_ptr.clearRetainingCapacity();
        }
    }
}

/// Create shallow copy of dict (handles both HashMap and PyValue.dict)
/// Two-Flow: runtime helper for uncertain dict types
pub fn pyDictCopy(allocator: std.mem.Allocator, d: anytype) @TypeOf(d) {
    const T = @TypeOf(d);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "init") and @hasDecl(T, "put") and @hasDecl(T, "iterator")) {
        var copy = T.init(allocator);
        var dict_iter = d.iterator();
        while (dict_iter.next()) |entry| {
            copy.put(entry.key_ptr.*, entry.value_ptr.*) catch unreachable;
        }
        return copy;
    }
    // Fallback: return original (can't copy unknown type)
    return d;
}

/// Set default value for key if not present, return current value
/// Two-Flow: runtime helper for uncertain dict types
pub fn pyDictSetdefault(allocator: std.mem.Allocator, dict_ptr: anytype, key: []const u8, default: anytype) PyValue {
    _ = allocator;
    const T = @TypeOf(dict_ptr.*);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "get") and @hasDecl(T, "put")) {
        if (dict_ptr.get(key)) |v| {
            return PyValue.from(v);
        }
        const def_val = PyValue.from(default);
        dict_ptr.put(key, def_val) catch unreachable;
        return def_val;
    }
    return PyValue.from(default);
}

/// Pop arbitrary item from dict and return (key, value) tuple
/// Two-Flow: runtime helper for uncertain dict types
pub fn pyDictPopitem(allocator: std.mem.Allocator, dict_ptr: anytype) !std.meta.Tuple(&[_]type{ []const u8, PyValue }) {
    _ = allocator;
    const T = @TypeOf(dict_ptr.*);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "iterator") and @hasDecl(T, "fetchSwapRemove")) {
        var dict_iter = dict_ptr.iterator();
        if (dict_iter.next()) |entry| {
            const pop_key = entry.key_ptr.*;
            const pop_val = PyValue.from(entry.value_ptr.*);
            _ = dict_ptr.fetchSwapRemove(pop_key);
            return .{ pop_key, pop_val };
        }
    }
    return error.KeyError;
}

// =============================================================================
// Set Two-Flow Runtime Helpers
// =============================================================================

/// Add element to a set (handles both HashMap and PyValue.set)
/// Two-Flow: runtime helper for uncertain set types
pub fn pySetAdd(allocator: std.mem.Allocator, set_ptr: anytype, elem: anytype) void {
    const T = @TypeOf(set_ptr.*);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "put")) {
        // HashMap-like with put() method
        set_ptr.put(elem, {}) catch unreachable;
    } else if (T == PyValue) {
        // PyValue.set - extract from ptr
        if (set_ptr.* == .ptr) {
            const hashmap_helper = @import("utils.hashmap_helper");
            const map_ptr: *hashmap_helper.StringHashMap(void) = @ptrCast(@alignCast(set_ptr.ptr));
            map_ptr.put(elem, {}) catch unreachable;
        }
    }
    _ = allocator;
}

/// Remove element from set, raises KeyError if not present
/// Two-Flow: runtime helper for uncertain set types
pub fn pySetRemove(allocator: std.mem.Allocator, set_ptr: anytype, elem: anytype) !void {
    _ = allocator;
    const T = @TypeOf(set_ptr.*);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "swapRemove")) {
        // ArrayHashMap-like with swapRemove
        if (!set_ptr.swapRemove(elem)) {
            return error.KeyError;
        }
    } else if (info == .@"struct" and @hasDecl(T, "remove")) {
        // AutoHashMap-like with remove
        if (!set_ptr.remove(elem)) {
            return error.KeyError;
        }
    } else if (T == PyValue) {
        if (set_ptr.* == .ptr) {
            const hashmap_helper = @import("utils.hashmap_helper");
            const map_ptr: *hashmap_helper.StringHashMap(void) = @ptrCast(@alignCast(set_ptr.ptr));
            if (!map_ptr.swapRemove(elem)) {
                return error.KeyError;
            }
        }
    }
}

/// Remove element from set if present (no error if missing)
/// Two-Flow: runtime helper for uncertain set types
pub fn pySetDiscard(allocator: std.mem.Allocator, set_ptr: anytype, elem: anytype) void {
    _ = allocator;
    const T = @TypeOf(set_ptr.*);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "swapRemove")) {
        // ArrayHashMap-like with swapRemove
        _ = set_ptr.swapRemove(elem);
    } else if (info == .@"struct" and @hasDecl(T, "remove")) {
        // AutoHashMap-like with remove
        _ = set_ptr.remove(elem);
    } else if (T == PyValue) {
        if (set_ptr.* == .ptr) {
            const hashmap_helper = @import("utils.hashmap_helper");
            const map_ptr: *hashmap_helper.StringHashMap(void) = @ptrCast(@alignCast(set_ptr.ptr));
            _ = map_ptr.swapRemove(elem);
        }
    }
}

/// Clear all elements from set
/// Two-Flow: runtime helper for uncertain set types
pub fn pySetClear(set_ptr: anytype) void {
    const T = @TypeOf(set_ptr.*);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "clearRetainingCapacity")) {
        set_ptr.clearRetainingCapacity();
    } else if (T == PyValue) {
        if (set_ptr.* == .ptr) {
            const hashmap_helper = @import("utils.hashmap_helper");
            const map_ptr: *hashmap_helper.StringHashMap(void) = @ptrCast(@alignCast(set_ptr.ptr));
            map_ptr.clearRetainingCapacity();
        }
    }
}

/// Pop arbitrary element from set, raises KeyError if empty
/// Two-Flow: runtime helper for uncertain set types
pub fn pySetPop(allocator: std.mem.Allocator, set_ptr: anytype) !PyValue {
    _ = allocator;
    const T = @TypeOf(set_ptr.*);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "iterator") and @hasDecl(T, "swapRemove")) {
        var set_iter = set_ptr.iterator();
        if (set_iter.next()) |entry| {
            const elem = entry.key_ptr.*;
            _ = set_ptr.swapRemove(elem);
            return PyValue.from(elem);
        }
    } else if (info == .@"struct" and @hasDecl(T, "iterator") and @hasDecl(T, "remove")) {
        var set_iter = set_ptr.iterator();
        if (set_iter.next()) |entry| {
            const elem = entry.key_ptr.*;
            _ = set_ptr.remove(elem);
            return PyValue.from(elem);
        }
    } else if (T == PyValue) {
        if (set_ptr.* == .ptr) {
            const hashmap_helper = @import("utils.hashmap_helper");
            const map_ptr: *hashmap_helper.StringHashMap(void) = @ptrCast(@alignCast(set_ptr.ptr));
            var map_iter = map_ptr.iterator();
            if (map_iter.next()) |entry| {
                const elem = entry.key_ptr.*;
                _ = map_ptr.swapRemove(elem);
                return .{ .string = elem };
            }
        }
    }
    return error.KeyError;
}

// =============================================================================
// PyValue-First List Operations (compile ONCE - no monomorphization)
// These replace anytype versions for uncertain types to prevent compile explosion
// =============================================================================

/// Append item to PyValue list - compiles ONCE
pub fn pyListAppendPV(allocator: std.mem.Allocator, py_list: *PyValue, item: PyValue) !void {
    switch (py_list.*) {
        .list => |al| try al.append(allocator, item),
        else => return error.TypeError,
    }
}

/// Extend PyValue list with items from another PyValue - compiles ONCE
pub fn pyListExtendPV(allocator: std.mem.Allocator, py_list: *PyValue, items: PyValue) !void {
    switch (py_list.*) {
        .list => |al| {
            switch (items) {
                .list => |other_al| try al.appendSlice(allocator, other_al.items),
                .tuple => |tup| try al.appendSlice(allocator, tup),
                else => return error.TypeError,
            }
        },
        else => return error.TypeError,
    }
}

/// Insert item at index in PyValue list - compiles ONCE
pub fn pyListInsertPV(allocator: std.mem.Allocator, py_list: *PyValue, index: i64, item: PyValue) !void {
    switch (py_list.*) {
        .list => |al| {
            const list_len = al.items.len;
            // Python semantics: negative index counts from end, clamp to bounds
            const idx: usize = if (index < 0)
                @intCast(@max(0, @as(i64, @intCast(list_len)) + index))
            else
                @min(@as(usize, @intCast(index)), list_len);
            try al.insert(allocator, idx, item);
        },
        else => return error.TypeError,
    }
}

/// Pop item from PyValue list at index (default -1) - compiles ONCE
pub fn pyListPopPV(py_list: *PyValue, index: ?i64) !PyValue {
    switch (py_list.*) {
        .list => |al| {
            const list_len = al.items.len;
            if (list_len == 0) return error.IndexError;

            const idx_raw = index orelse -1;
            // Python semantics: negative index counts from end
            const idx: usize = if (idx_raw < 0)
                @intCast(@as(i64, @intCast(list_len)) + idx_raw)
            else
                @intCast(idx_raw);

            if (idx >= list_len) return error.IndexError;
            return al.orderedRemove(idx);
        },
        else => return error.TypeError,
    }
}

/// Remove first occurrence of item from PyValue list - compiles ONCE
pub fn pyListRemovePV(py_list: *PyValue, item: PyValue) !void {
    const equality = @import("equality.zig");
    switch (py_list.*) {
        .list => |al| {
            for (al.items, 0..) |elem, i| {
                if (equality.pyValueEql(elem, item)) {
                    _ = al.orderedRemove(i);
                    return;
                }
            }
            return error.ValueError;
        },
        else => return error.TypeError,
    }
}

/// Clear PyValue list - compiles ONCE
pub fn pyListClearPV(py_list: *PyValue) void {
    switch (py_list.*) {
        .list => |al| al.clearRetainingCapacity(),
        else => {},
    }
}

/// Reverse PyValue list in place - compiles ONCE
pub fn pyListReversePV(py_list: *PyValue) void {
    switch (py_list.*) {
        .list => |al| std.mem.reverse(PyValue, al.items),
        else => {},
    }
}

/// Sort PyValue list in place - compiles ONCE
pub fn pyListSortPV(py_list: *PyValue) !void {
    const equality = @import("equality.zig");
    switch (py_list.*) {
        .list => |al| {
            std.mem.sort(PyValue, al.items, {}, struct {
                fn lessThan(_: void, a: PyValue, b: PyValue) bool {
                    return equality.pyValueLt(a, b);
                }
            }.lessThan);
        },
        else => return error.TypeError,
    }
}

/// Get length of PyValue container - compiles ONCE
pub fn pyLenPV(value: PyValue) !usize {
    return switch (value) {
        .list => |al| al.items.len,
        .tuple => |t| t.len,
        .string => |s| s.len,
        .bytes => |b| b.data.len,
        else => error.TypeError,
    };
}

/// Check if item is in PyValue container - compiles ONCE
pub fn pyContainsPV(container: PyValue, item: PyValue) bool {
    const equality = @import("equality.zig");
    return switch (container) {
        .list => |al| {
            for (al.items) |elem| {
                if (equality.pyValueEql(elem, item)) return true;
            }
            return false;
        },
        .tuple => |tup| {
            for (tup) |elem| {
                if (equality.pyValueEql(elem, item)) return true;
            }
            return false;
        },
        .string => |s| blk: {
            if (item != .string) break :blk false;
            break :blk std.mem.indexOf(u8, s, item.string) != null;
        },
        else => false,
    };
}

/// Get item at index from PyValue container - compiles ONCE
pub fn pyGetItemPV(container: PyValue, index: i64) !PyValue {
    return switch (container) {
        .list => |al| {
            const list_len = al.items.len;
            if (list_len == 0) return error.IndexError;
            const idx: usize = if (index < 0)
                @intCast(@as(i64, @intCast(list_len)) + index)
            else
                @intCast(index);
            if (idx >= list_len) return error.IndexError;
            return al.items[idx];
        },
        .tuple => |tup| {
            const tup_len = tup.len;
            if (tup_len == 0) return error.IndexError;
            const idx: usize = if (index < 0)
                @intCast(@as(i64, @intCast(tup_len)) + index)
            else
                @intCast(index);
            if (idx >= tup_len) return error.IndexError;
            return tup[idx];
        },
        else => error.TypeError,
    };
}

/// Set item at index in PyValue container - compiles ONCE
pub fn pySetItemPV(container: *PyValue, index: i64, value: PyValue) !void {
    switch (container.*) {
        .list => |al| {
            const list_len = al.items.len;
            if (list_len == 0) return error.IndexError;
            const idx: usize = if (index < 0)
                @intCast(@as(i64, @intCast(list_len)) + index)
            else
                @intCast(index);
            if (idx >= list_len) return error.IndexError;
            al.items[idx] = value;
        },
        else => return error.TypeError,
    }
}

// =============================================================================
// PyValue-First Dict Operations (compile ONCE - no monomorphization)
// Note: PyValue dicts are stored as .ptr -> *StringHashMap(PyValue)
// =============================================================================

const hm_helper = @import("utils.hashmap_helper");

/// Get value from PyValue dict by key - compiles ONCE
pub fn pyDictGetPV(py_dict: PyValue, key: []const u8) ?PyValue {
    if (py_dict != .ptr) return null;
    const map_ptr: *hm_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(py_dict.ptr));
    return map_ptr.get(key);
}

/// Set value in PyValue dict - compiles ONCE
pub fn pyDictSetPV(allocator: std.mem.Allocator, py_dict: *PyValue, key: []const u8, value: PyValue) !void {
    if (py_dict.* != .ptr) return error.TypeError;
    const map_ptr: *hm_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(py_dict.ptr));
    try map_ptr.put(allocator, key, value);
}

/// Pop and return value from PyValue dict - compiles ONCE
pub fn pyDictPopPV(py_dict: *PyValue, key: []const u8) ?PyValue {
    if (py_dict.* != .ptr) return null;
    const map_ptr: *hm_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(py_dict.ptr));
    if (map_ptr.fetchSwapRemove(key)) |kv| {
        return kv.value;
    }
    return null;
}

/// Update PyValue dict with another dict - compiles ONCE
pub fn pyDictUpdatePV(allocator: std.mem.Allocator, py_dict: *PyValue, other: PyValue) !void {
    if (py_dict.* != .ptr or other != .ptr) return error.TypeError;
    const map_ptr: *hm_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(py_dict.ptr));
    const other_ptr: *hm_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(other.ptr));
    var it = other_ptr.iterator();
    while (it.next()) |entry| {
        try map_ptr.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
    }
}

/// Get keys from PyValue dict as list - compiles ONCE
pub fn pyDictKeysPV(allocator: std.mem.Allocator, py_dict: PyValue) !PyValue {
    if (py_dict != .ptr) return error.TypeError;
    const map_ptr: *hm_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(py_dict.ptr));
    const al = try allocator.create(std.ArrayListUnmanaged(PyValue));
    al.* = .{};
    for (map_ptr.keys()) |key| {
        try al.append(allocator, .{ .string = key });
    }
    return .{ .list = al };
}

/// Get values from PyValue dict as list - compiles ONCE
pub fn pyDictValuesPV(allocator: std.mem.Allocator, py_dict: PyValue) !PyValue {
    if (py_dict != .ptr) return error.TypeError;
    const map_ptr: *hm_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(py_dict.ptr));
    const al = try allocator.create(std.ArrayListUnmanaged(PyValue));
    al.* = .{};
    for (map_ptr.values()) |val| {
        try al.append(allocator, val);
    }
    return .{ .list = al };
}

/// Get items from PyValue dict as list of tuples - compiles ONCE
pub fn pyDictItemsPV(allocator: std.mem.Allocator, py_dict: PyValue) !PyValue {
    if (py_dict != .ptr) return error.TypeError;
    const map_ptr: *hm_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(py_dict.ptr));
    const al = try allocator.create(std.ArrayListUnmanaged(PyValue));
    al.* = .{};
    var it = map_ptr.iterator();
    while (it.next()) |entry| {
        const pair = try allocator.alloc(PyValue, 2);
        pair[0] = .{ .string = entry.key_ptr.* };
        pair[1] = entry.value_ptr.*;
        try al.append(allocator, .{ .tuple = pair });
    }
    return .{ .list = al };
}

/// Clear PyValue dict - compiles ONCE
pub fn pyDictClearPV(py_dict: *PyValue) void {
    if (py_dict.* != .ptr) return;
    const map_ptr: *hm_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(py_dict.ptr));
    map_ptr.clearRetainingCapacity();
}

/// Check if key is in PyValue dict - compiles ONCE
pub fn pyDictContainsPV(py_dict: PyValue, key: []const u8) bool {
    if (py_dict != .ptr) return false;
    const map_ptr: *hm_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(py_dict.ptr));
    return map_ptr.contains(key);
}

// =============================================================================
// PyValue-First Set Operations (compile ONCE - no monomorphization)
// Note: PyValue sets are stored as .ptr -> *StringHashMap(void)
// =============================================================================

/// Add item to PyValue set - compiles ONCE
pub fn pySetAddPV(allocator: std.mem.Allocator, py_set: *PyValue, item: PyValue) !void {
    if (py_set.* != .ptr) return error.TypeError;
    const map_ptr: *hm_helper.StringHashMap(void) = @ptrCast(@alignCast(py_set.ptr));
    const key = switch (item) {
        .string => |s| s,
        .int => |i| blk: {
            // Convert int to string key
            var buf: [32]u8 = undefined;
            const str_len = std.fmt.formatIntBuf(&buf, i, 10, .lower, .{});
            const key_copy = try allocator.alloc(u8, str_len);
            @memcpy(key_copy, buf[0..str_len]);
            break :blk key_copy;
        },
        else => return error.TypeError,
    };
    try map_ptr.put(allocator, key, {});
}

/// Remove item from PyValue set (raises KeyError if not found) - compiles ONCE
pub fn pySetRemovePV(py_set: *PyValue, item: PyValue) !void {
    if (py_set.* != .ptr) return error.TypeError;
    const map_ptr: *hm_helper.StringHashMap(void) = @ptrCast(@alignCast(py_set.ptr));
    const key = switch (item) {
        .string => |s| s,
        else => return error.TypeError,
    };
    if (!map_ptr.swapRemove(key)) {
        return error.KeyError;
    }
}

/// Discard item from PyValue set (no error if not found) - compiles ONCE
pub fn pySetDiscardPV(py_set: *PyValue, item: PyValue) void {
    if (py_set.* != .ptr) return;
    const map_ptr: *hm_helper.StringHashMap(void) = @ptrCast(@alignCast(py_set.ptr));
    const key = switch (item) {
        .string => |s| s,
        else => return,
    };
    _ = map_ptr.swapRemove(key);
}

/// Pop arbitrary item from PyValue set - compiles ONCE
pub fn pySetPopPVFunc(py_set: *PyValue) !PyValue {
    if (py_set.* != .ptr) return error.TypeError;
    const map_ptr: *hm_helper.StringHashMap(void) = @ptrCast(@alignCast(py_set.ptr));
    var it = map_ptr.iterator();
    if (it.next()) |entry| {
        const key = entry.key_ptr.*;
        _ = map_ptr.swapRemove(key);
        return .{ .string = key };
    }
    return error.KeyError;
}

/// Clear PyValue set - compiles ONCE
pub fn pySetClearPV(py_set: *PyValue) void {
    if (py_set.* != .ptr) return;
    const map_ptr: *hm_helper.StringHashMap(void) = @ptrCast(@alignCast(py_set.ptr));
    map_ptr.clearRetainingCapacity();
}

/// Check if item is in PyValue set - compiles ONCE
pub fn pySetContainsPV(py_set: PyValue, item: PyValue) bool {
    if (py_set != .ptr) return false;
    const map_ptr: *hm_helper.StringHashMap(void) = @ptrCast(@alignCast(py_set.ptr));
    const key = switch (item) {
        .string => |s| s,
        else => return false,
    };
    return map_ptr.contains(key);
}

// =============================================================================
// Type Conversion Helper - for type(x) where type is a Zig type passed as anytype
// =============================================================================

/// Convert a value to a target type at comptime.
/// This is used for patterns like `type(i)` where `type` is an anytype parameter
/// holding a Zig type like i64 or f64.
///
/// Example: typeConvert(i64, 3.5) -> 3
/// Example: typeConvert(f64, 42) -> 42.0
pub fn typeConvert(comptime T: type, value: anytype) T {
    const V = @TypeOf(value);

    // Same type - return as-is
    if (T == V) return value;

    const t_info = @typeInfo(T);
    const v_info = @typeInfo(V);

    // Target is integer
    if (t_info == .int) {
        if (type_predicates.isIntInfo(v_info)) {
            return @intCast(value);
        }
        if (type_predicates.isFloatInfo(v_info)) {
            return @intFromFloat(value);
        }
    }

    // Target is float
    if (t_info == .float) {
        if (type_predicates.isIntInfo(v_info)) {
            return @floatFromInt(value);
        }
        if (type_predicates.isFloatInfo(v_info)) {
            return @floatCast(value);
        }
    }

    @compileError("typeConvert: cannot convert " ++ @typeName(V) ++ " to " ++ @typeName(T));
}

/// Like typeConvert but always returns f64.
/// Used for pow() and other math operations that require float arguments.
///
/// Example: typeConvertFloat(i64, 42) -> 42.0
/// Example: typeConvertFloat(f64, 42) -> 42.0
pub fn typeConvertFloat(comptime T: type, value: anytype) f64 {
    const converted = typeConvert(T, value);
    const info = @typeInfo(@TypeOf(converted));
    if (info == .float) return @floatCast(converted);
    if (info == .int) return @floatFromInt(converted);
    @compileError("typeConvertFloat: result is not numeric");
}

/// Convert any numeric value to f64.
/// Handles i64, f64, and other numeric types uniformly.
/// Used when a variable of unknown numeric type needs to be used as f64.
///
/// Example: numericToFloat(42_i64) -> 42.0
/// Example: numericToFloat(3.14_f64) -> 3.14
pub fn numericToFloat(value: anytype) f64 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);
    if (info == .float) return @floatCast(value);
    if (type_predicates.isIntInfo(info)) return @floatFromInt(value);
    if (info == .comptime_float) return @floatCast(value);
    @compileError("numericToFloat: expected numeric type, got " ++ @typeName(T));
}
