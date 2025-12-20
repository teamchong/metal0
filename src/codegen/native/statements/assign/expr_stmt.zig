/// Expression statement code generation - MIGRATED to builder.withStatement()
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const builder_mod = @import("codegen.builder");
const ZigBuilder = builder_mod.ZigBuilder;

// Trait imports for type checking
const type_traits = @import("../../../../analysis/traits/type_traits.zig");

const VoidFunctions = std.StaticStringMap(void).initComptime(.{
    .{ "main", {} }, .{ "exit", {} }, .{ "seed", {} },
});

/// Generate expression statement using builder.withStatement() for atomic semicolons
pub fn genExprStmt(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    const builder = try self.getBuilder();

    // Special handling for print()
    if (expr == .call and expr.call.func.* == .name) {
        const func_name = expr.call.func.name.id;
        if (std.mem.eql(u8, func_name, "print")) {
            const StmtCtx = struct {
                codegen: *NativeCodegen,
                args: []ast.Node,
                kwargs: []const ast.Node.KeywordArg,
                start_pos: usize,
            };

            const start_pos = self.output.items.len;

            try builder.withStatement(
                struct {
                    fn emit(b: *ZigBuilder, ctx: StmtCtx) !void {
                        const io = @import("../../builtins/io.zig");
                        try io.genPrintWithKeywords(ctx.codegen, ctx.args, ctx.kwargs);

                        // Capture what was written and move to builder
                        const print_output = ctx.codegen.output.items[ctx.start_pos..];
                        ctx.codegen.output.shrinkRetainingCapacity(ctx.start_pos);
                        try b.write(print_output);
                    }
                }.emit,
                StmtCtx{
                    .codegen = self,
                    .args = expr.call.args,
                    .kwargs = expr.call.keyword_args,
                    .start_pos = start_pos,
                },
                .{ .skip_semicolon = false }
            );

            // Flush builder to output
            const output = builder.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
            return;
        }
    }

    // Special handling for unittest.main() - complete block
    if (expr == .call and expr.call.func.* == .attribute) {
        const attr = expr.call.func.attribute;
        if (attr.value.* == .name) {
            const obj_name = attr.value.name.id;
            const method_name = attr.attr;
            if (std.mem.eql(u8, obj_name, "unittest") and std.mem.eql(u8, method_name, "main")) {
                // unittest.main() is a complete statement - no semicolon
                try self.emitIndent();
                try self.genExpr(expr);
                try self.output.append(self.allocator, '\n');
                return;
            }
        }
    }

    // Check if expression needs value discard
    const needs_discard = shouldDiscardValue(self, expr);

    // Pre-generate expression to detect labeled blocks and block statements
    const start_pos = self.output.items.len;
    try self.genExpr(expr);
    const expr_output = self.output.items[start_pos..];

    // Detect if this is a labeled block (pattern: __mN_xxx: { ... })
    // Labeled blocks at statement level don't need semicolons in Zig
    const is_labeled_block = std.mem.indexOf(u8, expr_output, ": {") != null and
        std.mem.startsWith(u8, std.mem.trim(u8, expr_output, " \t"), "__m");

    // Check if this is a block statement (ends with } or }\n)
    // Block statements like if/while/for with braces don't need semicolons
    const ends_with_brace = (expr_output.len > 0 and expr_output[expr_output.len - 1] == '}') or
        (expr_output.len >= 2 and expr_output[expr_output.len - 2] == '}' and expr_output[expr_output.len - 1] == '\n');
    const is_block_stmt = ends_with_brace and !is_labeled_block;

    // Determine if we should skip semicolon
    // Only skip for block statements and labeled blocks, NOT for expressions that already have semicolons
    // (we'll strip existing semicolons in the callback, then add them back via withStatement)
    const should_skip_semicolon = is_block_stmt or is_labeled_block;

    // Clear the generated output, we'll re-add it via builder
    self.output.shrinkRetainingCapacity(start_pos);

    // Context for the statement callback
    const StmtCtx = struct {
        pre_generated: []const u8,
    };

    // Use builder.withStatement for atomic indent + expr + semicolon
    try builder.withStatement(
        struct {
            fn emit(b: *ZigBuilder, ctx: StmtCtx) !void {
                var output = ctx.pre_generated;

                // Strip trailing semicolon+newline or just newline
                if (output.len >= 2 and output[output.len - 2] == ';' and output[output.len - 1] == '\n') {
                    output = output[0 .. output.len - 2];
                } else if (output.len > 0 and output[output.len - 1] == '\n') {
                    output = output[0 .. output.len - 1];
                }

                try b.write(output);
            }
        }.emit,
        StmtCtx{
            .pre_generated = expr_output,
        },
        .{
            .add_discard = needs_discard,
            .skip_semicolon = should_skip_semicolon,
        }
    );

    // Flush builder to output - now has: indent + expr + semicolon atomically
    const output = builder.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

/// Check if expression returns a value that needs `_ = ` prefix
fn shouldDiscardValue(self: *NativeCodegen, expr: ast.Node) bool {
    // PyValue.call() dispatch
    if (expr == .call and expr.call.func.* == .attribute) {
        const attr = expr.call.func.attribute;
        const attr_type = self.type_inferrer.inferExpr(expr.call.func.*) catch .unknown;

        if (attr_type == .pyvalue) return true;
        if (attr_type == .unknown) {
            const obj_type = self.type_inferrer.inferExpr(attr.value.*) catch .unknown;
            if (obj_type == .class_instance) {
                const class_name = obj_type.class_instance;
                if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                    if (class_info.fields.get(attr.attr)) |field_type| {
                        if (field_type == .unknown or field_type == .pyvalue) {
                            return true;
                        }
                    }
                }
            }
        }
    }

    // Module function calls
    if (expr == .call and expr.call.func.* == .attribute) {
        const attr = expr.call.func.attribute;
        if (attr.value.* == .name) {
            const module_alias = attr.value.name.id;
            const func_name = attr.attr;

            if (!VoidFunctions.has(func_name)) {
                const full_module = self.local_from_imports.get(module_alias) orelse module_alias;
                if (self.import_registry.getFunctionMeta(full_module, func_name)) |_| {
                    return true;
                } else if (self.local_from_imports.contains(module_alias)) {
                    return true;
                }
            }
        }
    }

    // Labeled block expressions
    // (These will be in self.output after genExpr, we'll check them there)
    // For now, conservatively return false and let the callback check

    return false;
}
