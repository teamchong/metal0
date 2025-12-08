//! needsErrorUnion - Check if function needs error union return type
//! USE: When generating function signatures (fn() !ReturnType)
//! CALL: graph.needsErrorUnion(func_name)

const CallGraph = @import("../function_traits.zig").CallGraph;

pub fn needsErrorUnion(graph: *const CallGraph, name: []const u8) bool {
    const info = graph.functions.get(name) orelse return false;
    // Check if error_types has any error flags set (not empty)
    return !info.error_types.isEmpty();
}
