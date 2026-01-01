/// For loop code generation (enumerate, zip)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const zig_keywords = @import("utils.zig_keywords");
const param_analyzer = @import("../../functions/param_analyzer.zig");
const for_basic = @import("for_basic.zig");
const container_traits = @import("../../../../../analysis/traits/container_traits.zig");
const expr_emitter = @import("../../../expr_emitter.zig");
const builder_mod = @import("codegen.builder");

// Helper for indented constant output
fn emitIndent(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeIndent();
    try b.emitRaw(val);
    const output = try b.getBodyDupe();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for indented formatted output
fn emitIndentFmt(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeIndent();
    try b.writeFmt(fmt, args);
    const output = try b.getBodyDupe();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for writing escaped identifier with indentation
fn emitIndentWithIdent(self: *NativeCodegen, prefix: []const u8, ident: []const u8, suffix: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeIndent();
    try b.emitRaw(prefix);
    try zig_keywords.writeEscapedIdent(b.body.writer(b.allocator), ident);
    try b.emitRaw(suffix);
    const output = try b.getBodyDupe();
    try self.output.appendSlice(self.allocator, output);
}

// Helper for writing escaped identifier with formatted suffix
fn emitIndentWithIdentFmt(self: *NativeCodegen, prefix: []const u8, ident: []const u8, comptime suffix_fmt: []const u8, suffix_args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeIndent();
    try b.emitRaw(prefix);
    try zig_keywords.writeEscapedIdent(b.body.writer(b.allocator), ident);
    try b.writeFmt(suffix_fmt, suffix_args);
    const output = try b.getBodyDupe();
    try self.output.appendSlice(self.allocator, output);
}

/// Generate enumerate loop
pub fn genEnumerateLoop(self: *NativeCodegen, target: ast.Node, args: []ast.Node, body: []ast.Node, orelse_body: ?[]ast.Node) CodegenError!void {
    // Handle single variable target: for item in enumerate(...) - item gets (idx, val) tuples
    // Valid Python: for x in enumerate(items): print(x)  # x is (0, first), (1, second), etc.
    if (target == .name) {
        // Generate tuple iteration where each iteration produces a (idx, val) struct
        const var_name = target.name.id;
        if (args.len == 0) {
            return error.UnsupportedSyntax;  // enumerate() requires at least 1 argument - caller uses VM fallback
        }
        try emitIndent(self, "{\n");
        self.indent();
        try emitIndent(self, "var __enum_idx: usize = 0;\n");
        try emitIndent(self, "for (");
        try self.genExpr(args[0]);
        try self.emit(") |__enum_val| {\n");
        self.indent();
        try emitIndentFmt(self, "const {s} = .{{ __enum_idx, __enum_val }};\n", .{var_name});
        for (body) |stmt| {
            try self.generateStmt(stmt);
        }
        try emitIndent(self, "__enum_idx += 1;\n");
        self.dedent();
        try emitIndent(self, "}\n");
        // Handle optional else clause
        if (orelse_body) |else_body| {
            for (else_body) |stmt| {
                try self.generateStmt(stmt);
            }
        }
        self.dedent();
        try emitIndent(self, "}\n");
        return;
    }

    // Validate target is a list or tuple (parser uses list/tuple node for tuple unpacking) with exactly 2 elements (idx, item)
    const target_elts = switch (target) {
        .list => |l| l.elts,
        .tuple => |t| t.elts,
        else => {
            // Unknown target type - caller uses VM fallback
            return error.UnsupportedSyntax;
        },
    };
    if (target_elts.len != 2) {
        // Not exactly 2 elements - Python allows but will unpack differently
        // Use VM fallback for drop-in CPython replacement
        return error.UnsupportedSyntax;
    }

    // Extract variable names - handle simple names and nested tuples
    const idx_var = if (target_elts[0] == .name) target_elts[0].name.id else "__enum_idx";
    // For nested unpacking like (a, b), generate a temp var and unpack later
    const item_is_tuple = target_elts[1] == .tuple or target_elts[1] == .list;
    const item_var = if (target_elts[1] == .name) target_elts[1].name.id else "__enum_item";

    // Extract iterable (first argument to enumerate)
    if (args.len == 0) {
        return error.UnsupportedSyntax; // enumerate() requires at least 1 argument
    }
    const iterable = args[0];

    // Extract start parameter (default 0)
    // enumerate(iterable, start=0) - start can be positional or keyword
    // Keyword args are handled by caller and converted to positional
    var start_value: i64 = 0;
    if (args.len >= 2) {
        if (args[1] == .constant and args[1].constant.value == .int) {
            start_value = args[1].constant.value.int;
        }
    }

    // Generate block scope
    try emitIndent(self, "{\n");
    self.indent();

    // Generate index counter: var __enum_idx_N: usize = start;
    // Use output buffer length as unique ID to avoid shadowing in nested loops
    const unique_id = self.output.items.len;
    if (start_value != 0) {
        try emitIndentFmt(self, "var __enum_idx_{d}: usize = {d};\n", .{ unique_id, start_value });
    } else {
        try emitIndentFmt(self, "var __enum_idx_{d}: usize = 0;\n", .{unique_id});
    }

    // Generate for loop over iterable
    try emitIndent(self, "for (");

    // Check if we need to add .items for ArrayList
    const iter_type = try self.type_inferrer.inferExpr(iterable);

    // If iterating over list literal, wrap in parens for .items access
    if (container_traits.isList(iter_type) and iterable == .list) {
        // Use emitParens auto-close helper for guaranteed bracket matching
        try self.emitParens(iterable);
        try self.emit(".items");
    } else {
        try self.genExpr(iterable);
        if (container_traits.isList(iter_type)) {
            try self.emit(".items");
        }
    }

    // Check if item variable is used in body - if item_is_tuple, we always need it for unpacking
    const item_var_used = item_is_tuple or param_analyzer.isNameUsedInBody(body, item_var);

    // Check if loop variable shadows an imported module or hoisted variable
    const shadows_import = self.imported_modules.contains(item_var);
    const shadows_hoisted = self.hoisted_vars.contains(item_var);
    const shadows_something = shadows_import or shadows_hoisted;
    var em = self.exprEmitter();
    const enum_unique_capture_id = em.peekLabelId();
    if (shadows_something and item_var_used) _ = em.reserveLabelId();

    if (!item_var_used) {
        try self.emit(") |_| {\n");
    } else if (shadows_something) {
        // Use unique capture name to avoid shadowing module import or hoisted variable
        try self.emitFmt(") |__loop_{s}_{d}__| {{\n", .{ item_var, enum_unique_capture_id });
    } else {
        const b = try self.getBuilder();
        try b.emitRaw(") |");
        try zig_keywords.writeEscapedIdent(b.body.writer(b.allocator), item_var);
        try b.emitRaw("| {\n");
        const output = try b.getBodyDupe();
        try self.output.appendSlice(self.allocator, output);
    }

    self.indent();

    // Push new scope for loop body
    try self.pushScope();

    // If we used a unique capture name due to shadowing, add var_renames for body generation
    if (shadows_something and item_var_used) {
        // Register the renamed variable so body uses __loop_X_N__ instead of X
        const renamed = try std.fmt.allocPrint(self.allocator, "__loop_{s}_{d}__", .{ item_var, enum_unique_capture_id });
        try self.var_renames.put(item_var, renamed);
    }

    // Emit suppression for loop capture variable to handle mismatch between
    // AST-based usage analysis and actual codegen (e.g., class field assignments
    // that get optimized away during class codegen)
    if (item_var_used) {
        if (shadows_something) {
            try emitIndentFmt(self, "_ = &__loop_{s}_{d}__;\n", .{ item_var, enum_unique_capture_id });
        } else {
            try emitIndentWithIdent(self, "_ = &", item_var, ";\n");
        }
        // Track loop capture variable for shadowing detection
        // When Python code does `name = f"f{j}"` inside the loop body,
        // we need to rename the new variable to avoid shadowing the immutable Zig capture
        try self.loop_capture_vars.put(item_var, {});

        // Check if the loop variable is reassigned anywhere in the body (including nested blocks)
        // If so, we need to pre-declare a mutable variable at this scope level to avoid
        // the issue where the renamed variable is declared inside a nested block but used outside
        if (for_basic.varIsReassignedInBody(body, item_var)) {
            const renamed = self.name_gen.loopVar(item_var) catch item_var;
            // Pre-declare the renamed variable at for-loop scope (before nested blocks)
            try emitIndentFmt(self, "var {s}: []const u8 = \"\";\n", .{renamed});
            // Mark as declared so assign.zig won't try to declare it again
            try self.declareVar(renamed);
            // Add to var_renames so all references use the renamed name
            try self.var_renames.put(item_var, renamed);
        }
    }

    // Generate: const idx = __enum_idx_N;
    try emitIndentWithIdentFmt(self, "const ", idx_var, " = __enum_idx_{d};\n", .{unique_id});

    // Always emit discard to handle cases where variable is used in eval strings
    // (e.g., runtime.eval("sh[cnum]") where cnum is the enum index)
    try emitIndentWithIdent(self, "_ = &", idx_var, ";\n");

    // Generate: __enum_idx_N += 1;
    try emitIndentFmt(self, "__enum_idx_{d} += 1;\n", .{unique_id});

    // If item was a nested tuple, unpack it
    if (item_is_tuple) {
        const nested_elts = if (target_elts[1] == .tuple) target_elts[1].tuple.elts else target_elts[1].list.elts;
        for (nested_elts, 0..) |elt, i| {
            if (elt == .name) {
                const b = try self.getBuilder();
                try b.writeIndent();
                try b.emitRaw("const ");
                try zig_keywords.writeEscapedIdent(b.body.writer(b.allocator), elt.name.id);
                try b.emitRaw(" = ");
                try zig_keywords.writeEscapedIdent(b.body.writer(b.allocator), item_var);
                try b.writeFmt(".@\"{d}\";\n", .{i});
                const output = try b.getBodyDupe();
                try self.output.appendSlice(self.allocator, output);
                // Only suppress unused warning if variable is NOT used in body
                if (!param_analyzer.isNameUsedInBody(body, elt.name.id)) {
                    try emitIndentWithIdent(self, "_ = ", elt.name.id, ";\n");
                }
            }
        }
    }

    // Generate body statements
    for (body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting loop
    self.popScope();

    // Clean up var_renames for shadowed imports and loop capture reassignment
    if (item_var_used) {
        // This removes var_renames entries added for both:
        // 1. Shadowed imports: item_var -> __loop_X_N__
        // 2. Reassigned loop captures: item_var -> __mN_lv_name
        _ = self.var_renames.swapRemove(item_var);
        _ = self.loop_capture_vars.swapRemove(item_var);
    }

    self.dedent();
    try emitIndent(self, "}\n");

    // Handle optional else clause (runs if loop completes without break)
    if (orelse_body) |else_body| {
        for (else_body) |stmt| {
            try self.generateStmt(stmt);
        }
    }

    // Close block scope
    self.dedent();
    try emitIndent(self, "}\n");
}

/// Generate zip() loop
/// Transforms: for x, y in zip(list1, list2) into:
/// {
///     const __zip_iter_0 = list1.items;
///     const __zip_iter_1 = list2.items;
///     var __zip_idx: usize = 0;
///     const __zip_len = @min(__zip_iter_0.len, __zip_iter_1.len);
///     while (__zip_idx < __zip_len) : (__zip_idx += 1) {
///         const x = __zip_iter_0[__zip_idx];
///         const y = __zip_iter_1[__zip_idx];
///         // body
///     }
/// }
pub fn genZipLoop(self: *NativeCodegen, target: ast.Node, args: []ast.Node, body: []ast.Node, orelse_body: ?[]ast.Node) CodegenError!void {
    // Validate target is a list or tuple (parser uses list/tuple node for tuple unpacking in for-loops)
    const target_elts = switch (target) {
        .list => |l| l.elts,
        .tuple => |t| t.elts,
        else => return error.UnsupportedSyntax, // zip() requires tuple unpacking: for x, y in zip(...)
    };

    const num_vars = target_elts.len;

    // Verify number of variables matches number of iterables
    if (num_vars != args.len) {
        return error.UnsupportedSyntax; // zip() variable count must match number of iterables
    }

    // zip() requires at least 2 iterables
    if (args.len < 2) {
        return error.UnsupportedSyntax; // zip() requires at least 2 iterables
    }

    // Open block for scoping
    try emitIndent(self, "{\n");
    self.indent();

    // Check type of each iterable to determine if we need .items
    var iter_is_list = try self.allocator.alloc(bool, args.len);
    defer self.allocator.free(iter_is_list);

    for (args, 0..) |iterable, i| {
        const iter_type = try self.type_inferrer.inferExpr(iterable);
        iter_is_list[i] = container_traits.isList(iter_type);
    }

    // Store each iterable in a temporary variable: const __zip_iter_N = ...
    for (args, 0..) |iterable, i| {
        try emitIndentFmt(self, "const __zip_iter_{d} = ", .{i});
        try self.genExpr(iterable);
        try self.emit(";\n");
    }

    // Generate: var __zip_idx: usize = 0;
    try emitIndent(self, "var __zip_idx: usize = 0;\n");

    // Generate: const __zip_len = @min(iter0.len, @min(iter1.len, ...));
    {
        const b = try self.getBuilder();
        try b.writeIndent();
        try b.emitRaw("const __zip_len = ");

        // Build nested @min calls - use .items.len for lists, .len for arrays
        if (args.len == 2) {
            try b.emitRaw("@min(__zip_iter_0");
            if (iter_is_list[0]) try b.emitRaw(".items");
            try b.emitRaw(".len, __zip_iter_1");
            if (iter_is_list[1]) try b.emitRaw(".items");
            try b.emitRaw(".len)");
        } else {
            // For 3+ iterables: @min(iter0.len, @min(iter1.len, @min(iter2.len, ...)))
            try b.emitRaw("@min(__zip_iter_0");
            if (iter_is_list[0]) try b.emitRaw(".items");
            try b.emitRaw(".len, ");
            for (1..args.len - 1) |_| {
                try b.emitRaw("@min(");
            }
            for (1..args.len) |i| {
                try b.writeFmt("__zip_iter_{d}", .{i});
                if (iter_is_list[i]) try b.emitRaw(".items");
                try b.emitRaw(".len");
                if (i < args.len - 1) {
                    try b.emitRaw(", ");
                }
            }
            for (1..args.len - 1) |_| {
                try b.emitRaw(")");
            }
            try b.emitRaw(")");
        }
        try b.emitRaw(";\n");
        const output = try b.getBodyDupe();
        try self.output.appendSlice(self.allocator, output);
    }

    // Generate: while (__zip_idx < __zip_len) : (__zip_idx += 1) {
    try emitIndent(self, "while (__zip_idx < __zip_len) : (__zip_idx += 1) {\n");
    self.indent();

    // Push new scope for loop body
    try self.pushScope();

    // Generate: const var1 = __zip_iter_0[__zip_idx]; const var2 = __zip_iter_1[__zip_idx]; ...
    // Use .items for lists, direct indexing for arrays
    // Also track which variables are unused to suppress warnings
    var unused_vars = std.ArrayList([]const u8){};
    defer unused_vars.deinit(self.allocator);

    for (target_elts, 0..) |elt, i| {
        const var_name = if (elt == .name) elt.name.id else "_";
        const b = try self.getBuilder();
        try b.writeIndent();
        try b.emitRaw("const ");
        try zig_keywords.writeEscapedIdent(b.body.writer(b.allocator), var_name);
        try b.writeFmt(" = __zip_iter_{d}", .{i});
        if (iter_is_list[i]) try b.emitRaw(".items");
        try b.emitRaw("[__zip_idx];\n");
        const output = try b.getBodyDupe();
        try self.output.appendSlice(self.allocator, output);

        // Add variable to symbol table so nested scopes can detect shadowing
        if (elt == .name and !std.mem.eql(u8, var_name, "_")) {
            try self.declareVar(var_name);
        }

        // Check if variable is used in body - if not, track for warning suppression
        if (elt == .name and !std.mem.eql(u8, var_name, "_")) {
            const is_used = for_basic.varUsedInBody(body, var_name);
            if (!is_used) {
                try unused_vars.append(self.allocator, var_name);
            }
        }
    }

    // Emit _ = &var; for any unused variables to suppress Zig warnings
    for (unused_vars.items) |var_name| {
        try emitIndentWithIdent(self, "_ = &", var_name, ";\n");
    }

    // Generate body statements
    for (body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting loop
    self.popScope();

    // Close while loop
    self.dedent();
    try emitIndent(self, "}\n");

    // Handle optional else clause (runs if loop completes without break)
    if (orelse_body) |else_body| {
        for (else_body) |stmt| {
            try self.generateStmt(stmt);
        }
    }

    // Close block scope
    self.dedent();
    try emitIndent(self, "}\n");
}
