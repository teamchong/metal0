/// Shared StaticStringMaps for operator dispatch
/// Consolidates duplicate definitions across codegen modules for DCE efficiency
const std = @import("std");

// ============================================================================
// Unified Operator Configuration
// Single source of truth for operator method names across all type contexts
// ============================================================================

/// Configuration for a binary operator across different type contexts
/// Each field contains the method/function name for that type context
pub const OperatorConfig = struct {
    /// Method name for BigInt operations (runtime.bigint_ops.xxx)
    bigint: []const u8,
    /// Method name for UnifiedInt operations (runtime.unified_int_ops.xxx)
    unified: []const u8,
    /// Method name for PyValue operations (.xxx() method on PyValue)
    pyvalue: []const u8,
    /// Direct Zig operator string, or null if not supported as direct op
    zig_op: ?[]const u8,
};

/// Unified operator map - single source of truth for all operator names
/// Maps Python AST operator tag to names for each type context
pub const OperatorMap = std.StaticStringMap(OperatorConfig).initComptime(.{
    // Arithmetic operators
    .{ "Add", OperatorConfig{ .bigint = "add", .unified = "add", .pyvalue = "add", .zig_op = " + " } },
    .{ "Sub", OperatorConfig{ .bigint = "sub", .unified = "sub", .pyvalue = "sub", .zig_op = " - " } },
    .{ "Mult", OperatorConfig{ .bigint = "mul", .unified = "mul", .pyvalue = "mul", .zig_op = " * " } },
    .{ "Div", OperatorConfig{ .bigint = "divFloor", .unified = "div", .pyvalue = "div", .zig_op = " / " } },
    .{ "FloorDiv", OperatorConfig{ .bigint = "divFloor", .unified = "floorDiv", .pyvalue = "floordiv", .zig_op = null } },
    .{ "Mod", OperatorConfig{ .bigint = "mod", .unified = "mod", .pyvalue = "mod", .zig_op = null } },
    .{ "Pow", OperatorConfig{ .bigint = "pow", .unified = "pow", .pyvalue = "pyPow", .zig_op = null } },
    // Bitwise operators
    .{ "BitAnd", OperatorConfig{ .bigint = "bitAnd", .unified = "bitAnd", .pyvalue = "pyBitAnd", .zig_op = " & " } },
    .{ "BitOr", OperatorConfig{ .bigint = "bitOr", .unified = "bitOr", .pyvalue = "pyBitOr", .zig_op = " | " } },
    .{ "BitXor", OperatorConfig{ .bigint = "bitXor", .unified = "bitXor", .pyvalue = "pyBitXor", .zig_op = " ^ " } },
    .{ "LShift", OperatorConfig{ .bigint = "shl", .unified = "shl", .pyvalue = "pyLShift", .zig_op = " << " } },
    .{ "RShift", OperatorConfig{ .bigint = "shr", .unified = "shr", .pyvalue = "pyRShift", .zig_op = " >> " } },
    // Matrix multiplication (not supported by primitive types)
    .{ "MatMul", OperatorConfig{ .bigint = "matmul", .unified = "matmul", .pyvalue = "matmul", .zig_op = null } },
});

/// Get BigInt method name for an operator
pub fn getBigIntOp(op_name: []const u8) ?[]const u8 {
    if (OperatorMap.get(op_name)) |config| return config.bigint;
    return null;
}

/// Get UnifiedInt method name for an operator
pub fn getUnifiedIntOp(op_name: []const u8) ?[]const u8 {
    if (OperatorMap.get(op_name)) |config| return config.unified;
    return null;
}

/// Get PyValue method name for an operator
pub fn getPyValueOp(op_name: []const u8) ?[]const u8 {
    if (OperatorMap.get(op_name)) |config| return config.pyvalue;
    return null;
}

/// Get direct Zig operator string for an operator (or null if not supported)
pub fn getZigOp(op_name: []const u8) ?[]const u8 {
    if (OperatorMap.get(op_name)) |config| return config.zig_op;
    return null;
}

// ============================================================================
// Legacy maps (kept for backward compatibility during migration)
// ============================================================================

/// Binary operator to Zig operator string mapping
/// NOTE: Pow, Mod, FloorDiv need special handling (std.math.pow, @mod, @divFloor)
/// and should NOT use this map! Pow has no direct Zig equivalent.
pub const BinOpStrings = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Add", " + " },  .{ "Sub", " - " },   .{ "Mult", " * " },
    .{ "Div", " / " },  .{ "FloorDiv", " / " }, .{ "Mod", " % " },
    // NOTE: "Pow" -> " ** " is WRONG - Zig ** is array repeat, not power!
    // Use std.math.pow(Type, base, exp) instead
    .{ "Pow", " INVALID_USE_STD_MATH_POW " },
    .{ "BitAnd", " & " }, .{ "BitOr", " | " },
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
    .{ "MatMul", "__imatmul__" },
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
    .{ "IndentationError", {} }, .{ "TabError", {} },         .{ "BlockingIOError", {} },
    .{ "UnboundLocalError", {} }, .{ "WindowsError", {} },    .{ "UnicodeTranslateError", {} },
    .{ "InterruptedError", {} }, .{ "ChildProcessError", {} }, .{ "ProcessLookupError", {} },
    .{ "FloatingPointError", {} }, .{ "EnvironmentError", {} }, .{ "FileExistsError", {} },
    .{ "IsADirectoryError", {} }, .{ "NotADirectoryError", {} },
    // OSError subclasses (network)
    .{ "BrokenPipeError", {} }, .{ "ConnectionAbortedError", {} },
    .{ "ConnectionRefusedError", {} }, .{ "ConnectionResetError", {} },
    // Exception groups (Python 3.11+)
    .{ "ExceptionGroup", {} },  .{ "BaseExceptionGroup", {} },
    // Warning types (used in assertWarns contexts)
    .{ "Warning", {} },         .{ "UserWarning", {} },       .{ "DeprecationWarning", {} },
    .{ "SyntaxWarning", {} },   .{ "RuntimeWarning", {} },    .{ "FutureWarning", {} },
    .{ "PendingDeprecationWarning", {} }, .{ "ImportWarning", {} }, .{ "UnicodeWarning", {} },
    .{ "BytesWarning", {} },    .{ "ResourceWarning", {} },   .{ "EncodingWarning", {} },
});

/// Python builtin names - constants, types, functions, exceptions, special names
pub const PythonBuiltinNames = std.StaticStringMap(void).initComptime(.{
    // Constants
    .{ "True", {} }, .{ "False", {} }, .{ "None", {} }, .{ "NotImplemented", {} },
    // Built-in types
    .{ "int", {} }, .{ "float", {} }, .{ "str", {} }, .{ "bool", {} }, .{ "bytes", {} },
    .{ "list", {} }, .{ "dict", {} }, .{ "set", {} }, .{ "tuple", {} }, .{ "frozenset", {} },
    .{ "type", {} }, .{ "object", {} }, .{ "super", {} }, .{ "complex", {} },
    .{ "bytearray", {} }, .{ "memoryview", {} }, .{ "slice", {} },
    // Functions - I/O
    .{ "print", {} }, .{ "input", {} }, .{ "open", {} },
    // Functions - type conversion
    .{ "repr", {} }, .{ "ascii", {} }, .{ "format", {} }, .{ "hex", {} }, .{ "oct", {} }, .{ "bin", {} },
    .{ "ord", {} }, .{ "chr", {} },
    // Functions - collections
    .{ "len", {} }, .{ "range", {} }, .{ "enumerate", {} }, .{ "zip", {} }, .{ "map", {} },
    .{ "filter", {} }, .{ "sorted", {} }, .{ "reversed", {} }, .{ "iter", {} }, .{ "next", {} },
    .{ "min", {} }, .{ "max", {} }, .{ "sum", {} }, .{ "all", {} }, .{ "any", {} },
    // Functions - math
    .{ "abs", {} }, .{ "round", {} }, .{ "pow", {} }, .{ "divmod", {} },
    // Functions - introspection
    .{ "isinstance", {} }, .{ "issubclass", {} }, .{ "callable", {} }, .{ "type", {} },
    .{ "hasattr", {} }, .{ "getattr", {} }, .{ "setattr", {} }, .{ "delattr", {} },
    .{ "id", {} }, .{ "hash", {} }, .{ "dir", {} }, .{ "vars", {} },
    .{ "globals", {} }, .{ "locals", {} }, .{ "eval", {} }, .{ "exec", {} }, .{ "compile", {} },
    // Functions - decorators
    .{ "staticmethod", {} }, .{ "classmethod", {} }, .{ "property", {} },
    // Exceptions (subset - see RuntimeExceptions for full list)
    .{ "Exception", {} }, .{ "ValueError", {} }, .{ "TypeError", {} }, .{ "KeyError", {} },
    .{ "IndexError", {} }, .{ "AttributeError", {} }, .{ "RuntimeError", {} },
    .{ "AssertionError", {} }, .{ "StopIteration", {} },
    // Collections module common types
    .{ "deque", {} }, .{ "Counter", {} }, .{ "defaultdict", {} }, .{ "OrderedDict", {} },
    // Special names
    .{ "self", {} }, .{ "__name__", {} }, .{ "__file__", {} }, .{ "__import__", {} },
    // Stdlib modules (commonly used as builtins)
    .{ "math", {} }, .{ "os", {} }, .{ "sys", {} }, .{ "re", {} }, .{ "json", {} },
    .{ "time", {} }, .{ "datetime", {} }, .{ "random", {} },
});

/// String methods that return strings (for type inference)
pub const StringMethods = std.StaticStringMap(void).initComptime(.{
    .{ "upper", {} }, .{ "lower", {} }, .{ "strip", {} }, .{ "lstrip", {} }, .{ "rstrip", {} },
    .{ "split", {} }, .{ "replace", {} }, .{ "join", {} }, .{ "capitalize", {} }, .{ "title", {} },
    .{ "swapcase", {} }, .{ "center", {} }, .{ "ljust", {} }, .{ "rjust", {} },
    .{ "startswith", {} }, .{ "endswith", {} }, .{ "find", {} }, .{ "index", {} },
    .{ "decode", {} }, .{ "encode", {} }, .{ "format", {} }, .{ "zfill", {} },
});

/// String methods that allocate memory (excludes strip/lstrip/rstrip which use std.mem.trim)
pub const AllocatingStringMethods = std.StaticStringMap(void).initComptime(.{
    .{ "upper", {} }, .{ "lower", {} }, .{ "replace", {} }, .{ "capitalize", {} },
    .{ "title", {} }, .{ "swapcase", {} }, .{ "center", {} }, .{ "ljust", {} },
    .{ "rjust", {} }, .{ "join", {} }, .{ "split", {} }, .{ "format", {} }, .{ "zfill", {} },
});

// ============================================================================
// AST Node Predicate Helpers
// Reduce repetitive pattern: `node == .constant and node.constant.value == .int`
// ============================================================================
const ast = @import("analysis.ast");

/// Check if node is an integer constant
pub fn isIntConstant(node: ast.Node) bool {
    return node == .constant and node.constant.value == .int;
}

/// Check if node is a string constant
pub fn isStringConstant(node: ast.Node) bool {
    return node == .constant and node.constant.value == .string;
}

/// Check if node is a float constant
pub fn isFloatConstant(node: ast.Node) bool {
    return node == .constant and node.constant.value == .float;
}

/// Check if node is a boolean constant (True/False)
pub fn isBoolConstant(node: ast.Node) bool {
    return node == .constant and (node.constant.value == .true or node.constant.value == .false);
}

/// Check if node is None constant
pub fn isNoneConstant(node: ast.Node) bool {
    return node == .constant and node.constant.value == .none;
}

/// Check if node is a negative integer constant
pub fn isNegativeIntConstant(node: ast.Node) bool {
    return node == .constant and node.constant.value == .int and node.constant.value.int < 0;
}

/// Check if node is a positive integer constant
pub fn isPositiveIntConstant(node: ast.Node) bool {
    return node == .constant and node.constant.value == .int and node.constant.value.int >= 0;
}

/// Check if node is an empty tuple literal ()
pub fn isEmptyTuple(node: ast.Node) bool {
    return node == .tuple and node.tuple.elts.len == 0;
}

/// Check if node is an empty list literal []
pub fn isEmptyList(node: ast.Node) bool {
    return node == .list and node.list.elts.len == 0;
}

/// Check if node is an empty dict literal {}
pub fn isEmptyDict(node: ast.Node) bool {
    return node == .dict and node.dict.keys.len == 0;
}

/// Check if node is a name with specific identifier
pub fn isName(node: ast.Node, name: []const u8) bool {
    return node == .name and std.mem.eql(u8, node.name.id, name);
}

/// Check if node is 'self' or '__self'
pub fn isSelfName(node: ast.Node) bool {
    return isName(node, "self") or isName(node, "__self");
}

/// Check if node is True constant or True name
pub fn isTrueValue(node: ast.Node) bool {
    return (node == .constant and node.constant.value == .true) or isName(node, "True");
}

/// Check if node is False constant or False name
pub fn isFalseValue(node: ast.Node) bool {
    return (node == .constant and node.constant.value == .false) or isName(node, "False");
}

/// Check if node is None constant or None name
pub fn isNoneValue(node: ast.Node) bool {
    return (node == .constant and node.constant.value == .none) or isName(node, "None");
}

/// Get integer value from constant node, or null if not an int constant
pub fn getIntValue(node: ast.Node) ?i64 {
    if (node == .constant and node.constant.value == .int) {
        return node.constant.value.int;
    }
    return null;
}

/// Get string value from constant node, or null if not a string constant
pub fn getStringValue(node: ast.Node) ?[]const u8 {
    if (node == .constant and node.constant.value == .string) {
        return node.constant.value.string;
    }
    return null;
}

/// Get name identifier from name node, or null if not a name
pub fn getNameId(node: ast.Node) ?[]const u8 {
    if (node == .name) {
        return node.name.id;
    }
    return null;
}
