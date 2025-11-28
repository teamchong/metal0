/// While loop code generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;

/// Generate while loop
pub fn genWhile(self: *NativeCodegen, while_stmt: ast.Node.While) CodegenError!void {
    const CodeBuilder = @import("../../../code_builder.zig").CodeBuilder;
    var builder = CodeBuilder.init(self);

    try self.emitIndent();
    _ = try builder.write("while (");
    try self.genExpr(while_stmt.condition.*);
    _ = try builder.write(")");
    _ = try builder.beginBlock();

    // Push new scope for loop body
    try self.pushScope();

    for (while_stmt.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting loop
    self.popScope();

    _ = try builder.endBlock();

    // Handle optional else clause (while/else)
    // Note: In Python, else runs if loop completes without break.
    // For now, we emit it unconditionally (correct for loops without break)
    if (while_stmt.orelse_body) |else_body| {
        for (else_body) |stmt| {
            try self.generateStmt(stmt);
        }
    }
}
