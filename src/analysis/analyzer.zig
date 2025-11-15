const std = @import("std");
const ast = @import("../ast.zig");
const types = @import("types.zig");
const lifetime = @import("lifetime.zig");
const expressions = @import("expressions.zig");

/// Main entry point for semantic analysis
/// Analyzes the AST and returns semantic information for optimization
pub fn analyze(allocator: std.mem.Allocator, tree: ast.Node) !types.SemanticInfo {
    var info = types.SemanticInfo.init(allocator);
    errdefer info.deinit();

    // Phase 1: Analyze variable lifetimes
    _ = try lifetime.analyzeLifetimes(&info, tree, 1);

    // Phase 2: Detect expression patterns
    try expressions.analyzeExpressions(&info, tree);

    return info;
}

/// Analyze a single node (for incremental analysis)
pub fn analyzeNode(info: *types.SemanticInfo, node: ast.Node) !void {
    _ = try lifetime.analyzeLifetimes(info, node, 1);
    try expressions.analyzeExpressions(info, node);
}
