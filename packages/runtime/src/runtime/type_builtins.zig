/// Type builtin wrappers - simple functions that return a truthy []const u8
/// Used when types are stored as first-class values in lists
/// These return a non-empty string so bool(type) returns True
const PyValue = @import("../Objects/object.zig").PyValue;
const std = @import("std");

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

/// Call a type builtin with an argument and return the result
/// Used for: bool(x), int(x), str(x), etc.
const exceptions = @import("exceptions.zig");
const PythonError = exceptions.PythonError;

/// bool() for PyValue - compiles once (no monomorphization)
pub fn boolBuiltinCallPyValue(t: PyValue) PythonError!bool {
    return switch (t) {
        .bool => |b| b,
        .int => |i| i != 0,
        .float => |f| f != 0.0 and !std.math.isNan(f),
        .string => |s| s.len > 0,
        .bytes => |b| b.data.len > 0,
        .list => |l| l.items.len > 0,
        .pylist => |l| l.ob_base.ob_size > 0, // CPython list
        .tuple => |tup| tup.len > 0,
        .none => false,
        .bigint => |bi| !bi.isZero(),
        .complex => |c| c.real != 0.0 or c.imag != 0.0,
        .ptr, .type_obj, .object => true,
        .not_implemented => true,
    };
}

/// Call bool() type constructor with arguments
/// Calling convention: boolBuiltinCall(first_arg, .{remaining_args})
/// Python: bool() -> False (called as boolBuiltinCall({}, .{}))
/// Python: bool(x) -> True/False (called as boolBuiltinCall(x, .{}))
/// Python: bool(42, 42) -> TypeError (called as boolBuiltinCall(42, .{42}))
pub fn boolBuiltinCall(t: anytype, args: anytype) PythonError!bool {
    const ArgsType = @TypeOf(args);
    const args_info = @typeInfo(ArgsType);

    // Check for extra arguments - if args tuple has any fields, too many args
    // (since t is already the first argument)
    if (args_info == .@"struct") {
        const fields = args_info.@"struct".fields;
        if (fields.len > 0) {
            // bool() takes at most 1 argument, but we have t + args
            exceptions.setException("TypeError", "bool() takes at most 1 argument");
            return PythonError.TypeError;
        }
    }

    // Fast path: PyValue (uncertain type) - compiles ONCE via concrete function
    const TType = @TypeOf(t);
    if (TType == PyValue) {
        return boolBuiltinCallPyValue(t);
    }

    // Check if t is empty struct (bool() with no args)
    const t_info = @typeInfo(TType);
    if (t_info == .@"struct") {
        const t_fields = t_info.@"struct".fields;
        if (t_fields.len == 0) {
            // bool() with no args -> False
            return false;
        }
    }

    // bool(x) - evaluate truthiness of t
    return toBoolWithDunder(t);
}

/// Convert any value to bool (Python truthiness) with __bool__ support
fn toBoolWithDunder(value: anytype) PythonError!bool {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    // For pointers to structs, check for __bool__ and __len__ methods
    if (info == .pointer and info.pointer.size == .one) {
        const ChildType = info.pointer.child;
        if (@typeInfo(ChildType) == .@"struct") {
            // Check for __bool__ method
            if (@hasDecl(ChildType, "__bool__")) {
                // Call __bool__ and propagate its result (including errors)
                return value.__bool__();
            }
            // Check for __len__ method (fallback)
            if (@hasDecl(ChildType, "__len__")) {
                const len_result = value.__len__();
                const LenType = @TypeOf(len_result);
                if (@typeInfo(LenType) == .error_union) {
                    const len = len_result catch return PythonError.TypeError;
                    // Python raises ValueError if __len__ returns negative
                    if (len < 0) return PythonError.ValueError;
                    return len > 0;
                }
                // Non-error-union __len__ result
                if (len_result < 0) return PythonError.ValueError;
                return len_result > 0;
            }
        }
    }

    // Simple type conversion
    return toBool(value);
}

/// Convert any value to bool (Python truthiness)
fn toBool(value: anytype) bool {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    return switch (info) {
        .bool => value,
        .int, .comptime_int => value != 0,
        .float, .comptime_float => value != 0.0,
        .optional => if (value) |v| toBool(v) else false,
        // Slices check len, non-optional pointers are always truthy (can't be null)
        .pointer => |p| if (p.size == .slice) value.len > 0 else true,
        else => true, // Objects are truthy by default
    };
}
