/// Assignment and expression statement code generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const helpers = @import("assign_helpers.zig");
const comptimeHelpers = @import("assign_comptime.zig");
const deferCleanup = @import("assign_defer.zig");
const typeHandling = @import("assign/type_handling.zig");
const valueGen = @import("assign/value_generation.zig");
const zig_keywords = @import("zig_keywords");

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

/// Generate assignment statement with automatic defer cleanup
pub fn genAssign(self: *NativeCodegen, assign: ast.Node.Assign) CodegenError!void {
    // Infer type from the current value expression
    var value_type = try self.inferExprScoped(assign.value.*);

    // For variable declarations and reassignments, use the scoped widened type
    // from the type inferrer. This ensures the variable can hold all values
    // that will be assigned to it within the same function scope.
    // The type inferrer's scoped map contains the widened type from ALL assignments
    // to this variable in the current function.
    for (assign.targets) |target| {
        if (target == .name) {
            const var_name = target.name.id;
            // Look up the scoped widened type (from current function's analysis)
            // This handles widening like: x = int(s); x = int(1e100)
            // where x needs to be BigInt to hold both values
            if (self.type_inferrer.getScopedVar(var_name)) |scoped_type| {
                if (scoped_type != .unknown) {
                    value_type = scoped_type;
                    break;
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
            if (assign.value.* == .call) {
                const call_value = assign.value.call;
                if (call_value.func.* == .name) {
                    const class_name = call_value.func.name.id;
                    if (self.nested_class_captures.contains(class_name)) {
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

            // Check collection types and allocation behavior
            const is_constant_array = typeHandling.isConstantArray(self, assign, var_name);
            const is_arraylist = typeHandling.isArrayList(self, assign, var_name);
            const is_listcomp = (assign.value.* == .listcomp);
            const is_dict = (assign.value.* == .dict);
            _ = assign.value.* == .dictcomp; // is_dictcomp - reserved for future use
            const is_allocated_string = typeHandling.isAllocatedString(self, assign.value.*);
            const is_mutable_class_instance = typeHandling.isMutableClassInstance(self, assign.value.*);

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

            // For unused variables, discard with _ = expr; to avoid Zig errors
            // But PyObjects still need decref to free memory (e.g., json.loads)
            // Use original_var_name since usage analysis uses the original Python variable name
            if (is_first_assignment and self.isVarUnused(original_var_name)) {
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
                // First assignment: emit var/const declaration with type annotation
                try valueGen.emitVarDeclaration(
                    self,
                    var_name,
                    value_type,
                    is_arraylist,
                    is_dict,
                    is_mutable_class_instance,
                    is_listcomp,
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
                // Use renamed version if in var_renames map (for exception handling)
                const actual_name = self.var_renames.get(var_name) orelse var_name;
                // Use writeEscapedIdent to handle Zig keywords (e.g., "packed" -> @"packed")
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), actual_name);
                try self.emit(" = ");
                // No type annotation on reassignment
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
            // When variable is typed as bigint, we need to convert values to BigInt
            if (value_type == .bigint) {
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
        } else if (target == .attribute) {
            // Handle attribute assignment (self.x = value or obj.y = value)
            const attr = target.attribute;

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
            if (is_dynamic) {
                // Dynamic attribute: use __dict__.put() with type wrapping
                const dyn_value_type = try self.inferExprScoped(assign.value.*);
                const py_value_tag = switch (dyn_value_type) {
                    .int => "int",
                    .float => "float",
                    .bool => "bool",
                    .string => "string",
                    else => "int", // Default fallback
                };

                try self.emit("try ");
                try self.genExpr(attr.value.*);
                try self.emitFmt(".__dict__.put(\"{s}\", runtime.PyValue{{ .{s} = ", .{ attr.attr, py_value_tag });
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

            // Only handle index subscripts for now (not slices)
            if (subscript.slice == .index) {
                // Determine the container type to generate appropriate code
                const container_type = try self.inferExprScoped(subscript.value.*);

                try self.emitIndent();

                if (container_type == .dict) {
                    // Dict assignment: dict.put(key, value)
                    try self.emit("try ");
                    try self.genExpr(subscript.value.*);
                    try self.emit(".put(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit(", ");
                    try self.genExpr(assign.value.*);
                    try self.emit(");\n");
                } else if (container_type == .list) {
                    // List assignment: list.items[idx] = value
                    try self.genExpr(subscript.value.*);
                    try self.emit(".items[@as(usize, @intCast(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit("))] = ");
                    try self.genExpr(assign.value.*);
                    try self.emit(";\n");
                } else {
                    // Generic array/slice assignment: arr[idx] = value
                    try self.genExpr(subscript.value.*);
                    try self.emit("[@as(usize, @intCast(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit("))] = ");
                    try self.genExpr(assign.value.*);
                    try self.emit(";\n");
                }
            }
        }
    }
}

/// Generate augmented assignment (+=, -=, *=, /=, //=, **=, %=)
pub fn genAugAssign(self: *NativeCodegen, aug: ast.Node.AugAssign) CodegenError!void {
    try self.emitIndent();

    // Handle subscript with slice augmented assignment: x[1:2] *= 2
    // This is a complex operation that modifies the list in place
    if (aug.target.* == .subscript and aug.target.subscript.slice == .slice) {
        // For slice augmented assignment, we need runtime support
        // For now, emit a self-assignment as placeholder to suppress "never mutated" warning
        // The mutation analyzer marks this variable as mutated, so codegen uses var
        try self.genExpr(aug.target.subscript.value.*);
        try self.emit(" = ");
        try self.genExpr(aug.target.subscript.value.*);
        try self.emit("; // TODO: slice augmented assignment not yet supported\n");
        return;
    }

    // Handle subscript augmented assignment on dicts: x[key] += value
    // Dicts use .get()/.put() instead of direct indexing
    if (aug.target.* == .subscript) {
        const subscript = aug.target.subscript;
        if (subscript.slice == .index) {
            // Check if base is a dict: either by type inference or by tracking
            const base_type = try self.inferExprScoped(subscript.value.*);
            const is_tracked_dict = if (subscript.value.* == .name)
                self.isDictVar(subscript.value.name.id)
            else
                false;
            if (base_type == .dict or is_tracked_dict) {
                // Dict subscript aug assign: x[key] += value
                // Generates: try base.put(key, (base.get(key).? OP value));
                try self.emit("try ");
                try self.genExpr(subscript.value.*);
                try self.emit(".put(");
                try self.genExpr(subscript.slice.index.*);
                try self.emit(", ");

                // Special cases for operators that need function calls
                if (aug.op == .FloorDiv) {
                    try self.emit("@divFloor(");
                    try self.genExpr(subscript.value.*);
                    try self.emit(".get(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit(").?, ");
                    try self.genExpr(aug.value.*);
                    try self.emit("));\n");
                    return;
                }
                if (aug.op == .Pow) {
                    try self.emit("std.math.pow(i64, ");
                    try self.genExpr(subscript.value.*);
                    try self.emit(".get(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit(").?, ");
                    try self.genExpr(aug.value.*);
                    try self.emit("));\n");
                    return;
                }
                if (aug.op == .Mod) {
                    try self.emit("@rem(");
                    try self.genExpr(subscript.value.*);
                    try self.emit(".get(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit(").?, ");
                    try self.genExpr(aug.value.*);
                    try self.emit("));\n");
                    return;
                }
                if (aug.op == .Div) {
                    try self.emit("@divTrunc(");
                    try self.genExpr(subscript.value.*);
                    try self.emit(".get(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit(").?, ");
                    try self.genExpr(aug.value.*);
                    try self.emit("));\n");
                    return;
                }

                // Generate the value expression with operation
                try self.emit("(");
                try self.genExpr(subscript.value.*);
                try self.emit(".get(");
                try self.genExpr(subscript.slice.index.*);
                try self.emit(").?");
                try self.emit(") ");

                // Emit simple binary operation
                const op_str = switch (aug.op) {
                    .Add => "+",
                    .Sub => "-",
                    .Mult => "*",
                    .BitAnd => "&",
                    .BitOr => "|",
                    .BitXor => "^",
                    else => "?",
                };
                try self.emit(op_str);
                try self.emit(" ");
                try self.genExpr(aug.value.*);
                try self.emit(");\n");
                return;
            }
        }
    }

    // Emit target (variable name)
    try self.genExpr(aug.target.*);
    try self.emit(" = ");

    // Special handling for floor division and power
    if (aug.op == .FloorDiv) {
        try self.emit("@divFloor(");
        try self.genExpr(aug.target.*);
        try self.emit(", ");
        try self.genExpr(aug.value.*);
        try self.emit(");\n");
        return;
    }

    if (aug.op == .Pow) {
        try self.emit("std.math.pow(i64, ");
        try self.genExpr(aug.target.*);
        try self.emit(", ");
        try self.genExpr(aug.value.*);
        try self.emit(");\n");
        return;
    }

    if (aug.op == .Mod) {
        try self.emit("@rem(");
        try self.genExpr(aug.target.*);
        try self.emit(", ");
        try self.genExpr(aug.value.*);
        try self.emit(");\n");
        return;
    }

    // Handle true division - Python's /= on integers returns float but we're in-place
    // For integer division assignment, use @divTrunc to truncate to integer
    if (aug.op == .Div) {
        try self.emit("@divTrunc(");
        try self.genExpr(aug.target.*);
        try self.emit(", ");
        try self.genExpr(aug.value.*);
        try self.emit(");\n");
        return;
    }

    // Handle bitwise shift operators separately due to RHS type casting
    if (aug.op == .LShift or aug.op == .RShift) {
        const shift_fn = if (aug.op == .LShift) "std.math.shl" else "std.math.shr";
        try self.emitFmt("{s}(i64, ", .{shift_fn});
        try self.genExpr(aug.target.*);
        try self.emit(", @as(u6, @intCast(");
        try self.genExpr(aug.value.*);
        try self.emit(")));\n");
        return;
    }

    // Regular operators: +=, -=, *=, /=, &=, |=, ^=
    // Handle matrix multiplication separately
    if (aug.op == .MatMul) {
        // MatMul: target @= value => call __imatmul__ if available, else numpy.matmulAuto
        const target_type = try self.inferExprScoped(aug.target.*);
        if (target_type == .class_instance or target_type == .unknown) {
            // User class with __imatmul__: try target.__imatmul__(allocator, value)
            try self.emit("try ");
            try self.genExpr(aug.target.*);
            try self.emit(".__imatmul__(__global_allocator, ");
            try self.genExpr(aug.value.*);
            try self.emit(");\n");
        } else {
            // numpy arrays: numpy.matmulAuto(target, value, allocator)
            try self.emit("try numpy.matmulAuto(");
            try self.genExpr(aug.target.*);
            try self.emit(", ");
            try self.genExpr(aug.value.*);
            try self.emit(", allocator);\n");
        }
        return;
    }

    // Special handling for list/array concatenation: x += [1, 2]
    // Check if RHS is a list literal
    if (aug.op == .Add and aug.value.* == .list) {
        try self.emit("runtime.concat(");
        try self.genExpr(aug.target.*);
        try self.emit(", ");
        try self.genExpr(aug.value.*);
        try self.emit(");\n");
        return;
    }

    // Special handling for list/array multiplication: x *= 2
    // Check if LHS is a list type
    if (aug.op == .Mult) {
        const target_type = try self.inferExprScoped(aug.target.*);
        if (target_type == .list or aug.target.* == .list) {
            // List repeat: x *= n => runtime.listRepeat(x, n)
            try self.emit("runtime.listRepeat(");
            try self.genExpr(aug.target.*);
            try self.emit(", ");
            try self.genExpr(aug.value.*);
            try self.emit(");\n");
            return;
        }
    }

    try self.genExpr(aug.target.*);

    const op_str = switch (aug.op) {
        .Add => " + ",
        .Sub => " - ",
        .Mult => " * ",
        .Div => " / ",
        .BitAnd => " & ",
        .BitOr => " | ",
        .BitXor => " ^ ",
        else => " ? ",
    };
    try self.emit(op_str);

    try self.genExpr(aug.value.*);
    try self.emit(";\n");
}

/// Generate expression statement (expression with semicolon)
pub fn genExprStmt(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    try self.emitIndent();

    // Special handling for print()
    if (expr == .call and expr.call.func.* == .name) {
        const func_name = expr.call.func.name.id;
        if (std.mem.eql(u8, func_name, "print")) {
            const genPrint = @import("misc.zig").genPrint;
            try genPrint(self, expr.call.args);
            return;
        }
    }

    // Special handling for unittest.main() - generates complete block with its own structure
    if (expr == .call and expr.call.func.* == .attribute) {
        const attr = expr.call.func.attribute;
        if (attr.value.* == .name) {
            const obj_name = attr.value.name.id;
            const method_name = attr.attr;
            if (std.mem.eql(u8, obj_name, "unittest") and std.mem.eql(u8, method_name, "main")) {
                // unittest.main() generates its own complete output
                try self.genExpr(expr);
                return;
            }
        }
    }

    // Track if we added "_ = " prefix - if so, we ALWAYS need a semicolon
    var added_discard_prefix = false;

    // Discard string constants (docstrings) by assigning to _
    // Zig requires all non-void values to be used
    if (expr == .constant and expr.constant.value == .string) {
        try self.emit("_ = ");
        added_discard_prefix = true;
    }

    // Discard return values from function calls (Zig requires all non-void values to be used)
    if (expr == .call and expr.call.func.* == .name) {
        const func_name = expr.call.func.name.id;

        // Builtin functions that return non-void values need _ = prefix
        const value_returning_builtins = [_][]const u8{
            "list", "dict", "set", "tuple", "frozenset",
            "str", "int", "float", "bool", "bytes", "bytearray",
            "range", "enumerate", "zip", "map", "filter", "sorted", "reversed",
            "len", "abs", "min", "max", "sum", "round", "pow",
            "ord", "chr", "hex", "oct", "bin",
            "type", "id", "hash", "repr", "ascii",
            "iter", "next", "slice", "object",
            "vars", "dir", "locals", "globals",
            "callable", "isinstance", "issubclass", "hasattr", "getattr",
            "format", "input",
        };

        var is_value_returning_builtin = false;
        for (value_returning_builtins) |builtin| {
            if (std.mem.eql(u8, func_name, builtin)) {
                is_value_returning_builtin = true;
                break;
            }
        }

        if (is_value_returning_builtin) {
            try self.emit("_ = ");
            added_discard_prefix = true;
        } else if (self.type_inferrer.func_return_types.get(func_name)) |return_type| {
            // Check if function returns non-void type
            // Skip void returns
            if (return_type != .unknown) {
                try self.emit("_ = ");
                added_discard_prefix = true;
            }
        } else if (self.var_renames.get(func_name)) |renamed| {
            // Variables renamed from type attributes (e.g., int_class -> _local_int_class)
            // These hold type constructors like int which return values
            _ = renamed;
            try self.emit("_ = ");
            added_discard_prefix = true;
        }
    }

    // Handle type attribute calls (e.g., self.int_class(...))
    // These return values and need _ = prefix
    if (expr == .call and expr.call.func.* == .attribute) {
        const attr = expr.call.func.attribute;
        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
            if (self.current_class_name) |class_name| {
                var type_attr_key_buf: [512]u8 = undefined;
                const type_attr_key = std.fmt.bufPrint(&type_attr_key_buf, "{s}.{s}", .{ class_name, attr.attr }) catch null;
                if (type_attr_key) |key| {
                    if (self.class_type_attrs.get(key)) |_| {
                        // This is a type attribute call - it returns a value
                        try self.emit("_ = ");
                        added_discard_prefix = true;
                    }
                }
            }
        }
    }

    // Discard return values from module function calls (e.g., secrets.token_bytes())
    // These generate labeled blocks that return values
    if (expr == .call and expr.call.func.* == .attribute) {
        const attr = expr.call.func.attribute;
        if (attr.value.* == .name) {
            const module_name = attr.value.name.id;
            const func_name = attr.attr;

            // Modules with value-returning functions
            const value_returning_modules = [_][]const u8{
                "secrets", "base64", "hashlib", "json", "pickle",
                "zlib", "gzip", "binascii", "struct", "math",
                "random", "re", "os", "sys", "io", "string",
            };

            var is_value_module = false;
            for (value_returning_modules) |mod| {
                if (std.mem.eql(u8, module_name, mod)) {
                    is_value_module = true;
                    break;
                }
            }

            // Exclude known void-returning functions
            const void_functions = [_][]const u8{
                "main", "exit", "seed",
            };

            var is_void_func = false;
            for (void_functions) |vf| {
                if (std.mem.eql(u8, func_name, vf)) {
                    is_void_func = true;
                    break;
                }
            }

            if (is_value_module and !is_void_func) {
                try self.emit("_ = ");
                added_discard_prefix = true;
            }
        }
    }

    const before_len = self.output.items.len;
    try self.genExpr(expr);

    // Check if generated code ends with a block statement (not struct initializers)
    const generated = self.output.items[before_len..];

    // Skip empty expression statements (e.g., void functions that emit just "{}")
    // These are no-ops that would generate invalid "{};
    if (std.mem.eql(u8, generated, "{}")) {
        // Remove the "{}" and the indent we emitted
        self.output.shrinkRetainingCapacity(before_len - self.indent_level * 4);
        return;
    }

    // If nothing was generated and we added a discard prefix, remove it all
    // This handles cases where genExpr produces no output (e.g., unsupported expressions)
    if (generated.len == 0) {
        if (added_discard_prefix) {
            // Remove the "_ = " prefix and indent we emitted
            // "_ = " is 4 chars, plus indent
            self.output.shrinkRetainingCapacity(before_len - 4);
        }
        return;
    }

    // Determine if we need a semicolon:
    // - If we added "_ = " prefix, we ALWAYS need a semicolon (it's an assignment)
    // - Struct initializers like "Type{}" need semicolons
    // - Statement blocks like "{ ... }" do NOT need semicolons
    // - Labeled blocks like "blk: { ... }" do NOT need semicolons
    var needs_semicolon = true;

    // If we added "_ = " prefix, it's an assignment that always needs semicolon
    if (!added_discard_prefix and generated.len > 0 and generated[generated.len - 1] == '}') {
        // Check for labeled blocks (e.g., "blk: {", "sub_0: {", "slice_1: {", "comp_2: {")
        // Pattern: identifier followed by colon and space then brace
        const is_labeled_block = blk: {
            // Check for common label patterns
            if (std.mem.indexOf(u8, generated, "blk: {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "sub_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "slice_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "comp_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "dict_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "gen_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "idx_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "str_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            if (std.mem.indexOf(u8, generated, "arr_") != null and std.mem.indexOf(u8, generated, ": {") != null) break :blk true;
            // Generic check: look for pattern like "word_N: {" at the start
            if (generated.len >= 6) {
                // Check if starts with a label pattern (letters/underscore followed by digits, then ": {")
                var i: usize = 0;
                while (i < generated.len and (std.ascii.isAlphabetic(generated[i]) or generated[i] == '_')) : (i += 1) {}
                while (i < generated.len and std.ascii.isDigit(generated[i])) : (i += 1) {}
                if (i > 0 and i + 3 < generated.len and std.mem.eql(u8, generated[i .. i + 3], ": {")) {
                    break :blk true;
                }
            }
            break :blk false;
        };

        if (is_labeled_block) {
            needs_semicolon = false;
        }
        // Check for comptime blocks - "comptime { ... }"
        else if (std.mem.startsWith(u8, generated, "comptime ")) {
            needs_semicolon = false;
        }
        // Check for anonymous statement blocks - starts with "{ " (not "Type{")
        // Statement blocks: "{ const x = ...; }"
        // Struct initializers: "Type{}" or "Type{ .field = value }"
        else if (generated.len >= 2) {
            // Find the first '{' and check what's before it
            if (std.mem.indexOf(u8, generated, "{ ")) |brace_pos| {
                if (brace_pos == 0) {
                    // Starts with "{ " - it's a statement block
                    needs_semicolon = false;
                }
            }
        }
    }

    if (needs_semicolon) {
        try self.emit(";\n");
    } else {
        try self.emit("\n");
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

    // Check if class has this field
    const class_info = self.type_inferrer.class_fields.get(class_name);
    if (class_info) |info| {
        // Check if field exists in class
        if (info.fields.get(attr.attr)) |_| {
            return false; // Known field
        }
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
