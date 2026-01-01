/// Conditional statement code generation (if, pass, break, continue)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const CodeBuilder = @import("../../code_builder.zig").CodeBuilder;
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const bool_conv = @import("../../helpers/bool_conv.zig");
const zig_keywords = @import("utils.zig_keywords");

/// Information about a variable to be hoisted
const HoistedVar = struct {
    name: []const u8,
    node: ast.Node,
};

/// Check if a condition is a comptime constant and return its boolean value
/// Returns null if not comptime constant, true/false otherwise
/// anytype_params: set of parameter names that are anytype (cannot be comptime evaluated)
fn isComptimeConstantCondition(node: ast.Node, anytype_params: anytype) ?bool {
    switch (node) {
        // Literal True/False or numeric constants
        .constant => |c| {
            switch (c.value) {
                .bool => |b| return b,
                // Python truthy: 0 is False, any other int is True
                .int => |i| return i != 0,
                .float => |f| return f != 0.0,
                // Empty string is falsy
                .string => |s| return s.len > 0,
                .none => return false,
                else => return null,
            }
        },
        // isinstance() returns true at compile time ONLY for non-anytype typed variables
        // NOTE: User-defined type check functions (isint, isnum, isRat) are NOT comptime constant
        // because they call isinstance internally which may have runtime behavior for anytype
        .call => |call| {
            if (call.func.* == .name) {
                const func_name = call.func.name.id;
                // Only isinstance itself can be comptime evaluated, not user wrappers
                if (std.mem.eql(u8, func_name, "isinstance")) {
                    // Check if the argument is an anytype parameter
                    if (call.args.len > 0 and call.args[0] == .name) {
                        const arg_name = call.args[0].name.id;
                        if (anytype_params.contains(arg_name)) {
                            // Cannot evaluate at comptime for anytype params
                            return null;
                        }
                    }
                    return true;
                }
            }
            return null;
        },
        // not <expr> - negate the inner value
        .unaryop => |u| {
            if (u.op == .Not) {
                if (isComptimeConstantCondition(u.operand.*, anytype_params)) |inner| {
                    return !inner;
                }
            }
            return null;
        },
        else => return null,
    }
}

/// Info about a type check pattern: if not isint(x): raise TypeError
const TypeCheckRaiseInfo = struct {
    param_name: []const u8,
    check_type: []const u8, // "int", "float", etc.
};

/// Info about a positive type check: if isClassName(x): ... OR if isinstance(x, ClassName): ...
/// Used for type narrowing within the if-body
const TypeNarrowingInfo = struct {
    param_name: []const u8,
    class_name: []const u8,
};

/// Detect if condition is a positive type check on an anytype param
/// Returns info to narrow the type within the if-body
/// Pattern: isClassName(x) or isinstance(x, ClassName) where x is anytype
fn detectTypeNarrowingCondition(condition: ast.Node, anytype_params: anytype) ?TypeNarrowingInfo {
    if (condition != .call) return null;
    const call = condition.call;
    if (call.func.* != .name) return null;
    const func_name = call.func.name.id;

    // Pattern 1: isClassName(param) - e.g., isRat(other)
    if (std.mem.startsWith(u8, func_name, "is") and call.args.len >= 1 and call.args[0] == .name) {
        const arg_name = call.args[0].name.id;
        if (anytype_params.contains(arg_name)) {
            // Extract class name from isClassName -> ClassName
            const class_name = func_name[2..]; // Remove "is" prefix
            if (class_name.len > 0) {
                return TypeNarrowingInfo{ .param_name = arg_name, .class_name = class_name };
            }
        }
    }
    // Pattern 2: isinstance(param, ClassName)
    else if (std.mem.eql(u8, func_name, "isinstance")) {
        if (call.args.len >= 2 and call.args[0] == .name and call.args[1] == .name) {
            const arg_name = call.args[0].name.id;
            const type_name = call.args[1].name.id;
            if (anytype_params.contains(arg_name)) {
                return TypeNarrowingInfo{ .param_name = arg_name, .class_name = type_name };
            }
        }
    }

    return null;
}

/// Check if an if statement is a type-check-then-raise pattern for an anytype param
/// Pattern: if not isinstance(x, int): raise TypeError  OR  if not isint(x): raise TypeError
fn isTypeCheckRaisePattern(if_stmt: ast.Node.If, anytype_params: anytype) ?TypeCheckRaiseInfo {
    // Body must be a single raise TypeError
    if (if_stmt.body.len != 1) return null;
    if (if_stmt.body[0] != .raise_stmt) return null;
    const raise = if_stmt.body[0].raise_stmt;
    if (raise.exc == null) return null;

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
    if (!is_type_error) return null;

    // Condition must be: not isint(x) or not isinstance(x, type)
    if (if_stmt.condition.* != .unaryop) return null;
    const unary = if_stmt.condition.unaryop;
    if (unary.op != .Not) return null;
    if (unary.operand.* != .call) return null;

    const call = unary.operand.call;
    if (call.func.* != .name) return null;
    const func_name = call.func.name.id;

    // Check for isint(x) pattern
    if (std.mem.eql(u8, func_name, "isint")) {
        if (call.args.len >= 1 and call.args[0] == .name) {
            const arg_name = call.args[0].name.id;
            if (anytype_params.contains(arg_name)) {
                return TypeCheckRaiseInfo{ .param_name = arg_name, .check_type = "int" };
            }
        }
    }
    // Check for isinstance(x, int) pattern
    else if (std.mem.eql(u8, func_name, "isinstance")) {
        if (call.args.len >= 2 and call.args[0] == .name and call.args[1] == .name) {
            const arg_name = call.args[0].name.id;
            const type_name = call.args[1].name.id;
            if (anytype_params.contains(arg_name)) {
                return TypeCheckRaiseInfo{ .param_name = arg_name, .check_type = type_name };
            }
        }
    }

    return null;
}

/// Pre-scan an expression for walrus operators (named_expr) and emit variable declarations
fn emitWalrusDeclarations(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    switch (node) {
        .named_expr => |ne| {
            // Found a walrus operator - declare the variable if not already declared
            if (ne.target.* == .name) {
                const var_name = ne.target.name.id;
                if (!self.isDeclared(var_name)) {
                    // Infer the type from the value
                    const value_type = try self.type_inferrer.inferExpr(ne.value.*);

                    // Two-Flow: For uncertain types, use runtime.PyValue
                    const is_uncertain = type_traits.isUnknown(value_type) or value_type == .pyvalue;

                    try self.emitIndent();
                    try self.emit("var ");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), var_name);
                    try self.emit(": ");

                    if (is_uncertain) {
                        try self.emit("runtime.PyValue");
                    } else {
                        // Get the Zig type string
                        var type_buf = std.ArrayList(u8){};
                        defer type_buf.deinit(self.allocator);
                        value_type.toZigType(self.allocator, &type_buf) catch {
                            try type_buf.writer(self.allocator).writeAll("i64");
                        };
                        try self.emit(type_buf.items);
                    }
                    try self.emit(" = undefined;\n");
                    try self.declareVar(var_name);
                }
            }
            // Also scan the value expression for nested walrus operators
            try emitWalrusDeclarations(self, ne.value.*);
        },
        .binop => |b| {
            try emitWalrusDeclarations(self, b.left.*);
            try emitWalrusDeclarations(self, b.right.*);
        },
        .compare => |c| {
            try emitWalrusDeclarations(self, c.left.*);
            for (c.comparators) |comp| {
                try emitWalrusDeclarations(self, comp);
            }
        },
        .boolop => |b| {
            for (b.values) |val| {
                try emitWalrusDeclarations(self, val);
            }
        },
        .call => |c| {
            try emitWalrusDeclarations(self, c.func.*);
            for (c.args) |arg| {
                try emitWalrusDeclarations(self, arg);
            }
        },
        .unaryop => |u| {
            try emitWalrusDeclarations(self, u.operand.*);
        },
        else => {}, // Other node types don't contain expressions we need to scan
    }
}

/// Collect variables assigned in a statement body that are not yet declared
/// These need to be hoisted before the if statement
fn collectAssignedVars(self: *NativeCodegen, stmts: []const ast.Node, vars: *std.ArrayList(HoistedVar)) CodegenError!void {
    for (stmts) |stmt| {
        switch (stmt) {
            .assign => |assign| {
                // Check each target for simple variable assignments
                for (assign.targets) |target| {
                    if (target == .name) {
                        const var_name = target.name.id;
                        if (!self.isDeclared(var_name)) {
                            // Check if already in our list
                            var found = false;
                            for (vars.items) |v| {
                                if (std.mem.eql(u8, v.name, var_name)) {
                                    found = true;
                                    break;
                                }
                            }
                            if (!found) {
                                try vars.append(self.allocator, HoistedVar{ .name = var_name, .node = assign.value.* });
                            }
                        }
                    }
                }
            },
            .if_stmt => |nested_if| {
                // Recursively scan nested if statements
                try collectAssignedVars(self, nested_if.body, vars);
                try collectAssignedVars(self, nested_if.else_body, vars);
            },
            else => {},
        }
    }
}

/// Collect function definition names from statements
/// Used to identify functions defined in if/else branches that need hoisting
fn collectFunctionDefs(stmts: []const ast.Node, funcs: *std.ArrayList([]const u8), allocator: std.mem.Allocator) !void {
    for (stmts) |stmt| {
        switch (stmt) {
            .function_def => |fd| {
                // Check if this function name is already in our list
                var found = false;
                for (funcs.items) |name| {
                    if (std.mem.eql(u8, name, fd.name)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    try funcs.append(allocator, fd.name);
                }
            },
            .if_stmt => |nested_if| {
                try collectFunctionDefs(nested_if.body, funcs, allocator);
                try collectFunctionDefs(nested_if.else_body, funcs, allocator);
            },
            else => {},
        }
    }
}

/// Collect class names defined in a list of statements
/// Used to prevent hoisting variables whose types are defined inside the block
fn collectNestedClassNames(stmts: []const ast.Node, classes: *std.ArrayList([]const u8), allocator: std.mem.Allocator) !void {
    for (stmts) |stmt| {
        switch (stmt) {
            .class_def => |cd| {
                try classes.append(allocator, cd.name);
            },
            .if_stmt => |nested_if| {
                try collectNestedClassNames(nested_if.body, classes, allocator);
                try collectNestedClassNames(nested_if.else_body, classes, allocator);
            },
            .for_stmt => |for_stmt| {
                try collectNestedClassNames(for_stmt.body, classes, allocator);
                if (for_stmt.orelse_body) |orelse_body| {
                    try collectNestedClassNames(orelse_body, classes, allocator);
                }
            },
            .while_stmt => |while_stmt| {
                try collectNestedClassNames(while_stmt.body, classes, allocator);
                if (while_stmt.orelse_body) |orelse_body| {
                    try collectNestedClassNames(orelse_body, classes, allocator);
                }
            },
            .try_stmt => |try_stmt| {
                try collectNestedClassNames(try_stmt.body, classes, allocator);
                for (try_stmt.handlers) |handler| {
                    try collectNestedClassNames(handler.body, classes, allocator);
                }
                try collectNestedClassNames(try_stmt.else_body, classes, allocator);
                try collectNestedClassNames(try_stmt.finalbody, classes, allocator);
            },
            .with_stmt => |with_stmt| {
                try collectNestedClassNames(with_stmt.body, classes, allocator);
            },
            .match_stmt => |match_stmt| {
                for (match_stmt.cases) |case| {
                    try collectNestedClassNames(case.body, classes, allocator);
                }
            },
            else => {},
        }
    }
}

/// Generate if statement
pub fn genIf(self: *NativeCodegen, if_stmt: ast.Node.If) CodegenError!void {
    return genIfImpl(self, if_stmt, false, true);
}

/// Internal if generation with option to skip initial indent (for elif chains)
/// hoist_vars: whether to pre-scan and hoist variable declarations (only for top-level if)
fn genIfImpl(self: *NativeCodegen, if_stmt: ast.Node.If, skip_indent: bool, hoist_vars: bool) CodegenError!void {
    // NOTE: Type-check-raise patterns (if not isint(x): raise TypeError) are now handled
    // at the function level in function_gen.zig using comptime branching that wraps the
    // entire function body. This ensures gcd(x, y) calls are only analyzed for valid types.

    // Check for comptime constant conditions - eliminate dead branches
    if (isComptimeConstantCondition(if_stmt.condition.*, self.anytype_params)) |comptime_value| {
        // Even though condition is comptime constant, we still need to "evaluate" it
        // to mark any variables it uses as referenced (e.g., isinstance(x, T) uses x)
        // Generate: _ = (condition); before the body
        try self.emitIndent();
        try self.emit("_ = ");
        try self.genExpr(if_stmt.condition.*);
        try self.emit(";\n");

        if (comptime_value) {
            // Condition is comptime True - only emit if body
            for (if_stmt.body) |stmt| {
                try self.generateStmt(stmt);
            }
            return;
        } else {
            // Condition is comptime False - only emit else body
            for (if_stmt.else_body) |stmt| {
                try self.generateStmt(stmt);
            }
            return;
        }
    }

    var builder = CodeBuilder.init(self);

    // Pre-scan condition for walrus operators and emit variable declarations
    try emitWalrusDeclarations(self, if_stmt.condition.*);

    // Function definitions inside if blocks are skipped in body generation (below)
    // The variable is usually already declared (e.g., from an import) so we don't hoist

    // For top-level if, hoist variables assigned in any branch
    if (hoist_vars) {
        var assigned_vars = std.ArrayList(HoistedVar){};
        defer assigned_vars.deinit(self.allocator);

        // First, collect class names defined inside the if/else blocks
        // These cannot be hoisted as types
        var nested_classes = std.ArrayList([]const u8){};
        defer nested_classes.deinit(self.allocator);
        collectNestedClassNames(if_stmt.body, &nested_classes, self.allocator) catch {};
        collectNestedClassNames(if_stmt.else_body, &nested_classes, self.allocator) catch {};

        // Collect function definitions from all branches
        // Functions defined in if/else need their names hoisted for Python scope semantics
        var func_defs = std.ArrayList([]const u8){};
        defer func_defs.deinit(self.allocator);
        collectFunctionDefs(if_stmt.body, &func_defs, self.allocator) catch {};
        collectFunctionDefs(if_stmt.else_body, &func_defs, self.allocator) catch {};

        // Hoist function names as DynamicClosure (will be assigned in branches)
        for (func_defs.items) |func_name| {
            // Skip if already declared
            if (self.isDeclared(func_name)) continue;

            try self.emitIndent();
            // Use a struct wrapper that can hold any closure and provides .call()
            try self.output.writer(self.allocator).print(
                "var {s}: runtime.DynamicClosure = undefined;\n",
                .{func_name},
            );
            try self.declareVar(func_name);
            // Mark as closure so calls use .call() syntax
            const func_copy = try self.arena.allocator().dupe(u8, func_name);
            try self.closure_vars.put(func_copy, {});
            // Also mark as hoisted DynamicClosure so zero_capture.zig knows to assign, not declare
            const func_copy2 = try self.arena.allocator().dupe(u8, func_name);
            try self.hoisted_dynamic_closures.put(func_copy2, {});
        }

        // Collect variables from all branches
        try collectAssignedVars(self, if_stmt.body, &assigned_vars);
        try collectAssignedVars(self, if_stmt.else_body, &assigned_vars);

        // Emit declarations for variables that will be assigned in branches
        for (assigned_vars.items) |v| {
            // Skip if already hoisted at function level
            if (self.hoisted_vars.contains(v.name)) continue;

            // Skip module-level variables/constants - they're already declared at module level
            // This prevents shadowing errors for __name__, __file__, and user-defined module vars
            if (self.module_level_vars.contains(v.name)) continue;

            // Skip module-level functions - they're already declared as functions
            // Python allows `genslices = rslices` to reassign function names,
            // but in Zig the function is already defined so we skip hoisting
            if (self.module_level_funcs.contains(v.name)) continue;

            // Skip variables that are renamed parameters (e.g., d -> __m2_p_d)
            // The parameter was renamed to avoid shadowing, but the Python code still
            // uses the original name. We should not create a new var for the original name.
            if (self.var_renames.contains(v.name)) continue;

            // Skip function aliases - the assignment value is a module-level function
            // e.g., `permutations = rpermutation` - rpermutation is already a function
            if (v.node == .name) {
                if (self.module_level_funcs.contains(v.node.name.id)) continue;
            }

            const var_type = self.type_inferrer.inferExpr(v.node) catch .unknown;

            // Skip hoisting if type refers to a class defined inside the block
            if (type_traits.isClassInstance(var_type)) {
                var skip = false;
                for (nested_classes.items) |nested_class| {
                    if (std.mem.eql(u8, var_type.class_instance, nested_class)) {
                        skip = true;
                        break;
                    }
                }
                if (skip) continue;
            }

            var type_buf = std.ArrayList(u8){};
            defer type_buf.deinit(self.allocator);
            var_type.toZigType(self.allocator, &type_buf) catch {
                try type_buf.writer(self.allocator).writeAll("i64");
            };

            try self.emitIndent();
            try self.emit("var ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), v.name);
            try self.emit(": ");
            try self.emit(type_buf.items);
            try self.emit(" = undefined;\n");
            try self.declareVar(v.name);
        }
    }

    // Check for FeatureMacros subscript - these are comptime-known, so we can eliminate dead branches
    if (if_stmt.condition.* == .subscript) {
        const sub = if_stmt.condition.subscript;
        if (sub.value.* == .name and std.mem.eql(u8, sub.value.name.id, "feature_macros")) {
            // Evaluate the feature macro key at codegen time
            if (sub.slice == .index and sub.slice.index.* == .constant) {
                const key = sub.slice.index.constant.value.string;
                // Evaluate known feature macros
                const value = blk: {
                    if (std.mem.eql(u8, key, "HAVE_FORK")) break :blk true;
                    if (std.mem.eql(u8, key, "MS_WINDOWS")) break :blk false;
                    if (std.mem.eql(u8, key, "PY_HAVE_THREAD_NATIVE_ID")) break :blk true;
                    if (std.mem.eql(u8, key, "Py_REF_DEBUG")) break :blk false;
                    if (std.mem.eql(u8, key, "Py_TRACE_REFS")) break :blk false;
                    if (std.mem.eql(u8, key, "USE_STACKCHECK")) break :blk false;
                    break :blk false;
                };

                if (value) {
                    // Condition is true - only emit if-body, skip else
                    for (if_stmt.body) |stmt| {
                        // Skip function definitions inside if blocks
                        if (stmt == .function_def) continue;
                        try self.generateStmt(stmt);
                    }
                } else {
                    // Condition is false - only emit else-body
                    for (if_stmt.else_body) |stmt| {
                        if (stmt == .function_def) continue;
                        try self.generateStmt(stmt);
                    }
                }
                return; // Early return - we've handled this if-statement
            }
        }
    }

    if (!skip_indent) {
        try self.emitIndent();
    }
    _ = try builder.write("if (");

    // Check for FeatureMacros subscript - these return comptime bool
    const is_feature_macros_subscript = blk: {
        if (if_stmt.condition.* == .subscript) {
            const sub = if_stmt.condition.subscript;
            if (sub.value.* == .name) {
                break :blk std.mem.eql(u8, sub.value.name.id, "feature_macros");
            }
        }
        break :blk false;
    };

    // Check condition type - need to handle PyObject truthiness
    const cond_type = self.type_inferrer.inferExpr(if_stmt.condition.*) catch .unknown;

    // Check if condition is a class comparison that needs .__bool__() wrapper
    // Class comparison methods like __gt__ may return non-bool types (e.g., SymbolicBool)
    const is_class_comparison = blk: {
        if (if_stmt.condition.* == .compare) {
            const compare = if_stmt.condition.compare;
            const left_type = self.type_inferrer.inferExpr(compare.left.*) catch .unknown;
            if (type_traits.isClassInstance(left_type)) {
                break :blk true;
            }
            // Also check comparators for class instances (e.g., 0 < x where x is class)
            for (compare.comparators) |comp| {
                const comp_type = self.type_inferrer.inferExpr(comp) catch .unknown;
                if (type_traits.isClassInstance(comp_type)) {
                    break :blk true;
                }
            }
        }
        break :blk false;
    };

    if (is_feature_macros_subscript) {
        // FeatureMacros subscript returns comptime bool - use directly
        try self.genExpr(if_stmt.condition.*);
    } else if (self.needsVMFallback(if_stmt.condition.*)) {
        // VM fallback generates PyValue.from(...), need .isTruthy() for bool conversion
        // This check MUST come before cond_type == .bool because type inference may
        // return .bool (expected return type) but codegen produces PyValue due to fallback
        try self.genExpr(if_stmt.condition.*);
        _ = try builder.write(".isTruthy()");
    } else if (cond_type == .bool) {
        // Bool type - use directly without wrapping
        try self.genExpr(if_stmt.condition.*);
    } else if (is_class_comparison) {
        // Class comparison - wrap with .__bool__() since dunder may return non-bool
        // The comparison result (e.g., SymbolicBool) is not an error union, but __bool__() returns !bool
        // Note: Line 553 adds the closing ) for the if(, so we don't include it here
        // genCompare wraps its output in (), so if we want: try (comparison).__bool__()
        // we write: "try (" + genCompare("(x.__gt__(0))") + ").__bool__()"
        // = "try ((x.__gt__(0)))).__bool__()" - WRONG, too many parens
        // Actually genCompare writes ( at start and ) at end, so:
        // "try " + genCompare("(x.__gt__(0))") + ".__bool__()"
        // = "try (x.__gt__(0))).__bool__()" - need to wrap in () for try
        // Final: "try (" + genCompare + ")).__bool__()" gives try ((x.__gt__(0)))).__bool__() - extra )
        // Just use: genCompare + ".__bool__()" with try/catch at right place
        if (self.inside_try_body) {
            // Inside try: use try to unwrap both the comparison error and __bool__() error
            // Class comparison like x.__gt__(0) returns !*SymbolicBool (error union)
            // Then .__bool__() on *SymbolicBool returns !bool
            // Pattern: try (try comparison).__bool__()
            // genCompare outputs (comparison), so: try (try (x.__gt__(0))).__bool__()
            // prefix: "try (try " = 1 open
            // genCompare: "(x.__gt__(0))" = 1 open, 1 close (net 0)
            // suffix: ").__bool__()" = 1 close (to match my 1 open)
            _ = try builder.write("try (try ");
            try self.genExpr(if_stmt.condition.*);
            _ = try builder.write(").__bool__()");
        } else {
            // Outside try: use catch to handle errors
            // Pattern: ((comparison) catch unreachable).__bool__() catch false
            _ = try builder.write("((");
            try self.genExpr(if_stmt.condition.*);
            _ = try builder.write(") catch unreachable).__bool__() catch false");
        }
    } else if (type_traits.isUnknown(cond_type) or cond_type == .pyvalue) {
        // Two-Flow: Unknown/PyValue type - use runtime truthiness check
        _ = try builder.write("runtime.pyTruthy(");
        try self.genExpr(if_stmt.condition.*);
        _ = try builder.write(")");
    } else {
        // Use type-specific inline bool conversion to avoid anytype monomorphization
        const prefix = bool_conv.getBoolPrefix(cond_type);
        const suffix = bool_conv.getBoolSuffix(cond_type);
        try builder.withAsBool(prefix, suffix, struct {
            pub fn emit(_: *CodeBuilder, ctx: anytype) !void {
                try ctx.self.genExpr(ctx.condition.*);
            }
        }.emit, .{ .self = self, .condition = if_stmt.condition });
    }
    _ = try builder.write(")");
    _ = try builder.beginBlock();

    // Save control_flow_terminated before generating branches
    // An if-statement only terminates control flow if BOTH branches terminate
    const saved_control_flow = self.control_flow_terminated;
    self.control_flow_terminated = false;

    // Type narrowing: if condition is isClassName(param) or isinstance(param, ClassName),
    // track the narrowed type for the param so attribute access can use direct field access
    // for known fields (preserves i64/f64 types) instead of getAttrDynamic (always returns f64).
    // Methods still use getAttrDynamic since they need callable dispatch.
    const narrowing = detectTypeNarrowingCondition(if_stmt.condition.*, self.anytype_params);
    if (narrowing) |info| {
        self.narrowed_type_params.put(info.param_name, info.class_name) catch {};
    }

    for (if_stmt.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Clear narrowed type after if-body (doesn't apply in else branch or after)
    if (narrowing) |info| {
        _ = self.narrowed_type_params.swapRemove(info.param_name);
    }

    const if_body_terminates = self.control_flow_terminated;

    if (if_stmt.else_body.len > 0) {
        // Reset for else body
        self.control_flow_terminated = false;

        // Check if else_body is a single If statement (elif pattern)
        const is_elif = if_stmt.else_body.len == 1 and if_stmt.else_body[0] == .if_stmt;
        if (is_elif) {
            // elif: emit "} else " then recursively generate the nested if (without indent)
            self.dedent();
            try self.emitIndent();
            try self.emit("} else ");
            // Recursively generate the elif chain (skip_indent=true avoids double indentation)
            // hoist_vars=false since top-level if already hoisted all variables
            try genIfImpl(self, if_stmt.else_body[0].if_stmt, true, false);
        } else {
            // Regular else block
            // elseClause() now handles dedent internally
            _ = try builder.elseClause();
            _ = try builder.beginBlock();
            for (if_stmt.else_body) |stmt| {
                try self.generateStmt(stmt);
            }
            _ = try builder.endBlock();
        }

        const else_body_terminates = self.control_flow_terminated;

        // Control flow only terminates after if-statement if BOTH branches terminate
        self.control_flow_terminated = saved_control_flow or (if_body_terminates and else_body_terminates);
    } else {
        _ = try builder.endBlock();
        // No else branch means control flow continues (the if-body might not execute)
        self.control_flow_terminated = saved_control_flow;
    }
}

/// Generate pass statement (no-op)
pub fn genPass(self: *NativeCodegen) CodegenError!void {
    var builder = CodeBuilder.init(self);
    _ = try builder.line("// pass");
}

/// Generate break statement
pub fn genBreak(self: *NativeCodegen) CodegenError!void {
    // Mark control flow as terminated after break
    defer self.control_flow_terminated = true;

    // Check if we're inside a finally block - break needs special handling
    // In Python, break in finally should run finally then break outer loop
    // For now, we emit break from the labeled block with a special signal
    if (self.inside_finally_block) {
        try self.emitIndent();
        // Break from finally block - the outer code will handle the actual break
        // For now, just break from the finally block; outer loop break is TODO (requires labeled loops)
        try self.output.writer(self.allocator).print("break :__finally_blk_{d} null; // break from finally (outer loop break TODO)\n", .{self.current_finally_id});
        return;
    }

    // Nuitka-style finally code duplication: emit all finally blocks BEFORE break
    // This ensures Python semantics where finally runs before any exit
    if (self.hasActiveFinallyBlocks()) {
        // Execute all active finally blocks (innermost to outermost)
        try self.emitAllFinallyBlocks();
    }

    // Check if we're inside a try helper that needs break handling
    if (self.try_break_helper_id != null) {
        // Inside try helper - return error to signal break
        try self.emitIndent();
        try self.emit("return error.BreakRequested;\n");
    } else {
        var builder = CodeBuilder.init(self);
        _ = try builder.line("break;");
    }
}

/// Generate continue statement
pub fn genContinue(self: *NativeCodegen) CodegenError!void {
    // Mark control flow as terminated after continue
    defer self.control_flow_terminated = true;

    // Check if we're inside a finally block - continue needs special handling
    // In Python, continue in finally should run finally then continue outer loop
    // For now, we emit break from the labeled block with a special signal
    if (self.inside_finally_block) {
        try self.emitIndent();
        // Break from finally block - the outer code will handle the actual continue
        // For now, just break from the finally block; outer loop continue is TODO (requires labeled loops)
        try self.output.writer(self.allocator).print("break :__finally_blk_{d} null; // continue from finally (outer loop continue TODO)\n", .{self.current_finally_id});
        return;
    }

    // Nuitka-style finally code duplication: emit all finally blocks BEFORE continue
    // This ensures Python semantics where finally runs before any exit
    if (self.hasActiveFinallyBlocks()) {
        // Execute all active finally blocks (innermost to outermost)
        try self.emitAllFinallyBlocks();
    }

    var builder = CodeBuilder.init(self);
    _ = try builder.line("continue;");
}

/// Generate match statement (PEP 634)
/// Compiles to a chain of if/else if statements
pub fn genMatch(self: *NativeCodegen, match_stmt: ast.Node.Match) CodegenError!void {
    var builder = CodeBuilder.init(self);

    // Store subject in a temp variable
    try self.emitIndent();
    _ = try builder.write("const __match_subject = ");
    try self.genExpr(match_stmt.subject.*);
    _ = try builder.line(";");

    // Generate if/else if chain for each case
    var first = true;
    for (match_stmt.cases) |case| {
        try self.emitIndent();
        if (first) {
            _ = try builder.write("if (");
            first = false;
        } else {
            _ = try builder.write("} else if (");
        }

        // Generate pattern matching condition
        try genPatternCondition(self, case.pattern, "__match_subject");

        // Add guard condition if present
        if (case.guard) |guard| {
            _ = try builder.write(" and ");
            try self.genExpr(guard.*);
        }

        _ = try builder.line(") {");
        self.indent_level += 1;

        // Generate capture bindings if needed
        try genPatternBindings(self, case.pattern, "__match_subject");

        // Generate body
        for (case.body) |stmt| {
            try self.generateStmt(stmt);
        }

        self.indent_level -= 1;
    }

    // Close the if chain - add else clause for wildcard fallthrough
    if (match_stmt.cases.len > 0) {
        // Check if last case is wildcard (always matches)
        const last_case = match_stmt.cases[match_stmt.cases.len - 1];
        if (last_case.pattern != .wildcard and last_case.pattern != .capture) {
            // Add else block to handle unmatched cases
            try self.emitIndent();
            _ = try builder.line("} else {");
            self.indent_level += 1;
            try self.emitIndent();
            _ = try builder.line("// No pattern matched");
            self.indent_level -= 1;
        }
        try self.emitIndent();
        _ = try builder.line("}");
    }
}

/// Generate the condition for a pattern match
fn genPatternCondition(self: *NativeCodegen, pattern: ast.Node.MatchPattern, subject: []const u8) CodegenError!void {
    var builder = CodeBuilder.init(self);

    switch (pattern) {
        .wildcard => {
            // Always matches
            _ = try builder.write("true");
        },
        .capture => {
            // Variable capture - always matches
            _ = try builder.write("true");
        },
        .literal => |lit| {
            // Compare subject to literal
            _ = try builder.write(subject);
            _ = try builder.write(" == ");
            try self.genExpr(lit.*);
        },
        .sequence => |patterns| {
            // Check length and each element
            _ = try builder.write(subject);
            _ = try builder.write(".len == ");
            try self.emitFmt("{d}", .{patterns.len});
            for (patterns, 0..) |p, i| {
                _ = try builder.write(" and ");
                var idx_buf: [32]u8 = undefined;
                const idx_str = std.fmt.bufPrint(&idx_buf, "{s}[{d}]", .{ subject, i }) catch "?";
                try genPatternCondition(self, p, idx_str);
            }
        },
        .mapping => |entries| {
            // Check each key exists and value matches
            if (entries.len == 0) {
                _ = try builder.write("true");
            } else {
                for (entries, 0..) |entry, i| {
                    if (i > 0) _ = try builder.write(" and ");
                    // Check key exists
                    _ = try builder.write(subject);
                    _ = try builder.write(".contains(");
                    try self.genExpr(entry.key.*);
                    _ = try builder.write(")");
                    // Check value pattern (unless it's a capture/wildcard which always matches)
                    switch (entry.pattern) {
                        .wildcard, .capture => {}, // Always match, no condition needed
                        .literal => |lit| {
                            // For literal patterns, compare value directly
                            _ = try builder.write(" and ");
                            _ = try builder.write(subject);
                            _ = try builder.write(".get(");
                            try self.genExpr(entry.key.*);
                            _ = try builder.write(") == ");
                            try self.genExpr(lit.*);
                        },
                        else => {
                            // Other patterns need recursive checking with value accessor
                            // For now, just check that key exists (partial match)
                            // Full recursive value pattern matching requires buffer allocation
                        },
                    }
                }
            }
        },
        .class_pattern => |cp| {
            // Check if subject is instance of class
            _ = try builder.write("@TypeOf(");
            _ = try builder.write(subject);
            _ = try builder.write(") == ");
            _ = try builder.write(cp.cls);
            // Check positional patterns (match against __match_args__ order)
            for (cp.positional, 0..) |pos_pattern, i| {
                switch (pos_pattern) {
                    .wildcard, .capture => {}, // Always match
                    .literal => |lit| {
                        _ = try builder.write(" and ");
                        _ = try builder.write(subject);
                        try self.emitFmt(".@\"{d}\" == ", .{i});
                        try self.genExpr(lit.*);
                    },
                    else => {},
                }
            }
            // Check keyword patterns (match named attributes)
            for (cp.keyword) |kw| {
                switch (kw.pattern) {
                    .wildcard, .capture => {}, // Always match
                    .literal => |lit| {
                        _ = try builder.write(" and ");
                        _ = try builder.write(subject);
                        _ = try builder.write(".");
                        _ = try builder.write(kw.name);
                        _ = try builder.write(" == ");
                        try self.genExpr(lit.*);
                    },
                    else => {},
                }
            }
        },
        .or_pattern => |patterns| {
            _ = try builder.write("(");
            for (patterns, 0..) |p, i| {
                if (i > 0) _ = try builder.write(" or ");
                try genPatternCondition(self, p, subject);
            }
            _ = try builder.write(")");
        },
        .as_pattern => |ap| {
            // Match inner pattern
            try genPatternCondition(self, ap.pattern.*, subject);
        },
        .value => |node| {
            // Value pattern: compare subject against the dotted expression
            _ = try builder.write(subject);
            _ = try builder.write(" == ");
            try self.genExpr(node.*);
        },
    }
}

/// Generate variable bindings for captures in a pattern
fn genPatternBindings(self: *NativeCodegen, pattern: ast.Node.MatchPattern, subject: []const u8) CodegenError!void {
    var builder = CodeBuilder.init(self);

    switch (pattern) {
        .capture => |name| {
            // Bind variable to subject
            try self.emitIndent();
            _ = try builder.write("const ");
            _ = try builder.write(name);
            _ = try builder.write(" = ");
            _ = try builder.write(subject);
            _ = try builder.line(";");
        },
        .sequence => |patterns| {
            // Bind each element
            for (patterns, 0..) |p, i| {
                var idx_buf: [64]u8 = undefined;
                const idx_str = std.fmt.bufPrint(&idx_buf, "{s}[{d}]", .{ subject, i }) catch continue;
                try genPatternBindings(self, p, idx_str);
            }
        },
        .as_pattern => |ap| {
            // Bind the name and recurse
            try self.emitIndent();
            _ = try builder.write("const ");
            _ = try builder.write(ap.name);
            _ = try builder.write(" = ");
            _ = try builder.write(subject);
            _ = try builder.line(";");
            try genPatternBindings(self, ap.pattern.*, subject);
        },
        else => {},
    }
}
