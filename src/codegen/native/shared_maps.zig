/// Shared StaticStringMaps for operator dispatch
/// Consolidates duplicate definitions across codegen modules for DCE efficiency
const std = @import("std");

/// Binary operator to Zig operator string mapping
pub const BinOpStrings = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Add", " + " },  .{ "Sub", " - " },   .{ "Mult", " * " },
    .{ "Div", " / " },  .{ "FloorDiv", " / " }, .{ "Mod", " % " },
    .{ "Pow", " ** " }, .{ "BitAnd", " & " }, .{ "BitOr", " | " },
    .{ "BitXor", " ^ " }, .{ "LShift", " << " }, .{ "RShift", " >> " },
    .{ "MatMul", " @ " },
});

/// Comparison operator to Zig operator string mapping
pub const CompOpStrings = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Eq", " == " },   .{ "NotEq", " != " },
    .{ "Lt", " < " },    .{ "LtEq", " <= " },
    .{ "Gt", " > " },    .{ "GtEq", " >= " },
    .{ "Is", " == " },   .{ "IsNot", " != " },
});

/// Binary dunder methods for class operator overloading
pub const BinaryDunders = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Add", "__add__" }, .{ "Sub", "__sub__" }, .{ "Mult", "__mul__" },
    .{ "Div", "__truediv__" }, .{ "FloorDiv", "__floordiv__" }, .{ "Mod", "__mod__" },
    .{ "Pow", "__pow__" }, .{ "BitAnd", "__and__" }, .{ "BitOr", "__or__" },
    .{ "BitXor", "__xor__" }, .{ "LShift", "__lshift__" }, .{ "RShift", "__rshift__" },
    .{ "MatMul", "__matmul__" },
});

/// Reverse dunder methods for class operator overloading
pub const ReverseDunders = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Add", "__radd__" }, .{ "Sub", "__rsub__" }, .{ "Mult", "__rmul__" },
    .{ "Div", "__rtruediv__" }, .{ "FloorDiv", "__rfloordiv__" }, .{ "Mod", "__rmod__" },
    .{ "Pow", "__rpow__" }, .{ "BitAnd", "__rand__" }, .{ "BitOr", "__ror__" },
    .{ "BitXor", "__rxor__" }, .{ "LShift", "__rlshift__" }, .{ "RShift", "__rrshift__" },
    .{ "MatMul", "__rmatmul__" },
});

/// In-place dunder methods for augmented assignment
pub const InplaceDunders = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Add", "__iadd__" }, .{ "Sub", "__isub__" }, .{ "Mult", "__imul__" },
    .{ "Div", "__itruediv__" }, .{ "FloorDiv", "__ifloordiv__" }, .{ "Mod", "__imod__" },
    .{ "Pow", "__ipow__" }, .{ "BitAnd", "__iand__" }, .{ "BitOr", "__ior__" },
    .{ "BitXor", "__ixor__" }, .{ "LShift", "__ilshift__" }, .{ "RShift", "__irshift__" },
});

/// Python builtin types (int, str, list, etc.) for type checking
pub const PythonBuiltinTypes = std.StaticStringMap(void).initComptime(.{
    .{ "bool", {} }, .{ "int", {} }, .{ "float", {} },
    .{ "str", {} }, .{ "list", {} }, .{ "dict", {} },
    .{ "set", {} }, .{ "tuple", {} }, .{ "bytes", {} },
    .{ "type", {} }, .{ "complex", {} },
});

/// Collection methods that mutate in-place (list/dict/set mutations)
pub const MutatingMethods = std.StaticStringMap(void).initComptime(.{
    .{ "append", {} }, .{ "extend", {} }, .{ "insert", {} }, .{ "pop", {} }, .{ "clear", {} },
    .{ "remove", {} }, .{ "update", {} }, .{ "add", {} }, .{ "discard", {} }, .{ "sort", {} },
    .{ "reverse", {} }, .{ "clone", {} },
});

/// Python type hints to Zig type strings
pub const PyTypeToZig = std.StaticStringMap([]const u8).initComptime(.{
    .{ "int", "i64" }, .{ "float", "f64" }, .{ "bool", "bool" }, .{ "str", "[]const u8" },
    .{ "list", "anytype" }, .{ "dict", "anytype" }, .{ "set", "anytype" },
    .{ "None", "null" }, .{ "True", "true" }, .{ "False", "false" },
    .{ "complex", "runtime.Complex" }, .{ "repr", "runtime.repr" },
});

/// Python exception types for runtime error mapping
pub const RuntimeExceptions = std.StaticStringMap(void).initComptime(.{
    .{ "Exception", {} },       .{ "BaseException", {} },     .{ "RuntimeError", {} },
    .{ "ValueError", {} },      .{ "TypeError", {} },         .{ "KeyError", {} },
    .{ "IndexError", {} },      .{ "AttributeError", {} },    .{ "NameError", {} },
    .{ "IOError", {} },         .{ "OSError", {} },           .{ "FileNotFoundError", {} },
    .{ "PermissionError", {} }, .{ "ZeroDivisionError", {} }, .{ "OverflowError", {} },
    .{ "NotImplementedError", {} }, .{ "StopIteration", {} }, .{ "AssertionError", {} },
    .{ "ImportError", {} },     .{ "ModuleNotFoundError", {} }, .{ "LookupError", {} },
    .{ "UnicodeError", {} },    .{ "UnicodeDecodeError", {} }, .{ "UnicodeEncodeError", {} },
    .{ "SystemError", {} },     .{ "RecursionError", {} },    .{ "MemoryError", {} },
    .{ "BufferError", {} },     .{ "ConnectionError", {} },   .{ "TimeoutError", {} },
    .{ "ArithmeticError", {} }, .{ "EOFError", {} },          .{ "GeneratorExit", {} },
    .{ "SystemExit", {} },      .{ "KeyboardInterrupt", {} }, .{ "SyntaxError", {} },
});
