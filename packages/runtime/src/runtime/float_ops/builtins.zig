/// Float and bool builtin call wrappers
const std = @import("std");
const exceptions = @import("../exceptions.zig");
const parsing = @import("parsing.zig");
const parseFloatWithUnicode = parsing.parseFloatWithUnicode;
const parseFloatBytes = parsing.parseFloatBytes;
const PyValue = @import("../../Objects/object.zig").PyValue;
const type_predicates = @import("../type_predicates.zig");

/// Python error types
pub const PythonError = error{
    ZeroDivisionError,
    IndexError,
    ValueError,
    TypeError,
    KeyError,
    OverflowError,
    OutOfMemory,
    Exception,
};

// =============================================================================
// CONCRETE PyValue FUNCTIONS (compile ONCE - no monomorphization)
// =============================================================================

/// float() for PyValue - compiles once
pub fn floatBuiltinCallPyValue(first: PyValue) PythonError!f64 {
    return switch (first) {
        .int => |i| @as(f64, @floatFromInt(i)),
        .float => |f| f,
        .bool => |b| if (b) @as(f64, 1.0) else @as(f64, 0.0),
        .string => |s| parseFloatWithUnicode(s) catch {
            exceptions.setFloatConversionErrorStr(s);
            return PythonError.ValueError;
        },
        .bytes => |b| parseFloatBytes(b.data) catch {
            exceptions.setFloatConversionError(b.data);
            return PythonError.ValueError;
        },
        .bigint => |*bi| bi.toFloat(),
        else => PythonError.TypeError,
    };
}

/// bool() for PyValue - compiles once
pub fn boolBuiltinCallPyValue(first: PyValue) PythonError!bool {
    return switch (first) {
        .bool => |b| b,
        .int => |i| i != 0,
        .float => |f| f != 0.0 and !std.math.isNan(f),
        .string => |s| s.len > 0,
        .bytes => |b| b.data.len > 0,
        .list => |l| l.items.len > 0,
        .pylist => |l| l.ob_base.ob_size > 0, // CPython list
        .tuple => |t| t.len > 0,
        .none => false,
        .bigint => |bi| !bi.isZero(),
        .complex => |c| c.real != 0.0 or c.imag != 0.0,
        .ptr, .type_obj, .object => true,
        .not_implemented => true,
    };
}

// =============================================================================
// ANYTYPE WRAPPERS (dispatch to concrete functions)
// =============================================================================

/// float() builtin call wrapper for assertRaises testing
pub fn floatBuiltinCall(first: anytype, rest: anytype) PythonError!f64 {
    const FirstType = @TypeOf(first);
    const first_info = @typeInfo(FirstType);
    const RestType = @TypeOf(rest);
    const rest_info = @typeInfo(RestType);

    // Fast path: PyValue (uncertain type) - compiles ONCE via concrete function
    if (FirstType == PyValue) {
        const has_extra = rest_info == .@"struct" and rest_info.@"struct".fields.len > 0;
        if (has_extra) return PythonError.TypeError;
        return floatBuiltinCallPyValue(first);
    }

    const has_extra_args = rest_info == .@"struct" and rest_info.@"struct".fields.len > 0;
    if (has_extra_args) {
        return PythonError.TypeError;
    }

    if (type_predicates.isIntInfo(first_info)) {
        return @as(f64, @floatFromInt(first));
    }
    if (type_predicates.isFloatInfo(first_info)) {
        return @as(f64, first);
    }
    if (first_info == .pointer) {
        const child_type = first_info.pointer.child;
        const child_info = @typeInfo(child_type);
        if (child_info == .@"struct") {
            if (@hasDecl(child_type, "__float__")) {
                const result = first.__float__();
                const ResultType = @TypeOf(result);
                const result_info = @typeInfo(ResultType);
                if (result_info == .error_union) {
                    return result catch return PythonError.ValueError;
                }
                if (type_predicates.isFloatInfo(result_info)) {
                    return result;
                }
                return PythonError.TypeError;
            }
            if (@hasField(child_type, "__base_value__")) {
                const base_value = first.__base_value__;
                const BaseType = @TypeOf(base_value);
                const base_info = @typeInfo(BaseType);
                if (type_predicates.isFloatInfo(base_info)) {
                    return @as(f64, base_value);
                }
                if (type_predicates.isIntInfo(base_info)) {
                    return @as(f64, @floatFromInt(base_value));
                }
                if (base_info == .pointer or base_info == .array) {
                    return parseFloatWithUnicode(base_value) catch return PythonError.ValueError;
                }
            }
            if (@hasDecl(child_type, "__index__")) {
                const result = first.__index__();
                const ResultType = @TypeOf(result);
                const result_info = @typeInfo(ResultType);
                if (result_info == .error_union) {
                    const unwrapped = result catch return PythonError.ValueError;
                    return @as(f64, @floatFromInt(unwrapped));
                }
                if (type_predicates.isIntInfo(result_info)) {
                    return @as(f64, @floatFromInt(result));
                }
            }
        }
        return parseFloatWithUnicode(first) catch {
            exceptions.setFloatConversionErrorStr(first);
            return PythonError.ValueError;
        };
    }
    if (first_info == .@"struct") {
        if (@hasField(FirstType, "data") and @TypeOf(@field(first, "data")) == []const u8) {
            return parseFloatBytes(first.data) catch {
                exceptions.setFloatConversionError(first.data);
                return PythonError.ValueError;
            };
        }
        if (@hasDecl(FirstType, "toFloat") and @hasField(FirstType, "managed")) {
            return (&first).toFloat();
        }
        if (@hasDecl(FirstType, "__float__")) {
            const result = first.__float__();
            const ResultType = @TypeOf(result);
            const result_info = @typeInfo(ResultType);
            if (result_info == .error_union) {
                return result catch return PythonError.ValueError;
            }
            if (type_predicates.isFloatInfo(result_info)) {
                return result;
            }
            return PythonError.TypeError;
        }
        if (@hasDecl(FirstType, "__index__")) {
            const result = first.__index__();
            const ResultType = @TypeOf(result);
            const result_info = @typeInfo(ResultType);
            if (result_info == .error_union) {
                const unwrapped = result catch return PythonError.ValueError;
                return @as(f64, @floatFromInt(unwrapped));
            }
            if (type_predicates.isIntInfo(result_info)) {
                return @as(f64, @floatFromInt(result));
            }
        }
        if (@hasField(FirstType, "__base_value__")) {
            const base_value = first.__base_value__;
            const BaseType = @TypeOf(base_value);
            const base_info = @typeInfo(BaseType);
            if (type_predicates.isFloatInfo(base_info)) {
                return @as(f64, base_value);
            }
            if (type_predicates.isIntInfo(base_info)) {
                return @as(f64, @floatFromInt(base_value));
            }
            if (base_info == .pointer or base_info == .array) {
                return parseFloatWithUnicode(base_value) catch return PythonError.ValueError;
            }
        }
    }
    if (first_info == .@"union" and first_info.@"union".tag_type != null) {
        if (@hasDecl(FirstType, "toFloat")) {
            // UnifiedInt.toFloat() returns f64 directly, not optional
            const RetType = @typeInfo(@TypeOf(FirstType.toFloat)).@"fn".return_type.?;
            if (RetType == f64) {
                return first.toFloat();
            } else if (@typeInfo(RetType) == .optional) {
                if (first.toFloat()) |val| {
                    return val;
                }
            }
        }
        if (@hasDecl(FirstType, "toInt")) {
            if (first.toInt()) |val| {
                return @as(f64, @floatFromInt(val));
            }
        }
    }

    return PythonError.TypeError;
}

/// bool() builtin call wrapper for assertRaises testing
pub fn boolBuiltinCall(first: anytype, rest: anytype) PythonError!bool {
    const FirstType = @TypeOf(first);
    const first_info = @typeInfo(FirstType);
    const RestType = @TypeOf(rest);
    const rest_info = @typeInfo(RestType);

    const has_extra_args = rest_info == .@"struct" and rest_info.@"struct".fields.len > 0;
    if (has_extra_args) {
        return PythonError.TypeError;
    }

    // Fast path: PyValue (uncertain type) - compiles ONCE via concrete function
    if (FirstType == PyValue) {
        return boolBuiltinCallPyValue(first);
    }

    if (FirstType == void or first_info == .@"struct" and first_info.@"struct".fields.len == 0) {
        return false;
    }

    if (first_info == .bool) {
        return first;
    }
    if (type_predicates.isIntInfo(first_info)) {
        return first != 0;
    }
    if (type_predicates.isFloatInfo(first_info)) {
        return first != 0.0;
    }
    if (first_info == .pointer and first_info.pointer.size == .slice) {
        return first.len > 0;
    }
    if (first_info == .pointer and first_info.pointer.size == .one) {
        const child_info = @typeInfo(first_info.pointer.child);
        if (child_info == .array) {
            return child_info.array.len > 0;
        }
    }
    if (first_info == .pointer and first_info.pointer.size == .one) {
        const ChildType = first_info.pointer.child;
        const child_info = @typeInfo(ChildType);
        if (child_info == .@"struct") {
            if (@hasDecl(ChildType, "__bool__")) {
                const bool_fn = @typeInfo(@TypeOf(ChildType.__bool__));
                const first_param = bool_fn.@"fn".params[0].type.?;
                const result = if (@typeInfo(first_param) == .pointer and !@typeInfo(first_param).pointer.is_const)
                    try @constCast(first).__bool__()
                else
                    try first.__bool__();
                if (@TypeOf(result) != bool) {
                    return PythonError.TypeError;
                }
                return result;
            }
            if (@hasDecl(ChildType, "__len__")) {
                const len = try first.__len__();
                if (len < 0) return PythonError.ValueError;
                return len > 0;
            }
            if (@hasField(ChildType, "items")) {
                return first.items.len > 0;
            }
            if (@hasField(ChildType, "__base_value__")) {
                const base_value = first.__base_value__;
                const BaseType = @TypeOf(base_value);
                const base_info = @typeInfo(BaseType);
                if (base_info == .bool) return base_value;
                if (type_predicates.isIntInfo(base_info)) return base_value != 0;
                if (type_predicates.isFloatInfo(base_info)) return base_value != 0.0;
                if (base_info == .pointer and base_info.pointer.size == .slice) return base_value.len > 0;
            }
        }
    }
    if (first_info == .@"struct") {
        if (@hasDecl(FirstType, "__bool__")) {
            const bool_fn = @typeInfo(@TypeOf(FirstType.__bool__));
            const first_param = bool_fn.@"fn".params[0].type.?;
            const result = if (@typeInfo(first_param) == .pointer and !@typeInfo(first_param).pointer.is_const)
                try @constCast(&first).__bool__()
            else
                try first.__bool__();
            if (@TypeOf(result) != bool) {
                return PythonError.TypeError;
            }
            return result;
        }
        if (@hasDecl(FirstType, "__len__")) {
            const len = try first.__len__();
            if (len < 0) return PythonError.ValueError;
            return len > 0;
        }
        if (@hasField(FirstType, "items")) {
            return first.items.len > 0;
        }
        if (@hasField(FirstType, "__base_value__")) {
            const base_value = first.__base_value__;
            const BaseType = @TypeOf(base_value);
            const base_info = @typeInfo(BaseType);
            if (base_info == .bool) return base_value;
            if (type_predicates.isIntInfo(base_info)) return base_value != 0;
            if (type_predicates.isFloatInfo(base_info)) return base_value != 0.0;
            if (base_info == .pointer and base_info.pointer.size == .slice) return base_value.len > 0;
        }
    }

    return true;
}
