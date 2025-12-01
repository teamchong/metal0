/// Zero-capture closure generation - optimized closures with no captured variables
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const zig_keywords = @import("zig_keywords");
const hashmap_helper = @import("hashmap_helper");
const var_tracking = @import("var_tracking.zig");

/// Generate zero-capture closure using comptime ZeroClosure
pub fn genZeroCaptureClosure(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
) CodegenError!void {
    // Save counter for unique naming
    const saved_counter = self.lambda_counter;

    // Generate the inner function
    const impl_name = try std.fmt.allocPrint(
        self.allocator,
        "__ZeroImpl_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(impl_name);

    // Use unique function name inside the struct to avoid shadowing
    const inner_fn_name = try std.fmt.allocPrint(
        self.allocator,
        "__fn_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(inner_fn_name);
    self.lambda_counter += 1;

    // Build param name mappings for unique names to avoid shadowing outer scope
    var param_renames = std.StringHashMap([]const u8).init(self.allocator);
    defer param_renames.deinit();

    try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{impl_name});
    self.indent();

    try self.emitIndent();
    try self.output.writer(self.allocator).print("fn {s}(", .{inner_fn_name});
    for (func.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        // Check if param is used in body - if not, use _ to discard (Zig 0.15 requirement)
        const is_used = var_tracking.isParamUsedInStmts(arg.name, func.body);
        if (is_used) {
            // Create unique param name to avoid shadowing outer scope
            const unique_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__p_{s}_{d}",
                .{ arg.name, saved_counter },
            );
            try param_renames.put(arg.name, unique_param_name);
            // Use anytype to allow flexible parameter types (supports string, int, etc.)
            try self.output.writer(self.allocator).print("{s}: anytype", .{unique_param_name});
        } else {
            try self.output.writer(self.allocator).print("_: anytype", .{});
        }
    }
    // Look up the function's inferred return type from type inference
    // Use it for proper type safety, falling back to anytype workaround via @TypeOf
    const return_type = self.type_inferrer.func_return_types.get(func.name);
    if (return_type) |rt| {
        // We have a known return type from inference - use it
        try self.emit(") !");
        var type_buf = std.ArrayList(u8){};
        defer type_buf.deinit(self.allocator);
        const native_types = @import("../../../../../analysis/native_types.zig");
        try native_types.NativeType.toZigType(rt, self.allocator, &type_buf);
        try self.emit(type_buf.items);
        try self.emit(" {\n");
    } else {
        // No inferred type - use anyerror!anytype pattern wouldn't work in Zig
        // Fall back to i64 but this may fail for non-integer returns
        try self.emit(") !i64 {\n");
    }

    self.indent();
    try self.pushScope();

    // Save and populate func_local_uses for this nested function
    const saved_func_local_uses = self.func_local_uses;
    self.func_local_uses = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.func_local_uses.deinit();
        self.func_local_uses = saved_func_local_uses;
    }

    // Populate func_local_uses with variables used in this function body
    try var_tracking.collectUsedNames(func.body, &self.func_local_uses);

    // Track which parameters need mutable copies due to reassignment
    var reassigned_param_vars = std.ArrayList([]const u8){};
    defer reassigned_param_vars.deinit(self.allocator);

    for (func.args) |arg| {
        try self.declareVar(arg.name);
        const is_reassigned = var_tracking.isParamReassignedInStmts(arg.name, func.body);

        // Add rename mapping for parameter access in body
        if (param_renames.get(arg.name)) |renamed| {
            if (is_reassigned) {
                // Create mutable var copy name
                const var_name = try std.fmt.allocPrint(self.allocator, "__v_{s}_{d}", .{ arg.name, saved_counter });
                try reassigned_param_vars.append(self.allocator, var_name);
                try self.var_renames.put(arg.name, var_name);
            } else {
                try self.var_renames.put(arg.name, renamed);
            }
        }
    }

    // Emit var copies for reassigned parameters
    for (func.args) |arg| {
        if (var_tracking.isParamReassignedInStmts(arg.name, func.body) and param_renames.get(arg.name) != null) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("var __v_{s}_{d} = __p_{s}_{d};\n", .{ arg.name, saved_counter, arg.name, saved_counter });
        }
    }

    // Mark as closure BEFORE generating body so recursive calls use .call() syntax
    // We'll add it again at the end (duplicate put is OK for the hashmap)
    const func_name_copy_early = try self.allocator.dupe(u8, func.name);
    try self.closure_vars.put(func_name_copy_early, {});

    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Free the reassigned param var names
    for (reassigned_param_vars.items) |var_name| {
        self.allocator.free(var_name);
    }

    // If function has non-void return type but no explicit return, add default return
    const has_explicit_return = blk: {
        for (func.body) |stmt| {
            if (stmt == .return_stmt) break :blk true;
        }
        break :blk false;
    };
    if (!has_explicit_return and return_type != null) {
        // Add default return based on return type
        try self.emitIndent();
        if (return_type) |rt| {
            if (rt == .int or rt == .usize) {
                try self.emit("return 0;\n");
            } else if (@as(std.meta.Tag(@TypeOf(rt)), rt) == .class_instance) {
                try self.emit("return undefined;\n");
            } else {
                try self.emit("return undefined;\n");
            }
        } else {
            try self.emit("return 0;\n");
        }
    }

    // Remove param renames after body generation
    for (func.args) |arg| {
        _ = self.var_renames.swapRemove(arg.name);
    }

    // Free renamed param names
    var rename_iter = param_renames.valueIterator();
    while (rename_iter.next()) |renamed| {
        self.allocator.free(renamed.*);
    }

    self.popScope();
    self.dedent();

    try self.emitIndent();
    try self.emit("}\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // Create wrapper struct for the closure
    // Use the original function name so that references resolve correctly
    // Get return type string for the wrapper
    const native_types = @import("../../../../../analysis/native_types.zig");
    var return_type_str = std.ArrayList(u8){};
    defer return_type_str.deinit(self.allocator);
    if (return_type) |rt| {
        try native_types.NativeType.toZigType(rt, self.allocator, &return_type_str);
    } else {
        try return_type_str.appendSlice(self.allocator, "i64");
    }

    try self.emitIndent();
    try self.emit("const ");
    // Check if function name shadows an imported module name (e.g., "test" shadows "import test")
    // If so, use a unique name to avoid redefinition error
    const shadows_import = self.imported_modules.contains(func.name);
    const wrapper_name = if (shadows_import)
        try std.fmt.allocPrint(self.allocator, "__local_{s}_{d}", .{ func.name, saved_counter })
    else
        func.name;
    // Don't defer free - the name is stored in var_renames for later reference
    // Register rename so references use the correct name
    if (shadows_import) {
        try self.var_renames.put(func.name, wrapper_name);
    }
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), wrapper_name);
    if (func.args.len == 1) {
        // Single arg - create simple wrapper struct
        const unique_param = try std.fmt.allocPrint(
            self.allocator,
            "__p_{s}_{d}",
            .{ func.args[0].name, saved_counter },
        );
        defer self.allocator.free(unique_param);

        try self.emit(" = struct {\n");
        self.indent();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("pub fn call(_: @This(), {s}: anytype) !{s} {{\n", .{ unique_param, return_type_str.items });
        self.indent();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("return try {s}.{s}({s});\n", .{ impl_name, inner_fn_name, unique_param });
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}{};\n");
    } else {
        // Multiple args - create wrapper struct with unique parameter names
        // Use a different counter for wrapper params (saved_counter is already used above)
        const wrapper_counter = self.lambda_counter;
        self.lambda_counter += 1;

        // Build param name mappings for unique names
        var param_names = std.ArrayList([]const u8){};
        defer {
            for (param_names.items) |name| {
                self.allocator.free(name);
            }
            param_names.deinit(self.allocator);
        }

        for (func.args) |arg| {
            const unique_name = try std.fmt.allocPrint(
                self.allocator,
                "__p_{s}_{d}",
                .{ arg.name, wrapper_counter },
            );
            try param_names.append(self.allocator, unique_name);
        }

        try self.emit(" = struct {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("pub fn call(_: @This()");
        for (param_names.items) |unique_name| {
            // Use anytype for flexible parameter types
            try self.output.writer(self.allocator).print(", {s}: anytype", .{unique_name});
        }
        // Use inferred return type
        try self.output.writer(self.allocator).print(") !{s} {{\n", .{return_type_str.items});
        self.indent();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("return try {s}.{s}(", .{ impl_name, inner_fn_name });
        for (param_names.items, 0..) |unique_name, i| {
            if (i > 0) try self.emit(", ");
            try self.emit(unique_name);
        }
        try self.emit(");\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}{};\n");
    }

    // Mark as closure so calls use .call() syntax
    const func_name_copy = try self.allocator.dupe(u8, func.name);
    try self.closure_vars.put(func_name_copy, {});
}
