/// Python logic_table module - @logic_table decorator for compiled Python
///
/// The @logic_table decorator compiles Python classes to native Zig code.
/// Python for loops are ACTUALLY compiled - no template substitution.
///
/// Example:
/// ```python
/// from logic_table import logic_table
///
/// @logic_table
/// class VectorOps:
///     def dot_product(self, a, b):
///         result = 0.0
///         for i in range(len(a)):
///             result = result + a[i] * b[i]
///         return result
/// ```
///
/// This compiles the actual Python for loop to native Zig code.
///
const std = @import("std");
const h = @import("mod_helper.zig");

/// Module functions for logic_table
/// Only the decorator - Python code is compiled by metal0's standard codegen
pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "logic_table", logicTableDecorator },
});

/// @logic_table decorator - marks class for compilation
/// Returns struct type with _is_logic_table marker
fn logicTableDecorator(self: *h.NativeCodegen, args: []@import("analysis.ast").Node) h.CodegenError!void {
    _ = args;
    try self.emit("struct { _is_logic_table: bool = true }{}");
}
