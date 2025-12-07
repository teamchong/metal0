//! needsAllocator - Check if function needs allocator parameter
//! USE: When generating function signatures
//! CALL: graph.needsAllocator(func_name)

const CallGraph = @import("../function_traits.zig").CallGraph;

pub fn needsAllocator(graph: *const CallGraph, name: []const u8) bool {
    const info = graph.functions.get(name) orelse return false;
    return info.uses_allocator;
}
