/// Nested function (closure) code generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const body = @import("generators/body.zig");
const zig_keywords = @import("zig_keywords");
const hashmap_helper = @import("hashmap_helper");

/// Find variables captured from outer scope by nested function
fn findCapturedVars(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
) CodegenError![][]const u8 {
    var captured = std.ArrayList([]const u8){};

    // Collect all variables referenced in function body
    var referenced = std.ArrayList([]const u8){};
    defer referenced.deinit(self.allocator);

    try collectReferencedVars(self, func.body, &referenced);

    // Check which referenced vars are in outer scope (not params or local)
    for (referenced.items) |var_name| {
        // Skip if it's a function parameter
        var is_param = false;
        for (func.args) |arg| {
            if (std.mem.eql(u8, arg.name, var_name)) {
                is_param = true;
                break;
            }
        }
        if (is_param) continue;

        // Check if variable is in outer scope
        if (self.symbol_table.lookup(var_name) != null) {
            // Add to captured list (avoid duplicates)
            var already_captured = false;
            for (captured.items) |captured_var| {
                if (std.mem.eql(u8, captured_var, var_name)) {
                    already_captured = true;
                    break;
                }
            }
            if (!already_captured) {
                try captured.append(self.allocator, var_name);
            }
        }
    }

    return captured.toOwnedSlice(self.allocator);
}

/// Collect all variable names referenced in statements
fn collectReferencedVars(
    self: *NativeCodegen,
    stmts: []ast.Node,
    referenced: *std.ArrayList([]const u8),
) CodegenError!void {
    for (stmts) |stmt| {
        try collectReferencedVarsInNode(self, stmt, referenced);
    }
}

/// Check if a parameter name is used in a list of statements
fn isParamUsedInStmts(param_name: []const u8, stmts: []ast.Node) bool {
    for (stmts) |stmt| {
        if (isParamUsedInNode(param_name, stmt)) return true;
    }
    return false;
}

/// Check if any of the captured variables are actually used in the function body
fn areCapturedVarsUsed(captured_vars: [][]const u8, stmts: []ast.Node) bool {
    for (captured_vars) |var_name| {
        if (isParamUsedInStmts(var_name, stmts)) return true;
    }
    return false;
}

/// Check if a function is recursive (calls itself by name)
fn isRecursiveFunction(func_name: []const u8, stmts: []ast.Node) bool {
    for (stmts) |stmt| {
        if (isRecursiveCall(func_name, stmt)) return true;
    }
    return false;
}

/// Check if a node contains a recursive call to func_name
fn isRecursiveCall(func_name: []const u8, node: ast.Node) bool {
    return switch (node) {
        .call => |c| blk: {
            // Check if the function being called is the recursive function
            if (c.func.* == .name and std.mem.eql(u8, c.func.name.id, func_name)) {
                break :blk true;
            }
            // Also check arguments for nested recursive calls
            for (c.args) |arg| {
                if (isRecursiveCall(func_name, arg)) break :blk true;
            }
            break :blk false;
        },
        .if_stmt => |i| blk: {
            for (i.body) |s| {
                if (isRecursiveCall(func_name, s)) break :blk true;
            }
            for (i.else_body) |s| {
                if (isRecursiveCall(func_name, s)) break :blk true;
            }
            break :blk false;
        },
        .for_stmt => |f| blk: {
            for (f.body) |s| {
                if (isRecursiveCall(func_name, s)) break :blk true;
            }
            break :blk false;
        },
        .while_stmt => |w| blk: {
            for (w.body) |s| {
                if (isRecursiveCall(func_name, s)) break :blk true;
            }
            break :blk false;
        },
        .expr_stmt => |e| isRecursiveCall(func_name, e.value.*),
        .return_stmt => |r| if (r.value) |v| isRecursiveCall(func_name, v.*) else false,
        .assign => |a| isRecursiveCall(func_name, a.value.*),
        .binop => |b| isRecursiveCall(func_name, b.left.*) or isRecursiveCall(func_name, b.right.*),
        .unaryop => |u| isRecursiveCall(func_name, u.operand.*),
        .if_expr => |ie| isRecursiveCall(func_name, ie.condition.*) or
            isRecursiveCall(func_name, ie.body.*) or
            isRecursiveCall(func_name, ie.orelse_value.*),
        .list => |l| blk: {
            for (l.elts) |elt| {
                if (isRecursiveCall(func_name, elt)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

/// Check if a parameter name is used in a single node
fn isParamUsedInNode(param_name: []const u8, node: ast.Node) bool {
    return switch (node) {
        .name => |n| std.mem.eql(u8, n.id, param_name),
        .binop => |b| isParamUsedInNode(param_name, b.left.*) or isParamUsedInNode(param_name, b.right.*),
        .unaryop => |u| isParamUsedInNode(param_name, u.operand.*),
        .call => |c| blk: {
            if (isParamUsedInNode(param_name, c.func.*)) break :blk true;
            for (c.args) |arg| {
                if (isParamUsedInNode(param_name, arg)) break :blk true;
            }
            for (c.keyword_args) |kw| {
                if (isParamUsedInNode(param_name, kw.value)) break :blk true;
            }
            break :blk false;
        },
        .return_stmt => |ret| if (ret.value) |val| isParamUsedInNode(param_name, val.*) else false,
        .assign => |assign| isParamUsedInNode(param_name, assign.value.*),
        .compare => |cmp| blk: {
            if (isParamUsedInNode(param_name, cmp.left.*)) break :blk true;
            for (cmp.comparators) |comp| {
                if (isParamUsedInNode(param_name, comp)) break :blk true;
            }
            break :blk false;
        },
        .subscript => |sub| isParamUsedInNode(param_name, sub.value.*) or
            (if (sub.slice == .index) isParamUsedInNode(param_name, sub.slice.index.*) else false),
        .attribute => |attr| isParamUsedInNode(param_name, attr.value.*),
        .if_stmt => |i| blk: {
            if (isParamUsedInNode(param_name, i.condition.*)) break :blk true;
            if (isParamUsedInStmts(param_name, i.body)) break :blk true;
            if (isParamUsedInStmts(param_name, i.else_body)) break :blk true;
            break :blk false;
        },
        .if_expr => |ie| isParamUsedInNode(param_name, ie.condition.*) or
            isParamUsedInNode(param_name, ie.body.*) or
            isParamUsedInNode(param_name, ie.orelse_value.*),
        .list => |l| blk: {
            for (l.elts) |elt| {
                if (isParamUsedInNode(param_name, elt)) break :blk true;
            }
            break :blk false;
        },
        .tuple => |t| blk: {
            for (t.elts) |elt| {
                if (isParamUsedInNode(param_name, elt)) break :blk true;
            }
            break :blk false;
        },
        .dict => |d| blk: {
            for (d.keys) |key| {
                if (isParamUsedInNode(param_name, key)) break :blk true;
            }
            for (d.values) |val| {
                if (isParamUsedInNode(param_name, val)) break :blk true;
            }
            break :blk false;
        },
        .for_stmt => |f| blk: {
            if (isParamUsedInNode(param_name, f.iter.*)) break :blk true;
            if (isParamUsedInStmts(param_name, f.body)) break :blk true;
            if (f.orelse_body) |ob| {
                if (isParamUsedInStmts(param_name, ob)) break :blk true;
            }
            break :blk false;
        },
        .while_stmt => |w| blk: {
            if (isParamUsedInNode(param_name, w.condition.*)) break :blk true;
            if (isParamUsedInStmts(param_name, w.body)) break :blk true;
            break :blk false;
        },
        .expr_stmt => |e| isParamUsedInNode(param_name, e.value.*),
        .boolop => |bo| blk: {
            for (bo.values) |v| {
                if (isParamUsedInNode(param_name, v)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

/// Collect variable names from a single node
fn collectReferencedVarsInNode(
    self: *NativeCodegen,
    node: ast.Node,
    referenced: *std.ArrayList([]const u8),
) CodegenError!void {
    switch (node) {
        .name => |n| {
            try referenced.append(self.allocator, n.id);
        },
        .binop => |b| {
            try collectReferencedVarsInNode(self, b.left.*, referenced);
            try collectReferencedVarsInNode(self, b.right.*, referenced);
        },
        .call => |c| {
            try collectReferencedVarsInNode(self, c.func.*, referenced);
            for (c.args) |arg| {
                try collectReferencedVarsInNode(self, arg, referenced);
            }
        },
        .return_stmt => |ret| {
            if (ret.value) |val| {
                try collectReferencedVarsInNode(self, val.*, referenced);
            }
        },
        .assign => |assign| {
            try collectReferencedVarsInNode(self, assign.value.*, referenced);
        },
        .compare => |cmp| {
            try collectReferencedVarsInNode(self, cmp.left.*, referenced);
            for (cmp.comparators) |comp| {
                try collectReferencedVarsInNode(self, comp, referenced);
            }
        },
        else => {},
    }
}

/// Generate a recursive closure using Y-combinator style pattern
/// For recursive closures, we use a struct with a function that receives itself via @This()
fn genRecursiveClosure(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    captured_vars: [][]const u8,
) CodegenError!void {
    const saved_counter = self.lambda_counter;
    self.lambda_counter += 1;

    // For recursive closures, we generate:
    // const inner = struct {
    //     var limit: i64 = undefined;  // captures as static vars
    //     var seen: ... = undefined;
    //     pub fn call(w: i64) void {
    //         // body can reference limit, seen, and call itself via call(...)
    //     }
    // };
    // inner.limit = limit;  // initialize captures
    // inner.seen = seen;
    // inner.call(w);  // initial call

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{func.name});
    self.indent();

    // Static capture variables (prefixed with __c_ to avoid shadowing)
    for (captured_vars) |var_name| {
        try self.emitIndent();
        // Use @TypeOf to get the correct type from the outer variable
        const outer_var_name = blk: {
            if (self.var_renames.get(var_name)) |renamed| {
                break :blk renamed;
            }
            break :blk var_name;
        };
        try self.output.writer(self.allocator).print("var __c_{s}: @TypeOf({s}) = undefined;\n", .{ var_name, outer_var_name });
    }

    // The recursive function
    // Use anytype for parameters to accept any type (int, bool, etc.)
    try self.emitIndent();
    try self.emit("pub fn call(");
    for (func.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        const is_used = isParamUsedInStmts(arg.name, func.body);
        if (is_used) {
            try self.output.writer(self.allocator).print("__p_{s}_{d}: anytype", .{ arg.name, saved_counter });
        } else {
            try self.emit("_: anytype");
        }
    }
    try self.emit(") void {\n");
    self.indent();

    // Generate body
    try self.pushScope();

    // Save and restore func_local_uses
    const saved_func_local_uses = self.func_local_uses;
    self.func_local_uses = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.func_local_uses.deinit();
        self.func_local_uses = saved_func_local_uses;
    }
    try collectUsedNames(func.body, &self.func_local_uses);

    // Save outer scope renames for captured variables (to restore later)
    var saved_outer_renames = std.ArrayList(?[]const u8){};
    defer saved_outer_renames.deinit(self.allocator);

    for (captured_vars) |var_name| {
        try saved_outer_renames.append(self.allocator, self.var_renames.get(var_name));
    }

    // Capture variable renames (use __c_ prefix to reference struct fields)
    var capture_renames = std.ArrayList([]const u8){};
    defer capture_renames.deinit(self.allocator);

    for (captured_vars) |var_name| {
        const rename = try std.fmt.allocPrint(self.allocator, "__c_{s}", .{var_name});
        try capture_renames.append(self.allocator, rename);
        try self.var_renames.put(var_name, rename);
    }

    // Save outer scope param renames (to restore later)
    var saved_param_renames = std.ArrayList(?[]const u8){};
    defer saved_param_renames.deinit(self.allocator);

    for (func.args) |arg| {
        try saved_param_renames.append(self.allocator, self.var_renames.get(arg.name));
    }

    // Param renames
    var param_renames = std.ArrayList([]const u8){};
    defer param_renames.deinit(self.allocator);

    for (func.args) |arg| {
        try self.declareVar(arg.name);
        const is_used = isParamUsedInStmts(arg.name, func.body);
        if (is_used) {
            const rename = try std.fmt.allocPrint(self.allocator, "__p_{s}_{d}", .{ arg.name, saved_counter });
            try param_renames.append(self.allocator, rename);
            try self.var_renames.put(arg.name, rename);
        }
    }

    // Rename the function name itself to just 'call' for recursive calls
    try self.var_renames.put(func.name, "call");

    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Clean up renames
    _ = self.var_renames.swapRemove(func.name);

    for (func.args, 0..) |arg, i| {
        // Restore outer scope param rename if there was one
        if (saved_param_renames.items[i]) |outer_rename| {
            try self.var_renames.put(arg.name, outer_rename);
        } else {
            _ = self.var_renames.swapRemove(arg.name);
        }
        if (i < param_renames.items.len) {
            self.allocator.free(param_renames.items[i]);
        }
    }

    for (captured_vars, 0..) |var_name, i| {
        // Restore outer scope rename if there was one
        if (saved_outer_renames.items[i]) |outer_rename| {
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

    // Initialize the capture variables (use __c_ prefix)
    // Now var_renames has been restored so outer scope renames work
    for (captured_vars) |var_name| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("{s}.__c_{s} = ", .{ func.name, var_name });
        if (self.var_renames.get(var_name)) |renamed| {
            try self.emit(renamed);
        } else {
            try self.emit(var_name);
        }
        try self.emit(";\n");
    }

    // Mark inner as a closure for .call() syntax
    const inner_name_copy = try self.allocator.dupe(u8, func.name);
    try self.closure_vars.put(inner_name_copy, {});
}

/// Generate nested function with closure support (immediate call only)
pub fn genNestedFunctionDef(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
) CodegenError!void {
    // Use captured variables from AST (pre-computed by closure analyzer)
    const captured_vars = func.captured_vars;

    // Check if this is a recursive function
    const is_recursive = isRecursiveFunction(func.name, func.body);

    if (captured_vars.len == 0) {
        // No captures - use ZeroClosure comptime pattern
        try self.emitIndent();
        try genZeroCaptureClosure(self, func);
        return;
    }

    if (is_recursive) {
        // Recursive closures need special handling - generate as a regular function
        // with captures passed as parameters, avoiding the closure struct pattern
        try genRecursiveClosure(self, func, captured_vars);
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
        try self.output.writer(self.allocator).print(" {s}: i64", .{var_name});
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
    const captures_used = areCapturedVarsUsed(captured_vars, func.body);

    try self.emitIndent();
    if (captures_used) {
        try self.output.writer(self.allocator).print("fn {s}({s}: {s}", .{ impl_fn_name, capture_param_name, capture_type_name });
    } else {
        // Captures not used, use _ to avoid unused parameter error
        try self.output.writer(self.allocator).print("fn {s}(_: {s}", .{ impl_fn_name, capture_type_name });
    }

    // Generate renamed parameters to avoid shadowing outer scope
    // Build a mapping from original param names to renamed versions
    var param_renames = std.StringHashMap([]const u8).init(self.allocator);
    defer param_renames.deinit();

    for (func.args) |arg| {
        // Check if param is used in body - if not, use _ to discard (Zig 0.15 requirement)
        const is_used = isParamUsedInStmts(arg.name, func.body);
        if (is_used) {
            // Create a unique parameter name to avoid shadowing: __p_name_counter
            const unique_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__p_{s}_{d}",
                .{ arg.name, saved_counter },
            );
            try param_renames.put(arg.name, unique_param_name);
            try self.output.writer(self.allocator).print(", {s}: i64", .{unique_param_name});
        } else {
            try self.output.writer(self.allocator).print(", _: i64", .{});
        }
    }
    try self.emit(") i64 {\n");

    // Generate body with captured vars renamed to capture_param.varname
    self.indent();
    try self.pushScope();

    // Save and populate func_local_uses for this nested function
    // This prevents incorrect "unused variable" detection for local vars
    const saved_func_local_uses = self.func_local_uses;
    self.func_local_uses = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.func_local_uses.deinit();
        self.func_local_uses = saved_func_local_uses;
    }

    // Populate func_local_uses with variables used in this function body
    try collectUsedNames(func.body, &self.func_local_uses);

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

    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Remove param renames after body generation
    for (func.args) |arg| {
        _ = self.var_renames.swapRemove(arg.name);
    }

    // Remove capture renames and free memory
    for (captured_vars, 0..) |var_name, i| {
        _ = self.var_renames.swapRemove(var_name);
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
    // Use unique variable name to avoid shadowing nested functions - use saved_counter
    const closure_var_name = try std.fmt.allocPrint(
        self.allocator,
        "__closure_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(closure_var_name);

    try self.emitIndent();
    if (func.args.len == 0) {
        // No arguments - use Closure0
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
        // Fallback to single arg tuple
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

    // Return type and function - use saved_counter for consistency
    const impl_fn_ref = try std.fmt.allocPrint(
        self.allocator,
        "call_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(impl_fn_ref);

    try self.output.writer(self.allocator).print(
        "i64, {s}.{s}){{ .captures = .{{",
        .{ closure_impl_name, impl_fn_ref },
    );

    // Initialize captures - use renamed variable names if applicable
    for (captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        // Check if this var was renamed (e.g., function parameter renamed to avoid shadowing)
        const actual_name = self.var_renames.get(var_name) orelse var_name;
        try self.output.writer(self.allocator).print(" .{s} = {s}", .{ var_name, actual_name });
    }
    try self.emit(" } };\n");

    // Create alias with original function name - use saved_counter
    const closure_alias_name = try std.fmt.allocPrint(
        self.allocator,
        "__closure_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(closure_alias_name);

    try self.emitIndent();
    try self.emit("const ");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), func.name);
    try self.output.writer(self.allocator).print(" = {s};\n", .{closure_alias_name});

    // Mark this variable as a closure so calls use .call() syntax
    const func_name_copy = try self.allocator.dupe(u8, func.name);
    try self.closure_vars.put(func_name_copy, {});
}

/// Generate nested function with outer capture context awareness
/// This handles the case where a closure is defined inside another closure
fn genNestedFunctionWithOuterCapture(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    outer_captured_vars: [][]const u8,
    outer_capture_param: []const u8,
) CodegenError!void {
    // Use captured variables from AST (pre-computed by closure analyzer)
    const captured_vars = func.captured_vars;

    if (captured_vars.len == 0) {
        // No captures - use ZeroClosure comptime pattern
        try self.emitIndent();
        try genZeroCaptureClosure(self, func);
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
        try self.output.writer(self.allocator).print(" {s}: i64", .{var_name});
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
    const captures_used = areCapturedVarsUsed(captured_vars, func.body);

    try self.emitIndent();
    if (captures_used) {
        try self.output.writer(self.allocator).print("fn {s}({s}: {s}", .{ impl_fn_name, capture_param_name, capture_type_name });
    } else {
        // Captures not used, use _ to avoid unused parameter error
        try self.output.writer(self.allocator).print("fn {s}(_: {s}", .{ impl_fn_name, capture_type_name });
    }

    // Generate renamed parameters to avoid shadowing outer scope (duplicate of above section)
    var param_renames2 = std.StringHashMap([]const u8).init(self.allocator);
    defer param_renames2.deinit();

    for (func.args) |arg| {
        // Check if param is used in body - if not, use _ to discard (Zig 0.15 requirement)
        const is_used = isParamUsedInStmts(arg.name, func.body);
        if (is_used) {
            // Create a unique parameter name to avoid shadowing: __p_name_counter
            const unique_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__p_{s}_{d}",
                .{ arg.name, saved_counter },
            );
            try param_renames2.put(arg.name, unique_param_name);
            try self.output.writer(self.allocator).print(", {s}: i64", .{unique_param_name});
        } else {
            try self.output.writer(self.allocator).print(", _: i64", .{});
        }
    }
    try self.emit(") i64 {\n");

    // Generate body with captured vars renamed to capture_param.varname
    self.indent();
    try self.pushScope();

    // Save and populate func_local_uses for this nested function
    const saved_func_local_uses2 = self.func_local_uses;
    self.func_local_uses = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.func_local_uses.deinit();
        self.func_local_uses = saved_func_local_uses2;
    }

    // Populate func_local_uses with variables used in this function body
    try collectUsedNames(func.body, &self.func_local_uses);

    // Add captured variable renames so they get prefixed with capture struct access
    var capture_renames2 = std.ArrayList([]const u8){};
    defer capture_renames2.deinit(self.allocator);

    for (captured_vars) |var_name| {
        const rename = try std.fmt.allocPrint(
            self.allocator,
            "{s}.{s}",
            .{ capture_param_name, var_name },
        );
        try capture_renames2.append(self.allocator, rename);
        try self.var_renames.put(var_name, rename);
    }

    for (func.args) |arg| {
        try self.declareVar(arg.name);
        // Add rename mapping for parameter access in body
        if (param_renames2.get(arg.name)) |renamed| {
            try self.var_renames.put(arg.name, renamed);
        }
    }

    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Remove param renames after body generation
    for (func.args) |arg| {
        _ = self.var_renames.swapRemove(arg.name);
    }

    // Remove capture renames and free memory
    for (captured_vars, 0..) |var_name, i| {
        _ = self.var_renames.swapRemove(var_name);
        self.allocator.free(capture_renames2.items[i]);
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
        "i64, {s}.{s}){{ .captures = .{{",
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
    const closure_alias_name = try std.fmt.allocPrint(
        self.allocator,
        "__closure_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(closure_alias_name);

    try self.emitIndent();
    try self.emit("const ");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), func.name);
    try self.output.writer(self.allocator).print(" = {s};\n", .{closure_alias_name});

    // Mark this variable as a closure so calls use .call() syntax
    const func_name_copy = try self.allocator.dupe(u8, func.name);
    try self.closure_vars.put(func_name_copy, {});
}

/// Generate zero-capture closure using comptime ZeroClosure
fn genZeroCaptureClosure(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
) CodegenError!void {
    // Save counter for unique naming
    const saved_counter = self.lambda_counter;

    // Generate the inner function
    const impl_name = try std.fmt.allocPrint(
        self.allocator,
        "__ZeroImpl_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(impl_name);

    // Use unique function name inside the struct to avoid shadowing
    const inner_fn_name = try std.fmt.allocPrint(
        self.allocator,
        "__fn_{s}_{d}",
        .{ func.name, saved_counter },
    );
    defer self.allocator.free(inner_fn_name);
    self.lambda_counter += 1;

    // Build param name mappings for unique names to avoid shadowing outer scope
    var param_renames = std.StringHashMap([]const u8).init(self.allocator);
    defer param_renames.deinit();

    try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{impl_name});
    self.indent();

    try self.emitIndent();
    try self.output.writer(self.allocator).print("fn {s}(", .{inner_fn_name});
    for (func.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        // Check if param is used in body - if not, use _ to discard (Zig 0.15 requirement)
        const is_used = isParamUsedInStmts(arg.name, func.body);
        if (is_used) {
            // Create unique param name to avoid shadowing outer scope
            const unique_param_name = try std.fmt.allocPrint(
                self.allocator,
                "__p_{s}_{d}",
                .{ arg.name, saved_counter },
            );
            try param_renames.put(arg.name, unique_param_name);
            try self.output.writer(self.allocator).print("{s}: i64", .{unique_param_name});
        } else {
            try self.output.writer(self.allocator).print("_: i64", .{});
        }
    }
    try self.emit(") i64 {\n");

    self.indent();
    try self.pushScope();

    // Save and populate func_local_uses for this nested function
    const saved_func_local_uses3 = self.func_local_uses;
    self.func_local_uses = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.func_local_uses.deinit();
        self.func_local_uses = saved_func_local_uses3;
    }

    // Populate func_local_uses with variables used in this function body
    try collectUsedNames(func.body, &self.func_local_uses);

    for (func.args) |arg| {
        try self.declareVar(arg.name);
        // Add rename mapping for parameter access in body
        if (param_renames.get(arg.name)) |renamed| {
            try self.var_renames.put(arg.name, renamed);
        }
    }

    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Remove param renames after body generation
    for (func.args) |arg| {
        _ = self.var_renames.swapRemove(arg.name);
    }

    // Free renamed param names
    var rename_iter = param_renames.valueIterator();
    while (rename_iter.next()) |renamed| {
        self.allocator.free(renamed.*);
    }

    self.popScope();
    self.dedent();

    try self.emitIndent();
    try self.emit("}\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // Use ZeroClosure for single arg, or struct wrapper for multiple
    // Use the original function name so that references resolve correctly
    try self.emitIndent();
    try self.emit("const ");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), func.name);
    if (func.args.len == 1) {
        try self.output.writer(self.allocator).print(" = runtime.ZeroClosure(i64, i64, {s}.{s}){{}};\n", .{ impl_name, inner_fn_name });
    } else {
        // Multiple args - create wrapper struct with unique parameter names
        // Use a different counter for wrapper params (saved_counter is already used above)
        const wrapper_counter = self.lambda_counter;
        self.lambda_counter += 1;

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
                "__p_{s}_{d}",
                .{ arg.name, wrapper_counter },
            );
            try param_names.append(self.allocator, unique_name);
        }

        try self.emit(" = struct {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("pub fn call(_: @This()");
        for (param_names.items) |unique_name| {
            try self.output.writer(self.allocator).print(", {s}: i64", .{unique_name});
        }
        try self.output.writer(self.allocator).print(") i64 {{\n", .{});
        self.indent();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("return {s}.{s}(", .{ impl_name, inner_fn_name });
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

    // Mark as closure so calls use .call() syntax
    const func_name_copy = try self.allocator.dupe(u8, func.name);
    try self.closure_vars.put(func_name_copy, {});
}

/// Generate statement with captured variable references prefixed with capture param name
fn genStmtWithCaptureStruct(
    self: *NativeCodegen,
    stmt: ast.Node,
    captured_vars: [][]const u8,
    capture_param_name: []const u8,
) CodegenError!void {
    switch (stmt) {
        .return_stmt => |ret| {
            try self.emitIndent();
            try self.emit("return ");
            if (ret.value) |val| {
                try genExprWithCaptureStruct(self, val.*, captured_vars, capture_param_name);
            }
            try self.emit(";\n");
        },
        .function_def => |func| {
            // Handle nested function definition within a closure
            // We need to generate this with awareness of the outer capture context
            try genNestedFunctionWithOuterCapture(self, func, captured_vars, capture_param_name);
        },
        .assign => |assign| {
            // For simple name target (single target), emit the name with const
            if (assign.targets.len == 1 and assign.targets[0] == .name) {
                const var_name = assign.targets[0].name.id;
                const is_already_declared = self.isDeclared(var_name);
                try self.emitIndent();
                if (is_already_declared) {
                    // Variable already exists (e.g., function parameter being reassigned)
                    // Just emit assignment without declaration
                    try self.emit(var_name);
                } else {
                    try self.emit("const ");
                    try self.emit(var_name);
                }
                try self.emit(" = ");
                try genExprWithCaptureStruct(self, assign.value.*, captured_vars, capture_param_name);
                try self.emit(";\n");
            } else if (assign.targets.len == 1 and (assign.targets[0] == .tuple or assign.targets[0] == .list)) {
                // Tuple/list unpacking - use regular assignment generation
                try self.generateStmt(stmt);
            } else {
                // Multiple targets or other patterns - fallback to regular generation
                try self.generateStmt(stmt);
            }
        },
        else => {
            // For other statements, use regular generation
            try self.generateStmt(stmt);
        },
    }
}

/// Generate expression with captured variable references prefixed with capture param name
fn genExprWithCaptureStruct(
    self: *NativeCodegen,
    node: ast.Node,
    captured_vars: [][]const u8,
    capture_param_name: []const u8,
) CodegenError!void {
    switch (node) {
        .name => |n| {
            // Check if this variable is captured
            for (captured_vars) |captured| {
                if (std.mem.eql(u8, n.id, captured)) {
                    try self.emit(capture_param_name);
                    try self.emit(".");
                    try self.emit(n.id);
                    return;
                }
            }
            try self.emit(n.id);
        },
        .binop => |b| {
            try self.emit("(");
            try genExprWithCaptureStruct(self, b.left.*, captured_vars, capture_param_name);

            const op_str = switch (b.op) {
                .Add => " + ",
                .Sub => " - ",
                .Mult => " * ",
                .MatMul => " @ ", // Matrix multiplication - handled by numpy at runtime
                .Div => " / ",
                .FloorDiv => " / ",
                .Mod => " % ",
                .Pow => " ** ",
                .BitAnd => " & ",
                .BitOr => " | ",
                .BitXor => " ^ ",
                .LShift => " << ",
                .RShift => " >> ",
            };
            try self.emit(op_str);

            try genExprWithCaptureStruct(self, b.right.*, captured_vars, capture_param_name);
            try self.emit(")");
        },
        .constant => |c| {
            const expressions = @import("../../expressions.zig");
            try expressions.genConstant(self, c);
        },
        .call => |c| {
            // Check if calling a closure variable - need to use .call() syntax
            const is_closure_call = if (c.func.* == .name) blk: {
                const func_name = c.func.name.id;
                break :blk self.closure_vars.contains(func_name);
            } else false;

            if (is_closure_call) {
                try genExprWithCaptureStruct(self, c.func.*, captured_vars, capture_param_name);
                try self.emit(".call(");
            } else {
                try genExprWithCaptureStruct(self, c.func.*, captured_vars, capture_param_name);
                try self.emit("(");
            }
            for (c.args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try genExprWithCaptureStruct(self, arg, captured_vars, capture_param_name);
            }
            try self.emit(")");
        },
        .attribute => |attr| {
            // Handle attribute access like self.foo, rewriting captured var prefix
            try genExprWithCaptureStruct(self, attr.value.*, captured_vars, capture_param_name);
            try self.emit(".");
            try self.emit(attr.attr);
        },
        .subscript => |sub| {
            // Handle subscript like foo[bar], rewriting captured vars in both parts
            try genExprWithCaptureStruct(self, sub.value.*, captured_vars, capture_param_name);
            try self.emit("[");
            switch (sub.slice) {
                .index => |idx| try genExprWithCaptureStruct(self, idx.*, captured_vars, capture_param_name),
                else => {
                    // For slice expressions, fall back to regular generation
                    const expressions = @import("../../expressions.zig");
                    try expressions.genExpr(self, node);
                    return;
                },
            }
            try self.emit("]");
        },
        else => {
            const expressions = @import("../../expressions.zig");
            try expressions.genExpr(self, node);
        },
    }
}

/// Collect all variable names used in statements (for func_local_uses tracking)
fn collectUsedNames(stmts: []ast.Node, uses: *hashmap_helper.StringHashMap(void)) error{OutOfMemory}!void {
    for (stmts) |stmt| {
        try collectUsedNamesFromNode(stmt, uses);
    }
}

fn collectUsedNamesFromNode(node: ast.Node, uses: *hashmap_helper.StringHashMap(void)) error{OutOfMemory}!void {
    switch (node) {
        .name => |n| {
            try uses.put(n.id, {});
        },
        .assign => |a| {
            // Collect target names (assigned variables should be marked as used)
            for (a.targets) |target| {
                try collectUsedNamesFromNode(target, uses);
            }
            try collectUsedNamesFromNode(a.value.*, uses);
        },
        .aug_assign => |a| {
            try collectUsedNamesFromNode(a.target.*, uses);
            try collectUsedNamesFromNode(a.value.*, uses);
        },
        .binop => |b| {
            try collectUsedNamesFromNode(b.left.*, uses);
            try collectUsedNamesFromNode(b.right.*, uses);
        },
        .unaryop => |u| {
            try collectUsedNamesFromNode(u.operand.*, uses);
        },
        .call => |c| {
            try collectUsedNamesFromNode(c.func.*, uses);
            for (c.args) |arg| {
                try collectUsedNamesFromNode(arg, uses);
            }
        },
        .attribute => |a| {
            try collectUsedNamesFromNode(a.value.*, uses);
        },
        .subscript => |s| {
            try collectUsedNamesFromNode(s.value.*, uses);
            switch (s.slice) {
                .index => |idx| try collectUsedNamesFromNode(idx.*, uses),
                .slice => |sl| {
                    if (sl.lower) |l| try collectUsedNamesFromNode(l.*, uses);
                    if (sl.upper) |upper| try collectUsedNamesFromNode(upper.*, uses);
                    if (sl.step) |st| try collectUsedNamesFromNode(st.*, uses);
                },
            }
        },
        .if_stmt => |i| {
            try collectUsedNamesFromNode(i.condition.*, uses);
            try collectUsedNames(i.body, uses);
            try collectUsedNames(i.else_body, uses);
        },
        .if_expr => |ie| {
            try collectUsedNamesFromNode(ie.condition.*, uses);
            try collectUsedNamesFromNode(ie.body.*, uses);
            try collectUsedNamesFromNode(ie.orelse_value.*, uses);
        },
        .for_stmt => |f| {
            try collectUsedNamesFromNode(f.target.*, uses);
            try collectUsedNamesFromNode(f.iter.*, uses);
            try collectUsedNames(f.body, uses);
            if (f.orelse_body) |else_body| {
                try collectUsedNames(else_body, uses);
            }
        },
        .while_stmt => |w| {
            try collectUsedNamesFromNode(w.condition.*, uses);
            try collectUsedNames(w.body, uses);
            if (w.orelse_body) |else_body| {
                try collectUsedNames(else_body, uses);
            }
        },
        .return_stmt => |r| {
            if (r.value) |v| try collectUsedNamesFromNode(v.*, uses);
        },
        .expr_stmt => |e| {
            try collectUsedNamesFromNode(e.value.*, uses);
        },
        .compare => |c| {
            try collectUsedNamesFromNode(c.left.*, uses);
            for (c.comparators) |cmp| {
                try collectUsedNamesFromNode(cmp, uses);
            }
        },
        .tuple => |t| {
            for (t.elts) |elt| {
                try collectUsedNamesFromNode(elt, uses);
            }
        },
        .list => |l| {
            for (l.elts) |elt| {
                try collectUsedNamesFromNode(elt, uses);
            }
        },
        .dict => |d| {
            for (d.keys) |key| {
                try collectUsedNamesFromNode(key, uses);
            }
            for (d.values) |val| {
                try collectUsedNamesFromNode(val, uses);
            }
        },
        .boolop => |b| {
            for (b.values) |val| {
                try collectUsedNamesFromNode(val, uses);
            }
        },
        .function_def => |f| {
            // For nested functions, collect names used in the body
            try collectUsedNames(f.body, uses);
        },
        else => {
            // Other node types don't contain name references we need to track
        },
    }
}
