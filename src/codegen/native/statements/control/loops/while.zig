/// While loop code generation
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const type_traits = @import("../../../../../analysis/traits/type_traits.zig");
const bool_conv = @import("../../../helpers/bool_conv.zig");

/// Generate while loop
pub fn genWhile(self: *NativeCodegen, while_stmt: ast.Node.While) CodegenError!void {
    const CodeBuilder = @import("../../../code_builder.zig").CodeBuilder;
    var builder = CodeBuilder.init(self);

    try self.emitIndent();
    _ = try builder.write("while (");

    // Check condition type - need to handle non-boolean conditions
    const cond_type = self.type_inferrer.inferExpr(while_stmt.condition.*) catch .unknown;
    if (type_traits.isUnknown(cond_type)) {
        // Unknown type (PyObject) - use runtime truthiness check
        _ = try builder.write("runtime.pyTruthy(");
        try self.genExpr(while_stmt.condition.*);
        _ = try builder.write(")");
    } else {
        // Use type-specific inline bool conversion to avoid anytype monomorphization
        const prefix = bool_conv.getBoolPrefix(cond_type);
        const suffix = bool_conv.getBoolSuffix(cond_type);
        _ = try builder.write(prefix);
        try self.genExpr(while_stmt.condition.*);
        _ = try builder.write(suffix);
    }

    _ = try builder.write(")");
    _ = try builder.beginBlock();

    // Push new scope for loop body
    try self.pushScope();

    // Set scope ID for scope-aware mutation tracking
    // Each loop body is a unique scope (using pointer address)
    const saved_scope_id = self.current_scope_id;
    self.current_scope_id = @intFromPtr(while_stmt.body.ptr);
    defer self.current_scope_id = saved_scope_id;

    for (while_stmt.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Emit discards for loop-scoped variables before they go out of scope
    try self.emitScopedDiscards();
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
