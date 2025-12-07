//! getCapturedVars - Get variables captured by closure
//! USE: When generating closure struct fields
//! CALL: graph.getCapturedVars(func_name)

const CallGraph = @import("../function_traits.zig").CallGraph;

pub fn getCapturedVars(graph: *const CallGraph, name: []const u8) []const []const u8 {
    const info = graph.functions.get(name) orelse return &[_][]const u8{};
    return info.captured_vars;
}
