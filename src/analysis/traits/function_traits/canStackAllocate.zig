//! canStackAllocate - Check if local var can use stack allocation
//! USE: When deciding var storage (stack frame vs heap)
//! CALL: graph.canStackAllocate(func_name, var_name)

const std = @import("std");
const CallGraph = @import("../function_traits.zig").CallGraph;

pub fn canStackAllocate(graph: *const CallGraph, func_name: []const u8, var_name: []const u8) bool {
    const info = graph.functions.get(func_name) orelse return false;
    for (info.non_escaping_locals) |local| {
        if (std.mem.eql(u8, local, var_name)) return true;
    }
    return false;
}
