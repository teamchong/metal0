//! buildCallGraph - Build call graph for module analysis
//! USE: At start of codegen to analyze all functions
//! CALL: function_traits.buildCallGraph(module, allocator)
//! RETURNS: CallGraph with info about all functions

const std = @import("std");
const ast = @import("../../ast.zig");
const CallGraph = @import("../function_traits.zig").CallGraph;

pub fn buildCallGraph(module: ast.Node.Module, allocator: std.mem.Allocator) !CallGraph {
    return @import("../function_traits.zig").buildCallGraph(module, allocator);
}
