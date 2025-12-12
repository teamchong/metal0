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

/// Python pow() builtin as a callable struct (for `for pow_op in pow, operator.pow:`)
/// This allows pow to be used identically to operator.pow with .call() syntax
/// Returns error union for compatibility with codegen that emits `try`
/// Note: static call function (no @This() param) for use as type, not instance
pub const pow = struct {
    pub fn call(base: anytype, exp: @TypeOf(base)) !@TypeOf(base) {
        const T = @TypeOf(base);
        if (@typeInfo(T) == .float) {
            // Python raises ZeroDivisionError for 0.0 ** negative
            if (base == 0.0 and exp < 0.0) {
                return error.ZeroDivisionError;
            }
            return std.math.pow(T, base, exp);
        }
        // For integers, use std.math.pow with conversion
        const base_f: f64 = @floatFromInt(base);
        const exp_f: f64 = @floatFromInt(exp);
        const result = std.math.pow(f64, base_f, exp_f);
        return @intFromFloat(result);
    }
};

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
    const float_ops = @import("float_ops/arithmetic.zig");

    pub fn call(_: @This(), a: anytype, b: @TypeOf(a)) @TypeOf(a) {
        const T = @TypeOf(a);
        if (@typeInfo(T) == .float) {
            // Use proper Python floored modulo semantics
            return @floatCast(float_ops.pyFloatMod(a, b));
        }
        return @mod(a, b);
    }
};

pub const OperatorPow = struct {
    /// Returns error union for compatibility with `pow` in tuple iteration
    pub fn call(_: @This(), base: anytype, exp: @TypeOf(base)) !@TypeOf(base) {
        const T = @TypeOf(base);
        if (@typeInfo(T) == .float) {
            // Python raises ZeroDivisionError for 0.0 ** negative
            if (base == 0.0 and exp < 0.0) {
                return error.ZeroDivisionError;
            }
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
const PyValue = @import("../Objects/object.zig").PyValue;

/// Append item to a list (handles both ArrayList and PyValue.list)
/// Two-Flow: runtime helper for uncertain list types
pub fn pyListAppend(allocator: std.mem.Allocator, list_ptr: anytype, item: anytype) void {
    const T = @TypeOf(list_ptr.*);
    const info = @typeInfo(T);

    // Check if it's an ArrayList-like type with append method
    if (info == .@"struct" and @hasField(T, "items") and @hasDecl(T, "append")) {
        // ArrayList - use standard append
        list_ptr.append(allocator, item) catch {};
    } else if (T == PyValue) {
        // PyValue.list is *ArrayListUnmanaged(PyValue) - can mutate via pointer
        if (list_ptr.* == .list) {
            list_ptr.list.append(allocator, PyValue.from(item)) catch {};
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
            list_ptr.appendSlice(allocator, other.items) catch {};
        } else if (other_info == .pointer and other_info.pointer.size == .Slice) {
            list_ptr.appendSlice(allocator, other) catch {};
        }
    } else if (T == PyValue) {
        // PyValue.list is *ArrayListUnmanaged(PyValue) - can mutate via pointer
        if (list_ptr.* == .list) {
            const OtherT = @TypeOf(other);
            const other_info = @typeInfo(OtherT);
            if (OtherT == PyValue and other == .list) {
                list_ptr.list.appendSlice(allocator, other.list.items) catch {};
            } else if (other_info == .pointer and other_info.pointer.size == .Slice) {
                for (other) |item| {
                    list_ptr.list.append(allocator, PyValue.from(item)) catch {};
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
        list_ptr.insert(allocator, idx, item) catch {};
    } else if (T == PyValue) {
        // PyValue.list is *ArrayListUnmanaged(PyValue) - can mutate via pointer
        if (list_ptr.* == .list) {
            const idx: usize = @intCast(index);
            list_ptr.list.insert(allocator, idx, PyValue.from(item)) catch {};
        }
    }
}

// =============================================================================
// Dict Two-Flow Runtime Helpers
// =============================================================================

/// Get list of keys from a dict (handles both HashMap and PyValue.dict)
/// Two-Flow: runtime helper for uncertain dict types
pub fn pyDictKeys(allocator: std.mem.Allocator, dict: anytype) std.ArrayListUnmanaged([]const u8) {
    var keys: std.ArrayListUnmanaged([]const u8) = .{};
    const T = @TypeOf(dict);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "keys")) {
        // HashMap-like with keys() method
        for (dict.keys()) |key| {
            keys.append(allocator, key) catch {};
        }
    } else if (info == .@"struct" and @hasDecl(T, "iterator")) {
        // ArrayHashMap-like with iterator
        var dict_iter = dict.iterator();
        while (dict_iter.next()) |entry| {
            keys.append(allocator, entry.key_ptr.*) catch {};
        }
    } else if (T == PyValue) {
        // PyValue.dict - extract from ptr
        if (dict == .ptr) {
            const hashmap_helper = @import("utils.hashmap_helper");
            const map_ptr: *hashmap_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(dict.ptr));
            for (map_ptr.keys()) |key| {
                keys.append(allocator, key) catch {};
            }
        }
    }
    return keys;
}

/// Get list of values from a dict (handles both HashMap and PyValue.dict)
/// Two-Flow: runtime helper for uncertain dict types
pub fn pyDictValues(allocator: std.mem.Allocator, dict: anytype) std.ArrayListUnmanaged(PyValue) {
    var values: std.ArrayListUnmanaged(PyValue) = .{};
    const T = @TypeOf(dict);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "values")) {
        // HashMap-like with values() method
        for (dict.values()) |val| {
            values.append(allocator, PyValue.from(val)) catch {};
        }
    } else if (info == .@"struct" and @hasDecl(T, "iterator")) {
        // ArrayHashMap-like with iterator
        var dict_iter = dict.iterator();
        while (dict_iter.next()) |entry| {
            values.append(allocator, PyValue.from(entry.value_ptr.*)) catch {};
        }
    } else if (T == PyValue) {
        // PyValue.dict - extract from ptr
        if (dict == .ptr) {
            const hashmap_helper = @import("utils.hashmap_helper");
            const map_ptr: *hashmap_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(dict.ptr));
            for (map_ptr.values()) |val| {
                values.append(allocator, val) catch {};
            }
        }
    }
    return values;
}

/// Get list of (key, value) tuples from a dict (handles both HashMap and PyValue.dict)
/// Two-Flow: runtime helper for uncertain dict types
pub fn pyDictItems(allocator: std.mem.Allocator, dict: anytype) std.ArrayListUnmanaged(std.meta.Tuple(&[_]type{ []const u8, PyValue })) {
    var items: std.ArrayListUnmanaged(std.meta.Tuple(&[_]type{ []const u8, PyValue })) = .{};
    const T = @TypeOf(dict);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "iterator")) {
        // HashMap-like with iterator
        var dict_iter = dict.iterator();
        while (dict_iter.next()) |entry| {
            items.append(allocator, .{ entry.key_ptr.*, PyValue.from(entry.value_ptr.*) }) catch {};
        }
    } else if (T == PyValue) {
        // PyValue.dict - extract from ptr
        if (dict == .ptr) {
            const hashmap_helper = @import("utils.hashmap_helper");
            const map_ptr: *hashmap_helper.StringHashMap(PyValue) = @ptrCast(@alignCast(dict.ptr));
            var map_iter = map_ptr.iterator();
            while (map_iter.next()) |entry| {
                items.append(allocator, .{ entry.key_ptr.*, entry.value_ptr.* }) catch {};
            }
        }
    }
    return items;
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
                dict_ptr.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
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
pub fn pyDictCopy(allocator: std.mem.Allocator, dict: anytype) @TypeOf(dict) {
    const T = @TypeOf(dict);
    const info = @typeInfo(T);

    if (info == .@"struct" and @hasDecl(T, "init") and @hasDecl(T, "put") and @hasDecl(T, "iterator")) {
        var copy = T.init(allocator);
        var dict_iter = dict.iterator();
        while (dict_iter.next()) |entry| {
            copy.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
        }
        return copy;
    }
    // Fallback: return original (can't copy unknown type)
    return dict;
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
        dict_ptr.put(key, def_val) catch {};
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
        set_ptr.put(elem, {}) catch {};
    } else if (T == PyValue) {
        // PyValue.set - extract from ptr
        if (set_ptr.* == .ptr) {
            const hashmap_helper = @import("utils.hashmap_helper");
            const map_ptr: *hashmap_helper.StringHashMap(void) = @ptrCast(@alignCast(set_ptr.ptr));
            map_ptr.put(elem, {}) catch {};
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
