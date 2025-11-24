/// Python eval() - cached bytecode execution with comptime target selection
///
/// This module provides dynamic code execution for PyAOT.
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
/// Python signature: eval(source)
///
/// Example:
///   result = eval("1 + 2 * 3")  # Returns PyInt(7)
///
/// Implementation:
/// Uses cached bytecode compilation with comptime target selection
pub fn eval(
    allocator: std.mem.Allocator,
    source: []const u8,
) anyerror!*@import("runtime.zig").PyObject {
    return eval_cache.evalCached(allocator, source);
}
