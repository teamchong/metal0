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
    .{ "setattr", {} }, .{ "delattr", {} },
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

    // Flush builder to output if there's pending content
    if (self.builder) |b| {
        const builder_content = b.getBodyAndClear();
        if (builder_content.len > 0) {
            try self.output.appendSlice(self.allocator, builder_content);
        }
    }

    const expr_output = self.output.items[start_pos..];

    // Check for empty block expressions {} from stub implementations
    // These are invalid Zig and should be skipped entirely
    const trimmed_expr = std.mem.trim(u8, expr_output, " \t\n");
    if (std.mem.eql(u8, trimmed_expr, "{}")) {
        // Skip empty block stub - don't generate any statement
        self.output.shrinkRetainingCapacity(start_pos);
        return;
    }

    // Detect if this is a labeled block (pattern: __mN_xxx: { ... } or set_pyval_N: { ... })
    // Labeled blocks at statement level don't need semicolons in Zig
    // BUT: Assigned labeled blocks (e.g., _ = set_pyval_39: { ... }) DO need semicolons
    const trimmed_start = std.mem.trim(u8, expr_output, " \t");
    const has_labeled_block_pattern = std.mem.indexOf(u8, expr_output, ": {") != null and
        (std.mem.startsWith(u8, trimmed_start, "__m") or
         std.mem.startsWith(u8, trimmed_start, "set_") or
         std.mem.startsWith(u8, trimmed_start, "dict_") or
         std.mem.startsWith(u8, trimmed_start, "list_"));
    const is_assigned_labeled_block = std.mem.indexOf(u8, expr_output, ": {") != null and
        std.mem.startsWith(u8, trimmed_start, "_ = ");

    // Check if this is a block statement (ends with } or }\n or }); or similar)
    // Block statements like if/while/for with braces don't need semicolons
    // Also check for labeled blocks that end with } followed by closing parens/brackets
    // EXCEPTION: `catch {}` and `catch |err| {}` are expression suffixes, NOT block statements - they need semicolons!
    const trimmed_end = std.mem.trimRight(u8, expr_output, " \t\n;");
    const ends_with_brace = trimmed_end.len > 0 and trimmed_end[trimmed_end.len - 1] == '}';

    // Check if this is a catch block suffix (pattern: "catch {}" or "catch |err| { ... }")
    // Must END with catch block, not just contain one
    // Simple heuristic: if there's a "catch |" followed by ") {", it's a catch block suffix
    const is_catch_suffix = ends_with_brace and (
        std.mem.endsWith(u8, trimmed_end, "catch {}") or
        blk: {
            if (std.mem.lastIndexOf(u8, trimmed_end, "catch |")) |catch_pos| {
                // Check if there's a ") {" pattern after the "catch |"
                if (std.mem.indexOf(u8, trimmed_end[catch_pos..], ") {")) |rel_pos| {
                    // Make sure this is at the end (no other blocks after it)
                    const abs_pos = catch_pos + rel_pos + 2; // Position of '{'
                    // Count braces from this point to end - should be balanced and end at the final '}'
                    var depth: i32 = 0;
                    var i = abs_pos;
                    while (i < trimmed_end.len) : (i += 1) {
                        if (trimmed_end[i] == '{') depth += 1
                        else if (trimmed_end[i] == '}') depth -= 1;
                    }
                    // If depth is -1, the catch block ends at the final '}'
                    break :blk depth == -1;
                }
            }
            break :blk false;
        }
    );

    // Check if this looks like a labeled block expression wrapped in parens
    // Pattern: (__mN_xxx: { ... })  or  (__mN_xxx: { ... }))
    const is_wrapped_labeled_block = has_labeled_block_pattern and
        std.mem.indexOf(u8, expr_output, "((__m") != null;

    const is_labeled_block = has_labeled_block_pattern and ends_with_brace and !is_assigned_labeled_block;
    const is_block_stmt = ends_with_brace and !is_labeled_block and !is_wrapped_labeled_block and !is_catch_suffix;

    // Determine if we should skip semicolon
    // Skip for: block statements, statement-level labeled blocks, wrapped labeled blocks
    // DON'T skip for: assigned labeled blocks (e.g., _ = __mN_xxx: { ... })
    // NOTE: If needs_discard is true, we're adding `_ = ` prefix, so labeled blocks become assignments and need semicolons
    const should_skip_semicolon = (is_block_stmt or is_labeled_block or is_wrapped_labeled_block) and !needs_discard;

    // Clear the generated output, we'll re-add it via builder
    self.output.shrinkRetainingCapacity(start_pos);

    // Context for the statement callback
    const StmtCtx = struct {
        pre_generated: []const u8,
        needs_discard: bool,
    };

    // Use builder.withStatement for atomic indent + expr + semicolon
    try builder.withStatement(
        struct {
            fn emit(b: *ZigBuilder, ctx: StmtCtx) !void {
                // Add discard prefix if needed
                if (ctx.needs_discard) {
                    try b.write("_ = ");
                }

                var output = ctx.pre_generated;

                // Strip trailing semicolons, newlines, and spaces aggressively
                // This prevents double semicolons when withStatement adds its own
                // We iterate until no more changes to handle nested patterns like "; ;" or ";\n;"
                var changed = true;
                while (changed and output.len > 0) {
                    changed = false;

                    // Pattern 1: "; ;" - semicolon, space, semicolon (common in labeled blocks)
                    if (output.len >= 3 and
                        output[output.len - 3] == ';' and
                        output[output.len - 2] == ' ' and
                        output[output.len - 1] == ';') {
                        output = output[0 .. output.len - 3]; // Remove all three chars
                        changed = true;
                        continue;
                    }

                    // Pattern 2: ";;" - double semicolon (no space)
                    if (output.len >= 2 and
                        output[output.len - 2] == ';' and
                        output[output.len - 1] == ';') {
                        output = output[0 .. output.len - 1]; // Remove one semicolon
                        changed = true;
                        continue;
                    }

                    // Pattern 3: Strip single trailing character (semicolon, newline, or space)
                    const last_char = output[output.len - 1];
                    if (last_char == ';' or last_char == '\n' or last_char == ' ' or last_char == '\t') {
                        output = output[0 .. output.len - 1];
                        changed = true;
                        continue;
                    }
                }

                try b.write(output);
            }
        }.emit,
        StmtCtx{
            .pre_generated = expr_output,
            .needs_discard = needs_discard,
        },
        .{
            .skip_semicolon = should_skip_semicolon,
        }
    );

    // Flush builder to output - now has: indent + expr + semicolon atomically
    const output = builder.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

/// Check if expression returns a value that needs `_ = ` prefix
fn shouldDiscardValue(self: *NativeCodegen, expr: ast.Node) bool {
    // Module docstrings (bare string literals) need discard
    if (expr == .constant) {
        if (expr.constant.value == .string) return true;
    }

    // Builtin function calls that return values (bool, int, float, str, etc.)
    if (expr == .call and expr.call.func.* == .name) {
        const func_name = expr.call.func.name.id;
        // Type conversion builtins always return values
        const returns_value = std.mem.eql(u8, func_name, "bool") or
            std.mem.eql(u8, func_name, "int") or
            std.mem.eql(u8, func_name, "float") or
            std.mem.eql(u8, func_name, "str") or
            std.mem.eql(u8, func_name, "bytes") or
            std.mem.eql(u8, func_name, "list") or
            std.mem.eql(u8, func_name, "dict") or
            std.mem.eql(u8, func_name, "tuple") or
            std.mem.eql(u8, func_name, "set") or
            std.mem.eql(u8, func_name, "frozenset") or
            std.mem.eql(u8, func_name, "len") or
            std.mem.eql(u8, func_name, "range") or
            std.mem.eql(u8, func_name, "abs") or
            std.mem.eql(u8, func_name, "min") or
            std.mem.eql(u8, func_name, "max") or
            std.mem.eql(u8, func_name, "sum") or
            std.mem.eql(u8, func_name, "sorted") or
            std.mem.eql(u8, func_name, "reversed") or
            std.mem.eql(u8, func_name, "enumerate") or
            std.mem.eql(u8, func_name, "zip") or
            std.mem.eql(u8, func_name, "map") or
            std.mem.eql(u8, func_name, "filter") or
            std.mem.eql(u8, func_name, "isinstance") or
            std.mem.eql(u8, func_name, "issubclass") or
            std.mem.eql(u8, func_name, "hasattr") or
            std.mem.eql(u8, func_name, "getattr") or
            std.mem.eql(u8, func_name, "callable") or
            std.mem.eql(u8, func_name, "type") or
            std.mem.eql(u8, func_name, "id") or
            std.mem.eql(u8, func_name, "hash") or
            std.mem.eql(u8, func_name, "repr") or
            std.mem.eql(u8, func_name, "format") or
            std.mem.eql(u8, func_name, "chr") or
            std.mem.eql(u8, func_name, "ord") or
            std.mem.eql(u8, func_name, "hex") or
            std.mem.eql(u8, func_name, "oct") or
            std.mem.eql(u8, func_name, "bin") or
            std.mem.eql(u8, func_name, "pow") or
            std.mem.eql(u8, func_name, "round") or
            std.mem.eql(u8, func_name, "divmod") or
            std.mem.eql(u8, func_name, "all") or
            std.mem.eql(u8, func_name, "any") or
            std.mem.eql(u8, func_name, "next") or
            std.mem.eql(u8, func_name, "iter") or
            std.mem.eql(u8, func_name, "object") or
            std.mem.eql(u8, func_name, "super") or
            std.mem.eql(u8, func_name, "property") or
            std.mem.eql(u8, func_name, "classmethod") or
            std.mem.eql(u8, func_name, "staticmethod") or
            std.mem.eql(u8, func_name, "vars") or
            std.mem.eql(u8, func_name, "dir") or
            std.mem.eql(u8, func_name, "globals") or
            std.mem.eql(u8, func_name, "locals") or
            std.mem.eql(u8, func_name, "input") or
            std.mem.eql(u8, func_name, "open") or
            std.mem.eql(u8, func_name, "eval") or
            std.mem.eql(u8, func_name, "exec") or
            std.mem.eql(u8, func_name, "compile");
        if (returns_value) return true;
    }

    // PyValue.call() dispatch
    if (expr == .call and expr.call.func.* == .attribute) {
        const attr = expr.call.func.attribute;

        // Always discard .call() method invocations (PyValue.call returns PyValue)
        if (std.mem.eql(u8, attr.attr, "call")) {
            return true;
        }

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

    // General function/closure calls that return non-void values
    // Check if this is a simple name call (could be closure, function variable, etc.)
    if (expr == .call and expr.call.func.* == .name) {
        const func_name = expr.call.func.name.id;
        // Check if it's a known function that returns void
        if (VoidFunctions.has(func_name)) {
            return false;
        }
        // For unknown functions/closures, check the inferred return type
        const func_type = self.type_inferrer.inferExpr(expr) catch .unknown;
        // If we can determine it's definitely void/none, don't discard
        if (func_type == .none) {
            return false;
        }
        // Otherwise, assume it returns a value and needs discard
        // This catches closures, PyValue variables, and other callable types
        return true;
    }

    // Labeled block expressions
    // (These will be in self.output after genExpr, we'll check them there)
    // For now, conservatively return false and let the callback check

    return false;
}
