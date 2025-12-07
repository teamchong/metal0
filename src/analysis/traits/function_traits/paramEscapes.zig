//! paramEscapes - Check if parameter escapes function scope
//! USE: When deciding stack vs heap allocation for arg
//! CALL: graph.paramEscapes(func_name, param_idx)

const CallGraph = @import("../function_traits.zig").CallGraph;

pub fn paramEscapes(graph: *const CallGraph, func_name: []const u8, param_idx: usize) bool {
    const info = graph.functions.get(func_name) orelse return false;
    return info.escaping_params.isSet(param_idx);
}
