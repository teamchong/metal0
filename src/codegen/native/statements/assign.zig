/// Assignment and expression statement code generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const NativeType = @import("../../../analysis/native_types/core.zig").NativeType;
const helpers = @import("assign_helpers.zig");
const comptimeHelpers = @import("assign_comptime.zig");
const deferCleanup = @import("assign_defer.zig");
const typeHandling = @import("assign/type_handling.zig");
const valueGen = @import("assign/value_generation.zig");
const zig_keywords = @import("zig_keywords");

// Re-export submodules
pub const genAugAssign = @import("assign/aug_assign.zig").genAugAssign;
pub const genExprStmt = @import("assign/expr_stmt.zig").genExprStmt;

/// Check if an expression results in a BigInt
/// This detects expressions that produce BigInt values at runtime
fn isBigIntExpression(expr: ast.Node) bool {
    // Left shift with non-comptime RHS produces BigInt
    if (expr == .binop and expr.binop.op == .LShift) {
        const rhs = expr.binop.right.*;
        // If RHS is not a constant int, it's not comptime-known
        // so we generate BigInt for safety
        if (rhs != .constant or rhs.constant.value != .int) {
            return true;
        }
        // If RHS is a large constant, also needs BigInt
        if (rhs.constant.value.int >= 63) {
            return true;
        }
    }
    // int() call with non-literal argument could produce BigInt
    // e.g., int(s) where s is a string variable (could be from file/input)
    if (expr == .call and expr.call.func.* == .name) {
        if (std.mem.eql(u8, expr.call.func.name.id, "int")) {
            if (expr.call.args.len >= 1) {
                const arg = expr.call.args[0];
                // If argument is not a literal, it's runtime and could be large
                if (arg != .constant) {
                    return true;
                }
            }
        }
    }
    // Recursively check nested expressions
    if (expr == .binop) {
        if (isBigIntExpression(expr.binop.left.*)) return true;
        if (isBigIntExpression(expr.binop.right.*)) return true;
    }
    return false;
}

/// Generate annotated assignment statement (x: int = 5)
pub fn genAnnAssign(self: *NativeCodegen, ann_assign: ast.Node.AnnAssign) CodegenError!void {
    // If no value, just a declaration (x: int), skip for now
    if (ann_assign.value == null) return;

    // Convert to regular assignment and process
    const targets = try self.allocator.alloc(ast.Node, 1);
    targets[0] = ann_assign.target.*;

    const assign = ast.Node.Assign{
        .targets = targets,
        .value = ann_assign.value.?,
    };
    try genAssign(self, assign);

    // Free the temporary targets allocation
    self.allocator.free(targets);
}

/// Check if an expression is a typing module call that should be a no-op
/// e.g., TypeVar('T'), Generic, etc.
fn isTypingNoOp(expr: ast.Node) bool {
    if (expr != .call) return false;
    const call = expr.call;
    if (call.func.* != .name) return false;
    const name = call.func.name.id;
    // TypeVar, ParamSpec, TypeVarTuple are all type hint constructors
    return std.mem.eql(u8, name, "TypeVar") or
        std.mem.eql(u8, name, "ParamSpec") or
        std.mem.eql(u8, name, "TypeVarTuple");
}

/// Generate assignment statement with automatic defer cleanup
pub fn genAssign(self: *NativeCodegen, assign: ast.Node.Assign) CodegenError!void {
    // Skip typing module assignments (TypeVar, etc.)
    // T = TypeVar('T') should be a no-op at runtime
    if (isTypingNoOp(assign.value.*)) {
        try self.emitIndent();
        try self.emit("// type hint: ");
        for (assign.targets) |target| {
            if (target == .name) {
                try self.emit(target.name.id);
            }
        }
        try self.emit("\n");
        return;
    }

    // Infer type from the current value expression
    var value_type = try self.inferExprScoped(assign.value.*);
    const original_expr_type = value_type; // Keep for class_instance shadowing detection

    // For variable declarations and reassignments, use the scoped widened type
    // from the type inferrer. This ensures the variable can hold all values
    // that will be assigned to it within the same function scope.
    // The type inferrer's scoped map contains the widened type from ALL assignments
    // to this variable in the current function.
    // EXCEPTION: For class_instance types, don't widen if the actual expression type
    // is a DIFFERENT class. This allows proper shadowing detection later.
    for (assign.targets) |target| {
        if (target == .name) {
            const var_name = target.name.id;
            // Look up the scoped widened type (from current function's analysis)
            // This handles widening like: x = int(s); x = int(1e100)
            // where x needs to be BigInt to hold both values
            if (self.type_inferrer.getScopedVar(var_name)) |scoped_type| {
                if (scoped_type != .unknown) {
                    // Don't widen for class_instance types that differ - need actual type for shadowing
                    const skip_widening = scoped_type == .class_instance and
                        original_expr_type == .class_instance and
                        !std.mem.eql(u8, scoped_type.class_instance, original_expr_type.class_instance);
                    if (!skip_widening) {
                        value_type = scoped_type;
                        break;
                    }
                }
            }
        }
    }

    // Track variables assigned from BigInt expressions
    // This handles cases like: hibit = 1 << (bits - 1) where bits is not comptime
    // We need to know hibit is BigInt for subsequent operations like hibit | x
    if (isBigIntExpression(assign.value.*)) {
        for (assign.targets) |target| {
            if (target == .name) {
                try self.bigint_vars.put(target.name.id, {});
            }
        }
    }

    // Track variables assigned from nested class constructor calls
    // This handles cases like: x = MyClass(1) where MyClass is defined in the same function
    // We need to know x is a MyClass instance for subsequent attribute accesses like x.val
    if (assign.value.* == .call and assign.value.call.func.* == .name) {
        const class_name = assign.value.call.func.name.id;
        if (self.nested_class_names.contains(class_name)) {
            for (assign.targets) |target| {
                if (target == .name) {
                    try self.nested_class_instances.put(target.name.id, class_name);
                    // Also register in type_inferrer's scoped variables for proper type lookup
                    try self.type_inferrer.putScopedVar(target.name.id, .{ .class_instance = class_name });
                }
            }
        }
    }

    // Track C extension module call results: arr = np.array([1,2,3])
    // When a variable is assigned from a C extension module function call,
    // track it as pyobject type for method call dispatch
    if (assign.value.* == .call and assign.value.call.func.* == .attribute) {
        const attr = assign.value.call.func.attribute;
        if (attr.value.* == .name) {
            const module_name = attr.value.name.id;
            if (self.isCExtensionModule(module_name)) {
                for (assign.targets) |target| {
                    if (target == .name) {
                        // Track as pyobject for method call dispatch
                        const key = try self.allocator.dupe(u8, target.name.id);
                        try self.type_inferrer.putScopedVar(key, .{ .pyobject = module_name });
                    }
                }
            }
        }
    }

    // Track ctypes function references: strlen = libc.strlen
    // When a variable is assigned from CDLL attribute access, track it for argtypes/restype
    // The assignment itself is a no-op - we generate the lookup at call sites
    if (assign.value.* == .attribute) {
        const attr_val = assign.value.attribute;
        if (attr_val.value.* == .name) {
            const lib_var = attr_val.value.name.id;
            const lib_type = try self.inferExprScoped(attr_val.value.*);
            if (lib_type == .cdll) {
                for (assign.targets) |target| {
                    if (target == .name) {
                        const var_name = target.name.id;
                        const func_name = attr_val.attr;
                        // Create ctypes function info with default types
                        const info = @import("../main/core.zig").CTypesFuncInfo{
                            .library_var = try self.allocator.dupe(u8, lib_var),
                            .func_name = try self.allocator.dupe(u8, func_name),
                            .argtypes = &[_][]const u8{},
                            .restype = try self.allocator.dupe(u8, "c_int"), // Default return type
                        };
                        const key = try self.allocator.dupe(u8, var_name);
                        try self.ctypes_functions.put(key, info);
                    }
                }
                // ctypes function assignment is a no-op - emit comment and return
                try self.emitIndent();
                try self.emit("// ctypes function reference tracked at compile time\n");
                return;
            }
        }
    }

    // Handle tuple unpacking: a, b = (1, 2)
    // Note: Parser may represent tuple targets as either .tuple or .list
    if (assign.targets.len == 1 and assign.targets[0] == .tuple) {
        const target_tuple = assign.targets[0].tuple;
        try valueGen.genTupleUnpack(self, assign, target_tuple);
        return;
    }
    if (assign.targets.len == 1 and assign.targets[0] == .list) {
        // List target unpacking: [a, b] = x or a, b = x (parsed as list)
        const target_list = assign.targets[0].list;
        try valueGen.genListUnpack(self, assign, target_list);
        return;
    }

    for (assign.targets) |target| {
        if (target == .name) {
            var var_name = target.name.id;
            const original_var_name = var_name; // Keep for usage checks (before any renaming)

            // Rename 'self' to '__self' inside nested class methods to avoid
            // shadowing the outer function's 'self' parameter
            // e.g., inside StrWithStr.__new__: self = str.__new__(cls, "") -> __self = ...
            if (std.mem.eql(u8, var_name, "self") and self.method_nesting_depth > 0) {
                var_name = "__self";
            }

            // Check if assigning to a for-loop capture variable
            // In Zig, loop captures are immutable, so we need to rename: line = line.strip()
            // becomes __loop_line = line.strip() and subsequent refs use __loop_line
            // NOTE: We set the rename AFTER generating the value, so the RHS uses the original capture
            const is_loop_capture_reassign = self.loop_capture_vars.contains(var_name);
            const loop_renamed_name = if (is_loop_capture_reassign)
                std.fmt.allocPrint(self.allocator, "__loop_{s}", .{var_name}) catch var_name
            else
                var_name;
            if (is_loop_capture_reassign) {
                var_name = loop_renamed_name;
            }

            // Check if this is assigning a type attribute to a variable with the same name
            // e.g., int_class = self.int_class -> would shadow the int_class function
            // In this case, rename the local variable to avoid shadowing
            if (assign.value.* == .attribute) {
                const attr = assign.value.attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                    if (std.mem.eql(u8, attr.attr, var_name)) {
                        // Check if this is a type attribute
                        if (self.current_class_name) |class_name| {
                            const type_attr_key = std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class_name, var_name }) catch null;
                            if (type_attr_key) |key| {
                                if (self.class_type_attrs.get(key)) |_| {
                                    // Rename the local variable to avoid shadowing
                                    const renamed = std.fmt.allocPrint(self.allocator, "_local_{s}", .{var_name}) catch var_name;
                                    try self.var_renames.put(var_name, renamed);
                                    var_name = renamed;
                                }
                            }
                        }
                    }
                }
            }

            // Track nested class instances: obj = Inner() -> obj is instance of Inner
            // This is used to pass allocator to method calls on nested class instances
            // and to identify class instances for pass-by-reference semantics
            if (assign.value.* == .call) {
                const call_value = assign.value.call;
                if (call_value.func.* == .name) {
                    const class_name = call_value.func.name.id;
                    // Check both nested_class_names (all nested classes) and
                    // nested_class_captures (nested classes with captured vars)
                    if (self.nested_class_names.contains(class_name) or
                        self.nested_class_captures.contains(class_name))
                    {
                        // This is a nested class constructor call
                        try self.nested_class_instances.put(var_name, class_name);
                    }
                }
            }

            // Special case: ellipsis assignment (x = ...)
            // Emit as explicit discard to avoid "unused variable" error
            if (assign.value.* == .ellipsis_literal) {
                try self.emitIndent();
                try self.emit("_ = ");
                try self.genExpr(assign.value.*);
                try self.emit(";\n");
                return;
            }

            // Skip import_module and get_feature_macros assignments
            // These are already emitted at module level as const
            if (self.import_module_vars.contains(var_name) and self.isDeclared(var_name)) {
                return;
            }

            // Also check for get_feature_macros call specifically
            if (assign.value.* == .call) {
                const call_val = assign.value.call;
                if (call_val.func.* == .name) {
                    if (std.mem.eql(u8, call_val.func.name.id, "get_feature_macros")) {
                        if (self.isDeclared(var_name)) {
                            return;
                        }
                    }
                }
            }

            // Track operator module callable structs: mod = operator.mod, pow_op = operator.pow
            // These become callable structs that need .call() syntax when invoked
            if (assign.value.* == .attribute) {
                const attr_val = assign.value.attribute;
                if (attr_val.value.* == .name) {
                    const module_name = attr_val.value.name.id;
                    if (std.mem.eql(u8, module_name, "operator")) {
                        if (std.mem.eql(u8, attr_val.attr, "mod") or std.mem.eql(u8, attr_val.attr, "pow")) {
                            // Register as callable variable so calls use .call() syntax
                            const owned_name = try self.allocator.dupe(u8, var_name);
                            try self.callable_vars.put(owned_name, {});
                        }
                    }
                }
            }

            // Special case: float.fromhex and float.hex are function references
            // Generate as assignment without type (works for both new vars and reassignment)
            if (assign.value.* == .attribute) {
                const attr_val = assign.value.attribute;
                if (attr_val.value.* == .name) {
                    const name = attr_val.value.name.id;
                    if (std.mem.eql(u8, name, "float")) {
                        if (std.mem.eql(u8, attr_val.attr, "fromhex") or std.mem.eql(u8, attr_val.attr, "hex")) {
                            // Callable globals are already emitted at module level in generator.zig
                            // Skip if this is a callable global that's already been handled
                            if (self.callable_global_vars.contains(var_name) and self.isDeclared(var_name)) {
                                return; // Already emitted at module level
                            }
                            // Check if already declared (local scope only for functions)
                            // Global callable vars are NOT pre-declared (skipped in generator.zig)
                            // so first assignment of a global callable needs 'var' keyword
                            const is_local_declared = self.isDeclared(var_name);
                            const is_global = self.isGlobalVar(var_name);
                            const needs_declaration = !is_local_declared;
                            try self.emitIndent();
                            if (needs_declaration) {
                                // Use 'var' for global callables (can be reassigned)
                                // Use 'const' for local callables
                                try self.emit(if (is_global) "var " else "const ");
                            }
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                            try self.emit(" = ");
                            try self.genExpr(assign.value.*);
                            try self.emit(";\n");
                            if (needs_declaration) {
                                try self.declareVar(var_name);
                            }
                            return;
                        }
                    }
                }
            }

            // Set current assignment target for type-aware empty list generation
            self.current_assign_target = var_name;
            defer self.current_assign_target = null;

            // Check collection types and allocation behavior
            const is_constant_array = typeHandling.isConstantArray(self, assign, var_name);
            const is_arraylist = typeHandling.isArrayList(self, assign, var_name);
            const is_listcomp = (assign.value.* == .listcomp);
            const is_dict = (assign.value.* == .dict);
            _ = assign.value.* == .dictcomp; // is_dictcomp - reserved for future use
            const is_allocated_string = typeHandling.isAllocatedString(self, assign.value.*);
            const is_mutable_class_instance = typeHandling.isMutableClassInstance(self, assign.value.*);

            // Track pending shadow rename - applied AFTER RHS generation to avoid self-reference issues
            // e.g., object = Class(object) must use OLD object value on RHS, not the new shadow name
            var pending_shadow_rename: ?struct { old_name: []const u8, new_name: []const u8 } = null;

            // Check if value is an iter() call - iterators need to be mutable for next() to work
            const is_iterator = typeHandling.isIteratorCall(assign.value.*);

            // Check if this is first assignment or reassignment
            // Hoisted variables should skip declaration (already declared before try block)
            // Global variables should also skip declaration (they're declared in outer scope)
            const is_hoisted = self.hoisted_vars.contains(var_name);
            const is_global = self.isGlobalVar(var_name);
            const is_first_assignment = !self.isDeclared(var_name) and !is_hoisted and !is_global;

            // Try compile-time evaluation FIRST
            // Skip comptime eval for variables typed as bigint (need runtime BigInt.fromInt)
            if (value_type != .bigint) {
                if (self.comptime_evaluator.tryEval(assign.value.*)) |comptime_val| {
                    // Only apply for simple types (no strings/lists that allocate during evaluation)
                    // TODO: Strings and lists need proper arena allocation to avoid memory leaks
                    const is_simple_type = switch (comptime_val) {
                        .int, .float, .bool => true,
                        .string, .list => false,
                    };

                    if (is_simple_type) {
                        // Check mutability BEFORE emitting
                        // Use isVarMutated() to check both module-level AND function-local mutations
                        const is_mutable = if (is_first_assignment)
                            self.isVarMutated(var_name)
                        else
                            false; // Reassignments don't declare

                        // Successfully evaluated at compile time!
                        try comptimeHelpers.emitComptimeAssignment(self, var_name, comptime_val, is_first_assignment, is_mutable);
                        if (is_first_assignment) {
                            // Declare with proper type for scope-aware type lookup
                            try self.declareVarWithType(var_name, value_type);
                        }

                        // If variable is used in eval string but nowhere else in actual code,
                        // emit _ = varname; to suppress Zig "unused" warning
                        // Use original_var_name for check, but emit renamed var_name
                        if (self.isEvalStringVar(original_var_name)) {
                            try self.emitIndent();
                            try self.emit("_ = ");
                            try self.emit(var_name);
                            try self.emit(";\n");
                        }

                        return;
                    }
                    // Fall through to runtime codegen for strings/lists
                    // Don't free - these are either AST-owned or will leak (TODO: arena)
                }
            }

            try self.emitIndent();

            // For unused variables, either skip the statement or discard with _ = expr;
            // Use original_var_name since usage analysis uses the original Python variable name
            if (is_first_assignment and self.isVarUnused(original_var_name)) {
                // Check if value expression has side effects
                // Simple name/constant references have no side effects - skip entirely
                // Calls, list/dict literals with calls, etc. have side effects - execute them
                const has_side_effects = switch (assign.value.*) {
                    .name, .constant => false,
                    else => true,
                };

                if (!has_side_effects) {
                    // No side effects - skip the entire statement
                    return;
                }

                if (value_type == .unknown) {
                    // PyObject: capture in block and decref immediately
                    // { const __unused = expr; runtime.decref(__unused, __global_allocator); }
                    try self.emit("{ const __unused = ");
                    try self.genExpr(assign.value.*);
                    try self.emit("; runtime.decref(__unused, __global_allocator); }\n");
                } else {
                    try self.emit("_ = ");
                    try self.genExpr(assign.value.*);
                    try self.emit(";\n");
                }
                // Don't declare - variable doesn't exist
                return;
            }

            if (is_first_assignment) {
                // Special handling for y = x where x is ArrayList
                // In Python, y = x makes y an alias (reference) to the same list
                // Generate: const y = &x (pointer to x)
                if (assign.value.* == .name) {
                    const rhs_name = assign.value.name.id;
                    // Check if the inferred type is a list (not just if variable was ever ArrayList)
                    // This ensures we don't alias class instances even if a previous function had same var name
                    const is_rhs_list_type = value_type == .list or value_type == .array;
                    const is_rhs_arraylist = is_rhs_list_type and (self.isArrayListVar(rhs_name) or self.arraylist_aliases.contains(rhs_name));
                    if (is_rhs_arraylist) {
                        // Track y as an alias pointing to x
                        const var_name_copy = try self.allocator.dupe(u8, var_name);
                        const rhs_name_copy = try self.allocator.dupe(u8, rhs_name);
                        try self.arraylist_aliases.put(var_name_copy, rhs_name_copy);

                        // Generate const pointer assignment: const y = &x
                        // Always use const - if y is reassigned to different type, we shadow it
                        try self.emit("const ");
                        try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), var_name);
                        try self.emit(" = &");
                        try self.genExpr(assign.value.*);
                        try self.emit(";\n");

                        // Mark as declared
                        try self.declareVarWithType(var_name, value_type);
                        return;
                    }

                    // For nested class instances (heap-allocated pointers), y = x simply copies the pointer
                    // This is handled by normal assignment - no special case needed since
                    // nested classes now return *@This() from init(), so x is already a pointer
                }

                // First assignment: emit var/const declaration with type annotation
                try valueGen.emitVarDeclaration(
                    self,
                    var_name,
                    value_type,
                    is_arraylist,
                    is_dict,
                    is_mutable_class_instance,
                    is_listcomp,
                    is_iterator,
                );

                // Mark as declared with proper type for scope-aware type lookup
                try self.declareVarWithType(var_name, value_type);

                // Track array slice vars
                const is_array_slice = typeHandling.isArraySlice(self, assign.value.*);
                if (is_array_slice) {
                    const var_name_copy = try self.allocator.dupe(u8, var_name);
                    try self.array_slice_vars.put(var_name_copy, {});
                }

            } else {
                // Reassignment: x = value (no var/const keyword!)
                // EXCEPTION: If the new type differs from the declared type (e.g., different struct),
                // we need to shadow the variable with a new const declaration
                const declared_type = self.getLocalVarType(var_name) orelse .unknown;
                const new_type = value_type;

                // Check if we're assigning a different class type (needs variable shadowing)
                // This handles reassignments like: u = Class1(); u = Class2()
                // In Zig, we can't change a variable's type, so we shadow with a new const
                const needs_shadow = blk: {
                    // Collection type transitions: list <-> dict, array <-> hashmap
                    // These are fundamentally incompatible in Zig
                    const declared_tag = @as(std.meta.Tag(NativeType), declared_type);
                    const new_tag = @as(std.meta.Tag(NativeType), new_type);

                    // List/array to dict/set transition
                    if ((declared_tag == .list or declared_tag == .array) and
                        (new_tag == .dict or new_tag == .set))
                    {
                        break :blk true;
                    }
                    // Dict/set to list/array transition
                    if ((declared_tag == .dict or declared_tag == .set) and
                        (new_tag == .list or new_tag == .array))
                    {
                        break :blk true;
                    }

                    if (declared_type == .class_instance and new_type == .class_instance) {
                        // Different class instances - need shadow
                        if (!std.mem.eql(u8, declared_type.class_instance, new_type.class_instance)) {
                            break :blk true;
                        }
                    }
                    // Primitive type being reassigned to class instance
                    // e.g., value = float('nan'); value = F('nan') where F(float, H)
                    // In Python, F inherits from float but in Zig they're different types
                    if (new_type == .class_instance) {
                        // Was a primitive type (int, float, bool, string) but now is class instance
                        if (declared_type == .int or declared_type == .float or
                            declared_type == .bool or declared_type == .string)
                        {
                            break :blk true;
                        }
                    }
                    // Struct-typed variable being reassigned a different struct
                    if (assign.value.* == .call and assign.value.call.func.* == .name) {
                        const call_name = assign.value.call.func.name.id;

                        // Check if this is a nested class (lowercase names like 'subclass')
                        // or a regular class (uppercase names like 'Foo')
                        const is_nested_class = self.nested_class_names.contains(call_name);
                        const is_uppercase_class = call_name.len > 0 and std.ascii.isUpper(call_name[0]);

                        if (is_nested_class or is_uppercase_class) {
                            // Class constructor call - check if different from original
                            if (declared_type == .class_instance) {
                                if (!std.mem.eql(u8, declared_type.class_instance, call_name)) {
                                    break :blk true;
                                }
                            } else if (is_nested_class) {
                                // First assignment was also a nested class but type wasn't tracked
                                // as class_instance. Check if call names differ.
                                // This handles: u = subclass(); u = subclass_with_init()
                                // where declared_type might be .unknown
                                if (declared_type == .unknown) {
                                    break :blk true; // Different nested class, need shadow
                                }
                            }
                            // Also shadow if declared as primitive but now assigning nested class
                            if (declared_type == .int or declared_type == .float or
                                declared_type == .bool or declared_type == .string)
                            {
                                break :blk true;
                            }
                        }
                    }
                    break :blk false;
                };

                if (needs_shadow) {
                    // Check if this is an alias being reassigned to a different type
                    // y = x where y was a pointer alias and x's type changed
                    const is_alias_reassign = self.arraylist_aliases.contains(var_name) and assign.value.* == .name;
                    if (is_alias_reassign) {
                        const rhs_name = assign.value.name.id;
                        const is_rhs_list_type = new_type == .list or new_type == .array;
                        const is_rhs_arraylist = is_rhs_list_type and (self.isArrayListVar(rhs_name) or self.arraylist_aliases.contains(rhs_name));
                        if (is_rhs_arraylist) {
                            // Shadow the alias - generate new pointer variable
                            const unique_suffix = self.output.items.len;
                            const unique_name = std.fmt.allocPrint(self.allocator, "{s}__{d}", .{ var_name, unique_suffix }) catch var_name;

                            // Don't emit _ = y - original alias is const and likely already used
                            // Just declare the new shadow alias
                            try self.emit("const ");
                            try self.emit(unique_name);
                            try self.emit(" = &");
                            try self.genExpr(assign.value.*);
                            try self.emit(";\n");

                            // Update alias tracking and renames
                            const unique_name_copy = try self.allocator.dupe(u8, unique_name);
                            const rhs_name_copy = try self.allocator.dupe(u8, rhs_name);
                            try self.arraylist_aliases.put(unique_name_copy, rhs_name_copy);
                            try self.var_renames.put(var_name, unique_name);
                            try self.declareVarWithType(var_name, new_type);
                            try self.declareVarWithType(unique_name, new_type);
                            return;
                        }
                    }

                    // Generate a unique name for this new type
                    // Use the output buffer length as a unique suffix
                    const unique_suffix = self.output.items.len;
                    const unique_name = std.fmt.allocPrint(self.allocator, "{s}__{d}", .{ var_name, unique_suffix }) catch var_name;

                    // Mark the original variable as used to prevent "var never mutated" warning
                    // The original var was declared as mutable because we detected a reassignment,
                    // but since this reassignment creates a shadow (type change), the original
                    // is never actually mutated. Use _ = &var; to suppress the warning.
                    try self.emit("_ = &");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                    try self.emit(";\n");
                    try self.emitIndent();

                    // For nested class instances (heap-allocated), shadowing works normally
                    // since x is already a pointer (*ClassName), y = x copies the pointer

                    // Check if the shadow variable will be aug_assigned (e.g., x += 1)
                    // Only aug_assign needs var, regular multi-assignment doesn't (uses shadowing)
                    const shadow_is_mutable = self.isVarAugAssigned(var_name);
                    try self.emit(if (shadow_is_mutable) "var " else "const ");
                    try self.emit(unique_name);
                    try self.emit(" = ");

                    // DEFER rename registration until AFTER RHS is generated!
                    // This prevents self-referential issues like: object = Class(object)
                    // where RHS needs the OLD value of object, not the new shadowed name.
                    // The rename will be applied after genExpr() below.
                    pending_shadow_rename = .{ .old_name = var_name, .new_name = unique_name };

                    // Declare type for BOTH the original name and unique name
                    // Original name: needed for tracking
                    // Unique name: needed for type inference when lookups use the renamed variable
                    try self.declareVarWithType(var_name, new_type);
                    try self.declareVarWithType(unique_name, new_type);
                } else {
                    // Check if this is reassigning an alias (y = x where y was previously an alias)
                    // When reassigning an alias, we need to update the pointer: y = &x
                    if (self.arraylist_aliases.contains(var_name) and assign.value.* == .name) {
                        const rhs_name = assign.value.name.id;
                        const is_rhs_list_type = value_type == .list or value_type == .array;
                        const is_rhs_arraylist = is_rhs_list_type and (self.isArrayListVar(rhs_name) or self.arraylist_aliases.contains(rhs_name));
                        if (is_rhs_arraylist) {
                            // Update alias to point to new target
                            const var_name_copy = try self.allocator.dupe(u8, var_name);
                            const rhs_name_copy = try self.allocator.dupe(u8, rhs_name);
                            try self.arraylist_aliases.put(var_name_copy, rhs_name_copy);

                            // Generate pointer reassignment: y = &x
                            try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), var_name);
                            try self.emit(" = &");
                            try self.genExpr(assign.value.*);
                            try self.emit(";\n");
                            return;
                        }
                    }

                    // Normal reassignment
                    // Use renamed version if in var_renames map (for exception handling)
                    const actual_name = self.var_renames.get(var_name) orelse var_name;

                    // Skip type-changing assignments for anytype parameters
                    // Pattern: other = Rat(other) where other is anytype and RHS is constructor
                    // This is incompatible with Zig's type system - will be handled by comptime branching
                    const is_anytype = self.anytype_params.contains(var_name);
                    if (is_anytype) {
                        // Check if RHS is a constructor call (class instantiation)
                        if (assign.value.* == .call) {
                            if (assign.value.call.func.* == .name) {
                                const func_name = assign.value.call.func.name.id;
                                // Check if it's a class constructor (starts with uppercase or is a known class)
                                if (func_name.len > 0 and std.ascii.isUpper(func_name[0])) {
                                    // Skip this assignment - it would change the type
                                    try self.emitIndent();
                                    try self.emit("_ = ");
                                    try self.genExpr(assign.value.*);
                                    try self.emit("; // Type-changing assignment skipped\n");
                                    return;
                                }
                            }
                        }
                    }

                    // Use writeEscapedIdent to handle Zig keywords (e.g., "packed" -> @"packed")
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), actual_name);
                    try self.emit(" = ");
                    // No type annotation on reassignment
                }
            }

            // Special handling for string concatenation with nested operations
            // s1 + " " + s2 needs intermediate temps
            if (assign.value.* == .binop and assign.value.binop.op == .Add) {
                const left_type = try self.inferExprScoped(assign.value.binop.left.*);
                const right_type = try self.inferExprScoped(assign.value.binop.right.*);
                if (left_type == .string or right_type == .string) {
                    try valueGen.genStringConcat(self, assign, var_name, is_first_assignment);
                    return;
                }
            }

            // Special handling for list literals that will be mutated
            // Generate ArrayList initialization directly instead of fixed array
            if (is_arraylist and assign.value.* == .list) {
                const list = assign.value.list;
                try valueGen.genArrayListInit(self, var_name, list);

                // Add defer cleanup
                try deferCleanup.emitDeferCleanups(
                    self,
                    var_name,
                    is_first_assignment,
                    is_arraylist,
                    is_listcomp,
                    is_dict,
                    is_allocated_string,
                    assign.value.*,
                );
                return;
            }

            // Special handling for bigint variable assignments
            // When variable is typed as bigint OR has unbounded int (could overflow i64),
            // we need to convert values to BigInt
            const needs_bigint = value_type == .bigint or
                (value_type == .int and value_type.int.needsBigInt());
            if (needs_bigint) {
                // Infer the type of the current value expression
                const current_value_type = try self.inferExprScoped(assign.value.*);

                // If current value is int-typed, convert to BigInt
                if (current_value_type == .int) {
                    // Check if this is an int() call - use parseIntToBigInt directly
                    // to avoid overflow when parsing very large strings like int('1' * 600)
                    if (assign.value.* == .call and assign.value.call.func.* == .name and
                        std.mem.eql(u8, assign.value.call.func.name.id, "int"))
                    {
                        const int_call = assign.value.call;
                        if (int_call.args.len >= 1) {
                            // int(string) or int(string, base) -> use parseIntToBigInt
                            try self.emit("(try runtime.parseIntToBigInt(__global_allocator, ");
                            try self.genExpr(int_call.args[0]);
                            try self.emit(", ");
                            if (int_call.args.len >= 2) {
                                try self.emit("@intCast(");
                                try self.genExpr(int_call.args[1]);
                                try self.emit(")");
                            } else {
                                try self.emit("10");
                            }
                            try self.emit("));\n");

                            // Track variable metadata
                            try valueGen.trackVariableMetadata(
                                self,
                                var_name,
                                is_first_assignment,
                                is_constant_array,
                                typeHandling.isArraySlice(self, assign.value.*),
                                assign,
                            );
                            return;
                        }
                    }

                    // Small integer constants can use fromInt (i64)
                    // Other int expressions (arithmetic, int(string), etc.) may produce i128
                    if (assign.value.* == .constant) {
                        try self.emit("(runtime.BigInt.fromInt(__global_allocator, ");
                    } else {
                        try self.emit("(runtime.BigInt.fromInt128(__global_allocator, ");
                    }
                    try self.genExpr(assign.value.*);
                    try self.emit(") catch unreachable);\n");

                    // Track variable metadata
                    try valueGen.trackVariableMetadata(
                        self,
                        var_name,
                        is_first_assignment,
                        is_constant_array,
                        typeHandling.isArraySlice(self, assign.value.*),
                        assign,
                    );
                    return;
                }
                // If current value is already bigint, emit normally
            }

            // Check if this is an async function call that needs auto-await
            const is_async_call = isAsyncFunctionCall(self, assign.value.*);

            if (is_async_call) {
                // Auto-await: wrap async call with scheduler init + wait + result extraction
                try self.emit("(blk: {\n");
                try self.emitIndent();
                // Initialize scheduler if needed (first async call)
                try self.emit("    if (!runtime.scheduler_initialized) {\n");
                try self.emitIndent();
                try self.emit("        const __num_threads = std.Thread.getCpuCount() catch 8;\n");
                try self.emitIndent();
                try self.emit("        runtime.scheduler = runtime.Scheduler.init(__global_allocator, __num_threads) catch unreachable;\n");
                try self.emitIndent();
                try self.emit("        runtime.scheduler.start() catch unreachable;\n");
                try self.emitIndent();
                try self.emit("        runtime.scheduler_initialized = true;\n");
                try self.emitIndent();
                try self.emit("    }\n");
                try self.emitIndent();
                try self.emit("    const __thread = ");
                try self.genExpr(assign.value.*);
                try self.emit(";\n");
                try self.emitIndent();
                try self.emit("    runtime.scheduler.wait(__thread);\n");
                try self.emitIndent();
                try self.emit("    const __result = __thread.result orelse unreachable;\n");
                try self.emitIndent();
                try self.emit("    break :blk @as(*i64, @ptrCast(@alignCast(__result))).*;\n");
                try self.emitIndent();
                try self.emit("});\n");
            } else {
                // Emit value normally
                try self.genExpr(assign.value.*);
                try self.emit(";\n");
            }

            // Apply pending shadow rename AFTER RHS generation
            // This ensures: object = Class(object) uses OLD object on RHS
            if (pending_shadow_rename) |rename| {
                try self.var_renames.put(rename.old_name, rename.new_name);
            }

            // For iterators, add pointer discard to suppress "never mutated" warnings
            // Some iterator uses pass by value (json.dumps) vs by pointer (next())
            if (is_iterator and is_first_assignment) {
                try self.emitIndent();
                try self.emit("_ = &");
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), var_name);
                try self.emit(";\n");
            }

            // Track variable metadata (ArrayList vars, closures, etc.)
            try valueGen.trackVariableMetadata(
                self,
                var_name,
                is_first_assignment,
                is_constant_array,
                typeHandling.isArraySlice(self, assign.value.*),
                assign,
            );

            // Add defer cleanup based on assignment type
            try deferCleanup.emitDeferCleanups(
                self,
                var_name,
                is_first_assignment,
                is_arraylist,
                is_listcomp,
                is_dict,
                is_allocated_string,
                assign.value.*,
            );

            // Register loop capture rename AFTER value is generated
            // This ensures the RHS uses the original capture, but subsequent reads use the new var
            if (is_loop_capture_reassign) {
                try self.var_renames.put(original_var_name, loop_renamed_name);
                // Also register the type for the renamed variable so type inference works
                // e.g., when checking `not __loop_line` we need to know it's a string
                try self.type_inferrer.var_types.put(loop_renamed_name, value_type);
            }
        } else if (target == .attribute) {
            // Handle attribute assignment (self.x = value or obj.y = value)
            const attr = target.attribute;

            // Check for ctypes argtypes/restype assignment: strlen.argtypes = [...], strlen.restype = c_int
            if (attr.value.* == .name) {
                const var_name = attr.value.name.id;
                if (self.ctypes_functions.get(var_name)) |existing_info| {
                    if (std.mem.eql(u8, attr.attr, "argtypes")) {
                        // Parse argtypes list: [ctypes.c_char_p, ctypes.c_int]
                        if (assign.value.* == .list) {
                            var argtypes_list = std.ArrayList([]const u8){};
                            for (assign.value.list.elts) |elem| {
                                if (elem == .attribute and elem.attribute.value.* == .name) {
                                    if (std.mem.eql(u8, elem.attribute.value.name.id, "ctypes")) {
                                        try argtypes_list.append(self.allocator, try self.allocator.dupe(u8, elem.attribute.attr));
                                    }
                                }
                            }
                            // Update the info with new argtypes
                            const new_info = @import("../main/core.zig").CTypesFuncInfo{
                                .library_var = existing_info.library_var,
                                .func_name = existing_info.func_name,
                                .argtypes = try argtypes_list.toOwnedSlice(self.allocator),
                                .restype = existing_info.restype,
                            };
                            try self.ctypes_functions.put(var_name, new_info);
                        }
                        // argtypes assignment is a no-op in generated code (tracked at compile time)
                        try self.emitIndent();
                        try self.emit("// ctypes argtypes tracked at compile time\n");
                        return;
                    } else if (std.mem.eql(u8, attr.attr, "restype")) {
                        // Parse restype: ctypes.c_int, ctypes.c_size_t, etc.
                        var restype_name: []const u8 = "c_int";
                        if (assign.value.* == .attribute and assign.value.attribute.value.* == .name) {
                            if (std.mem.eql(u8, assign.value.attribute.value.name.id, "ctypes")) {
                                restype_name = assign.value.attribute.attr;
                            }
                        }
                        // Update the info with new restype
                        const new_info = @import("../main/core.zig").CTypesFuncInfo{
                            .library_var = existing_info.library_var,
                            .func_name = existing_info.func_name,
                            .argtypes = existing_info.argtypes,
                            .restype = try self.allocator.dupe(u8, restype_name),
                        };
                        try self.ctypes_functions.put(var_name, new_info);
                        // restype assignment is a no-op in generated code
                        try self.emitIndent();
                        try self.emit("// ctypes restype tracked at compile time\n");
                        return;
                    }
                }
            }

            // Check for module class attribute assignment (e.g., array.array.foo = 1)
            // This is not supported - in Python it would raise TypeError
            if (attr.value.* == .attribute) {
                // Nested attribute like module.class.attr - check if it's a module type
                const inner_attr = attr.value.attribute;
                if (inner_attr.value.* == .name) {
                    // Could be array.array.foo or similar - emit noop
                    try self.emitIndent();
                    try self.emit("// TypeError: cannot set attribute on immutable type\n");
                    return;
                }
            }

            // Check if the value being assigned to is a call expression (e.g., B().x = 0)
            // In this case we need to create a temp variable since Zig doesn't allow
            // assigning to fields of block expressions
            if (attr.value.* == .call) {
                // Generate: { var __tmp_N = B.init(...); __tmp_N.x = value; }
                const tmp_id = self.unpack_counter;
                self.unpack_counter += 1;
                try self.emitIndent();
                try self.emit("{\n");
                self.indent_level += 1;
                try self.emitIndent();
                try self.emitFmt("var __attr_tmp_{d} = ", .{tmp_id});
                try self.genExpr(attr.value.*);
                try self.emit(";\n");
                try self.emitIndent();
                try self.emitFmt("__attr_tmp_{d}.", .{tmp_id});
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
                try self.emit(" = ");
                try self.genExpr(assign.value.*);
                try self.emit(";\n");
                self.indent_level -= 1;
                try self.emitIndent();
                try self.emit("}\n");
                return;
            }

            // Check if this is a dynamic attribute
            const is_dynamic = try isDynamicAttrAssign(self, attr);

            try self.emitIndent();

            // Check for sys.stdout/stderr/argv assignment - these need special handling
            if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "sys")) {
                if (std.mem.eql(u8, attr.attr, "stdout") or std.mem.eql(u8, attr.attr, "stderr")) {
                    try self.emit("runtime.discard(");
                    try self.genExpr(assign.value.*);
                    try self.emit("); // sys.");
                    try self.emit(attr.attr);
                    try self.emit(" assignment is a no-op in metal0\n");
                    return;
                }
                // sys.argv assignment: store in mutable global __sys_argv
                if (std.mem.eql(u8, attr.attr, "argv")) {
                    try self.emit("__sys_argv = ");
                    try self.genExpr(assign.value.*);
                    try self.emit(";\n");
                    return;
                }
            }

            if (is_dynamic) {
                // Dynamic attribute: use __dict__.put() with type wrapping
                // Use @constCast since the object may be declared as const (HashMap stores data via pointers,
                // so @constCast works correctly - the internal data is heap-allocated)
                const dyn_value_type = try self.inferExprScoped(assign.value.*);
                const py_value_tag = switch (dyn_value_type) {
                    .int => "int",
                    .float => "float",
                    .bool => "bool",
                    .string => "string",
                    else => "int", // Default fallback
                };

                try self.emit("try @constCast(&");
                try self.genExpr(attr.value.*);
                try self.emitFmt(".__dict__).put(\"{s}\", runtime.PyValue{{ .{s} = ", .{ attr.attr, py_value_tag });
                try self.genExpr(assign.value.*);
                try self.emit(" })");
            } else {
                // Known attribute: direct assignment
                try self.genExpr(target);
                try self.emit(" = ");
                try self.genExpr(assign.value.*);
            }
            try self.emit(";\n");
        } else if (target == .subscript) {
            // Handle subscript assignment: self.routes[path] = handler, dict[key] = value
            const subscript = target.subscript;

            if (subscript.slice == .index) {
                // Index subscript: arr[idx] = value
                // Determine the container type to generate appropriate code
                const container_type = try self.inferExprScoped(subscript.value.*);

                // Check if this is a nested subscript (chained like arr[0][1][2])
                // Nested subscripts need special handling to avoid block expressions in LHS
                const is_nested = subscript.value.* == .subscript;

                try self.emitIndent();

                if (container_type == .dict) {
                    // Dict assignment: dict.put(key, value)
                    try self.emit("try ");
                    if (is_nested) {
                        try self.genSubscriptLHS(subscript.value.subscript);
                    } else {
                        try self.genExpr(subscript.value.*);
                    }
                    try self.emit(".put(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit(", ");
                    try self.genExpr(assign.value.*);
                    try self.emit(");\n");
                } else if (container_type == .list) {
                    // List assignment: list.items[idx] = value
                    if (is_nested) {
                        try self.genSubscriptLHS(subscript.value.subscript);
                    } else {
                        try self.genExpr(subscript.value.*);
                    }
                    try self.emit(".items[@as(usize, @intCast(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit("))] = ");
                    try self.genExpr(assign.value.*);
                    try self.emit(";\n");
                } else {
                    // Generic array/slice assignment: arr[idx] = value
                    if (is_nested) {
                        try self.genSubscriptLHS(subscript.value.subscript);
                    } else {
                        try self.genExpr(subscript.value.*);
                    }
                    try self.emit("[@as(usize, @intCast(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit("))] = ");
                    try self.genExpr(assign.value.*);
                    try self.emit(";\n");
                }
            } else if (subscript.slice == .slice) {
                // Slice assignment: a[:] = data, a[1:3] = [x, y]
                // This replaces the slice with the contents of the RHS
                const slice = subscript.slice.slice;
                const container_type = try self.inferExprScoped(subscript.value.*);
                const is_full_slice = slice.lower == null and slice.upper == null;

                try self.emitIndent();
                try self.emit("{\n");
                self.indent_level += 1;

                // Get container reference
                try self.emitIndent();
                try self.emit("const __slice_target = &");
                try self.genExpr(subscript.value.*);
                try self.emit(";\n");

                // Get source data
                try self.emitIndent();
                try self.emit("const __slice_src = ");
                try self.genExpr(assign.value.*);
                try self.emit(";\n");

                if (container_type == .list) {
                    if (is_full_slice) {
                        // a[:] = data - replace entire list
                        try self.emitIndent();
                        try self.emit("__slice_target.clearRetainingCapacity();\n");
                        try self.emitIndent();
                        try self.emit("for (__slice_src.items) |__item| {\n");
                        self.indent_level += 1;
                        try self.emitIndent();
                        try self.emit("__slice_target.append(__global_allocator, __item) catch {};\n");
                        self.indent_level -= 1;
                        try self.emitIndent();
                        try self.emit("}\n");
                    } else {
                        // a[start:end] = data - replace slice with new data
                        // Calculate start and end indices
                        try self.emitIndent();
                        if (slice.lower) |lower| {
                            try self.emit("const __slice_start: usize = @intCast(");
                            try self.genExpr(lower.*);
                            try self.emit(");\n");
                        } else {
                            try self.emit("const __slice_start: usize = 0;\n");
                        }

                        try self.emitIndent();
                        if (slice.upper) |upper| {
                            try self.emit("const __slice_end: usize = @intCast(");
                            try self.genExpr(upper.*);
                            try self.emit(");\n");
                        } else {
                            try self.emit("const __slice_end: usize = __slice_target.items.len;\n");
                        }

                        // Remove elements in [start, end) range
                        try self.emitIndent();
                        try self.emit("var __i: usize = __slice_start;\n");
                        try self.emitIndent();
                        try self.emit("while (__i < __slice_end) : (__i += 1) {\n");
                        self.indent_level += 1;
                        try self.emitIndent();
                        try self.emit("_ = __slice_target.orderedRemove(__slice_start);\n");
                        self.indent_level -= 1;
                        try self.emitIndent();
                        try self.emit("}\n");

                        // Insert new elements at start position
                        try self.emitIndent();
                        try self.emit("var __j: usize = 0;\n");
                        try self.emitIndent();
                        try self.emit("for (__slice_src.items) |__item| {\n");
                        self.indent_level += 1;
                        try self.emitIndent();
                        try self.emit("__slice_target.insert(__global_allocator, __slice_start + __j, __item) catch {};\n");
                        try self.emitIndent();
                        try self.emit("__j += 1;\n");
                        self.indent_level -= 1;
                        try self.emitIndent();
                        try self.emit("}\n");
                    }
                } else {
                    // Fixed array/slice: copy items
                    try self.emitIndent();
                    if (slice.lower) |lower| {
                        try self.emit("const __slice_start: usize = @intCast(");
                        try self.genExpr(lower.*);
                        try self.emit(");\n");
                    } else {
                        try self.emit("const __slice_start: usize = 0;\n");
                    }

                    try self.emitIndent();
                    if (slice.upper) |upper| {
                        try self.emit("const __slice_end: usize = @intCast(");
                        try self.genExpr(upper.*);
                        try self.emit(");\n");
                    } else {
                        try self.emit("const __slice_end: usize = __slice_target.len;\n");
                    }

                    try self.emitIndent();
                    try self.emit("const __copy_len = @min(__slice_end - __slice_start, __slice_src.len);\n");
                    try self.emitIndent();
                    try self.emit("@memcpy(__slice_target.*[__slice_start..][0..__copy_len], __slice_src[0..__copy_len]);\n");
                }

                self.indent_level -= 1;
                try self.emitIndent();
                try self.emit("}\n");
            }
        }
    }
}

/// Check if attribute assignment is to a dynamic attribute
fn isDynamicAttrAssign(self: *NativeCodegen, attr: ast.Node.Attribute) !bool {
    // Only check for class instance attributes (self.attr or obj.attr)
    if (attr.value.* != .name) return false;

    const obj_name = attr.value.name.id;

    // Get object type
    const obj_type = try self.inferExprScoped(attr.value.*);

    // Check if it's a class instance
    if (obj_type != .class_instance) return false;

    const class_name = obj_type.class_instance;

    // Check if class has this field (including inherited fields)
    const has_field = blk: {
        // Check own class fields
        if (self.type_inferrer.class_fields.get(class_name)) |info| {
            if (info.fields.get(attr.attr)) |_| {
                break :blk true;
            }
        }
        // Check parent class fields for nested classes
        if (self.nested_class_bases.get(class_name)) |parent_name| {
            if (self.type_inferrer.class_fields.get(parent_name)) |parent_info| {
                if (parent_info.fields.get(attr.attr)) |_| {
                    break :blk true;
                }
            }
        }
        break :blk false;
    };
    if (has_field) {
        return false; // Known field (own or inherited)
    }

    // Check for special module attributes
    if (std.mem.eql(u8, obj_name, "sys")) {
        return false;
    }

    // Unknown field - dynamic attribute
    return true;
}

/// Check if expression is a call to an async function
fn isAsyncFunctionCall(self: *NativeCodegen, expr: ast.Node) bool {
    if (expr != .call) return false;
    const call = expr.call;

    // Only handle direct function calls (name), not method calls
    if (call.func.* != .name) return false;

    const func_name = call.func.name.id;
    return self.async_functions.contains(func_name);
}

// Comptime assignment functions moved to assign_comptime.zig
