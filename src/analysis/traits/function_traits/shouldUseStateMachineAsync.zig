//! shouldUseStateMachineAsync - Check if async needs state machine
//! USE: When deciding async codegen strategy
//! CALL: graph.shouldUseStateMachineAsync(func_name)

const CallGraph = @import("../function_traits.zig").CallGraph;

pub fn shouldUseStateMachineAsync(graph: *const CallGraph, name: []const u8) bool {
    const info = graph.functions.get(name) orelse return false;
    return info.is_async and (info.async_complexity == .complex or info.async_complexity == .loop_with_await);
}
