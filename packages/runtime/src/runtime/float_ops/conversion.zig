/// Float type conversion and property operations
const std = @import("std");
const rounding = @import("rounding.zig");
const IntResult = rounding.IntResult;
const FloorCeilResult = rounding.FloorCeilResult;

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

/// float.__getformat__(typestr) - Returns the IEEE 754 format string
pub fn floatGetFormat(typestr: anytype) PythonError![]const u8 {
    const T = @TypeOf(typestr);
    const type_info = @typeInfo(T);

    // Extract string slice from various string types
    const str: []const u8 = blk: {
        if (T == []const u8 or T == []u8) {
            break :blk typestr;
        } else if (type_info == .pointer) {
            const child_info = @typeInfo(type_info.pointer.child);
            if (child_info == .array and child_info.array.child == u8) {
                // Pointer to fixed-size array (e.g., *const [6:0]u8)
                // Get the array length and slice directly
                const arr_len = child_info.array.len;
                break :blk typestr[0..arr_len];
            }
        }
        // Not a string type - raise TypeError
        return PythonError.TypeError;
    };

    if (!std.mem.eql(u8, str, "double") and !std.mem.eql(u8, str, "float")) {
        return PythonError.ValueError;
    }

    const native_endian = @import("builtin").cpu.arch.endian();
    return if (native_endian == .little)
        "IEEE, little-endian"
    else
        "IEEE, big-endian";
}

/// float.is_integer() - Returns True if float is integral (no fractional part)
pub fn floatIsInteger(value: anytype) bool {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    const f: f64 = if (type_info == .float or type_info == .comptime_float)
        @as(f64, value)
    else if (type_info == .int or type_info == .comptime_int)
        @as(f64, @floatFromInt(value))
    else if (type_info == .@"struct" and @hasField(T, "__base_value__"))
        @as(f64, value.__base_value__)
    else
        0.0;

    if (std.math.isNan(f) or std.math.isInf(f)) {
        return false;
    }

    return f == @trunc(f);
}

/// Universal Python float coercion function
/// Extracts f64 from any numeric type, including union types
pub fn pyFloat(value: anytype) f64 {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    if (T == f64) return value;
    if (T == f32) return @floatCast(value);
    if (info == .comptime_float) return @as(f64, value);

    if (info == .int or info == .comptime_int) return @floatFromInt(value);

    if (info == .@"union" and info.@"union".tag_type != null) {
        if (@hasField(T, "float_val") and @hasField(T, "complex_val")) {
            return switch (value) {
                .float_val => |v| v,
                .complex_val => |c| c.real,
            };
        }

        if (@hasField(T, "small") and @hasField(T, "big")) {
            return switch (value) {
                .small => |v| @floatFromInt(v),
                .big => |b| b.toFloat(),
            };
        }

        if (@hasField(T, "int") and @hasField(T, "float")) {
            return switch (value) {
                .int => |v| @floatFromInt(v),
                .float => |f| f,
            };
        }
    }

    if (@hasDecl(T, "toFloat")) {
        return value.toFloat();
    }

    @compileError("pyFloat: cannot convert type to f64");
}

/// Convert any value to float - handles both native types and class instances
pub fn toFloat(value: anytype) f64 {
    const T = @TypeOf(value);
    const type_info = @typeInfo(T);

    if (type_info == .float or type_info == .comptime_float) {
        return @as(f64, value);
    }

    if (type_info == .int or type_info == .comptime_int) {
        return @as(f64, @floatFromInt(value));
    }

    if (type_info == .@"struct") {
        if (@hasDecl(T, "toFloat") and @hasField(T, "managed")) {
            return (&value).toFloat();
        }
        if (@hasField(T, "__base_value__")) {
            return value.__base_value__;
        }
        if (@hasDecl(T, "__float__")) {
            const float_result = (&value).__float__();
            const result_type = @TypeOf(float_result);
            const result_info = @typeInfo(result_type);
            if (result_info == .float) {
                return @as(f64, float_result);
            } else if (result_info == .int) {
                return @as(f64, @floatFromInt(float_result));
            } else {
                return 0.0;
            }
        }
        if (@hasField(T, "value")) {
            const field_type = @TypeOf(value.value);
            const field_info = @typeInfo(field_type);
            if (field_info == .@"union") {
                if (@hasDecl(field_type, "toFloat")) {
                    if (value.value.toFloat()) |f| return f;
                }
            } else {
                return toFloat(value.value);
            }
        }
    }

    if (type_info == .pointer) {
        const child_info = @typeInfo(type_info.pointer.child);
        if (child_info == .@"struct") {
            return toFloat(value.*);
        }
        if (type_info.pointer.child == u8) {
            return std.fmt.parseFloat(f64, value) catch 0.0;
        }
    }

    if (type_info == .@"union") {
        if (@hasDecl(T, "toFloat")) {
            // UnifiedInt.toFloat() returns f64 directly, not optional
            const RetType = @typeInfo(@TypeOf(T.toFloat)).@"fn".return_type.?;
            if (RetType == f64) {
                return value.toFloat();
            } else if (@typeInfo(RetType) == .optional) {
                if (value.toFloat()) |f| return f;
            }
        }
    }

    return 0.0;
}
