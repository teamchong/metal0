/// Standard closure generation with captured variables
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const DeferredClosureInfo = @import("../../../main/core.zig").DeferredClosureInfo;
const zig_keywords = @import("zig_keywords");
const hashmap_helper = @import("hashmap_helper");
const var_tracking = @import("var_tracking.zig");

/// Emit the type annotation for a captured variable in a closure struct.
/// This centralizes type inference logic for captured variables:
/// - 'self' in class context -> *const ClassName
/// - Known closures -> @TypeOf(closure_var_name) (closures have complex parameterized types)
/// - Inferred types -> use type inference
/// - Unknown -> *runtime.PyObject as fallback
fn emitCapturedVarType(self: *NativeCodegen, var_name: []const u8) CodegenError!void {
    // Case 1: 'self' in a class context
    if (std.mem.eql(u8, var_name, "self") and self.current_class_name != null) {
        try self.output.writer(self.allocator).print(": *const {s}", .{self.current_class_name.?});
        return;
    }

    // Case 2: Captured variable is itself a closure
    // Closures have complex parameterized types (AnyClosure1, AnyClosure2, etc.)
    // that can't be expressed statically. Use @TypeOf() to infer from the actual value.
    // Note: anytype can only be used in function params, not struct fields.
    if (self.closure_vars.contains(var_name)) {
        try self.emit(": @TypeOf(");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
        try self.emit(")");
        return;
    }

    // Case 3: Try to infer the type from type analysis
    const var_type = self.getLocalVarType(var_name) orelse
        self.getVarType(var_name) orelse
        self.type_inferrer.getScopedVar(var_name) orelse
        .unknown;
    const type_str = try self.nativeTypeToZigType(var_type);
    defer self.allocator.free(type_str);
    try self.output.writer(self.allocator).print(": {s}", .{type_str});
}

/// Generate standard closure with captured variables
pub fn genStandardClosure(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    captured_vars: [][]const u8,
) CodegenError!void {
    // Save counter before any nested generation that might increment it
    const saved_counter = self.lambda_counter;
    self.lambda_counter += 1;

    // Generate comptime closure using runtime.Closure1 helper
    const closure_impl_name = try std.fmt.allocPrint(
        self.allocator,
        "__ClosureImpl_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(closure_impl_name);

    // Generate the capture struct type (must be defined once and reused)
    const capture_type_name = try std.fmt.allocPrint(
        self.allocator,
        "__CaptureType_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(capture_type_name);

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = struct {{", .{capture_type_name});
    for (captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        try self.emit(" ");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
        // Emit the type for this captured variable
        try emitCapturedVarType(self, var_name);
    }
    try self.emit(" };\n");

    // Generate the inner function that takes (captures, args...)
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{closure_impl_name});
    self.indent();

    // Generate static function that closure will call
    // Use unique name based on function name + saved counter to avoid shadowing
    const impl_fn_name = try std.fmt.allocPrint(
        self.allocator,
        "call_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(impl_fn_name);

    // Use unique capture param name to avoid shadowing in nested closures
    const capture_param_name = try std.fmt.allocPrint(
        self.allocator,
        "__cap_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(capture_param_name);

    // Check if captured vars are actually used in the function body
    const captures_used = var_tracking.areCapturedVarsUsed(captured_vars, func.body);

    try self.emitIndent();
    if (captures_used) {
        try self.output.writer(self.allocator).print("fn {s}({s}: {s}", .{ impl_fn_name, capture_param_name, capture_type_name });
    } else {
        // Captures not used, use _ to avoid unused parameter error
        try self.output.writer(self.allocator).print("fn {s}(_: {s}", .{ impl_fn_name, capture_type_name });
    }

    // Generate renamed parameters to avoid shadowing outer scope
    // Build a mapping from original param names to renamed versions
    var param_renames = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
    defer param_renames.deinit();

    for (func.args) |arg| {
        // Check if param is used in body - if not, use _ to discard (Zig 0.15 requirement)
        const is_used = var_tracking.isParamUsedInStmts(arg.name, func.body);
        if (is_used) {
            // Create a unique parameter name to avoid shadowing: __p_name_counter
            const unique_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__p_{s}_{d}",
                .{ arg.name, saved_counter },
            );
            try param_renames.put(arg.name, unique_param_name);
            try self.output.writer(self.allocator).print(", {s}: anytype", .{unique_param_name});
        } else {
            try self.output.writer(self.allocator).print(", _: anytype", .{});
        }
    }
    // Handle *args (vararg) parameter
    if (func.vararg) |vararg_name| {
        const is_used = var_tracking.isParamUsedInStmts(vararg_name, func.body);
        if (is_used) {
            const unique_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__p_{s}_{d}",
                .{ vararg_name, saved_counter },
            );
            try param_renames.put(vararg_name, unique_param_name);
            try self.output.writer(self.allocator).print(", {s}: anytype", .{unique_param_name});
        } else {
            try self.output.writer(self.allocator).print(", _: anytype", .{});
        }
    }
    // Handle **kwargs (kwarg) parameter
    if (func.kwarg) |kwarg_name| {
        const is_used = var_tracking.isParamUsedInStmts(kwarg_name, func.body);
        if (is_used) {
            const unique_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__p_{s}_{d}",
                .{ kwarg_name, saved_counter },
            );
            try param_renames.put(kwarg_name, unique_param_name);
            try self.output.writer(self.allocator).print(", {s}: anytype", .{unique_param_name});
        } else {
            try self.output.writer(self.allocator).print(", _: anytype", .{});
        }
    }
    // Determine return type based on body analysis:
    // - Has return with value -> anyerror!i64
    // - Can produce errors (calls, etc.) -> anyerror!void
    // - Neither -> void
    if (var_tracking.hasReturnWithValue(func.body)) {
        try self.emit(") anyerror!i64 {\n");
    } else if (var_tracking.canProduceErrors(func.body)) {
        try self.emit(") anyerror!void {\n");
    } else {
        try self.emit(") void {\n");
    }

    // Generate body with captured vars renamed to capture_param.varname
    self.indent();
    try self.pushScope();

    // Mark that we're inside a nested function body - this affects isDeclared()
    // Variables from outer scope that weren't captured should be treated as undeclared
    const saved_inside_nested = self.inside_nested_function;
    self.inside_nested_function = true;
    defer self.inside_nested_function = saved_inside_nested;

    // Save and reset control_flow_terminated - nested function has its own control flow
    const saved_control_flow_terminated = self.control_flow_terminated;
    self.control_flow_terminated = false;
    defer self.control_flow_terminated = saved_control_flow_terminated;

    // Add discard for capture param to avoid unused parameter warnings
    // (unittest methods like assertEqual bypass captured self and call runtime directly)
    if (captures_used) {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("_ = &{s};\n", .{capture_param_name});
    }

    // Create mutable local copies for parameters that are reassigned in body
    // (anytype params are const, but Python allows reassigning parameters)
    for (func.args) |arg| {
        if (param_renames.get(arg.name)) |renamed| {
            if (var_tracking.isParamReassignedInStmts(arg.name, func.body)) {
                // Create: var __p_name_local = __p_name;
                const local_name = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}_local",
                    .{renamed},
                );
                try self.emitIndent();
                try self.output.writer(self.allocator).print("var {s} = {s};\n", .{ local_name, renamed });
                // Update rename to use local copy
                try param_renames.put(arg.name, local_name);
            }
        }
    }

    // Save and populate func_local_uses for this nested function
    // This prevents incorrect "unused variable" detection for local vars
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

    // IMPORTANT: Save outer scope renames BEFORE we overwrite them with capture struct access
    // These are needed later when initializing the closure captures with the actual outer values
    var outer_capture_renames = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
    defer outer_capture_renames.deinit();
    for (captured_vars) |var_name| {
        if (self.var_renames.get(var_name)) |renamed| {
            try outer_capture_renames.put(var_name, renamed);
        }
    }

    // Add captured variable renames so they get prefixed with capture struct access
    var capture_renames = std.ArrayList([]const u8){};
    defer capture_renames.deinit(self.allocator);

    for (captured_vars) |var_name| {
        const rename = try std.fmt.allocPrint(
            self.allocator,
            "{s}.{s}",
            .{ capture_param_name, var_name },
        );
        try capture_renames.append(self.allocator, rename);
        try self.var_renames.put(var_name, rename);
    }

    for (func.args) |arg| {
        try self.declareVar(arg.name);
        // Add rename mapping for parameter access in body
        if (param_renames.get(arg.name)) |renamed| {
            try self.var_renames.put(arg.name, renamed);
        }
    }
    // Also declare and rename vararg if present
    if (func.vararg) |vararg_name| {
        try self.declareVar(vararg_name);
        if (param_renames.get(vararg_name)) |renamed| {
            try self.var_renames.put(vararg_name, renamed);
        }
    }
    // Also declare and rename kwarg if present
    if (func.kwarg) |kwarg_name| {
        try self.declareVar(kwarg_name);
        if (param_renames.get(kwarg_name)) |renamed| {
            try self.var_renames.put(kwarg_name, renamed);
        }
    }

    // Track closure body start position for scope-limited discard detection
    const saved_function_start = self.function_start_pos;
    self.function_start_pos = self.output.items.len;
    defer self.function_start_pos = saved_function_start;

    // Save and clear pending_discards for this closure body
    const saved_pending_discards = self.pending_discards;
    self.pending_discards = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
    defer {
        self.pending_discards.deinit();
        self.pending_discards = saved_pending_discards;
    }

    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Emit discards for unused local vars in closure body (before popScope)
    if (!self.control_flow_terminated) {
        try self.emitPendingDiscards();
    }

    // Remove param renames after body generation
    for (func.args) |arg| {
        _ = self.var_renames.swapRemove(arg.name);
    }
    // Remove vararg and kwarg renames
    if (func.vararg) |vararg_name| {
        _ = self.var_renames.swapRemove(vararg_name);
    }
    if (func.kwarg) |kwarg_name| {
        _ = self.var_renames.swapRemove(kwarg_name);
    }

    // Restore outer scope renames (or remove if there was no outer rename)
    for (captured_vars, 0..) |var_name, i| {
        if (outer_capture_renames.get(var_name)) |outer_rename| {
            // Restore the outer scope's rename
            try self.var_renames.put(var_name, outer_rename);
        } else {
            // No outer rename existed - just remove
            _ = self.var_renames.swapRemove(var_name);
        }
        self.allocator.free(capture_renames.items[i]);
    }

    self.popScope();
    self.dedent();

    try self.emitIndent();
    try self.emit("}\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // Check for forward-referenced captures (variables not yet declared)
    // These need deferred instantiation - will be instantiated when the variable is assigned
    var forward_ref_vars = std.ArrayList([]const u8){};
    defer forward_ref_vars.deinit(self.allocator);

    for (captured_vars) |var_name| {
        // Skip 'self' - it's always available in class context
        if (std.mem.eql(u8, var_name, "self")) continue;

        // Check if variable is forward-declared (not yet assigned)
        if (self.forward_declared_vars.contains(var_name)) {
            try forward_ref_vars.append(self.allocator, var_name);
        }
    }

    // Use AnyClosure for flexible parameter types (strings, ints, etc.)
    // Total param count includes args + vararg + kwarg
    var total_params: usize = func.args.len;
    if (func.vararg != null) total_params += 1;
    if (func.kwarg != null) total_params += 1;

    // Create alias with original function name - use saved_counter
    // Check if func.name would shadow a module-level import
    const shadows_import = self.imported_modules.contains(func.name);

    // Check if func.name is already declared in current scope (redefinition)
    // Python allows redefining function names: def f(): ... def f(): ... (second shadows first)
    const is_redefinition = self.isDeclared(func.name);

    // If shadowing an import or redefinition, use a prefixed name to avoid Zig's "shadows declaration" error
    const alias_name = if (shadows_import or is_redefinition)
        try std.fmt.allocPrint(self.allocator, "__local_{s}_{d}", .{ func.name, saved_counter })
    else
        try self.allocator.dupe(u8, func.name);
    defer self.allocator.free(alias_name);

    // Create closure variable name
    const closure_var_name = try std.fmt.allocPrint(
        self.allocator,
        "__closure_{s}_{d}",
        .{ func.name, saved_counter },
    );

    // Note: impl_fn_name is already created above (line ~59) and is still in scope

    if (forward_ref_vars.items.len > 0) {
        // Defer instantiation - store info to instantiate later when variables are available
        // Make persistent copies of names for deferred use
        const closure_var_name_copy = try self.allocator.dupe(u8, closure_var_name);
        const capture_type_name_copy = try self.allocator.dupe(u8, capture_type_name);
        const closure_impl_name_copy = try self.allocator.dupe(u8, closure_impl_name);
        const impl_fn_name_copy = try self.allocator.dupe(u8, impl_fn_name);
        const alias_name_copy = try self.allocator.dupe(u8, alias_name);
        const func_name_copy = try self.allocator.dupe(u8, func.name);

        // Copy captured vars
        var captured_vars_copy = try self.allocator.alloc([]const u8, captured_vars.len);
        for (captured_vars, 0..) |v, i| {
            captured_vars_copy[i] = try self.allocator.dupe(u8, v);
        }

        // Copy forward ref vars
        var forward_ref_copy = try self.allocator.alloc([]const u8, forward_ref_vars.items.len);
        for (forward_ref_vars.items, 0..) |v, i| {
            forward_ref_copy[i] = try self.allocator.dupe(u8, v);
        }

        const deferred_info = DeferredClosureInfo{
            .func_name = func_name_copy,
            .closure_var_name = closure_var_name_copy,
            .capture_type_name = capture_type_name_copy,
            .closure_impl_name = closure_impl_name_copy,
            .impl_fn_name = impl_fn_name_copy,
            .captured_vars = captured_vars_copy,
            .total_params = total_params,
            .forward_ref_vars = forward_ref_copy,
            .alias_name = alias_name_copy,
        };

        // Register deferred instantiation for each forward-ref variable
        // When any of them is assigned, the closure will be instantiated
        for (forward_ref_vars.items) |fwd_var| {
            const gop = try self.deferred_closure_instantiations.getOrPut(fwd_var);
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayList(DeferredClosureInfo){};
            }
            try gop.value_ptr.append(self.allocator, deferred_info);
        }

        // Mark this variable as a closure so calls use .call() syntax (even before instantiation)
        try self.closure_vars.put(func_name_copy, {});

        // Free closure_var_name since we copied it - impl_fn_name is freed by defer at function end
        self.allocator.free(closure_var_name);
    } else {
        // Immediate instantiation - all captures are available
        defer self.allocator.free(closure_var_name);
        // Note: impl_fn_name is freed by the defer at line ~64

        try self.emitIndent();

        if (total_params == 0) {
            try self.output.writer(self.allocator).print(
                "const {s} = runtime.AnyClosure0({s}, ",
                .{ closure_var_name, capture_type_name },
            );
        } else if (total_params == 1) {
            try self.output.writer(self.allocator).print(
                "const {s} = runtime.AnyClosure1({s}, ",
                .{ closure_var_name, capture_type_name },
            );
        } else if (total_params == 2) {
            try self.output.writer(self.allocator).print(
                "const {s} = runtime.AnyClosure2({s}, ",
                .{ closure_var_name, capture_type_name },
            );
        } else if (total_params == 3) {
            try self.output.writer(self.allocator).print(
                "const {s} = runtime.AnyClosure3({s}, ",
                .{ closure_var_name, capture_type_name },
            );
        } else if (total_params == 4) {
            try self.output.writer(self.allocator).print(
                "const {s} = runtime.AnyClosure4({s}, ",
                .{ closure_var_name, capture_type_name },
            );
        } else if (total_params == 5) {
            try self.output.writer(self.allocator).print(
                "const {s} = runtime.AnyClosure5({s}, ",
                .{ closure_var_name, capture_type_name },
            );
        } else if (total_params == 6) {
            try self.output.writer(self.allocator).print(
                "const {s} = runtime.AnyClosure6({s}, ",
                .{ closure_var_name, capture_type_name },
            );
        } else if (total_params == 7) {
            try self.output.writer(self.allocator).print(
                "const {s} = runtime.AnyClosure7({s}, ",
                .{ closure_var_name, capture_type_name },
            );
        } else {
            // For functions with more than 7 params, fall back to AnyClosure7
            // This is rare in practice; most closures have few parameters
            try self.output.writer(self.allocator).print(
                "const {s} = runtime.AnyClosure7({s}, ",
                .{ closure_var_name, capture_type_name },
            );
        }

        try self.output.writer(self.allocator).print(
            "{s}.{s}){{ .captures = .{{",
            .{ closure_impl_name, impl_fn_name },
        );

        // Initialize captures - use renamed variable names from outer scope saved earlier
        for (captured_vars, 0..) |var_name, i| {
            if (i > 0) try self.emit(", ");
            // Check saved outer renames first (for params that were renamed in outer function),
            // then fall back to current var_renames, then the original name
            const actual_name = outer_capture_renames.get(var_name) orelse
                self.var_renames.get(var_name) orelse var_name;
            try self.output.writer(self.allocator).print(" .{s} = {s}", .{ var_name, actual_name });
        }
        try self.emit(" } };\n");

        try self.emitIndent();
        try self.emit("const ");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), alias_name);
        try self.output.writer(self.allocator).print(" = {s};\n", .{closure_var_name});

        // If we renamed the function, also add a var_rename so calls use the prefixed name
        if (shadows_import or is_redefinition) {
            const alias_copy = try self.allocator.dupe(u8, alias_name);
            try self.var_renames.put(func.name, alias_copy);
        }

        // Declare the alias name (using unique name if redefinition)
        try self.declareVar(alias_name);

        // Mark this variable as a closure so calls use .call() syntax
        const func_name_copy = try self.allocator.dupe(u8, func.name);
        try self.closure_vars.put(func_name_copy, {});
    }
}

/// Emit closure instantiation code (can be called immediately or deferred)
/// This generates the code that creates the closure value and assigns it to a variable
pub fn emitClosureInstantiation(
    self: *NativeCodegen,
    info: DeferredClosureInfo,
) CodegenError!void {
    try self.emitIndent();

    // Select AnyClosure based on param count
    if (info.total_params == 0) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.AnyClosure0({s}, ",
            .{ info.closure_var_name, info.capture_type_name },
        );
    } else if (info.total_params == 1) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.AnyClosure1({s}, ",
            .{ info.closure_var_name, info.capture_type_name },
        );
    } else if (info.total_params == 2) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.AnyClosure2({s}, ",
            .{ info.closure_var_name, info.capture_type_name },
        );
    } else if (info.total_params == 3) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.AnyClosure3({s}, ",
            .{ info.closure_var_name, info.capture_type_name },
        );
    } else if (info.total_params == 4) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.AnyClosure4({s}, ",
            .{ info.closure_var_name, info.capture_type_name },
        );
    } else if (info.total_params == 5) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.AnyClosure5({s}, ",
            .{ info.closure_var_name, info.capture_type_name },
        );
    } else if (info.total_params == 6) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.AnyClosure6({s}, ",
            .{ info.closure_var_name, info.capture_type_name },
        );
    } else {
        // For 7+ params, use AnyClosure7
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.AnyClosure7({s}, ",
            .{ info.closure_var_name, info.capture_type_name },
        );
    }

    try self.output.writer(self.allocator).print(
        "{s}.{s}){{ .captures = .{{",
        .{ info.closure_impl_name, info.impl_fn_name },
    );

    // Initialize captures
    for (info.captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        // Use var_renames if available, otherwise use original name
        const actual_name = self.var_renames.get(var_name) orelse var_name;
        try self.output.writer(self.allocator).print(" .{s} = {s}", .{ var_name, actual_name });
    }
    try self.emit(" } };\n");

    // Create alias with original function name
    try self.emitIndent();
    try self.emit("const ");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), info.alias_name);
    try self.output.writer(self.allocator).print(" = {s};\n", .{info.closure_var_name});

    // Declare the alias name
    try self.declareVar(info.alias_name);

    // Mark this variable as a closure so calls use .call() syntax
    const func_name_copy = try self.allocator.dupe(u8, info.func_name);
    try self.closure_vars.put(func_name_copy, {});
}

/// Generate nested function with outer capture context awareness
/// This handles the case where a closure is defined inside another closure
pub fn genNestedFunctionWithOuterCapture(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    outer_captured_vars: [][]const u8,
    outer_capture_param: []const u8,
) CodegenError!void {
    // Use captured variables from AST (pre-computed by closure analyzer)
    const captured_vars = func.captured_vars;

    if (captured_vars.len == 0) {
        // No captures - use ZeroClosure comptime pattern
        const zero_capture = @import("zero_capture.zig");
        try self.emitIndent();
        try zero_capture.genZeroCaptureClosure(self, func);
        return;
    }

    // Save counter before any nested generation that might increment it
    const saved_counter = self.lambda_counter;
    self.lambda_counter += 1;

    // Generate comptime closure using runtime.Closure1 helper
    const closure_impl_name = try std.fmt.allocPrint(
        self.allocator,
        "__ClosureImpl_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(closure_impl_name);

    // Generate the capture struct type (must be defined once and reused)
    const capture_type_name = try std.fmt.allocPrint(
        self.allocator,
        "__CaptureType_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(capture_type_name);

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = struct {{", .{capture_type_name});
    for (captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        try self.emit(" ");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
        // Emit the type for this captured variable
        try emitCapturedVarType(self, var_name);
    }
    try self.emit(" };\n");

    // Generate the inner function that takes (captures, args...)
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{closure_impl_name});
    self.indent();

    // Generate static function that closure will call
    const impl_fn_name = try std.fmt.allocPrint(
        self.allocator,
        "call_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(impl_fn_name);

    // Use unique capture param name to avoid shadowing in nested closures
    const capture_param_name = try std.fmt.allocPrint(
        self.allocator,
        "__cap_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(capture_param_name);

    // Check if captured vars are actually used in the function body
    const captures_used = var_tracking.areCapturedVarsUsed(captured_vars, func.body);

    try self.emitIndent();
    if (captures_used) {
        try self.output.writer(self.allocator).print("fn {s}({s}: {s}", .{ impl_fn_name, capture_param_name, capture_type_name });
    } else {
        // Captures not used, use _ to avoid unused parameter error
        try self.output.writer(self.allocator).print("fn {s}(_: {s}", .{ impl_fn_name, capture_type_name });
    }

    // Generate renamed parameters to avoid shadowing outer scope (duplicate of above section)
    var param_renames = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
    defer param_renames.deinit();

    for (func.args) |arg| {
        // Check if param is used in body - if not, use _ to discard (Zig 0.15 requirement)
        const is_used = var_tracking.isParamUsedInStmts(arg.name, func.body);
        if (is_used) {
            // Create a unique parameter name to avoid shadowing: __p_name_counter
            const unique_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__p_{s}_{d}",
                .{ arg.name, saved_counter },
            );
            try param_renames.put(arg.name, unique_param_name);
            try self.output.writer(self.allocator).print(", {s}: anytype", .{unique_param_name});
        } else {
            try self.output.writer(self.allocator).print(", _: anytype", .{});
        }
    }
    // Determine return type based on body analysis
    if (var_tracking.hasReturnWithValue(func.body)) {
        try self.emit(") anyerror!i64 {\n");
    } else if (var_tracking.canProduceErrors(func.body)) {
        try self.emit(") anyerror!void {\n");
    } else {
        try self.emit(") void {\n");
    }

    // Generate body with captured vars renamed to capture_param.varname
    self.indent();
    try self.pushScope();

    // Mark that we're inside a nested function body - this affects isDeclared()
    // Variables from outer scope that weren't captured should be treated as undeclared
    const saved_inside_nested = self.inside_nested_function;
    self.inside_nested_function = true;
    defer self.inside_nested_function = saved_inside_nested;

    // Save and reset control_flow_terminated - nested function has its own control flow
    const saved_control_flow_terminated2 = self.control_flow_terminated;
    self.control_flow_terminated = false;
    defer self.control_flow_terminated = saved_control_flow_terminated2;

    // Add discard for capture param to avoid unused parameter warnings
    if (captures_used) {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("_ = &{s};\n", .{capture_param_name});
    }

    // Create mutable local copies for parameters that are reassigned in body
    for (func.args) |arg| {
        if (param_renames.get(arg.name)) |renamed| {
            if (var_tracking.isParamReassignedInStmts(arg.name, func.body)) {
                const local_name = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}_local",
                    .{renamed},
                );
                try self.emitIndent();
                try self.output.writer(self.allocator).print("var {s} = {s};\n", .{ local_name, renamed });
                try param_renames.put(arg.name, local_name);
            }
        }
    }

    // Save and populate func_local_uses for this nested function
    const saved_func_local_uses2 = self.func_local_uses;
    self.func_local_uses = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.func_local_uses.deinit();
        self.func_local_uses = saved_func_local_uses2;
    }

    // Save and clear hoisted_vars - nested function has its own hoisting context
    const saved_hoisted_vars2 = self.hoisted_vars;
    self.hoisted_vars = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.hoisted_vars.deinit();
        self.hoisted_vars = saved_hoisted_vars2;
    }

    // Populate func_local_uses with variables used in this function body
    try var_tracking.collectUsedNames(func.body, &self.func_local_uses);

    // IMPORTANT: Save outer scope renames BEFORE we overwrite them with capture struct access
    var outer_capture_renames2 = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
    defer outer_capture_renames2.deinit();
    for (captured_vars) |var_name| {
        if (self.var_renames.get(var_name)) |renamed| {
            try outer_capture_renames2.put(var_name, renamed);
        }
    }

    // Add captured variable renames so they get prefixed with capture struct access
    var capture_renames = std.ArrayList([]const u8){};
    defer capture_renames.deinit(self.allocator);

    for (captured_vars) |var_name| {
        const rename = try std.fmt.allocPrint(
            self.allocator,
            "{s}.{s}",
            .{ capture_param_name, var_name },
        );
        try capture_renames.append(self.allocator, rename);
        try self.var_renames.put(var_name, rename);
    }

    for (func.args) |arg| {
        try self.declareVar(arg.name);
        // Add rename mapping for parameter access in body
        if (param_renames.get(arg.name)) |renamed| {
            try self.var_renames.put(arg.name, renamed);
        }
    }

    // Track closure body start position for scope-limited discard detection
    const saved_function_start2 = self.function_start_pos;
    self.function_start_pos = self.output.items.len;
    defer self.function_start_pos = saved_function_start2;

    // Save and clear pending_discards for this closure body
    const saved_pending_discards2 = self.pending_discards;
    self.pending_discards = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
    defer {
        self.pending_discards.deinit();
        self.pending_discards = saved_pending_discards2;
    }

    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Emit discards for unused local vars in closure body (before popScope)
    if (!self.control_flow_terminated) {
        try self.emitPendingDiscards();
    }

    // Remove param renames after body generation
    for (func.args) |arg| {
        _ = self.var_renames.swapRemove(arg.name);
    }

    // Restore outer scope renames (or remove if there was no outer rename)
    for (captured_vars, 0..) |var_name, i| {
        if (outer_capture_renames2.get(var_name)) |outer_rename| {
            try self.var_renames.put(var_name, outer_rename);
        } else {
            _ = self.var_renames.swapRemove(var_name);
        }
        self.allocator.free(capture_renames.items[i]);
    }

    self.popScope();
    self.dedent();

    try self.emitIndent();
    try self.emit("}\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // Create closure type using comptime helper based on arg count
    const closure_var_name = try std.fmt.allocPrint(
        self.allocator,
        "__closure_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(closure_var_name);

    try self.emitIndent();
    if (func.args.len == 0) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure0({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else if (func.args.len == 1) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure1({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else if (func.args.len == 2) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure2({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else if (func.args.len == 3) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure3({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure1({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    }

    // Arg types (skip for zero-arg closures)
    for (func.args, 0..) |_, i| {
        if (func.args.len > 1 and i > 0) try self.emit(", ");
        try self.emit("i64");
        if (func.args.len == 1 or i == func.args.len - 1) {
            try self.emit(", ");
        }
    }

    // Return type and function
    const impl_fn_ref = try std.fmt.allocPrint(
        self.allocator,
        "call_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(impl_fn_ref);

    try self.output.writer(self.allocator).print(
        "{s}.{s}){{ .captures = .{{",
        .{ closure_impl_name, impl_fn_ref },
    );

    // Initialize captures - reference outer captured vars through outer capture struct
    // or use renamed variable names if applicable
    for (captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        // Check if this var is from outer closure's captures
        var is_outer_capture = false;
        for (outer_captured_vars) |outer_var| {
            if (std.mem.eql(u8, var_name, outer_var)) {
                is_outer_capture = true;
                break;
            }
        }
        if (is_outer_capture) {
            try self.output.writer(self.allocator).print(" .{s} = {s}.{s}", .{ var_name, outer_capture_param, var_name });
        } else {
            // Check if this var was renamed (e.g., function parameter renamed to avoid shadowing)
            const actual_name = self.var_renames.get(var_name) orelse var_name;
            try self.output.writer(self.allocator).print(" .{s} = {s}", .{ var_name, actual_name });
        }
    }
    try self.emit(" } };\n");

    // Create alias with original function name
    // Check if func.name would shadow a module-level import
    const shadows_import2 = self.imported_modules.contains(func.name);

    // Check if func.name is already declared in current scope (redefinition)
    // Python allows redefining function names: def f(): ... def f(): ... (second shadows first)
    const is_redefinition2 = self.isDeclared(func.name);

    // If shadowing an import or redefinition, use a prefixed name to avoid Zig's "shadows declaration" error
    const alias_name2 = if (shadows_import2 or is_redefinition2)
        try std.fmt.allocPrint(self.allocator, "__local_{s}_{d}", .{ func.name, saved_counter })
    else
        try self.allocator.dupe(u8, func.name);
    defer self.allocator.free(alias_name2);

    try self.emitIndent();
    try self.emit("const ");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), alias_name2);
    try self.output.writer(self.allocator).print(" = {s};\n", .{closure_var_name});

    // If we renamed the function, also add a var_rename so calls use the prefixed name
    if (shadows_import2 or is_redefinition2) {
        const alias_copy2 = try self.allocator.dupe(u8, alias_name2);
        try self.var_renames.put(func.name, alias_copy2);
    }

    // Declare the alias name (using unique name if redefinition)
    try self.declareVar(alias_name2);

    // Mark this variable as a closure so calls use .call() syntax
    const func_name_copy = try self.allocator.dupe(u8, func.name);
    try self.closure_vars.put(func_name_copy, {});
}
