//! isGenerator - Check if function is a generator (uses yield)
//! USE: When deciding codegen strategy (state machine vs normal)
//! CALL: graph.isGenerator(func_name)

const CallGraph = @import("../function_traits.zig").CallGraph;

pub fn isGenerator(graph: *const CallGraph, name: []const u8) bool {
    const info = graph.functions.get(name) orelse return false;
    return info.is_generator;
}
