/// For loop code generation (enumerate, zip)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const zig_keywords = @import("zig_keywords");
const param_analyzer = @import("../../functions/param_analyzer.zig");

/// Generate enumerate loop
pub fn genEnumerateLoop(self: *NativeCodegen, target: ast.Node, args: []ast.Node, body: []ast.Node) CodegenError!void {
    // Handle single variable target: for item in enumerate(...) - item gets (idx, val) tuples
    // This is unusual but valid Python - emit a TODO comment and use simple iteration
    if (target == .name) {
        try self.emitIndent();
        try self.emit("// TODO: enumerate() with single variable target not fully supported\n");
        // Fall back to simple iteration - emit a basic for loop
        try self.emitIndent();
        try self.emit("{\n");
        self.indent();
        try self.emitIndent();
        try self.emit("var __enum_idx: usize = 0;\n");
        try self.emitIndent();
        try self.emit("_ = __enum_idx;\n"); // Suppress unused warning
        for (body) |stmt| {
            try self.generateStmt(stmt);
        }
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        return;
    }

    // Validate target is a list or tuple (parser uses list/tuple node for tuple unpacking) with exactly 2 elements (idx, item)
    const target_elts = switch (target) {
        .list => |l| l.elts,
        .tuple => |t| t.elts,
        else => {
            // Unknown target type - emit placeholder
            try self.emitIndent();
            try self.emit("// TODO: Unsupported enumerate target type\n");
            return;
        },
    };
    if (target_elts.len != 2) {
        // Not exactly 2 elements - emit placeholder
        try self.emitIndent();
        try self.emitFmt("// TODO: enumerate() with {d} variables not supported (need exactly 2)\n", .{target_elts.len});
        return;
    }

    // Extract variable names - handle simple names and nested tuples
    const idx_var = if (target_elts[0] == .name) target_elts[0].name.id else "__enum_idx";
    // For nested unpacking like (a, b), generate a temp var and unpack later
    const item_is_tuple = target_elts[1] == .tuple or target_elts[1] == .list;
    const item_var = if (target_elts[1] == .name) target_elts[1].name.id else "__enum_item";

    // Extract iterable (first argument to enumerate)
    if (args.len == 0) {
        @panic("enumerate() requires at least 1 argument");
    }
    const iterable = args[0];

    // Extract start parameter (default 0)
    var start_value: i64 = 0;
    if (args.len >= 2) {
        // Check if it's a keyword argument "start=N"
        // For now, assume positional: enumerate(items, start)
        // TODO: Handle keyword args properly
        if (args[1] == .constant and args[1].constant.value == .int) {
            start_value = args[1].constant.value.int;
        }
    }

    // Generate block scope
    try self.emitIndent();
    try self.emit("{\n");
    self.indent();

    // Generate index counter: var __enum_idx_N: usize = start;
    // Use output buffer length as unique ID to avoid shadowing in nested loops
    const unique_id = self.output.items.len;
    try self.emitIndent();
    try self.emitFmt("var __enum_idx_{d}: usize = ", .{unique_id});
    if (start_value != 0) {
        try self.emitFmt("{d}", .{start_value});
    } else {
        try self.emit("0");
    }
    try self.emit(";\n");

    // Generate for loop over iterable
    try self.emitIndent();
    try self.emit("for (");

    // Check if we need to add .items for ArrayList
    const iter_type = try self.type_inferrer.inferExpr(iterable);

    // If iterating over list literal, wrap in parens for .items access
    if (iter_type == .list and iterable == .list) {
        try self.emit("(");
        try self.genExpr(iterable);
        try self.emit(").items");
    } else {
        try self.genExpr(iterable);
        if (iter_type == .list) {
            try self.emit(".items");
        }
    }

    // Check if item variable is used in body - if item_is_tuple, we always need it for unpacking
    const item_var_used = item_is_tuple or param_analyzer.isNameUsedInBody(body, item_var);

    try self.emit(") |");
    if (!item_var_used) {
        try self.emit("_");
    } else {
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), item_var);
    }
    try self.emit("| {\n");

    self.indent();

    // Push new scope for loop body
    try self.pushScope();

    // Generate: const idx = __enum_idx_N;
    try self.emitIndent();
    try self.emit("const ");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), idx_var);
    try self.output.writer(self.allocator).print(" = __enum_idx_{d};\n", .{unique_id});
    // Suppress unused warning only if idx_var is NOT used in body
    if (!param_analyzer.isNameUsedInBody(body, idx_var)) {
        try self.emitIndent();
        try self.emit("_ = ");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), idx_var);
        try self.emit(";\n");
    }

    // Generate: __enum_idx_N += 1;
    try self.emitIndent();
    try self.emitFmt("__enum_idx_{d} += 1;\n", .{unique_id});

    // If item was a nested tuple, unpack it
    if (item_is_tuple) {
        const nested_elts = if (target_elts[1] == .tuple) target_elts[1].tuple.elts else target_elts[1].list.elts;
        for (nested_elts, 0..) |elt, i| {
            if (elt == .name) {
                try self.emitIndent();
                try self.emit("const ");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), elt.name.id);
                try self.emit(" = ");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), item_var);
                try self.output.writer(self.allocator).print(".@\"{d}\";\n", .{i});
                // Only suppress unused warning if variable is NOT used in body
                if (!param_analyzer.isNameUsedInBody(body, elt.name.id)) {
                    try self.emitIndent();
                    try self.emit("_ = ");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), elt.name.id);
                    try self.emit(";\n");
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

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // Close block scope
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
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
pub fn genZipLoop(self: *NativeCodegen, target: ast.Node, args: []ast.Node, body: []ast.Node) CodegenError!void {
    // Validate target is a list or tuple (parser uses list/tuple node for tuple unpacking in for-loops)
    const target_elts = switch (target) {
        .list => |l| l.elts,
        .tuple => |t| t.elts,
        else => @panic("zip() requires tuple unpacking: for x, y in zip(...)"),
    };

    const num_vars = target_elts.len;

    // Verify number of variables matches number of iterables
    if (num_vars != args.len) {
        @panic("zip() variable count must match number of iterables");
    }

    // zip() requires at least 2 iterables
    if (args.len < 2) {
        @panic("zip() requires at least 2 iterables");
    }

    // Open block for scoping
    try self.emitIndent();
    try self.emit("{\n");
    self.indent();

    // Check type of each iterable to determine if we need .items
    var iter_is_list = try self.allocator.alloc(bool, args.len);
    defer self.allocator.free(iter_is_list);

    for (args, 0..) |iterable, i| {
        const iter_type = try self.type_inferrer.inferExpr(iterable);
        iter_is_list[i] = (iter_type == .list);
    }

    // Store each iterable in a temporary variable: const __zip_iter_N = ...
    for (args, 0..) |iterable, i| {
        try self.emitIndent();
        try self.emitFmt("const __zip_iter_{d} = ", .{i});
        try self.genExpr(iterable);
        try self.emit(";\n");
    }

    // Generate: var __zip_idx: usize = 0;
    try self.emitIndent();
    try self.emit("var __zip_idx: usize = 0;\n");

    // Generate: const __zip_len = @min(iter0.len, @min(iter1.len, ...));
    try self.emitIndent();
    try self.emit("const __zip_len = ");

    // Build nested @min calls - use .items.len for lists, .len for arrays
    if (args.len == 2) {
        try self.emit("@min(__zip_iter_0");
        if (iter_is_list[0]) try self.emit(".items");
        try self.emit(".len, __zip_iter_1");
        if (iter_is_list[1]) try self.emit(".items");
        try self.emit(".len)");
    } else {
        // For 3+ iterables: @min(iter0.len, @min(iter1.len, @min(iter2.len, ...)))
        try self.emit("@min(__zip_iter_0");
        if (iter_is_list[0]) try self.emit(".items");
        try self.emit(".len, ");
        for (1..args.len - 1) |_| {
            try self.emit("@min(");
        }
        for (1..args.len) |i| {
            try self.emitFmt("__zip_iter_{d}", .{i});
            if (iter_is_list[i]) try self.emit(".items");
            try self.emit(".len");
            if (i < args.len - 1) {
                try self.emit(", ");
            }
        }
        for (1..args.len - 1) |_| {
            try self.emit(")");
        }
        try self.emit(")");
    }
    try self.emit(";\n");

    // Generate: while (__zip_idx < __zip_len) : (__zip_idx += 1) {
    try self.emitIndent();
    try self.emit("while (__zip_idx < __zip_len) : (__zip_idx += 1) {\n");
    self.indent();

    // Push new scope for loop body
    try self.pushScope();

    // Generate: const var1 = __zip_iter_0[__zip_idx]; const var2 = __zip_iter_1[__zip_idx]; ...
    // Use .items for lists, direct indexing for arrays
    for (target_elts, 0..) |elt, i| {
        const var_name = if (elt == .name) elt.name.id else "_";
        try self.emitIndent();
        try self.emit("const ");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
        try self.output.writer(self.allocator).print(" = __zip_iter_{d}", .{i});
        if (iter_is_list[i]) try self.emit(".items");
        try self.emit("[__zip_idx];\n");
    }

    // Generate body statements
    for (body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting loop
    self.popScope();

    // Close while loop
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");

    // Close block scope
    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}
