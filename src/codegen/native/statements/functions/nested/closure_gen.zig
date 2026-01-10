/// Standard closure generation with captured variables
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const DeferredClosureInfo = @import("../../../main/core.zig").DeferredClosureInfo;
const zig_keywords = @import("utils.zig_keywords");
const hashmap_helper = @import("utils.hashmap_helper");
const var_tracking = @import("var_tracking.zig");
const function_traits = @import("analysis.function_traits");

/// Find the specific context manager type from return statements in body
/// Returns the Zig type string for the context manager, or null if unknown
fn findContextManagerTypeInBody(body: []const ast.Node) ?[]const u8 {
    for (body) |stmt| {
        if (stmt == .return_stmt) {
            const ret = stmt.return_stmt;
            if (ret.value) |val_ptr| {
                return findContextManagerTypeInExpr(val_ptr.*);
            }
        }
    }
    return null;
}

/// Find context manager type from an expression
fn findContextManagerTypeInExpr(expr: ast.Node) ?[]const u8 {
    if (expr == .call) {
        const call = expr.call;
        if (call.func.* == .attribute) {
            const attr = call.func.attribute;
            // Check known context manager methods
            return function_traits.getContextManagerType(attr.attr);
        }
        if (call.func.* == .name) {
            // Check known context manager functions
            return function_traits.getContextManagerType(call.func.name.id);
        }
    }
    return null;
}

/// Emit the type annotation for a captured variable in a closure struct.
/// This centralizes type inference logic for captured variables:
/// - 'self' in class context -> *const ClassName
/// - Known closures -> @TypeOf(closure_var_name) (closures have complex parameterized types)
/// - Mutated vars -> pointer type (*T) so closure can modify the original
/// - Inferred types -> use type inference
/// - Unknown -> *runtime.PyObject as fallback
fn emitCapturedVarType(self: *NativeCodegen, var_name: []const u8, is_mutated: bool) CodegenError!void {
    const container_traits = @import("../../../../../analysis/traits/container_traits.zig");

    // Case 1: 'self' in a class context
    if (std.mem.eql(u8, var_name, "self") and self.current_class_name != null) {
        try self.emitFmt(": *const {s}", .{self.current_class_name.?});
        return;
    }

    // Case 2: Captured variable is itself a closure
    // Using @TypeOf() to get the exact closure type - this preserves compatibility
    // with the closure's .call() method. AnyCallable has anytype making it comptime-only.
    if (self.closure_vars.contains(var_name)) {
        if (is_mutated) {
            try self.emit(": *@TypeOf(");
        } else {
            try self.emit(": @TypeOf(");
        }
        if (self.var_renames.get(var_name)) |renamed| {
            try self.emit(renamed);
        } else {
            try self.emitIdent(var_name);
        }
        try self.emit(")");
        return;
    }

    // Case 3: Try to infer the type from type analysis
    const var_type = self.getLocalVarType(var_name) orelse
        self.getVarType(var_name) orelse
        self.type_inferrer.getScopedVar(var_name) orelse
        .unknown;

    // Case 4: For mutable containers (lists, dicts) with unknown element types,
    // use @TypeOf() to get the actual type from the variable at capture time.
    // This avoids type mismatches when mutation analysis inside nested functions
    // determines a different element type than static analysis.
    // E.g., actual_calls = []; def f(): actual_calls.append((pos, value))
    // Static analysis sees .list with unknown element, but declaration uses tuple type.
    if (container_traits.isList(var_type) or container_traits.isDict(var_type)) {
        // Check if element type is unknown (couldn't be determined statically)
        const has_unknown_element = switch (var_type) {
            .list => |elem| elem.* == .unknown,
            .dict => |kv| kv.value.* == .unknown,
            else => false,
        };
        if (has_unknown_element) {
            // For mutated vars, use pointer to @TypeOf
            if (is_mutated) {
                try self.emit(": *@TypeOf(");
            } else {
                try self.emit(": @TypeOf(");
            }
            if (self.var_renames.get(var_name)) |renamed| {
                try self.emit(renamed);
            } else {
                try self.emitIdent(var_name);
            }
            try self.emit(")");
            return;
        }
    }

    // Case 5: If type is still unknown, use runtime.AnyCallable
    // This uses vtable dispatch to prevent monomorphization explosion
    // Wraps the function with function pointers for .call() and .__name__
    if (var_type == .unknown) {
        if (is_mutated) {
            try self.emit(": *runtime.AnyCallable");
        } else {
            try self.emit(": runtime.AnyCallable");
        }
        return;
    }

    // For mutated vars, wrap with pointer
    if (is_mutated) {
        const type_str = try self.nativeTypeToZigType(var_type);
        defer self.allocator.free(type_str);
        try self.emitFmt(": *{s}", .{type_str});
    } else {
        const type_str = try self.nativeTypeToZigType(var_type);
        defer self.allocator.free(type_str);
        try self.emitFmt(": {s}", .{type_str});
    }
}

/// Convert Python type annotation to Zig type string
/// Returns "anytype" for unknown/missing annotations to maintain flexibility
fn pythonTypeToZig(type_annotation: ?[]const u8) []const u8 {
    const annotation = type_annotation orelse return "anytype";
    if (std.mem.eql(u8, annotation, "int")) return "i64";
    if (std.mem.eql(u8, annotation, "float")) return "f64";
    if (std.mem.eql(u8, annotation, "str")) return "[]const u8";
    if (std.mem.eql(u8, annotation, "bool")) return "bool";
    if (std.mem.eql(u8, annotation, "bytes")) return "[]const u8";
    if (std.mem.eql(u8, annotation, "None")) return "void";
    // For complex types (List, Dict, etc.) or unknown annotations, use anytype
    return "anytype";
}

/// Generate standard closure with captured variables
pub fn genStandardClosure(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    captured_vars: [][]const u8,
) CodegenError!void {
    // Save ID before any nested generation
    const saved_id = self.name_gen.nextId();

    // Identify captured vars that are mutated in the function body
    // These need to be captured by pointer (*T) instead of by value (T)
    // Also mark `nonlocal` variables as mutated - `nonlocal x` declares intent to modify outer x
    var mutated_captures = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer mutated_captures.deinit();
    for (captured_vars) |var_name| {
        if (var_tracking.isVarMutatedInStmts(var_name, func.body) or
            var_tracking.isNonlocalVar(var_name, func.body))
        {
            try mutated_captures.put(var_name, {});
        }
    }

    // Track generator closures for listFromSlice wrapping during assignment
    const signature = @import("../generators/signature.zig");
    if (signature.hasYieldStatement(func.body)) {
        const func_name_copy = try self.arena.allocator().dupe(u8, func.name);
        try self.generator_closure_vars.put(func_name_copy, {});
    }

    // Generate comptime closure using runtime.Closure1 helper
    const closure_impl_name = try std.fmt.allocPrint(
        self.allocator,
        "__m{d}_ClosureImpl_{s}",
        .{ saved_id, func.name },
    );
    defer self.allocator.free(closure_impl_name);

    // Generate the capture struct type (must be defined once and reused)
    const capture_type_name = try std.fmt.allocPrint(
        self.allocator,
        "__m{d}_CaptureType_{s}",
        .{ saved_id, func.name },
    );
    defer self.allocator.free(capture_type_name);

    try self.emitIndent();
    try self.emitFmt("const {s} = struct {{", .{capture_type_name});
    for (captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        try self.emit(" ");
        try self.emitIdent(var_name);
        // Emit the type for this captured variable
        // Mutated vars need pointer type so closure can modify them
        try emitCapturedVarType(self, var_name, mutated_captures.contains(var_name));
    }
    try self.emit(" };\n");

    // Generate the inner function that takes (captures, args...)
    try self.emitIndent();
    try self.emitFmt("const {s} = struct {{\n", .{closure_impl_name});
    self.indent();

    // Generate static function that closure will call
    // Use unique name based on function name + saved ID to avoid shadowing
    const impl_fn_name = try std.fmt.allocPrint(
        self.allocator,
        "__m{d}_call_{s}",
        .{ saved_id, func.name },
    );
    defer self.allocator.free(impl_fn_name);

    // Use unique capture param name to avoid shadowing in nested closures
    const capture_param_name = try std.fmt.allocPrint(
        self.allocator,
        "__m{d}_cap_{s}",
        .{ saved_id, func.name },
    );
    defer self.allocator.free(capture_param_name);

    // Check if captured vars are actually used in the function body
    const captures_used = var_tracking.areCapturedVarsUsed(captured_vars, func.body);

    try self.emitIndent();
    if (captures_used) {
        try self.emitFmt("fn {s}({s}: {s}", .{ impl_fn_name, capture_param_name, capture_type_name });
    } else {
        // Captures not used, use _ to avoid unused parameter error
        try self.emitFmt("fn {s}(_: {s}", .{ impl_fn_name, capture_type_name });
    }

    // Generate renamed parameters to avoid shadowing outer scope
    // Build a mapping from original param names to renamed versions
    var param_renames = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
    defer param_renames.deinit();

    // Track parameter types for TypedClosure (use concrete types when available)
    // This reduces monomorphization: one closure signature instead of per-call-site
    var param_types = try self.allocator.alloc([]const u8, func.args.len);
    defer self.allocator.free(param_types);
    var all_params_typed = true; // Track if all params have concrete types (not anytype)

    for (func.args, 0..) |arg, idx| {
        // Get Zig type from Python annotation, or "anytype" if unknown
        const zig_type = pythonTypeToZig(arg.type_annotation);
        param_types[idx] = zig_type;
        if (std.mem.eql(u8, zig_type, "anytype")) {
            all_params_typed = false;
        }

        // Check if param is used in body - if not, use _ to discard (Zig 0.15 requirement)
        const is_used = var_tracking.isParamUsedInStmts(arg.name, func.body);
        if (is_used) {
            // Create a unique parameter name to avoid shadowing: __p_name_id
            const unique_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__m{d}_p_{s}",
                .{ saved_id, arg.name },
            );
            try param_renames.put(arg.name, unique_param_name);
            try self.emitFmt(", {s}: {s}", .{ unique_param_name, zig_type });
        } else {
            try self.emitFmt(", _: {s}", .{zig_type});
        }
    }
    // Handle *args (vararg) parameter - always anytype (tuple of varying types)
    if (func.vararg) |vararg_name| {
        all_params_typed = false; // varargs prevent TypedClosure
        const is_used = var_tracking.isParamUsedInStmts(vararg_name, func.body);
        if (is_used) {
            const unique_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__m{d}_p_{s}",
                .{ saved_id, vararg_name },
            );
            try param_renames.put(vararg_name, unique_param_name);
            try self.emitFmt(", {s}: anytype", .{unique_param_name});
        } else {
            try self.emit(", _: anytype");
        }
    }
    // Handle **kwargs (kwarg) parameter - always anytype (dict of varying types)
    if (func.kwarg) |kwarg_name| {
        all_params_typed = false; // kwargs prevent TypedClosure
        const is_used = var_tracking.isParamUsedInStmts(kwarg_name, func.body);
        if (is_used) {
            const unique_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__m{d}_p_{s}",
                .{ saved_id, kwarg_name },
            );
            try param_renames.put(kwarg_name, unique_param_name);
            try self.emitFmt(", {s}: anytype", .{unique_param_name});
        } else {
            try self.emit(", _: anytype");
        }
    }
    // Determine return type and track for TypedClosure
    // 1. Use explicit return type annotation if available (-> int, -> float, etc.)
    // 2. Otherwise, analyze body for context managers, returns, etc.
    var return_type_str: []const u8 = "anyerror!i64"; // default for TypedClosure
    var use_typed_closure = all_params_typed; // Can use TypedClosure if all params typed

    if (func.return_type) |ret_type| {
        // Map Python type annotations to Zig types
        const zig_type = if (std.mem.eql(u8, ret_type, "int"))
            "i64"
        else if (std.mem.eql(u8, ret_type, "float"))
            "f64"
        else if (std.mem.eql(u8, ret_type, "str"))
            "[]const u8"
        else if (std.mem.eql(u8, ret_type, "bool"))
            "bool"
        else if (std.mem.eql(u8, ret_type, "None"))
            "void"
        else
            // Unknown annotation - fall back to PyValue
            "runtime.PyValue";

        if (std.mem.eql(u8, zig_type, "void")) {
            if (var_tracking.canProduceErrors(func.body)) {
                try self.emit(") anyerror!void {\n");
                return_type_str = "anyerror!void";
            } else {
                try self.emit(") void {\n");
                return_type_str = "void";
            }
        } else {
            // ALWAYS use error union since calls.zig wraps closure calls with `try`
            try self.emitFmt(") anyerror!{s} {{\n", .{zig_type});
            // Map to static strings for TypedClosure
            if (std.mem.eql(u8, zig_type, "i64")) {
                return_type_str = "anyerror!i64";
            } else if (std.mem.eql(u8, zig_type, "f64")) {
                return_type_str = "anyerror!f64";
            } else if (std.mem.eql(u8, zig_type, "bool")) {
                return_type_str = "anyerror!bool";
            } else if (std.mem.eql(u8, zig_type, "[]const u8")) {
                return_type_str = "anyerror![]const u8";
            } else {
                use_typed_closure = false; // Unknown return type, use AnyClosure
            }
        }
    } else {
        // No explicit return type - analyze body
        const closure_ret_type = function_traits.analyzeClosureReturnType(func.body);
        if (closure_ret_type == .context_manager) {
            // Context managers - find the specific return type from the body
            const ctx_type = findContextManagerTypeInBody(func.body);
            if (ctx_type) |cm_type| {
                try self.emitFmt(") {s} {{\n", .{cm_type});
            } else {
                // Fallback: use generic context manager type
                try self.emit(") runtime.unittest.AssertRaisesContext {\n");
            }
            use_typed_closure = false; // Context managers don't use TypedClosure
        } else if (closure_ret_type == .void) {
            if (var_tracking.canProduceErrors(func.body)) {
                try self.emit(") anyerror!void {\n");
                return_type_str = "anyerror!void";
            } else {
                try self.emit(") void {\n");
                return_type_str = "void";
            }
        } else {
            // Has return with value - use inferred type
            // ALWAYS use error union since calls.zig wraps closure calls with `try`
            const zig_type = function_traits.closureReturnTypeToZig(closure_ret_type);
            try self.emitFmt(") anyerror!{s} {{\n", .{zig_type});
            // Map to static strings for TypedClosure
            if (std.mem.eql(u8, zig_type, "i64")) {
                return_type_str = "anyerror!i64";
            } else if (std.mem.eql(u8, zig_type, "f64")) {
                return_type_str = "anyerror!f64";
            } else {
                return_type_str = "anyerror!i64"; // default for inferred
            }
        }
    }
    // Now we have: param_types, use_typed_closure, return_type_str for closure instantiation

    // Generate body with captured vars renamed to capture_param.varname
    self.indent();
    try self.pushScope();

    // Mark that we're inside a nested function body - this affects isDeclared()
    // Variables from outer scope that weren't captured should be treated as undeclared
    const saved_inside_nested = self.inside_nested_function;
    self.inside_nested_function = true;
    defer self.inside_nested_function = saved_inside_nested;

    // Track the base scope level for this nested function
    // isDeclared() will check all scopes from this level to current (including for loops within)
    const saved_nested_base_scope = self.nested_function_base_scope;
    self.nested_function_base_scope = self.symbol_table.currentScopeLevel();
    defer self.nested_function_base_scope = saved_nested_base_scope;

    // Save and reset control_flow_terminated - nested function has its own control flow
    const saved_control_flow_terminated = self.control_flow_terminated;
    self.control_flow_terminated = false;
    defer self.control_flow_terminated = saved_control_flow_terminated;

    // Add discard for capture param to avoid unused parameter warnings
    // (unittest methods like assertEqual bypass captured self and call runtime directly)
    if (captures_used) {
        try self.emitIndent();
        try self.emitFmt("_ = &{s};\n", .{capture_param_name});
    }

    // Create mutable local copies for parameters that are reassigned in body
    // (anytype params are const, but Python allows reassigning parameters)
    for (func.args) |arg| {
        if (param_renames.get(arg.name)) |renamed| {
            if (var_tracking.isParamReassignedInStmts(arg.name, func.body)) {
                // Create mutable copy using NameGen for consistent naming
                const local_name = try self.name_gen.mutable(arg.name);
                try self.emitIndent();
                try self.emitFmt("var {s} = {s};\n", .{ local_name, renamed });
                // Emit discard to suppress "unused local variable" warning
                try self.emitIndent();
                try self.emitFmt("_ = &{s};\n", .{local_name});
                // Update rename to use local copy
                try param_renames.put(arg.name, local_name);

                // Register the mutable copy's type in scoped type map
                // This is CRITICAL for aug_assign to detect the correct type and use native operations
                if (self.type_inferrer.getScopedVar(arg.name)) |param_type| {
                    try self.type_inferrer.putScopedVar(local_name, param_type);
                } else if (self.type_inferrer.var_types.get(arg.name)) |param_type| {
                    try self.type_inferrer.putScopedVar(local_name, param_type);
                }
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

    // Save and clear func_local_vars - nested function has its own local variables
    // Outer function's locals should NOT prevent var_renames lookup for parameters
    const saved_func_local_vars = self.func_local_vars;
    self.func_local_vars = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.func_local_vars.deinit();
        self.func_local_vars = saved_func_local_vars;
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
    // For mutated/nonlocal captures, add .* to dereference the pointer
    // For AnyCallable-wrapped captures, mark them as closures so .call() is generated
    var capture_renames = std.ArrayList([]const u8){};
    defer capture_renames.deinit(self.allocator);

    // Track which captured variables we add to closure_vars so we can clean them up later
    // This prevents captured variable names from polluting the outer scope's namespace
    var added_closure_vars = std.ArrayList([]const u8){};
    defer added_closure_vars.deinit(self.allocator);

    for (captured_vars) |var_name| {
        // Check if this is an AnyCallable-wrapped capture
        const var_type = self.getLocalVarType(var_name) orelse
            self.getVarType(var_name) orelse
            self.type_inferrer.getScopedVar(var_name) orelse
            .unknown;

        // Mark AnyCallable vars as closures so they get .call() treatment
        // Track that we added this so it can be cleaned up after closure generation
        if (var_type == .unknown) {
            try self.closure_vars.put(var_name, {});
            try added_closure_vars.append(self.allocator, var_name);
        }

        const rename = if (mutated_captures.contains(var_name))
            // Mutated/nonlocal captures are pointers - need dereference
            try std.fmt.allocPrint(
                self.allocator,
                "{s}.{s}.*",
                .{ capture_param_name, var_name },
            )
        else
            try std.fmt.allocPrint(
                self.allocator,
                "{s}.{s}",
                .{ capture_param_name, var_name },
            );
        try capture_renames.append(self.allocator, rename);
        try self.var_renames.put(var_name, rename);
    }

    for (func.args, 0..) |arg, idx| {
        try self.declareVar(arg.name);
        // Add rename mapping for parameter access in body
        // IMPORTANT: Must dupe renamed value because param_renames is deferred deinit
        if (param_renames.get(arg.name)) |renamed| {
            const renamed_copy = try self.arena.allocator().dupe(u8, renamed);
            try self.var_renames.put(arg.name, renamed_copy);
        }
        // If this param is anytype, add the ORIGINAL name to anytype_params
        // This ensures dunder dispatch checks work correctly (AST uses original names)
        if (std.mem.eql(u8, param_types[idx], "anytype")) {
            try self.anytype_params.put(arg.name, {});
        }
    }
    // Also declare and rename vararg if present (always anytype)
    if (func.vararg) |vararg_name| {
        try self.declareVar(vararg_name);
        // IMPORTANT: Must dupe renamed value because param_renames is deferred deinit
        if (param_renames.get(vararg_name)) |renamed| {
            const renamed_copy = try self.arena.allocator().dupe(u8, renamed);
            try self.var_renames.put(vararg_name, renamed_copy);
        }
        try self.anytype_params.put(vararg_name, {}); // varargs are always anytype
    }
    // Also declare and rename kwarg if present (always anytype)
    if (func.kwarg) |kwarg_name| {
        try self.declareVar(kwarg_name);
        // IMPORTANT: Must dupe renamed value because param_renames is deferred deinit
        if (param_renames.get(kwarg_name)) |renamed| {
            const renamed_copy = try self.arena.allocator().dupe(u8, renamed);
            try self.var_renames.put(kwarg_name, renamed_copy);
        }
        try self.anytype_params.put(kwarg_name, {}); // kwargs are always anytype
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

    // Save and clear mutation tracking for this closure body
    // Closures need their own mutation analysis to determine var vs const
    const saved_func_local_mutations = self.func_local_mutations;
    const saved_func_local_aug_assigns = self.func_local_aug_assigns;
    self.func_local_mutations = hashmap_helper.StringHashMap(void).init(self.allocator);
    self.func_local_aug_assigns = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.func_local_mutations.deinit();
        self.func_local_aug_assigns.deinit();
        self.func_local_mutations = saved_func_local_mutations;
        self.func_local_aug_assigns = saved_func_local_aug_assigns;
    }

    // Analyze closure body for local mutations (determines var vs const)
    // Note: passes system already analyzed mutations - this is a no-op for compatibility
    const body = @import("../generators/body.zig");
    try body.analyzeFunctionLocalMutations(self, func);

    // Analyze VM fallback variables - these are variables used inside eval() strings
    // Without this, variables like `res` in `eval("res.append(i)")` appear unused
    const vm_fallback_analysis = @import("../generators/body/vm_fallback_analysis.zig");
    try vm_fallback_analysis.analyzeVMFallbackVars(self, func);

    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Emit discards for unused local vars in closure body (before popScope)
    if (!self.control_flow_terminated) {
        try self.emitPendingDiscards();
    }

    // Remove param renames and anytype_params after body generation
    for (func.args, 0..) |arg, idx| {
        // Remove from anytype_params if we added it (using original name)
        if (std.mem.eql(u8, param_types[idx], "anytype")) {
            _ = self.anytype_params.swapRemove(arg.name);
        }
        _ = self.var_renames.swapRemove(arg.name);
    }
    // Remove vararg and kwarg renames (always anytype)
    if (func.vararg) |vararg_name| {
        _ = self.anytype_params.swapRemove(vararg_name);
        _ = self.var_renames.swapRemove(vararg_name);
    }
    if (func.kwarg) |kwarg_name| {
        _ = self.anytype_params.swapRemove(kwarg_name);
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

    // Clean up closure_vars entries we added for captured variables
    // This prevents captured variable names (like "args") from polluting the outer scope
    // and causing "undeclared identifier" errors when the outer scope tries to assign
    // a new variable with the same name
    for (added_closure_vars.items) |var_name| {
        _ = self.closure_vars.swapRemove(var_name);
    }

    self.popScope();
    self.dedent();

    try self.emitIndent();
    try self.emit("}\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // Add discard statements to prevent "unused local constant" errors
    // The closure impl/capture types might not be used if the closure itself isn't called
    try self.emitIndent();
    try self.emitFmt("_ = &{s};\n", .{closure_impl_name});
    try self.emitIndent();
    try self.emitFmt("_ = &{s};\n", .{capture_type_name});

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

    // Count required params (those without defaults)
    var required_params: usize = 0;
    for (func.args) |arg| {
        if (arg.default == null) {
            required_params += 1;
        }
    }

    // Extract parameter names for keyword argument mapping
    var param_names = try self.allocator.alloc([]const u8, func.args.len);
    for (func.args, 0..) |arg, i| {
        param_names[i] = arg.name;
    }

    // Store function signature for default parameter handling during calls
    const func_sig_name = try self.arena.allocator().dupe(u8, func.name);
    try self.function_signatures.put(func_sig_name, .{
        .total_params = total_params,
        .required_params = required_params,
        .param_names = param_names,
    });

    // Create alias with original function name - use saved_counter
    // Check if func.name would shadow a module-level import
    const shadows_import = self.imported_modules.contains(func.name);

    // Check if func.name is already declared in current scope (redefinition)
    // Python allows redefining function names: def f(): ... def f(): ... (second shadows first)
    const is_redefinition = self.isDeclared(func.name);

    // If shadowing an import or redefinition, use NameGen for consistent unique naming
    const alias_name = if (shadows_import or is_redefinition)
        try self.name_gen.closure(func.name)
    else
        try self.arena.allocator().dupe(u8, func.name);
    defer self.allocator.free(alias_name);

    // Create closure variable name
    const closure_var_name = try std.fmt.allocPrint(
        self.allocator,
        "__m{d}_closure_{s}",
        .{ saved_id, func.name },
    );

    // Note: impl_fn_name is already created above (line ~59) and is still in scope

    if (forward_ref_vars.items.len > 0) {
        // Defer instantiation - store info to instantiate later when variables are available
        // Make persistent copies of names for deferred use
        const closure_var_name_copy = try self.arena.allocator().dupe(u8, closure_var_name);
        const capture_type_name_copy = try self.arena.allocator().dupe(u8, capture_type_name);
        const closure_impl_name_copy = try self.arena.allocator().dupe(u8, closure_impl_name);
        const impl_fn_name_copy = try self.arena.allocator().dupe(u8, impl_fn_name);
        const alias_name_copy = try self.arena.allocator().dupe(u8, alias_name);
        const func_name_copy = try self.arena.allocator().dupe(u8, func.name);

        // Copy captured vars
        var captured_vars_copy = try self.allocator.alloc([]const u8, captured_vars.len);
        for (captured_vars, 0..) |v, i| {
            captured_vars_copy[i] = try self.arena.allocator().dupe(u8, v);
        }

        // Copy forward ref vars
        var forward_ref_copy = try self.allocator.alloc([]const u8, forward_ref_vars.items.len);
        for (forward_ref_vars.items, 0..) |v, i| {
            forward_ref_copy[i] = try self.arena.allocator().dupe(u8, v);
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

        // Use TypedClosure when possible to reduce monomorphization:
        // - 0-param closures: always use TypedClosure0 (no argument type issues)
        // - With typed params: use TypedClosure1-7 with explicit types
        // - Otherwise: fall back to AnyClosure (anytype params)
        if (total_params == 0 or (use_typed_closure and total_params <= 7)) {
            // Emit TypedClosure with explicit type parameters
            try self.emitFmt(
                "const {s} = runtime.TypedClosure{d}({s}, ",
                .{ closure_var_name, total_params, capture_type_name },
            );
            // Emit argument types
            for (param_types) |pt| {
                try self.emitFmt("{s}, ", .{pt});
            }
            // Emit return type and function
            try self.emitFmt(
                "{s}, {s}.{s}){{ .captures = .{{",
                .{ return_type_str, closure_impl_name, impl_fn_name },
            );
        } else {
            // Fall back to AnyClosure (anytype params)
            if (total_params == 0) {
                try self.emitFmt(
                    "const {s} = runtime.AnyClosure0({s}, ",
                    .{ closure_var_name, capture_type_name },
                );
            } else if (total_params == 1) {
                try self.emitFmt(
                    "const {s} = runtime.AnyClosure1({s}, ",
                    .{ closure_var_name, capture_type_name },
                );
            } else if (total_params == 2) {
                try self.emitFmt(
                    "const {s} = runtime.AnyClosure2({s}, ",
                    .{ closure_var_name, capture_type_name },
                );
            } else if (total_params == 3) {
                try self.emitFmt(
                    "const {s} = runtime.AnyClosure3({s}, ",
                    .{ closure_var_name, capture_type_name },
                );
            } else if (total_params == 4) {
                try self.emitFmt(
                    "const {s} = runtime.AnyClosure4({s}, ",
                    .{ closure_var_name, capture_type_name },
                );
            } else if (total_params == 5) {
                try self.emitFmt(
                    "const {s} = runtime.AnyClosure5({s}, ",
                    .{ closure_var_name, capture_type_name },
                );
            } else if (total_params == 6) {
                try self.emitFmt(
                    "const {s} = runtime.AnyClosure6({s}, ",
                    .{ closure_var_name, capture_type_name },
                );
            } else if (total_params == 7) {
                try self.emitFmt(
                    "const {s} = runtime.AnyClosure7({s}, ",
                    .{ closure_var_name, capture_type_name },
                );
            } else {
                // For functions with more than 7 params, fall back to AnyClosure7
                // This is rare in practice; most closures have few parameters
                try self.emitFmt(
                    "const {s} = runtime.AnyClosure7({s}, ",
                    .{ closure_var_name, capture_type_name },
                );
            }

            try self.emitFmt(
                "{s}.{s}){{ .captures = .{{",
                .{ closure_impl_name, impl_fn_name },
            );
        }

        // Initialize captures - use renamed variable names from outer scope saved earlier
        // For mutated captures, use & to take pointer
        for (captured_vars, 0..) |var_name, i| {
            if (i > 0) try self.emit(", ");
            // Check saved outer renames first (for params that were renamed in outer function),
            // then fall back to current var_renames, then the original name
            const actual_name = outer_capture_renames.get(var_name) orelse
                self.var_renames.get(var_name) orelse var_name;

            // Initialize capture - use & for mutated captures, value for non-mutated
            // For closures, the type is @TypeOf(actual_var) so we pass directly
            if (mutated_captures.contains(var_name)) {
                try self.emitFmt(" .{s} = &{s}", .{ var_name, actual_name });
            } else {
                try self.emitFmt(" .{s} = {s}", .{ var_name, actual_name });
            }
        }
        try self.emit(" } };\n");

        try self.emitIndent();

        // Check if this function was hoisted as a DynamicClosure (from if/else branch)
        // In this case, we assign to the existing var instead of declaring a new one
        const is_hoisted_closure = self.hoisted_dynamic_closures.contains(func.name);

        if (is_hoisted_closure) {
            // Assign to hoisted DynamicClosure variable (no var/const declaration)
            try self.emitIdent(alias_name);
            try self.emitFmt(" = {s};\n", .{closure_var_name});
        } else {
            // Check if function name will be reassigned (e.g., bar = decorator(bar))
            // If so, use var instead of const to allow the reassignment
            // NOTE: We check saved_func_local_mutations (outer function's mutations) because
            // at this point self.func_local_mutations has been replaced with the nested function's map
            var outer_key_buf: [256]u8 = undefined;
            const outer_key = std.fmt.bufPrint(&outer_key_buf, "{s}:0", .{func.name}) catch func.name;
            const is_func_mutated = saved_func_local_mutations.contains(func.name) or
                saved_func_local_mutations.contains(outer_key);
            try self.emit(if (is_func_mutated) "var " else "const ");
            try self.emitIdent(alias_name);
            try self.emitFmt(" = {s};\n", .{closure_var_name});
        }

        // If we renamed the function, also add a var_rename so calls use the prefixed name
        if (shadows_import or is_redefinition) {
            const alias_copy = try self.arena.allocator().dupe(u8, alias_name);
            try self.var_renames.put(func.name, alias_copy);
        }

        // Declare the alias name (using unique name if redefinition) - skip if hoisted
        if (!is_hoisted_closure) {
            try self.declareVar(alias_name);

            // Suppress unused local constant warning for the alias
            try self.emitIndent();
            try self.emit("_ = &");
            try self.emitIdent(alias_name);
            try self.emit(";\n");
        }

        // Mark this variable as a closure so calls use .call() syntax
        const func_name_copy = try self.arena.allocator().dupe(u8, func.name);
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
        try self.emitFmt(
            "const {s} = runtime.AnyClosure0({s}, ",
            .{ info.closure_var_name, info.capture_type_name },
        );
    } else if (info.total_params == 1) {
        try self.emitFmt(
            "const {s} = runtime.AnyClosure1({s}, ",
            .{ info.closure_var_name, info.capture_type_name },
        );
    } else if (info.total_params == 2) {
        try self.emitFmt(
            "const {s} = runtime.AnyClosure2({s}, ",
            .{ info.closure_var_name, info.capture_type_name },
        );
    } else if (info.total_params == 3) {
        try self.emitFmt(
            "const {s} = runtime.AnyClosure3({s}, ",
            .{ info.closure_var_name, info.capture_type_name },
        );
    } else if (info.total_params == 4) {
        try self.emitFmt(
            "const {s} = runtime.AnyClosure4({s}, ",
            .{ info.closure_var_name, info.capture_type_name },
        );
    } else if (info.total_params == 5) {
        try self.emitFmt(
            "const {s} = runtime.AnyClosure5({s}, ",
            .{ info.closure_var_name, info.capture_type_name },
        );
    } else if (info.total_params == 6) {
        try self.emitFmt(
            "const {s} = runtime.AnyClosure6({s}, ",
            .{ info.closure_var_name, info.capture_type_name },
        );
    } else {
        // For 7+ params, use AnyClosure7
        try self.emitFmt(
            "const {s} = runtime.AnyClosure7({s}, ",
            .{ info.closure_var_name, info.capture_type_name },
        );
    }

    try self.emitFmt(
        "{s}.{s}){{ .captures = .{{",
        .{ info.closure_impl_name, info.impl_fn_name },
    );

    // Initialize captures
    for (info.captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        // For captured variables, use the ORIGINAL name, not the renamed one.
        // Captured variables exist in the outer scope under their original names.
        // The var_renames may contain shadow renames from inner scopes, which
        // shouldn't apply to capture initialization.
        try self.emitFmt(" .{s} = {s}", .{ var_name, var_name });
    }
    try self.emit(" } };\n");

    // Create alias with original function name
    try self.emitIndent();
    try self.emit("const ");
    try self.emitIdent(info.alias_name);
    try self.emitFmt(" = {s};\n", .{info.closure_var_name});

    // Declare the alias name
    try self.declareVar(info.alias_name);

    // Mark this variable as a closure so calls use .call() syntax
    const func_name_copy = try self.arena.allocator().dupe(u8, info.func_name);
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

    // Save ID before any nested generation
    const saved_id = self.name_gen.nextId();

    // Identify captured vars that are mutated in the function body (including nonlocal)
    var mutated_captures = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer mutated_captures.deinit();
    for (captured_vars) |var_name| {
        if (var_tracking.isVarMutatedInStmts(var_name, func.body) or
            var_tracking.isNonlocalVar(var_name, func.body))
        {
            try mutated_captures.put(var_name, {});
        }
    }

    // Generate comptime closure using runtime.Closure1 helper
    const closure_impl_name = try std.fmt.allocPrint(
        self.allocator,
        "__m{d}_ClosureImpl_{s}",
        .{ saved_id, func.name },
    );
    defer self.allocator.free(closure_impl_name);

    // Generate the capture struct type (must be defined once and reused)
    const capture_type_name = try std.fmt.allocPrint(
        self.allocator,
        "__m{d}_CaptureType_{s}",
        .{ saved_id, func.name },
    );
    defer self.allocator.free(capture_type_name);

    try self.emitIndent();
    try self.emitFmt("const {s} = struct {{", .{capture_type_name});
    for (captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        try self.emit(" ");
        try self.emitIdent(var_name);
        // Emit the type for this captured variable
        try emitCapturedVarType(self, var_name, mutated_captures.contains(var_name));
    }
    try self.emit(" };\n");

    // Generate the inner function that takes (captures, args...)
    try self.emitIndent();
    try self.emitFmt("const {s} = struct {{\n", .{closure_impl_name});
    self.indent();

    // Generate static function that closure will call
    const impl_fn_name = try std.fmt.allocPrint(
        self.allocator,
        "__m{d}_call_{s}",
        .{ saved_id, func.name },
    );
    defer self.allocator.free(impl_fn_name);

    // Use unique capture param name to avoid shadowing in nested closures
    const capture_param_name = try std.fmt.allocPrint(
        self.allocator,
        "__m{d}_cap_{s}",
        .{ saved_id, func.name },
    );
    defer self.allocator.free(capture_param_name);

    // Check if captured vars are actually used in the function body
    const captures_used = var_tracking.areCapturedVarsUsed(captured_vars, func.body);

    try self.emitIndent();
    if (captures_used) {
        try self.emitFmt("fn {s}({s}: {s}", .{ impl_fn_name, capture_param_name, capture_type_name });
    } else {
        // Captures not used, use _ to avoid unused parameter error
        try self.emitFmt("fn {s}(_: {s}", .{ impl_fn_name, capture_type_name });
    }

    // Generate renamed parameters to avoid shadowing outer scope (duplicate of above section)
    var param_renames = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
    defer param_renames.deinit();

    for (func.args) |arg| {
        // Check if param is used in body - if not, use _ to discard (Zig 0.15 requirement)
        const is_used = var_tracking.isParamUsedInStmts(arg.name, func.body);
        if (is_used) {
            // Create a unique parameter name to avoid shadowing: __p_name_id
            const unique_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__m{d}_p_{s}",
                .{ saved_id, arg.name },
            );
            try param_renames.put(arg.name, unique_param_name);
            try self.emitFmt(", {s}: anytype", .{unique_param_name});
        } else {
            try self.emit(", _: anytype");
        }
    }
    // Determine return type:
    // 1. Use explicit return type annotation if available (-> int, -> float, etc.)
    // 2. Otherwise, analyze body
    if (func.return_type) |ret_type| {
        // Map Python type annotations to Zig types
        const zig_type = if (std.mem.eql(u8, ret_type, "int"))
            "i64"
        else if (std.mem.eql(u8, ret_type, "float"))
            "f64"
        else if (std.mem.eql(u8, ret_type, "str"))
            "[]const u8"
        else if (std.mem.eql(u8, ret_type, "bool"))
            "bool"
        else if (std.mem.eql(u8, ret_type, "None"))
            "void"
        else
            // Unknown annotation - fall back to PyValue
            "runtime.PyValue";

        if (std.mem.eql(u8, zig_type, "void")) {
            if (var_tracking.canProduceErrors(func.body)) {
                try self.emit(") anyerror!void {\n");
            } else {
                try self.emit(") void {\n");
            }
        } else {
            try self.emitFmt(") anyerror!{s} {{\n", .{zig_type});
        }
    } else if (var_tracking.hasReturnWithValue(func.body)) {
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

    // Track the base scope level for this nested function
    const saved_nested_base_scope2 = self.nested_function_base_scope;
    self.nested_function_base_scope = self.symbol_table.currentScopeLevel();
    defer self.nested_function_base_scope = saved_nested_base_scope2;

    // Save and reset control_flow_terminated - nested function has its own control flow
    const saved_control_flow_terminated2 = self.control_flow_terminated;
    self.control_flow_terminated = false;
    defer self.control_flow_terminated = saved_control_flow_terminated2;

    // Add discard for capture param to avoid unused parameter warnings
    if (captures_used) {
        try self.emitIndent();
        try self.emitFmt("_ = &{s};\n", .{capture_param_name});
    }

    // Create mutable local copies for parameters that are reassigned in body
    for (func.args) |arg| {
        if (param_renames.get(arg.name)) |renamed| {
            if (var_tracking.isParamReassignedInStmts(arg.name, func.body)) {
                // Create mutable copy using NameGen for consistent naming
                const local_name = try self.name_gen.mutable(arg.name);
                try self.emitIndent();
                try self.emitFmt("var {s} = {s};\n", .{ local_name, renamed });
                // Emit discard to suppress "unused local variable" warning
                try self.emitIndent();
                try self.emitFmt("_ = &{s};\n", .{local_name});
                try param_renames.put(arg.name, local_name);

                // Register the mutable copy's type in scoped type map
                // This is CRITICAL for aug_assign to detect the correct type and use native operations
                if (self.type_inferrer.getScopedVar(arg.name)) |param_type| {
                    try self.type_inferrer.putScopedVar(local_name, param_type);
                } else if (self.type_inferrer.var_types.get(arg.name)) |param_type| {
                    try self.type_inferrer.putScopedVar(local_name, param_type);
                }
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

    // Save and clear func_local_vars - nested function has its own local variables
    const saved_func_local_vars2 = self.func_local_vars;
    self.func_local_vars = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.func_local_vars.deinit();
        self.func_local_vars = saved_func_local_vars2;
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
    // For mutated/nonlocal captures, add .* to dereference the pointer
    var capture_renames = std.ArrayList([]const u8){};
    defer capture_renames.deinit(self.allocator);

    for (captured_vars) |var_name| {
        const rename = if (mutated_captures.contains(var_name))
            // Mutated/nonlocal captures are pointers - need dereference
            try std.fmt.allocPrint(
                self.allocator,
                "{s}.{s}.*",
                .{ capture_param_name, var_name },
            )
        else
            try std.fmt.allocPrint(
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
        // IMPORTANT: Must dupe renamed value because param_renames is deferred deinit
        if (param_renames.get(arg.name)) |renamed| {
            const renamed_copy = try self.arena.allocator().dupe(u8, renamed);
            try self.var_renames.put(arg.name, renamed_copy);
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
        "__m{d}_closure_{s}",
        .{ saved_id, func.name },
    );
    defer self.allocator.free(closure_var_name);

    try self.emitIndent();
    if (func.args.len == 0) {
        try self.emitFmt(
            "const {s} = runtime.Closure0({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else if (func.args.len == 1) {
        try self.emitFmt(
            "const {s} = runtime.Closure1({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else if (func.args.len == 2) {
        try self.emitFmt(
            "const {s} = runtime.Closure2({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else if (func.args.len == 3) {
        try self.emitFmt(
            "const {s} = runtime.Closure3({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else {
        try self.emitFmt(
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
        "__m{d}_call_{s}",
        .{ saved_id, func.name },
    );
    defer self.allocator.free(impl_fn_ref);

    try self.emitFmt(
        "{s}.{s}){{ .captures = .{{",
        .{ closure_impl_name, impl_fn_ref },
    );

    // Initialize captures - reference outer captured vars through outer capture struct
    // or use renamed variable names if applicable
    // For mutated/nonlocal captures, use & to take pointer
    for (captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        const is_mutated = mutated_captures.contains(var_name);
        // Check if this var is from outer closure's captures
        var is_outer_capture = false;
        for (outer_captured_vars) |outer_var| {
            if (std.mem.eql(u8, var_name, outer_var)) {
                is_outer_capture = true;
                break;
            }
        }
        if (is_outer_capture) {
            if (is_mutated) {
                try self.emitFmt(" .{s} = &{s}.{s}", .{ var_name, outer_capture_param, var_name });
            } else {
                try self.emitFmt(" .{s} = {s}.{s}", .{ var_name, outer_capture_param, var_name });
            }
        } else {
            // For captured variables, use the ORIGINAL name.
            // Captured variables exist in the outer scope under their original names.
            if (is_mutated) {
                try self.emitFmt(" .{s} = &{s}", .{ var_name, var_name });
            } else {
                try self.emitFmt(" .{s} = {s}", .{ var_name, var_name });
            }
        }
    }
    try self.emit(" } };\n");

    // Create alias with original function name
    // Check if func.name would shadow a module-level import
    const shadows_import2 = self.imported_modules.contains(func.name);

    // Check if func.name is already declared in current scope (redefinition)
    // Python allows redefining function names: def f(): ... def f(): ... (second shadows first)
    const is_redefinition2 = self.isDeclared(func.name);

    // If shadowing an import or redefinition, use NameGen for consistent unique naming
    const alias_name2 = if (shadows_import2 or is_redefinition2)
        try self.name_gen.closure(func.name)
    else
        try self.arena.allocator().dupe(u8, func.name);
    defer self.allocator.free(alias_name2);

    try self.emitIndent();
    try self.emit("const ");
    try self.emitIdent(alias_name2);
    try self.emitFmt(" = {s};\n", .{closure_var_name});

    // If we renamed the function, also add a var_rename so calls use the prefixed name
    if (shadows_import2 or is_redefinition2) {
        const alias_copy2 = try self.arena.allocator().dupe(u8, alias_name2);
        try self.var_renames.put(func.name, alias_copy2);
    }

    // Declare the alias name (using unique name if redefinition)
    try self.declareVar(alias_name2);

    // Mark this variable as a closure so calls use .call() syntax
    const func_name_copy = try self.arena.allocator().dupe(u8, func.name);
    try self.closure_vars.put(func_name_copy, {});
}
