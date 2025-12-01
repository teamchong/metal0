/// Function and method body generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../../main.zig").CodegenError;
const CodeBuilder = @import("../../../../code_builder.zig").CodeBuilder;
const allocator_analyzer = @import("../../allocator_analyzer.zig");
const zig_keywords = @import("zig_keywords");

const mutation_analysis = @import("mutation_analysis.zig");
const usage_analysis = @import("usage_analysis.zig");
const nested_captures = @import("nested_captures.zig");

/// Info about a type check at the start of a function
pub const TypeCheckInfo = struct {
    param_name: []const u8,
    check_type: []const u8,
};

/// Detect type-check-raise pattern at the start of a function body
/// Pattern: if not isint(param): raise TypeError  OR  if not isinstance(param, type): raise TypeError
/// Returns the checks found and the index of the first non-type-check statement
pub fn detectTypeCheckRaisePatterns(body: []ast.Node, anytype_params: anytype, allocator: std.mem.Allocator) !struct { checks: []TypeCheckInfo, start_idx: usize } {
    var checks = std.ArrayList(TypeCheckInfo){};
    var idx: usize = 0;

    while (idx < body.len) : (idx += 1) {
        const stmt = body[idx];
        // Skip docstrings (expr_stmt containing a string constant)
        if (stmt == .expr_stmt) {
            const expr = stmt.expr_stmt.value.*;
            if (expr == .constant) {
                const val = expr.constant.value;
                if (val == .string) {
                    // It's a docstring - skip it
                    continue;
                }
            }
        }
        if (stmt != .if_stmt) break;

        const if_stmt = stmt.if_stmt;

        // Body must be a single raise TypeError
        std.debug.print("DEBUG: if_stmt.body.len = {}\n", .{if_stmt.body.len});
        if (if_stmt.body.len != 1) break;
        std.debug.print("DEBUG: if_stmt.body[0] tag = {s}\n", .{@tagName(if_stmt.body[0])});
        if (if_stmt.body[0] != .raise_stmt) break;
        const raise = if_stmt.body[0].raise_stmt;
        std.debug.print("DEBUG: raise.exc is null = {}\n", .{raise.exc == null});
        if (raise.exc == null) break;

        // Check the exception is TypeError
        std.debug.print("DEBUG: raise.exc.?.* tag = {s}\n", .{@tagName(raise.exc.?.*)});
        const is_type_error = blk: {
            if (raise.exc.?.* == .call) {
                const call = raise.exc.?.call;
                std.debug.print("DEBUG: call.func.* tag = {s}\n", .{@tagName(call.func.*)});
                if (call.func.* == .name) {
                    std.debug.print("DEBUG: call.func.name.id = {s}\n", .{call.func.name.id});
                    break :blk std.mem.eql(u8, call.func.name.id, "TypeError");
                }
            } else if (raise.exc.?.* == .name) {
                break :blk std.mem.eql(u8, raise.exc.?.name.id, "TypeError");
            }
            break :blk false;
        };
        std.debug.print("DEBUG: is_type_error = {}\n", .{is_type_error});
        if (!is_type_error) break;

        // Condition must be: not isint(x) or not isinstance(x, type)
        if (if_stmt.condition.* != .unaryop) break;
        const unary = if_stmt.condition.unaryop;
        if (unary.op != .Not) break;
        if (unary.operand.* != .call) break;

        const call = unary.operand.call;
        if (call.func.* != .name) break;
        const func_name = call.func.name.id;

        // Check for isint(x) pattern
        if (std.mem.eql(u8, func_name, "isint")) {
            if (call.args.len >= 1 and call.args[0] == .name) {
                const arg_name = call.args[0].name.id;
                if (anytype_params.contains(arg_name)) {
                    try checks.append(allocator, TypeCheckInfo{ .param_name = arg_name, .check_type = "int" });
                    continue;
                }
            }
        }
        // Check for isinstance(x, int) pattern
        else if (std.mem.eql(u8, func_name, "isinstance")) {
            if (call.args.len >= 2 and call.args[0] == .name and call.args[1] == .name) {
                const arg_name = call.args[0].name.id;
                const type_name = call.args[1].name.id;
                if (anytype_params.contains(arg_name)) {
                    try checks.append(allocator, TypeCheckInfo{ .param_name = arg_name, .check_type = type_name });
                    continue;
                }
            }
        }
        break;
    }

    return .{ .checks = checks.items, .start_idx = idx };
}

/// Use state machine async (true non-blocking) vs thread-based (blocking)
/// State machines allow 1000x+ concurrent I/O operations (like Go/Rust)
const USE_STATE_MACHINE_ASYNC = true;

/// Generate function body with scope management
pub fn genFunctionBody(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    _: bool, // has_allocator_param - unused, handled in signature.zig
    _: bool, // actually_uses_allocator - unused, handled in signature.zig
) CodegenError!void {
    // For async functions, generate task spawn wrapper
    if (func.is_async) {
        try genAsyncFunctionBody(self, func);
        return;
    }

    // Analyze function body for mutated variables BEFORE generating code
    // This populates func_local_mutations so emitVarDeclaration can make correct var/const decisions
    self.func_local_mutations.clearRetainingCapacity();
    self.func_local_aug_assigns.clearRetainingCapacity();
    self.hoisted_vars.clearRetainingCapacity();
    self.nested_class_instances.clearRetainingCapacity();
    self.class_instance_aliases.clearRetainingCapacity();
    // Clear variable renames from previous functions to avoid cross-function pollution
    // (e.g., gcd's a->a__mut rename shouldn't affect test_constructor's local var 'a')
    self.var_renames.clearRetainingCapacity();
    try mutation_analysis.analyzeFunctionLocalMutations(self, func);

    // Analyze function body for used variables (prevents false "unused" detection)
    try usage_analysis.analyzeFunctionLocalUses(self, func);

    // Track local variables and analyze nested class captures for closure support
    self.func_local_vars.clearRetainingCapacity();
    self.nested_class_captures.clearRetainingCapacity();
    try nested_captures.analyzeNestedClassCaptures(self, func);

    self.indent();

    // Push new scope for function body
    try self.pushScope();

    // Note: Unused parameters are handled in signature.zig with "_" prefix
    // (e.g., unused param "op" becomes "_op" in signature)
    // No need to emit "_ = param;" here since "_" prefix already suppresses the warning

    // Generate default parameter initialization (before declaring them in scope)
    // When default value references the same name as the parameter (e.g., def foo(x=x):),
    // we need to use a different local name to avoid shadowing the module-level variable
    for (func.args) |arg| {
        if (arg.default) |default_expr| {
            const expressions = @import("../../../../expressions.zig");

            // Check if default expression is a name that matches the parameter name
            // This would cause shadowing in Zig, so we rename the local variable
            const needs_rename = if (default_expr.* == .name)
                std.mem.eql(u8, default_expr.name.id, arg.name)
            else
                false;

            if (needs_rename) {
                // Rename local variable to avoid shadowing module-level variable
                // Use __local_X and add to var_renames so all references use the new name
                const renamed = try std.fmt.allocPrint(self.allocator, "__local_{s}", .{arg.name});
                try self.var_renames.put(arg.name, renamed);

                try self.emitIndent();
                try self.emit("const ");
                try self.emit(renamed);
                try self.emit(" = ");
                try self.emit(arg.name);
                try self.emit("_param orelse ");
                // Reference the original module-level variable (arg.name), not the renamed one
                try self.emit(arg.name);
                try self.emit(";\n");
            } else {
                try self.emitIndent();
                try self.emit("const ");
                try self.emit(arg.name);
                try self.emit(" = ");
                try self.emit(arg.name);
                try self.emit("_param orelse ");
                try expressions.genExpr(self, default_expr.*);
                try self.emit(";\n");
            }
        }
    }

    // Declare function parameters in the scope so closures can capture them
    // Also create mutable copies for parameters that are reassigned in the body
    const var_tracking = @import("../../nested/var_tracking.zig");
    for (func.args) |arg| {
        // Skip parameters with defaults - they're handled above
        if (arg.default != null) continue;

        try self.declareVar(arg.name);

        // Check if this parameter is reassigned in the function body
        if (var_tracking.isParamReassignedInStmts(arg.name, func.body)) {
            // Create a mutable copy of the parameter
            try self.emitIndent();
            try self.emit("var ");
            try self.emit(arg.name);
            try self.emit("__mut = ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
            try self.emit(";\n");
            // Rename all references to use the mutable copy
            try self.var_renames.put(arg.name, try std.fmt.allocPrint(self.allocator, "{s}__mut", .{arg.name}));
        }
    }

    // NOTE: Forward-referenced captured variables (class captures variable before it's declared)
    // are a complex edge case that requires runtime type erasure. For now, these patterns
    // may fail to compile. See test_equal_operator_modifying_operand for an example.

    // Detect type-check-raise patterns at the start of the function body for anytype params
    // These need comptime branching to prevent invalid type instantiations from being analyzed
    const type_checks = try detectTypeCheckRaisePatterns(func.body, self.anytype_params, self.allocator);

    if (type_checks.checks.len > 0) {
        // Generate comptime type guard: if (comptime istype(@TypeOf(p1), "int") and istype(@TypeOf(p2), "int")) {
        try self.emitIndent();
        try self.emit("if (comptime ");
        for (type_checks.checks, 0..) |check, i| {
            if (i > 0) try self.emit(" and ");
            try self.emit("runtime.istype(@TypeOf(");
            try self.emit(check.param_name);
            try self.emit("), \"");
            try self.emit(check.check_type);
            try self.emit("\")");
        }
        try self.emit(") {\n");
        self.indent();

        // Generate the rest of the function body (after the type checks)
        for (func.body[type_checks.start_idx..]) |stmt| {
            try self.generateStmt(stmt);
        }

        // Close the comptime if block with else returning error.TypeError
        self.dedent();
        try self.emitIndent();
        try self.emit("} else {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("return error.TypeError;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    } else {
        // No type-check patterns - generate body normally
        for (func.body) |stmt| {
            try self.generateStmt(stmt);
        }
    }

    // NOTE: Nested class unused suppression (e.g., _ = &ClassName;) is now handled
    // immediately after each class definition in generators.zig genClassDef().
    // This is necessary because classes inside if/for/while blocks are out of scope here.

    // Pop scope when exiting function
    self.popScope();

    // Clear function-local state after exiting function
    self.func_local_mutations.clearRetainingCapacity();
    self.func_local_aug_assigns.clearRetainingCapacity();
    self.func_local_vars.clearRetainingCapacity();
    self.forward_declared_vars.clearRetainingCapacity();
    // Clear nested_class_captures (free the slices first)
    var cap_iter = self.nested_class_captures.iterator();
    while (cap_iter.next()) |entry| {
        self.allocator.free(entry.value_ptr.*);
    }
    self.nested_class_captures.clearRetainingCapacity();

    // Clear nested class tracking (names and bases) after exiting function
    // This prevents class name collisions between different functions
    // BUT: Preserve if current class is nested or inside a nested class (class_nesting_depth > 1)
    const current_class_is_nested_fn = if (self.current_class_name) |ccn| self.nested_class_names.contains(ccn) else false;
    if (!current_class_is_nested_fn and self.class_nesting_depth <= 1) {
        self.nested_class_names.clearRetainingCapacity();
        self.nested_class_bases.clearRetainingCapacity();
    }

    var builder = CodeBuilder.init(self);
    _ = try builder.endBlock();
}

/// Generate async function body (implementation function for green thread scheduler)
pub fn genAsyncFunctionBody(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
) CodegenError!void {
    // State machine approach generates everything in signature phase
    if (USE_STATE_MACHINE_ASYNC) {
        return; // Body already generated by state_machine.genAsyncStateMachine
    }

    // Fallback: thread-based approach (blocking)
    // Analyze function body for mutated variables BEFORE generating code
    // This populates func_local_mutations so emitVarDeclaration can make correct var/const decisions
    self.func_local_mutations.clearRetainingCapacity();
    self.func_local_aug_assigns.clearRetainingCapacity();
    self.hoisted_vars.clearRetainingCapacity();
    self.nested_class_instances.clearRetainingCapacity();
    self.class_instance_aliases.clearRetainingCapacity();
    try mutation_analysis.analyzeFunctionLocalMutations(self, func);

    // Analyze function body for used variables (prevents false "unused" detection)
    try usage_analysis.analyzeFunctionLocalUses(self, func);

    self.indent();

    // Push new scope for function body
    try self.pushScope();

    // Async impl functions use __global_allocator directly in generated code (e.g., createTask).
    // The `allocator` alias is provided for consistency but often unused.
    // Always suppress warning since analysis can't distinguish direct vs aliased use.
    try self.emitIndent();
    try self.emit("const allocator = __global_allocator; _ = allocator;\n");

    // Declare function parameters in the scope
    for (func.args) |arg| {
        try self.declareVar(arg.name);
    }

    // Generate function body directly (no task wrapping needed)
    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting function
    self.popScope();

    var builder = CodeBuilder.init(self);
    _ = try builder.endBlock();
}

/// Generate method body with self-usage detection
pub fn genMethodBody(self: *NativeCodegen, method: ast.Node.FunctionDef) CodegenError!void {
    // genMethodBodyWithAllocatorInfo with automatic detection
    const needs_allocator = allocator_analyzer.functionNeedsAllocator(method);
    const actually_uses = allocator_analyzer.functionActuallyUsesAllocatorParam(method);
    try genMethodBodyWithAllocatorInfo(self, method, needs_allocator, actually_uses);
}

/// Check if method body contains a super() call
pub fn hasSuperCall(stmts: []ast.Node) bool {
    for (stmts) |stmt| {
        if (stmtHasSuperCall(stmt)) return true;
    }
    return false;
}

fn stmtHasSuperCall(stmt: ast.Node) bool {
    return switch (stmt) {
        .expr_stmt => |e| exprHasSuperCall(e.value.*),
        .assign => |a| exprHasSuperCall(a.value.*),
        .return_stmt => |r| if (r.value) |v| exprHasSuperCall(v.*) else false,
        .if_stmt => |i| hasSuperCall(i.body) or hasSuperCall(i.else_body),
        .while_stmt => |w| hasSuperCall(w.body),
        .for_stmt => |f| hasSuperCall(f.body),
        .try_stmt => |t| blk: {
            if (hasSuperCall(t.body)) break :blk true;
            for (t.handlers) |h| {
                if (hasSuperCall(h.body)) break :blk true;
            }
            break :blk hasSuperCall(t.finalbody);
        },
        else => false,
    };
}

fn exprHasSuperCall(expr: ast.Node) bool {
    return switch (expr) {
        .call => |c| blk: {
            // Check if this is super() or super().method()
            if (c.func.* == .name and std.mem.eql(u8, c.func.name.id, "super")) {
                break :blk true;
            }
            // Check if func is attr access on super() call: super().method()
            if (c.func.* == .attribute) {
                const attr = c.func.attribute;
                if (attr.value.* == .call) {
                    const inner_call = attr.value.call;
                    if (inner_call.func.* == .name and std.mem.eql(u8, inner_call.func.name.id, "super")) {
                        break :blk true;
                    }
                }
            }
            // Check arguments
            for (c.args) |arg| {
                if (exprHasSuperCall(arg)) break :blk true;
            }
            break :blk false;
        },
        .binop => |b| exprHasSuperCall(b.left.*) or exprHasSuperCall(b.right.*),
        .attribute => |a| exprHasSuperCall(a.value.*),
        else => false,
    };
}

/// Generate method body with explicit allocator info
pub fn genMethodBodyWithAllocatorInfo(
    self: *NativeCodegen,
    method: ast.Node.FunctionDef,
    _: bool, // has_allocator_param - unused, handled in signature.zig
    _: bool, // actually_uses_allocator - unused, handled in signature.zig
) CodegenError!void {
    return genMethodBodyWithAllocatorInfoAndContext(self, method, &[_][]const u8{});
}

/// Generate method body with extra context for inherited methods
/// extra_class_names: class names to add to nested_class_names (for inherited method constructor calls)
pub fn genMethodBodyWithContext(
    self: *NativeCodegen,
    method: ast.Node.FunctionDef,
    extra_class_names: []const []const u8,
) CodegenError!void {
    return genMethodBodyWithAllocatorInfoAndContext(self, method, extra_class_names);
}

fn genMethodBodyWithAllocatorInfoAndContext(
    self: *NativeCodegen,
    method: ast.Node.FunctionDef,
    extra_class_names: []const []const u8,
) CodegenError!void {
    // Track whether we're inside a method with 'self' parameter.
    // This is used by generators.zig to know if a nested class should use __self.
    // The first parameter of a class method is always self (regardless of name like test_self, cls, etc.)
    const has_self = method.args.len > 0;
    const was_inside_method = self.inside_method_with_self;
    if (has_self) self.inside_method_with_self = true;
    defer self.inside_method_with_self = was_inside_method;

    // Analyze method body for mutated variables BEFORE generating code
    // This populates func_local_mutations so emitVarDeclaration can make correct var/const decisions
    self.func_local_mutations.clearRetainingCapacity();
    self.func_local_aug_assigns.clearRetainingCapacity();
    self.hoisted_vars.clearRetainingCapacity();
    self.nested_class_instances.clearRetainingCapacity();
    self.class_instance_aliases.clearRetainingCapacity();
    try mutation_analysis.analyzeFunctionLocalMutations(self, method);

    // Analyze method body for used variables (prevents false "unused" detection)
    try usage_analysis.analyzeFunctionLocalUses(self, method);

    // Track local variables and analyze nested class captures for closure support
    // Clear all maps for each method to avoid pollution from sibling methods
    // (e.g., class A in test_sane_len should not affect class A in test_blocked)
    // BUT: Preserve nested_class_names/bases when current class is nested (in nested_class_names)
    // or when deeply nested (class_nesting_depth > 1)
    self.func_local_vars.clearRetainingCapacity();
    self.nested_class_captures.clearRetainingCapacity();
    const current_class_is_nested = if (self.current_class_name) |ccn| self.nested_class_names.contains(ccn) else false;
    if (!current_class_is_nested and self.class_nesting_depth <= 1) {
        self.nested_class_names.clearRetainingCapacity();
        self.nested_class_bases.clearRetainingCapacity();
    }
    try nested_captures.analyzeNestedClassCaptures(self, method);

    // Add extra class names (for inherited method bodies that call parent class constructors)
    for (extra_class_names) |name| {
        try self.nested_class_names.put(name, {});
    }

    self.indent();

    // Push new scope for method body (symbol table)
    try self.pushScope();

    // Enter named type inferrer scope to match analysis phase
    // Use "ClassName.method_name" for methods or "func_name" for standalone functions
    // This enables scoped variable type lookup during codegen
    var scope_name_buf: [256]u8 = undefined;
    const scope_name = if (self.current_class_name) |class_name|
        std.fmt.bufPrint(&scope_name_buf, "{s}.{s}", .{ class_name, method.name }) catch method.name
    else
        method.name;
    const old_type_scope = self.type_inferrer.enterScope(scope_name);
    defer self.type_inferrer.exitScope(old_type_scope);

    // Note: We removed the "_ = self;" emission for super() calls
    // This was causing "pointless discard of function parameter" errors when
    // self IS actually used in the method body beyond super() calls.
    // If self is truly unused, signature.zig should handle it with "_" prefix.

    // However, if the method uses type attributes (e.g., self.int_class), the generated
    // code uses @This().int_class which doesn't reference self, causing "unused parameter" error.
    // Detect this case and emit _ = self; to suppress the warning.
    // BUT: only emit _ = self; if the method ONLY uses type attributes and not regular self methods.
    // If the method uses BOTH type attributes AND regular self (e.g., self.check()), then self IS used.
    if (self.current_class_name) |class_name| {
        const uses_type_attrs = blk: {
            for (method.body) |stmt| {
                if (mutation_analysis.usesTypeAttribute(stmt, class_name, self.class_type_attrs)) {
                    break :blk true;
                }
            }
            break :blk false;
        };
        const uses_regular_self = blk2: {
            for (method.body) |stmt| {
                if (mutation_analysis.usesRegularSelf(stmt, class_name, self.class_type_attrs)) {
                    break :blk2 true;
                }
            }
            break :blk2 false;
        };
        // Only emit _ = self if we use type attrs but DON'T use regular self
        if (uses_type_attrs and !uses_regular_self) {
            try self.emitIndent();
            try self.emit("_ = self;\n");
        }
    }

    // Note: Unused allocator param is handled in signature.zig with "_:" prefix
    // No need to emit "_ = allocator;" here

    // Clear local variable types (new method scope)
    self.clearLocalVarTypes();

    // Track parameters that were renamed to avoid method shadowing (e.g., init -> init_arg)
    // We'll restore these when exiting the method
    var renamed_params = std.ArrayList([]const u8){};
    defer renamed_params.deinit(self.allocator);

    // Declare method parameters in the scope (skip 'self')
    // This prevents variable shadowing when reassigning parameters
    // Get the first param name for renaming if it's not "self"
    const first_param_name = if (method.args.len > 0) method.args[0].name else null;
    const needs_first_param_rename = if (first_param_name) |name|
        !std.mem.eql(u8, name, "self")
    else
        false;

    // If first param isn't named "self", rename it to "self" for proper Zig self reference
    // Use the appropriate self name based on nesting depth (self vs __self)
    if (needs_first_param_rename) {
        const target_self_name = if (self.method_nesting_depth > 0) "__self" else "self";
        try self.var_renames.put(first_param_name.?, target_self_name);
        try renamed_params.append(self.allocator, first_param_name.?);
    }

    var is_first = true;
    for (method.args) |arg| {
        // Skip the first parameter (self/cls/test_self/etc.)
        if (is_first) {
            is_first = false;
            continue;
        }
        // Check if this param would shadow a method name and needs renaming
        if (zig_keywords.wouldShadowMethod(arg.name)) {
            // Add rename mapping: original -> renamed
            const renamed = try std.fmt.allocPrint(self.allocator, "{s}_arg", .{arg.name});
            try self.var_renames.put(arg.name, renamed);
            try renamed_params.append(self.allocator, arg.name);
        }
        try self.declareVar(arg.name);
    }

    // NOTE: Forward-referenced captured variables (class captures variable before it's declared)
    // are a complex edge case that requires runtime type erasure. For now, these patterns
    // may fail to compile. See test_equal_operator_modifying_operand for an example.

    // Generate method body
    for (method.body) |method_stmt| {
        try self.generateStmt(method_stmt);
    }

    // NOTE: Nested class unused suppression (e.g., _ = &ClassName;) is now handled
    // immediately after each class definition in generators.zig genClassDef().
    // This is necessary because classes inside if/for/while blocks are out of scope here.

    // Remove parameter renames when exiting method scope
    for (renamed_params.items) |param_name| {
        if (self.var_renames.fetchSwapRemove(param_name)) |entry| {
            // Only free dynamically allocated strings (not static "self" or "__self")
            if (!std.mem.eql(u8, entry.value, "self") and !std.mem.eql(u8, entry.value, "__self")) {
                self.allocator.free(entry.value);
            }
        }
    }

    // Pop scope when exiting method
    self.popScope();

    // Clear function-local mutations and forward declarations after exiting method
    self.func_local_mutations.clearRetainingCapacity();
    self.func_local_aug_assigns.clearRetainingCapacity();
    self.forward_declared_vars.clearRetainingCapacity();

    // Clear nested class tracking (names and bases) after exiting method
    // This prevents class name collisions between different methods
    // (e.g., both test_foo and test_bar may have a nested class named BadIndex)
    // BUT: Preserve if current class is nested or inside a nested class (class_nesting_depth > 1)
    const current_class_is_nested_exit = if (self.current_class_name) |ccn| self.nested_class_names.contains(ccn) else false;
    if (!current_class_is_nested_exit and self.class_nesting_depth <= 1) {
        self.nested_class_names.clearRetainingCapacity();
        self.nested_class_bases.clearRetainingCapacity();
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}
