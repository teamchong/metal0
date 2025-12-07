//! isPure - Check if function has no side effects
//! USE: For optimization (can cache results, hoist out of loops)
//! CALL: graph.isPure(func_name)

const CallGraph = @import("../function_traits.zig").CallGraph;

pub fn isPure(graph: *const CallGraph, name: []const u8) bool {
    const info = graph.functions.get(name) orelse return false;
    return info.is_pure;
}
