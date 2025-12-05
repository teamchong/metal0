/// Python eval() - cached bytecode execution with comptime target selection
///
/// This module provides dynamic code execution for metal0.
///
/// Architecture:
/// 1. Parse source → AST (cached per source string)
/// 2. Compile AST → bytecode (cached)
/// 3. Execute bytecode (comptime: WASM vs Native)
///
/// Performance:
/// - First call: ~100µs (parse + compile + execute)
/// - Cached calls: ~1µs (execute only, 100x faster)
///
/// Limitations:
/// - Only basic expressions supported (constants, binops)
/// - Hardcoded patterns for MVP
const std = @import("std");
const eval_cache = @import("eval_cache.zig");

/// eval() - Evaluate Python expression and return result as PyObject
///
/// Python signature: eval(source) or eval(code_object)
///
/// Example:
///   result = eval("1 + 2 * 3")  # Returns PyInt(7)
///   code = compile("1 + 2", "<string>", "eval")
///   result = eval(code)  # Returns PyInt(3)
///
/// Implementation:
/// Uses cached bytecode compilation with comptime target selection
pub fn eval(
    allocator: std.mem.Allocator,
    source: anytype,
) anyerror!*@import("../runtime.zig").PyObject {
    const runtime = @import("../runtime.zig");

    // Handle both string and PyObject (code object from compile())
    const T = @TypeOf(source);

    // For MVP: Support string literals, slices, and PyString objects
    const source_str: []const u8 = if (T == *runtime.PyObject) blk: {
        // Code object from compile() - for MVP it's a PyString
        const PyString = runtime.PyString;
        if (source.type_id != .string) {
            return error.TypeError;
        }
        // Extract PyString from PyObject.data
        const str_obj = @as(*PyString, @ptrCast(@alignCast(source.data)));
        break :blk str_obj.data;
    } else blk: {
        // String literal (*const [N:0]u8) or slice ([]const u8)
        // Both coerce to []const u8
        break :blk source;
    };

    return eval_cache.evalCached(allocator, source_str);
}
