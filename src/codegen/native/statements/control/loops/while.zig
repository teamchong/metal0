/// While loop code generation
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const type_traits = @import("../../../../../analysis/traits/type_traits.zig");
const bool_conv = @import("../../../helpers/bool_conv.zig");

/// Generate while loop
pub fn genWhile(self: *NativeCodegen, while_stmt: ast.Node.While) CodegenError!void {
    const b = try self.getBuilder();

    try b.writeIndent();
    try b.write("while (");

    // Check condition type - need to handle non-boolean conditions
    const cond_type = self.type_inferrer.inferExpr(while_stmt.condition.*) catch .unknown;
    // TWO-FLOW: Check for both .unknown and .pyvalue (uncertain types)
    if (type_traits.isUnknown(cond_type) or cond_type == .pyvalue) {
        // Unknown/PyValue type - use runtime truthiness check
        try b.write("runtime.pyTruthy(");
        const cond_val = try self.captureExpr(while_stmt.condition.*);
        try b.emitValue(cond_val, .{});
        try b.write(")");
    } else {
        // Use type-specific inline bool conversion to avoid anytype monomorphization
        const prefix = bool_conv.getBoolPrefix(cond_type);
        const suffix = bool_conv.getBoolSuffix(cond_type);
        try b.write(prefix);
        const cond_val = try self.captureExpr(while_stmt.condition.*);
        try b.emitValue(cond_val, .{});
        try b.write(suffix);
    }

    try b.write(") {\n");

    // Flush builder before generating body
    const builder_output = b.getBody();
    try self.output.appendSlice(self.allocator, builder_output);

    // Indent for loop body
    self.indent();

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

    // Close while block
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // Handle optional else clause (while/else)
    // Note: In Python, else runs if loop completes without break.
    // For now, we emit it unconditionally (correct for loops without break)
    if (while_stmt.orelse_body) |else_body| {
        for (else_body) |stmt| {
            try self.generateStmt(stmt);
        }
    }
}
