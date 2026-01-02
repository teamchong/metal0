/// Assignment and expression statement code generation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const native_types_core = @import("../../../analysis/native_types/core.zig");
const NativeType = native_types_core.NativeType;
const TypeConfidence = native_types_core.TypeConfidence;
const helpers = @import("assign_helpers.zig");
const comptimeHelpers = @import("assign_comptime.zig");
const deferCleanup = @import("assign_defer.zig");
const typeHandling = @import("assign/type_handling.zig");
const valueGen = @import("assign/value_generation.zig");
const zig_keywords = @import("utils.zig_keywords");
const string_traits = @import("../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../analysis/traits/container_traits.zig");
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const imports = @import("misc/imports.zig");
const expressions = @import("../expressions.zig");

// Re-export submodules
pub const genAugAssign = @import("assign/aug_assign.zig").genAugAssign;
pub const genExprStmt = @import("assign/expr_stmt.zig").genExprStmt;

/// Check if an expression results in a BigInt
/// This detects expressions that produce BigInt values at runtime
fn isBigIntExpression(self: *NativeCodegen, expr: ast.Node) bool {
    // Name expression - check if variable is typed as BigInt
    if (expr == .name) {
        const var_name = expr.name.id;
        if (self.getVarType(var_name)) |var_type| {
            return var_type == .bigint or (var_type == .int and var_type.int.needsBigInt());
        }
        return false;
    }

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
    // Pow operator (2**100) produces BigInt when result would overflow
    // The genExpr for Pow uses BigInt.pow() when exp >= 20 (see arithmetic.zig:1013)
    if (expr == .binop and expr.binop.op == .Pow) {
        const rhs = expr.binop.right.*;
        // If RHS is not a small constant, pow produces BigInt
        if (rhs != .constant or rhs.constant.value != .int) {
            return true;
        }
        // Codegen uses BigInt for any exponent >= 20 (see arithmetic.zig:1013)
        // Must match the threshold used in codegen to avoid type mismatch
        if (rhs.constant.value.int >= 20) {
            return true;
        }
    }
    // int() call MAY produce BigInt, but only in specific cases:
    // - int(bigint_var) - returns the BigInt as-is
    // NOT BigInt-producing:
    // - int(string_var) - now uses UnifiedInt (auto-promotes if needed)
    // - int(class_instance) - calls __int__() which returns i64
    // - int(float_var) - truncates to i64 (may overflow but genInt handles it)
    if (expr == .call and expr.call.func.* == .name) {
        if (std.mem.eql(u8, expr.call.func.name.id, "int")) {
            if (expr.call.args.len >= 1) {
                const arg = expr.call.args[0];
                if (arg == .name) {
                    const arg_name = arg.name.id;
                    if (self.getVarType(arg_name)) |arg_type| {
                        // BigInt argument: int(bigint_var) returns BigInt
                        if (arg_type == .bigint) return true;
                        if (arg_type == .int and arg_type.int.needsBigInt()) return true;
                        // Note: int(string_var) now uses UnifiedInt, not BigInt
                    }
                }
            }
        }
    }
    // BigInt binary operations (bitOr, bitAnd, etc.) produce BigInt
    // when either operand is BigInt or needs BigInt (unbounded int)
    if (expr == .binop) {
        // BitOr, BitAnd, BitXor operations with BigInt operands produce BigInt
        const is_bitwise = expr.binop.op == .BitOr or expr.binop.op == .BitAnd or expr.binop.op == .BitXor;
        if (is_bitwise) {
            // If either operand requires BigInt, the result is BigInt
            if (isBigIntExpression(self, expr.binop.left.*)) return true;
            if (isBigIntExpression(self, expr.binop.right.*)) return true;
        } else {
            // For other binops, recurse
            if (isBigIntExpression(self, expr.binop.left.*)) return true;
            if (isBigIntExpression(self, expr.binop.right.*)) return true;
        }
    }
    return false;
}

/// Collect all variable names referenced in an AST node (recursive)
/// Used to find variables that appear only in VM fallback strings and need discards
fn collectNamesFromNode(allocator: std.mem.Allocator, node: ast.Node, names: *std.ArrayList([]const u8)) void {
    switch (node) {
        .name => |n| {
            // Skip Python builtins and keywords
            if (std.mem.eql(u8, n.id, "None") or std.mem.eql(u8, n.id, "True") or
                std.mem.eql(u8, n.id, "False") or std.mem.eql(u8, n.id, "self"))
            {
                return;
            }
            names.append(allocator, n.id) catch {};
        },
        .call => |call| {
            // Collect names from function and arguments
            collectNamesFromNode(allocator, call.func.*, names);
            for (call.args) |arg| {
                collectNamesFromNode(allocator, arg, names);
            }
            for (call.keyword_args) |kw| {
                collectNamesFromNode(allocator, kw.value, names);
            }
        },
        .attribute => |attr| {
            collectNamesFromNode(allocator, attr.value.*, names);
        },
        .subscript => |sub| {
            collectNamesFromNode(allocator, sub.value.*, names);
            switch (sub.slice) {
                .index => |idx| collectNamesFromNode(allocator, idx.*, names),
                .slice => |range| {
                    if (range.lower) |lower| collectNamesFromNode(allocator, lower.*, names);
                    if (range.upper) |upper| collectNamesFromNode(allocator, upper.*, names);
                    if (range.step) |step| collectNamesFromNode(allocator, step.*, names);
                },
            }
        },
        .binop => |binop| {
            collectNamesFromNode(allocator, binop.left.*, names);
            collectNamesFromNode(allocator, binop.right.*, names);
        },
        .unaryop => |unary| {
            collectNamesFromNode(allocator, unary.operand.*, names);
        },
        .compare => |cmp| {
            collectNamesFromNode(allocator, cmp.left.*, names);
            for (cmp.comparators) |comp| {
                collectNamesFromNode(allocator, comp, names);
            }
        },
        .boolop => |boolop| {
            for (boolop.values) |val| {
                collectNamesFromNode(allocator, val, names);
            }
        },
        .if_expr => |if_expr| {
            collectNamesFromNode(allocator, if_expr.condition.*, names);
            collectNamesFromNode(allocator, if_expr.body.*, names);
            collectNamesFromNode(allocator, if_expr.orelse_value.*, names);
        },
        .tuple => |tuple| {
            for (tuple.elts) |elt| {
                collectNamesFromNode(allocator, elt, names);
            }
        },
        .list => |list| {
            for (list.elts) |elt| {
                collectNamesFromNode(allocator, elt, names);
            }
        },
        .dict => |dict| {
            for (dict.keys) |key| {
                collectNamesFromNode(allocator, key, names);
            }
            for (dict.values) |val| {
                collectNamesFromNode(allocator, val, names);
            }
        },
        else => {},
    }
}

/// Check for deferred closure instantiations waiting on this variable
/// These are closures that captured the variable before it was declared
pub fn triggerDeferredClosureInstantiations(self: *NativeCodegen, var_name: []const u8) CodegenError!void {
    if (self.deferred_closure_instantiations.getPtr(var_name)) |deferred_list| {
        const closure_gen = @import("functions/nested/closure_gen.zig");
        for (deferred_list.items) |info| {
            try closure_gen.emitClosureInstantiation(self, info);
        }
        // Clear deferred list for this variable (instantiation done)
        deferred_list.deinit(self.allocator);
        _ = self.deferred_closure_instantiations.swapRemove(var_name);
    }
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

/// Check if this is a pytest.mark assignment that should be skipped
/// pytestmark = pytest.mark.skipif(...) is test metadata, not runtime behavior
fn isPytestmarkNoOp(targets: []const ast.Node, expr: ast.Node) bool {
    // Check if target is "pytestmark"
    if (targets.len != 1 or targets[0] != .name) return false;
    if (!std.mem.eql(u8, targets[0].name.id, "pytestmark")) return false;

    // Check if value involves pytest.mark
    return isPytestMarkExpr(expr);
}

fn isPytestMarkExpr(expr: ast.Node) bool {
    // Direct: pytest.mark.skipif(...)
    if (expr == .call) {
        const call = expr.call;
        if (call.func.* == .attribute) {
            return isPytestMarkAttribute(call.func.attribute);
        }
    }
    // List: [pytest.mark.skipif(...), ...]
    if (expr == .list) {
        for (expr.list.elts) |elem| {
            if (isPytestMarkExpr(elem)) return true;
        }
    }
    // Attribute: pytest.mark.skipif (without call)
    if (expr == .attribute) {
        return isPytestMarkAttribute(expr.attribute);
    }
    return false;
}

fn isPytestMarkAttribute(attr: ast.Node.Attribute) bool {
    // Check for pytest.mark.* pattern
    if (attr.value.* == .attribute) {
        const parent = attr.value.attribute;
        if (parent.value.* == .name) {
            const module_name = parent.value.name.id;
            const attr_name = parent.attr;
            return std.mem.eql(u8, module_name, "pytest") and
                std.mem.eql(u8, attr_name, "mark");
        }
    }
    return false;
}

/// Generate assignment statement with automatic defer cleanup
pub fn genAssign(self: *NativeCodegen, assign: ast.Node.Assign) CodegenError!void {
    const b = try self.getBuilder();
    // Clear target_dict_value_type context at end of assignment
    // This ensures dict codegen context doesn't leak to subsequent statements
    defer self.target_dict_value_type = null;

    // Track current assignment target for genTuple to check if empty tuple should be empty set
    // Set when we have a single name target that's a conditionally hoisted set variable
    defer self.current_assign_target = null;
    if (assign.targets.len == 1 and assign.targets[0] == .name) {
        const target_name = assign.targets[0].name.id;
        if (self.conditional_var_types.contains(target_name)) {
            self.current_assign_target = target_name;
        }
    }

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

    // Skip pytestmark assignments (pytest.mark.* decorators)
    // These are test metadata that metal0's test runner doesn't use
    if (isPytestmarkNoOp(assign.targets, assign.value.*)) {
        try self.emitIndent();
        try self.emit("// pytest marker skipped\n");
        return;
    }

    // Infer type from the current value expression
    var value_type = try self.inferExprScoped(assign.value.*);
    const original_expr_type = value_type; // Keep for class_instance shadowing detection

    // VM fallback expressions return PyValue, not the inferred type
    // This ensures subsequent uses of the variable know it's PyValue
    if (self.needsVMFallback(assign.value.*)) {
        value_type = .pyvalue;
    }

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
                    const skip_widening = type_traits.isClassInstance(scoped_type) and
                        type_traits.isClassInstance(original_expr_type) and
                        !std.mem.eql(u8, scoped_type.class_instance, original_expr_type.class_instance);
                    if (!skip_widening) {
                        value_type = scoped_type;

                        // Check if widened type is a dict with pyvalue values
                        // If so, set context for dict literal codegen to use PyValue
                        // Context is cleared at end of genAssign via defer
                        if (@as(std.meta.Tag(NativeType), scoped_type) == .dict) {
                            const val_type = scoped_type.dict.value.*;
                            if (@as(std.meta.Tag(NativeType), val_type) == .pyvalue) {
                                self.target_dict_value_type = "runtime.PyValue";
                            }
                        }
                        break;
                    }
                }
            }
        }
    }

    // TWO-FLOW TYPE SYSTEM: Track confidence for all assigned variables
    // This connects analysis-phase confidence tracking to codegen-phase PyValue decisions
    // Confidence determines whether to use raw Zig types (certain) or PyValue (uncertain)
    for (assign.targets) |target| {
        if (target == .name) {
            const var_name = target.name.id;
            const confidence: TypeConfidence = blk: {
                // VM fallback expressions are always uncertain (return PyValue)
                if (self.needsVMFallback(assign.value.*)) break :blk .uncertain;
                // PyValue and unknown types are uncertain
                if (value_type == .pyvalue or value_type == .unknown) break :blk .uncertain;
                // If we used a widened scoped type, propagate its existing confidence
                if (self.type_inferrer.getScopedVar(var_name)) |_| {
                    break :blk self.type_inferrer.getConfidence(var_name);
                }
                // Known types are certain
                break :blk .certain;
            };
            self.type_inferrer.putConfidence(var_name, confidence) catch {};
        }
    }

    // Track variables assigned from BigInt expressions
    // This handles cases like: hibit = 1 << (bits - 1) where bits is not comptime
    // We need to know hibit is BigInt for subsequent operations like hibit | x
    if (isBigIntExpression(self, assign.value.*)) {
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

    // Track error-returning builtins assigned to variables: pow_op = pow
    // These need try prefix when called: (try pow_op(...))
    // List of builtins that return error unions (from runtime/builtins.zig)
    const is_error_returning = blk: {
        if (assign.value.* == .name) {
            const builtin_name = assign.value.name.id;
            // Check if this is an error-returning builtin function
            break :blk std.mem.eql(u8, builtin_name, "pow") or
                std.mem.eql(u8, builtin_name, "open") or
                std.mem.eql(u8, builtin_name, "eval") or
                std.mem.eql(u8, builtin_name, "exec");
        }
        // Also check for attribute expressions like operator.pow
        if (assign.value.* == .attribute) {
            const attr = assign.value.attribute;
            if (attr.value.* == .name) {
                const module_name = attr.value.name.id;
                const attr_name = attr.attr;
                // operator.pow returns error union
                if (std.mem.eql(u8, module_name, "operator") and std.mem.eql(u8, attr_name, "pow")) {
                    break :blk true;
                }
            }
        }
        break :blk false;
    };
    if (is_error_returning) {
        for (assign.targets) |target| {
            if (target == .name) {
                const owned_name = try self.arena.allocator().dupe(u8, target.name.id);
                try self.error_callable_vars.put(owned_name, {});
            }
        }
    }

    // Track class type assignments: R = fractions.Fraction
    // When a variable is assigned from a module attribute that's a known class type,
    // track it for .init() instantiation (instead of .call())
    if (assign.value.* == .attribute) {
        const attr = assign.value.attribute;
        if (attr.value.* == .name) {
            const module_name = attr.value.name.id;
            const class_name = attr.attr;
            if (imports.isKnownClassType(module_name, class_name)) {
                for (assign.targets) |target| {
                    if (target == .name) {
                        try self.imported_class_types.put(target.name.id, {});
                    }
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
                        const key = try self.arena.allocator().dupe(u8, target.name.id);
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
                            .library_var = try self.arena.allocator().dupe(u8, lib_var),
                            .func_name = try self.arena.allocator().dupe(u8, func_name),
                            .argtypes = &[_][]const u8{},
                            .restype = try self.arena.allocator().dupe(u8, "c_int"), // Default return type
                        };
                        const key = try self.arena.allocator().dupe(u8, var_name);
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

    // Handle chained assignment with tuple unpacking: ka, va = ta = a.popitem()
    // This has multiple targets where one is a tuple/list
    if (assign.targets.len > 1) {
        // Check if any target is a tuple/list that needs unpacking
        var has_tuple_target = false;
        for (assign.targets) |target| {
            if (target == .tuple or target == .list) {
                has_tuple_target = true;
                break;
            }
        }

        if (has_tuple_target) {
            // Generate temp variable for the value
            const tmp_name = try self.freshName("chained_tmp");

            // Infer source type
            // Two-Flow: Include .pyvalue for uncertain container types
            const source_type = try self.type_inferrer.inferExpr(assign.value.*);
            const is_list_type = container_traits.isList(source_type) or source_type == .pyvalue;

            // Generate: const __chained_tmp_N = value_expr;
            try self.emitIndent();
            try self.emit("const ");
            try self.emit(tmp_name);
            try self.emit(" = ");
            try self.genExpr(assign.value.*);
            try self.emit(";\n");

            // Now assign to each target (in reverse order for Python semantics)
            // Python evaluates right-to-left: ka, va = ta = x means ta = x, then ka, va = ta
            var i: usize = assign.targets.len;
            while (i > 0) {
                i -= 1;
                const target = assign.targets[i];
                if (target == .name) {
                    const var_name = target.name.id;

                    // Handle underscore discard variable (like tuple unpacking does)
                    const is_discard = std.mem.eql(u8, var_name, "_");
                    if (is_discard) {
                        try self.emitIndent();
                        try self.emit("_ = ");
                        try self.emit(tmp_name);
                        try self.emit(";\n");
                    } else {
                        const is_first_assignment = !self.isDeclared(var_name);

                        try self.emitIndent();
                        if (is_first_assignment) {
                            try self.emit("const ");
                            try self.declareVar(var_name);
                        }
                        // Use var_renames if available (for outer scope variables like in exception handlers)
                        // Otherwise use writeLocalVarName which applies shadowing rename
                        if (self.var_renames.get(var_name)) |renamed| {
                            // Use writeLocalVarName to handle capture field access like "__m22_cap_check.expected"
                            try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), renamed);
                        } else {
                            try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), var_name);
                        }
                        try self.emit(" = ");
                        try self.emit(tmp_name);
                        try self.emit(";\n");
                    }
                } else if (target == .tuple) {
                    // Unpack tuple elements
                    for (target.tuple.elts, 0..) |elem, j| {
                        if (elem == .name) {
                            const var_name = elem.name.id;
                            const is_unused = std.mem.eql(u8, var_name, "_") or self.isVarUnused(var_name);
                            if (is_unused) {
                                try self.emitIndent();
                                if (is_list_type) {
                                    try self.output.writer(self.allocator).print("_ = {s}.items[{d}];\n", .{ tmp_name, j });
                                } else {
                                    try self.output.writer(self.allocator).print("_ = {s}.@\"{d}\";\n", .{ tmp_name, j });
                                }
                                continue;
                            }

                            const is_first_assignment = !self.isDeclared(var_name);

                            try self.emitIndent();
                            if (is_first_assignment) {
                                try self.emit("const ");
                                try self.declareVar(var_name);
                            }
                            try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), var_name);
                            if (is_list_type) {
                                try self.output.writer(self.allocator).print(" = {s}.items[{d}];\n", .{ tmp_name, j });
                            } else {
                                try self.output.writer(self.allocator).print(" = {s}.@\"{d}\";\n", .{ tmp_name, j });
                            }
                        }
                    }
                } else if (target == .list) {
                    // Unpack list elements
                    for (target.list.elts, 0..) |elem, j| {
                        if (elem == .name) {
                            const var_name = elem.name.id;
                            const is_unused = std.mem.eql(u8, var_name, "_") or self.isVarUnused(var_name);
                            if (is_unused) {
                                try self.emitIndent();
                                if (is_list_type) {
                                    try self.output.writer(self.allocator).print("_ = {s}.items[{d}];\n", .{ tmp_name, j });
                                } else {
                                    try self.output.writer(self.allocator).print("_ = {s}.@\"{d}\";\n", .{ tmp_name, j });
                                }
                                continue;
                            }

                            const is_first_assignment = !self.isDeclared(var_name);

                            try self.emitIndent();
                            if (is_first_assignment) {
                                try self.emit("const ");
                                try self.declareVar(var_name);
                            }
                            try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), var_name);
                            if (is_list_type) {
                                try self.output.writer(self.allocator).print(" = {s}.items[{d}];\n", .{ tmp_name, j });
                            } else {
                                try self.output.writer(self.allocator).print(" = {s}.@\"{d}\";\n", .{ tmp_name, j });
                            }
                        }
                    }
                }
            }
            return;
        }
    }

    for (assign.targets) |target| {
        if (target == .name) {
            // IMPORTANT: Copy the variable name to arena memory immediately to prevent
            // use-after-free when subsequent expression generation causes memory operations
            // that could invalidate pointers into the original AST
            var var_name: []const u8 = try self.arena.allocator().dupe(u8, target.name.id);
            const original_var_name = var_name; // Keep for usage checks (before any renaming)

            // Skip function-aliasing assignments: genslices = rslices, permutations = rpermutation
            // When value is a module-level function, skip the assignment
            // In Python this aliases one function to another name, but in Zig functions
            // can't be reassigned - they're compile-time constants
            if (assign.value.* == .name) {
                const rhs_name = assign.value.name.id;
                if (self.module_level_funcs.contains(rhs_name)) {
                    // RHS is a function - emit comment and skip
                    try self.emitIndent();
                    try self.emit("// function alias: ");
                    try self.emit(var_name);
                    try self.emit(" = ");
                    try self.emit(rhs_name);
                    try self.emit(" (skipped - functions are compile-time constants)\n");
                    continue;
                }
                // Track when exception type is assigned to variable (e.g., context = IndexError)
                if (expressions.isPythonExceptionType(rhs_name)) {
                    const var_name_copy = try self.arena.allocator().dupe(u8, var_name);
                    const rhs_name_copy = try self.arena.allocator().dupe(u8, rhs_name);
                    try self.exception_type_vars.put(var_name_copy, rhs_name_copy);
                }
            }

            // Handle type alias assignments: R = fractions.Fraction, D = decimal.Decimal
            // These need `const R = type` not `var R = type` or `R = type`
            // Skip if already declared (module-level type aliases are emitted at module level)
            if (self.type_alias_vars.contains(var_name)) {
                if (self.isDeclared(var_name)) {
                    // Already declared at module level - skip
                    continue;
                }
                try self.emitIndent();
                try self.emit("const ");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                try self.emit(" = ");
                try self.genExpr(assign.value.*);
                try self.emit(";\n");
                try self.declareVar(var_name);
                continue;
            }

            // Rename 'self' to '__self' inside nested class methods to avoid
            // shadowing the outer function's 'self' parameter
            // e.g., inside StrWithStr.__new__: self = str.__new__(cls, "") -> __self = ...
            if (std.mem.eql(u8, var_name, "self") and self.method_nesting_depth > 0) {
                var_name = "__self";
            }

            // Check if assigning to a for-loop capture variable
            // In Zig, loop captures are immutable, so we need to rename: line = line.strip()
            // becomes __mN_lv_line = line.strip() and subsequent refs use __mN_lv_line
            // NOTE: We set the rename AFTER generating the value, so the RHS uses the original capture
            const is_loop_capture_reassign = self.loop_capture_vars.contains(var_name);
            // First check if var_renames already has a renamed version (pre-declared at for-loop level)
            // This avoids generating a new name when genEnumerateLoop already pre-declared one
            const loop_renamed_name = if (is_loop_capture_reassign)
                (self.var_renames.get(var_name) orelse self.name_gen.loopVar(var_name) catch var_name)
            else
                var_name;
            if (is_loop_capture_reassign) {
                var_name = loop_renamed_name;
                // Propagate confidence from original name to renamed name
                // This prevents defaulting to uncertain for renamed loop capture variables
                // when the original variable had certain confidence
                const original_confidence = self.type_inferrer.getConfidence(original_var_name);
                self.type_inferrer.putConfidence(loop_renamed_name, original_confidence) catch {};
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
                                    // Rename the local variable to avoid shadowing (using NameGen)
                                    const renamed = self.name_gen.local(var_name) catch var_name;
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

            // Skip callable_global_vars assignments (includes tuples of callables like order_comparisons = le, lt, ge, gt)
            // These are already emitted at module level as const in PHASE 5.7
            if (self.callable_global_vars.contains(var_name) and self.isDeclared(var_name)) {
                return;
            }

            // Skip module constant assignments (e.g., maxsize = support.MAX_Py_ssize_t)
            // These are already emitted at module level as const with correct type
            if (assign.value.* == .attribute) {
                const attr = assign.value.attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "support")) {
                    // Check if it's a known support module constant
                    const attr_name = attr.attr;
                    if (std.mem.eql(u8, attr_name, "MAX_Py_ssize_t") or
                        std.mem.eql(u8, attr_name, "_1G") or
                        std.mem.eql(u8, attr_name, "_2G") or
                        std.mem.eql(u8, attr_name, "_4G") or
                        std.mem.eql(u8, attr_name, "verbose") or
                        std.mem.eql(u8, attr_name, "MS_WINDOWS") or
                        std.mem.eql(u8, attr_name, "is_apple") or
                        std.mem.eql(u8, attr_name, "SHORT_TIMEOUT"))
                    {
                        // Already emitted at module level, skip assignment
                        return;
                    }
                }
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

            // Handle csv module function calls (csv.reader, csv.writer, csv.DictReader, csv.DictWriter)
            // These return anonymous structs that can't be pre-declared, so we declare inline
            // csv.reader/DictReader need 'var' since their internal state changes on .next()
            // csv.writer/DictWriter need 'var' since they accumulate buffer data
            if (assign.value.* == .call) {
                const call_val = assign.value.call;
                if (call_val.func.* == .attribute) {
                    const attr = call_val.func.attribute;
                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "csv")) {
                        // csv module call - declare variable inline since not pre-declared
                        const is_declared = self.isDeclared(var_name);
                        try self.emitIndent();
                        if (!is_declared) {
                            // csv iterators/writers are mutated internally, need 'var'
                            try self.emit("var ");
                        }
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                        try self.emit(" = ");
                        try self.genExpr(assign.value.*);
                        try self.emit(";\n");
                        if (!is_declared) {
                            try self.declareVar(var_name);
                            // Mark as csv iterator for proper for-loop handling
                            try self.csv_iterators.put(try self.arena.allocator().dupe(u8, var_name), {});
                            // Add suppression for "never mutated" warning (csv types use var for internal state)
                            try self.emitIndent();
                            try self.emit("_ = &");
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                            try self.emit(";\n");
                        }
                        return;
                    }
                }
            }

            // Function references (like mod = operator.mod) don't need special tracking
            // Zig allows calling function pointers directly: const f = &func; f(args) works
            // The .call() pattern is only for PyCallable structs from runtime (closures/iterables)

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

            // Check if value is a deque() call - deques are mutable ArrayListUnmanaged
            const is_deque = typeHandling.isDequeCall(assign.value.*);

            // Check if this is first assignment or reassignment
            // Hoisted variables should skip declaration (already declared before try block)
            // Forward-declared variables (captured by nested classes before assignment) also skip
            // Global variables should also skip declaration (they're declared in outer scope)
            const is_hoisted = self.hoisted_vars.contains(var_name);
            // Check both original and renamed names for forward-declared vars
            // (forward_declared_vars may contain renamed version like "__local_set2" for "set2")
            const renamed_var = self.var_renames.get(var_name);
            const is_forward_declared = self.forward_declared_vars.contains(var_name) or
                (if (renamed_var) |rv| self.forward_declared_vars.contains(rv) else false);
            const is_global = self.isGlobalVar(var_name);
            // Also check if this is a module-level variable (declared at top of module)
            const is_module_level = self.module_level_vars.contains(var_name);
            // Check both original name AND renamed version for is_declared
            // When a nested function def bar() declares __m13_c_bar and renames bar -> __m13_c_bar,
            // the subsequent bar = decorator(bar) should see bar as "already declared" via the rename
            const renamed_is_declared = if (renamed_var) |rv| self.isDeclared(rv) else false;
            // Also check if this variable is a closure (nested function) - closures are always "declared"
            // This handles: def bar(): ...; bar = decorator(bar)
            // The function definition generates const __m13_c_bar and puts bar in closure_vars
            const is_closure = self.closure_vars.contains(var_name);
            const is_first_assignment = !self.isDeclared(var_name) and !renamed_is_declared and !is_closure and !is_hoisted and !is_forward_declared and !is_global and !is_module_level;

            // When a forward-declared variable is assigned, remove it from forward_declared_vars
            // This allows closures defined AFTER this assignment to know the variable is now available
            if (is_forward_declared) {
                _ = self.forward_declared_vars.fetchSwapRemove(var_name);
                if (renamed_var) |rv| {
                    _ = self.forward_declared_vars.fetchSwapRemove(rv);
                }
            }

            // If forward-declared and we have a rename, use the renamed version
            // This ensures "set2 = ..." assigns to "__local_set2" which was forward-declared
            if (is_forward_declared and renamed_var != null) {
                var_name = renamed_var.?;
            }

            // When inside a nested function, check if this new local would shadow an outer scope variable
            // that's not captured. Zig doesn't allow shadowing across nested struct boundaries.
            // e.g., outer has `var rep`, closure creates `const rep` -> rename to avoid shadow
            if (self.inside_nested_function and is_first_assignment) {
                // Check if name exists in outer scope (not just current scope)
                const exists_in_outer = self.symbol_table.lookup(var_name) != null;
                // Check if it's a captured variable (via var_renames)
                const is_captured = self.var_renames.contains(var_name);
                if (exists_in_outer and !is_captured) {
                    // Rename to avoid shadowing using unified name_gen
                    const shadow_name = try self.name_gen.shadow(var_name);
                    try self.var_renames.put(var_name, shadow_name);
                    var_name = shadow_name;
                }
            }

            // Check if local variable would shadow an imported module
            // Python allows this (locals shadow imports) but Zig doesn't allow shadowing module-level vars
            // e.g., `const overrides = @import("./overrides.zig")` then local `overrides = ...` -> rename local
            if (is_first_assignment and self.wouldShadowImport(var_name)) {
                const shadow_name = try self.name_gen.local(var_name);
                try self.var_renames.put(var_name, shadow_name);
                var_name = shadow_name;
            }

            // Also check if local variable would shadow a module-level pre-declared global
            // Python allows this (locals shadow globals) but Zig doesn't allow shadowing module-level vars
            // e.g., global `var set2` at module level, local `var set2` in method -> rename local
            if (is_first_assignment and !is_global) {
                // Check if this var name exists as a module-level var (pre-declared global)
                // For constants like __name__, __file__ - skip the assignment entirely
                // since const cannot be reassigned in Zig
                if (self.module_level_vars.contains(var_name)) {
                    // Skip assignment to module-level constants
                    // Emit comment and discard the value to suppress warnings
                    try self.emitIndent();
                    try self.emit("// Assignment to module-level constant '");
                    try self.emit(var_name);
                    try self.emit("' skipped (const cannot be reassigned)\n");
                    try self.emitIndent();
                    try self.emit("_ = ");
                    try self.genExpr(assign.value.*);
                    try self.emit(";\n");
                    continue;
                }
            }

            // Try compile-time evaluation FIRST
            // Skip comptime eval for:
            // - bigint typed vars (need runtime BigInt.fromInt)
            // - ArrayList lists (need runtime ArrayList for mutations like .append())
            // The comptime path generates [N]T fixed arrays which can't be mutated.
            if (value_type != .bigint and !is_arraylist) {
                if (self.comptime_evaluator.tryEval(assign.value.*)) |comptime_val| {
                    // Check mutability BEFORE emitting
                    // Use isVarMutated() to check both module-level AND function-local mutations
                    const is_mutable = if (is_first_assignment)
                        self.isVarMutated(var_name)
                    else
                        false; // Reassignments don't declare

                    // Successfully evaluated at compile time!
                    // All comptime values (int, float, bool, string, list) can be emitted
                    try comptimeHelpers.emitComptimeAssignment(self, var_name, comptime_val, is_first_assignment, is_mutable);

                    // Free owned memory after emission (strings/lists allocate during concat/operations)
                    defer comptime_val.deinit(self.allocator);

                    if (is_first_assignment) {
                        // Declare with proper type for scope-aware type lookup
                        try self.declareVarWithType(var_name, value_type);
                        // Trigger any deferred closures waiting on this variable
                        try triggerDeferredClosureInstantiations(self, var_name);
                    }

                    // If variable is used in eval string but nowhere else in actual code,
                    // emit _ = &varname; to suppress Zig "unused" warning
                    // Use original_var_name for check, but emit renamed var_name
                    // Use &var to avoid "pointless discard of local constant" error
                    if (self.isEvalStringVar(original_var_name)) {
                        try self.emitIndent();
                        try self.emit("_ = &");
                        try self.emit(var_name);
                        try self.emit(";\n");
                    }

                    // Track first assignments for potential discard emission
                    // Even comptime-evaluated variables need discard tracking for unused var suppression
                    if (is_first_assignment) {
                        const suppress_name = self.var_renames.get(var_name) orelse var_name;
                        try self.pending_discards.put(try self.arena.allocator().dupe(u8, var_name), try self.arena.allocator().dupe(u8, suppress_name));
                    }

                    return;
                }
            }

            try self.emitIndent();

            // For unused variables, either skip the statement or discard with _ = expr;
            // Use original_var_name since usage analysis uses the original Python variable name
            // EXCEPTION: At module level (current_function_name == null), never skip - module vars
            // might be used in class methods or functions, which lifetime analysis doesn't scan
            // Also don't skip if var is used in eval/exec strings (dynamic usage)
            // Also don't skip chained assignments (a = b = c = None) - all targets need declaration
            // since they might be used in try blocks where the helper struct needs them as parameters
            const at_module_level = self.current_function_name == null;
            const is_eval_var = self.isEvalStringVar(original_var_name);
            const is_chained_assignment = assign.targets.len > 1;
            if (is_first_assignment and !at_module_level and !is_eval_var and !is_chained_assignment and self.isVarUnused(original_var_name)) {
                // Check if value expression has side effects
                // Simple name/constant references have no side effects - skip entirely
                // Calls, list/dict literals with calls, etc. have side effects - execute them
                const has_side_effects = switch (assign.value.*) {
                    .name, .constant => false,
                    else => true,
                };

                if (!has_side_effects) {
                    // No side effects - skip this target but continue to next
                    // (chained assignment: a = b = c = None processes each target)
                    continue;
                }

                // Two-Flow: Include .pyvalue for uncertain types
                if (type_traits.isUnknown(value_type) or value_type == .pyvalue) {
                    // PyObject/PyValue: capture in block and decref immediately
                    const unused = try self.name_gen.temp();
                    try self.emitFmt("{{ const {s} = ", .{unused});
                    try self.genExpr(assign.value.*);
                    try self.emitFmt("; runtime.decref({s}, __global_allocator); }}\n", .{unused});
                } else {
                    try self.emit("_ = ");
                    try self.genExpr(assign.value.*);
                    try self.emit(";\n");
                }
                // Don't declare - variable doesn't exist, but continue to next target
                continue;
            }

            // Track if PyValue.from() wrapper was opened and needs closing
            // Declared at higher scope so early return paths can access it
            var wrapper_opened: bool = false;
            // TWO-FLOW TYPE SYSTEM: Track if PyValue.from() wrapper needed for reassignment
            var reassign_pyvalue_wrap: bool = false;
            // UNIFIED INT: Track if UnifiedInt wrapper needed for reassignment
            var reassign_unified_int_wrap: bool = false;
            // UNIFIED INT: Track if i128 version needed (for sys.maxsize expressions)
            var reassign_unified_int_i128: bool = false;

            if (is_first_assignment) {
                // Special handling for y = x where x is ArrayList
                // In Python, y = x makes y an alias (reference) to the same list
                // Generate: const y = &x (pointer to x)
                if (assign.value.* == .name) {
                    const rhs_name = assign.value.name.id;
                    // Check if the inferred type is a list (not just if variable was ever ArrayList)
                    // This ensures we don't alias class instances even if a previous function had same var name
                    const is_rhs_list_type = container_traits.isList(value_type);
                    const is_rhs_arraylist = is_rhs_list_type and (self.isArrayListVar(rhs_name) or self.arraylist_aliases.contains(rhs_name));
                    if (is_rhs_arraylist) {
                        // Track y as an alias pointing to x
                        const var_name_copy = try self.arena.allocator().dupe(u8, var_name);
                        const rhs_name_copy = try self.arena.allocator().dupe(u8, rhs_name);
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
                        // Trigger any deferred closures waiting on this variable
                        try triggerDeferredClosureInstantiations(self, var_name);
                        return;
                    }

                    // For nested class instances (heap-allocated pointers), y = x simply copies the pointer
                    // This is handled by normal assignment - no special case needed since
                    // nested classes now return *@This() from init(), so x is already a pointer
                }

                // Handle function-local type aliases: R = fractions.Fraction, D = decimal.Decimal
                // These are type aliases inside functions that need `const R = type`, not PyValue wrapping
                if (assign.value.* == .attribute) {
                    const attr = assign.value.attribute;
                    if (attr.value.* == .name) {
                        const module_name = attr.value.name.id;
                        const attr_name = attr.attr;
                        // Known type exports from modules (same list as generator.zig)
                        const is_type_alias = blk: {
                            if (std.mem.eql(u8, module_name, "fractions") and std.mem.eql(u8, attr_name, "Fraction")) break :blk true;
                            if (std.mem.eql(u8, module_name, "decimal") and std.mem.eql(u8, attr_name, "Decimal")) break :blk true;
                            break :blk false;
                        };
                        if (is_type_alias) {
                            // Track this type alias for call codegen
                            // So R(...) knows to use .init() without allocator
                            try self.type_alias_vars.put(var_name, {});
                            // Also store what type it aliases (e.g., "R" -> "Fraction")
                            try self.type_alias_targets.put(try self.allocator.dupe(u8, var_name), try self.allocator.dupe(u8, attr_name));
                            // Emit: const R = type (let Zig infer, no PyValue wrapping)
                            try self.emit("const ");
                            try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), var_name);
                            try self.emit(" = ");
                            try self.genExpr(assign.value.*);
                            try self.emit(";\n");
                            try self.declareVarWithType(var_name, value_type);
                            try triggerDeferredClosureInstantiations(self, var_name);
                            return;
                        }
                    }
                }

                // First assignment: emit var/const declaration with type annotation
                // wrapper_opened indicates if PyValue.from() wrapper was opened and needs closing
                wrapper_opened = try valueGen.emitVarDeclaration(
                    self,
                    var_name,
                    value_type,
                    is_arraylist,
                    is_dict,
                    is_mutable_class_instance,
                    is_listcomp,
                    is_iterator,
                    assign.value.*,
                );

                // Mark as declared with proper type for scope-aware type lookup
                try self.declareVarWithType(var_name, value_type);

                // Track array slice vars
                const is_array_slice = typeHandling.isArraySlice(self, assign.value.*);
                if (is_array_slice) {
                    const var_name_copy = try self.arena.allocator().dupe(u8, var_name);
                    try self.array_slice_vars.put(var_name_copy, {});
                }

            } else {
                // Reassignment: x = value (no var/const keyword!)
                // EXCEPTION: If the new type differs from the declared type (e.g., different struct),
                // we need to shadow the variable with a new const declaration
                // Check local symbol table first, then fall back to type_inferrer.var_types for global vars
                const declared_type = self.getLocalVarType(var_name) orelse
                    self.type_inferrer.var_types.get(var_name) orelse .unknown;
                const new_type = value_type;

                // Check if we're assigning a different class type (needs variable shadowing)
                // This handles reassignments like: u = Class1(); u = Class2()
                // In Zig, we can't change a variable's type, so we shadow with a new const
                const needs_shadow = blk: {
                    // Collection type transitions: list/array <-> dict/set
                    // These are fundamentally incompatible in Zig

                    // List/array to dict/set transition
                    const is_list_or_array = container_traits.isList(declared_type) or container_traits.isArray(declared_type);
                    const is_dict_or_set = container_traits.isDict(new_type) or container_traits.isSet(new_type);
                    if (is_list_or_array and is_dict_or_set) {
                        break :blk true;
                    }
                    // Dict/set to list/array transition
                    const was_dict_or_set = container_traits.isDict(declared_type) or container_traits.isSet(declared_type);
                    const now_list_or_array = container_traits.isList(new_type) or container_traits.isArray(new_type);
                    if (was_dict_or_set and now_list_or_array) {
                        break :blk true;
                    }

                    if (type_traits.isClassInstance(declared_type) and type_traits.isClassInstance(new_type)) {
                        // Different class instances - need shadow
                        if (!std.mem.eql(u8, declared_type.class_instance, new_type.class_instance)) {
                            break :blk true;
                        }
                    }
                    // Primitive type being reassigned to class instance
                    // e.g., value = float('nan'); value = F('nan') where F(float, H)
                    // In Python, F inherits from float but in Zig they're different types
                    if (type_traits.isClassInstance(new_type)) {
                        // Was a primitive type (int, float, bool, string) but now is class instance
                        if (type_traits.isIntegral(declared_type) or type_traits.isFloating(declared_type) or
                            type_traits.isBoolean(declared_type) or string_traits.isString(declared_type))
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
                            if (type_traits.isClassInstance(declared_type)) {
                                if (!std.mem.eql(u8, declared_type.class_instance, call_name)) {
                                    break :blk true;
                                }
                            } else if (is_nested_class) {
                                // First assignment was also a nested class but type wasn't tracked
                                // as class_instance. Check if call names differ.
                                // This handles: u = subclass(); u = subclass_with_init()
                                // where declared_type might be .unknown
                                if (type_traits.isUnknown(declared_type)) {
                                    break :blk true; // Different nested class, need shadow
                                }
                            }
                            // Also shadow if declared as primitive but now assigning nested class
                            if (type_traits.isIntegral(declared_type) or type_traits.isFloating(declared_type) or
                                type_traits.isBoolean(declared_type) or string_traits.isString(declared_type))
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
                        const is_rhs_list_type = container_traits.isList(new_type);
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
                            const unique_name_copy = try self.arena.allocator().dupe(u8, unique_name);
                            const rhs_name_copy = try self.arena.allocator().dupe(u8, rhs_name);
                            try self.arraylist_aliases.put(unique_name_copy, rhs_name_copy);
                            try self.var_renames.put(var_name, unique_name);
                            try self.declareVarWithType(var_name, new_type);
                            try self.declareVarWithType(unique_name, new_type);
                            // Trigger any deferred closures waiting on this variable
                            try triggerDeferredClosureInstantiations(self, var_name);
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
                    // Use the current (possibly already renamed) name, not the original name.
                    // ONLY emit discard if variable actually exists (not just forward-declared/hoisted)
                    const current_name = self.var_renames.get(var_name) orelse var_name;
                    if (self.isDeclared(current_name)) {
                        try self.emit("_ = &");
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), current_name);
                        try self.emit(";\n");
                        try self.emitIndent();
                    }

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
                        const is_rhs_list_type = container_traits.isList(value_type);
                        const is_rhs_arraylist = is_rhs_list_type and (self.isArrayListVar(rhs_name) or self.arraylist_aliases.contains(rhs_name));
                        if (is_rhs_arraylist) {
                            // Update alias to point to new target
                            const var_name_copy = try self.arena.allocator().dupe(u8, var_name);
                            const rhs_name_copy = try self.arena.allocator().dupe(u8, rhs_name);
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
                    // Track if we got name from var_renames (indicates it's already properly declared)
                    const has_rename = self.var_renames.contains(var_name);

                    // TWO-FLOW TYPE SYSTEM: Check if reassigning a PyValue variable
                    // If so, we need to wrap the RHS in runtime.PyValue.from()
                    // EXCEPTION 1: If the expression already produces PyValue (e.g., binop with uncertain operands),
                    // don't double-wrap
                    // EXCEPTION 2: List literals use the ArrayList expansion pattern (init + appends),
                    // which is incompatible with PyValue.from() wrapping
                    // EXCEPTION 3: eval() calls already wrap result in PyValue.from() via genEval
                    // Also check pyvalue_hoisted_vars for variables hoisted from try-except blocks
                    // Also check conditional_var_types for module-level variables declared as PyValue
                    const is_conditional_pyvalue = blk: {
                        if (self.conditional_var_types.get(var_name)) |zig_type| {
                            break :blk std.mem.eql(u8, zig_type, "runtime.PyValue");
                        }
                        break :blk false;
                    };
                    const is_pyvalue_reassign = (declared_type == .pyvalue) or self.pyvalue_hoisted_vars.contains(var_name) or is_conditional_pyvalue;
                    const binop_produces_pyvalue = valueGen.binopProducesPyValue(self, assign.value.*);
                    // Check if this is an eval() call - genEval already wraps in PyValue.from()
                    const is_eval_call = blk: {
                        if (assign.value.* == .call) {
                            const call = assign.value.call;
                            if (call.func.* == .name) {
                                const func_name = call.func.name.id;
                                if (std.mem.eql(u8, func_name, "eval")) break :blk true;
                            }
                        }
                        break :blk false;
                    };
                    const expr_produces_pyvalue = binop_produces_pyvalue or is_eval_call;
                    const is_list_literal = assign.value.* == .list;
                    // Skip PyValue wrapping for exception-to-exception assignments
                    // e.g., `raised = exc` where `exc` is from `except Exception as exc:`
                    // PyException should NOT be wrapped in PyValue.from()
                    const is_exception_assignment = blk: {
                        if (assign.value.* == .name) {
                            const rhs_name = assign.value.name.id;
                            if (self.exception_vars.contains(rhs_name)) break :blk true;
                        }
                        break :blk false;
                    };
                    reassign_pyvalue_wrap = is_pyvalue_reassign and !expr_produces_pyvalue and !is_list_literal and !is_exception_assignment;

                    // UNIFIED INT: Check if reassigning a UnifiedInt variable
                    // If the target is UnifiedInt and RHS is not already UnifiedInt, wrap with fromI64()
                    const is_unified_int_reassign = (declared_type == .unified_int);
                    const rhs_type = self.inferExprScoped(assign.value.*) catch .unknown;
                    // Wrap if RHS is a simple integer (i64) or binop result, but not if already unified_int
                    const rhs_is_not_unified_int = (rhs_type != .unified_int);
                    // Check if RHS could produce i128 (binop with attribute like sys.maxsize)
                    reassign_unified_int_i128 = blk: {
                        if (rhs_type == .int and rhs_type.int.needsBigInt()) break :blk true;
                        if (assign.value.* == .binop) {
                            const binop = assign.value.binop;
                            if (binop.left.* == .attribute or binop.right.* == .attribute) break :blk true;
                            if (binop.left.* == .unaryop and binop.left.unaryop.operand.* == .attribute) break :blk true;
                            if (binop.right.* == .unaryop and binop.right.unaryop.operand.* == .attribute) break :blk true;
                        }
                        break :blk false;
                    };
                    reassign_unified_int_wrap = is_unified_int_reassign and rhs_is_not_unified_int;

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

                    // Use writeLocalVarName to handle Zig keywords AND shadowing names
                    // (e.g., "packed" -> @"packed", "init" -> "init_")
                    // IMPORTANT: Must match the escaping used in declarations (emitVarName)
                    // EXCEPTION: If variable has a var_renames entry, it's already properly declared
                    // (e.g., in try-except handlers) - use the exact name without shadowing rename
                    if (has_rename) {
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), actual_name);
                    } else {
                        try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), actual_name);
                    }
                    try self.emit(" = ");
                    // TWO-FLOW TYPE SYSTEM: Open PyValue.from() wrapper for reassignment if needed
                    // Check if RHS is a generator call (returns []PyValue) - use listFromSlice instead
                    const is_generator_call = blk: {
                        if (assign.value.* == .call) {
                            const call = assign.value.call;
                            // Direct call: gen()
                            if (call.func.* == .name) {
                                const func_name = call.func.name.id;
                                // Check both call graph and generator_closure_vars
                                // (nested generator closures are tracked in generator_closure_vars)
                                break :blk self.funcIsGenerator(func_name) or self.generator_closure_vars.contains(func_name);
                            }
                            // Attribute call: self.gen() or cap.gen.call()
                            if (call.func.* == .attribute) {
                                const attr = call.func.attribute;
                                // Check if it's a closure .call() pattern
                                if (std.mem.eql(u8, attr.attr, "call")) {
                                    // The base is the closure, which may be a generator
                                    // For cap.gen pattern, check if gen is a generator
                                    if (attr.value.* == .attribute) {
                                        const inner_attr = attr.value.attribute;
                                        break :blk self.funcIsGenerator(inner_attr.attr) or self.generator_closure_vars.contains(inner_attr.attr);
                                    }
                                }
                                // Regular method call: check if the method is a generator
                                break :blk self.funcIsGenerator(attr.attr) or self.generator_closure_vars.contains(attr.attr);
                            }
                        }
                        break :blk false;
                    };
                    if (reassign_pyvalue_wrap) {
                        if (is_generator_call) {
                            try self.emit("try runtime.PyValue.listFromSlice(__global_allocator, ");
                        } else {
                            try self.emit("runtime.PyValue.from(");
                        }
                    }
                    // UNIFIED INT: Open UnifiedInt wrapper for reassignment if needed
                    if (reassign_unified_int_wrap) {
                        if (reassign_unified_int_i128) {
                            try self.emit("(try runtime.UnifiedInt.fromI128(__global_allocator, ");
                        } else {
                            try self.emit("runtime.UnifiedInt.fromI64(");
                        }
                    }
                    // No type annotation on reassignment
                }
            }

            // Special handling for string concatenation with nested operations
            // s1 + " " + s2 needs intermediate temps
            if (assign.value.* == .binop and assign.value.binop.op == .Add) {
                const left_type = try self.inferExprScoped(assign.value.binop.left.*);
                const right_type = try self.inferExprScoped(assign.value.binop.right.*);
                if (string_traits.isString(left_type) or string_traits.isString(right_type)) {
                    // Pass wrapper_opened so genStringConcat can close the PyValue.from() wrapper before semicolon
                    // For first assignment: wrapper_opened is set by emitVarDeclaration
                    // For reassignment: reassign_pyvalue_wrap is set when reassigning a PyValue variable
                    const pyvalue_wrap_opened = (is_first_assignment and wrapper_opened) or reassign_pyvalue_wrap;
                    try valueGen.genStringConcat(self, assign, var_name, is_first_assignment, pyvalue_wrap_opened);
                    return;
                }
            }

            // Special handling for list literals that will be mutated
            // Generate ArrayList initialization directly instead of fixed array
            if (is_arraylist and assign.value.* == .list) {
                const list = assign.value.list;
                // Pass wrapper_opened for first assignment (reassignment never has wrapper for lists
                // because we disabled it above to avoid conflict with ArrayList expansion pattern)
                try valueGen.genArrayListInit(self, var_name, list, wrapper_opened);

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
                // genArrayListInit now closes the wrapper internally, so don't add extra );\n
                return;
            }

            // Special handling for bigint variable assignments
            // When variable is typed as bigint OR has unbounded int (could overflow i64),
            // we need to convert values to BigInt
            const needs_bigint = value_type == .bigint or
                (value_type == .int and value_type.int.needsBigInt());
            if (needs_bigint) {
                // BigInt variables have explicit `: runtime.BigInt =` type annotation
                // They NEVER use PyValue wrapper, so clear the flag to prevent double-closing
                wrapper_opened = false;

                // Infer the type of the current value expression
                const current_value_type = try self.inferExprScoped(assign.value.*);

                // If current value is int-typed, convert to BigInt
                // BUT: if current value is already BigInt type OR produces BigInt, emit directly without wrapping
                const produces_bigint = current_value_type == .bigint or
                    (current_value_type == .int and current_value_type.int.needsBigInt()) or
                    isBigIntExpression(self, assign.value.*);
                if (produces_bigint) {
                    // Expression already produces BigInt (e.g., bigint ops: bitOr, bitAnd, 2**100, etc.)
                    try self.genExpr(assign.value.*);
                    try self.emit(";\n");
                    try valueGen.trackVariableMetadata(
                        self,
                        var_name,
                        is_first_assignment,
                        is_constant_array,
                        typeHandling.isArraySlice(self, assign.value.*),
                        assign,
                    );
                    return;
                } else if (type_traits.isIntegral(current_value_type)) {
                    // Check if this is an int() call - handle based on argument type
                    // to avoid overflow when parsing very large strings like int('1' * 600)
                    // or converting large floats like int(1e100)
                    if (assign.value.* == .call and assign.value.call.func.* == .name and
                        std.mem.eql(u8, assign.value.call.func.name.id, "int"))
                    {
                        const int_call = assign.value.call;
                        if (int_call.args.len >= 1) {
                            // Check the type of the argument to int()
                            const arg_type = try self.inferExprScoped(int_call.args[0]);
                            if (type_traits.isFloating(arg_type)) {
                                // int(float) -> use UnifiedInt.fromFloat (auto-demotes to i64 if fits)
                                try self.emit("(try runtime.UnifiedInt.fromFloat(__global_allocator, ");
                                try self.genExpr(int_call.args[0]);
                                try self.emit("))");
                            } else {
                                // int(string) or int(string, base) -> use parseIntToBigInt
                                try self.emit("(try runtime.parseIntToBigInt(__global_allocator, ");
                                try self.genExpr(int_call.args[0]);
                                try self.emit(", ");
                                if (int_call.args.len >= 2) {
                                    try self.emitCallCtx("@intCast", int_call.args[1], struct {
                                        pub fn f(s: *NativeCodegen, arg: ast.Node) CodegenError!void {
                                            try s.genExpr(arg);
                                        }
                                    }.f);
                                } else {
                                    try self.emit("10");
                                }
                                try self.emit("))");
                            }

                            // Close PyValue wrapper if it was opened
                            if (is_first_assignment and wrapper_opened) {
                                try self.emit(")");
                            }
                            try self.emit(";\n");

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
                    // BUT: if the constant is already a bigint literal, genExpr already produces
                    // parseIntToBigInt(...) which returns BigInt directly - don't double-wrap
                    // ALSO: if expression already produces BigInt (e.g., 2**100 uses .pow() which returns BigInt)
                    // we should emit directly without wrapping
                    if (assign.value.* == .constant and assign.value.constant.value == .bigint) {
                        // Already a bigint literal - genExpr will produce BigInt directly
                        try self.genExpr(assign.value.*);
                    } else if (assign.value.* == .constant) {
                        try self.emit("(runtime.BigInt.fromInt(__global_allocator, ");
                        try self.genExpr(assign.value.*);
                        try self.emit(") catch unreachable)");
                    } else if (isBigIntExpression(self, assign.value.*)) {
                        // Expression already produces BigInt (e.g., 2**100, bigint ops)
                        try self.genExpr(assign.value.*);
                    } else {
                        try self.emit("(runtime.BigInt.fromInt128(__global_allocator, ");
                        try self.genExpr(assign.value.*);
                        try self.emit(") catch unreachable)");
                    }

                    // Close PyValue wrapper if it was opened
                    if (is_first_assignment and wrapper_opened) {
                        try self.emit(")");
                    }
                    try self.emit(";\n");

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
                try self.withInlineBlock("async", assign.value.*, struct {
                    fn emit(s: *NativeCodegen, label: []const u8, value: ast.Node) CodegenError!void {
                        const num_threads = try s.name_gen.temp();
                        const thread = try s.name_gen.temp();
                        const result = try s.name_gen.temp();
                        try s.emit("\n");
                        try s.emitIndent();
                        // Initialize scheduler if needed (first async call)
                        try s.emit("    if (!runtime.scheduler_initialized) {\n");
                        try s.emitIndent();
                        try s.emitFmt("        const {s} = std.Thread.getCpuCount() catch 8;\n", .{num_threads});
                        try s.emitIndent();
                        try s.emitFmt("        runtime.scheduler = runtime.Scheduler.init(__global_allocator, {s}) catch unreachable;\n", .{num_threads});
                        try s.emitIndent();
                        try s.emit("        runtime.scheduler.?.start() catch unreachable;\n");
                        try s.emitIndent();
                        try s.emit("        runtime.scheduler_initialized = true;\n");
                        try s.emitIndent();
                        try s.emit("    }\n");
                        try s.emitIndent();
                        try s.emitFmt("    const {s} = ", .{thread});
                        try s.genExpr(value);
                        try s.emit(";\n");
                        try s.emitIndent();
                        try s.emitFmt("    runtime.scheduler.?.wait({s});\n", .{thread});
                        try s.emitIndent();
                        try s.emitFmt("    const {s} = {s}.result orelse unreachable;\n", .{ result, thread });
                        try s.emitIndent();
                        try s.emit("    break :");
                        try s.emit(label);
                        try s.emitFmt(" @as(*i64, @ptrCast(@alignCast({s}))).*;\n", .{result});
                        try s.emitIndent();
                    }
                }.emit);
                try self.emit(");\n");
            } else {
                // TWO-FLOW TYPE SYSTEM: Emit value normally
                // genExpr() for calls already handles 'try' when needed (see calls.zig:1523)
                // so we don't need to add it here
                try self.genExpr(assign.value.*);
                // TWO-FLOW TYPE SYSTEM: Close PyValue.from() wrapper if it was opened
                // Use wrapper_opened flag from emitVarDeclaration which already handles
                // all the conditions (unknown type, uncertain var, and expr_produces_pyvalue check)
                if (is_first_assignment and wrapper_opened) {
                    try self.emit(")");
                    // Update var_types to mark this variable as PyValue so that subsequent
                    // uses in binop detect it via isOperandUncertain and use PyValue methods
                    try self.type_inferrer.var_types.put(var_name, .pyvalue);
                    // Also update scoped_var_types so getScopedVar returns .pyvalue (not the original type)
                    // This is critical for aug_assign detection inside functions where scope is set
                    try self.type_inferrer.putScopedVar(var_name, .pyvalue);
                    // Also update symbol_table so getLocalVarType() returns .pyvalue for reassignment detection
                    try self.symbol_table.declare(var_name, .pyvalue, true);
                    // TWO-FLOW: Set confidence to uncertain since we wrapped in PyValue
                    self.type_inferrer.putConfidence(var_name, .uncertain) catch {};
                }
                // TWO-FLOW TYPE SYSTEM: Close PyValue.from() wrapper for reassignment if opened
                if (reassign_pyvalue_wrap) {
                    try self.emit(")");
                }
                // UNIFIED INT: Close UnifiedInt wrapper for reassignment if opened
                if (reassign_unified_int_wrap) {
                    if (reassign_unified_int_i128) {
                        try self.emit("))"); // Close fromI128 and try
                    } else {
                        try self.emit(")"); // Close fromI64 only
                    }
                }
                try self.emit(";\n");
            }

            // Apply pending shadow rename AFTER RHS generation
            // This ensures: object = Class(object) uses OLD object on RHS
            if (pending_shadow_rename) |rename| {
                try self.var_renames.put(rename.old_name, rename.new_name);
                // Also update nested_class_instances if this variable was a nested class instance
                // The old name was registered during assignment detection, but attribute access
                // uses the new (renamed) name, so we need to map both
                if (self.nested_class_instances.get(rename.old_name)) |class_name| {
                    try self.nested_class_instances.put(rename.new_name, class_name);
                }
                // Track the shadow variable for unused suppression
                // Shadow variables might not be used after declaration (type-changing reassignment
                // at end of function), so they need _ = &shadow_var; if unused
                try self.pending_discards.put(try self.arena.allocator().dupe(u8, rename.old_name), try self.arena.allocator().dupe(u8, rename.new_name));
                // Remove from func_local_vars so var_renames lookup is used in expressions.zig
                // This is critical for type-changing reassignments: subsequent uses of the old name
                // must resolve to the new shadow name (e.g., x -> x__15914 for dict operations)
                _ = self.func_local_vars.swapRemove(rename.old_name);
            }

            // For iterators, add pointer discard to suppress "never mutated" warnings
            // Some iterator uses pass by value (json.dumps) vs by pointer (next())
            if (is_iterator and is_first_assignment) {
                const actual_name = self.var_renames.get(var_name) orelse var_name;
                try self.emitIndent();
                try self.emit("_ = &");
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), actual_name);
                try self.emit(";\n");
            }

            // For deques, add pointer discard to suppress "never mutated" warnings
            // Deques use `var` for .deinit() but may not be mutated at the variable level
            if (is_deque and is_first_assignment) {
                const actual_name = self.var_renames.get(var_name) orelse var_name;
                try self.emitIndent();
                try self.emit("_ = &");
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), actual_name);
                try self.emit(";\n");
            }

            // For class instances, add pointer discard to suppress "unused local constant" warnings
            // Class instances may only be used in conditionally compiled branches (e.g., inside if blocks)
            // which can result in the variable appearing unused at the Zig level
            if (type_traits.isClassInstance(value_type) and is_first_assignment) {
                const actual_name = self.var_renames.get(var_name) orelse var_name;
                try self.emitIndent();
                try self.emit("_ = &");
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), actual_name);
                try self.emit(";\n");
            }

            // For variables declared with `var` (because isVarMutated returned true),
            // emit suppression to avoid "local variable is never mutated" when the mutation
            // is in a branch that doesn't execute at runtime (e.g., try/except else: block)
            if (is_first_assignment and !is_iterator) {
                const is_mutated = self.isVarMutated(var_name);
                if (is_mutated) {
                    const actual_name = self.var_renames.get(var_name) orelse var_name;
                    try self.emitIndent();
                    try self.emit("_ = &");
                    try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), actual_name);
                    try self.emit(";\n");
                }
            }

            // For variables assigned from VM fallback, emit discard to suppress unused warnings
            // VM fallback variables are referenced by name in subsequent eval() strings,
            // not as Zig identifiers, so Zig sees them as unused
            // Also track as pyvalue_vars for callable dispatch at call sites
            if (self.needsVMFallback(assign.value.*)) {
                // Track as pyvalue_var for .call() generation at call sites
                // Must track for BOTH first assignment AND reassignment since
                // reassignment like `line = line.strip()` returns PyValue
                const pyvalue_key = try self.arena.allocator().dupe(u8, var_name);
                try self.pyvalue_vars.put(pyvalue_key, {});

                // For first assignment only, emit discard to suppress unused warnings
                // VM fallback variables are referenced by name in subsequent eval() strings,
                // not as Zig identifiers, so Zig sees them as unused
                if (is_first_assignment) {
                    const actual_name = self.var_renames.get(var_name) orelse var_name;
                    try self.emitIndent();
                    try self.emit("_ = &");
                    try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), actual_name);
                    try self.emit(";\n");
                }
            }

            // Also emit discards for variables USED in VM fallback RHS expressions
            // Example: x = weakref.ref(obj) -> runtime.eval("weakref.ref(obj)")
            // Here `obj` only appears in the string literal, so Zig sees it as unused
            if (self.needsVMFallback(assign.value.*)) {
                var rhs_names: std.ArrayList([]const u8) = .{};
                defer rhs_names.deinit(self.allocator);
                collectNamesFromNode(self.allocator, assign.value.*, &rhs_names);
                for (rhs_names.items) |rhs_name| {
                    // Only emit discard for local variables that we've seen declared
                    // Skip the LHS variable (already handled above)
                    if (std.mem.eql(u8, rhs_name, var_name)) continue;
                    // Check if it's a local variable in this function scope
                    // ALSO check isDeclared to ensure variable wasn't discarded in tuple unpacking
                    const rhs_actual_name = self.var_renames.get(rhs_name) orelse rhs_name;
                    if ((self.func_local_vars.contains(rhs_name) or self.pending_discards.contains(rhs_name)) and self.isDeclared(rhs_actual_name)) {
                        try self.emitIndent();
                        try self.emit("_ = &");
                        try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), rhs_actual_name);
                        try self.emit(";\n");
                    }
                }
            }

            // Track first assignments for potential discard emission
            // We defer discard emission to check if the variable is actually used in generated code
            // This avoids "pointless discard" errors when the variable IS used
            if (is_first_assignment) {
                const suppress_name = self.var_renames.get(var_name) orelse var_name;
                // Record both the original name and the emitted name for later discard check
                try self.pending_discards.put(try self.arena.allocator().dupe(u8, var_name), try self.arena.allocator().dupe(u8, suppress_name));
            }

            // If variable is used in eval string or VM fallback but nowhere else in actual code,
            // emit _ = &varname; to suppress Zig "unused local constant" error
            // This handles:
            // 1. Runtime-assigned variables (non-comptime path) - via isEvalStringVar
            // 2. Variables referenced in generated VM fallback expressions - via vm_fallback_used_vars
            // The comptime path at lines 924-933 handles this separately
            const is_vm_fallback_var = self.vm_fallback_used_vars.contains(original_var_name);
            if (is_first_assignment and (self.isEvalStringVar(original_var_name) or is_vm_fallback_var)) {
                const actual_name = self.var_renames.get(var_name) orelse var_name;
                try self.emitIndent();
                try self.emit("_ = &");
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), actual_name);
                try self.emit(";\n");
            }

            // Emit discard for ALL first assignments to handle unused const variables
            // This catches cases not covered by the specific categories above (iterator,
            // deque, class instance, mutated, VM fallback, eval string)
            // Examples: field2 (used only in eval), two (dead code), protocol (unused const)
            if (is_first_assignment) {
                // Check if any of the specific categories already emitted a discard
                const is_class_instance = type_traits.isClassInstance(value_type);
                const is_mutated = self.isVarMutated(var_name);
                const already_handled = is_iterator or is_deque or is_class_instance or
                    is_mutated or self.needsVMFallback(assign.value.*) or
                    self.isEvalStringVar(original_var_name) or is_vm_fallback_var;

                if (!already_handled) {
                    const actual_name = self.var_renames.get(var_name) orelse var_name;
                    try self.emitIndent();
                    try self.emit("_ = &");
                    try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), actual_name);
                    try self.emit(";\n");
                }
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
                // Use putScopedVar to update both scoped and global maps (for aug_assign detection)
                try self.type_inferrer.putScopedVar(loop_renamed_name, value_type);
                // Remove from func_local_vars so var_renames lookup is used in expressions.zig
                // This ensures subsequent uses of the variable resolve to the renamed version
                _ = self.func_local_vars.swapRemove(original_var_name);
            }

            // Trigger any deferred closures waiting on this variable
            // This must happen AFTER the entire assignment is complete (value generated)
            try triggerDeferredClosureInstantiations(self, var_name);
        } else if (target == .attribute) {
            // Handle attribute assignment (self.x = value or obj.y = value)
            const attr = target.attribute;

            // Check for __code__ assignment - this is a no-op since we compile to native code
            // Python: f.__code__ = f.__code__.replace(co_linetable=...)
            if (std.mem.eql(u8, attr.attr, "__code__")) {
                try self.emitIndent();
                try self.emit("// __code__ assignment is a no-op in compiled code\n");
                return;
            }

            // Check for traceback field assignment (tb_next, tb_frame, tb_lineno, tb_lasti)
            // In AOT compilation, tracebacks are stubs - use runtime.traceback_stub.set_tb_next
            const tb_fields_assign = [_][]const u8{ "tb_next", "tb_frame", "tb_lineno", "tb_lasti" };
            const is_tb_field_assign = for (tb_fields_assign) |field| {
                if (std.mem.eql(u8, attr.attr, field)) break true;
            } else false;
            if (is_tb_field_assign) {
                // Generate: runtime.traceback_stub.set_tb_next(tb, value)
                try self.emitIndent();
                try self.emit("runtime.traceback_stub.set_tb_next(");
                try self.genExpr(attr.value.*);
                try self.emit(", ");
                try self.genExpr(assign.value.*);
                try self.emit(");\n");
                return;
            }

            // Check for default_factory assignment (defaultdict)
            // d.default_factory = list  ->  d.default_factory = .list
            // d.default_factory = None  ->  d.default_factory = .none
            if (std.mem.eql(u8, attr.attr, "default_factory")) {
                try self.emitIndent();
                try self.genExpr(target);
                try self.emit(" = ");
                // Map Python type names to FactoryType enum values
                if (assign.value.* == .name) {
                    const val_name = assign.value.name.id;
                    if (std.mem.eql(u8, val_name, "list")) {
                        try self.emit(".list");
                    } else if (std.mem.eql(u8, val_name, "int")) {
                        try self.emit(".int");
                    } else if (std.mem.eql(u8, val_name, "str")) {
                        try self.emit(".str");
                    } else if (std.mem.eql(u8, val_name, "dict")) {
                        try self.emit(".dict");
                    } else if (std.mem.eql(u8, val_name, "set")) {
                        try self.emit(".set");
                    } else if (std.mem.eql(u8, val_name, "None")) {
                        try self.emit(".none");
                    } else {
                        // Custom callable - use custom factory
                        try self.emitFmt("runtime.FactoryType{{ .custom = \"{s}\" }}", .{val_name});
                    }
                } else if (assign.value.* == .constant) {
                    // Check if constant is None
                    switch (assign.value.constant.value) {
                        .none => try self.emit(".none"),
                        else => try self.genExpr(assign.value.*),
                    }
                } else {
                    // Fallback: emit as-is (may fail, but at least shows intent)
                    try self.genExpr(assign.value.*);
                }
                try self.emit(";\n");
                return;
            }

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
                                        try argtypes_list.append(self.allocator, try self.arena.allocator().dupe(u8, elem.attribute.attr));
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
                            .restype = try self.arena.allocator().dupe(u8, restype_name),
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
                const tmp_name = try b.freshTemp();
                try self.emitIndent();
                try self.emit("{\n");
                self.indent_level += 1;
                try self.emitIndent();
                try self.emitFmt("var {s} = ", .{tmp_name});
                try self.genExpr(attr.value.*);
                try self.emit(";\n");
                try self.emitIndent();
                try self.emitFmt("{s}.", .{tmp_name});
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

            // Check for sys module attribute assignment - needs special handling
            // Some sys attributes are mutable at runtime (breakpointhook, etc.)
            if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "sys")) {
                if (std.mem.eql(u8, attr.attr, "stdout") or std.mem.eql(u8, attr.attr, "stderr")) {
                    const Ctx = struct { val: *ast.Node, attr_name: []const u8 };
                    try self.emitCallCtx("runtime.discard", Ctx{ .val = assign.value, .attr_name = attr.attr }, struct {
                        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
                            try s.genExpr(ctx.val.*);
                        }
                    }.f);
                    try self.emit("; // sys.");
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
                // For other sys module attributes (breakpointhook, etc.),
                // use VM fallback since they're not compile-time known
                try self.emitVMFallback(.{ .assign = assign });
                try self.emit(";\n");
                return;
            }

            // Check if the attribute's base object is uncertain (would generate runtime.eval)
            // If so, we need to use VM fallback for the entire assignment since
            // runtime.eval() returns an rvalue, not an lvalue
            const target_needs_vm_fallback = self.needsVMFallback(target);
            if (target_needs_vm_fallback) {
                // Use VM fallback for entire assignment: obj.attr = value
                try self.emitVMFallback(.{ .assign = assign });
                try self.emit(";\n");
                return;
            }

            if (is_dynamic) {
                // Dynamic attribute: use __dict__.put() with runtime.PyValue.from()
                // This handles all types correctly including class instances (stored as .ptr)
                // Use @constCast since the object may be declared as const (HashMap stores data via pointers,
                // so @constCast works correctly - the internal data is heap-allocated)
                if (self.inside_defer) {
                    try self.emit("@constCast(&");
                    try self.genExpr(attr.value.*);
                    try self.emitFmt(".__dict__).put(\"{s}\", runtime.PyValue.from(", .{attr.attr});
                    try self.genExpr(assign.value.*);
                    try self.emit(")) catch {}");
                } else {
                    try self.emit("try @constCast(&");
                    try self.genExpr(attr.value.*);
                    try self.emitFmt(".__dict__).put(\"{s}\", runtime.PyValue.from(", .{attr.attr});
                    try self.genExpr(assign.value.*);
                    try self.emit("))");
                }
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

                // Check if subscript.value is a dynamic attribute (stored in __dict__)
                // These need special handling with pyListSetPy for Python index semantics
                const is_dynamic_attr = blk: {
                    if (subscript.value.* == .attribute) {
                        const attr = subscript.value.attribute;
                        if (attr.value.* == .name) {
                            const obj_name = attr.value.name.id;
                            // Check if it's a self attribute
                            if (std.mem.eql(u8, obj_name, "self") or std.mem.eql(u8, obj_name, "__self")) {
                                // Check if attribute is in class_fields (static) or not (dynamic)
                                if (self.current_class_name) |class_name| {
                                    if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                                        if (class_info.fields.contains(attr.attr)) {
                                            break :blk false; // Static field
                                        }
                                    }
                                }
                                break :blk true; // Dynamic attribute
                            }
                        }
                    }
                    break :blk false;
                };

                // Dynamic attribute subscript assignment: self.a[-12] = val
                // Uses pyListSetPy for Python index semantics
                if (is_dynamic_attr and subscript.value.* == .attribute) {
                    const attr = subscript.value.attribute;
                    const self_name = if (self.method_nesting_depth > 0) "__self" else "self";
                    // Generate: self.__dict__.get("a").?.pyListSetPy(idx, runtime.PyValue.from(val))
                    try self.emit(self_name);
                    try self.output.writer(self.allocator).print(".__dict__.get(\"{s}\").?.pyListSetPy(", .{attr.attr});
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit(", runtime.PyValue.from(");
                    // Get the RHS - also need to check if it's a dynamic attr
                    if (assign.value.* == .attribute) {
                        const rhs_attr = assign.value.attribute;
                        if (rhs_attr.value.* == .name) {
                            const rhs_obj = rhs_attr.value.name.id;
                            if (std.mem.eql(u8, rhs_obj, "self") or std.mem.eql(u8, rhs_obj, "__self")) {
                                // RHS is also a dynamic attribute - need to get from __dict__
                                const rhs_is_dynamic = blk2: {
                                    if (self.current_class_name) |class_name| {
                                        if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                                            if (class_info.fields.contains(rhs_attr.attr)) {
                                                break :blk2 false;
                                            }
                                        }
                                    }
                                    break :blk2 true;
                                };
                                if (rhs_is_dynamic) {
                                    try self.emit(self_name);
                                    try self.output.writer(self.allocator).print(".__dict__.get(\"{s}\").?", .{rhs_attr.attr});
                                    try self.emit("));\n");
                                    return;
                                }
                            }
                        }
                    }
                    try self.genExpr(assign.value.*);
                    try self.emit("));\n");
                    return;
                }

                if (container_type == .defaultdict) {
                    // defaultdict assignment: d.put(key, runtime.PyValue.from(value))
                    try self.emit("try ");
                    if (is_nested) {
                        try self.genSubscriptLHS(subscript.value.subscript);
                    } else {
                        try self.genExpr(subscript.value.*);
                    }
                    try self.emit(".put(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit(", runtime.PyValue.from(");
                    try self.genExpr(assign.value.*);
                    try self.emit("));\n");
                } else if (container_traits.isDict(container_type)) {
                    // Dict assignment: dict.put(key, value)
                    // Check if dict has PyValue values - if so, wrap the value
                    const dict_value_type = container_type.dict.value.*;
                    const needs_pyvalue_wrap = dict_value_type == .pyvalue;

                    try self.emit("try ");
                    if (is_nested) {
                        try self.genSubscriptLHS(subscript.value.subscript);
                    } else {
                        try self.genExpr(subscript.value.*);
                    }
                    try self.emit(".put(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit(", ");
                    if (needs_pyvalue_wrap) {
                        try self.emit("try runtime.PyValue.fromAlloc(__global_allocator, ");
                        try self.genExpr(assign.value.*);
                        try self.emit(")");
                    } else {
                        try self.genExpr(assign.value.*);
                    }
                    try self.emit(");\n");
                } else if (container_traits.isList(container_type) or (subscript.value.* == .name and self.isArrayListVar(subscript.value.name.id))) {
                    // List assignment: list.items[idx] = value
                    // Also handles ArrayList variables which may have .array type from inference
                    // Need to handle negative indices: a[-1] = x → a.items[a.items.len - 1] = x

                    // Check if index is a negative literal
                    const is_negative_literal = subscript.slice.index.* == .unaryop and
                        subscript.slice.index.unaryop.op == .USub and
                        subscript.slice.index.unaryop.operand.* == .constant and
                        subscript.slice.index.unaryop.operand.constant.value == .int;

                    if (is_nested) {
                        try self.genSubscriptLHS(subscript.value.subscript);
                    } else {
                        try self.genExpr(subscript.value.*);
                    }

                    if (is_negative_literal) {
                        // For negative literal index: use len - abs(idx)
                        const neg_val = subscript.slice.index.unaryop.operand.constant.value.int;
                        try self.output.writer(self.allocator).print(".items[", .{});
                        if (is_nested) {
                            try self.genSubscriptLHS(subscript.value.subscript);
                        } else {
                            try self.genExpr(subscript.value.*);
                        }
                        try self.output.writer(self.allocator).print(".items.len - {d}] = ", .{neg_val});
                    } else {
                        // For non-negative or runtime index: cast to usize
                        try self.emit(".items[@intCast(");
                        try self.genExpr(subscript.slice.index.*);
                        try self.emit(")] = ");
                    }
                    try self.genExpr(assign.value.*);
                    try self.emit(";\n");
                } else if (container_type == .pyvalue) {
                    // PyValue dict assignment: pyval.pyDictPut(allocator, key, value)
                    // PyValue can contain a dict (wrapped as ptr to StringHashMap)
                    const index_type = try self.inferExprScoped(subscript.slice.index.*);
                    if (string_traits.isString(index_type) or index_type == .pyvalue or type_traits.isUnknown(index_type)) {
                        // String key (or PyValue containing string, or unknown) - treat as dict assignment
                        // For PyValue/unknown key, we need to unwrap it to string with .asString()
                        try self.emit("try ");
                        if (is_nested) {
                            try self.genSubscriptLHS(subscript.value.subscript);
                        } else {
                            try self.genExpr(subscript.value.*);
                        }
                        try self.emit(".pyDictPut(__global_allocator, ");
                        if (index_type == .pyvalue or type_traits.isUnknown(index_type)) {
                            try self.genExpr(subscript.slice.index.*);
                            try self.emit(".asString()");
                        } else {
                            try self.genExpr(subscript.slice.index.*);
                        }
                        try self.emit(", try runtime.PyValue.fromAlloc(__global_allocator, ");
                        try self.genExpr(assign.value.*);
                        try self.emit("));\n");
                    } else {
                        // Int key - treat as list/tuple access (use pyAt for now, but assignment needs different approach)
                        // For now, fall through to generic handling
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
                } else {
                    // Generic array/slice assignment: arr[idx] = value
                    // Also handles unknown type with string/pyvalue key (could be dict)
                    const index_type = try self.inferExprScoped(subscript.slice.index.*);
                    // For nested subscripts with PyValue-style iteration variable (string key from dict iteration)
                    // or unknown containers with string/pyvalue keys, use runtime dict handling
                    // Check if this is a nested subscript where the index comes from PyValue iteration
                    const is_pyvalue_key = (string_traits.isString(index_type) or index_type == .pyvalue or type_traits.isUnknown(index_type));
                    if (is_nested and is_pyvalue_key) {
                        // Unknown container with string/pyvalue key - likely dict access
                        // Use runtime type check
                        _ = try self.emitInlineBlockStart("dict");
                        try self.emit("\n");
                        self.indent_level += 1;
                        const cont = try self.name_gen.temp();
                        try self.emitIndent();
                        try self.emitFmt("const {s} = ", .{cont});
                        if (is_nested) {
                            try self.genSubscriptLHS(subscript.value.subscript);
                        } else {
                            try self.genExpr(subscript.value.*);
                        }
                        try self.emit(";\n");
                        // For PyValue keys, extract the string
                        const key = try self.name_gen.temp();
                        if (index_type == .pyvalue) {
                            try self.emitIndent();
                            try self.emitFmt("const {s} = ", .{key});
                            try self.genExpr(subscript.slice.index.*);
                            try self.emit(".asString();\n");
                        }
                        try self.emitIndent();
                        try self.emitFmt("if (@TypeOf({s}) == runtime.PyValue) {{\n", .{cont});
                        self.indent_level += 1;
                        try self.emitIndent();
                        try self.emitFmt("try {s}.pyDictPut(__global_allocator, ", .{cont});
                        if (index_type == .pyvalue) {
                            try self.emit(key);
                        } else {
                            try self.genExpr(subscript.slice.index.*);
                        }
                        try self.emit(", try runtime.PyValue.fromAlloc(__global_allocator, ");
                        try self.genExpr(assign.value.*);
                        try self.emit("));\n");
                        self.indent_level -= 1;
                        try self.emitIndent();
                        try self.emit("} else {\n");
                        self.indent_level += 1;
                        try self.emitIndent();
                        // ArrayHashMap.put() doesn't take allocator
                        try self.emitFmt("try {s}.put(", .{cont});
                        if (index_type == .pyvalue) {
                            try self.emit(key);
                        } else {
                            try self.genExpr(subscript.slice.index.*);
                        }
                        try self.emit(", ");
                        try self.genExpr(assign.value.*);
                        try self.emit(");\n");
                        self.indent_level -= 1;
                        try self.emitIndent();
                        try self.emit("}\n");
                        self.indent_level -= 1;
                        try self.emitIndent();
                        try self.emitInlineBlockEnd();
                        // Labeled block used as statement needs semicolon
                        try self.emit(";\n");
                    } else {
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

                // Generate unique temp names for this scope
                const slice_target = try self.name_gen.temp();
                const slice_src = try self.name_gen.temp();

                // Get container reference
                try self.emitIndent();
                try self.emitFmt("const {s} = &", .{slice_target});
                try self.genExpr(subscript.value.*);
                try self.emit(";\n");

                // Get source data
                try self.emitIndent();
                try self.emitFmt("const {s} = ", .{slice_src});
                try self.genExpr(assign.value.*);
                try self.emit(";\n");

                if (container_traits.isList(container_type)) {
                    if (is_full_slice) {
                        // a[:] = data - replace entire list
                        const item = try self.name_gen.temp();
                        try self.emitIndent();
                        try self.emitFmt("{s}.clearRetainingCapacity();\n", .{slice_target});
                        try self.emitIndent();
                        try self.emitFmt("for ({s}.items) |{s}| {{\n", .{ slice_src, item });
                        self.indent_level += 1;
                        try self.emitIndent();
                        try self.emitFmt("{s}.append(__global_allocator, {s}) catch unreachable;\n", .{ slice_target, item });
                        self.indent_level -= 1;
                        try self.emitIndent();
                        try self.emit("}\n");
                    } else {
                        // a[start:end] = data - replace slice with new data
                        const slice_start = try self.name_gen.temp();
                        const slice_end = try self.name_gen.temp();
                        const i = try self.name_gen.temp();
                        const j = try self.name_gen.temp();
                        const item = try self.name_gen.temp();

                        // Calculate start and end indices
                        try self.emitIndent();
                        if (slice.lower) |lower| {
                            try self.emitFmt("const {s}: usize = @intCast(", .{slice_start});
                            try self.genExpr(lower.*);
                            try self.emit(");\n");
                        } else {
                            try self.emitFmt("const {s}: usize = 0;\n", .{slice_start});
                        }

                        try self.emitIndent();
                        if (slice.upper) |upper| {
                            try self.emitFmt("const {s}: usize = @intCast(", .{slice_end});
                            try self.genExpr(upper.*);
                            try self.emit(");\n");
                        } else {
                            try self.emitFmt("const {s}: usize = {s}.items.len;\n", .{ slice_end, slice_target });
                        }

                        // Remove elements in [start, end) range
                        try self.emitIndent();
                        try self.emitFmt("var {s}: usize = {s};\n", .{ i, slice_start });
                        try self.emitIndent();
                        try self.emitFmt("while ({s} < {s}) : ({s} += 1) {{\n", .{ i, slice_end, i });
                        self.indent_level += 1;
                        try self.emitIndent();
                        try self.emitFmt("_ = {s}.orderedRemove({s});\n", .{ slice_target, slice_start });
                        self.indent_level -= 1;
                        try self.emitIndent();
                        try self.emit("}\n");

                        // Insert new elements at start position
                        try self.emitIndent();
                        try self.emitFmt("var {s}: usize = 0;\n", .{j});
                        try self.emitIndent();
                        try self.emitFmt("for ({s}.items) |{s}| {{\n", .{ slice_src, item });
                        self.indent_level += 1;
                        try self.emitIndent();
                        try self.emitFmt("{s}.insert(__global_allocator, {s} + {s}, {s}) catch unreachable;\n", .{ slice_target, slice_start, j, item });
                        try self.emitIndent();
                        try self.emitFmt("{s} += 1;\n", .{j});
                        self.indent_level -= 1;
                        try self.emitIndent();
                        try self.emit("}\n");
                    }
                } else {
                    // Fixed array/slice/ArrayList: copy items
                    if (slice.step != null) {
                        // Stepped slice assignment: a[start::step] = src
                        const idx = try self.name_gen.temp();
                        const step = try self.name_gen.temp();
                        const target_len = try self.name_gen.temp();
                        const src_data = try self.name_gen.temp();
                        const src_idx = try self.name_gen.temp();

                        // Replace elements at indices start, start+step, start+2*step, ...
                        try self.emitIndent();
                        if (slice.lower) |lower| {
                            try self.emitFmt("var {s}: usize = @intCast(", .{idx});
                            try self.genExpr(lower.*);
                            try self.emit(");\n");
                        } else {
                            try self.emitFmt("var {s}: usize = 0;\n", .{idx});
                        }

                        try self.emitIndent();
                        try self.emitFmt("const {s}: usize = @intCast(", .{step});
                        try self.genExpr(slice.step.?.*);
                        try self.emit(");\n");

                        try self.emitIndent();
                        // Use container_dispatch helpers - avoids inline @hasField monomorphization
                        try self.emitFmt("const {s} = runtime.container_dispatch.getPtrLen(@TypeOf({s}), {s});\n", .{ target_len, slice_target, slice_target });
                        try self.emitIndent();
                        try self.emitFmt("const {s} = runtime.container_dispatch.getSlice(@TypeOf({s}), {s});\n", .{ src_data, slice_src, slice_src });
                        try self.emitIndent();
                        try self.emitFmt("var {s}: usize = 0;\n", .{src_idx});
                        try self.emitIndent();
                        try self.emitFmt("while ({s} < {s} and {s} < {s}.len) {{\n", .{ idx, target_len, src_idx, src_data });
                        self.indent_level += 1;
                        try self.emitIndent();
                        try self.emitFmt("runtime.container_dispatch.setPtrAt(@TypeOf({s}), @TypeOf({s}[0]), {s}, {s}, {s}[{s}]);\n", .{ slice_target, src_data, slice_target, idx, src_data, src_idx });
                        try self.emitIndent();
                        try self.emitFmt("{s} += {s};\n", .{ idx, step });
                        try self.emitIndent();
                        try self.emitFmt("{s} += 1;\n", .{src_idx});
                        self.indent_level -= 1;
                        try self.emitIndent();
                        try self.emit("}\n");
                    } else {
                        // Contiguous slice assignment
                        const slice_start = try self.name_gen.temp();
                        const slice_end = try self.name_gen.temp();
                        const copy_len = try self.name_gen.temp();
                        const target_slice = try self.name_gen.temp();
                        const src_slice = try self.name_gen.temp();

                        try self.emitIndent();
                        if (slice.lower) |lower| {
                            try self.emitFmt("const {s}: usize = @intCast(", .{slice_start});
                            try self.genExpr(lower.*);
                            try self.emit(");\n");
                        } else {
                            try self.emitFmt("const {s}: usize = 0;\n", .{slice_start});
                        }

                        try self.emitIndent();
                        if (slice.upper) |upper| {
                            try self.emitFmt("const {s}: usize = @intCast(", .{slice_end});
                            try self.genExpr(upper.*);
                            try self.emit(");\n");
                        } else {
                            // Use container_dispatch helper - avoids inline @hasField monomorphization
                            try self.emitFmt("const {s}: usize = runtime.container_dispatch.getPtrLen(@TypeOf({s}), {s});\n", .{ slice_end, slice_target, slice_target });
                        }

                        try self.emitIndent();
                        // Use container_dispatch helpers - avoids inline @hasField monomorphization
                        try self.emitFmt("const {s} = @min({s} - {s}, runtime.container_dispatch.getLen(@TypeOf({s}), {s}));\n", .{ copy_len, slice_end, slice_start, slice_src, slice_src });
                        try self.emitIndent();
                        try self.emitFmt("const {s} = runtime.container_dispatch.getMutSlice(@TypeOf({s}.*), {s});\n", .{ target_slice, slice_target, slice_target });
                        try self.emitIndent();
                        try self.emitFmt("const {s} = runtime.container_dispatch.getSlice(@TypeOf({s}), {s});\n", .{ src_slice, slice_src, slice_src });
                        try self.emitIndent();
                        try self.emitFmt("@memcpy({s}[{s}..][0..{s}], {s}[0..{s}]);\n", .{ target_slice, slice_start, copy_len, src_slice, copy_len });
                    }
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
    if (!type_traits.isClassInstance(obj_type)) return false;

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
