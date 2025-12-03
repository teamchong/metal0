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
    var param_renames = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
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
    // Handle vararg (*args) parameter
    if (func.vararg) |vararg_name| {
        if (func.args.len > 0) try self.emit(", ");
        const is_vararg_used = var_tracking.isParamUsedInStmts(vararg_name, func.body);
        if (is_vararg_used) {
            const unique_vararg_name = try std.fmt.allocPrint(
                self.allocator,
                "__p_{s}_{d}",
                .{ vararg_name, saved_counter },
            );
            try param_renames.put(vararg_name, unique_vararg_name);
            try self.output.writer(self.allocator).print("{s}: anytype", .{unique_vararg_name});
        } else {
            try self.emit("_: anytype");
        }
    }
    // Handle kwarg (**kwargs) parameter
    if (func.kwarg) |kwarg_name| {
        if (func.args.len > 0 or func.vararg != null) try self.emit(", ");
        const is_kwarg_used = var_tracking.isParamUsedInStmts(kwarg_name, func.body);
        if (is_kwarg_used) {
            const unique_kwarg_name = try std.fmt.allocPrint(
                self.allocator,
                "__p_{s}_{d}",
                .{ kwarg_name, saved_counter },
            );
            try param_renames.put(kwarg_name, unique_kwarg_name);
            try self.output.writer(self.allocator).print("{s}: anytype", .{unique_kwarg_name});
        } else {
            try self.emit("_: anytype");
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

    // Mark that we're inside a nested function body - this affects isDeclared()
    const saved_inside_nested = self.inside_nested_function;
    self.inside_nested_function = true;
    defer self.inside_nested_function = saved_inside_nested;

    // Save and populate func_local_uses for this nested function
    const saved_func_local_uses = self.func_local_uses;
    self.func_local_uses = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.func_local_uses.deinit();
        self.func_local_uses = saved_func_local_uses;
    }

    // Save and clear hoisted_vars - nested function has its own hoisting context
    // Outer function's hoisted vars should NOT affect nested function scope
    const saved_hoisted_vars = self.hoisted_vars;
    self.hoisted_vars = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.hoisted_vars.deinit();
        self.hoisted_vars = saved_hoisted_vars;
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

    // Handle vararg scope declaration and rename mapping
    if (func.vararg) |vararg_name| {
        try self.declareVar(vararg_name);
        if (param_renames.get(vararg_name)) |renamed| {
            const is_reassigned = var_tracking.isParamReassignedInStmts(vararg_name, func.body);
            if (is_reassigned) {
                const var_name = try std.fmt.allocPrint(self.allocator, "__v_{s}_{d}", .{ vararg_name, saved_counter });
                try reassigned_param_vars.append(self.allocator, var_name);
                try self.var_renames.put(vararg_name, var_name);
            } else {
                try self.var_renames.put(vararg_name, renamed);
            }
        }
    }

    // Handle kwarg scope declaration and rename mapping
    if (func.kwarg) |kwarg_name| {
        try self.declareVar(kwarg_name);
        if (param_renames.get(kwarg_name)) |renamed| {
            const is_reassigned = var_tracking.isParamReassignedInStmts(kwarg_name, func.body);
            if (is_reassigned) {
                const var_name = try std.fmt.allocPrint(self.allocator, "__v_{s}_{d}", .{ kwarg_name, saved_counter });
                try reassigned_param_vars.append(self.allocator, var_name);
                try self.var_renames.put(kwarg_name, var_name);
            } else {
                try self.var_renames.put(kwarg_name, renamed);
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

    // Emit var copy for reassigned vararg
    if (func.vararg) |vararg_name| {
        if (var_tracking.isParamReassignedInStmts(vararg_name, func.body) and param_renames.get(vararg_name) != null) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("var __v_{s}_{d} = __p_{s}_{d};\n", .{ vararg_name, saved_counter, vararg_name, saved_counter });
        }
    }

    // Emit var copy for reassigned kwarg
    if (func.kwarg) |kwarg_name| {
        if (var_tracking.isParamReassignedInStmts(kwarg_name, func.body) and param_renames.get(kwarg_name) != null) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("var __v_{s}_{d} = __p_{s}_{d};\n", .{ kwarg_name, saved_counter, kwarg_name, saved_counter });
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

    // Remove vararg rename after body generation
    if (func.vararg) |vararg_name| {
        _ = self.var_renames.swapRemove(vararg_name);
    }

    // Free renamed param names
    for (param_renames.values()) |renamed| {
        self.allocator.free(renamed);
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
    // Always use a unique wrapper name to avoid conflicts with:
    // 1. Imported module names (e.g., "test" shadows "import test")
    // 2. Nested class method names (e.g., closure "foo" vs class method "foo")
    // Using unique names prevents Zig's "shadows local constant" errors
    const wrapper_name = try std.fmt.allocPrint(self.allocator, "__closure_{s}_{d}", .{ func.name, saved_counter });
    // Don't defer free - the name is stored in var_renames for later reference
    // Register rename so references use the correct name
    try self.var_renames.put(func.name, wrapper_name);
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), wrapper_name);

    // Calculate total param count (including vararg)
    const has_vararg = func.vararg != null;
    const total_params = func.args.len + @intFromBool(has_vararg);

    if (total_params == 1 and !has_vararg) {
        // Single arg (no vararg) - create simple wrapper struct
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
        // Multiple args or has vararg - create wrapper struct with unique parameter names
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

        // Add vararg to param_names
        var vararg_param_name: ?[]const u8 = null;
        if (func.vararg) |vararg_name| {
            vararg_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__p_{s}_{d}",
                .{ vararg_name, wrapper_counter },
            );
            try param_names.append(self.allocator, vararg_param_name.?);
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

    // Suppress unused local constant warning for the wrapper
    try self.emitIndent();
    try self.output.writer(self.allocator).print("_ = &{s};\n", .{wrapper_name});

    // Emit alias so original name can be used: const f = __closure_f_0;
    // This allows code like [f, C.m] to work
    // Check if func.name would shadow a module-level import
    const shadows_import = self.imported_modules.contains(func.name);

    // If shadowing an import, use a prefixed name to avoid Zig's "shadows declaration" error
    const alias_name = if (shadows_import)
        try std.fmt.allocPrint(self.allocator, "__local_{s}_{d}", .{ func.name, saved_counter })
    else
        try self.allocator.dupe(u8, func.name);
    defer self.allocator.free(alias_name);

    try self.emitIndent();
    try self.emit("const ");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), alias_name);
    try self.output.writer(self.allocator).print(" = {s};\n", .{wrapper_name});

    // If we renamed the function, also add a var_rename so calls use the prefixed name
    if (shadows_import) {
        const alias_copy = try self.allocator.dupe(u8, alias_name);
        try self.var_renames.put(func.name, alias_copy);
    }

    // Suppress unused local constant warning for the alias
    try self.emitIndent();
    try self.emit("_ = &");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), alias_name);
    try self.emit(";\n");

    // Mark as closure so calls use .call() syntax
    const func_name_copy = try self.allocator.dupe(u8, func.name);
    try self.closure_vars.put(func_name_copy, {});
}

/// Generate a zero-capture closure at module level.
/// This is called during the pre-scan phase for functions that return closures.
/// The generated type can be used as the function's return type.
pub fn genModuleLevelZeroCaptureClosure(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    type_name: []const u8,
) CodegenError!void {
    const saved_counter = self.lambda_counter;

    // Generate the implementation struct at module level
    const impl_name = try std.fmt.allocPrint(
        self.allocator,
        "__ModImpl_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(impl_name);

    const inner_fn_name = try std.fmt.allocPrint(
        self.allocator,
        "__fn_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(inner_fn_name);

    // Build param name mappings for unique names
    var param_renames = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
    defer {
        for (param_renames.values()) |v| self.allocator.free(v);
        param_renames.deinit();
    }

    // Generate impl struct
    try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{impl_name});
    try self.output.writer(self.allocator).print("    fn {s}(", .{inner_fn_name});

    // Generate parameters
    for (func.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        const is_used = var_tracking.isParamUsedInStmts(arg.name, func.body);
        if (is_used) {
            const unique_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__p_{s}_{d}",
                .{ arg.name, saved_counter },
            );
            try param_renames.put(arg.name, unique_param_name);
            try self.output.writer(self.allocator).print("{s}: anytype", .{unique_param_name});
        } else {
            try self.emit("_: anytype");
        }
    }

    // Handle vararg
    if (func.vararg) |vararg_name| {
        if (func.args.len > 0) try self.emit(", ");
        const is_vararg_used = var_tracking.isParamUsedInStmts(vararg_name, func.body);
        if (is_vararg_used) {
            const unique_vararg_name = try std.fmt.allocPrint(
                self.allocator,
                "__p_{s}_{d}",
                .{ vararg_name, saved_counter },
            );
            try param_renames.put(vararg_name, unique_vararg_name);
            try self.output.writer(self.allocator).print("{s}: anytype", .{unique_vararg_name});
        } else {
            try self.emit("_: anytype");
        }
    }

    // Determine return type
    const return_type = self.type_inferrer.func_return_types.get(func.name);
    if (return_type) |rt| {
        try self.emit(") !");
        const native_types = @import("../../../../../analysis/native_types.zig");
        var type_buf = std.ArrayList(u8){};
        defer type_buf.deinit(self.allocator);
        try native_types.NativeType.toZigType(rt, self.allocator, &type_buf);
        try self.emit(type_buf.items);
        try self.emit(" {\n");
    } else {
        try self.emit(") !*runtime.PyObject {\n");
    }

    // Generate function body
    try self.pushScope();

    // Mark that we're inside a nested function body - this affects isDeclared()
    const saved_inside_nested = self.inside_nested_function;
    self.inside_nested_function = true;
    defer self.inside_nested_function = saved_inside_nested;

    // Add parameter renames to var_renames temporarily
    var rename_keys = std.ArrayList([]const u8){};
    defer rename_keys.deinit(self.allocator);
    var rename_iter = param_renames.iterator();
    while (rename_iter.next()) |entry| {
        try self.declareVar(entry.key_ptr.*);
        try self.var_renames.put(entry.key_ptr.*, entry.value_ptr.*);
        try rename_keys.append(self.allocator, entry.key_ptr.*);
    }

    // Handle vararg scope
    if (func.vararg) |vararg_name| {
        try self.declareVar(vararg_name);
        if (param_renames.get(vararg_name)) |renamed| {
            try self.var_renames.put(vararg_name, renamed);
        }
    }

    self.indent();
    self.indent(); // Extra indent for inside struct fn

    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    self.dedent();
    self.dedent();
    self.popScope();

    // Remove param renames
    for (rename_keys.items) |key| {
        _ = self.var_renames.swapRemove(key);
    }
    if (func.vararg) |vararg_name| {
        _ = self.var_renames.swapRemove(vararg_name);
    }

    try self.emit("    }\n");
    try self.emit("};\n\n");

    // Generate wrapper type with the specified type_name
    // This wrapper calls the impl struct
    try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{type_name});
    try self.emit("    pub fn call(_: @This()");

    // Parameter list for wrapper
    const wrapper_counter = saved_counter + 1;
    var param_names = std.ArrayList([]const u8){};
    defer {
        for (param_names.items) |name| self.allocator.free(name);
        param_names.deinit(self.allocator);
    }

    for (func.args) |arg| {
        const unique_name = try std.fmt.allocPrint(
            self.allocator,
            "__p_{s}_{d}",
            .{ arg.name, wrapper_counter },
        );
        try param_names.append(self.allocator, unique_name);
        try self.output.writer(self.allocator).print(", {s}: anytype", .{unique_name});
    }

    if (func.vararg) |vararg_name| {
        const vararg_param_name = try std.fmt.allocPrint(
            self.allocator,
            "__p_{s}_{d}",
            .{ vararg_name, wrapper_counter },
        );
        try param_names.append(self.allocator, vararg_param_name);
        try self.output.writer(self.allocator).print(", {s}: anytype", .{vararg_param_name});
    }

    // Return type for wrapper
    if (return_type) |rt| {
        try self.emit(") !");
        const native_types = @import("../../../../../analysis/native_types.zig");
        var type_buf = std.ArrayList(u8){};
        defer type_buf.deinit(self.allocator);
        try native_types.NativeType.toZigType(rt, self.allocator, &type_buf);
        try self.emit(type_buf.items);
        try self.emit(" {\n");
    } else {
        try self.emit(") !*runtime.PyObject {\n");
    }

    // Call impl
    try self.output.writer(self.allocator).print("        return try {s}.{s}(", .{ impl_name, inner_fn_name });
    for (param_names.items, 0..) |pname, i| {
        if (i > 0) try self.emit(", ");
        try self.emit(pname);
    }
    try self.emit(");\n");
    try self.emit("    }\n");
    try self.emit("};\n\n");

    // Mark the function as a closure
    const func_name_copy = try self.allocator.dupe(u8, func.name);
    try self.closure_vars.put(func_name_copy, {});
}
