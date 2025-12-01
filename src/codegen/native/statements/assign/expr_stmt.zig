/// Expression statement code generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;

/// Generate expression statement (expression with semicolon)
pub fn genExprStmt(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    try self.emitIndent();

    // Special handling for print()
    if (expr == .call and expr.call.func.* == .name) {
        const func_name = expr.call.func.name.id;
        if (std.mem.eql(u8, func_name, "print")) {
            const genPrint = @import("../misc.zig").genPrint;
            try genPrint(self, expr.call.args);
            return;
        }
    }

    // Special handling for unittest.main() - generates complete block with its own structure
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

    // Discard return values from function calls (Zig requires all non-void values to be used)
    if (expr == .call and expr.call.func.* == .name) {
        const func_name = expr.call.func.name.id;

        // Builtin functions that return non-void values need _ = prefix
        const value_returning_builtins = [_][]const u8{
            "list", "dict", "set", "tuple", "frozenset",
            "str", "int", "float", "bool", "bytes", "bytearray",
            "range", "enumerate", "zip", "map", "filter", "sorted", "reversed",
            "len", "abs", "min", "max", "sum", "round", "pow",
            "ord", "chr", "hex", "oct", "bin",
            "type", "id", "hash", "repr", "ascii",
            "iter", "next", "slice", "object",
            "vars", "dir", "locals", "globals",
            "callable", "isinstance", "issubclass", "hasattr", "getattr",
            "format", "input",
        };

        var is_value_returning_builtin = false;
        for (value_returning_builtins) |builtin| {
            if (std.mem.eql(u8, func_name, builtin)) {
                is_value_returning_builtin = true;
                break;
            }
        }

        if (is_value_returning_builtin) {
            try self.emit("_ = ");
            added_discard_prefix = true;
        } else if (self.closure_vars.contains(func_name)) {
            // Closure calls return error unions - discard both value and error
            // Generate: _ = call(...) catch {}
            try self.emit("_ = ");
            added_discard_prefix = true;
            // Mark that we need to append " catch {}" after the expression
            // We'll use a simple approach: generate expr then append
            try self.genExpr(expr);
            try self.emit(" catch {};\n");
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

    // Discard return values from module function calls (e.g., secrets.token_bytes())
    // These generate labeled blocks that return values
    if (expr == .call and expr.call.func.* == .attribute) {
        const attr = expr.call.func.attribute;
        if (attr.value.* == .name) {
            const module_name = attr.value.name.id;
            const func_name = attr.attr;

            // Modules with value-returning functions
            const value_returning_modules = [_][]const u8{
                "secrets", "base64", "hashlib", "json", "pickle",
                "zlib", "gzip", "binascii", "struct", "math",
                "random", "re", "os", "sys", "io", "string",
            };

            var is_value_module = false;
            for (value_returning_modules) |mod| {
                if (std.mem.eql(u8, module_name, mod)) {
                    is_value_module = true;
                    break;
                }
            }

            // Exclude known void-returning functions
            const void_functions = [_][]const u8{
                "main", "exit", "seed",
            };

            var is_void_func = false;
            for (void_functions) |vf| {
                if (std.mem.eql(u8, func_name, vf)) {
                    is_void_func = true;
                    break;
                }
            }

            if (is_value_module and !is_void_func) {
                try self.emit("_ = ");
                added_discard_prefix = true;
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

    // Determine if we need a semicolon:
    // - If we added "_ = " prefix, we ALWAYS need a semicolon (it's an assignment)
    // - Struct initializers like "Type{}" need semicolons
    // - Statement blocks like "{ ... }" do NOT need semicolons
    // - Labeled blocks like "blk: { ... }" do NOT need semicolons
    var needs_semicolon = true;

    // If we added "_ = " prefix, it's an assignment that always needs semicolon
    if (!added_discard_prefix and generated.len > 0 and generated[generated.len - 1] == '}') {
        // Check for labeled blocks (e.g., "blk: {", "sub_0: {", "slice_1: {", "comp_2: {")
        // Pattern: identifier followed by colon and space then brace
        const is_labeled_block = blk: {
            // Check for common label patterns
            if (std.mem.indexOf(u8, generated, "blk: {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "sub_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "slice_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "comp_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "dict_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "gen_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "idx_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "str_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "arr_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
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
