/// Expression statement code generation
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;

// Trait imports for type checking
const type_traits = @import("../../../../analysis/traits/type_traits.zig");

const ValueReturningBuiltins = std.StaticStringMap(void).initComptime(.{
    .{ "list", {} }, .{ "dict", {} }, .{ "set", {} }, .{ "tuple", {} }, .{ "frozenset", {} },
    .{ "str", {} }, .{ "int", {} }, .{ "float", {} }, .{ "bool", {} }, .{ "bytes", {} }, .{ "bytearray", {} },
    .{ "range", {} }, .{ "enumerate", {} }, .{ "zip", {} }, .{ "map", {} }, .{ "filter", {} }, .{ "sorted", {} }, .{ "reversed", {} },
    .{ "len", {} }, .{ "abs", {} }, .{ "min", {} }, .{ "max", {} }, .{ "sum", {} }, .{ "round", {} }, .{ "pow", {} },
    .{ "ord", {} }, .{ "chr", {} }, .{ "hex", {} }, .{ "oct", {} }, .{ "bin", {} },
    .{ "type", {} }, .{ "id", {} }, .{ "hash", {} }, .{ "repr", {} }, .{ "ascii", {} },
    .{ "iter", {} }, .{ "next", {} }, .{ "slice", {} }, .{ "object", {} },
    .{ "vars", {} }, .{ "dir", {} }, .{ "locals", {} }, .{ "globals", {} },
    .{ "callable", {} }, .{ "isinstance", {} }, .{ "issubclass", {} }, .{ "hasattr", {} }, .{ "getattr", {} },
    .{ "format", {} }, .{ "input", {} },
});

const VoidFunctions = std.StaticStringMap(void).initComptime(.{
    .{ "main", {} }, .{ "exit", {} }, .{ "seed", {} },
});

/// Generate expression statement (expression with semicolon)
pub fn genExprStmt(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    try self.emitIndent();

    // Special handling for print()
    if (expr == .call and expr.call.func.* == .name) {
        const func_name = expr.call.func.name.id;
        if (std.mem.eql(u8, func_name, "print")) {
            const io = @import("../../builtins/io.zig");
            try io.genPrintWithKeywords(self, expr.call.args, expr.call.keyword_args);
            try self.emit(";\n");
            return;
        }
    }

    // Special handling for unittest.main() - generates complete block with its own structure
    // Also handle assertion methods - they generate complete if statements with semicolons
    if (expr == .call and expr.call.func.* == .attribute) {
        const attr = expr.call.func.attribute;
        if (attr.value.* == .name) {
            const obj_name = attr.value.name.id;
            const method_name = attr.attr;
            if (std.mem.eql(u8, obj_name, "unittest") and std.mem.eql(u8, method_name, "main")) {
                // unittest.main() generates its own complete output
                try self.genExpr(expr);
                return;
            }
            // ONLY these assertion methods generate inline if statements with their own semicolons:
            // assertEqual, assertNotEqual, assertLess, assertLessEqual, assertGreater, assertGreaterEqual
            // All others (assertTrue, assertFalse, assertIn, assertNotIn, assertIs, assertIsInstance, etc.)
            // generate function calls like "try unittest.assertXxx(...)" that need semicolons
            const inline_assertions = [_][]const u8{
                "assertEqual", "assertNotEqual",
                "assertLess", "assertLessEqual", "assertGreater", "assertGreaterEqual",
            };
            if (std.mem.eql(u8, obj_name, "self")) {
                for (inline_assertions) |inline_assert| {
                    if (std.mem.eql(u8, method_name, inline_assert)) {
                        try self.genExpr(expr);
                        return;
                    }
                }
            }
            // Note: unittest.assert*() calls and non-inline self.assert*() calls are regular function calls that DO need semicolons
            // (handled by the normal path below)
        }
    }

    // Track if we added "_ = " prefix - if so, we ALWAYS need a semicolon
    var added_discard_prefix = false;

    // Discard string constants (docstrings) by assigning to _
    // Zig requires all non-void values to be used
    if (expr == .constant and expr.constant.value == .string) {
        try self.emit("_ = ");
        added_discard_prefix = true;
    }

    // Discard binary operator results on class instances (e.g., x / 1 where x has __truediv__)
    // These generate method calls that return values
    if (expr == .binop) {
        const left_type = try self.inferExprScoped(expr.binop.left.*);
        if (type_traits.isClassInstance(left_type)) {
            try self.emit("_ = ");
            added_discard_prefix = true;
        } else {
            const right_type = try self.inferExprScoped(expr.binop.right.*);
            if (type_traits.isClassInstance(right_type)) {
                try self.emit("_ = ");
                added_discard_prefix = true;
            }
        }
    }

    // Discard return values from function calls (Zig requires all non-void values to be used)
    if (expr == .call and expr.call.func.* == .name) {
        const func_name = expr.call.func.name.id;

        // Builtin functions that return non-void values need _ = prefix
        if (ValueReturningBuiltins.has(func_name)) {
            try self.emit("_ = ");
            added_discard_prefix = true;
        } else if (self.closure_vars.contains(func_name)) {
            // Check if this is a void-returning closure (like one that calls assertRaises)
            if (self.void_closure_vars.contains(func_name)) {
                // Void closure - just call it directly without catch
                try self.genExpr(expr);
                try self.emit(";\n");
                return;
            }
            // Closure calls return error unions - discard both value and error
            // The closure call generates "(try closure.call(...))" which unwraps the error
            // We need to use _ = to discard the return value
            // DO NOT add "catch {}" because "try" already unwraps the error
            try self.emit("_ = ");
            added_discard_prefix = true;
            try self.genExpr(expr);
            try self.emit(";\n");
            return;
        } else if (self.type_inferrer.func_return_types.get(func_name)) |return_type| {
            // Check if function returns non-void type
            // Skip void returns
            if (return_type != .unknown) {
                try self.emit("_ = ");
                added_discard_prefix = true;
            }
        } else if (self.var_renames.get(func_name)) |renamed| {
            // Variables renamed from type attributes (e.g., int_class -> _local_int_class)
            // These hold type constructors like int which return values
            _ = renamed;
            try self.emit("_ = ");
            added_discard_prefix = true;
        }
    }

    // Handle type attribute calls (e.g., self.int_class(...))
    // These return values and need _ = prefix
    if (expr == .call and expr.call.func.* == .attribute) {
        const attr = expr.call.func.attribute;
        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
            if (self.current_class_name) |class_name| {
                var type_attr_key_buf: [512]u8 = undefined;
                const type_attr_key = std.fmt.bufPrint(&type_attr_key_buf, "{s}.{s}", .{ class_name, attr.attr }) catch null;
                if (type_attr_key) |key| {
                    if (self.class_type_attrs.get(key)) |_| {
                        // This is a type attribute call - it returns a value
                        try self.emit("_ = ");
                        added_discard_prefix = true;
                    }
                }
            }
        }
    }

    // Discard return values from module function calls (e.g., tokenizer.encode())
    // Generic: use import_registry to check if module function returns a value
    if (expr == .call and expr.call.func.* == .attribute) {
        const attr = expr.call.func.attribute;
        if (attr.value.* == .name) {
            const module_alias = attr.value.name.id;
            const func_name = attr.attr;

            // Skip known void functions
            if (VoidFunctions.has(func_name)) {
                // Fall through - don't add discard prefix
            } else {
                // Resolve module alias to full module path (e.g., "tokenizer" -> "metal0.tokenizer")
                const full_module = self.local_from_imports.get(module_alias) orelse module_alias;

                // Check import_registry for function metadata
                if (self.import_registry.getFunctionMeta(full_module, func_name)) |meta| {
                    // If function has metadata, it's a known module function that returns a value
                    _ = meta;
                    try self.emit("_ = ");
                    added_discard_prefix = true;
                } else if (self.local_from_imports.contains(module_alias)) {
                    // Module was imported but function not in registry - assume it returns a value
                    try self.emit("_ = ");
                    added_discard_prefix = true;
                }
            }
        }
    }

    const before_len = self.output.items.len;
    try self.genExpr(expr);

    // Check if generated code ends with a block statement (not struct initializers)
    const generated = self.output.items[before_len..];

    // Skip empty expression statements (e.g., void functions that emit just "{}")
    // These are no-ops that would generate invalid "{};
    if (std.mem.eql(u8, generated, "{}")) {
        // Remove the "{}" and the indent we emitted
        self.output.shrinkRetainingCapacity(before_len - self.indent_level * 4);
        return;
    }

    // If nothing was generated and we added a discard prefix, remove it all
    // This handles cases where genExpr produces no output (e.g., unsupported expressions)
    if (generated.len == 0) {
        if (added_discard_prefix) {
            // Remove the "_ = " prefix and indent we emitted
            // "_ = " is 4 chars, plus indent
            self.output.shrinkRetainingCapacity(before_len - 4);
        }
        return;
    }

    // Early check: if statements are complete statements that don't need _ = prefix
    // This must be checked BEFORE the needs_discard block since that block modifies the buffer
    const is_if_statement = std.mem.startsWith(u8, generated, "if (");

    // Detect value-returning expressions that need _ = prefix:
    // 1. Labeled block expressions: (blk: { ... break :blk value; })
    // 2. Try expressions for module functions: try runtime.tokenizer.init(...)
    // NOTE: if statements are excluded even if they contain value-returning sub-expressions
    const needs_discard = blk: {
        if (added_discard_prefix) break :blk false;
        if (is_if_statement) break :blk false; // if statements are complete, don't add _ =
        if (generated.len <= 10) break :blk false;

        // Pattern 1: Labeled block expressions
        // Matches both old style "(blk: {" and new style "(__m{d}_xxx: {"
        if ((std.mem.startsWith(u8, generated, "(blk: {") and std.mem.indexOf(u8, generated, "break :blk") != null) or
            (std.mem.startsWith(u8, generated, "(__m") and std.mem.indexOf(u8, generated, ": {") != null and std.mem.indexOf(u8, generated, "break :__m") != null))
        {
            break :blk true;
        }

        // Pattern 2: Try expressions for runtime module functions that return values
        // Generic: any "try runtime.xxx.yyy(...)" call returns a value
        // Also includes unittest module functions (aliased as runtime.Lib.unittest)
        if (std.mem.startsWith(u8, generated, "try runtime.") or std.mem.startsWith(u8, generated, "try unittest.")) {
            // Find if it's a function call (has parentheses after module.func)
            if (std.mem.indexOf(u8, generated, "(") != null) {
                break :blk true;
            }
        }

        // Pattern 3: Expressions ending with .len (count_tokens returns usize)
        if (std.mem.endsWith(u8, generated, ").len")) {
            break :blk true;
        }

        // Pattern 4: Labeled blocks that return values (struct.pack, struct.unpack, struct.calcsize)
        if (std.mem.indexOf(u8, generated, "struct_pack_blk:") != null) break :blk true;
        if (std.mem.indexOf(u8, generated, "struct_unpack_blk:") != null) break :blk true;
        if (std.mem.indexOf(u8, generated, "struct_calcsize_blk:") != null) break :blk true;

        break :blk false;
    };

    if (needs_discard) {
        // Insert "_ = " before the expression
        const indent_len = self.indent_level * 4;
        const expr_start = before_len - indent_len;

        // Temporarily store the generated content
        const gen_copy = self.arena.allocator().dupe(u8, self.output.items[expr_start..]) catch return error.OutOfMemory;
        defer self.allocator.free(gen_copy);

        // Reset to before indent and re-emit with _ =
        self.output.shrinkRetainingCapacity(expr_start);
        try self.emitIndent();
        try self.emit("_ = ");
        try self.emit(gen_copy[indent_len..]); // Skip the indent we already re-emitted
        added_discard_prefix = true;
    }

    // Determine if we need a semicolon:
    // - If we added "_ = " prefix, we ALWAYS need a semicolon (it's an assignment)
    // - Struct initializers like "Type{}" need semicolons
    // - Statement blocks like "{ ... }" do NOT need semicolons
    // - Labeled blocks like "blk: { ... }" do NOT need semicolons
    // - If statements like "if (...) return error.AssertionFailed;" are complete and do NOT need semicolons
    var needs_semicolon = true;

    // If statements are complete statements - no semicolon needed
    // (is_if_statement was checked early, before any buffer modifications)
    if (is_if_statement) {
        needs_semicolon = false;
    }
    // If we added "_ = " prefix, it's an assignment that always needs semicolon
    else if (!added_discard_prefix and generated.len > 0 and generated[generated.len - 1] == '}') {
        // Check for labeled blocks (e.g., "blk: {", "sub_0: {", "slice_1: {", "comp_2: {", "__m{d}_xxx: {")
        // Pattern: identifier followed by colon and space then brace
        const is_labeled_block = blk: {
            // Check for new unique ID label pattern __m{d}_xxx: {
            if (std.mem.indexOf(u8, generated, "__m") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            // Check for common label patterns
            if (std.mem.indexOf(u8, generated, "blk: {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "__asyncio_run: {") != null) break :blk true;
            // Assertion-related labeled blocks
            if (std.mem.indexOf(u8, generated, "__ar_obj_blk: {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "__ar_noarg_blk: {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "__ar_blk: {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "ar_closure_blk: {") != null) break :blk true;
            // Collection and iterator labeled blocks
            if (std.mem.indexOf(u8, generated, "list_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "mcall_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "tuple_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "iter_blk: {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "cast_blk: {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "sub_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "slice_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "comp_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "dict_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "gen_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "idx_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "str_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "arr_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "discard_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            // Generic check: look for pattern like "word_N: {" at the start
            if (generated.len >= 6) {
                // Check if starts with a label pattern (letters/underscore followed by digits, then ": {")
                var i: usize = 0;
                while (i < generated.len and (std.ascii.isAlphabetic(generated[i]) or generated[i] == '_')) : (i += 1) {}
                while (i < generated.len and std.ascii.isDigit(generated[i])) : (i += 1) {}
                if (i > 0 and i + 3 < generated.len and std.mem.eql(u8, generated[i .. i + 3], ": {")) {
                    break :blk true;
                }
            }
            break :blk false;
        };

        if (is_labeled_block) {
            needs_semicolon = false;
        }
        // Check for comptime blocks - "comptime { ... }"
        else if (std.mem.startsWith(u8, generated, "comptime ")) {
            needs_semicolon = false;
        }
        // Check for anonymous statement blocks - starts with "{ " (not "Type{")
        // Statement blocks: "{ const x = ...; }"
        // Struct initializers: "Type{}" or "Type{ .field = value }"
        else if (generated.len >= 2) {
            // Find the first '{' and check what's before it
            if (std.mem.indexOf(u8, generated, "{ ")) |brace_pos| {
                if (brace_pos == 0) {
                    // Starts with "{ " - it's a statement block
                    needs_semicolon = false;
                }
            }
        }
    }

    if (needs_semicolon) {
        try self.emit(";\n");
    } else {
        try self.emit("\n");
    }
}
