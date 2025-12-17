/// Global statement code generation
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;

/// Generate global statement
/// The global statement itself doesn't emit code - it just marks variables as global
/// so that subsequent assignments reference the outer scope variable instead of creating a new one
pub fn genGlobal(self: *NativeCodegen, global_node: ast.Node.GlobalStmt) CodegenError!void {
    // Mark each variable as global
    for (global_node.names) |name| {
        try self.markGlobalVar(name);
    }
    // No code emitted - this is a directive, not an executable statement
}
