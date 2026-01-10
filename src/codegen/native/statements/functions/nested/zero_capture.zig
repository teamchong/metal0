/// Zero-capture closure generation - optimized closures with no captured variables
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const zig_keywords = @import("utils.zig_keywords");
const hashmap_helper = @import("utils.hashmap_helper");
const var_tracking = @import("var_tracking.zig");
const type_traits = @import("../../../../../analysis/traits/type_traits.zig");
const signature = @import("../generators/signature.zig");

/// Check if a function has the @abstractmethod decorator
/// Returns true if any decorator is "abstractmethod" or "abc.abstractmethod"
fn hasAbstractmethodDecorator(decorators: []ast.Node) bool {
    for (decorators) |dec| {
        if (dec == .name) {
            if (std.mem.eql(u8, dec.name.id, "abstractmethod")) return true;
        } else if (dec == .attribute) {
            // Handle abc.abstractmethod
            if (std.mem.eql(u8, dec.attribute.attr, "abstractmethod")) return true;
        }
    }
    return false;
}

/// Generate zero-capture closure using comptime ZeroClosure
pub fn genZeroCaptureClosure(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
) CodegenError!void {
    // Save ID for unique naming
    const saved_id = self.name_gen.nextId();

    // Generate the inner function
    const impl_name = try std.fmt.allocPrint(
        self.allocator,
        "__m{d}_ZeroImpl_{s}",
        .{ saved_id, func.name },
    );
    defer self.allocator.free(impl_name);

    // Use unique function name inside the struct to avoid shadowing
    const inner_fn_name = try std.fmt.allocPrint(
        self.allocator,
        "__m{d}_fn_{s}",
        .{ saved_id, func.name },
    );

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
                "__m{d}_p_{s}",
                .{ saved_id, arg.name },
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
                "__m{d}_p_{s}",
                .{ saved_id, vararg_name },
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
                "__m{d}_p_{s}",
                .{ saved_id, kwarg_name },
            );
            try param_renames.put(kwarg_name, unique_kwarg_name);
            try self.output.writer(self.allocator).print("{s}: anytype", .{unique_kwarg_name});
        } else {
            try self.emit("_: anytype");
        }
    }
    // Check if this is a generator function (contains yield) - used for return type
    const is_generator_func = signature.hasYieldStatement(func.body);

    // Look up the function's inferred return type from type inference
    // Use it for proper type safety, falling back to anytype workaround via @TypeOf
    const return_type = self.type_inferrer.func_return_types.get(func.name);
    if (is_generator_func) {
        // Generators return slice of PyValue
        try self.emit(") ![]runtime.PyValue {\n");
    } else if (return_type) |rt| {
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

    // Track the base scope level for this nested function
    const saved_nested_base_scope = self.nested_function_base_scope;
    self.nested_function_base_scope = self.symbol_table.currentScopeLevel();
    defer self.nested_function_base_scope = saved_nested_base_scope;

    // Save and reset control_flow_terminated - nested function has its own control flow
    // Without this, a return statement in nested function prevents subsequent statements
    // in the outer function from being generated
    const saved_control_flow_terminated = self.control_flow_terminated;
    self.control_flow_terminated = false;
    defer self.control_flow_terminated = saved_control_flow_terminated;

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

    // Save and clear func_local_vars - nested function has its own local variables
    // Outer function's locals should NOT prevent var_renames lookup for parameters
    // (e.g., outer `x` should not prevent `x -> __p_x_11` rename in nested function)
    const saved_func_local_vars = self.func_local_vars;
    self.func_local_vars = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.func_local_vars.deinit();
        self.func_local_vars = saved_func_local_vars;
    }

    // Save outer function's var_renames - nested function has its own parameter renames
    // Without this, when we remove nested param renames after body generation (lines 469-476),
    // we would also remove outer function's renames for params with the same name
    // (e.g., if both outer and nested have `width` param, outer's `width -> width_param` gets removed)
    const VarRenameEntry = struct { key: []const u8, value: []const u8 };
    var saved_var_renames = std.ArrayListUnmanaged(VarRenameEntry){};
    {
        var iter = self.var_renames.iterator();
        while (iter.next()) |entry| {
            saved_var_renames.append(self.allocator, .{ .key = entry.key_ptr.*, .value = entry.value_ptr.* }) catch {};
        }
    }
    defer {
        // Restore outer function's var_renames
        for (saved_var_renames.items) |entry| {
            self.var_renames.put(entry.key, entry.value) catch {};
        }
        saved_var_renames.deinit(self.allocator);
    }

    // Save and clear nested_class_captures for this nested function
    // Each nested function needs its own capture analysis
    const saved_nested_class_captures = self.nested_class_captures;
    self.nested_class_captures = hashmap_helper.StringHashMap([][]const u8).init(self.allocator);
    defer {
        // Free any allocated capture slices
        var cap_iter = self.nested_class_captures.iterator();
        while (cap_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.nested_class_captures.deinit();
        self.nested_class_captures = saved_nested_class_captures;
    }

    // Analyze nested class captures BEFORE generating body
    // This populates func_local_vars with parameters and local variables,
    // then finds which outer variables are referenced by nested classes
    const nested_captures = @import("../generators/body/nested_captures.zig");
    try nested_captures.analyzeNestedClassCaptures(self, func);

    // Save and clear mutation tracking for this nested function body
    // Nested functions need their own mutation analysis to determine var vs const
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

    // Mutation analysis now handled by passes system (no-op)
    const body = @import("../generators/body.zig");
    try body.analyzeFunctionLocalMutations(self, func);

    // Analyze VM fallback variables - these are variables used inside eval() strings
    // Without this, variables like `res` in `eval("res.append(i)")` appear unused
    const vm_fallback_analysis = @import("../generators/body/vm_fallback_analysis.zig");
    try vm_fallback_analysis.analyzeVMFallbackVars(self, func);

    // Populate func_local_uses with variables used in this function body
    try var_tracking.collectUsedNames(func.body, &self.func_local_uses);

    // Track which parameters need mutable copies due to reassignment
    var reassigned_param_vars = std.ArrayList([]const u8){};
    defer reassigned_param_vars.deinit(self.allocator);

    for (func.args) |arg| {
        try self.declareVar(arg.name);
        const is_reassigned = var_tracking.isParamReassignedInStmts(arg.name, func.body);

        // Add rename mapping for parameter access in body
        // IMPORTANT: Must dupe renamed value because param_renames is deferred deinit
        if (param_renames.get(arg.name)) |renamed| {
            if (is_reassigned) {
                // Create mutable var copy name
                const var_name = try std.fmt.allocPrint(self.allocator, "__m{d}_v_{s}", .{ saved_id, arg.name });
                try reassigned_param_vars.append(self.allocator, var_name);
                try self.var_renames.put(arg.name, var_name);
            } else {
                const renamed_copy = try self.arena.allocator().dupe(u8, renamed);
                try self.var_renames.put(arg.name, renamed_copy);
            }
        }
    }

    // Handle vararg scope declaration and rename mapping
    if (func.vararg) |vararg_name| {
        try self.declareVar(vararg_name);
        // IMPORTANT: Must dupe renamed value because param_renames is deferred deinit
        if (param_renames.get(vararg_name)) |renamed| {
            const is_reassigned = var_tracking.isParamReassignedInStmts(vararg_name, func.body);
            if (is_reassigned) {
                const var_name = try std.fmt.allocPrint(self.allocator, "__m{d}_v_{s}", .{ saved_id, vararg_name });
                try reassigned_param_vars.append(self.allocator, var_name);
                try self.var_renames.put(vararg_name, var_name);
            } else {
                const renamed_copy = try self.arena.allocator().dupe(u8, renamed);
                try self.var_renames.put(vararg_name, renamed_copy);
            }
        }
    }

    // Handle kwarg scope declaration and rename mapping
    if (func.kwarg) |kwarg_name| {
        try self.declareVar(kwarg_name);
        // IMPORTANT: Must dupe renamed value because param_renames is deferred deinit
        if (param_renames.get(kwarg_name)) |renamed| {
            const is_reassigned = var_tracking.isParamReassignedInStmts(kwarg_name, func.body);
            if (is_reassigned) {
                const var_name = try std.fmt.allocPrint(self.allocator, "__m{d}_v_{s}", .{ saved_id, kwarg_name });
                try reassigned_param_vars.append(self.allocator, var_name);
                try self.var_renames.put(kwarg_name, var_name);
            } else {
                const renamed_copy = try self.arena.allocator().dupe(u8, renamed);
                try self.var_renames.put(kwarg_name, renamed_copy);
            }
        }
    }

    // Emit var copies for reassigned parameters
    for (func.args) |arg| {
        if (var_tracking.isParamReassignedInStmts(arg.name, func.body) and param_renames.get(arg.name) != null) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("var __m{d}_v_{s} = __m{d}_p_{s};\n", .{ saved_id, arg.name, saved_id, arg.name });
        }
    }

    // Emit var copy for reassigned vararg
    if (func.vararg) |vararg_name| {
        if (var_tracking.isParamReassignedInStmts(vararg_name, func.body) and param_renames.get(vararg_name) != null) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("var __m{d}_v_{s} = __m{d}_p_{s};\n", .{ saved_id, vararg_name, saved_id, vararg_name });
        }
    }

    // Emit var copy for reassigned kwarg
    if (func.kwarg) |kwarg_name| {
        if (var_tracking.isParamReassignedInStmts(kwarg_name, func.body) and param_renames.get(kwarg_name) != null) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("var __m{d}_v_{s} = __m{d}_p_{s};\n", .{ saved_id, kwarg_name, saved_id, kwarg_name });
        }
    }

    // Mark as closure BEFORE generating body so recursive calls use .call() syntax
    // We'll add it again at the end (duplicate put is OK for the hashmap)
    const func_name_copy_early = try self.arena.allocator().dupe(u8, func.name);
    try self.closure_vars.put(func_name_copy_early, {});

    // Check if this is a generator function (contains yield)
    const is_generator = signature.hasYieldStatement(func.body);
    // Track generator closures for listFromSlice wrapping during assignment
    if (is_generator) {
        try self.generator_closure_vars.put(func_name_copy_early, {});
    }
    const saved_in_generator = self.in_generator_function;
    if (is_generator) {
        self.in_generator_function = true;
        // Initialize __gen_result ArrayList for collecting yield values
        try self.emitIndent();
        try self.emit("var __gen_result = std.ArrayListUnmanaged(runtime.PyValue){};\n");
        try self.emitIndent();
        try self.emit("_ = &__gen_result;\n");
    }
    defer self.in_generator_function = saved_in_generator;

    // Check if body contains early-terminating statements (skipped imports)
    // If so, emit param discards upfront before they become unreachable
    const has_early_termination = blk: {
        for (func.body) |stmt| {
            if (stmt == .import_stmt) {
                if (self.isSkippedModule(stmt.import_stmt.module)) break :blk true;
            } else if (stmt == .import_from) {
                if (self.isSkippedModule(stmt.import_from.module)) break :blk true;
            }
        }
        break :blk false;
    };

    // Emit param discards upfront if we'll terminate early
    if (has_early_termination) {
        for (func.args) |arg| {
            // Skip already-anonymous parameters (named "_")
            if (std.mem.eql(u8, arg.name, "_")) continue;
            // Emit discard for parameter
            try self.emitIndent();
            try self.emit("_ = &");
            // Use renamed parameter if applicable
            if (param_renames.get(arg.name)) |renamed| {
                try self.emit(renamed);
            } else {
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
            }
            try self.emit(";\n");
        }
    }

    // Emit param discards for parameters captured by nested classes
    // These params are used inside nested class methods but the class may not be
    // instantiated in a way that Zig can see (e.g., passed to type.__new__)
    // Without this, Zig complains about unused parameters
    {
        var captured_params = hashmap_helper.StringHashMap(void).init(self.allocator);
        defer captured_params.deinit();

        // Collect all captured variable names from nested classes
        var ncc_iter = self.nested_class_captures.iterator();
        while (ncc_iter.next()) |entry| {
            for (entry.value_ptr.*) |cap_name| {
                try captured_params.put(cap_name, {});
            }
        }

        // Emit discards for params that are captured but not otherwise used directly
        for (func.args) |arg| {
            if (captured_params.contains(arg.name)) {
                if (param_renames.get(arg.name)) |renamed| {
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("_ = &{s};\n", .{renamed});
                }
            }
        }
        // Also check vararg
        if (func.vararg) |vararg_name| {
            if (captured_params.contains(vararg_name)) {
                if (param_renames.get(vararg_name)) |renamed| {
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("_ = &{s};\n", .{renamed});
                }
            }
        }
        // Also check kwarg
        if (func.kwarg) |kwarg_name| {
            if (captured_params.contains(kwarg_name)) {
                if (param_renames.get(kwarg_name)) |renamed| {
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("_ = &{s};\n", .{renamed});
                }
            }
        }
    }

    // Always emit param discards for all parameters
    // This is safe because Zig ignores redundant _ = &x; statements if x is actually used
    // and handles cases where params are used in runtime.eval() strings but not in Zig code
    {
        for (func.args) |arg| {
            if (std.mem.eql(u8, arg.name, "_")) continue;
            if (param_renames.get(arg.name)) |renamed| {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("_ = &{s};\n", .{renamed});
            }
        }
        if (func.vararg) |vararg_name| {
            if (param_renames.get(vararg_name)) |renamed| {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("_ = &{s};\n", .{renamed});
            }
        }
        if (func.kwarg) |kwarg_name| {
            if (param_renames.get(kwarg_name)) |renamed| {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("_ = &{s};\n", .{renamed});
            }
        }
    }

    for (func.body) |stmt| {
        try self.generateStmt(stmt);
        // If control flow terminated, skip remaining statements
        if (self.control_flow_terminated) break;
    }

    // For generators, return the collected results
    if (is_generator and !self.control_flow_terminated) {
        try self.emitIndent();
        try self.emit("return __gen_result.items;\n");
    }

    // Free the reassigned param var names
    for (reassigned_param_vars.items) |var_name| {
        self.allocator.free(var_name);
    }

    // If function has non-void return type but no explicit return/raise, add default return
    // Both return_stmt and raise_stmt are terminating statements - don't add return after them
    // Skip for generators - their return is handled above
    if (!is_generator) {
        const has_explicit_return = blk: {
            for (func.body) |stmt| {
                if (stmt == .return_stmt or stmt == .raise_stmt) break :blk true;
            }
            break :blk false;
        };
        if (!has_explicit_return and return_type != null) {
            // Add default return based on return type
            try self.emitIndent();
            if (return_type) |rt| {
                if (rt == .int or rt == .usize) {
                    try self.emit("return 0;\n");
                } else if (type_traits.isClassInstance(rt)) {
                    try self.emit("return undefined;\n");
                } else {
                    try self.emit("return undefined;\n");
                }
            } else {
                try self.emit("return 0;\n");
            }
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
    if (is_generator_func) {
        // Generators return slice of PyValue
        try return_type_str.appendSlice(self.allocator, "[]runtime.PyValue");
    } else if (return_type) |rt| {
        try native_types.NativeType.toZigType(rt, self.allocator, &return_type_str);
    } else {
        try return_type_str.appendSlice(self.allocator, "i64");
    }

    // Check if this function was hoisted as a DynamicClosure (from if/else branch)
    // Used below to decide whether to add var_rename
    const is_hoisted_dynamic = self.hoisted_dynamic_closures.contains(func.name);

    try self.emitIndent();
    try self.emit("const ");
    // Always use a unique wrapper name to avoid conflicts with:
    // 1. Imported module names (e.g., "test" shadows "import test")
    // 2. Nested class method names (e.g., closure "foo" vs class method "foo")
    // Using unique names prevents Zig's "shadows local constant" errors
    const wrapper_name = try std.fmt.allocPrint(self.allocator, "__m{d}_closure_{s}", .{ saved_id, func.name });
    // Don't defer free - the name is stored in var_renames for later reference
    // Register rename so references use the correct name
    // BUT: For hoisted dynamic closures (from if/else branches), do NOT add var_rename.
    // Hoisted closures use the original name (e.g., ptr_formatter) which was hoisted
    // as DynamicClosure. The wrapper_name is only used internally.
    if (!is_hoisted_dynamic) {
        try self.var_renames.put(func.name, wrapper_name);
    }
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), wrapper_name);

    // Calculate total param count (including vararg)
    const has_vararg = func.vararg != null;
    const total_params = func.args.len + @intFromBool(has_vararg);

    if (total_params == 1 and !has_vararg) {
        // Single arg (no vararg) - create simple wrapper struct
        const unique_param = try std.fmt.allocPrint(
            self.allocator,
            "__m{d}_p_{s}",
            .{ saved_id, func.args[0].name },
        );
        defer self.allocator.free(unique_param);

        try self.emit(" = struct {\n");
        self.indent();
        // Add __name__ and __dict__ fields for Python function attribute compatibility
        try self.emitIndent();
        try self.output.writer(self.allocator).print("__name__: []const u8 = \"{s}\",\n", .{func.name});
        try self.emitIndent();
        try self.emit("__dict__: ?*anyopaque = null,\n");
        // Add __isabstractmethod__ field - always present (Python accesses this on all callables)
        // Set to true only if function has @abstractmethod decorator
        try self.emitIndent();
        if (hasAbstractmethodDecorator(func.decorators)) {
            try self.emit("__isabstractmethod__: bool = true,\n");
        } else {
            try self.emit("__isabstractmethod__: bool = false,\n");
        }
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
        // Use a different ID for wrapper params (saved_id is already used above)
        const wrapper_id = self.name_gen.nextId();

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
                "__m{d}_p_{s}",
                .{ wrapper_id, arg.name },
            );
            try param_names.append(self.allocator, unique_name);
        }

        // Add vararg to param_names
        var vararg_param_name: ?[]const u8 = null;
        if (func.vararg) |vararg_name| {
            vararg_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__m{d}_p_{s}",
                .{ wrapper_id, vararg_name },
            );
            try param_names.append(self.allocator, vararg_param_name.?);
        }

        try self.emit(" = struct {\n");
        self.indent();
        // Add __name__ and __dict__ fields for Python function attribute compatibility
        try self.emitIndent();
        try self.output.writer(self.allocator).print("__name__: []const u8 = \"{s}\",\n", .{func.name});
        try self.emitIndent();
        try self.emit("__dict__: ?*anyopaque = null,\n");
        // Add __isabstractmethod__ field - always present (Python accesses this on all callables)
        // Set to true only if function has @abstractmethod decorator
        try self.emitIndent();
        if (hasAbstractmethodDecorator(func.decorators)) {
            try self.emit("__isabstractmethod__: bool = true,\n");
        } else {
            try self.emit("__isabstractmethod__: bool = false,\n");
        }
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

    // Check if func.name is already declared in current scope (redefinition)
    // Python allows redefining function names: def f(): ... def f(): ... (second shadows first)
    const is_redefinition = self.isDeclared(func.name);

    // Check if this function was hoisted as a DynamicClosure (from if/else branch)
    // In this case, we assign to the existing var instead of creating a new const
    // Use hoisted_dynamic_closures, not closure_vars - closure_vars includes ALL closures
    const is_hoisted_closure = self.hoisted_dynamic_closures.contains(func.name);

    if (is_hoisted_closure) {
        // Assign to hoisted DynamicClosure variable
        try self.emitIndent();
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), func.name);
        try self.output.writer(self.allocator).print(" = runtime.DynamicClosure.init({s});\n", .{wrapper_name});
    } else {
        // If shadowing an import or redefinition, use NameGen for consistent unique naming
        const alias_name = if (shadows_import or is_redefinition)
            try self.name_gen.closure(func.name)
        else
            try self.arena.allocator().dupe(u8, func.name);
        defer self.allocator.free(alias_name);

        try self.emitIndent();
        // Check if function name will be reassigned (e.g., bar = decorator(bar))
        // If so, use var instead of const to allow the reassignment
        // NOTE: We check saved_func_local_mutations (outer function's mutations) because
        // at this point self.func_local_mutations has been replaced with the nested function's
        // mutation map. The decorator reassignment happens in the OUTER function scope.
        var outer_key_buf: [256]u8 = undefined;
        const outer_key = std.fmt.bufPrint(&outer_key_buf, "{s}:0", .{func.name}) catch func.name;
        const is_func_mutated = saved_func_local_mutations.contains(func.name) or
            saved_func_local_mutations.contains(outer_key);
        try self.emit(if (is_func_mutated) "var " else "const ");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), alias_name);
        try self.output.writer(self.allocator).print(" = {s};\n", .{wrapper_name});

        // If we renamed the function, also add a var_rename so calls use the prefixed name
        if (shadows_import or is_redefinition) {
            const alias_copy = try self.arena.allocator().dupe(u8, alias_name);
            try self.var_renames.put(func.name, alias_copy);
        }

        // Declare the alias name (using unique name if redefinition)
        try self.declareVar(alias_name);

        // Suppress unused local constant warning for the alias
        try self.emitIndent();
        try self.emit("_ = &");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), alias_name);
        try self.emit(";\n");

        // Mark as closure so calls use .call() syntax
        const func_name_copy = try self.arena.allocator().dupe(u8, func.name);
        try self.closure_vars.put(func_name_copy, {});
    }
}

/// Generate a zero-capture closure at module level.
/// This is called during the pre-scan phase for functions that return closures.
/// The generated type can be used as the function's return type.
pub fn genModuleLevelZeroCaptureClosure(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    type_name: []const u8,
) CodegenError!void {
    const saved_id = self.name_gen.nextId();

    // Generate the implementation struct at module level
    const impl_name = try std.fmt.allocPrint(
        self.allocator,
        "__m{d}_ModImpl_{s}",
        .{ saved_id, func.name },
    );
    defer self.allocator.free(impl_name);

    const inner_fn_name = try std.fmt.allocPrint(
        self.allocator,
        "__m{d}_fn_{s}",
        .{ saved_id, func.name },
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
                "__m{d}_p_{s}",
                .{ saved_id, arg.name },
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
                "__m{d}_p_{s}",
                .{ saved_id, vararg_name },
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

    // Track the base scope level for this nested function
    const saved_nested_base_scope = self.nested_function_base_scope;
    self.nested_function_base_scope = self.symbol_table.currentScopeLevel();
    defer self.nested_function_base_scope = saved_nested_base_scope;

    // Save and clear mutation tracking for this nested function body
    const saved_func_local_mutations_2 = self.func_local_mutations;
    const saved_func_local_aug_assigns_2 = self.func_local_aug_assigns;
    self.func_local_mutations = hashmap_helper.StringHashMap(void).init(self.allocator);
    self.func_local_aug_assigns = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.func_local_mutations.deinit();
        self.func_local_aug_assigns.deinit();
        self.func_local_mutations = saved_func_local_mutations_2;
        self.func_local_aug_assigns = saved_func_local_aug_assigns_2;
    }

    // Analyze nested function body for local mutations (determines var vs const)
    // Note: passes system already analyzed mutations - this is a no-op for compatibility
    const body = @import("../generators/body.zig");
    try body.analyzeFunctionLocalMutations(self, func);

    // Analyze VM fallback variables - these are variables used inside eval() strings
    // Without this, variables like `res` in `eval("res.append(i)")` appear unused
    const vm_fallback_analysis = @import("../generators/body/vm_fallback_analysis.zig");
    try vm_fallback_analysis.analyzeVMFallbackVars(self, func);

    // Add parameter renames to var_renames temporarily
    // IMPORTANT: Must dupe renamed values because param_renames is deferred deinit
    var rename_keys = std.ArrayList([]const u8){};
    defer rename_keys.deinit(self.allocator);
    var rename_iter = param_renames.iterator();
    while (rename_iter.next()) |entry| {
        try self.declareVar(entry.key_ptr.*);
        const value_copy = try self.arena.allocator().dupe(u8, entry.value_ptr.*);
        try self.var_renames.put(entry.key_ptr.*, value_copy);
        try rename_keys.append(self.allocator, entry.key_ptr.*);
    }

    // Handle vararg scope
    if (func.vararg) |vararg_name| {
        try self.declareVar(vararg_name);
        // IMPORTANT: Must dupe renamed value because param_renames is deferred deinit
        if (param_renames.get(vararg_name)) |renamed| {
            const renamed_copy = try self.arena.allocator().dupe(u8, renamed);
            try self.var_renames.put(vararg_name, renamed_copy);
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
    // Add __name__ and __dict__ fields for Python function attribute compatibility
    try self.output.writer(self.allocator).print("    __name__: []const u8 = \"{s}\",\n", .{func.name});
    try self.emit("    __dict__: ?*anyopaque = null,\n");
    // Add __isabstractmethod__ field - always present (Python accesses this on all callables)
    // Set to true only if function has @abstractmethod decorator
    if (hasAbstractmethodDecorator(func.decorators)) {
        try self.emit("    __isabstractmethod__: bool = true,\n");
    } else {
        try self.emit("    __isabstractmethod__: bool = false,\n");
    }
    try self.emit("    pub fn call(_: @This()");

    // Parameter list for wrapper
    const wrapper_id = self.name_gen.nextId();
    var param_names = std.ArrayList([]const u8){};
    defer {
        for (param_names.items) |name| self.allocator.free(name);
        param_names.deinit(self.allocator);
    }

    for (func.args) |arg| {
        const unique_name = try std.fmt.allocPrint(
            self.allocator,
            "__m{d}_p_{s}",
            .{ wrapper_id, arg.name },
        );
        try param_names.append(self.allocator, unique_name);
        try self.output.writer(self.allocator).print(", {s}: anytype", .{unique_name});
    }

    if (func.vararg) |vararg_name| {
        const vararg_param_name = try std.fmt.allocPrint(
            self.allocator,
            "__m{d}_p_{s}",
            .{ wrapper_id, vararg_name },
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
    const func_name_copy = try self.arena.allocator().dupe(u8, func.name);
    try self.closure_vars.put(func_name_copy, {});
}

/// Check if an AST node contains generator expressions that would compile to runtime.eval()
/// and thus not actually use referenced variables in the generated Zig code
fn containsEvalComprehension(node: ast.Node) bool {
    return switch (node) {
        // Generator expressions compile to runtime.eval()
        .genexp => true,

        // Return statement may contain a comprehension
        .return_stmt => |r| if (r.value) |v| containsEvalComprehensionExpr(v.*) else false,

        // Expression statement may contain a comprehension
        .expr_stmt => |e| containsEvalComprehensionExpr(e.value.*),

        // Assign may have comprehension on right side
        .assign => |a| containsEvalComprehensionExpr(a.value.*),

        // Check compound statements recursively
        .if_stmt => |i| blk: {
            for (i.body) |s| if (containsEvalComprehension(s)) break :blk true;
            for (i.else_body) |s| if (containsEvalComprehension(s)) break :blk true;
            break :blk false;
        },
        .for_stmt => |f| blk: {
            for (f.body) |s| if (containsEvalComprehension(s)) break :blk true;
            if (f.orelse_body) |ob| for (ob) |s| if (containsEvalComprehension(s)) break :blk true;
            break :blk false;
        },
        .while_stmt => |w| blk: {
            for (w.body) |s| if (containsEvalComprehension(s)) break :blk true;
            if (w.orelse_body) |ob| for (ob) |s| if (containsEvalComprehension(s)) break :blk true;
            break :blk false;
        },
        .try_stmt => |t| blk: {
            for (t.body) |s| if (containsEvalComprehension(s)) break :blk true;
            for (t.handlers) |h| for (h.body) |s| if (containsEvalComprehension(s)) break :blk true;
            for (t.else_body) |s| if (containsEvalComprehension(s)) break :blk true;
            for (t.finalbody) |s| if (containsEvalComprehension(s)) break :blk true;
            break :blk false;
        },
        .with_stmt => |w| blk: {
            for (w.body) |s| if (containsEvalComprehension(s)) break :blk true;
            break :blk false;
        },
        else => false,
    };
}

/// Check if an expression node contains eval comprehensions
fn containsEvalComprehensionExpr(node: ast.Node) bool {
    return switch (node) {
        .genexp => true,
        .call => |c| blk: {
            // Check call arguments
            for (c.args) |arg| if (containsEvalComprehensionExpr(arg)) break :blk true;
            break :blk false;
        },
        .tuple => |t| blk: {
            for (t.elts) |e| if (containsEvalComprehensionExpr(e)) break :blk true;
            break :blk false;
        },
        .list => |l| blk: {
            for (l.elts) |e| if (containsEvalComprehensionExpr(e)) break :blk true;
            break :blk false;
        },
        .binop => |b| containsEvalComprehensionExpr(b.left.*) or containsEvalComprehensionExpr(b.right.*),
        .unaryop => |u| containsEvalComprehensionExpr(u.operand.*),
        else => false,
    };
}
