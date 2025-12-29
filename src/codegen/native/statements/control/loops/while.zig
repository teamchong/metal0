/// While loop code generation
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const type_traits = @import("../../../../../analysis/traits/type_traits.zig");
const bool_conv = @import("../../../helpers/bool_conv.zig");
const builder_mod = @import("codegen.builder");
const ZigBuilder = builder_mod.ZigBuilder;

/// Generate while loop
pub fn genWhile(self: *NativeCodegen, while_stmt: ast.Node.While) CodegenError!void {
    const b = try self.getBuilder();

    // Check condition type - need to handle non-boolean conditions
    const cond_type = self.type_inferrer.inferExpr(while_stmt.condition.*) catch .unknown;

    // Get bool conversion prefix/suffix for Python truthiness semantics
    const bool_prefix = bool_conv.getBoolPrefix(cond_type);
    const bool_suffix = bool_conv.getBoolSuffix(cond_type);

    // Capture the condition expression
    const cond_val = try self.captureExpr(while_stmt.condition.*);

    // Use withWhileBool which handles Python truthiness conversion automatically
    // For bool types, it passes through directly; for other types, it wraps with != 0, .len > 0, etc.
    try b.withWhileBool(cond_val, bool_prefix, bool_suffix, struct {
        fn body(builder: *ZigBuilder, ctx: anytype) !void {
            const codegen: *NativeCodegen = ctx.codegen;
            const stmt_node = ctx.while_stmt;

            // Push new scope for loop body
            try codegen.pushScope();
            defer codegen.popScope();

            // Set scope ID for scope-aware mutation tracking
            const saved_scope_id = codegen.current_scope_id;
            codegen.current_scope_id = @intFromPtr(stmt_node.body.ptr);
            defer codegen.current_scope_id = saved_scope_id;

            // Generate body statements using captureStmt
            for (stmt_node.body) |stmt| {
                const stmt_code = try codegen.captureStmt(stmt);
                try builder.write(stmt_code);
            }

            // Emit discards for loop-scoped variables
            const discards = try codegen.captureScopedDiscards();
            try builder.write(discards);
        }
    }.body, .{ .codegen = self, .while_stmt = while_stmt });

    // Handle optional else clause (while/else)
    // Note: In Python, else runs if loop completes without break.
    // For now, we emit it unconditionally (correct for loops without break)
    if (while_stmt.orelse_body) |else_body| {
        for (else_body) |stmt| {
            const stmt_code = try self.captureStmt(stmt);
            try b.write(stmt_code);
        }
    }

    // Final flush
    const output = try b.getBodyDupe();
    try self.output.appendSlice(self.allocator, output);
}
