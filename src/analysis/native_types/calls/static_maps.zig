/// Static type maps for builtin functions and methods
const std = @import("std");
const core = @import("../core.zig");

pub const NativeType = core.NativeType;

/// Built-in functions return type map
/// Note: int types here use .bounded because these are bounded operations:
/// - len() is always ≤ max array size
/// - ord() is always 0-1114111 (Unicode range)
/// - hash() is bounded to i64 range by design
/// Functions like int(), min(), max(), sum() need special handling based on args
pub const BuiltinFuncMap = std.StaticStringMap(NativeType).initComptime(.{
    .{ "len", NativeType{ .int = .bounded } }, // len() is always bounded
    .{ "str", NativeType{ .string = .runtime } },
    .{ "repr", NativeType{ .string = .runtime } },
    .{ "bytes", NativeType{ .string = .runtime } }, // bytes() returns byte string
    .{ "bytearray", NativeType{ .string = .runtime } }, // bytearray() returns byte array (treated as string)
    // int() is handled specially - depends on argument source
    .{ "float", NativeType.float },
    .{ "bool", NativeType.bool },
    .{ "round", NativeType{ .int = .bounded } }, // round() on float is bounded
    .{ "chr", NativeType{ .string = .runtime } },
    .{ "ord", NativeType{ .int = .bounded } }, // ord() is always 0-1114111
    // min/max/sum need special handling based on args - default to bounded
    .{ "min", NativeType{ .int = .bounded } },
    .{ "max", NativeType{ .int = .bounded } },
    .{ "sum", NativeType{ .int = .bounded } },
    .{ "hash", NativeType{ .int = .bounded } }, // hash() is bounded to i64
    // Boolean return functions
    .{ "any", NativeType.bool },
    .{ "all", NativeType.bool },
    .{ "callable", NativeType.bool },
    .{ "hasattr", NativeType.bool },
    .{ "isinstance", NativeType.bool },
    .{ "issubclass", NativeType.bool },
    // io module (from io import StringIO, BytesIO)
    .{ "StringIO", NativeType.stringio },
    .{ "BytesIO", NativeType.bytesio },
    // File I/O
    .{ "open", NativeType.file },
});

pub const StringMethods = std.StaticStringMap(NativeType).initComptime(.{
    .{ "upper", NativeType{ .string = .runtime } },
    .{ "lower", NativeType{ .string = .runtime } },
    .{ "strip", NativeType{ .string = .runtime } },
    .{ "lstrip", NativeType{ .string = .runtime } },
    .{ "rstrip", NativeType{ .string = .runtime } },
    .{ "capitalize", NativeType{ .string = .runtime } },
    .{ "title", NativeType{ .string = .runtime } },
    .{ "swapcase", NativeType{ .string = .runtime } },
    .{ "replace", NativeType{ .string = .runtime } },
    .{ "join", NativeType{ .string = .runtime } },
    .{ "center", NativeType{ .string = .runtime } },
    .{ "ljust", NativeType{ .string = .runtime } },
    .{ "rjust", NativeType{ .string = .runtime } },
    .{ "zfill", NativeType{ .string = .runtime } },
});

pub const StringBoolMethods = std.StaticStringMap(void).initComptime(.{
    .{ "startswith", {} },
    .{ "endswith", {} },
    .{ "isdigit", {} },
    .{ "isalpha", {} },
    .{ "isalnum", {} },
    .{ "isspace", {} },
    .{ "islower", {} },
    .{ "isupper", {} },
    .{ "isascii", {} },
    .{ "istitle", {} },
    .{ "isprintable", {} },
});

pub const StringIntMethods = std.StaticStringMap(void).initComptime(.{
    .{ "find", {} },
    .{ "count", {} },
    .{ "index", {} },
    .{ "rfind", {} },
    .{ "rindex", {} },
});

pub const DfColumnMethods = std.StaticStringMap(void).initComptime(.{
    .{ "sum", {} },
    .{ "mean", {} },
    .{ "min", {} },
    .{ "max", {} },
    .{ "std", {} },
});

/// Math module function return types
pub const MathIntFuncs = std.StaticStringMap(void).initComptime(.{
    .{ "factorial", {} },
    .{ "gcd", {} },
    .{ "lcm", {} },
});

pub const MathBoolFuncs = std.StaticStringMap(void).initComptime(.{
    .{ "isnan", {} },
    .{ "isinf", {} },
    .{ "isfinite", {} },
});

