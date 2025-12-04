/// Function and method body generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../../main.zig").CodegenError;
const CodeBuilder = @import("../../../../code_builder.zig").CodeBuilder;
const function_traits = @import("function_traits");
const zig_keywords = @import("zig_keywords");
const hashmap_helper = @import("hashmap_helper");

const mutation_analysis = @import("mutation_analysis.zig");
const usage_analysis = @import("usage_analysis.zig");
const nested_captures = @import("nested_captures.zig");
const scope_analyzer = @import("../../scope_analyzer.zig");
const var_hoisting = @import("../../var_hoisting.zig");
const self_analyzer = @import("../../self_analyzer.zig");
const signature = @import("../signature.zig");

/// Info about a type check at the start of a function
pub const TypeCheckInfo = struct {
    param_name: []const u8,
    check_type: []const u8,
};

/// Info about type-changing pattern detection
pub const TypeDispatchInfo = struct {
    needs_dispatch: bool,
    param_name: []const u8, // The anytype parameter involved
    target_class: []const u8, // The class it converts to (e.g., "Rat")
    // Indices of relevant if-statements in the body
    type_check_indices: []usize,
};

/// Detect type-changing pattern in method body
/// Patterns supported:
/// 1. Type-changing assignment: if isint(param): param = ClassName(param)
/// 2. Polymorphic return: if isRat(other): return Rat(...); if isnum(other): return float(...)
fn detectTypeChangingPattern(self: *NativeCodegen, method: ast.Node.FunctionDef) !TypeDispatchInfo {
    const empty_result = TypeDispatchInfo{
        .needs_dispatch = false,
        .param_name = "",
        .target_class = "",
        .type_check_indices = &[_]usize{},
    };

    // Only process if we have anytype params
    if (self.anytype_params.count() == 0) return empty_result;

    // Detect polymorphic return pattern (different return types based on input type)
    var has_class_return = false;
    var has_float_return = false;
    var detected_param: ?[]const u8 = null;
    var detected_class: ?[]const u8 = null;

    for (method.body) |stmt| {
        if (stmt != .if_stmt) continue;
        const if_stmt = stmt.if_stmt;
        if (if_stmt.condition.* != .call) continue;
        const call = if_stmt.condition.call;
        if (call.func.* != .name) continue;
        const func_name = call.func.name.id;

        // Get param from the type check call
        if (call.args.len > 0 and call.args[0] == .name) {
            const arg_name = call.args[0].name.id;
            if (self.anytype_params.contains(arg_name)) {
                detected_param = arg_name;
            }
        }

        // Check for isint/isRat returning class instance or type-changing assignment
        if (std.mem.eql(u8, func_name, "isint") or std.mem.eql(u8, func_name, "isinstance")) {
            for (if_stmt.body) |body_stmt| {
                // Pattern 1: Type-changing assignment
                if (body_stmt == .assign) {
                    const assign = body_stmt.assign;
                    if (assign.targets.len > 0 and assign.targets[0] == .name) {
                        if (assign.value.* == .call and assign.value.call.func.* == .name) {
                            const class_name = assign.value.call.func.name.id;
                            if (class_name.len > 0 and std.ascii.isUpper(class_name[0])) {
                                detected_class = class_name;
                                has_class_return = true;
                            }
                        }
                    }
                }
                // Pattern 2: Direct class return
                if (body_stmt == .return_stmt) {
                    if (body_stmt.return_stmt.value) |val| {
                        if (val.* == .call and val.call.func.* == .name) {
                            const class_name = val.call.func.name.id;
                            if (class_name.len > 0 and std.ascii.isUpper(class_name[0])) {
                                detected_class = class_name;
                                has_class_return = true;
                            }
                        }
                    }
                }
            }
        } else if (std.mem.startsWith(u8, func_name, "is") and func_name.len > 2 and std.ascii.isUpper(func_name[2])) {
            // isRat, isClassName patterns - check for class return
            for (if_stmt.body) |body_stmt| {
                if (body_stmt == .return_stmt) {
                    if (body_stmt.return_stmt.value) |val| {
                        if (val.* == .call and val.call.func.* == .name) {
                            const class_name = val.call.func.name.id;
                            if (class_name.len > 0 and std.ascii.isUpper(class_name[0])) {
                                detected_class = class_name;
                                has_class_return = true;
                            }
                        }
                    }
                }
            }
        } else if (std.mem.eql(u8, func_name, "isnum")) {
            // Check for float return
            for (if_stmt.body) |body_stmt| {
                if (body_stmt == .return_stmt) {
                    if (body_stmt.return_stmt.value) |val| {
                        if (val.* == .binop or val.* == .call) {
                            has_float_return = true;
                        }
                    }
                }
            }
        }
    }

    // Trigger comptime dispatch for:
    // 1. Polymorphic pattern: both class return AND float return paths exist
    // 2. Type-changing assignment pattern: if isint(x): x = Class(x); ...uses x as class...
    if (has_class_return and detected_param != null and detected_class != null) {
        return TypeDispatchInfo{
            .needs_dispatch = true,
            .param_name = detected_param.?,
            .target_class = detected_class.?,
            .type_check_indices = &[_]usize{},
        };
    }

    return empty_result;
}

/// Generate comptime type dispatch for methods with type-changing patterns
/// Handles two patterns:
/// 1. Type-changing: if isint(x): x = Class(x); if isClass(x): use x
/// 2. Direct return: if isRat(x): return...; if isint(x): return...; if isnum(x): return...
fn generateComptimeTypeDispatch(
    self: *NativeCodegen,
    method: ast.Node.FunctionDef,
    info: TypeDispatchInfo,
) CodegenError!void {
    const param_name = info.param_name;
    const class_name = info.target_class;

    // Detect which pattern we're dealing with
    const has_type_changing_assign = hasTypeChangingAssignment(method, param_name);

    // Generate: const __T = @TypeOf(param);
    try self.emitIndent();
    try self.emit("const __T = @TypeOf(");
    try self.emit(param_name);
    try self.emit(");\n");

    // Generate int/comptime_int branch
    try self.emitIndent();
    try self.emit("if (comptime @typeInfo(__T) == .int or @typeInfo(__T) == .comptime_int) {\n");
    self.indent();

    // Push scope for int branch (each comptime branch needs independent variable tracking)
    try self.pushScope();

    if (has_type_changing_assign) {
        // Pattern 1: Convert param and use isClassName body
        try self.emitIndent();
        try self.emit("const ");
        try self.emit(param_name);
        try self.emit("_converted = try ");
        try self.emit(class_name);
        try self.emit(".init(__global_allocator, ");
        try self.emit(param_name);
        try self.emit(", 1);\n");

        // Find isClassName body and emit with substitution
        try self.var_renames.put(param_name, try std.fmt.allocPrint(self.allocator, "{s}_converted", .{param_name}));
        try generateBodyForTypeCheck(self, method, class_name, true);
        if (self.var_renames.fetchSwapRemove(param_name)) |entry| {
            self.allocator.free(entry.value);
        }
    } else {
        // Pattern 2: Directly emit isint body
        try generateBodyForTypeCheck(self, method, "int", false);
    }

    self.popScope();
    self.dedent();
    try self.emitIndent();
    try self.emit("} else if (comptime __T == ");
    try self.emit(class_name);
    try self.emit(" or __T == *");
    try self.emit(class_name);
    try self.emit(" or __T == *const ");
    try self.emit(class_name);
    try self.emit(") {\n");
    self.indent();

    // Push scope for class branch
    try self.pushScope();
    // Generate the class case body directly
    try generateBodyForTypeCheck(self, method, class_name, true);
    self.popScope();

    self.dedent();
    try self.emitIndent();
    try self.emit("} else if (comptime @typeInfo(__T) == .float or @typeInfo(__T) == .comptime_float) {\n");
    self.indent();

    // Generate float case - look for isnum block
    for (method.body) |stmt| {
        if (stmt != .if_stmt) continue;
        const if_stmt = stmt.if_stmt;
        if (if_stmt.condition.* != .call) continue;
        const call = if_stmt.condition.call;
        if (call.func.* != .name) continue;

        const func_name = call.func.name.id;
        if (!std.mem.eql(u8, func_name, "isnum")) continue;

        // Generate float case body
        for (if_stmt.body) |body_stmt| {
            try self.generateStmt(body_stmt);
        }
        break;
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("} else {\n");
    self.indent();

    // Generate fallback
    try self.emitIndent();
    try self.emit("return error.NotImplemented;\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Check if method has type-changing assignment: param = ClassName(param)
fn hasTypeChangingAssignment(method: ast.Node.FunctionDef, param_name: []const u8) bool {
    for (method.body) |stmt| {
        if (stmt != .if_stmt) continue;
        const if_stmt = stmt.if_stmt;
        for (if_stmt.body) |body_stmt| {
            if (body_stmt != .assign) continue;
            const assign = body_stmt.assign;
            if (assign.targets.len == 0) continue;
            if (assign.targets[0] != .name) continue;
            if (!std.mem.eql(u8, assign.targets[0].name.id, param_name)) continue;
            if (assign.value.* == .call and assign.value.call.func.* == .name) {
                return true;
            }
        }
    }
    return false;
}

/// Generate body for a specific type check (isClassName or isint)
/// Also handles fallthrough pattern: if isint: ...; elif not isRat: return; <rest>
fn generateBodyForTypeCheck(
    self: *NativeCodegen,
    method: ast.Node.FunctionDef,
    check_type: []const u8,
    is_class: bool,
) CodegenError!void {
    // First try to find the explicit block
    for (method.body) |stmt| {
        if (stmt != .if_stmt) continue;
        const if_stmt = stmt.if_stmt;
        if (if_stmt.condition.* != .call) continue;
        const call = if_stmt.condition.call;
        if (call.func.* != .name) continue;

        const func_name = call.func.name.id;

        if (is_class) {
            // Looking for isClassName (e.g., isRat)
            var class_check_name_buf: [64]u8 = undefined;
            const expected_func = std.fmt.bufPrint(&class_check_name_buf, "is{s}", .{check_type}) catch continue;
            if (!std.mem.eql(u8, func_name, expected_func)) continue;
        } else {
            // Looking for isint
            if (!std.mem.eql(u8, func_name, "isint") and !std.mem.eql(u8, func_name, "isinstance")) continue;
        }

        // Generate body
        for (if_stmt.body) |body_stmt| {
            try self.generateStmt(body_stmt);
        }
        return;
    }

    // No explicit block found - generate remaining statements (fallthrough pattern)
    // Pattern: if isint: ...; elif not isRat: return NotImplemented; x = self/other; return ...
    // We generate all statements after the type-checking if blocks
    var found_type_checks = false;
    for (method.body) |stmt| {
        if (stmt == .if_stmt) {
            const if_stmt = stmt.if_stmt;
            if (if_stmt.condition.* == .call) {
                const call = if_stmt.condition.call;
                if (call.func.* == .name) {
                    const func_name = call.func.name.id;
                    if (std.mem.startsWith(u8, func_name, "is")) {
                        found_type_checks = true;
                        continue; // Skip type-checking if blocks
                    }
                }
            }
            // Also skip "elif not isRat" pattern (unaryop with Not)
            if (if_stmt.condition.* == .unaryop) {
                const unary = if_stmt.condition.unaryop;
                if (unary.op == .Not and unary.operand.* == .call) {
                    const call = unary.operand.call;
                    if (call.func.* == .name and std.mem.startsWith(u8, call.func.name.id, "is")) {
                        found_type_checks = true;
                        continue;
                    }
                }
            }
        }
        if (found_type_checks) {
            try self.generateStmt(stmt);
        }
    }
}

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
        if (if_stmt.body.len != 1) break;
        if (if_stmt.body[0] != .raise_stmt) break;
        const raise = if_stmt.body[0].raise_stmt;
        if (raise.exc == null) break;

        // Check the exception is TypeError
        const is_type_error = blk: {
            if (raise.exc.?.* == .call) {
                const call = raise.exc.?.call;
                if (call.func.* == .name) {
                    break :blk std.mem.eql(u8, call.func.name.id, "TypeError");
                }
            } else if (raise.exc.?.* == .name) {
                break :blk std.mem.eql(u8, raise.exc.?.name.id, "TypeError");
            }
            break :blk false;
        };
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

// NOTE: Async strategy is now determined per-function via function_traits
// Query self.shouldUseStateMachineAsync(func.name) instead of hardcoded constant

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
    // Track function start position for scope-limited variable usage detection
    self.function_start_pos = self.output.items.len;

    // Register parameter renames for parameters that shadow module-level functions
    // or sibling class methods
    // This must happen AFTER the clear and BEFORE body generation
    for (func.args) |arg| {
        const shadows_module = self.module_level_funcs.contains(arg.name);

        // Check if parameter shadows a sibling method in the class
        const shadows_class_method = if (self.current_class_body) |class_body| blk: {
            for (class_body) |stmt| {
                if (stmt == .function_def) {
                    if (std.mem.eql(u8, stmt.function_def.name, arg.name)) {
                        break :blk true;
                    }
                }
                // Check class attributes assigned to None - these become stub methods
                if (stmt == .assign) {
                    for (stmt.assign.targets) |target| {
                        if (target == .name and stmt.assign.value.* == .constant and
                            stmt.assign.value.constant.value == .none)
                        {
                            if (std.mem.eql(u8, target.name.id, arg.name)) {
                                break :blk true;
                            }
                        }
                    }
                }
            }
            break :blk false;
        } else false;

        if (shadows_module or shadows_class_method) {
            const renamed = try std.fmt.allocPrint(self.allocator, "{s}__local", .{arg.name});
            try self.var_renames.put(arg.name, renamed);
        }
    }

    try mutation_analysis.analyzeFunctionLocalMutations(self, func);

    // Analyze function body for used variables (prevents false "unused" detection)
    try usage_analysis.analyzeFunctionLocalUses(self, func);

    // Analyze scope-escaping variables that need hoisting
    // Variables first assigned in for/if/while/try blocks but used outside need hoisting
    var scope_analysis = try scope_analyzer.analyzeScopes(func.body, self.allocator);
    defer scope_analysis.deinit();
    // Mark all escaped vars as hoisted (so assignment skips declaration)
    for (scope_analysis.escaped_vars.items) |escaped| {
        try self.hoisted_vars.put(escaped.name, {});
    }

    // Track local variables and analyze nested class captures for closure support
    self.func_local_vars.clearRetainingCapacity();
    self.nested_class_captures.clearRetainingCapacity();
    try nested_captures.analyzeNestedClassCaptures(self, func);

    self.indent();

    // Push new scope for function body
    try self.pushScope();

    // Emit hoisted variable declarations using shared hoisting module
    // This handles forward reference detection and fallback types
    try var_hoisting.emitHoistedDeclarations(self, scope_analysis.escaped_vars.items, func.args);

    // For generator functions, yield body becomes `// pass` which loses param usage.
    // We need to emit `_ = param;` ONLY for params that:
    // 1. Are in a generator function (yield body becomes pass)
    // 2. Are NOT actually used in the non-yield parts of the body
    // 3. Don't have defaults (defaults are handled below)
    const param_analyzer = @import("../../param_analyzer.zig");
    if (signature.hasYieldStatement(func.body)) {
        for (func.args) |arg| {
            // Skip params with defaults - they're used in "const x = x_param orelse ..."
            if (arg.default != null) continue;
            // Only discard if param is NOT used in the body (excluding yield expressions)
            // Use ExcludingYield variant since yield becomes `// pass`
            if (param_analyzer.isNameUsedInBodyExcludingYield(func.body, arg.name)) continue;
            try self.emitIndent();
            try self.emit("_ = ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
            try self.emit(";\n");
        }
    }

    // Track output position for unused anytype param detection after body generation
    const body_start_pos: usize = self.output.items.len;

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

            // Check if parameter is unused in the function body
            // For generator functions, use ExcludingYield since yield bodies become `// pass`
            const is_generator = signature.hasYieldStatement(func.body);
            const is_param_unused = if (is_generator)
                !param_analyzer.isNameUsedInBodyExcludingYield(func.body, arg.name)
            else
                !param_analyzer.isNameUsedInBody(func.body, arg.name);

            if (needs_rename) {
                if (is_param_unused) {
                    // Parameter is unused - just discard the optional value
                    try self.emitIndent();
                    try self.emit("_ = ");
                    try self.emit(arg.name);
                    try self.emit("_param;\n");
                } else {
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
                }
            } else {
                if (is_param_unused) {
                    // Parameter is unused - just discard the optional value
                    try self.emitIndent();
                    try self.emit("_ = ");
                    try self.emit(arg.name);
                    try self.emit("_param;\n");
                } else {
                    try self.emitIndent();
                    try self.emit("const ");
                    try self.emit(arg.name);
                    try self.emit(" = ");
                    try self.emit(arg.name);
                    try self.emit("_param orelse ");
                    try expressions.genExpr(self, default_expr.*);
                    try self.emit(";\n");
                    // Declare the param so it won't be hoisted later
                    try self.declareVar(arg.name);
                }
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
            // If ALL reassignments are type-changing (e.g., object = Class(object)),
            // we don't need a mutable copy because these become shadow variables
            // (const object__123 = Class.init(object)) - the original param is never mutated
            const all_type_changing = var_tracking.areAllReassignmentsTypeChanging(arg.name, func.body);

            if (all_type_changing) {
                // Don't create mutable copy - type-changing assignments use shadowing
                continue;
            }

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

    // Forward-referenced captured variables: emit var declarations with undefined
    // before the class definitions, so `&list2` doesn't fail with "undeclared"
    // Pass func.args to avoid shadowing function parameters
    var forward_refs = try nested_captures.findForwardReferencedCapturesWithParams(self, func.body, func.args);
    defer forward_refs.deinit(self.allocator);
    for (forward_refs.items) |fwd_var| {
        // Check if this variable would shadow a module-level declaration
        // (module-level functions, imports, module-level vars, or global vars declared with 'global' keyword)
        // If so, rename to avoid Zig's shadowing error
        var actual_fwd_var = fwd_var;
        const shadows_module_level = self.module_level_funcs.contains(fwd_var) or
            self.imported_modules.contains(fwd_var) or
            self.module_level_vars.contains(fwd_var) or
            self.isGlobalVar(fwd_var);
        if (shadows_module_level) {
            // Rename to avoid shadowing: set2 -> __local_set2
            const renamed = try std.fmt.allocPrint(self.allocator, "__local_{s}", .{fwd_var});
            try self.var_renames.put(try self.allocator.dupe(u8, fwd_var), renamed);
            actual_fwd_var = renamed;
        }
        try self.emitIndent();
        try self.emit("var ");
        try self.emit(actual_fwd_var);
        // Use i64 as the default type for forward-declared captured variables
        // This matches the capture struct type in closure_gen.zig which uses i64 for non-self captures
        try self.emit(": i64 = undefined;\n");
        // Suppress unused variable warning (forward-declared but might not be used in all paths)
        try self.emitIndent();
        try self.emit("_ = &");
        try self.emit(actual_fwd_var);
        try self.emit(";\n");
        // Mark as forward-declared so assignment doesn't re-declare
        try self.forward_declared_vars.put(actual_fwd_var, {});
    }

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

        // For generators, initialize __gen_result ArrayList before body
        if (self.in_generator_function) {
            try self.emitIndent();
            try self.emit("var __gen_result = std.ArrayList(runtime.PyValue){};\n");
            // Suppress unused warning in case function terminates early (e.g., raise before yield)
            try self.emitIndent();
            try self.emit("_ = &__gen_result;\n");
        }

        // Generate the rest of the function body (after the type checks)
        for (func.body[type_checks.start_idx..]) |stmt| {
            try self.generateStmt(stmt);
        }

        // For generators, return the collected results (if control flow not already terminated)
        if (self.in_generator_function and !self.control_flow_terminated) {
            try self.emitIndent();
            try self.emit("return __gen_result.items;\n");
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
        // For generators, initialize __gen_result ArrayList before body
        if (self.in_generator_function) {
            try self.emitIndent();
            try self.emit("var __gen_result = std.ArrayList(runtime.PyValue){};\n");
            // Suppress unused warning in case function terminates early (e.g., raise before yield)
            try self.emitIndent();
            try self.emit("_ = &__gen_result;\n");
        }
        for (func.body) |stmt| {
            try self.generateStmt(stmt);
        }
        // For generators, return the collected results (if control flow not already terminated)
        if (self.in_generator_function and !self.control_flow_terminated) {
            try self.emitIndent();
            try self.emit("return __gen_result.items;\n");
        }
    }

    // Check if anytype parameters were actually used in generated body
    // If not, emit `_ = param;` to suppress unused parameter warning
    // Handle early returns: if body ends with return, insert at body_start_pos instead of appending
    {
        const body_output = self.output.items[body_start_pos..];
        // Check if body ends with a return statement (would make appended code unreachable)
        // For block-expression returns like "return blk: { ... };", we need to find the last
        // "return " at the start of a line (after trimming whitespace)
        const ends_with_return = blk: {
            // Trim trailing whitespace to find the actual end
            var end_idx = body_output.len;
            while (end_idx > 0 and (body_output[end_idx - 1] == ' ' or body_output[end_idx - 1] == '\n' or body_output[end_idx - 1] == '\t')) {
                end_idx -= 1;
            }
            // Body must end with ; for it to be a complete return statement
            if (end_idx < 2 or body_output[end_idx - 1] != ';') {
                break :blk false;
            }
            // Find the last newline before the end
            var search_pos: usize = end_idx;
            while (search_pos > 0) {
                if (body_output[search_pos - 1] == '\n') {
                    // Found newline - check if next (non-whitespace) is "return "
                    var stmt_start = search_pos;
                    while (stmt_start < end_idx and (body_output[stmt_start] == ' ' or body_output[stmt_start] == '\t')) {
                        stmt_start += 1;
                    }
                    if (stmt_start + 7 <= end_idx) {
                        if (std.mem.eql(u8, body_output[stmt_start .. stmt_start + 7], "return ")) {
                            break :blk true;
                        }
                    }
                    // Not a return - keep searching for previous newline
                }
                search_pos -= 1;
            }
            // Check from the very start (no newline before)
            var stmt_start: usize = 0;
            while (stmt_start < end_idx and (body_output[stmt_start] == ' ' or body_output[stmt_start] == '\t')) {
                stmt_start += 1;
            }
            if (stmt_start + 7 <= end_idx) {
                if (std.mem.eql(u8, body_output[stmt_start .. stmt_start + 7], "return ")) {
                    break :blk true;
                }
            }
            break :blk false;
        };

        for (func.args) |arg| {
            // Check all params - anytype params don't get _ prefix in signature,
            // but regular params might be unused if body was partially skipped
            // Check if this param appears as a complete identifier in the generated body
            // (not just as a substring - e.g., "t" shouldn't match in "const")
            const param_is_used = blk: {
                var pos: usize = 0;
                while (std.mem.indexOfPos(u8, body_output, pos, arg.name)) |idx| {
                    const end = idx + arg.name.len;
                    // Check boundaries for complete identifier match
                    const valid_start = idx == 0 or (!std.ascii.isAlphanumeric(body_output[idx - 1]) and body_output[idx - 1] != '_');
                    const valid_end = end >= body_output.len or (!std.ascii.isAlphanumeric(body_output[end]) and body_output[end] != '_');
                    if (valid_start and valid_end) {
                        break :blk true;
                    }
                    pos = end;
                }
                break :blk false;
            };

            if (!param_is_used) {
                // Param not used - emit discard
                if (ends_with_return) {
                    // Body ends with return - insert at body_start_pos
                    // Build the discard statement
                    const discard = try std.fmt.allocPrint(self.allocator, "    _ = {s};\n", .{arg.name});
                    defer self.allocator.free(discard);
                    // Insert at body_start_pos
                    try self.output.insertSlice(self.allocator, body_start_pos, discard);
                } else {
                    // Safe to append at end
                    try self.emitIndent();
                    try self.emit("_ = ");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
                    try self.emit(";\n");
                }
            }
        }
    }

    // NOTE: Nested class unused suppression (e.g., _ = &ClassName;) is now handled
    // immediately after each class definition in generators.zig genClassDef().
    // This is necessary because classes inside if/for/while blocks are out of scope here.

    // Emit discards for any local variables that were assigned but not used in generated code
    // This must be done BEFORE popping scope, while output is still complete
    // BUT only if control flow hasn't terminated (return/raise) - otherwise we'd emit unreachable code
    if (!self.control_flow_terminated) {
        try self.emitPendingDiscards();
    } else {
        // Just clear without emitting since code after return is unreachable
        self.pending_discards.clearRetainingCapacity();
    }

    // Pop scope when exiting function
    self.popScope();

    // Clear function-local state after exiting function
    self.func_local_mutations.clearRetainingCapacity();
    self.func_local_aug_assigns.clearRetainingCapacity();
    self.func_local_vars.clearRetainingCapacity();

    // Clear nested class tracking (names and bases) after exiting function
    // This prevents class name collisions between different functions
    // BUT: Preserve if current class is nested or inside a nested class (class_nesting_depth > 1)
    const current_class_is_nested_fn = if (self.current_class_name) |ccn| self.nested_class_names.contains(ccn) else false;
    if (!current_class_is_nested_fn and self.class_nesting_depth <= 1) {
        self.nested_class_names.clearRetainingCapacity();
        self.nested_class_bases.clearRetainingCapacity();
        // Only clear forward declarations when exiting top-level function, not nested class methods
        self.forward_declared_vars.clearRetainingCapacity();
        // Clear nested_class_captures (free the slices first)
        var cap_iter = self.nested_class_captures.iterator();
        while (cap_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.nested_class_captures.clearRetainingCapacity();
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
    // Use state machine only when ANY async function has I/O (for consistency)
    if (self.anyAsyncHasIO()) {
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
    const needs_allocator = function_traits.analyzeNeedsAllocator(method, null);
    const actually_uses = function_traits.analyzeUsesAllocatorParam(method, null);
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
    // Save and restore control_flow_terminated for method body scope.
    // This is CRITICAL: nested class methods (like Foo.__bool__) may have return statements
    // that set this flag, but after the class definition, we need to continue generating
    // statements in the parent scope. Without this, statements after nested class defs get skipped.
    const saved_control_flow_terminated = self.control_flow_terminated;
    self.control_flow_terminated = false; // Reset for this method
    defer self.control_flow_terminated = saved_control_flow_terminated;

    // Save and restore pending_discards for method body scope.
    // This prevents emitPendingDiscards() (called before return statements) from emitting
    // discards for outer scope variables inside a nested class method.
    // e.g., u = ... <outer>; class C: def __new__: return self <--- shouldn't emit _ = &u here
    const saved_pending_discards = self.pending_discards;
    self.pending_discards = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
    defer {
        self.pending_discards.deinit();
        self.pending_discards = saved_pending_discards;
    }

    // Track whether we're inside a method with 'self' parameter.
    // This is used by generators.zig to know if a nested class should use __self.
    // The first parameter of a class method is always self (regardless of name like test_self, cls, etc.)
    const has_self = method.args.len > 0;
    const was_inside_method = self.inside_method_with_self;
    if (has_self) self.inside_method_with_self = true;
    defer self.inside_method_with_self = was_inside_method;

    // Check if this method is a generator (contains yield statements)
    // If so, set in_generator_function flag so yield statements work properly
    const is_generator_method = signature.hasYieldStatement(method.body);
    const saved_in_generator = self.in_generator_function;
    if (is_generator_method) {
        self.in_generator_function = true;
    }
    defer self.in_generator_function = saved_in_generator;

    // Set current function body for lookahead-based type inference
    // (e.g., inferring dict key type from subsequent subscript assignments)
    const prev_func_body = self.current_function_body;
    self.current_function_body = method.body;
    defer self.current_function_body = prev_func_body;

    // Analyze method body for mutated variables BEFORE generating code
    // This populates func_local_mutations so emitVarDeclaration can make correct var/const decisions
    self.func_local_mutations.clearRetainingCapacity();
    self.func_local_aug_assigns.clearRetainingCapacity();

    // Save parent's hoisted vars when generating nested class methods inside a function
    // Nested classes (like `class usub` inside an if block) call genMethodBody for their methods,
    // which clears hoisted_vars. After the class is generated, we need parent's hoisted vars
    // restored so subsequent assignments in the parent scope work correctly.
    // Condition: We're inside a parent function (func_local_uses has entries from parent scope)
    // AND we're in a nested class (class_nesting_depth > 1, since 1 = regular class method)
    const is_nested_class_in_function = self.func_local_uses.count() > 0 and self.class_nesting_depth > 1;
    var saved_hoisted_keys = std.ArrayList([]const u8){};
    if (is_nested_class_in_function) {
        var iter = self.hoisted_vars.iterator();
        while (iter.next()) |entry| {
            saved_hoisted_keys.append(self.allocator, entry.key_ptr.*) catch {};
        }
    }
    // Restore parent's hoisted vars when this method completes (using defer)
    defer {
        if (is_nested_class_in_function) {
            for (saved_hoisted_keys.items) |key| {
                self.hoisted_vars.put(key, {}) catch {};
            }
        }
        saved_hoisted_keys.deinit(self.allocator);
    }

    self.hoisted_vars.clearRetainingCapacity();
    self.nested_class_instances.clearRetainingCapacity();
    self.class_instance_aliases.clearRetainingCapacity();
    // Track method start position for scope-limited variable usage detection
    self.function_start_pos = self.output.items.len;
    try mutation_analysis.analyzeFunctionLocalMutations(self, method);

    // Analyze method body for used variables (prevents false "unused" detection)
    try usage_analysis.analyzeFunctionLocalUses(self, method);

    // Track local variables and analyze nested class captures for closure support
    // Clear all maps for each method to avoid pollution from sibling methods
    // (e.g., class A in test_sane_len should not affect class A in test_blocked)
    // BUT: Preserve nested_class_names/bases/captures when current class is nested (in nested_class_names)
    // or when deeply nested (class_nesting_depth > 1)
    // This is CRITICAL: nested_class_captures must NOT be cleared when generating methods
    // of a nested class, because sibling classes defined in the parent scope need their captures preserved
    self.func_local_vars.clearRetainingCapacity();
    const current_class_is_nested = if (self.current_class_name) |ccn| self.nested_class_names.contains(ccn) else false;
    if (!current_class_is_nested and self.class_nesting_depth <= 1) {
        self.nested_class_names.clearRetainingCapacity();
        self.nested_class_bases.clearRetainingCapacity();
        self.nested_class_captures.clearRetainingCapacity();
    }
    try nested_captures.analyzeNestedClassCaptures(self, method);

    // Add extra class names (for inherited method bodies that call parent class constructors)
    for (extra_class_names) |name| {
        try self.nested_class_names.put(name, {});
    }

    // Analyze scope-escaping variables that need hoisting
    // Variables first assigned in for/if/while/try blocks but used outside need hoisting
    var scope_analysis_method = try scope_analyzer.analyzeScopes(method.body, self.allocator);
    defer scope_analysis_method.deinit();
    // Mark all escaped vars as hoisted (so assignment skips declaration)
    for (scope_analysis_method.escaped_vars.items) |escaped| {
        try self.hoisted_vars.put(escaped.name, {});
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

    // Note: Unused allocator param is handled in signature.zig with "_:" prefix
    // No need to emit "_ = allocator;" here

    // Emit self parameter suppression for regular class methods (not @staticmethod or @classmethod)
    // This handles cases where self_analyzer detects self.attr access but the generated code
    // uses @This().attr for class attributes, making self appear unused to Zig.
    // Using _ = &self instead of _ = self avoids "pointless discard" errors when self IS used.
    const is_new_method = std.mem.eql(u8, method.name, "__new__");
    const is_staticmethod = signature.hasStaticmethodDecorator(method.decorators);
    const is_classmethod = signature.hasClassmethodDecorator(method.decorators);

    // Skip self suppression for @staticmethod and @classmethod - they don't have a self parameter
    if (self.current_class_name != null and method.args.len > 0 and !is_staticmethod and !is_classmethod) {
        // For __new__: nested uses __cls, top-level uses _ (no suppression needed)
        // For other methods: nested uses __self, top-level uses self
        const self_param_name: ?[]const u8 = if (is_new_method)
            (if (self.method_nesting_depth > 0) "__cls" else null)
        else if (self.method_nesting_depth > 0)
            "__self"
        else
            "self";

        if (self_param_name) |spn| {
            try self.emitIndent();
            try self.emit("_ = &");
            try self.emit(spn);
            try self.emit(";\n");
        }
    }

    // For comparison magic methods (__eq__, __ne__, __lt__, __le__, __gt__, __ge__),
    // emit suppression for second parameter since codegen may not use it in all cases
    // (e.g., `return SymbolicBool()` doesn't reference `other`)
    const is_comparison_method = std.mem.eql(u8, method.name, "__eq__") or
        std.mem.eql(u8, method.name, "__ne__") or
        std.mem.eql(u8, method.name, "__lt__") or
        std.mem.eql(u8, method.name, "__le__") or
        std.mem.eql(u8, method.name, "__gt__") or
        std.mem.eql(u8, method.name, "__ge__");
    if (is_comparison_method and method.args.len > 1) {
        // Second parameter (after self) is the comparison target
        const other_param_name = method.args[1].name;
        try self.emitIndent();
        try self.emit("_ = &");
        try self.emit(other_param_name);
        try self.emit(";\n");
    }

    // Emit hoisted variable declarations using shared hoisting module
    // This handles forward reference detection and fallback types
    try var_hoisting.emitHoistedDeclarations(self, scope_analysis_method.escaped_vars.items, method.args);

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

    // Track the first param name so we can recognize unittest calls like test_self.assertEqual()
    // Save previous value and restore on exit (for nested class methods)
    const saved_first_param = self.current_method_first_param;
    self.current_method_first_param = first_param_name;
    defer self.current_method_first_param = saved_first_param;

    // If first param isn't named "self", rename it to "self" for proper Zig self reference
    // Use the appropriate self name based on nesting depth (self vs __self)
    if (needs_first_param_rename) {
        const target_self_name = if (self.method_nesting_depth > 0) "__self" else "self";
        try self.var_renames.put(first_param_name.?, target_self_name);
        try renamed_params.append(self.allocator, first_param_name.?);
    }

    const var_tracking = @import("../../nested/var_tracking.zig");
    var is_first = true;
    for (method.args) |arg| {
        // Skip the first parameter (self/cls/test_self/etc.)
        if (is_first) {
            is_first = false;
            continue;
        }
        // Check if this param would shadow a method name or sibling class method
        const shadows_builtin_method = zig_keywords.wouldShadowMethod(arg.name);
        const shadows_class_method = if (self.current_class_body) |cb| blk: {
            for (cb) |stmt| {
                if (stmt == .function_def) {
                    if (std.mem.eql(u8, stmt.function_def.name, arg.name)) {
                        break :blk true;
                    }
                }
                // Check class attributes assigned to None - these become stub methods
                if (stmt == .assign) {
                    for (stmt.assign.targets) |target| {
                        if (target == .name and stmt.assign.value.* == .constant and
                            stmt.assign.value.constant.value == .none)
                        {
                            if (std.mem.eql(u8, target.name.id, arg.name)) {
                                break :blk true;
                            }
                        }
                    }
                }
            }
            break :blk false;
        } else false;

        if (shadows_builtin_method or shadows_class_method) {
            // Add rename mapping: original -> renamed
            const renamed = try std.fmt.allocPrint(self.allocator, "{s}__local", .{arg.name});
            try self.var_renames.put(arg.name, renamed);
            try renamed_params.append(self.allocator, arg.name);
        }
        try self.declareVar(arg.name);
    }

    // Track body start position for unused param detection BEFORE mutable copies are generated
    // This ensures "var xs__mut = xs;" is included in the usage check so we don't emit pointless "_ = xs;"
    const method_body_start_pos = self.output.items.len;

    // Check if parameters are reassigned in the method body
    // Zig function parameters are const, so we need mutable copies
    // Start from index 1 to skip self parameter
    for (method.args[@min(1, method.args.len)..]) |arg| {
        // Check if this parameter is reassigned in the method body
        if (var_tracking.isParamReassignedInStmts(arg.name, method.body)) {
            // If ALL reassignments are type-changing (e.g., object = Class(object)),
            // we don't need a mutable copy because these become shadow variables
            // (const object__123 = Class.init(object)) - the original param is never mutated
            const all_type_changing = var_tracking.areAllReassignmentsTypeChanging(arg.name, method.body);

            if (all_type_changing) {
                // Don't create mutable copy - type-changing assignments use shadowing
                continue;
            }

            // Create a mutable copy of the parameter
            try self.emitIndent();
            try self.emit("var ");
            try self.emit(arg.name);
            try self.emit("__mut = ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
            try self.emit(";\n");
            // Rename all references to use the mutable copy
            try self.var_renames.put(arg.name, try std.fmt.allocPrint(self.allocator, "{s}__mut", .{arg.name}));
            try renamed_params.append(self.allocator, arg.name);
        }
    }

    // Forward-referenced captured variables: emit var declarations with undefined
    // before the class definitions, so `&list2` doesn't fail with "undeclared"
    // Pass method.args to avoid shadowing method parameters
    var forward_refs_method = try nested_captures.findForwardReferencedCapturesWithParams(self, method.body, method.args);
    defer forward_refs_method.deinit(self.allocator);
    for (forward_refs_method.items) |fwd_var| {
        // Check if this variable would shadow a module-level declaration
        // (module-level functions, imports, module-level vars, or global vars declared with 'global' keyword)
        // If so, rename to avoid Zig's shadowing error
        var actual_fwd_var = fwd_var;
        const shadows_module_level = self.module_level_funcs.contains(fwd_var) or
            self.imported_modules.contains(fwd_var) or
            self.module_level_vars.contains(fwd_var) or
            self.isGlobalVar(fwd_var);
        if (shadows_module_level) {
            const renamed = try std.fmt.allocPrint(self.allocator, "__local_{s}", .{fwd_var});
            try self.var_renames.put(try self.allocator.dupe(u8, fwd_var), renamed);
            actual_fwd_var = renamed;
        }
        try self.emitIndent();
        try self.emit("var ");
        try self.emit(actual_fwd_var);
        // Use i64 as the default type for forward-declared captured variables
        // This matches the capture struct type in closure_gen.zig which uses i64 for non-self captures
        try self.emit(": i64 = undefined;\n");
        // Suppress unused variable warning (forward-declared but might not be used in all paths)
        try self.emitIndent();
        try self.emit("_ = &");
        try self.emit(actual_fwd_var);
        try self.emit(";\n");
        // Mark as forward-declared so assignment doesn't re-declare
        try self.forward_declared_vars.put(actual_fwd_var, {});
    }

    // Check if we need comptime type dispatch for anytype params with type-changing patterns
    // Pattern: if isint(param): param = ClassName(param); if isClassName(param): ... use param.__field ...
    // This pattern requires generating separate code paths for each type to avoid Zig type errors
    const type_dispatch_info = try detectTypeChangingPattern(self, method);

    if (type_dispatch_info.needs_dispatch) {
        // Generate comptime type dispatch
        try generateComptimeTypeDispatch(self, method, type_dispatch_info);
    } else {
        // For generator methods, initialize __gen_result ArrayList before body
        if (is_generator_method) {
            try self.emitIndent();
            try self.emit("var __gen_result = std.ArrayList(runtime.PyValue){};\n");
            try self.emitIndent();
            try self.emit("_ = &__gen_result;\n");
        }

        // Generate method body normally
        for (method.body) |method_stmt| {
            try self.generateStmt(method_stmt);
        }

        // For generator methods, return the collected results
        if (is_generator_method and !self.control_flow_terminated) {
            try self.emitIndent();
            try self.emit("return __gen_result.items;\n");
        }
    }

    // Check if method parameters (beyond self) were actually used in generated body
    // If not, emit `_ = param;` to suppress unused parameter warning
    // This is needed when Python functions like gc.is_tracked() are compiled away to constants
    // BUT: Skip this if control flow is terminated (return/raise) - would cause unreachable code
    // AND: Skip params that were already made anonymous ("_:") in signature generation
    if (!self.control_flow_terminated) {
        const method_body_output = self.output.items[method_body_start_pos..];
        // Start from 1 to skip self parameter (already handled above)
        const start_param = if (method.args.len > 0) @as(usize, 1) else @as(usize, 0);
        for (method.args[start_param..]) |arg| {
            // Check if this param appears as a complete identifier in the generated body
            const param_is_used = blk: {
                var pos: usize = 0;
                while (std.mem.indexOfPos(u8, method_body_output, pos, arg.name)) |idx| {
                    const end = idx + arg.name.len;
                    // Check boundaries for complete identifier match
                    const valid_start = idx == 0 or (!std.ascii.isAlphanumeric(method_body_output[idx - 1]) and method_body_output[idx - 1] != '_');
                    const valid_end = end >= method_body_output.len or (!std.ascii.isAlphanumeric(method_body_output[end]) and method_body_output[end] != '_');
                    if (valid_start and valid_end) {
                        break :blk true;
                    }
                    pos = end;
                }
                break :blk false;
            };

            if (!param_is_used) {
                // Param not used - emit discard
                try self.emitIndent();
                try self.emit("_ = ");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
                try self.emit(";\n");
            }
        }
    }

    // NOTE: Self parameter suppression is now handled at the beginning of method body
    // using _ = &self; which doesn't have "pointless discard" issues

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

    // Emit discards for any local variables that were assigned but not used in generated code
    // This must be done BEFORE popping scope, while output is still complete
    // BUT only if control flow hasn't terminated (return/raise) - otherwise we'd emit unreachable code
    if (!self.control_flow_terminated) {
        try self.emitPendingDiscards();
    } else {
        // Just clear without emitting since code after return is unreachable
        self.pending_discards.clearRetainingCapacity();
    }

    // Pop scope when exiting method
    self.popScope();

    // Clear function-local mutations after exiting method
    self.func_local_mutations.clearRetainingCapacity();
    self.func_local_aug_assigns.clearRetainingCapacity();

    // Clear nested class tracking (names and bases) after exiting method
    // This prevents class name collisions between different methods
    // (e.g., both test_foo and test_bar may have a nested class named BadIndex)
    // BUT: Preserve if current class is nested or inside a nested class (class_nesting_depth > 1)
    const current_class_is_nested_exit = if (self.current_class_name) |ccn| self.nested_class_names.contains(ccn) else false;
    if (!current_class_is_nested_exit and self.class_nesting_depth <= 1) {
        self.nested_class_names.clearRetainingCapacity();
        self.nested_class_bases.clearRetainingCapacity();
        // Only clear forward declarations when exiting top-level method, not nested class methods
        self.forward_declared_vars.clearRetainingCapacity();
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}
