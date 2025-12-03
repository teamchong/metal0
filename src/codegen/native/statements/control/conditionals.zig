/// Conditional statement code generation (if, pass, break, continue)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const CodeBuilder = @import("../../code_builder.zig").CodeBuilder;

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

                    // Get the Zig type string
                    var type_buf = std.ArrayList(u8){};
                    defer type_buf.deinit(self.allocator);
                    value_type.toZigType(self.allocator, &type_buf) catch {
                        try type_buf.writer(self.allocator).writeAll("i64");
                    };

                    try self.emitIndent();
                    try self.emit("var ");
                    try self.emit(var_name);
                    try self.emit(": ");
                    try self.emit(type_buf.items);
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

        // Collect variables from all branches
        try collectAssignedVars(self, if_stmt.body, &assigned_vars);
        try collectAssignedVars(self, if_stmt.else_body, &assigned_vars);

        // Emit declarations for variables that will be assigned in branches
        for (assigned_vars.items) |v| {
            // Skip if already hoisted at function level
            if (self.hoisted_vars.contains(v.name)) continue;

            // Skip module-level functions - they're already declared as functions
            // Python allows `genslices = rslices` to reassign function names,
            // but in Zig the function is already defined so we skip hoisting
            if (self.module_level_funcs.contains(v.name)) continue;

            const var_type = self.type_inferrer.inferExpr(v.node) catch .unknown;

            // Skip hoisting if type refers to a class defined inside the block
            if (var_type == .class_instance) {
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
            try self.emit(v.name);
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
    const cond_tag = @as(std.meta.Tag(@TypeOf(cond_type)), cond_type);
    if (is_feature_macros_subscript) {
        // FeatureMacros subscript returns comptime bool - use directly
        try self.genExpr(if_stmt.condition.*);
    } else if (cond_type == .unknown) {
        // Unknown type (PyObject) - use runtime truthiness check
        _ = try builder.write("runtime.pyTruthy(");
        try self.genExpr(if_stmt.condition.*);
        _ = try builder.write(")");
    } else if (cond_type == .optional) {
        // Optional type - check for non-null
        try self.genExpr(if_stmt.condition.*);
        _ = try builder.write(" != null");
    } else if (cond_type == .bool) {
        // Boolean - use directly
        try self.genExpr(if_stmt.condition.*);
    } else if (cond_tag == .class_instance) {
        // Class instance - use runtime.toBool for duck typing (__bool__ support)
        _ = try builder.write("runtime.toBool(");
        try self.genExpr(if_stmt.condition.*);
        _ = try builder.write(")");
    } else {
        // Other types (int, float, string, etc.) - use runtime.toBool
        // This handles Python truthiness semantics (0 is false, "" is false, etc.)
        _ = try builder.write("runtime.toBool(");
        try self.genExpr(if_stmt.condition.*);
        _ = try builder.write(")");
    }
    _ = try builder.write(")");
    _ = try builder.beginBlock();

    for (if_stmt.body) |stmt| {
        try self.generateStmt(stmt);
    }

    if (if_stmt.else_body.len > 0) {
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
    } else {
        _ = try builder.endBlock();
    }
}

/// Generate pass statement (no-op)
pub fn genPass(self: *NativeCodegen) CodegenError!void {
    var builder = CodeBuilder.init(self);
    _ = try builder.line("// pass");
}

/// Generate break statement
pub fn genBreak(self: *NativeCodegen) CodegenError!void {
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
            for (entries, 0..) |entry, i| {
                if (i > 0) _ = try builder.write(" and ");
                _ = try builder.write(subject);
                _ = try builder.write(".contains(");
                try self.genExpr(entry.key.*);
                _ = try builder.write(")");
                // TODO: Also check value pattern
            }
            if (entries.len == 0) {
                _ = try builder.write("true");
            }
        },
        .class_pattern => |cp| {
            // Check if subject is instance of class
            _ = try builder.write("@TypeOf(");
            _ = try builder.write(subject);
            _ = try builder.write(") == ");
            _ = try builder.write(cp.cls);
            // TODO: Check positional and keyword patterns
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
