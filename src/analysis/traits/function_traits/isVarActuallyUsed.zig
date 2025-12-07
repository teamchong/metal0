//! isVarActuallyUsed - Check if variable is actually used after declaration
//! USE: When deciding if unused var warning should be emitted
//! CALL: function_traits.isVarActuallyUsed(body, var_name)

const ast = @import("../../ast.zig");

pub fn isVarActuallyUsed(body: []const ast.Node, var_name: []const u8) bool {
    return @import("../function_traits.zig").isVarActuallyUsed(body, var_name);
}
