/// Built-in Python functions implemented in Zig
/// This module re-exports from specialized submodules for better organization.
const std = @import("std");
const runtime_core = @import("../runtime.zig");
const pyint = @import("../Objects/intobject.zig");
const pylist = @import("../Objects/listobject.zig");
const pystring = @import("../Objects/unicodeobject.zig");
const pytuple = @import("../Objects/tupleobject.zig");
const dict_module = @import("../Objects/dictobject.zig");
const pycomplex = @import("../Objects/complexobject.zig");
const pyset = @import("../Objects/setobject.zig");
const pydeque = @import("../Objects/dequeobject.zig");
const BigInt = @import("bigint").BigInt;

const PyObject = runtime_core.PyObject;
const PythonError = runtime_core.PythonError;
const PyInt = pyint.PyInt;
const PyList = pylist.PyList;
const PyString = pystring.PyString;
const PyTuple = pytuple.PyTuple;
const PyDict = dict_module.PyDict;
const PyComplex = pycomplex.PyComplex;
const PySet = pyset.PySet;
const PyDeque = pydeque.PyDeque;
const incref = runtime_core.incref;
const decref = runtime_core.decref;

// =============================================================================
// Re-exports from submodules
// =============================================================================

/// Power function (pow)
pub const pow_mod = @import("builtins/pow.zig");
pub const PyPowResult = pow_mod.PyPowResult;
pub const pyPow = pow_mod.pyPow;

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

// =============================================================================
// Functions that remain in this file (tightly coupled or complex dependencies)
// =============================================================================

/// callable() builtin - returns true if object is callable
pub fn callable(obj: anytype) bool {
    const T = @TypeOf(obj);
    if (@typeInfo(T) == .@"fn") return true;
    if (@typeInfo(T) == .pointer) {
        const child = @typeInfo(T).pointer.child;
        if (@typeInfo(child) == .@"fn") return true;
    }
    if (T == *PyObject) {
        if (obj.ob_type) |type_obj| {
            const type_id = type_obj.tp_flags & 0xFF;
            if (type_id == 0x10 or type_id == 0x11) return true;
            if (@hasField(@TypeOf(type_obj.*), "tp_call")) {
                if (type_obj.tp_call != null) return true;
            }
        }
        return false;
    }
    return false;
}

/// Helper to check if type is a slice
fn isSlice(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |p| p.size == .slice,
        else => false,
    };
}

/// len() builtin
pub fn len(obj: anytype) usize {
    const T = @TypeOf(obj);
    if (T == *PyObject) {
        return runtime_core.pyLen(obj);
    } else if (comptime isSlice(T)) {
        return obj.len;
    } else if (@typeInfo(T) == .pointer) {
        const Child = @typeInfo(T).pointer.child;
        const child_info = @typeInfo(Child);
        if (child_info == .@"struct" and @hasField(Child, "items")) {
            return obj.items.len;
        } else if (child_info == .@"struct" and @hasDecl(Child, "len")) {
            return obj.len;
        }
    } else if (@typeInfo(T) == .@"struct") {
        if (@hasDecl(T, "len")) {
            return obj.len();
        } else if (@hasField(T, "items")) {
            return obj.items.len;
        }
    } else if (@typeInfo(T) == .array) {
        return @typeInfo(T).array.len;
    }
    return 0;
}

/// id() builtin - returns object identity (pointer address)
pub fn id(obj: anytype) usize {
    const T = @TypeOf(obj);
    if (@typeInfo(T) == .pointer) {
        return @intFromPtr(obj);
    }
    return 0;
}

/// hash() builtin - returns hash of object
pub fn hash(obj: anytype) i64 {
    const T = @TypeOf(obj);
    if (T == *PyObject) {
        return @intCast(runtime_core.pyHash(obj));
    } else if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
        return @intCast(obj);
    } else if (T == []const u8 or T == []u8) {
        var h: u64 = 0;
        for (obj) |c| h = h *% 31 +% c;
        return @intCast(h);
    } else if (@typeInfo(T) == .@"struct") {
        return tupleHash(obj);
    }
    return 0;
}

/// Python-compatible tuple hash using xxHash algorithm
fn tupleHash(tup: anytype) i64 {
    const T = @TypeOf(tup);
    const info = @typeInfo(T);
    if (info != .@"struct") return 0;

    const fields = info.@"struct".fields;
    const num_fields = fields.len;

    const XXPRIME_1: u64 = 11400714785074694791;
    const XXPRIME_2: u64 = 14029467366897019727;
    const XXPRIME_5: u64 = 2870177450012600261;

    var acc: u64 = XXPRIME_5;

    inline for (fields) |field| {
        const elem = @field(tup, field.name);
        const elem_hash: u64 = @bitCast(hash(elem));
        acc +%= elem_hash *% XXPRIME_2;
        acc = (acc << 31) | (acc >> 33);
        acc *%= XXPRIME_1;
    }

    acc +%= @as(u64, num_fields) ^ (XXPRIME_5 ^ 3527539);

    if (acc == @as(u64, @bitCast(@as(i64, -1)))) {
        return 1546275796;
    }

    return @bitCast(acc);
}

/// compile() builtin - not supported in AOT context
pub fn compile(source: []const u8, filename: []const u8, mode: []const u8) PythonError!void {
    _ = source;
    _ = filename;
    _ = mode;
    return PythonError.ValueError;
}

/// exec() builtin - not supported in AOT context
pub fn exec(code: anytype) PythonError!void {
    _ = code;
    return PythonError.ValueError;
}

/// struct.pack() stub - no args version
pub fn structPackNoArgs() PythonError![]const u8 {
    return PythonError.TypeError;
}

/// struct.pack_into() stub - no args version
pub fn structPackIntoNoArgs() PythonError!void {
    return PythonError.TypeError;
}

/// str() builtin
pub fn str(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8 or T == []u8) return value;
    if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .one) {
        const Child = @typeInfo(T).pointer.child;
        if (@typeInfo(Child) == .array and @typeInfo(Child).array.child == u8) {
            return value;
        }
    }
    return "";
}

/// bytes() builtin
pub fn bytes(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8 or T == []u8) return value;
    if (T == PyBytes) return value.data;
    return "";
}

/// bytearray() builtin
pub fn bytearray(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8 or T == []u8) return value;
    if (T == PyBytes) return value.data;
    return "";
}

/// memoryview() builtin
pub fn memoryview(value: anytype) []const u8 {
    const T = @TypeOf(value);
    if (T == []const u8 or T == []u8) return value;
    if (T == PyBytes) return value.data;
    return "";
}

/// bytes() callable version
pub fn bytes_callable(value: []const u8) []const u8 {
    return value;
}

/// bytearray() callable version
pub fn bytearray_callable(value: []const u8) []const u8 {
    return value;
}

/// str() callable version
pub fn str_callable(value: []const u8) []const u8 {
    return value;
}

/// memoryview() callable version
pub fn memoryview_callable(value: []const u8) []const u8 {
    return value;
}

/// BigInt divmod
pub fn bigIntDivmod(a: anytype, b: anytype, allocator: std.mem.Allocator) struct { @TypeOf(a), @TypeOf(a) } {
    const T = @TypeOf(a);
    if (@typeInfo(T) == .@"struct" and @hasDecl(T, "divFloor")) {
        const q = a.divFloor(b, allocator) catch return .{ a, a };
        const r = a.mod(b, allocator) catch return .{ a, a };
        return .{ q, r };
    }
    return .{ a, a };
}

/// Compare operation enum
pub const CompareOp = enum { lt, le, eq, ne, gt, ge };

/// BigInt comparison
pub fn bigIntCompare(a: anytype, b: anytype, op: CompareOp) bool {
    const T = @TypeOf(a);
    if (@typeInfo(T) == .@"struct" and @hasDecl(T, "compare")) {
        const cmp = a.compare(b);
        return switch (op) {
            .lt => cmp < 0,
            .le => cmp <= 0,
            .eq => cmp == 0,
            .ne => cmp != 0,
            .gt => cmp > 0,
            .ge => cmp >= 0,
        };
    }
    return false;
}

// =============================================================================
// Operator comparison functions
// =============================================================================

/// operator.eq - equality comparison
pub fn operatorEq(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .bool or info == .comptime_int or info == .comptime_float) {
            return a == b;
        }
    }
    return false;
}

/// operator.ne - inequality comparison
pub fn operatorNe(a: anytype, b: anytype) bool {
    return !operatorEq(a, b);
}

/// operator.lt - less than comparison
pub fn operatorLt(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .comptime_int or info == .comptime_float) {
            return a < b;
        }
    }
    return false;
}

/// operator.le - less than or equal comparison
pub fn operatorLe(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .comptime_int or info == .comptime_float) {
            return a <= b;
        }
    }
    return false;
}

/// operator.gt - greater than comparison
pub fn operatorGt(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .comptime_int or info == .comptime_float) {
            return a > b;
        }
    }
    return false;
}

/// operator.ge - greater than or equal comparison
pub fn operatorGe(a: anytype, b: anytype) bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);

    if (TypeA == TypeB) {
        const info = @typeInfo(TypeA);
        if (info == .int or info == .float or info == .comptime_int or info == .comptime_float) {
            return a >= b;
        }
    }
    return false;
}

/// Class instance equality comparison
pub fn classInstanceEq(a: anytype, b: anytype, allocator: std.mem.Allocator) bool {
    const TypeA = @TypeOf(a);
    const type_info = @typeInfo(TypeA);

    if (type_info == .@"struct" and @hasDecl(TypeA, "__eq__")) {
        const eq_info = @typeInfo(@TypeOf(TypeA.__eq__));
        if (eq_info == .@"fn") {
            const params = eq_info.@"fn".params;
            const result = if (params.len == 3)
                a.__eq__(allocator, b)
            else
                a.__eq__(b);

            const ResultType = @TypeOf(result);
            if (@typeInfo(ResultType) == .error_union) {
                return result catch false;
            } else if (ResultType == bool) {
                return result;
            }
        }
    }
    return false;
}

/// Class instance not-equal comparison
pub fn classInstanceNe(a: anytype, b: anytype, allocator: std.mem.Allocator) bool {
    const TypeA = @TypeOf(a);
    const type_info = @typeInfo(TypeA);

    if (type_info == .@"struct" and @hasDecl(TypeA, "__ne__")) {
        const ne_info = @typeInfo(@TypeOf(TypeA.__ne__));
        if (ne_info == .@"fn") {
            const params = ne_info.@"fn".params;
            const result = if (params.len == 3)
                a.__ne__(allocator, b)
            else
                a.__ne__(b);

            const ResultType = @TypeOf(result);
            if (@typeInfo(ResultType) == .error_union) {
                return result catch true;
            } else if (ResultType == bool) {
                return result;
            }
        }
    }
    return !classInstanceEq(a, b, allocator);
}

/// Generic assertEqual helper
pub fn assertEqualGeneric(a: anytype, b: anytype, allocator: std.mem.Allocator) !bool {
    return pyEqual(allocator, a, b);
}

/// Universal Python-semantic equality comparison
pub fn pyEqual(allocator: std.mem.Allocator, a: anytype, b: anytype) !bool {
    const TypeA = @TypeOf(a);
    const TypeB = @TypeOf(b);
    const info_a = @typeInfo(TypeA);
    const info_b = @typeInfo(TypeB);

    // Same type fast path
    if (TypeA == TypeB) {
        if (TypeA == f64) return @as(u64, @bitCast(a)) == @as(u64, @bitCast(b));
        if (TypeA == f32) return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
        if (info_a == .int or info_a == .comptime_int or info_a == .comptime_float or info_a == .bool) {
            return a == b;
        }
        if (info_a == .pointer and info_a.pointer.size == .slice) {
            if (info_a.pointer.child == u8) {
                return std.mem.eql(u8, a, b);
            }
        }
    }

    // Tagged union handling
    if (info_a == .@"union" and info_a.@"union".tag_type != null) {
        const tag = std.meta.activeTag(a);
        inline for (info_a.@"union".fields) |field| {
            if (tag == @field(std.meta.Tag(TypeA), field.name)) {
                const field_value = @field(a, field.name);
                return pyEqual(allocator, field_value, b);
            }
        }
    }
    if (info_b == .@"union" and info_b.@"union".tag_type != null) {
        const tag = std.meta.activeTag(b);
        inline for (info_b.@"union".fields) |field| {
            if (tag == @field(std.meta.Tag(TypeB), field.name)) {
                const field_value = @field(b, field.name);
                return pyEqual(allocator, a, field_value);
            }
        }
    }

    // Builtin subclass handling
    if (info_a == .@"struct" and @hasField(TypeA, "__base_value__")) {
        return pyEqual(allocator, a.__base_value__, b);
    }
    if (info_b == .@"struct" and @hasField(TypeB, "__base_value__")) {
        return pyEqual(allocator, a, b.__base_value__);
    }

    // ArrayList comparison
    if (info_a == .@"struct" and @hasField(TypeA, "items") and @hasField(TypeA, "capacity") and
        info_b == .@"struct" and @hasField(TypeB, "items") and @hasField(TypeB, "capacity"))
    {
        if (a.items.len != b.items.len) return false;
        for (a.items, b.items) |item_a, item_b| {
            if (!try pyEqual(allocator, item_a, item_b)) return false;
        }
        return true;
    }

    // ArrayList to tuple
    if (info_a == .@"struct" and @hasField(TypeA, "items") and @hasField(TypeA, "capacity")) {
        return pyEqualSliceToTuple(allocator, a.items, b);
    }
    if (info_b == .@"struct" and @hasField(TypeB, "items") and @hasField(TypeB, "capacity")) {
        return pyEqualSliceToTuple(allocator, b.items, a);
    }

    // Tuple element-wise comparison
    if (info_a == .@"struct" and info_b == .@"struct") {
        const a_is_class = @hasDecl(TypeA, "__name__");
        const b_is_class = @hasDecl(TypeB, "__name__");
        if (!a_is_class and !b_is_class) {
            const fields_a = info_a.@"struct".fields;
            const fields_b = info_b.@"struct".fields;
            if (fields_a.len != fields_b.len) return false;
            inline for (fields_a, 0..) |field_a, i| {
                const a_val = @field(a, field_a.name);
                const b_val = @field(b, fields_b[i].name);
                if (!try pyEqual(allocator, a_val, b_val)) return false;
            }
            return true;
        }
    }

    // Custom __eq__ method
    const a_has_eq = info_a == .@"struct" and @hasDecl(TypeA, "__eq__");
    const b_has_eq = info_b == .@"struct" and @hasDecl(TypeB, "__eq__");

    if (a_has_eq) return classInstanceEq(a, b, allocator);
    if (b_has_eq) return classInstanceEq(b, a, allocator);

    // Numeric coercion fallback
    const object = @import("../Objects/object.zig");
    const a_val = try object.toPyValue(allocator, a);
    const b_val = try object.toPyValue(allocator, b);
    return a_val.eql(b_val);
}

/// Helper to compare slice to tuple
fn pyEqualSliceToTuple(allocator: std.mem.Allocator, slice: anytype, tup: anytype) !bool {
    const SliceType = @TypeOf(slice);
    const TupleType = @TypeOf(tup);
    const slice_info = @typeInfo(SliceType);
    const tup_info = @typeInfo(TupleType);

    if (slice_info != .pointer or slice_info.pointer.size != .slice) return false;

    if (tup_info == .array) {
        const arr_info = tup_info.array;
        if (slice.len != arr_info.len) return false;
        for (0..arr_info.len) |i| {
            if (!try pyEqual(allocator, slice[i], tup[i])) return false;
        }
        return true;
    }

    if (tup_info == .@"struct") {
        const fields = tup_info.@"struct".fields;
        if (slice.len != fields.len) return false;
        inline for (fields, 0..) |field, i| {
            const tup_val = @field(tup, field.name);
            if (!try pyEqual(allocator, slice[i], tup_val)) return false;
        }
        return true;
    }

    return false;
}

// =============================================================================
// Type constructor callables
// =============================================================================

/// list() type constructor
pub const list = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        const T = @TypeOf(arg);
        if (T == void) return try PyList.create(allocator);
        if (T == *PyObject) {
            if (arg.type_id == .list) {
                const source: *PyList = @ptrCast(@alignCast(arg.data));
                const result = try PyList.create(allocator);
                for (source.items.items) |item| {
                    incref(item);
                    try PyList.append(result, item);
                }
                return result;
            }
        }
        return try PyList.create(allocator);
    }
}{};

/// tuple() type constructor
pub const tuple = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        const T = @TypeOf(arg);
        if (T == void) return try PyTuple.create(allocator, 0);
        if (T == *PyObject) {
            if (arg.type_id == .list) {
                const source: *PyList = @ptrCast(@alignCast(arg.data));
                const result = try PyTuple.create(allocator, source.items.items.len);
                for (source.items.items, 0..) |item, i| {
                    incref(item);
                    PyTuple.setItem(result, i, item);
                }
                return result;
            }
        }
        return try PyTuple.create(allocator, 0);
    }
}{};

/// set() type constructor
pub const set = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        const T = @TypeOf(arg);
        if (T == void) return try PySet.create(allocator);
        if (T == *PyObject) {
            if (runtime_core.PyList_Check(arg)) {
                return try PySet.fromList(allocator, arg);
            }
        }
        return try PySet.create(allocator);
    }
}{};

/// frozenset() type constructor
pub const frozenset = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        const T = @TypeOf(arg);
        if (T == void) return try PySet.createFrozenset(allocator);
        if (T == *PyObject) {
            if (runtime_core.PyList_Check(arg)) {
                return try PySet.frozensetFromList(allocator, arg);
            }
        }
        return try PySet.createFrozenset(allocator);
    }
}{};

/// deque() type constructor
pub const deque = struct {
    pub fn call(_: @This(), allocator: std.mem.Allocator, arg: anytype) !*PyObject {
        const T = @TypeOf(arg);
        if (T == void) return try PyDeque.create(allocator, null);
        if (T == *PyObject) {
            if (runtime_core.PyList_Check(arg)) {
                return try PyDeque.fromList(allocator, arg, null);
            }
        }
        return try PyDeque.create(allocator, null);
    }
}{};
