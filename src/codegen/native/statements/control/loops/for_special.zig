/// For loop code generation (enumerate, zip)
const std = @import("std");
const ast = @import("../../../../../ast.zig");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;

/// Generate enumerate loop
pub fn genEnumerateLoop(self: *NativeCodegen, target: ast.Node, args: []ast.Node, body: []ast.Node) CodegenError!void {
    // Validate target is a list (parser uses list node for tuple unpacking) with exactly 2 elements (idx, item)
    if (target != .list) {
        @panic("enumerate() requires tuple unpacking: for i, item in enumerate(...)");
    }
    const target_elts = target.list.elts;
    if (target_elts.len != 2) {
        @panic("enumerate() requires exactly 2 variables: for i, item in enumerate(...)");
    }

    // Extract variable names
    const idx_var = target_elts[0].name.id;
    const item_var = target_elts[1].name.id;

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
    try self.output.appendSlice(self.allocator, "{\n");
    self.indent();

    // Generate index counter: var __enum_idx_N: usize = start;
    // Use output buffer length as unique ID to avoid shadowing in nested loops
    const unique_id = self.output.items.len;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var __enum_idx_{d}: usize = ", .{unique_id});
    if (start_value != 0) {
        const start_str = try std.fmt.allocPrint(self.allocator, "{d}", .{start_value});
        try self.output.appendSlice(self.allocator, start_str);
    } else {
        try self.output.appendSlice(self.allocator, "0");
    }
    try self.output.appendSlice(self.allocator, ";\n");

    // Generate for loop over iterable
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "for (");

    // Check if we need to add .items for ArrayList
    const iter_type = try self.type_inferrer.inferExpr(iterable);

    // If iterating over list literal, wrap in parens for .items access
    if (iter_type == .list and iterable == .list) {
        try self.output.appendSlice(self.allocator, "(");
        try self.genExpr(iterable);
        try self.output.appendSlice(self.allocator, ").items");
    } else {
        try self.genExpr(iterable);
        if (iter_type == .list) {
            try self.output.appendSlice(self.allocator, ".items");
        }
    }

    try self.output.appendSlice(self.allocator, ") |");
    try self.output.appendSlice(self.allocator, item_var);
    try self.output.appendSlice(self.allocator, "| {\n");

    self.indent();

    // Push new scope for loop body
    try self.pushScope();

    // Generate: const idx = __enum_idx_N;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = __enum_idx_{d};\n", .{ idx_var, unique_id });

    // Generate: __enum_idx_N += 1;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("__enum_idx_{d} += 1;\n", .{unique_id});

    // Generate body statements
    for (body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting loop
    self.popScope();

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");

    // Close block scope
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
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
    // Validate target is a list (parser uses list node for tuple unpacking in for-loops)
    if (target != .list) {
        @panic("zip() requires tuple unpacking: for x, y in zip(...)");
    }

    const num_vars = target.list.elts.len;

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
    try self.output.appendSlice(self.allocator, "{\n");
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
        try self.output.writer(self.allocator).print("const __zip_iter_{d} = ", .{i});
        try self.genExpr(iterable);
        try self.output.appendSlice(self.allocator, ";\n");
    }

    // Generate: var __zip_idx: usize = 0;
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var __zip_idx: usize = 0;\n");

    // Generate: const __zip_len = @min(iter0.len, @min(iter1.len, ...));
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "const __zip_len = ");

    // Build nested @min calls - use .items.len for lists, .len for arrays
    if (args.len == 2) {
        try self.output.appendSlice(self.allocator, "@min(__zip_iter_0");
        if (iter_is_list[0]) try self.output.appendSlice(self.allocator, ".items");
        try self.output.appendSlice(self.allocator, ".len, __zip_iter_1");
        if (iter_is_list[1]) try self.output.appendSlice(self.allocator, ".items");
        try self.output.appendSlice(self.allocator, ".len)");
    } else {
        // For 3+ iterables: @min(iter0.len, @min(iter1.len, @min(iter2.len, ...)))
        try self.output.appendSlice(self.allocator, "@min(__zip_iter_0");
        if (iter_is_list[0]) try self.output.appendSlice(self.allocator, ".items");
        try self.output.appendSlice(self.allocator, ".len, ");
        for (1..args.len - 1) |_| {
            try self.output.appendSlice(self.allocator, "@min(");
        }
        for (1..args.len) |i| {
            try self.output.writer(self.allocator).print("__zip_iter_{d}", .{i});
            if (iter_is_list[i]) try self.output.appendSlice(self.allocator, ".items");
            try self.output.appendSlice(self.allocator, ".len");
            if (i < args.len - 1) {
                try self.output.appendSlice(self.allocator, ", ");
            }
        }
        for (1..args.len - 1) |_| {
            try self.output.appendSlice(self.allocator, ")");
        }
        try self.output.appendSlice(self.allocator, ")");
    }
    try self.output.appendSlice(self.allocator, ";\n");

    // Generate: while (__zip_idx < __zip_len) : (__zip_idx += 1) {
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "while (__zip_idx < __zip_len) : (__zip_idx += 1) {\n");
    self.indent();

    // Push new scope for loop body
    try self.pushScope();

    // Generate: const var1 = __zip_iter_0[__zip_idx]; const var2 = __zip_iter_1[__zip_idx]; ...
    // Use .items for lists, direct indexing for arrays
    for (target.list.elts, 0..) |elt, i| {
        const var_name = elt.name.id;
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "const ");
        try self.output.appendSlice(self.allocator, var_name);
        try self.output.writer(self.allocator).print(" = __zip_iter_{d}", .{i});
        if (iter_is_list[i]) try self.output.appendSlice(self.allocator, ".items");
        try self.output.appendSlice(self.allocator, "[__zip_idx];\n");
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
    try self.output.appendSlice(self.allocator, "}\n");

    // Close block scope
    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
}
