/// metal0 Runtime Library
/// Core runtime support for compiled Python code
const std = @import("std");
const builtin = @import("builtin");

/// Browser WASM (freestanding) has no threading or OS support
pub const is_freestanding = builtin.os.tag == .freestanding;

const hashmap_helper = @import("hashmap_helper");
const pyint = @import("Objects/intobject.zig");
const pyfloat = @import("Objects/floatobject.zig");
const pybool = @import("Objects/boolobject.zig");
const pylist = @import("Objects/listobject.zig");
pub const pystring = @import("Objects/unicodeobject.zig");
const pytuple = @import("Objects/tupleobject.zig");
const pyfile = @import("Objects/fileobject.zig");

/// BigInt for arbitrary precision integers (Python int semantics)
pub const bigint = @import("bigint");
pub const BigInt = bigint.BigInt;

/// Export string utilities for native codegen
pub const string_utils = @import("runtime/string_utils.zig");

/// Export _string module (formatter_parser, etc.)
pub const _string = @import("Modules/_string.zig");

/// Export C accelerator modules
pub const _functools = @import("Modules/_functools.zig");
pub const _operator = @import("Modules/_operator.zig");
pub const _collections = @import("Modules/_collections.zig");
pub const _bisect = @import("Modules/_bisect.zig");
pub const _heapq = @import("Modules/_heapq.zig");
pub const _struct = @import("Modules/_struct.zig");
pub const _random = @import("Modules/_random.zig");
pub const _pickle = @import("Modules/_pickle.zig");

/// Export AST executor for eval() support
pub const ast_executor = @import("Python/ast_executor.zig");

/// Export iterators (TupleIterator, ListIterator, ReversedIterator)
pub const iterators = @import("Python/iterobject.zig");
pub const TupleIterator = iterators.TupleIterator;
pub const ListIterator = iterators.ListIterator;
pub const ReversedIterator = iterators.ReversedIterator;
pub const SequenceIterator = iterators.SequenceIterator;

/// Export calendar module
pub const calendar = @import("Lib/calendar.zig");

/// Export os module
pub const os = @import("Lib/os.zig");

/// Export itertools module
pub const itertools = @import("Lib/itertools.zig");

/// Export ctypes FFI module
pub const ctypes = @import("Modules/_ctypes.zig");

/// Export typing module types
pub const typing = @import("Lib/typing.zig");

/// Export dynamic attribute access stubs
const dynamic_attrs = @import("runtime/dynamic_attrs.zig");

/// Export PyValue for dynamic attributes
pub const PyValue = @import("Objects/object.zig").PyValue;

/// Export comptime type inference helpers
const comptime_helpers = @import("runtime/comptime_helpers.zig");
pub const InferListType = comptime_helpers.InferListType;
pub const createListComptime = comptime_helpers.createListComptime;
pub const InferDictValueType = comptime_helpers.InferDictValueType;

/// Export comptime closure helpers
pub const closure_impl = @import("runtime/closure_impl.zig");
pub const Closure0 = closure_impl.Closure0;
pub const Closure1 = closure_impl.Closure1;
pub const Closure2 = closure_impl.Closure2;
pub const Closure3 = closure_impl.Closure3;
pub const ZeroClosure = closure_impl.ZeroClosure;
pub const AnyClosure0 = closure_impl.AnyClosure0;
pub const AnyClosure1 = closure_impl.AnyClosure1;
pub const AnyClosure2 = closure_impl.AnyClosure2;
pub const AnyClosure3 = closure_impl.AnyClosure3;
pub const AnyClosure4 = closure_impl.AnyClosure4;
pub const AnyClosure5 = closure_impl.AnyClosure5;
pub const AnyClosure6 = closure_impl.AnyClosure6;
pub const AnyClosure7 = closure_impl.AnyClosure7;

/// Debug info reader for Python line number translation
pub const debug_reader = @import("runtime/debug_reader.zig");

/// Export TypeFactory for first-class types (classes as values)
pub const type_factory = @import("runtime/type_factory.zig");
pub const TypeFactory = type_factory.TypeFactory;
pub const AnyTypeFactory = type_factory.AnyTypeFactory;

/// Export format utilities from runtime_format.zig
const runtime_format = @import("Python/formatter.zig");
pub const formatAny = runtime_format.formatAny;
pub const formatUnknown = runtime_format.formatUnknown;
pub const formatFloat = runtime_format.formatFloat;
pub const formatPyObject = runtime_format.formatPyObject;
pub const PyDict_AsString = runtime_format.PyDict_AsString;
pub const printValue = runtime_format.printValue;
pub const pyFormat = runtime_format.pyFormat;
pub const pyMod = runtime_format.pyMod;
pub const pyFloatMod = runtime_format.pyFloatMod;
pub const pyFloatFloorDiv = runtime_format.pyFloatFloorDiv;
pub const pyStringFormat = runtime_format.pyStringFormat;

/// Export exception types from runtime/exceptions.zig
pub const exceptions = @import("runtime/exceptions.zig");
pub const PythonError = exceptions.PythonError;
pub const ExceptionTypeId = exceptions.ExceptionTypeId;
pub const TypeError = exceptions.TypeError;
pub const ValueError = exceptions.ValueError;
pub const KeyError = exceptions.KeyError;
pub const IndexError = exceptions.IndexError;
pub const ZeroDivisionError = exceptions.ZeroDivisionError;
pub const AttributeError = exceptions.AttributeError;
pub const NameError = exceptions.NameError;
pub const FileNotFoundError = exceptions.FileNotFoundError;
pub const IOError = exceptions.IOError;
pub const RuntimeError = exceptions.RuntimeError;
pub const StopIteration = exceptions.StopIteration;
pub const NotImplementedError = exceptions.NotImplementedError;
pub const AssertionError = exceptions.AssertionError;
pub const OverflowError = exceptions.OverflowError;
pub const ImportError = exceptions.ImportError;
pub const ModuleNotFoundError = exceptions.ModuleNotFoundError;
pub const OSError = exceptions.OSError;
pub const PermissionError = exceptions.PermissionError;
pub const TimeoutError = exceptions.TimeoutError;
pub const ConnectionError = exceptions.ConnectionError;
pub const RecursionError = exceptions.RecursionError;
pub const MemoryError = exceptions.MemoryError;
pub const LookupError = exceptions.LookupError;
pub const ArithmeticError = exceptions.ArithmeticError;
pub const BufferError = exceptions.BufferError;
pub const EOFError = exceptions.EOFError;
pub const GeneratorExit = exceptions.GeneratorExit;
pub const SystemExit = exceptions.SystemExit;
pub const KeyboardInterrupt = exceptions.KeyboardInterrupt;
pub const BaseException = exceptions.BaseException;
pub const Exception = exceptions.Exception;
pub const SyntaxError = exceptions.SyntaxError;
pub const UnicodeError = exceptions.UnicodeError;
pub const UnicodeDecodeError = exceptions.UnicodeDecodeError;
pub const UnicodeEncodeError = exceptions.UnicodeEncodeError;

// Exception message handling
pub const setExceptionMessage = exceptions.setExceptionMessage;
pub const setExceptionType = exceptions.setExceptionType;
pub const setException = exceptions.setException;
pub const getExceptionMessage = exceptions.getExceptionMessage;
pub const getExceptionType = exceptions.getExceptionType;
pub const getExceptionStr = exceptions.getExceptionStr;
pub const clearException = exceptions.clearException;

/// Python's NotImplemented singleton - used by binary operations to signal
/// that the operation is not supported for the given types.
/// In Python: return NotImplemented tells the interpreter to try the reflected method.
/// In metal0: we use a sentinel struct that evaluates to false in boolean contexts.
pub const NotImplementedType = struct {
    _marker: u8 = 0,

    pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = self;
        _ = fmt;
        _ = options;
        try writer.writeAll("NotImplemented");
    }
};
pub const NotImplemented: NotImplementedType = .{};

/// Comptime type check for Python type names
/// Used for comptime branching in type-checking patterns with anytype params
/// Example: if (comptime !runtime.istype(@TypeOf(x), "int")) return error.TypeError;
pub fn istype(comptime T: type, comptime type_name: []const u8) bool {
    const info = @typeInfo(T);

    if (comptime std.mem.eql(u8, type_name, "int")) {
        return info == .int or info == .comptime_int or T == bool;
    } else if (comptime std.mem.eql(u8, type_name, "float")) {
        return info == .float or info == .comptime_float;
    } else if (comptime std.mem.eql(u8, type_name, "bool")) {
        return T == bool;
    } else if (comptime std.mem.eql(u8, type_name, "str")) {
        if (T == []const u8 or T == []u8) return true;
        // String literals: *const [N:0]u8
        if (info == .pointer and info.pointer.size == .one) {
            const child_info = @typeInfo(info.pointer.child);
            if (child_info == .array and child_info.array.child == u8) {
                return true;
            }
        }
        return false;
    } else {
        // Unknown type - check for struct with matching name
        if (info == .@"struct") {
            if (@hasDecl(T, "__class_name__")) {
                return std.mem.eql(u8, T.__class_name__, type_name);
            }
        }
        return false;
    }
}

/// Discard a value (consume it to prevent unused variable errors)
/// This is a no-op function that accepts any value
pub inline fn discard(_: anytype) void {}

/// Python-style containment check for slices
/// Handles NaN specially: both sides being NaN counts as a match (identity semantics)
pub fn pyContains(comptime T: type, slice: []const T, value: T) bool {
    // For floats, check NaN identity
    if (@typeInfo(T) == .float) {
        const value_is_nan = std.math.isNan(value);
        for (slice) |item| {
            if (value_is_nan and std.math.isNan(item)) return true;
            if (item == value) return true;
        }
        return false;
    }
    // For slice types (like strings), use std.mem.eql
    if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice) {
        for (slice) |item| {
            if (std.mem.eql(@typeInfo(T).pointer.child, item, value)) return true;
        }
        return false;
    }
    // For other types, use standard equality
    return std.mem.indexOfScalar(T, slice, value) != null;
}

/// Python-style count for slices
/// Handles NaN specially: both sides being NaN counts as a match (identity semantics)
pub fn pyCount(comptime T: type, slice: []const T, value: T) usize {
    var count: usize = 0;
    // For floats, check NaN identity
    if (@typeInfo(T) == .float) {
        const value_is_nan = std.math.isNan(value);
        for (slice) |item| {
            if ((value_is_nan and std.math.isNan(item)) or item == value) count += 1;
        }
    } else {
        // For other types, use standard equality
        for (slice) |item| {
            if (item == value) count += 1;
        }
    }
    return count;
}

/// Python-style slice equality
/// Handles NaN specially: two NaN values are considered equal (identity semantics)
pub fn pySliceEql(comptime T: type, a: []const T, b: []const T) bool {
    if (a.len != b.len) return false;
    // For floats, use NaN-aware comparison
    if (@typeInfo(T) == .float) {
        for (a, b) |a_item, b_item| {
            const a_nan = std.math.isNan(a_item);
            const b_nan = std.math.isNan(b_item);
            // Both NaN -> equal (identity), otherwise use value comparison
            if (a_nan and b_nan) continue;
            if (a_nan or b_nan) return false; // One NaN, one not
            if (a_item != b_item) return false;
        }
        return true;
    }
    // For other types, use standard equality
    return std.mem.eql(T, a, b);
}

/// Python-style tuple/array equality
/// Handles NaN specially: two NaN values are considered equal (identity semantics)
pub fn pyTupleEql(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);
    const info = @typeInfo(T);

    // Handle arrays
    if (info == .array) {
        const ElemT = info.array.child;
        if (@typeInfo(ElemT) == .float) {
            for (a, b) |a_item, b_item| {
                const a_nan = std.math.isNan(a_item);
                const b_nan = std.math.isNan(b_item);
                if (a_nan and b_nan) continue;
                if (a_nan or b_nan) return false;
                if (a_item != b_item) return false;
            }
            return true;
        }
    }

    // Handle structs (tuples are anonymous structs in Zig)
    if (info == .@"struct") {
        inline for (info.@"struct".fields) |field| {
            const a_field = @field(a, field.name);
            const b_field = @field(b, field.name);
            const FieldT = field.type;

            if (@typeInfo(FieldT) == .float) {
                const a_nan = std.math.isNan(a_field);
                const b_nan = std.math.isNan(b_field);
                // Both NaN -> equal (identity), skip to next field
                // Only one NaN or different values -> not equal
                if (!(a_nan and b_nan)) {
                    if (a_nan or b_nan) return false;
                    if (a_field != b_field) return false;
                }
            } else {
                if (!std.meta.eql(a_field, b_field)) return false;
            }
        }
        return true;
    }

    // Fallback to standard equality
    return std.meta.eql(a, b);
}

/// Python-style generic equality for any two types
/// If types differ, returns false (Python semantics for `==` with different types)
/// If types match, uses pyAnyEqlSameType for proper comparison
pub fn pyAnyEql(a: anytype, b: anytype) bool {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const a_info = @typeInfo(A);
    const b_info = @typeInfo(B);

    // Different types are never equal in Python (for most cases)
    if (A != B) {
        // Special case: optional types - unwrap and compare
        if (a_info == .optional) {
            if (a) |unwrapped_a| {
                return pyAnyEql(unwrapped_a, b);
            }
            return false;
        }
        if (b_info == .optional) {
            if (b) |unwrapped_b| {
                return pyAnyEql(a, unwrapped_b);
            }
            return false;
        }

        // Special case: ArrayList vs fixed array - compare as slices
        // This handles `x == [1,2,3]` where x is an ArrayList after mutation
        const a_is_arraylist = a_info == .@"struct" and @hasField(A, "items") and @hasField(A, "capacity");
        const b_is_arraylist = b_info == .@"struct" and @hasField(B, "items") and @hasField(B, "capacity");
        const a_is_array = a_info == .array;
        const b_is_array = b_info == .array;

        if (a_is_arraylist and b_is_array) {
            // ArrayList vs fixed array: compare items as slices
            // Only compare if element types match
            const AElem = std.meta.Elem(@TypeOf(a.items));
            const BElem = b_info.array.child;
            if (AElem != BElem) return false;
            if (a.items.len != b.len) return false;
            for (a.items, 0..) |item, idx| {
                if (!std.meta.eql(item, b[idx])) return false;
            }
            return true;
        }
        if (a_is_array and b_is_arraylist) {
            // Fixed array vs ArrayList: compare items as slices
            // Only compare if element types match
            const AElem = a_info.array.child;
            const BElem = std.meta.Elem(@TypeOf(b.items));
            if (AElem != BElem) return false;
            if (a.len != b.items.len) return false;
            for (b.items, 0..) |item, idx| {
                if (!std.meta.eql(a[idx], item)) return false;
            }
            return true;
        }

        // Special case: PyValue vs primitive type - unwrap PyValue and compare
        const a_is_pyvalue = A == PyValue;
        const b_is_pyvalue = B == PyValue;
        if (a_is_pyvalue and !b_is_pyvalue) {
            // Unwrap PyValue and compare with b
            return switch (a) {
                .int => |v| if (b_info == .comptime_int or b_info == .int) v == @as(i64, b) else false,
                .float => |v| if (b_info == .comptime_float or b_info == .float) v == @as(f64, b) else false,
                .bool => |v| if (B == bool) v == b else false,
                .string => |v| if (b_info == .pointer and b_info.pointer.size == .slice and b_info.pointer.child == u8) std.mem.eql(u8, v, b) else false,
                .list => |list| if (b_info == .array) blk: {
                    if (list.len != b.len) break :blk false;
                    for (list, 0..) |elem, i| {
                        if (!pyAnyEql(elem, b[i])) break :blk false;
                    }
                    break :blk true;
                } else false,
                else => false,
            };
        }
        if (b_is_pyvalue and !a_is_pyvalue) {
            // Unwrap PyValue and compare with a
            return switch (b) {
                .int => |v| if (a_info == .comptime_int or a_info == .int) @as(i64, a) == v else false,
                .float => |v| if (a_info == .comptime_float or a_info == .float) @as(f64, a) == v else false,
                .bool => |v| if (A == bool) a == v else false,
                .string => |v| if (a_info == .pointer and a_info.pointer.size == .slice and a_info.pointer.child == u8) std.mem.eql(u8, a, v) else false,
                .list => |list| if (a_info == .array) blk: {
                    if (a.len != list.len) break :blk false;
                    for (a, 0..) |elem, i| {
                        if (!pyAnyEql(elem, list[i])) break :blk false;
                    }
                    break :blk true;
                } else false,
                else => false,
            };
        }

        // Special case: int/comptime_int comparison
        // Runtime i64 vs comptime_int or vice versa
        const a_is_int = a_info == .int or a_info == .comptime_int;
        const b_is_int = b_info == .int or b_info == .comptime_int;
        if (a_is_int and b_is_int) {
            return @as(i64, a) == @as(i64, b);
        }

        // Special case: float/comptime_float comparison
        const a_is_float = a_info == .float or a_info == .comptime_float;
        const b_is_float = b_info == .float or b_info == .comptime_float;
        if (a_is_float and b_is_float) {
            return @as(f64, a) == @as(f64, b);
        }

        return false;
    }

    return pyAnyEqlSameType(A, a, b);
}

/// Python-style generic equality for any type (same type required)
/// Handles: lists (ArrayList), tuples (structs), sets (AutoHashMap with void value), dicts (AutoHashMap)
/// Uses NaN identity semantics for floats
fn pyAnyEqlSameType(comptime T: type, a: T, b: T) bool {
    const info = @typeInfo(T);

    // ArrayList (Python list) - compare items with NaN semantics
    if (info == .@"struct" and @hasField(T, "items") and @hasField(T, "capacity")) {
        const ItemT = std.meta.Elem(@TypeOf(a.items));
        return pySliceEql(ItemT, a.items, b.items);
    }

    // AutoHashMap (Python set or dict) - compare by count and key/value match
    if (info == .@"struct" and @hasField(T, "entries") and @hasDecl(T, "count")) {
        if (a.count() != b.count()) return false;
        var it = a.iterator();
        while (it.next()) |entry| {
            if (!b.contains(entry.key_ptr.*)) return false;
            // For dicts, also compare values
            if (@hasDecl(T, "get")) {
                const ValT = @TypeOf(entry.value_ptr.*);
                if (ValT != void) {
                    // This is a dict (value type is not void)
                    if (b.get(entry.key_ptr.*)) |bv| {
                        if (!std.meta.eql(entry.value_ptr.*, bv)) return false;
                    } else {
                        return false;
                    }
                }
            }
        }
        return true;
    }

    // Tuples/structs - use pyTupleEql for NaN semantics
    if (info == .@"struct") {
        return pyTupleEql(a, b);
    }

    // Arrays - use pyTupleEql which handles arrays
    if (info == .array) {
        return pyTupleEql(a, b);
    }

    // Floats - handle NaN identity
    if (info == .float) {
        const a_nan = std.math.isNan(a);
        const b_nan = std.math.isNan(b);
        if (a_nan and b_nan) return true;
        if (a_nan or b_nan) return false;
        return a == b;
    }

    // Slices
    if (info == .pointer and info.pointer.size == .slice) {
        const ElemT = std.meta.Elem(T);
        return pySliceEql(ElemT, a, b);
    }

    // Fallback to std.meta.eql
    return std.meta.eql(a, b);
}

/// Convert ArrayList or other container types to a slice for iteration
/// This is a comptime function that normalizes different container types to slices
pub inline fn iterSlice(value: anytype) IterSliceType(@TypeOf(value)) {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Handle ArrayList - extract .items slice
    if (info == .@"struct" and @hasField(T, "items") and @hasField(T, "capacity")) {
        return value.items;
    }

    // Handle pointer to ArrayList - dereference and extract .items
    if (info == .pointer and info.pointer.size == .one) {
        const Child = info.pointer.child;
        const child_info = @typeInfo(Child);
        if (child_info == .@"struct" and @hasField(Child, "items") and @hasField(Child, "capacity")) {
            return value.items;
        }
    }

    // Handle PyValue - extract list slice
    if (T == PyValue) {
        return switch (value) {
            .list => |l| l,
            .tuple => |t| t,
            else => &[_]PyValue{},
        };
    }

    // Array - convert to slice
    if (info == .array) {
        return &value;
    }

    // Already a slice - return as-is
    return value;
}

/// Helper to determine return type for iterSlice
fn IterSliceType(comptime T: type) type {
    const info = @typeInfo(T);

    // ArrayList -> slice of its item type
    if (info == .@"struct" and @hasField(T, "items") and @hasField(T, "capacity")) {
        // ArrayList.items is a slice, return that slice type directly
        return @TypeOf(@as(T, undefined).items);
    }

    // Pointer to ArrayList -> slice of its item type
    if (info == .pointer and info.pointer.size == .one) {
        const Child = info.pointer.child;
        const child_info = @typeInfo(Child);
        if (child_info == .@"struct" and @hasField(Child, "items") and @hasField(Child, "capacity")) {
            return @TypeOf(@as(Child, undefined).items);
        }
    }

    // PyValue -> []const PyValue
    if (T == PyValue) {
        return []const PyValue;
    }

    // Already a slice - return same type
    if (info == .pointer and info.pointer.size == .slice) {
        return T;
    }

    // Array - return as slice
    if (info == .array) {
        return []const info.array.child;
    }

    // Fallback
    return T;
}

/// Generic bool conversion for Python truthiness semantics
/// Returns false for: 0, 0.0, false, empty strings, empty slices
/// Returns true for everything else
pub fn toBool(value: anytype) bool {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Handle integers
    if (info == .int or info == .comptime_int) {
        return value != 0;
    }

    // Handle floats
    if (info == .float or info == .comptime_float) {
        return value != 0.0;
    }

    // Handle bool
    if (T == bool) {
        return value;
    }

    // Handle slices (including strings)
    if (info == .pointer and info.pointer.size == .slice) {
        return value.len > 0;
    }

    // Handle single-item pointers to arrays (string literals)
    if (info == .pointer and info.pointer.size == .one) {
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .array) {
            return child_info.array.len > 0;
        }
        // Handle pointers to structs with __bool__ method (Python objects)
        if (child_info == .@"struct") {
            const ChildT = info.pointer.child;
            if (@hasDecl(ChildT, "__bool__")) {
                // Check if __bool__ takes a mutable pointer (self-mutating method)
                const bool_fn_info = @typeInfo(@TypeOf(ChildT.__bool__));
                const first_param_type = bool_fn_info.@"fn".params[0].type.?;
                const first_param_info = @typeInfo(first_param_type);

                const result = blk: {
                    if (first_param_info == .pointer and !first_param_info.pointer.is_const) {
                        // __bool__ takes *@This() (mutable) - value is already a pointer
                        if (info.pointer.is_const) {
                            // Cast away const if needed
                            break :blk @constCast(value).__bool__();
                        } else {
                            break :blk value.__bool__();
                        }
                    } else {
                        // __bool__ takes *const @This() or value - call directly
                        break :blk value.__bool__();
                    }
                };
                const ResultT = @TypeOf(result);
                if (@typeInfo(ResultT) == .bool) {
                    return result;
                }
                // Handle error union wrapping bool
                if (@typeInfo(ResultT) == .error_union) {
                    const unwrapped = result catch return false;
                    const UnwrappedT = @TypeOf(unwrapped);
                    if (@typeInfo(UnwrappedT) == .bool) {
                        return unwrapped;
                    }
                    @panic("TypeError: __bool__ should return bool, not error union with non-bool");
                }
                @panic("TypeError: __bool__ should return bool");
            }
            // Check for __len__ as fallback (containers with 0 length are falsy)
            if (@hasDecl(ChildT, "__len__")) {
                const len = value.__len__() catch return false;
                return len > 0;
            }
        }
    }

    // Handle PyString
    if (T == PyString) {
        return value.len() > 0;
    }

    // Handle PyInt
    if (T == PyInt) {
        return value.value != 0;
    }

    // Handle PyBool
    if (T == PyBool) {
        return value.value;
    }

    // Handle optional
    if (info == .optional) {
        return value != null;
    }

    // Handle structs with __bool__ method (Python protocol)
    if (info == .@"struct") {
        if (@hasDecl(T, "__bool__")) {
            // Check if __bool__ takes a mutable pointer (self-mutating method)
            const bool_fn_info = @typeInfo(@TypeOf(T.__bool__));
            const first_param_type = bool_fn_info.@"fn".params[0].type.?;
            const first_param_info = @typeInfo(first_param_type);

            const result = blk: {
                if (first_param_info == .pointer and !first_param_info.pointer.is_const) {
                    // __bool__ takes *@This() (mutable) - need to cast away const
                    // This matches Python's pass-by-reference semantics where
                    // objects can be mutated through any reference
                    var mutable = @constCast(&value);
                    break :blk mutable.__bool__();
                } else {
                    // __bool__ takes *const @This() or value - call directly
                    break :blk value.__bool__();
                }
            };
            const ResultT = @TypeOf(result);
            if (@typeInfo(ResultT) == .bool) {
                return result;
            }
            // Handle error union wrapping bool
            if (@typeInfo(ResultT) == .error_union) {
                const unwrapped = result catch return false;
                const UnwrappedT = @TypeOf(unwrapped);
                if (@typeInfo(UnwrappedT) == .bool) {
                    return unwrapped;
                }
                // __bool__ returned error union with non-bool payload
                @panic("TypeError: __bool__ should return bool, not error union with non-bool");
            }
            // Python 3: __bool__ MUST return bool (True or False)
            // Returning anything else (including int 0/1) is a TypeError
            @panic("TypeError: __bool__ should return bool");
        }
        // Check for __len__ as fallback (containers with 0 length are falsy)
        if (@hasDecl(T, "__len__")) {
            const len = value.__len__() catch return false;
            return len > 0;
        }
        // Check for .items field (ArrayListUnmanaged, etc.) - empty list is falsy
        if (@hasField(T, "items")) {
            return value.items.len > 0;
        }
        // Check for .count() method (HashMap/ArrayHashMap) - empty dict is falsy
        if (@hasDecl(T, "count")) {
            return value.count() > 0;
        }
    }

    // Handle arrays (fixed-size arrays) - empty is falsy, non-empty is truthy
    if (info == .array) {
        return info.array.len > 0;
    }

    // Handle tuples (anonymous structs with numbered fields) - empty tuple is falsy
    // This catches `struct {}` (empty tuple) and `struct { i64, i64 }` etc.
    if (info == .@"struct" and info.@"struct".is_tuple) {
        return info.@"struct".fields.len > 0;
    }

    // Default: truthy for everything else (non-empty types)
    return true;
}

/// Validate that __bool__ returns bool (Python 3 requirement)
/// Returns error.TypeError if value is not bool
pub fn validateBoolReturn(value: anytype) PythonError!bool {
    const T = @TypeOf(value);
    if (@typeInfo(T) == .bool) {
        return value;
    }
    // Python 3: __bool__ MUST return bool (True or False)
    return PythonError.TypeError;
}

/// Validate that __float__ returns float (Python 3 requirement)
/// Returns error.TypeError if value is not float
pub fn validateFloatReturn(value: anytype) PythonError!f64 {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);
    if (type_info == .float or type_info == .comptime_float) {
        return value;
    }
    // Handle PyValue union (when __float__ returns stored value)
    if (T == PyValue) {
        switch (value) {
            .float => |f| return f,
            else => return PythonError.TypeError,
        }
    }
    // Handle struct with __base_value__ (float subclass)
    if (type_info == .@"struct") {
        if (@hasField(T, "__base_value__")) {
            const base_val = value.__base_value__;
            const base_type = @typeInfo(@TypeOf(base_val));
            if (base_type == .float or base_type == .comptime_float) {
                return @as(f64, base_val);
            }
        }
    }
    // Python 3: __float__ MUST return float (not int or other types)
    // "ClassName.__float__ returned non-float (type int)"
    return PythonError.TypeError;
}

/// Generic int conversion for __len__, __hash__, etc.
/// Handles both native int types and PyValue
/// Returns error for non-convertible types (e.g., string for __len__)
pub fn pyToInt(value: anytype) PythonError!i64 {
    const T = @TypeOf(value);
    if (T == PyValue) {
        // Extract int from PyValue, return error on non-convertible types
        if (value.toInt()) |i| {
            return i;
        } else {
            // Set exception message like Python: "'str' object cannot be interpreted as an integer"
            // Use pre-computed messages for each type since Zig can't concat runtime strings
            const msg = switch (value) {
                .string => "'str' object cannot be interpreted as an integer",
                .bytes => "'bytes' object cannot be interpreted as an integer",
                .float => "'float' object cannot be interpreted as an integer",
                .bool => "'bool' object cannot be interpreted as an integer",
                .none => "'NoneType' object cannot be interpreted as an integer",
                .list => "'list' object cannot be interpreted as an integer",
                .tuple => "'tuple' object cannot be interpreted as an integer",
                .ptr => "'object' object cannot be interpreted as an integer",
                .int => "'int' object cannot be interpreted as an integer", // shouldn't happen
            };
            setException("TypeError", msg);
            return PythonError.TypeError;
        }
    } else if (T == i64 or T == i32 or T == i16 or T == i8 or T == u64 or T == u32 or T == u16 or T == u8 or T == usize or T == isize or T == comptime_int) {
        return @intCast(value);
    } else if (T == bool) {
        return if (value) 1 else 0;
    } else if (@typeInfo(T) == .optional) {
        if (value) |v| return try pyToInt(v);
        return 0;
    } else {
        // Return error for unsupported types at runtime
        // Map Zig types to Python type names for better error messages
        const type_info = @typeInfo(T);
        const py_type_name = comptime blk: {
            // Pointers to arrays are strings
            if (type_info == .pointer and type_info.pointer.size == .one) {
                const child = @typeInfo(type_info.pointer.child);
                if (child == .array and child.array.child == u8) {
                    break :blk "str";
                }
            }
            // Slices of u8 are strings
            if (type_info == .pointer and type_info.pointer.size == .slice and type_info.pointer.child == u8) {
                break :blk "str";
            }
            // Default to Zig type name
            break :blk @typeName(T);
        };
        setException("TypeError", "'" ++ py_type_name ++ "' object cannot be interpreted as an integer");
        return PythonError.TypeError;
    }
}

/// Generic int conversion for Python int() semantics
/// Handles: integers (pass through), strings (parse), bools, floats
// =============================================================================
// CPython-Compatible PyObject Layout
// =============================================================================
// These structures use `extern struct` for C ABI compatibility.
// Field order and sizes MUST match CPython exactly for C extension compatibility.
// Reference: https://github.com/python/cpython/blob/main/Include/object.h
// =============================================================================

/// Py_ssize_t equivalent - signed size type matching C's ssize_t
pub const Py_ssize_t = isize;

/// PyObject - Base object header (CPython compatible)
/// Layout: ob_refcnt (8 bytes) + ob_type (8 bytes) = 16 bytes
pub const PyObject = extern struct {
    ob_refcnt: Py_ssize_t,
    ob_type: *PyTypeObject,

    /// Value type for initializing lists/tuples from literals (backwards compat)
    pub const Value = struct {
        int: i64,
    };
};

/// PyVarObject - Variable-size object header (CPython compatible)
/// Used for list, tuple, string, etc.
pub const PyVarObject = extern struct {
    ob_base: PyObject,
    ob_size: Py_ssize_t,
};

/// Type object flags (subset of CPython's Py_TPFLAGS_*)
pub const Py_TPFLAGS = struct {
    pub const HEAPTYPE: u64 = 1 << 9;
    pub const BASETYPE: u64 = 1 << 10;
    pub const HAVE_GC: u64 = 1 << 14;
    pub const DEFAULT: u64 = 0;
};

/// PyTypeObject - Type descriptor (simplified CPython compatible)
/// Full CPython PyTypeObject has ~50 fields; we implement the critical ones
pub const PyTypeObject = extern struct {
    ob_base: PyVarObject,
    tp_name: [*:0]const u8,
    tp_basicsize: Py_ssize_t,
    tp_itemsize: Py_ssize_t,
    // Destructor
    tp_dealloc: ?*const fn (*PyObject) callconv(.c) void,
    // Placeholder for vectorcall_offset
    tp_vectorcall_offset: Py_ssize_t,
    // Reserved slots (for getattr, setattr, etc.)
    tp_getattr: ?*anyopaque,
    tp_setattr: ?*anyopaque,
    tp_as_async: ?*anyopaque,
    tp_repr: ?*const fn (*PyObject) callconv(.c) *PyObject,
    // Number/sequence/mapping protocols
    tp_as_number: ?*anyopaque,
    tp_as_sequence: ?*anyopaque,
    tp_as_mapping: ?*anyopaque,
    tp_hash: ?*const fn (*PyObject) callconv(.c) Py_ssize_t,
    tp_call: ?*anyopaque,
    tp_str: ?*const fn (*PyObject) callconv(.c) *PyObject,
    tp_getattro: ?*anyopaque,
    tp_setattro: ?*anyopaque,
    tp_as_buffer: ?*anyopaque,
    tp_flags: u64,
    tp_doc: ?[*:0]const u8,
    // Traversal and clear for GC
    tp_traverse: ?*anyopaque,
    tp_clear: ?*anyopaque,
    tp_richcompare: ?*anyopaque,
    tp_weaklistoffset: Py_ssize_t,
    tp_iter: ?*anyopaque,
    tp_iternext: ?*anyopaque,
    tp_methods: ?*anyopaque,
    tp_members: ?*anyopaque,
    tp_getset: ?*anyopaque,
    tp_base: ?*PyTypeObject,
    tp_dict: ?*PyObject,
    tp_descr_get: ?*anyopaque,
    tp_descr_set: ?*anyopaque,
    tp_dictoffset: Py_ssize_t,
    tp_init: ?*anyopaque,
    tp_alloc: ?*anyopaque,
    tp_new: ?*anyopaque,
    tp_free: ?*anyopaque,
    tp_is_gc: ?*anyopaque,
    tp_bases: ?*PyObject,
    tp_mro: ?*PyObject,
    tp_cache: ?*PyObject,
    tp_subclasses: ?*anyopaque,
    tp_weaklist: ?*PyObject,
    tp_del: ?*anyopaque,
    tp_version_tag: u32,
    tp_finalize: ?*anyopaque,
    tp_vectorcall: ?*anyopaque,
};

// =============================================================================
// Concrete Python Type Objects (CPython ABI compatible)
// =============================================================================

/// PyLongObject - Python integer (CPython compatible)
/// CPython uses variable-length digit array; we use fixed i64 for simplicity
/// Note: For full bigint support, may need variable-length digits later
pub const PyLongObject = extern struct {
    ob_base: PyVarObject,
    // In CPython this is a variable-length digit array
    // We simplify to a single i64 for now (covers most use cases)
    ob_digit: i64,
};

/// PyFloatObject - Python float (CPython compatible)
pub const PyFloatObject = extern struct {
    ob_base: PyObject,
    ob_fval: f64,
};

/// PyComplexObject - Python complex number (CPython compatible)
pub const PyComplexObject = extern struct {
    ob_base: PyObject,
    cval_real: f64,
    cval_imag: f64,
};

/// PyBoolObject - Python bool (same layout as PyLongObject in CPython)
pub const PyBoolObject = extern struct {
    ob_base: PyVarObject,
    ob_digit: i64, // 0 for False, 1 for True
};

/// PyBigIntObject - Python int for arbitrary precision (when > i64 range)
/// Used by bytecode VM for eval() with large integers
pub const PyBigIntObject = struct {
    ob_base: PyVarObject,
    value: BigInt, // Heap-allocated arbitrary precision integer
};

/// PyListObject - Python list (CPython compatible)
pub const PyListObject = extern struct {
    ob_base: PyVarObject,
    ob_item: [*]*PyObject, // Array of PyObject pointers
    allocated: Py_ssize_t, // Allocated capacity
};

/// PyTupleObject - Python tuple (CPython compatible)
pub const PyTupleObject = extern struct {
    ob_base: PyVarObject,
    ob_item: [*]*PyObject, // Inline array of PyObject pointers
};

/// PyDictObject - Python dict (simplified, not full CPython layout)
/// CPython's dict is complex with compact dict + indices; we use simpler layout
pub const PyDictObject = extern struct {
    ob_base: PyObject,
    ma_used: Py_ssize_t, // Number of items
    // Internal hash map storage (not CPython compatible, but functional)
    ma_keys: ?*anyopaque, // Pointer to our hashmap
    ma_values: ?*anyopaque, // Reserved for split-table dict
};

/// PyBytesObject - Python bytes (CPython compatible)
pub const PyBytesObject = extern struct {
    ob_base: PyVarObject,
    ob_shash: Py_ssize_t, // Cached hash (-1 if not computed)
    ob_sval: [1]u8, // Variable-length byte array (at least 1 byte)
};

/// PyUnicodeObject - Python string (simplified)
/// Full CPython Unicode is very complex (compact/legacy/etc.)
/// We use a simplified UTF-8 representation
pub const PyUnicodeObject = extern struct {
    ob_base: PyObject,
    length: Py_ssize_t, // Number of code points
    hash: Py_ssize_t, // Cached hash (-1 if not computed)
    // State flags (interned, kind, compact, ascii, ready)
    state: u32,
    _padding: u32, // Alignment padding
    // UTF-8 data pointer (simplified from CPython's complex union)
    data: [*]const u8,
};

/// PyNoneStruct - The None singleton
pub const PyNoneStruct = extern struct {
    ob_base: PyObject,
};

/// PyFileObject - File handle (metal0 specific, not CPython compatible)
pub const PyFileObject = extern struct {
    ob_base: PyObject,
    // File-specific fields (not matching CPython's io module)
    fd: i32,
    mode: u32,
    name: ?[*:0]const u8,
};

// =============================================================================
// Global Type Objects (singletons)
// =============================================================================

/// Forward declaration for type object initialization
fn nullDealloc(_: *PyObject) callconv(.c) void {}

/// Base type object template
fn makeTypeObject(comptime name: [*:0]const u8, comptime basicsize: Py_ssize_t, comptime itemsize: Py_ssize_t) PyTypeObject {
    return PyTypeObject{
        .ob_base = .{
            .ob_base = .{
                .ob_refcnt = 1, // Immortal
                .ob_type = undefined, // Will be set to &PyType_Type
            },
            .ob_size = 0,
        },
        .tp_name = name,
        .tp_basicsize = basicsize,
        .tp_itemsize = itemsize,
        .tp_dealloc = nullDealloc,
        .tp_vectorcall_offset = 0,
        .tp_getattr = null,
        .tp_setattr = null,
        .tp_as_async = null,
        .tp_repr = null,
        .tp_as_number = null,
        .tp_as_sequence = null,
        .tp_as_mapping = null,
        .tp_hash = null,
        .tp_call = null,
        .tp_str = null,
        .tp_getattro = null,
        .tp_setattro = null,
        .tp_as_buffer = null,
        .tp_flags = Py_TPFLAGS.DEFAULT,
        .tp_doc = null,
        .tp_traverse = null,
        .tp_clear = null,
        .tp_richcompare = null,
        .tp_weaklistoffset = 0,
        .tp_iter = null,
        .tp_iternext = null,
        .tp_methods = null,
        .tp_members = null,
        .tp_getset = null,
        .tp_base = null,
        .tp_dict = null,
        .tp_descr_get = null,
        .tp_descr_set = null,
        .tp_dictoffset = 0,
        .tp_init = null,
        .tp_alloc = null,
        .tp_new = null,
        .tp_free = null,
        .tp_is_gc = null,
        .tp_bases = null,
        .tp_mro = null,
        .tp_cache = null,
        .tp_subclasses = null,
        .tp_weaklist = null,
        .tp_del = null,
        .tp_version_tag = 0,
        .tp_finalize = null,
        .tp_vectorcall = null,
    };
}

// Type object singletons
pub var PyLong_Type: PyTypeObject = makeTypeObject("int", @sizeOf(PyLongObject), 0);
pub var PyFloat_Type: PyTypeObject = makeTypeObject("float", @sizeOf(PyFloatObject), 0);
pub var PyComplex_Type: PyTypeObject = makeTypeObject("complex", @sizeOf(PyComplexObject), 0);
pub var PyBool_Type: PyTypeObject = makeTypeObject("bool", @sizeOf(PyBoolObject), 0);
pub var PyList_Type: PyTypeObject = makeTypeObject("list", @sizeOf(PyListObject), @sizeOf(*PyObject));
pub var PyTuple_Type: PyTypeObject = makeTypeObject("tuple", @sizeOf(PyTupleObject), @sizeOf(*PyObject));
pub var PyDict_Type: PyTypeObject = makeTypeObject("dict", @sizeOf(PyDictObject), 0);
pub var PyUnicode_Type: PyTypeObject = makeTypeObject("str", @sizeOf(PyUnicodeObject), 0);
pub var PyBytes_Type: PyTypeObject = makeTypeObject("bytes", @sizeOf(PyBytesObject), 1);
pub var PyNone_Type: PyTypeObject = makeTypeObject("NoneType", @sizeOf(PyNoneStruct), 0);
pub var PyType_Type: PyTypeObject = makeTypeObject("type", @sizeOf(PyTypeObject), 0);
pub var PyFile_Type: PyTypeObject = makeTypeObject("file", @sizeOf(PyFileObject), 0);
pub var PyBigInt_Type: PyTypeObject = makeTypeObject("int", @sizeOf(PyBigIntObject), 0);

// None singleton
pub var _Py_NoneStruct: PyNoneStruct = .{
    .ob_base = .{
        .ob_refcnt = 1, // Immortal
        .ob_type = &PyNone_Type,
    },
};
pub const Py_None: *PyObject = @ptrCast(&_Py_NoneStruct);

// =============================================================================
// CPython-compatible Reference Counting Macros
// =============================================================================

pub inline fn Py_INCREF(op: *PyObject) void {
    op.ob_refcnt += 1;
}

pub inline fn Py_DECREF(op: *PyObject) void {
    op.ob_refcnt -= 1;
    if (op.ob_refcnt == 0) {
        if (op.ob_type.tp_dealloc) |dealloc| {
            dealloc(op);
        }
    }
}

pub inline fn Py_XINCREF(op: ?*PyObject) void {
    if (op) |o| Py_INCREF(o);
}

pub inline fn Py_XDECREF(op: ?*PyObject) void {
    if (op) |o| Py_DECREF(o);
}

/// Type checking macros
pub inline fn Py_TYPE(op: *PyObject) *PyTypeObject {
    return op.ob_type;
}

pub inline fn Py_IS_TYPE(op: *PyObject, typ: *PyTypeObject) bool {
    return Py_TYPE(op) == typ;
}

pub inline fn PyLong_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyLong_Type);
}

pub inline fn PyFloat_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyFloat_Type);
}

pub inline fn PyComplex_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyComplex_Type);
}

pub inline fn PyBool_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyBool_Type);
}

pub inline fn PyList_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyList_Type);
}

pub inline fn PyTuple_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyTuple_Type);
}

pub inline fn PyDict_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyDict_Type);
}

pub inline fn PyUnicode_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyUnicode_Type);
}

pub inline fn PyBytes_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyBytes_Type);
}

pub inline fn PyBigInt_Check(op: *PyObject) bool {
    return Py_IS_TYPE(op, &PyBigInt_Type);
}

/// Get ob_size from PyVarObject
pub inline fn Py_SIZE(op: *PyObject) Py_ssize_t {
    const var_obj: *PyVarObject = @ptrCast(@alignCast(op));
    return var_obj.ob_size;
}

/// Set ob_size on PyVarObject
pub inline fn Py_SET_SIZE(op: *PyObject, size: Py_ssize_t) void {
    const var_obj: *PyVarObject = @ptrCast(@alignCast(op));
    var_obj.ob_size = size;
}

/// Convert PyObject pointer to a list (for list() builtin on PyObject)
/// Returns PyValue.list containing the elements
pub fn pyObjectToList(obj: *PyObject) PyValue {
    // Check if it's a list
    if (PyList_Check(obj)) {
        const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
        const size = list_obj.ob_base.ob_size;
        if (size <= 0) return .{ .list = &[_]PyValue{} };
        // For now, return an empty list as full conversion requires allocation
        // TODO: properly convert list elements
        return .{ .list = &[_]PyValue{} };
    }
    // Check if it's a tuple
    if (PyTuple_Check(obj)) {
        const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
        const size = tuple_obj.ob_base.ob_size;
        if (size <= 0) return .{ .list = &[_]PyValue{} };
        return .{ .list = &[_]PyValue{} };
    }
    // Default: return empty list
    return .{ .list = &[_]PyValue{} };
}

/// Extract value from PyObject for comparisons
/// Returns f64 for numeric types (allows uniform comparison)
pub fn pyObjectToValue(obj: *PyObject) f64 {
    if (PyFloat_Check(obj)) {
        const float_obj: *PyFloatObject = @ptrCast(@alignCast(obj));
        return float_obj.ob_fval;
    }
    if (PyLong_Check(obj)) {
        const long_obj: *PyLongObject = @ptrCast(@alignCast(obj));
        return @floatFromInt(long_obj.ob_digit);
    }
    if (PyBool_Check(obj)) {
        const bool_obj: *PyBoolObject = @ptrCast(@alignCast(obj));
        return @floatFromInt(bool_obj.ob_digit);
    }
    // Default to 0 for non-numeric types
    return 0.0;
}

/// Convert PyObject to string representation (like Python's str())
pub fn pyObjToStr(allocator: std.mem.Allocator, obj: *PyObject) ![]const u8 {
    if (PyLong_Check(obj)) {
        const val = PyInt.getValue(obj);
        return std.fmt.allocPrint(allocator, "{d}", .{val});
    }
    if (PyFloat_Check(obj)) {
        const val = PyFloat.getValue(obj);
        // Python convention: nan never has sign
        if (std.math.isNan(val)) return try allocator.dupe(u8, "nan");
        if (std.math.isInf(val)) return try allocator.dupe(u8, if (val < 0) "-inf" else "inf");
        return std.fmt.allocPrint(allocator, "{d}", .{val});
    }
    if (PyBool_Check(obj)) {
        const val = PyBool.getValue(obj);
        return if (val) "True" else "False";
    }
    if (PyUnicode_Check(obj)) {
        return PyString.getValue(obj);
    }
    // Fallback for other types
    return std.fmt.allocPrint(allocator, "<PyObject@{*}>", .{obj});
}

// =============================================================================
// Backwards Compatibility - Legacy TypeId enum
// =============================================================================
// This provides a bridge for existing code that uses the old type_id system

pub const TypeId = enum {
    int,
    float,
    bool,
    string,
    list,
    tuple,
    dict,
    none,
    file,
    regex,
    bytes,
    bigint,

    /// Convert PyObject to legacy TypeId
    pub fn fromPyObject(obj: *PyObject) TypeId {
        if (Py_IS_TYPE(obj, &PyLong_Type)) return .int;
        if (Py_IS_TYPE(obj, &PyFloat_Type)) return .float;
        if (Py_IS_TYPE(obj, &PyBool_Type)) return .bool;
        if (Py_IS_TYPE(obj, &PyUnicode_Type)) return .string;
        if (Py_IS_TYPE(obj, &PyList_Type)) return .list;
        if (Py_IS_TYPE(obj, &PyTuple_Type)) return .tuple;
        if (Py_IS_TYPE(obj, &PyDict_Type)) return .dict;
        if (Py_IS_TYPE(obj, &PyNone_Type)) return .none;
        if (Py_IS_TYPE(obj, &PyBytes_Type)) return .bytes;
        if (Py_IS_TYPE(obj, &PyBigInt_Type)) return .bigint;
        return .none; // Default fallback
    }
};

/// Legacy type_id accessor for backwards compatibility
pub fn getTypeId(obj: *PyObject) TypeId {
    return TypeId.fromPyObject(obj);
}

// =============================================================================
// Legacy Reference Counting (bridges to new CPython-compatible functions)
// =============================================================================

/// Legacy incref - bridges to Py_INCREF
pub fn incref(obj: *PyObject) void {
    Py_INCREF(obj);
}

/// Legacy decref with allocator - uses new type-based deallocation
pub fn decref(obj: *PyObject, allocator: std.mem.Allocator) void {
    if (obj.ob_refcnt <= 0) {
        std.debug.print("WARNING: Attempting to decref object with ref_count already 0\n", .{});
        return;
    }
    obj.ob_refcnt -= 1;
    if (obj.ob_refcnt == 0) {
        // Use type-based deallocation
        const type_id = getTypeId(obj);
        switch (type_id) {
            .int => {
                // PyLongObject is self-contained, just free it
                const long_obj: *PyLongObject = @ptrCast(@alignCast(obj));
                allocator.destroy(long_obj);
            },
            .float => {
                const float_obj: *PyFloatObject = @ptrCast(@alignCast(obj));
                allocator.destroy(float_obj);
            },
            .bool => {
                const bool_obj: *PyBoolObject = @ptrCast(@alignCast(obj));
                allocator.destroy(bool_obj);
            },
            .list => {
                const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
                const size: usize = @intCast(list_obj.ob_base.ob_size);
                // Decref all items
                for (0..size) |i| {
                    decref(list_obj.ob_item[i], allocator);
                }
                // Free the item array
                if (list_obj.allocated > 0) {
                    const alloc_size: usize = @intCast(list_obj.allocated);
                    allocator.free(list_obj.ob_item[0..alloc_size]);
                }
                allocator.destroy(list_obj);
            },
            .tuple => {
                const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
                const size: usize = @intCast(tuple_obj.ob_base.ob_size);
                // Decref all items
                for (0..size) |i| {
                    decref(tuple_obj.ob_item[i], allocator);
                }
                // Free the tuple (items are inline in CPython, but we allocate separately)
                allocator.free(tuple_obj.ob_item[0..size]);
                allocator.destroy(tuple_obj);
            },
            .string => {
                const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
                // Free the string data if owned
                const len: usize = @intCast(str_obj.length);
                if (len > 0) {
                    allocator.free(str_obj.data[0..len]);
                }
                allocator.destroy(str_obj);
            },
            .dict => {
                const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));
                // Free internal hashmap if present
                if (dict_obj.ma_keys) |keys_ptr| {
                    const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(keys_ptr));
                    var it = map.iterator();
                    while (it.next()) |entry| {
                        allocator.free(entry.key_ptr.*);
                        decref(entry.value_ptr.*, allocator);
                    }
                    map.deinit();
                    allocator.destroy(map);
                }
                allocator.destroy(dict_obj);
            },
            .none => {
                // Never free the None singleton
            },
            else => {
                // Generic deallocation for unknown types
                // Just free the base PyObject
            },
        }
    }
}

/// Check if a PyObject is truthy (Python truthiness semantics)
/// Returns false for: None, False, 0, empty string, empty list/dict
/// Returns true for everything else
pub fn pyTruthy(obj: *PyObject) bool {
    const type_id = getTypeId(obj);
    switch (type_id) {
        .none => return false,
        .bool => {
            const bool_obj: *PyBoolObject = @ptrCast(@alignCast(obj));
            return bool_obj.ob_digit != 0;
        },
        .int => {
            const long_obj: *PyLongObject = @ptrCast(@alignCast(obj));
            return long_obj.ob_digit != 0;
        },
        .float => {
            const float_obj: *PyFloatObject = @ptrCast(@alignCast(obj));
            return float_obj.ob_fval != 0.0;
        },
        .string => {
            const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
            return str_obj.length > 0;
        },
        .list => {
            const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
            return list_obj.ob_base.ob_size > 0;
        },
        .dict => {
            const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));
            return dict_obj.ma_used > 0;
        },
        .tuple => {
            const tuple_obj: *PyTupleObject = @ptrCast(@alignCast(obj));
            return tuple_obj.ob_base.ob_size > 0;
        },
        else => return true, // All other types (file, regex, etc.) are truthy
    }
}

/// Helper function to print PyObject based on runtime type
pub fn printPyObject(obj: *PyObject) void {
    printPyObjectImpl(obj, false);
}

/// Internal: print PyObject with quote_strings flag for container elements
fn printPyObjectImpl(obj: *PyObject, quote_strings: bool) void {
    const type_id = getTypeId(obj);
    switch (type_id) {
        .int => {
            const long_obj: *PyLongObject = @ptrCast(@alignCast(obj));
            std.debug.print("{}", .{long_obj.ob_digit});
        },
        .float => {
            const float_obj: *PyFloatObject = @ptrCast(@alignCast(obj));
            std.debug.print("{d}", .{float_obj.ob_fval});
        },
        .bool => {
            const bool_obj: *PyBoolObject = @ptrCast(@alignCast(obj));
            std.debug.print("{s}", .{if (bool_obj.ob_digit != 0) "True" else "False"});
        },
        .string => {
            const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(obj));
            const len: usize = @intCast(str_obj.length);
            if (quote_strings) {
                std.debug.print("'{s}'", .{str_obj.data[0..len]});
            } else {
                std.debug.print("{s}", .{str_obj.data[0..len]});
            }
        },
        .none => {
            std.debug.print("None", .{});
        },
        .list => {
            printList(obj);
        },
        .tuple => {
            PyTuple.print(obj);
        },
        .dict => {
            printDict(obj);
        },
        else => {
            // For C extension types, try to call tp_str or tp_repr
            const type_obj = Py_TYPE(obj);
            if (type_obj.tp_str) |str_func| {
                const str_result = str_func(obj);
                // Check if result is a string type (PyUnicode) and print it
                const result_type = Py_TYPE(str_result);
                if (result_type == &PyUnicode_Type or
                    std.mem.eql(u8, std.mem.span(result_type.tp_name), "str"))
                {
                    const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(str_result));
                    const len: usize = @intCast(str_obj.length);
                    std.debug.print("{s}", .{str_obj.data[0..len]});
                    return;
                }
            }
            if (type_obj.tp_repr) |repr_func| {
                const repr_result = repr_func(obj);
                const result_type = Py_TYPE(repr_result);
                if (result_type == &PyUnicode_Type or
                    std.mem.eql(u8, std.mem.span(result_type.tp_name), "str"))
                {
                    const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(repr_result));
                    const len: usize = @intCast(str_obj.length);
                    std.debug.print("{s}", .{str_obj.data[0..len]});
                    return;
                }
            }
            // Fallback: print type name and pointer
            std.debug.print("<{s} at {*}>", .{ std.mem.span(type_obj.tp_name), obj });
        },
    }
}

/// Helper function to print a dict in Python format: {'key': value, ...}
fn printDict(obj: *PyObject) void {
    std.debug.assert(PyDict_Check(obj));
    const dict_obj: *PyDictObject = @ptrCast(@alignCast(obj));

    std.debug.print("{{", .{});
    if (dict_obj.ma_keys) |keys_ptr| {
        const map: *hashmap_helper.StringHashMap(*PyObject) = @ptrCast(@alignCast(keys_ptr));
        var iter = map.iterator();
        var idx: usize = 0;
        while (iter.next()) |entry| {
            if (idx > 0) {
                std.debug.print(", ", .{});
            }
            // Print key with quotes (string keys)
            std.debug.print("'{s}': ", .{entry.key_ptr.*});
            // Recursively print value (with quoted strings)
            printPyObjectImpl(entry.value_ptr.*, true);
            idx += 1;
        }
    }
    std.debug.print("}}", .{});
}

/// Helper function to print a list in Python format: [elem1, elem2, elem3]
pub fn printList(obj: *PyObject) void {
    std.debug.assert(PyList_Check(obj));
    const list_obj: *PyListObject = @ptrCast(@alignCast(obj));
    const size: usize = @intCast(list_obj.ob_base.ob_size);

    std.debug.print("[", .{});
    for (0..size) |i| {
        if (i > 0) {
            std.debug.print(", ", .{});
        }
        const item = list_obj.ob_item[i];
        // Print each element based on its type
        const item_type = getTypeId(item);
        switch (item_type) {
            .int => {
                const long_obj: *PyLongObject = @ptrCast(@alignCast(item));
                std.debug.print("{}", .{long_obj.ob_digit});
            },
            .string => {
                const str_obj: *PyUnicodeObject = @ptrCast(@alignCast(item));
                const len: usize = @intCast(str_obj.length);
                std.debug.print("'{s}'", .{str_obj.data[0..len]});
            },
            .tuple => {
                PyTuple.print(item);
            },
            else => {
                std.debug.print("{*}", .{item});
            },
        }
    }
    std.debug.print("]", .{});
}

/// Python integer type - re-exported from pyint.zig
pub const PyInt = pyint.PyInt;

/// Python float type - re-exported from pyfloat.zig
pub const PyFloat = pyfloat.PyFloat;

/// Python bool type - re-exported from pybool.zig
pub const PyBool = pybool.PyBool;

/// Bool singletons - re-exported from pybool.zig
pub const Py_True = pybool.Py_True;
pub const Py_False = pybool.Py_False;

/// Feature macros struct - CPython build configuration with comptime-known values
/// Supports subscript access: feature_macros["HAVE_FORK"] returns bool
pub const FeatureMacros = struct {
    /// Comptime subscript access - used when key is known at compile time
    pub fn index(_: FeatureMacros, comptime key: []const u8) bool {
        if (comptime std.mem.eql(u8, key, "HAVE_FORK")) return true;
        if (comptime std.mem.eql(u8, key, "MS_WINDOWS")) return false;
        if (comptime std.mem.eql(u8, key, "PY_HAVE_THREAD_NATIVE_ID")) return true;
        if (comptime std.mem.eql(u8, key, "Py_REF_DEBUG")) return false;
        if (comptime std.mem.eql(u8, key, "Py_TRACE_REFS")) return false;
        if (comptime std.mem.eql(u8, key, "USE_STACKCHECK")) return false;
        return false;
    }

    /// Runtime key lookup - returns bool for known keys
    pub fn get(_: FeatureMacros, key: []const u8) bool {
        if (std.mem.eql(u8, key, "HAVE_FORK")) return true;
        if (std.mem.eql(u8, key, "MS_WINDOWS")) return false;
        if (std.mem.eql(u8, key, "PY_HAVE_THREAD_NATIVE_ID")) return true;
        if (std.mem.eql(u8, key, "Py_REF_DEBUG")) return false;
        if (std.mem.eql(u8, key, "Py_TRACE_REFS")) return false;
        if (std.mem.eql(u8, key, "USE_STACKCHECK")) return false;
        return false;
    }

    /// Static key list for iteration
    pub const key_list: [6][]const u8 = .{
        "HAVE_FORK",
        "MS_WINDOWS",
        "PY_HAVE_THREAD_NATIVE_ID",
        "Py_REF_DEBUG",
        "Py_TRACE_REFS",
        "USE_STACKCHECK",
    };

    /// Iterator for keys() - returns comptime slice of keys
    pub fn keys() []const []const u8 {
        return &key_list;
    }
};

/// Python file type - re-exported from pyfile.zig
pub const PyFile = pyfile.PyFile;

/// Helper functions for operations that can raise exceptions
/// True division (Python's / operator) - always returns float
/// Integer division (floor division //) with zero check
/// Modulo with zero check
/// Split string on whitespace (Python str.split() with no args)
/// Returns ArrayList of string slices, removes empty strings
pub fn stringSplitWhitespace(text: []const u8, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8){};

    // Split on any whitespace, skip empty parts (like Python's split())
    var iter = std.mem.tokenizeAny(u8, text, " \t\n\r\x0c\x0b");
    while (iter.next()) |part| {
        try result.append(allocator, part);
    }

    return result;
}

/// Convert any value to i64 (Python int() constructor)
/// Handles strings, floats, ints, and types with __int__ method
/// Repeat string n times (Python str * n or bytes * n)
/// Accepts both []const u8 and PyBytes for bytes literal support
pub fn strRepeat(allocator: std.mem.Allocator, s: anytype, n: usize) []const u8 {
    // Extract the actual slice from either []const u8, PyBytes, or string literal pointer at comptime type check
    const T = @TypeOf(s);
    const actual_slice: []const u8 = if (T == []const u8)
        s
    else if (@typeInfo(T) == .@"struct" and @hasField(T, "data"))
        // PyBytes has a .data field
        s.data
    else if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .one) blk: {
        // Pointer to array (string literal like *const [N:0]u8) - coerce to slice
        const child_info = @typeInfo(@typeInfo(T).pointer.child);
        if (child_info == .array and child_info.array.child == u8) {
            break :blk s;
        } else {
            @compileError("strRepeat expects []const u8, PyBytes, or string literal, got " ++ @typeName(T));
        }
    } else @compileError("strRepeat expects []const u8, PyBytes, or string literal, got " ++ @typeName(T));

    if (n == 0) return "";
    if (n == 1) return actual_slice;

    const result = allocator.alloc(u8, actual_slice.len * n) catch return "";
    for (0..n) |i| {
        @memcpy(result[i * actual_slice.len ..][0..actual_slice.len], actual_slice);
    }
    return result;
}

/// Concatenate two tuples (Python tuple + tuple)
/// Returns a new tuple struct with all elements from both tuples
/// Uses comptime to create the correct result type
pub fn tupleConcat(a: anytype, b: anytype) TupleConcatResult(@TypeOf(a), @TypeOf(b)) {
    const A = @TypeOf(a);
    const B = @TypeOf(b);
    const a_fields = @typeInfo(A).@"struct".fields;
    const b_fields = @typeInfo(B).@"struct".fields;
    const Result = TupleConcatResult(A, B);

    // Build result tuple using comptime field initialization
    var result: Result = undefined;
    inline for (a_fields, 0..) |field, i| {
        @field(result, std.fmt.comptimePrint("{d}", .{i})) = @field(a, field.name);
    }
    inline for (b_fields, 0..) |field, i| {
        @field(result, std.fmt.comptimePrint("{d}", .{a_fields.len + i})) = @field(b, field.name);
    }

    return result;
}

/// Helper type for tuple concatenation result
/// Returns an anonymous struct (tuple) type with fields named "0", "1", etc.
fn TupleConcatResult(comptime A: type, comptime B: type) type {
    const a_info = @typeInfo(A);
    const b_info = @typeInfo(B);
    if (a_info != .@"struct" or b_info != .@"struct") {
        @compileError("tupleConcat expects two tuple/struct types");
    }

    const a_fields = a_info.@"struct".fields;
    const b_fields = b_info.@"struct".fields;
    const total_len = a_fields.len + b_fields.len;

    // Build struct field definitions
    var fields: [total_len]std.builtin.Type.StructField = undefined;
    inline for (a_fields, 0..) |afield, i| {
        fields[i] = .{
            .name = std.fmt.comptimePrint("{d}", .{i}),
            .type = afield.type,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(afield.type),
        };
    }
    inline for (b_fields, 0..) |bfield, i| {
        fields[a_fields.len + i] = .{
            .name = std.fmt.comptimePrint("{d}", .{a_fields.len + i}),
            .type = bfield.type,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(bfield.type),
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

/// Repeat tuple n times at comptime (Python tuple * n where n is known at compile time)
/// Returns a new tuple struct with elements repeated n times
pub fn tupleMultiply(comptime n: usize, tuple: anytype) TupleMultiplyResult(@TypeOf(tuple), n) {
    const T = @TypeOf(tuple);
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("tupleMultiply expects a tuple/struct");

    const src_fields = info.@"struct".fields;
    const tuple_len = src_fields.len;
    const Result = TupleMultiplyResult(T, n);

    var result: Result = undefined;
    inline for (0..n) |rep| {
        inline for (src_fields, 0..) |field, i| {
            @field(result, std.fmt.comptimePrint("{d}", .{rep * tuple_len + i})) = @field(tuple, field.name);
        }
    }
    return result;
}

/// Helper type for tuple multiplication result
/// Returns an anonymous struct (tuple) type with fields named "0", "1", etc.
fn TupleMultiplyResult(comptime T: type, comptime n: usize) type {
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("TupleMultiplyResult expects a tuple/struct type");
    const src_fields = info.@"struct".fields;
    const total_len = src_fields.len * n;

    // Build struct field definitions
    var fields: [total_len]std.builtin.Type.StructField = undefined;
    inline for (0..n) |rep| {
        inline for (src_fields, 0..) |sfield, i| {
            fields[rep * src_fields.len + i] = .{
                .name = std.fmt.comptimePrint("{d}", .{rep * src_fields.len + i}),
                .type = sfield.type,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(sfield.type),
            };
        }
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

/// Repeat tuple n times (Python tuple * n) - dynamic version
/// Takes a Zig tuple (anonymous struct) and returns a slice with elements repeated
pub fn tupleRepeat(allocator: std.mem.Allocator, tuple: anytype, n: usize) []const @typeInfo(@TypeOf(tuple)).@"struct".fields[0].type {
    const T = @TypeOf(tuple);
    const info = @typeInfo(T);
    if (info != .@"struct") @compileError("tupleRepeat expects a tuple/struct");

    const fields = info.@"struct".fields;
    const tuple_len = fields.len;
    const ElemType = fields[0].type;
    const total_len = tuple_len * n;

    if (n == 0) return &[_]ElemType{};

    const result = allocator.alloc(ElemType, total_len) catch return &[_]ElemType{};
    var idx: usize = 0;
    for (0..n) |_| {
        inline for (fields) |field| {
            result[idx] = @field(tuple, field.name);
            idx += 1;
        }
    }
    return result;
}

/// Repeat list/slice/array n times dynamically (Python list * n with runtime n)
/// Accepts arrays, slices, or pointers to arrays
pub fn sliceRepeatDynamic(allocator: std.mem.Allocator, list: anytype, n: usize) []const getElemType(@TypeOf(list)) {
    const T = @TypeOf(list);
    const ElemType = getElemType(T);

    // Get as slice for uniform handling
    const as_slice: []const ElemType = if (@typeInfo(T) == .array)
        &list
    else if (@typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .array)
        list
    else
        list;

    const list_len = as_slice.len;
    const total_len = list_len * n;

    if (n == 0) return &[_]ElemType{};

    const result = allocator.alloc(ElemType, total_len) catch return &[_]ElemType{};
    for (0..n) |i| {
        @memcpy(result[i * list_len ..][0..list_len], as_slice);
    }
    return result;
}

/// Get element type from array, slice, or pointer to array
fn getElemType(comptime T: type) type {
    const info = @typeInfo(T);
    return switch (info) {
        .array => |a| a.child,
        .pointer => |p| switch (@typeInfo(p.child)) {
            .array => |a| a.child,
            else => p.child,
        },
        else => @compileError("Expected array, slice, or pointer to array"),
    };
}

/// Check if a byte is Unicode whitespace
/// Handles ASCII whitespace plus Unicode whitespace characters like \xa0 (NBSP)
pub fn isUnicodeWhitespace(c: u8) bool {
    // ASCII whitespace
    if (std.ascii.isWhitespace(c)) return true;
    // Non-breaking space (Unicode 0xA0)
    if (c == 0xA0) return true;
    // Other common Unicode whitespace in Latin-1 range
    return false;
}

/// Check if a Unicode codepoint is whitespace
pub fn isUnicodeCodepointWhitespace(cp: u21) bool {
    // ASCII whitespace (0x09-0x0D, 0x20)
    if (cp <= 0x20) {
        return cp == 0x20 or (cp >= 0x09 and cp <= 0x0D);
    }
    // Unicode whitespace characters
    return switch (cp) {
        0x00A0, // Non-breaking space
        0x1680, // Ogham space
        0x2000...0x200A, // Various typographic spaces
        0x2028, // Line separator
        0x2029, // Paragraph separator
        0x202F, // Narrow no-break space
        0x205F, // Medium mathematical space
        0x3000, // Ideographic space
        => true,
        else => false,
    };
}

/// Check if a UTF-8 string contains only whitespace characters
pub fn isStringAllWhitespace(text: []const u8) bool {
    if (text.len == 0) return false;
    var i: usize = 0;
    while (i < text.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch return false;
        if (i + cp_len > text.len) return false;
        const cp = std.unicode.utf8Decode(text[i..][0..cp_len]) catch return false;
        if (!isUnicodeCodepointWhitespace(cp)) return false;
        i += cp_len;
    }
    return true;
}

/// Convert primitive i64 to PyString
// Import and re-export built-in functions
pub const builtins = @import("runtime/builtins.zig");
pub const range = builtins.range;
pub const enumerate = builtins.enumerate;
pub const zip2 = builtins.zip2;
pub const zip3 = builtins.zip3;
pub const all = builtins.all;
pub const any = builtins.any;
pub const abs = builtins.abs;
pub const minList = builtins.minList;
pub const minVarArgs = builtins.minVarArgs;
pub const maxList = builtins.maxList;
pub const maxVarArgs = builtins.maxVarArgs;
pub const sum = builtins.sum;
pub const sorted = builtins.sorted;
pub const reversed = builtins.reversed;
pub const filterTruthy = builtins.filterTruthy;
pub const callable = builtins.callable;
pub const builtinLen = builtins.len;
pub const builtinId = builtins.id;
pub const builtinHash = builtins.hash;
pub const bigIntDivmod = builtins.bigIntDivmod;
pub const bigIntCompare = builtins.bigIntCompare;
pub const operatorEq = builtins.operatorEq;
pub const operatorNe = builtins.operatorNe;
pub const operatorLt = builtins.operatorLt;
pub const operatorLe = builtins.operatorLe;
pub const operatorGt = builtins.operatorGt;
pub const operatorGe = builtins.operatorGe;
pub const classInstanceEq = builtins.classInstanceEq;
pub const classInstanceNe = builtins.classInstanceNe;
pub const PyPowResult = builtins.PyPowResult;
// pyPow is defined locally in this file with more comprehensive special case handling
pub const PyBytes = builtins.PyBytes;
pub const pyStr = builtins.pyStr;

/// Get Python type name for type() builtin
/// Handles special cases like PyPowResult which can be float or complex
pub fn pyTypeName(comptime T: type, value: T) []const u8 {
    // Special handling for PyPowResult - check which variant it is
    if (T == PyPowResult) {
        return value.typeName();
    }

    // Map Zig types to Python type names
    const info = @typeInfo(T);
    if (info == .float or info == .comptime_float) {
        return "float";
    }
    if (info == .int or info == .comptime_int) {
        return "int";
    }
    if (info == .bool) {
        return "bool";
    }
    if (T == []const u8 or T == []u8) {
        return "str";
    }

    // For structs, check if it has a Python type name
    if (info == .@"struct") {
        if (@hasDecl(T, "__name__")) {
            return T.__name__;
        }
    }

    // Default: use Zig type name
    return @typeName(T);
}

// Import and re-export float operations
pub const float_ops = @import("runtime/float_ops.zig");
pub const divideFloat = float_ops.divideFloat;
pub const floatFromHex = float_ops.floatFromHex;
pub const floatGetFormat = float_ops.floatGetFormat;
pub const toFloat = float_ops.toFloat;
pub const subtractNum = float_ops.subtractNum;
pub const addNum = float_ops.addNum;
pub const mulNum = float_ops.mulNum;
pub const numToFloat = float_ops.numToFloat;
pub const floatIsInteger = float_ops.floatIsInteger;

// Import and re-export integer operations
pub const int_ops = @import("runtime/int_ops.zig");
pub const toInt = int_ops.toInt;

/// Convert value to integer for struct.pack - handles BigInt and regular integers
pub inline fn packInt(value: anytype) u64 {
    const T = @TypeOf(value);
    // Handle BigInt directly
    if (T == BigInt) {
        // Try toInt64 first, then fallback to truncation for large values
        return @bitCast(value.toInt64() orelse 0);
    }
    // Handle pointer to BigInt
    if (@typeInfo(T) == .pointer) {
        const child = @typeInfo(T).pointer.child;
        if (child == BigInt) {
            return @bitCast(value.toInt64() orelse 0);
        }
    }
    // Handle regular integers and comptime_int
    const info = @typeInfo(T);
    if (info == .int or info == .comptime_int) {
        return @as(u64, @intCast(value));
    }
    // Fallback
    return 0;
}
pub const int__new__ = int_ops.int__new__;
pub const divideInt = int_ops.divideInt;
pub const moduloInt = int_ops.moduloInt;
pub const pyIntFromAny = int_ops.pyIntFromAny;
pub const intToString = int_ops.intToString;
pub const parseIntUnicode = int_ops.parseIntUnicode;
pub const parseIntToBigInt = int_ops.parseIntToBigInt;
pub const intBuiltinCall = int_ops.intBuiltinCall;
pub const intFromBytes = int_ops.intFromBytes;
pub const intToBytes = int_ops.intToBytes;
pub const floatAsIntegerRatio = float_ops.floatAsIntegerRatio;
pub const floatAsIntegerRatioBigInt = float_ops.floatAsIntegerRatioBigInt;
pub const IntegerRatioResult = float_ops.IntegerRatioResult;
pub const floatHex = float_ops.floatHex;
pub const floatToHex = float_ops.floatToHex;
pub const floatFloor = float_ops.floatFloor;
pub const floatFloorBig = float_ops.floatFloorBig;
pub const floatFloorAny = float_ops.floatFloorAny;
pub const floatCeil = float_ops.floatCeil;
pub const floatCeilBig = float_ops.floatCeilBig;
pub const floatCeilAny = float_ops.floatCeilAny;
pub const floatTrunc = float_ops.floatTrunc;
pub const IntResult = float_ops.IntResult;
pub const FloorCeilResult = float_ops.FloorCeilResult;
pub const floatRound = float_ops.floatRound;
pub const floatBuiltinCall = float_ops.floatBuiltinCall;
pub const floatBuiltinCallBytes = float_ops.floatBuiltinCallBytes;
pub const boolBuiltinCall = float_ops.boolBuiltinCall;
pub const parseFloatWithUnicode = float_ops.parseFloatWithUnicode;
pub const parseFloatStr = float_ops.parseFloatStr;

/// Type builtin wrappers - simple functions that return a truthy []const u8
/// Used when types are stored as first-class values in lists
/// These return a non-empty string so bool(type) returns True
pub fn boolBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "bool";
}

pub fn intBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "int";
}

pub fn floatBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "float";
}

pub fn strBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "str";
}

pub fn bytesBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "bytes";
}

pub fn listBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "list";
}

pub fn dictBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "dict";
}

pub fn setBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "set";
}

pub fn tupleBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "tuple";
}

pub fn frozensetBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "frozenset";
}

pub fn typeBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "type";
}

pub fn objectBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "object";
}

pub fn complexBuiltin(arg: []const u8) []const u8 {
    return if (arg.len > 0) arg else "complex";
}

/// Format mode for formatInt
pub const FormatMode = enum {
    hex_lower,
    hex_upper,
    octal,
    decimal,
};

/// Convert any numeric value (including bool) to a hex/octal formatted string
/// This is needed because Zig's {x} format doesn't support bool directly
/// Returns a stack-allocated formatted string (valid for the current scope)
pub fn formatInt(value: anytype, mode: FormatMode) []const u8 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // Convert to unsigned int for formatting
    const int_val: u64 = if (info == .bool)
        @as(u64, if (value) 1 else 0)
    else if (info == .int or info == .comptime_int)
        @as(u64, @intCast(if (value < 0) @as(i64, value) +% @as(i64, @bitCast(@as(u64, std.math.maxInt(u64)))) +% 1 else @as(i64, value)))
    else if (info == .float or info == .comptime_float)
        @as(u64, @intFromFloat(@abs(value)))
    else
        0;

    // Use thread-local buffer for result
    const S = struct {
        threadlocal var buf: [32]u8 = undefined;
    };

    const len = switch (mode) {
        .hex_lower => std.fmt.bufPrint(&S.buf, "{x}", .{int_val}) catch return "0",
        .hex_upper => std.fmt.bufPrint(&S.buf, "{X}", .{int_val}) catch return "0",
        .octal => std.fmt.bufPrint(&S.buf, "{o}", .{int_val}) catch return "0",
        .decimal => std.fmt.bufPrint(&S.buf, "{d}", .{int_val}) catch return "0",
    };
    return len;
}

/// Compare two sets for equality
/// Sets are equal if they have the same elements (order doesn't matter)
pub fn setEqual(a: anytype, b: anytype) bool {
    // If they're the same pointer, they're equal (identity)
    if (@intFromPtr(&a) == @intFromPtr(&b)) return true;

    // Check if they have the same count
    if (a.count() != b.count()) return false;

    // Check if all elements in a are in b
    var iter = a.iterator();
    while (iter.next()) |entry| {
        if (b.get(entry.key_ptr.*) == null) return false;
    }

    return true;
}

/// Generic 'in' operator for any type - works with ArrayLists, slices, etc.
pub fn containsGeneric(container: anytype, item: anytype) bool {
    const T = @TypeOf(container);
    const info = @typeInfo(T);

    // ArrayList: check .items
    if (info == .@"struct" and @hasField(T, "items")) {
        for (container.items) |elem| {
            if (std.meta.eql(elem, item)) return true;
        }
        return false;
    }

    // Array: iterate and compare (e.g., [_]i64{1, 2, 3})
    if (info == .array) {
        for (container) |elem| {
            if (std.meta.eql(elem, item)) return true;
        }
        return false;
    }

    // Slice: iterate and compare
    if (info == .pointer and info.pointer.size == .slice) {
        for (container) |elem| {
            if (std.meta.eql(elem, item)) return true;
        }
        return false;
    }

    // Empty list []
    if (info == .pointer and info.pointer.size == .one) {
        const child_info = @typeInfo(info.pointer.child);
        if (child_info == .array and child_info.array.len == 0) {
            return false;
        }
    }

    return false;
}

/// Generic 'in' operator - checks membership based on container type
pub fn contains(needle: *PyObject, haystack: *PyObject) bool {
    const haystack_type = getTypeId(haystack);
    switch (haystack_type) {
        .string => {
            // String contains substring
            return PyString.contains(haystack, needle);
        },
        .list => {
            // List contains element
            return PyList.contains(haystack, needle);
        },
        .dict => {
            // Dict contains key (needle must be a string)
            const needle_type = getTypeId(needle);
            if (needle_type != .string) {
                return false;
            }
            const key = PyString.getValue(needle);
            return PyDict.contains(haystack, key);
        },
        else => {
            // Unsupported type - return false
            return false;
        },
    }
}

/// Python list type - re-exported from pylist.zig
pub const PyList = pylist.PyList;

/// Python tuple type - re-exported from pytuple.zig
pub const PyTuple = pytuple.PyTuple;

/// Python string type - re-exported from pystring.zig
pub const PyString = pystring.PyString;

// Import PyDict from separate file
const dict_module = @import("Objects/dictobject.zig");
pub const PyDict = dict_module.PyDict;

// HTTP, async, JSON, regex, sys, and dynamic execution modules
// HTTP uses pool.zig/server.zig which have Mutex - not available on freestanding
pub const http = if (is_freestanding) void else @import("Lib/http.zig");
// WebSocket client (maps to Python's websockets library)
pub const websocket = if (is_freestanding) void else @import("Lib/websocket.zig");
// Async modules require threading (not available on freestanding)
pub const async_runtime = if (is_freestanding) void else @import("Lib/async.zig");
pub const asyncio = if (is_freestanding) void else @import("Lib/asyncio.zig");
pub const parallel = if (is_freestanding) void else @import("runtime/parallel.zig");
pub const io = @import("Lib/io.zig");
pub const json = @import("Lib/json.zig");
pub const re = @import("Lib/re.zig");
pub const tokenizer = @import("runtime/tokenizer.zig");
pub const sys = @import("Lib/sys.zig");
pub const time = @import("Lib/time.zig");
pub const math = @import("Lib/math.zig");
pub const unittest = @import("Lib/unittest.zig");
pub const pathlib = @import("Lib/pathlib.zig");
pub const datetime = @import("Lib/datetime.zig");
// eval/exec use eval_cache which has Thread.Mutex - not available on freestanding
pub const eval_module = if (is_freestanding) void else @import("Python/ceval.zig");
pub const exec_module = if (is_freestanding) void else @import("Python/pythonrun.zig");
pub const gzip = @import("gzip");
pub const zlib = @import("Modules/zlibmodule.zig");
pub const hashlib = @import("Modules/_hashlib.zig");
pub const pickle = @import("Lib/pickle.zig");
pub const test_support = @import("runtime/test_support.zig");
pub const list_tests = @import("runtime/list_tests.zig");
pub const base64 = @import("Lib/base64.zig");
pub const pylong = @import("Objects/longobject.zig");
pub const TestBuffer = @import("runtime/testbuffer.zig");

// Green thread runtime (real M:N scheduler) - use module imports to avoid conflicts with h2
// Conditional on non-freestanding targets (browser WASM doesn't support threads)
pub const GreenThread = if (is_freestanding) void else @import("green_thread").GreenThread;
pub const Scheduler = if (is_freestanding) void else @import("scheduler").Scheduler;
pub var scheduler: if (is_freestanding) void else Scheduler = if (is_freestanding)
{} else undefined;
pub var scheduler_initialized = false;

// Netpoller for async I/O and timers (not available on freestanding)
pub const netpoller = if (is_freestanding) void else @import("netpoller");

// Export convenience functions (some require threading)
pub const httpGet = if (is_freestanding) void else http.getAsPyString;
pub const httpGetResponse = if (is_freestanding) void else http.getAsResponse;
pub const sleep = if (is_freestanding) void else async_runtime.sleep;
pub const now = if (is_freestanding) void else async_runtime.now;
pub const jsonLoads = json.loads;
pub const jsonDumps = json.dumps;
pub const reCompile = re.compile;
pub const reSearch = re.search;
pub const reMatch = re.match;

// Dynamic execution exports (require threading via eval_cache)
pub const eval = if (is_freestanding) void else eval_module.eval;
pub const exec = if (is_freestanding) void else exec_module.exec;
pub const compile_builtin = @import("Python/ast.zig").compile_builtin;
pub const dynamic_import = @import("runtime/dynamic_import.zig").dynamic_import;

// Bytecode execution (for comptime eval)
pub const bytecode = @import("Python/compile.zig");
pub const BytecodeProgram = bytecode.BytecodeProgram;
pub const BytecodeVM = bytecode.VM;

// Dynamic attribute access exports
pub const getattr_builtin = dynamic_attrs.getattr_builtin;
pub const setattr_builtin = dynamic_attrs.setattr_builtin;
pub const hasattr_builtin = dynamic_attrs.hasattr_builtin;
pub const vars_builtin = dynamic_attrs.vars_builtin;
pub const globals_builtin = dynamic_attrs.globals_builtin;
pub const locals_builtin = dynamic_attrs.locals_builtin;
pub const dir_builtin = dynamic_attrs.dir_builtin;

// Type checking functions
/// Check if a value is callable (has a __call__ method or is a function)
pub fn isCallable(value: anytype) bool {
    const T = @TypeOf(value);
    const info = @typeInfo(T);
    return switch (info) {
        .@"fn" => true,
        .pointer => |ptr| switch (@typeInfo(ptr.child)) {
            .@"fn" => true,
            .@"struct" => @hasDecl(ptr.child, "__call__"),
            else => false,
        },
        .@"struct" => @hasDecl(T, "__call__"),
        else => false,
    };
}

/// Check if cls is a subclass of base (placeholder for runtime type checking)
pub fn isSubclass(cls: anytype, base: anytype) bool {
    _ = cls;
    _ = base;
    // At compile time, type relationships are static
    // Return false as a safe default for runtime checks
    return false;
}

/// Check if cls is a subclass of any of the types in the tuple (for type unions like int | str)
pub fn isSubclassMulti(cls: anytype, bases: anytype) bool {
    _ = cls;
    _ = bases;
    // At compile time, type relationships are static
    // Return false as a safe default for runtime checks
    return false;
}

/// Complex number type
pub const PyComplex = struct {
    real: f64,
    imag: f64,

    pub fn create(real: f64, imag: f64) PyComplex {
        return .{ .real = real, .imag = imag };
    }

    pub fn fromValue(value: anytype) PyComplex {
        const T = @TypeOf(value);
        return switch (@typeInfo(T)) {
            .int, .comptime_int => .{ .real = @floatFromInt(value), .imag = 0.0 },
            .float, .comptime_float => .{ .real = value, .imag = 0.0 },
            .bool => .{ .real = if (value) 1.0 else 0.0, .imag = 0.0 },
            else => .{ .real = 0.0, .imag = 0.0 },
        };
    }

    pub fn add(self: PyComplex, other: PyComplex) PyComplex {
        return .{ .real = self.real + other.real, .imag = self.imag + other.imag };
    }

    pub fn sub(self: PyComplex, other: PyComplex) PyComplex {
        return .{ .real = self.real - other.real, .imag = self.imag - other.imag };
    }

    pub fn mul(self: PyComplex, other: PyComplex) PyComplex {
        return .{
            .real = self.real * other.real - self.imag * other.imag,
            .imag = self.real * other.imag + self.imag * other.real,
        };
    }

    pub fn div(self: PyComplex, other: PyComplex) PyComplex {
        // (a + bi) / (c + di) = (ac + bd) / (c^2 + d^2) + ((bc - ad) / (c^2 + d^2))i
        const denom = other.real * other.real + other.imag * other.imag;
        return .{
            .real = (self.real * other.real + self.imag * other.imag) / denom,
            .imag = (self.imag * other.real - self.real * other.imag) / denom,
        };
    }

    /// Negation operator for PyComplex (-c)
    pub fn neg(self: PyComplex) PyComplex {
        return .{ .real = -self.real, .imag = -self.imag };
    }

    pub fn eql(self: PyComplex, other: anytype) bool {
        const T = @TypeOf(other);
        switch (@typeInfo(T)) {
            .int, .comptime_int => {
                const f: f64 = @floatFromInt(other);
                return self.real == f and self.imag == 0.0;
            },
            .float, .comptime_float => {
                return self.real == other and self.imag == 0.0;
            },
            .bool => {
                // complex(False) == False is True (both are "zero")
                const f: f64 = if (other) 1.0 else 0.0;
                return self.real == f and self.imag == 0.0;
            },
            .@"struct" => {
                if (T == PyComplex) {
                    return self.real == other.real and self.imag == other.imag;
                }
            },
            else => {},
        }
        return false;
    }
};

/// Decimal type for fixed-point decimal arithmetic (Python's decimal module)
/// This is a simplified implementation using f64 for now
pub const Decimal = struct {
    value: f64,

    pub fn create(value: f64) Decimal {
        return .{ .value = value };
    }

    pub fn fromString(s: []const u8) Decimal {
        return .{ .value = std.fmt.parseFloat(f64, s) catch 0 };
    }

    pub fn add(self: Decimal, other: Decimal) Decimal {
        return .{ .value = self.value + other.value };
    }

    pub fn sub(self: Decimal, other: Decimal) Decimal {
        return .{ .value = self.value - other.value };
    }

    pub fn mul(self: Decimal, other: Decimal) Decimal {
        return .{ .value = self.value * other.value };
    }

    pub fn div(self: Decimal, other: Decimal) Decimal {
        return .{ .value = self.value / other.value };
    }

    pub fn neg(self: Decimal) Decimal {
        return .{ .value = -self.value };
    }

    pub fn eql(self: Decimal, other: anytype) bool {
        const T = @TypeOf(other);
        switch (@typeInfo(T)) {
            .int, .comptime_int => return self.value == @as(f64, @floatFromInt(other)),
            .float, .comptime_float => return self.value == other,
            .@"struct" => {
                if (T == Decimal) {
                    return self.value == other.value;
                }
            },
            else => {},
        }
        return false;
    }
};

// Tests
test "PyInt creation and retrieval" {
    const allocator = std.testing.allocator;
    const obj = try PyInt.create(allocator, 42);
    defer decref(obj, allocator);

    try std.testing.expectEqual(@as(i64, 42), PyInt.getValue(obj));
    try std.testing.expectEqual(@as(usize, 1), obj.ref_count);
}

test "PyList append and retrieval" {
    const allocator = std.testing.allocator;
    const list = try PyList.create(allocator);
    defer decref(list, allocator);

    const item1 = try PyInt.create(allocator, 10);
    const item2 = try PyInt.create(allocator, 20);

    try PyList.append(list, item1);
    try PyList.append(list, item2);

    // Transfer ownership to list (decref our references)
    decref(item1, allocator);
    decref(item2, allocator);

    try std.testing.expectEqual(@as(usize, 2), PyList.len(list));
    try std.testing.expectEqual(@as(i64, 10), PyInt.getValue(try PyList.getItem(list, 0)));
    try std.testing.expectEqual(@as(i64, 20), PyInt.getValue(try PyList.getItem(list, 1)));
}

test "PyString creation" {
    const allocator = std.testing.allocator;
    const obj = try PyString.create(allocator, "hello");
    defer decref(obj, allocator);

    const value = PyString.getValue(obj);
    try std.testing.expectEqualStrings("hello", value);
}

test "PyDict set and get" {
    const allocator = std.testing.allocator;
    const dict = try PyDict.create(allocator);
    defer decref(dict, allocator);

    const value = try PyInt.create(allocator, 100);
    try PyDict.set(dict, "key", value);

    // Transfer ownership to dict
    decref(value, allocator);

    const retrieved = PyDict.get(dict, "key");
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(@as(i64, 100), PyInt.getValue(retrieved.?));
}

/// Python hash() builtin - returns integer hash of object
/// For integers: returns the integer itself (Python behavior)
/// For strings: uses wyhash for fast hashing
/// For bools: 1 for True, 0 for False
pub fn pyHash(value: anytype) i64 {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    // Integer types: hash is the value itself (Python behavior)
    // Note: Python maps -1 to -2 because -1 is reserved as error indicator in C API
    if (type_info == .int or type_info == .comptime_int) {
        const result: i64 = @intCast(value);
        return if (result == -1) -2 else result;
    }

    // Bool: 1 for true, 0 for false
    if (type_info == .bool) {
        return if (value) 1 else 0;
    }

    // Pointer types - check if it's a string slice
    if (type_info == .pointer) {
        const child = type_info.pointer.child;
        // Check for []const u8 (string slice)
        if (child == u8) {
            return @as(i64, @bitCast(std.hash.Wyhash.hash(0, value)));
        }
        // Check for slice of u8
        if (@typeInfo(child) == .array) {
            const array_child = @typeInfo(child).array.child;
            if (array_child == u8) {
                return @as(i64, @bitCast(std.hash.Wyhash.hash(0, value)));
            }
        }
    }

    // Float: use Python's float hash algorithm
    if (type_info == .float or type_info == .comptime_float) {
        return floatHashInternal(@as(f64, value));
    }

    // Struct (tuple): use Python's tuple hash algorithm
    if (type_info == .@"struct") {
        return tupleHashInternal(value);
    }

    // Default: return 0 for unhashable types
    return 0;
}

/// Python-compatible pow function
/// Handles special cases like (-1)**1e100 = 1.0 (large even exponent)
/// and 1**anything = 1.0
pub fn pyPow(base: f64, exp: f64) f64 {
    // Special case: 1**anything = 1.0
    if (base == 1.0) {
        return 1.0;
    }

    // Special case: anything**0 = 1.0
    if (exp == 0.0) {
        return 1.0;
    }

    // Special case: (-1)**large_integer
    // If exp is a very large number that would become infinity,
    // but the mathematical result should be 1 or -1
    if (base == -1.0) {
        // Check if exponent is an integer (or effectively an integer)
        // For very large exponents, we need to determine if even or odd
        // If |exp| >= 2^53, all floats are integers and even (due to representation)
        if (@abs(exp) >= 9007199254740992.0) {
            // Very large exponent - all such floats are even integers
            return 1.0;
        }
        // For smaller exponents, check if it's an integer
        if (exp == @trunc(exp)) {
            // It's an integer - check odd/even
            const exp_int: i64 = @intFromFloat(exp);
            return if (@mod(exp_int, 2) == 0) 1.0 else -1.0;
        }
    }

    // Default: use standard pow
    return std.math.pow(f64, base, exp);
}

/// Python-compatible float hash (from Objects/object.c _Py_HashDouble)
/// Uses the same algorithm as CPython to ensure hash(0.5) == hash(Fraction(1,2))
fn floatHashInternal(v: f64) i64 {
    // Special cases
    if (std.math.isNan(v)) {
        return 0;
    }
    if (std.math.isInf(v)) {
        return if (v > 0) 314159 else -314159;
    }
    if (v == 0.0) {
        return 0;
    }

    // Python's _PyHASH_MODULUS = (1 << 61) - 1 on 64-bit systems
    const P: u128 = 2305843009213693951;

    // Get the sign and absolute value
    const sign: i64 = if (v < 0) -1 else 1;
    const abs_v = @abs(v);

    // frexp: v = m * 2^e where 0.5 <= |m| < 1
    const frexp_result = std.math.frexp(abs_v);
    var m: f64 = frexp_result.significand;
    var e: i32 = frexp_result.exponent;

    // Reduce the fraction: multiply mantissa by 2 until it's >= 1
    // to get the integer numerator, tracking the power of 2 divisor
    while (m != @trunc(m) and m < 9007199254740992.0) { // 2^53
        m *= 2.0;
        e -= 1;
    }

    // m is now effectively the numerator, 2^(-e) is the denominator (if e < 0)
    // or 2^e is a multiplier (if e >= 0)
    var x: u128 = @intFromFloat(m);

    // Apply the exponent
    if (e >= 0) {
        // Multiply by 2^e mod P
        while (e > 0) : (e -= 1) {
            x = (x * 2) % P;
        }
    } else {
        // Divide by 2^|e| mod P = multiply by modular inverse of 2^|e|
        // inv(2) mod P = (P+1)/2 for Mersenne prime P = 2^61 - 1
        const INV_2: u128 = 1152921504606846976;
        while (e < 0) : (e += 1) {
            x = (x * INV_2) % P;
        }
    }

    var result: i64 = @intCast(x);
    result *= sign;
    if (result == -1) {
        result = -2;
    }
    return result;
}

/// Python-compatible tuple hash using xxHash algorithm (CPython 3.8+)
fn tupleHashInternal(tup: anytype) i64 {
    const T = @TypeOf(tup);
    const info = @typeInfo(T);
    if (info != .@"struct") return 0;

    const fields = info.@"struct".fields;
    const num_fields = fields.len;

    // Python's xxHash constants
    const XXPRIME_1: u64 = 11400714785074694791;
    const XXPRIME_2: u64 = 14029467366897019727;
    const XXPRIME_5: u64 = 2870177450012600261;

    var acc: u64 = XXPRIME_5;

    // Hash each element
    inline for (fields) |field| {
        const elem = @field(tup, field.name);
        const elem_hash: u64 = @bitCast(pyHash(elem));
        acc +%= elem_hash *% XXPRIME_2;
        acc = (acc << 31) | (acc >> 33); // rotate left 31
        acc *%= XXPRIME_1;
    }

    // Final mix
    acc +%= @as(u64, num_fields) ^ (XXPRIME_5 ^ 3527539);

    if (acc == @as(u64, @bitCast(@as(i64, -1)))) {
        return 1546275796;
    }

    return @bitCast(acc);
}

/// Python len() builtin for PyObject* types
/// Dispatches to the appropriate type's len function based on type_id
pub fn pyLen(obj: *PyObject) usize {
    const type_id = getTypeId(obj);
    return switch (type_id) {
        .list => PyList.len(obj),
        .dict => PyDict.len(obj),
        .tuple => PyTuple.len(obj),
        .string => PyString.len(obj),
        else => 0, // None, int, float, bool don't have length
    };
}

/// Compare PyObject with integer (for eval() result comparisons)
pub fn pyObjEqInt(obj: *PyObject, value: i64) bool {
    const type_id = getTypeId(obj);
    if (type_id == .int) {
        return PyInt.getValue(obj) == value;
    }
    return false;
}

/// Extract int value from PyObject (for eval() results)
pub fn pyObjToInt(obj: *PyObject) i64 {
    const type_id = getTypeId(obj);
    if (type_id == .int) {
        return PyInt.getValue(obj);
    }
    return 0;
}

/// Extract BigInt value from PyObject (for eval() results with large integers)
pub fn pyObjToBigInt(obj: *PyObject, allocator: std.mem.Allocator) BigInt {
    const type_id = getTypeId(obj);
    if (type_id == .bigint) {
        // PyBigIntObject - clone the BigInt value
        const bigint_obj: *PyBigIntObject = @ptrCast(@alignCast(obj));
        return bigint_obj.value.clone(allocator) catch BigInt.fromInt(allocator, 0) catch unreachable;
    }
    if (type_id == .int) {
        const val = PyInt.getValue(obj);
        return BigInt.fromInt(allocator, val) catch BigInt.fromInt(allocator, 0) catch unreachable;
    }
    return BigInt.fromInt(allocator, 0) catch unreachable;
}

/// Bounds-checked array list access for exception handling
/// Returns element at index or IndexError if out of bounds
pub fn arrayListGet(comptime T: type, list: std.ArrayList(T), index: i64) PythonError!T {
    const len: i64 = @intCast(list.items.len);

    // Handle negative indices (Python-style)
    const actual_index = if (index < 0) len + index else index;

    // Bounds check
    if (actual_index < 0 or actual_index >= len) {
        return PythonError.IndexError;
    }

    return list.items[@intCast(actual_index)];
}

/// Create a unique base object instance (for sentinel values)
/// Each call returns a new unique object that can be compared by identity
pub fn createObject() *PyObject {
    // Use a static struct for identity comparison with proper alignment
    // Each call creates a unique instance at comptime
    const Sentinel = struct { _marker: u64 align(@alignOf(PyObject)) = 0 };
    const sentinel = Sentinel{};
    return @ptrCast(@alignCast(@constCast(&sentinel)));
}

/// Parse int from string with Unicode whitespace stripping (like Python's int())
/// Strips Unicode whitespace (EM SPACE, EN SPACE, etc.) before parsing
/// Returns error.ValueError for invalid strings (like Python's int())
/// Supports base 0 for auto-detection from prefix (0x, 0o, 0b, 0X, 0O, 0B)
/// Parse int from string directly to BigInt with Unicode whitespace stripping
/// Use this when you know the result will be stored in a BigInt
/// Check if codepoint is Unicode whitespace (Python's definition)
/// Get numeric value of a Unicode digit character (0-9)
/// Returns null if not a digit
/// Parse integer from string with Unicode digit support
/// Concatenate two arrays/slices - returns a new array with elements from both
/// This is Python list concatenation: [1,2] + [3,4] = [1,2,3,4]
pub inline fn concat(a: anytype, b: anytype) @TypeOf(a ++ b) {
    return a ++ b;
}

/// Runtime-friendly list concatenation that handles PyValue types
/// Use this when values might not be comptime-known
/// Returns PyValue (list variant) for Python semantic compatibility
pub fn concatRuntime(allocator: std.mem.Allocator, a: anytype, b: anytype) !PyValue {
    var result = std.ArrayList(PyValue){};

    // Add elements from a
    const AType = @TypeOf(a);
    const a_is_pyvalue = @typeInfo(AType) == .@"union" and @hasField(AType, "list");
    const a_is_arraylist = @typeInfo(AType) == .@"struct" and @hasField(AType, "items") and @hasField(AType, "capacity");
    if (a_is_pyvalue) {
        const a_list = if (a == .list) a.list else if (a == .tuple) a.tuple else &[_]PyValue{};
        try result.appendSlice(allocator, a_list);
    } else if (a_is_arraylist) {
        // ArrayList - iterate over items and convert each to PyValue
        for (a.items) |item| {
            try result.append(allocator, try PyValue.fromAlloc(allocator, item));
        }
    } else {
        const a_slice = iterSlice(a);
        for (a_slice) |item| {
            try result.append(allocator, try PyValue.fromAlloc(allocator, item));
        }
    }

    // Add elements from b
    const BType = @TypeOf(b);
    const b_is_pyvalue = @typeInfo(BType) == .@"union" and @hasField(BType, "list");
    const b_is_arraylist = @typeInfo(BType) == .@"struct" and @hasField(BType, "items") and @hasField(BType, "capacity");
    if (b_is_pyvalue) {
        const b_list = if (b == .list) b.list else if (b == .tuple) b.tuple else &[_]PyValue{};
        try result.appendSlice(allocator, b_list);
    } else if (b_is_arraylist) {
        // ArrayList - iterate over items and convert each to PyValue
        for (b.items) |item| {
            try result.append(allocator, try PyValue.fromAlloc(allocator, item));
        }
    } else {
        const b_slice = iterSlice(b);
        for (b_slice) |item| {
            try result.append(allocator, try PyValue.fromAlloc(allocator, item));
        }
    }

    return PyValue{ .list = result.items };
}

/// Python list repetition: [1, 2] * 3 = [1, 2, 1, 2, 1, 2]
/// Returns a new list with elements repeated n times
pub fn repeatRuntime(allocator: std.mem.Allocator, a: anytype, n: anytype) !PyValue {
    var result = std.ArrayList(PyValue){};

    // Convert count to usize
    const count: usize = if (n < 0) 0 else @intCast(n);

    // Get the source elements
    const AType = @TypeOf(a);
    const a_is_pyvalue = @typeInfo(AType) == .@"union" and @hasField(AType, "list");
    const a_is_arraylist = @typeInfo(AType) == .@"struct" and @hasField(AType, "items") and @hasField(AType, "capacity");

    // Repeat n times
    for (0..count) |_| {
        if (a_is_pyvalue) {
            const a_list = if (a == .list) a.list else if (a == .tuple) a.tuple else &[_]PyValue{};
            try result.appendSlice(allocator, a_list);
        } else if (a_is_arraylist) {
            for (a.items) |item| {
                try result.append(allocator, try PyValue.fromAlloc(allocator, item));
            }
        } else {
            const a_slice = iterSlice(a);
            for (a_slice) |item| {
                try result.append(allocator, try PyValue.fromAlloc(allocator, item));
            }
        }
    }

    return PyValue{ .list = result.items };
}

/// Safe array/list comparison that handles different lengths
/// Python semantics: compare element by element, shorter list is "less" if equal prefix
pub fn arrayLessThan(a: anytype, b: anytype) bool {
    const a_slice = iterSlice(a);
    const b_slice = iterSlice(b);
    const min_len = @min(a_slice.len, b_slice.len);

    for (a_slice[0..min_len], b_slice[0..min_len]) |ea, eb| {
        if (comptime @typeInfo(@TypeOf(ea)) == .@"struct") {
            // Handle tuple elements by comparing field by field
            const ea_val: i64 = if (@hasField(@TypeOf(ea), "@\"0\"")) @intCast(ea.@"0") else 0;
            const eb_val: i64 = if (@hasField(@TypeOf(eb), "@\"0\"")) @intCast(eb.@"0") else 0;
            if (ea_val < eb_val) return true;
            if (ea_val > eb_val) return false;
        } else {
            if (ea < eb) return true;
            if (ea > eb) return false;
        }
    }
    return a_slice.len < b_slice.len;
}

/// Repeat an array n times - returns a new array with elements repeated
/// This is Python list multiplication: [1,2] * 3 = [1,2,1,2,1,2]
pub inline fn listRepeat(arr: anytype, n: anytype) @TypeOf(arr ** @as(usize, @intCast(n))) {
    return arr ** @as(usize, @intCast(n));
}

/// Marshal loads - decode simplified marshal format back to value
/// Uses compile-time encoding: "T" = True, "F" = False
pub fn marshalLoads(data: []const u8) bool {
    if (data.len == 0) return false;
    // "T" for True, "F" for False
    return data[0] == 'T';
}

/// Pickle loads - decode pickle format back to value using full pickle implementation
/// Returns a PickleValue which can be any Python type
pub fn pickleLoads(data: []const u8) pickle.PickleValue {
    // Use global allocator for pickle deserialization
    const allocator = if (@import("builtin").is_test)
        std.testing.allocator
    else
        std.heap.page_allocator;

    return pickle.loads(data, allocator) catch .{ .none = {} };
}

/// Pickle loads returning bool (legacy compatibility for bool-only pickle)
pub fn pickleLoadsBool(data: []const u8) bool {
    if (data.len < 4) return false;
    // Protocol 0: "I01\n." = True, "I00\n." = False
    if (data[0] == 'I' and data[1] == '0') {
        return data[2] == '1';
    }
    // Protocol 2+: \x88 = True, \x89 = False
    if (data.len >= 4 and data[0] == 0x80 and data[1] == 0x02) {
        return data[2] == 0x88;
    }
    return false;
}

/// Match a glob pattern against a filename (Python glob semantics)
/// Supports: * (any chars), ? (single char), [abc] (char class), [!abc] (negated)
pub fn globMatch(pattern: []const u8, name: []const u8) bool {
    var pi: usize = 0;
    var ni: usize = 0;
    var star_p: ?usize = null;
    var star_n: ?usize = null;

    while (ni < name.len or pi < pattern.len) {
        if (pi < pattern.len) {
            const pc = pattern[pi];
            if (pc == '*') {
                // * matches any sequence
                star_p = pi;
                star_n = ni;
                pi += 1;
                continue;
            } else if (pc == '?') {
                // ? matches any single char
                if (ni < name.len) {
                    pi += 1;
                    ni += 1;
                    continue;
                }
            } else if (pc == '[') {
                // Character class
                if (ni < name.len) {
                    if (matchCharClass(pattern[pi..], name[ni])) |skip| {
                        pi += skip;
                        ni += 1;
                        continue;
                    }
                }
            } else {
                // Literal match
                if (ni < name.len and pc == name[ni]) {
                    pi += 1;
                    ni += 1;
                    continue;
                }
            }
        }
        // No match - backtrack to last * if possible
        if (star_p) |sp| {
            pi = sp + 1;
            star_n.? += 1;
            ni = star_n.?;
            if (ni > name.len) return false;
        } else {
            return false;
        }
    }
    return true;
}

/// Match character class [abc] or [!abc], returns chars to skip in pattern or null
fn matchCharClass(pattern: []const u8, c: u8) ?usize {
    if (pattern.len < 2 or pattern[0] != '[') return null;
    var i: usize = 1;
    const negate = if (i < pattern.len and (pattern[i] == '!' or pattern[i] == '^')) blk: {
        i += 1;
        break :blk true;
    } else false;

    var matched = false;
    while (i < pattern.len and pattern[i] != ']') : (i += 1) {
        // Check for range [a-z]
        if (i + 2 < pattern.len and pattern[i + 1] == '-' and pattern[i + 2] != ']') {
            if (c >= pattern[i] and c <= pattern[i + 2]) matched = true;
            i += 2;
        } else {
            if (c == pattern[i]) matched = true;
        }
    }
    if (i >= pattern.len) return null; // No closing ]
    return if ((matched and !negate) or (!matched and negate)) i + 1 else null;
}

/// Recursively collect files matching glob pattern
pub fn rglobCollect(allocator: std.mem.Allocator, base_path: []const u8, pattern: []const u8, entries: *std.ArrayList([]const u8)) void {
    var dir = std.fs.cwd().openDir(base_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var it = dir.iterate();
    while (it.next() catch null) |entry| {
        const full_path = std.fs.path.join(allocator, &.{ base_path, entry.name }) catch continue;

        if (globMatch(pattern, entry.name)) {
            entries.append(allocator, full_path) catch continue;
        }

        // Recurse into directories
        if (entry.kind == .directory) {
            rglobCollect(allocator, full_path, pattern, entries);
        }
    }
}

test "reference counting" {
    const allocator = std.testing.allocator;
    const obj = try PyInt.create(allocator, 42);

    try std.testing.expectEqual(@as(usize, 1), obj.ref_count);

    incref(obj);
    try std.testing.expectEqual(@as(usize, 2), obj.ref_count);

    decref(obj, allocator);
    try std.testing.expectEqual(@as(usize, 1), obj.ref_count);

    decref(obj, allocator);
    // Object should be destroyed here
}
