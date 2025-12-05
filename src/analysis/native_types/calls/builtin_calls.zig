/// Type inference for builtin function calls (int, str, len, abs, list, map, etc.)
const std = @import("std");
const ast = @import("ast");
const core = @import("../core.zig");
const fnv_hash = @import("fnv_hash");
const static_maps = @import("static_maps.zig");
const expressions = @import("../expressions.zig");

pub const NativeType = core.NativeType;
pub const InferError = core.InferError;
pub const ClassInfo = core.ClassInfo;

const hashmap_helper = @import("hashmap_helper");
const FnvHashMap = hashmap_helper.StringHashMap(NativeType);
const FnvClassMap = hashmap_helper.StringHashMap(ClassInfo);

/// Infer type from builtin function call (name calls, not method calls)
pub fn inferBuiltinCall(
    allocator: std.mem.Allocator,
    var_types: *FnvHashMap,
    class_fields: *FnvClassMap,
    func_return_types: *FnvHashMap,
    func_name: []const u8,
    call: ast.Node.Call,
) InferError!NativeType {
    // Check if the callee is a callable variable (from iterating over callable list)
    // PyCallable.call() returns []const u8 (bytes)
    if (var_types.get(func_name)) |var_type| {
        if (@as(std.meta.Tag(NativeType), var_type) == .callable) {
            return .{ .string = .runtime };
        }
    }

    // Check if this is a class constructor (class_name matches a registered class)
    if (class_fields.get(func_name)) |class_info| {
        _ = class_info;
        return .{ .class_instance = func_name };
    }

    // Check for external class types from stdlib modules (like ndarray, staticarray)
    // Note: memoryview is a Python builtin, handled separately
    if (std.mem.eql(u8, func_name, "ndarray") or
        std.mem.eql(u8, func_name, "staticarray"))
    {
        return .{ .class_instance = func_name };
    }

    // Check for registered function return types (lambdas, etc.)
    if (func_return_types.get(func_name)) |return_type| {
        return return_type;
    }

    // Special case: abs() returns same type as input
    const ABS_HASH = comptime fnv_hash.hash("abs");
    if (fnv_hash.hash(func_name) == ABS_HASH and call.args.len > 0) {
        return try expressions.inferExpr(allocator, var_types, class_fields, func_return_types, call.args[0]);
    }

    // Special case: int() - check argument source for boundedness
    const INT_HASH = comptime fnv_hash.hash("int");
    if (fnv_hash.hash(func_name) == INT_HASH) {
        if (call.args.len == 0) {
            // int() with no args returns 0 - bounded
            return .{ .int = .bounded };
        }
        const arg = call.args[0];
        // Check if argument is a large float literal (e.g., 1e100)
        if (arg == .constant and arg.constant.value == .float) {
            const fval = arg.constant.value.float;
            // If float exceeds i64 range, use bigint
            const max_i64: f64 = @as(f64, @floatFromInt(std.math.maxInt(i64)));
            const min_i64: f64 = @as(f64, @floatFromInt(std.math.minInt(i64)));
            if (fval > max_i64 or fval < min_i64 or @abs(fval) > max_i64) {
                return .bigint;
            }
        }
        // Check for unary minus with float literal: int(-1e100)
        if (arg == .unaryop and arg.unaryop.op == .USub) {
            if (arg.unaryop.operand.* == .constant and arg.unaryop.operand.constant.value == .float) {
                const fval = arg.unaryop.operand.constant.value.float;
                const max_i64: f64 = @as(f64, @floatFromInt(std.math.maxInt(i64)));
                if (fval > max_i64) {
                    return .bigint;
                }
            }
        }
        // Check if argument is an int/float literal - bounded
        if (arg == .constant) {
            return .{ .int = .bounded };
        }
        // Check if argument comes from unbounded source (input(), file.read(), etc.)
        // by inferring the arg type and checking if it's a string (from external source)
        const arg_type = try expressions.inferExpr(allocator, var_types, class_fields, func_return_types, arg);
        const arg_tag = @as(std.meta.Tag(NativeType), arg_type);
        // If arg is a RUNTIME string (not literal), it could be from input() - unbounded
        // Literal strings like "123" are bounded because we can verify the value at compile time
        if (arg_tag == .string and arg_type.string != .literal) {
            // String from file/input/network - unbounded
            return .{ .int = .unbounded };
        }
        // If arg is already an unbounded int, propagate
        if (arg_tag == .int and arg_type.int == .unbounded) {
            return .{ .int = .unbounded };
        }
        // Default: bounded (e.g., int(float_literal), int(int_var), int("123"))
        return .{ .int = .bounded };
    }

    // Special case: round() - returns int if no ndigits, float if ndigits provided
    const ROUND_HASH = comptime fnv_hash.hash("round");
    if (fnv_hash.hash(func_name) == ROUND_HASH) {
        // round(x) or round(x, None) → int
        // round(x, ndigits) → float (when ndigits is not None)
        if (call.args.len <= 1) {
            // No ndigits or ndigits not provided
            return .{ .int = .bounded };
        }
        // Check if second arg is None
        const ndigits_arg = call.args[1];
        if (ndigits_arg == .constant and ndigits_arg.constant.value == .none) {
            return .{ .int = .bounded };
        }
        // Also check for keyword arg ndigits=None
        for (call.keyword_args) |kwarg| {
            if (std.mem.eql(u8, kwarg.name, "ndigits")) {
                if (kwarg.value == .constant and kwarg.value.constant.value == .none) {
                    return .{ .int = .bounded };
                }
                // ndigits provided and not None → float
                return .float;
            }
        }
        // ndigits provided as positional arg and not None → float
        return .float;
    }

    // dict() builtin - returns dict type
    const DICT_BUILTIN_HASH = comptime fnv_hash.hash("dict");
    if (fnv_hash.hash(func_name) == DICT_BUILTIN_HASH) {
        // dict() with or without args returns a dict
        // dict(), dict(a=1), dict([(k,v),...]), dict({...}) all return dict
        // For dict(kwargs), keys are always strings, values can vary
        // Default to string->string for simplicity
        const key_type = try allocator.create(NativeType);
        key_type.* = .{ .string = .runtime };
        const value_type = try allocator.create(NativeType);
        // Try to infer value type from kwargs if available
        if (call.keyword_args.len > 0) {
            // Infer from first kwarg value
            const first_val_type = try expressions.inferExpr(allocator, var_types, class_fields, func_return_types, call.keyword_args[0].value);
            value_type.* = first_val_type;
        } else if (call.args.len > 0) {
            // dict(iterable) - try to infer from iterable
            const arg_type = try expressions.inferExpr(allocator, var_types, class_fields, func_return_types, call.args[0]);
            if (@as(std.meta.Tag(NativeType), arg_type) == .dict) {
                // Already a dict - return same type
                return arg_type;
            }
            value_type.* = .unknown;
        } else {
            value_type.* = .unknown;
        }
        return .{ .dict = .{ .key = key_type, .value = value_type } };
    }

    // set() builtin - returns set type
    const SET_BUILTIN_HASH = comptime fnv_hash.hash("set");
    if (fnv_hash.hash(func_name) == SET_BUILTIN_HASH) {
        const elem_type = try allocator.create(NativeType);
        if (call.args.len > 0) {
            // Infer from iterable argument
            const arg_type = try expressions.inferExpr(allocator, var_types, class_fields, func_return_types, call.args[0]);
            if (@as(std.meta.Tag(NativeType), arg_type) == .set) {
                return arg_type;
            }
            if (@as(std.meta.Tag(NativeType), arg_type) == .list) {
                elem_type.* = arg_type.list.*;
            } else if (@as(std.meta.Tag(NativeType), arg_type) == .array) {
                // Array literals like ['a', 'b'] get array type - extract element type
                elem_type.* = arg_type.array.element_type.*;
            } else if (@as(std.meta.Tag(NativeType), arg_type) == .string) {
                elem_type.* = .{ .string = .runtime }; // set("abc") -> set of chars
            } else {
                elem_type.* = .unknown;
            }
        } else {
            // Empty set() - default to i64 element type to match codegen
            // The codegen uses std.AutoHashMap(i64, void) for empty sets
            elem_type.* = .{ .int = .bounded };
        }
        return .{ .set = elem_type };
    }

    // frozenset() builtin - returns set type (immutable, but same runtime representation)
    const FROZENSET_BUILTIN_HASH = comptime fnv_hash.hash("frozenset");
    if (fnv_hash.hash(func_name) == FROZENSET_BUILTIN_HASH) {
        const elem_type = try allocator.create(NativeType);
        if (call.args.len > 0) {
            // Infer from iterable argument
            const arg_type = try expressions.inferExpr(allocator, var_types, class_fields, func_return_types, call.args[0]);
            if (@as(std.meta.Tag(NativeType), arg_type) == .set) {
                return arg_type;
            }
            if (@as(std.meta.Tag(NativeType), arg_type) == .list) {
                elem_type.* = arg_type.list.*;
            } else if (@as(std.meta.Tag(NativeType), arg_type) == .array) {
                // Array literals like ['a', 'b'] get array type - extract element type
                elem_type.* = arg_type.array.element_type.*;
            } else if (@as(std.meta.Tag(NativeType), arg_type) == .string) {
                elem_type.* = .{ .string = .runtime }; // frozenset("abc") -> set of chars
            } else {
                elem_type.* = .unknown;
            }
        } else {
            // Empty frozenset() - default to i64 element type to match codegen
            elem_type.* = .{ .int = .bounded };
        }
        return .{ .set = elem_type };
    }

    // tuple() builtin - returns tuple type
    const TUPLE_BUILTIN_HASH = comptime fnv_hash.hash("tuple");
    if (fnv_hash.hash(func_name) == TUPLE_BUILTIN_HASH) {
        if (call.args.len > 0) {
            // Infer from argument
            const arg_type = try expressions.inferExpr(allocator, var_types, class_fields, func_return_types, call.args[0]);
            if (@as(std.meta.Tag(NativeType), arg_type) == .tuple) {
                return arg_type;
            }
            // If arg is a literal string, create tuple type with that many string elements
            if (call.args[0] == .constant and call.args[0].constant.value == .string) {
                const str = call.args[0].constant.value.string;
                // Count UTF-8 characters
                var char_count: usize = 0;
                var i: usize = 0;
                while (i < str.len) {
                    const byte = str[i];
                    const char_len: usize = if (byte < 0x80) 1 else if (byte < 0xE0) 2 else if (byte < 0xF0) 3 else 4;
                    i += char_len;
                    char_count += 1;
                }
                // Create tuple type with char_count string elements
                if (char_count == 0) {
                    return .{ .tuple = &[_]NativeType{} };
                }
                const elem_types = try allocator.alloc(NativeType, char_count);
                for (elem_types) |*et| {
                    et.* = .{ .string = .runtime };
                }
                return .{ .tuple = elem_types };
            }
            // If arg is a literal list, create tuple type with those element types
            if (call.args[0] == .list) {
                const list = call.args[0].list;
                if (list.elts.len == 0) {
                    return .{ .tuple = &[_]NativeType{} };
                }
                const elem_types = try allocator.alloc(NativeType, list.elts.len);
                for (list.elts, 0..) |elt, idx| {
                    elem_types[idx] = try expressions.inferExpr(allocator, var_types, class_fields, func_return_types, elt);
                }
                return .{ .tuple = elem_types };
            }
        }
        // Empty tuple or unknown element types
        return .{ .tuple = &[_]NativeType{} };
    }

    // list() builtin - returns list with inferred element type from argument
    const LIST_BUILTIN_HASH = comptime fnv_hash.hash("list");
    if (fnv_hash.hash(func_name) == LIST_BUILTIN_HASH) {
        if (call.args.len > 0) {
            // Infer element type from the iterable argument
            const arg_type = try expressions.inferExpr(allocator, var_types, class_fields, func_return_types, call.args[0]);
            // If arg is already a list, return its type
            if (@as(std.meta.Tag(NativeType), arg_type) == .list) {
                return arg_type;
            }
            // If arg is a string, list() returns list of single chars (strings)
            if (@as(std.meta.Tag(NativeType), arg_type) == .string) {
                const elem_ptr = try allocator.create(NativeType);
                elem_ptr.* = .{ .string = .runtime };
                return .{ .list = elem_ptr };
            }
            // If arg is a tuple, list() returns list of PyValue (heterogeneous)
            if (@as(std.meta.Tag(NativeType), arg_type) == .tuple) {
                const elem_ptr = try allocator.create(NativeType);
                elem_ptr.* = .pyvalue;
                return .{ .list = elem_ptr };
            }
            // For iterables, return list of unknown element type
            const elem_ptr = try allocator.create(NativeType);
            elem_ptr.* = .unknown;
            return .{ .list = elem_ptr };
        }
        // Empty list() call returns list of unknown type
        const elem_ptr = try allocator.create(NativeType);
        elem_ptr.* = .unknown;
        return .{ .list = elem_ptr };
    }

    // Look up in static map for other builtins
    if (static_maps.BuiltinFuncMap.get(func_name)) |return_type| {
        return return_type;
    }

    // map() builtin - returns list (slice from .items)
    const MAP_BUILTIN_HASH = comptime fnv_hash.hash("map");
    if (fnv_hash.hash(func_name) == MAP_BUILTIN_HASH) {
        // map() always returns a list of strings when using str.strip, etc.
        // For now, we just mark it as list of unknown, which will use [N] indexing
        const elem_ptr = try allocator.create(NativeType);
        elem_ptr.* = .{ .string = .runtime };
        return .{ .list = elem_ptr };
    }

    // Path() constructor from pathlib
    if (fnv_hash.hash(func_name) == comptime fnv_hash.hash("Path")) {
        return .path;
    }

    // collections module constructors
    const func_hash = fnv_hash.hash(func_name);
    const COUNTER_HASH = comptime fnv_hash.hash("Counter");
    const DEFAULTDICT_HASH = comptime fnv_hash.hash("defaultdict");
    const ORDEREDDICT_HASH = comptime fnv_hash.hash("OrderedDict");
    const DEQUE_HASH = comptime fnv_hash.hash("deque");
    if (func_hash == COUNTER_HASH or
        func_hash == DEFAULTDICT_HASH or
        func_hash == ORDEREDDICT_HASH)
    {
        return .counter; // Counter type for hashmap_helper.StringHashMap
    }
    if (func_hash == DEQUE_HASH) {
        return .deque; // Deque type for std.ArrayList
    }

    // itertools module functions (from itertools import repeat, chain, etc.)
    // These return lists (std.ArrayList(i64))
    const REPEAT_HASH = comptime fnv_hash.hash("repeat");
    const CHAIN_HASH = comptime fnv_hash.hash("chain");
    const CYCLE_HASH = comptime fnv_hash.hash("cycle");
    const ISLICE_HASH = comptime fnv_hash.hash("islice");
    const COUNT_HASH_ITER = comptime fnv_hash.hash("count");
    const ZIP_LONGEST_HASH = comptime fnv_hash.hash("zip_longest");
    if (func_hash == REPEAT_HASH or func_hash == CHAIN_HASH or
        func_hash == CYCLE_HASH or func_hash == ISLICE_HASH or
        func_hash == COUNT_HASH_ITER or func_hash == ZIP_LONGEST_HASH)
    {
        return .deque; // Returns std.ArrayList(i64)
    }

    // functools module functions
    const REDUCE_HASH = comptime fnv_hash.hash("reduce");
    if (func_hash == REDUCE_HASH) {
        // reduce(func, iterable) -> element type of iterable
        // Most common use case is numeric reduction, so default to int
        return .{ .int = .bounded };
    }

    // Exception constructors - RuntimeError, ValueError, TypeError, etc.
    const exception_types = [_][]const u8{
        "Exception",
        "BaseException",
        "RuntimeError",
        "ValueError",
        "TypeError",
        "KeyError",
        "IndexError",
        "AttributeError",
        "NameError",
        "IOError",
        "OSError",
        "FileNotFoundError",
        "PermissionError",
        "ZeroDivisionError",
        "OverflowError",
        "NotImplementedError",
        "StopIteration",
        "AssertionError",
        "ImportError",
        "ModuleNotFoundError",
        "LookupError",
        "UnicodeError",
        "UnicodeDecodeError",
        "UnicodeEncodeError",
        "SystemError",
        "RecursionError",
        "MemoryError",
        "BufferError",
        "ConnectionError",
        "TimeoutError",
    };
    for (exception_types) |exc_name| {
        if (std.mem.eql(u8, func_name, exc_name)) {
            return .{ .exception = exc_name };
        }
    }

    return .unknown;
}
