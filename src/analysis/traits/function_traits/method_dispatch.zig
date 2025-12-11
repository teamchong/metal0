/// Primitive type method dispatch - Python methods on Zig primitives
/// Maps Python methods on int/float/dict/list to runtime helper functions
const std = @import("std");

/// Methods available on Python float that need runtime dispatch
pub const FloatMethods = std.StaticStringMap([]const u8).initComptime(.{
    // Float representation methods
    .{ "as_integer_ratio", "runtime.float_ops.asIntegerRatio" },
    .{ "is_integer", "runtime.float_ops.isInteger" },
    .{ "hex", "runtime.float_ops.toHex" },
    .{ "fromhex", "runtime.float_ops.fromHex" },

    // Magic methods for math module
    .{ "__floor__", "runtime.float_ops.floor" },
    .{ "__ceil__", "runtime.float_ops.ceil" },
    .{ "__trunc__", "runtime.float_ops.trunc" },
    .{ "__round__", "runtime.float_ops.round" },
    .{ "__abs__", "runtime.float_ops.abs" },
    .{ "__neg__", "runtime.float_ops.neg" },
    .{ "__pos__", "runtime.float_ops.pos" },

    // Comparison magic methods
    .{ "__eq__", "runtime.float_ops.eq" },
    .{ "__ne__", "runtime.float_ops.ne" },
    .{ "__lt__", "runtime.float_ops.lt" },
    .{ "__le__", "runtime.float_ops.le" },
    .{ "__gt__", "runtime.float_ops.gt" },
    .{ "__ge__", "runtime.float_ops.ge" },

    // String conversion
    .{ "__repr__", "runtime.float_ops.repr" },
    .{ "__str__", "runtime.float_ops.str" },
    .{ "__format__", "runtime.float_ops.format" },

    // Hash and bool
    .{ "__hash__", "runtime.float_ops.hash" },
    .{ "__bool__", "runtime.float_ops.toBool" },

    // Type conversion
    .{ "__int__", "runtime.float_ops.toInt" },
    .{ "__float__", "runtime.float_ops.toFloat" },

    // Conjugate (for complex compat)
    .{ "conjugate", "runtime.float_ops.conjugate" },
    .{ "real", "runtime.float_ops.real" },
    .{ "imag", "runtime.float_ops.imag" },
});

/// Methods available on Python int that need runtime dispatch
pub const IntMethods = std.StaticStringMap([]const u8).initComptime(.{
    // Bit operations
    .{ "bit_length", "runtime.int_ops.bitLength" },
    .{ "bit_count", "runtime.int_ops.bitCount" },
    .{ "to_bytes", "runtime.int_ops.toBytes" },
    .{ "from_bytes", "runtime.int_ops.fromBytes" },

    // Type conversion
    .{ "as_integer_ratio", "runtime.int_ops.asIntegerRatio" },
    .{ "__index__", "runtime.int_ops.index" },
    .{ "__int__", "runtime.int_ops.toInt" },
    .{ "__float__", "runtime.int_ops.toFloat" },

    // Math magic methods
    .{ "__floor__", "runtime.int_ops.floor" },
    .{ "__ceil__", "runtime.int_ops.ceil" },
    .{ "__trunc__", "runtime.int_ops.trunc" },
    .{ "__round__", "runtime.int_ops.round" },
    .{ "__abs__", "runtime.int_ops.abs" },

    // String conversion
    .{ "__repr__", "runtime.int_ops.repr" },
    .{ "__str__", "runtime.int_ops.str" },
    .{ "__format__", "runtime.int_ops.format" },

    // Hash and bool
    .{ "__hash__", "runtime.int_ops.hash" },
    .{ "__bool__", "runtime.int_ops.toBool" },

    // Conjugate (for complex compat)
    .{ "conjugate", "runtime.int_ops.conjugate" },
    .{ "real", "runtime.int_ops.real" },
    .{ "imag", "runtime.int_ops.imag" },

    // Numerator/denominator (for rational compat)
    .{ "numerator", "runtime.int_ops.numerator" },
    .{ "denominator", "runtime.int_ops.denominator" },
});

/// Methods available on Python dict that need runtime dispatch
/// Dict in Zig uses ArrayHashMap which has different method names
pub const DictMethods = std.StaticStringMap([]const u8).initComptime(.{
    // Mutating methods
    .{ "update", "runtime.dict_ops.update" },
    .{ "clear", "runtime.dict_ops.clear" },
    .{ "pop", "runtime.dict_ops.pop" },
    .{ "popitem", "runtime.dict_ops.popitem" },
    .{ "setdefault", "runtime.dict_ops.setdefault" },

    // Non-mutating methods
    .{ "get", "runtime.dict_ops.get" },
    .{ "keys", "runtime.dict_ops.keys" },
    .{ "values", "runtime.dict_ops.values" },
    .{ "items", "runtime.dict_ops.items" },
    .{ "copy", "runtime.dict_ops.copy" },

    // Comparison/membership
    .{ "__contains__", "runtime.dict_ops.contains" },
    .{ "__eq__", "runtime.dict_ops.eq" },
    .{ "__ne__", "runtime.dict_ops.ne" },

    // OrderedDict methods
    .{ "move_to_end", "runtime.dict_ops.moveToEnd" },

    // String conversion
    .{ "__repr__", "runtime.dict_ops.repr" },
    .{ "__str__", "runtime.dict_ops.str" },

    // Length
    .{ "__len__", "runtime.dict_ops.len" },
});

/// Methods available on Python list that need runtime dispatch
pub const ListMethods = std.StaticStringMap([]const u8).initComptime(.{
    // Mutating methods
    .{ "append", "runtime.list_ops.append" },
    .{ "extend", "runtime.list_ops.extend" },
    .{ "insert", "runtime.list_ops.insert" },
    .{ "remove", "runtime.list_ops.remove" },
    .{ "pop", "runtime.list_ops.pop" },
    .{ "clear", "runtime.list_ops.clear" },
    .{ "reverse", "runtime.list_ops.reverse" },
    .{ "sort", "runtime.list_ops.sort" },

    // Non-mutating methods
    .{ "index", "runtime.list_ops.index" },
    .{ "count", "runtime.list_ops.count" },
    .{ "copy", "runtime.list_ops.copy" },

    // String conversion
    .{ "__repr__", "runtime.list_ops.repr" },
    .{ "__str__", "runtime.list_ops.str" },

    // Length/comparison
    .{ "__len__", "runtime.list_ops.len" },
    .{ "__eq__", "runtime.list_ops.eq" },
    .{ "__contains__", "runtime.list_ops.contains" },
});

/// Check if a method name is a Python primitive method that needs dispatch
pub fn isPrimitiveMethod(method_name: []const u8) bool {
    return FloatMethods.has(method_name) or IntMethods.has(method_name);
}

/// Check if a method name is a Python dict method that needs dispatch
pub fn isDictMethod(method_name: []const u8) bool {
    return DictMethods.has(method_name);
}

/// Check if a method name is a Python list method that needs dispatch
pub fn isListMethod(method_name: []const u8) bool {
    return ListMethods.has(method_name);
}

/// Get the runtime function for a float method
pub fn getFloatMethod(method_name: []const u8) ?[]const u8 {
    return FloatMethods.get(method_name);
}

/// Get the runtime function for an int method
pub fn getIntMethod(method_name: []const u8) ?[]const u8 {
    return IntMethods.get(method_name);
}

/// Get the runtime function for a dict method
pub fn getDictMethod(method_name: []const u8) ?[]const u8 {
    return DictMethods.get(method_name);
}

/// Get the runtime function for a list method
pub fn getListMethod(method_name: []const u8) ?[]const u8 {
    return ListMethods.get(method_name);
}

/// Known methods that return context managers (for `with` statement usage)
pub const ContextManagerMethods = std.StaticStringMap([]const u8).initComptime(.{
    // unittest assertion context managers
    .{ "assertRaises", "runtime.unittest.AssertRaisesContext" },
    .{ "assertRaisesRegex", "runtime.unittest.AssertRaisesContext" },
    .{ "assertWarns", "runtime.unittest.AssertWarnsContext" },
    .{ "assertWarnsRegex", "runtime.unittest.AssertWarnsContext" },
    .{ "assertLogs", "runtime.unittest.AssertLogsContext" },
    .{ "assertNoLogs", "runtime.unittest.AssertLogsContext" },

    // File/IO context managers
    .{ "open", "runtime.io.File" },

    // Threading context managers
    .{ "Lock", "runtime.threading.Lock" },
    .{ "RLock", "runtime.threading.RLock" },

    // Contextlib
    .{ "contextmanager", "runtime.contextlib.ContextManager" },
    .{ "nullcontext", "runtime.contextlib.NullContext" },
    .{ "suppress", "runtime.contextlib.SuppressContext" },
    .{ "redirect_stdout", "runtime.contextlib.RedirectContext" },
    .{ "redirect_stderr", "runtime.contextlib.RedirectContext" },

    // Decimal context
    .{ "localcontext", "runtime.decimal.LocalContext" },

    // Warnings
    .{ "catch_warnings", "runtime.warnings.CatchWarningsContext" },
});

/// Check if a method name returns a context manager
pub fn isContextManagerMethod(method_name: []const u8) bool {
    return ContextManagerMethods.has(method_name);
}

/// Get the Zig type for a context manager method
pub fn getContextManagerType(method_name: []const u8) ?[]const u8 {
    return ContextManagerMethods.get(method_name);
}
