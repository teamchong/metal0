//! isParamMutated - Check if function parameter is mutated
//! USE: When deciding if param needs copy or can be borrowed
//! CALL: graph.isParamMutated(func_name, param_idx)

const CallGraph = @import("../function_traits.zig").CallGraph;

pub fn isParamMutated(graph: *const CallGraph, func_name: []const u8, param_idx: usize) bool {
    const info = graph.functions.get(func_name) orelse return false;
    return info.mutated_params.isSet(param_idx);
}
