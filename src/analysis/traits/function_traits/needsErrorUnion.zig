//! needsErrorUnion - Check if function needs error union return type
//! USE: When generating function signatures (fn() !ReturnType)
//! CALL: graph.needsErrorUnion(func_name)

const CallGraph = @import("../function_traits.zig").CallGraph;

pub fn needsErrorUnion(graph: *const CallGraph, name: []const u8) bool {
    const info = graph.functions.get(name) orelse return false;
    return info.error_set != .none;
}
