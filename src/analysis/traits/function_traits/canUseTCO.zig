//! canUseTCO - Check if function can use tail call optimization
//! USE: When deciding if @call(.always_tail, ...) is valid
//! CALL: graph.canUseTCO(func_name)

const CallGraph = @import("../function_traits.zig").CallGraph;

pub fn canUseTCO(graph: *const CallGraph, name: []const u8) bool {
    const info = graph.functions.get(name) orelse return false;
    return info.can_tco;
}
