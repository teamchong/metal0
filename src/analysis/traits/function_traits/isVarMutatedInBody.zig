//! isVarMutatedInBody - Check if variable is mutated in function body
//! USE: When deciding if var should be mut/const in Zig
//! CALL: function_traits.isVarMutatedInBody(body, var_name)

const ast = @import("../../ast.zig");

pub fn isVarMutatedInBody(body: []const ast.Node, var_name: []const u8) bool {
    return @import("../function_traits.zig").isVarMutatedInBody(body, var_name);
}
