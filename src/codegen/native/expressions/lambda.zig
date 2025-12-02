/// Lambda expression code generation
/// Generates anonymous functions as named functions with function pointers
/// With closure support using Zig structs
const std = @import("std");
const hashmap_helper = @import("hashmap_helper");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const zig_keywords = @import("zig_keywords");

const ClosureError = error{
    NotAClosure,
} || CodegenError;
const native_types = @import("../../../analysis/native_types.zig");
const NativeType = native_types.NativeType;
const lambda_closure = @import("lambda_closure.zig");
const shared = @import("../shared_maps.zig");
const ListMethodsMap = shared.MutatingMethods;
const StringMethodsMap = shared.StringMethods;

const TypeStrToNativeMap = std.StaticStringMap(NativeType).initComptime(.{
    .{ "i64", NativeType{ .int = .bounded } },
    .{ "f64", NativeType.float },
    .{ "bool", NativeType.bool },
    .{ "[]const u8", NativeType{ .string = .runtime } },
});

/// Generate lambda expression as anonymous function
/// Strategy: Generate named function at module level, return function pointer
/// UNLESS the lambda captures nested types (classes defined in enclosing function),
/// in which case generate an inline struct lambda to keep types in scope.
///
/// Example (no captures):
///   Python: lambda x: x * 2
///   Zig:    fn __lambda_0(x: i64) i64 { return x * 2; }
///           &__lambda_0
///
/// Example (captures nested type):
///   Python: class Foo: ...; f = lambda x: Foo(x)
///   Zig:    const Foo = struct { ... };
///           const f = struct { fn call(x: i64) Foo { return Foo.init(x); } }.call;
pub fn genLambda(self: *NativeCodegen, lambda: ast.Node.Lambda) ClosureError!void {
    // Check if this is a closure (lambda returning lambda)
    if (lambda.body.* == .lambda) {
        // Try closure generation
        lambda_closure.genClosureLambda(self, lambda) catch {
            // If closure generation fails, fall back to regular lambda
            // This can happen if closure support is incomplete
        };
        return;
    }

    // Check if lambda references nested classes (types defined in enclosing function)
    // These CANNOT be hoisted to module level - the type wouldn't be in scope
    if (referencesNestedClass(self, lambda.body.*)) {
        try genInlineLambda(self, lambda);
        return;
    }

    // Check if lambda references variables from outer scope (not its parameters)
    const captured_vars = try findCapturedVars(self, lambda);
    defer self.allocator.free(captured_vars);

    if (captured_vars.len > 0) {
        // This lambda captures outer variables - treat as closure
        try lambda_closure.genSimpleClosureLambda(self, lambda, captured_vars);
        // Note: The caller (assignment) needs to mark this variable as a closure
        // We can't do it here because we don't know the variable name
        return;
    }

    // Generate unique lambda function name
    const lambda_name = try std.fmt.allocPrint(
        self.allocator,
        "__lambda_{d}",
        .{self.lambda_counter},
    );
    // Don't free yet - we need it for later
    self.lambda_counter += 1;

    // Save current output position - we'll generate lambda function separately
    const current_output = try self.output.toOwnedSlice(self.allocator);
    defer self.allocator.free(current_output);

    // Generate lambda function definition
    var lambda_func = std.ArrayList(u8){};

    // Function signature: fn __lambda_N(
    try lambda_func.writer(self.allocator).print("fn {s}(", .{lambda_name});

    // First pass: Infer parameter types and register them
    var param_types = try self.allocator.alloc([]const u8, lambda.args.len);
    defer self.allocator.free(param_types);

    for (lambda.args, 0..) |arg, i| {
        // Infer parameter type from how it's used in the body
        param_types[i] = try inferParamType(self, arg.name, lambda.body.*);

        // Register parameter with type inferrer so it knows the type during body codegen
        const native_type = stringToNativeType(param_types[i]);
        try self.type_inferrer.var_types.put(arg.name, native_type);
    }

    // Generate parameter list - check if parameter is used in body
    for (lambda.args, 0..) |arg, i| {
        if (i > 0) try lambda_func.writer(self.allocator).writeAll(", ");
        // Check if param is used in body - if not, use _ to discard
        const is_used = isParamUsedInBody(arg.name, lambda.body.*);
        if (is_used) {
            // Escape Zig reserved keywords (e.g., "fn" -> @"fn", "test" -> @"test")
            try zig_keywords.writeEscapedIdent(lambda_func.writer(self.allocator), arg.name);
            try lambda_func.writer(self.allocator).print(": {s}", .{param_types[i]});
        } else {
            // In Zig 0.15, unused params must be named exactly "_", not "_name"
            try lambda_func.writer(self.allocator).print("_: {s}", .{param_types[i]});
        }
    }

    // Infer return type from body expression (now that params are registered)
    const return_type = try inferReturnType(self, lambda.body.*);
    try lambda_func.writer(self.allocator).print(") {s} {{\n", .{return_type});

    // Clean up registered parameters after lambda generation
    defer {
        for (lambda.args) |arg| {
            _ = self.type_inferrer.var_types.swapRemove(arg.name);
        }
    }

    // Generate body - single return expression
    try lambda_func.writer(self.allocator).writeAll("    return ");

    // Generate body expression in temporary output
    const saved_output = self.output;
    self.output = std.ArrayList(u8){};

    // Import expressions module to generate body
    const expressions = @import("../expressions.zig");
    try expressions.genExpr(self, lambda.body.*);

    const body_code = try self.output.toOwnedSlice(self.allocator);
    self.output = saved_output;

    try lambda_func.writer(self.allocator).writeAll(body_code);
    self.allocator.free(body_code);

    try lambda_func.writer(self.allocator).writeAll(";\n}\n\n");

    // Store lambda function for later prepending to module
    try self.lambda_functions.append(self.allocator, try lambda_func.toOwnedSlice(self.allocator));

    // Restore original output
    self.output = std.ArrayList(u8){};
    try self.emit(current_output);

    // Generate function pointer reference in current context
    try self.emit("&");
    try self.emit(lambda_name);

    // Free lambda_name now
    self.allocator.free(lambda_name);
}

/// Public function to check if lambda captures outer variables
pub fn lambdaCapturesVars(self: *NativeCodegen, lambda: ast.Node.Lambda) bool {
    const captured_vars = findCapturedVars(self, lambda) catch return false;
    defer self.allocator.free(captured_vars);
    return captured_vars.len > 0;
}

/// Public function to get lambda return type
pub fn getLambdaReturnType(self: *NativeCodegen, lambda: ast.Node.Lambda) CodegenError!NativeType {
    // First register parameter types temporarily
    for (lambda.args) |arg| {
        const param_type_str = try inferParamType(self, arg.name, lambda.body.*);
        const param_native_type = stringToNativeType(param_type_str);
        try self.type_inferrer.var_types.put(arg.name, param_native_type);
    }
    defer {
        for (lambda.args) |arg| {
            _ = self.type_inferrer.var_types.swapRemove(arg.name);
        }
    }

    const return_type_str = try inferReturnType(self, lambda.body.*);
    return stringToNativeType(return_type_str);
}

/// Find variables captured from outer scope (not lambda parameters)
fn findCapturedVars(self: *NativeCodegen, lambda: ast.Node.Lambda) CodegenError![][]const u8 {
    var captured = std.ArrayList([]const u8){};

    // Find all variable references in lambda body
    try findVarReferences(self, lambda.body.*, &captured);

    // Remove lambda parameters from captured list
    var filtered = std.ArrayList([]const u8){};
    for (captured.items) |var_name| {
        var is_param = false;
        for (lambda.args) |arg| {
            if (std.mem.eql(u8, var_name, arg.name)) {
                is_param = true;
                break;
            }
        }
        if (!is_param) {
            // Check if this variable is actually declared in outer scope
            // Also treat "self" as a captured variable when inside a class method
            // Check both symbol_table (via isDeclared) and type_inferrer.var_types
            // because for loop variables are only in var_types, not symbol_table
            if (self.isDeclared(var_name) or
                self.type_inferrer.var_types.contains(var_name) or
                (std.mem.eql(u8, var_name, "self") and self.current_class_name != null))
            {
                try filtered.append(self.allocator, var_name);
            }
        }
    }

    captured.deinit(self.allocator);
    return filtered.toOwnedSlice(self.allocator);
}

/// Check if a parameter name is used in the lambda body (for unused parameter detection)
fn isParamUsedInBody(param_name: []const u8, body: ast.Node) bool {
    return switch (body) {
        .name => |n| std.mem.eql(u8, n.id, param_name),
        .binop => |b| isParamUsedInBody(param_name, b.left.*) or isParamUsedInBody(param_name, b.right.*),
        .unaryop => |u| isParamUsedInBody(param_name, u.operand.*),
        .call => |c| blk: {
            if (isParamUsedInBody(param_name, c.func.*)) break :blk true;
            for (c.args) |arg| {
                if (isParamUsedInBody(param_name, arg)) break :blk true;
            }
            for (c.keyword_args) |kw| {
                if (isParamUsedInBody(param_name, kw.value)) break :blk true;
            }
            break :blk false;
        },
        .compare => |cmp| blk: {
            if (isParamUsedInBody(param_name, cmp.left.*)) break :blk true;
            for (cmp.comparators) |comp| {
                if (isParamUsedInBody(param_name, comp)) break :blk true;
            }
            break :blk false;
        },
        .subscript => |sub| isParamUsedInBody(param_name, sub.value.*) or
            (if (sub.slice == .index) isParamUsedInBody(param_name, sub.slice.index.*) else false),
        .attribute => |attr| isParamUsedInBody(param_name, attr.value.*),
        .if_expr => |ie| isParamUsedInBody(param_name, ie.condition.*) or
            isParamUsedInBody(param_name, ie.body.*) or
            isParamUsedInBody(param_name, ie.orelse_value.*),
        .list => |l| blk: {
            for (l.elts) |elt| {
                if (isParamUsedInBody(param_name, elt)) break :blk true;
            }
            break :blk false;
        },
        .tuple => |t| blk: {
            for (t.elts) |elt| {
                if (isParamUsedInBody(param_name, elt)) break :blk true;
            }
            break :blk false;
        },
        .dict => |d| blk: {
            for (d.keys) |key| {
                if (isParamUsedInBody(param_name, key)) break :blk true;
            }
            for (d.values) |val| {
                if (isParamUsedInBody(param_name, val)) break :blk true;
            }
            break :blk false;
        },
        .lambda => |lam| isParamUsedInBody(param_name, lam.body.*),
        .boolop => |bo| blk: {
            for (bo.values) |v| {
                if (isParamUsedInBody(param_name, v)) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

/// Recursively find all variable references in AST
fn findVarReferences(self: *NativeCodegen, node: ast.Node, captured: *std.ArrayList([]const u8)) CodegenError!void {
    switch (node) {
        .name => |n| {
            // Add to captured list if not already there
            for (captured.items) |existing| {
                if (std.mem.eql(u8, existing, n.id)) return;
            }
            try captured.append(self.allocator, n.id);
        },
        .binop => |b| {
            try findVarReferences(self, b.left.*, captured);
            try findVarReferences(self, b.right.*, captured);
        },
        .call => |c| {
            try findVarReferences(self, c.func.*, captured);
            for (c.args) |arg| {
                try findVarReferences(self, arg, captured);
            }
            for (c.keyword_args) |kw| {
                try findVarReferences(self, kw.value, captured);
            }
        },
        .compare => |cmp| {
            try findVarReferences(self, cmp.left.*, captured);
            for (cmp.comparators) |comp| {
                try findVarReferences(self, comp, captured);
            }
        },
        .attribute => |attr| {
            // Recurse into the value (e.g., for self.x, we need to capture self)
            try findVarReferences(self, attr.value.*, captured);
        },
        .subscript => |sub| {
            try findVarReferences(self, sub.value.*, captured);
            if (sub.slice == .index) {
                try findVarReferences(self, sub.slice.index.*, captured);
            }
        },
        .if_expr => |ie| {
            try findVarReferences(self, ie.condition.*, captured);
            try findVarReferences(self, ie.body.*, captured);
            try findVarReferences(self, ie.orelse_value.*, captured);
        },
        .unaryop => |u| {
            try findVarReferences(self, u.operand.*, captured);
        },
        .list => |l| {
            for (l.elts) |elt| {
                try findVarReferences(self, elt, captured);
            }
        },
        .tuple => |t| {
            for (t.elts) |elt| {
                try findVarReferences(self, elt, captured);
            }
        },
        .dict => |d| {
            for (d.keys) |key| {
                try findVarReferences(self, key, captured);
            }
            for (d.values) |val| {
                try findVarReferences(self, val, captured);
            }
        },
        .lambda => |lam| {
            try findVarReferences(self, lam.body.*, captured);
        },
        .boolop => |bo| {
            for (bo.values) |v| {
                try findVarReferences(self, v, captured);
            }
        },
        else => {},
    }
}

/// Convert type string to NativeType
fn stringToNativeType(type_str: []const u8) NativeType {
    // Check static map first
    if (TypeStrToNativeMap.get(type_str)) |native_type| {
        return native_type;
    }
    // Check if it's a closure type (__Closure_N)
    if (std.mem.startsWith(u8, type_str, "__Closure_")) {
        return .{ .closure = type_str };
    }
    // For complex types, default to unknown
    return .unknown;
}

/// Infer parameter type from how it's used in the lambda body
fn inferParamType(self: *NativeCodegen, param_name: []const u8, body: ast.Node) CodegenError![]const u8 {
    // Analyze body to determine how the parameter is used
    return analyzeParamUsage(self, param_name, body);
}

/// Recursively analyze how a parameter is used to infer its type
fn analyzeParamUsage(self: *NativeCodegen, param_name: []const u8, node: ast.Node) CodegenError![]const u8 {
    switch (node) {
        // If param is subscripted: param[x], likely string or list
        .subscript => |sub| {
            if (sub.value.* == .name and std.mem.eql(u8, sub.value.name.id, param_name)) {
                // Check if index is integer (string/list) or string (dict)
                if (sub.slice == .index) {
                    const index_type = self.type_inferrer.inferExpr(sub.slice.index.*) catch .unknown;
                    if (index_type == .int) {
                        // Could be string or list - default to string for single char access
                        // Heuristic: if used with string operations elsewhere, it's string
                        return "[]const u8";
                    } else if (index_type == .string) {
                        return "hashmap_helper.StringHashMap(i64)"; // Dict access
                    }
                }
                return "[]const u8"; // Default for subscript
            }
            // Recurse into subscript parts
            const val_type = try analyzeParamUsage(self, param_name, sub.value.*);
            if (!std.mem.eql(u8, val_type, "i64")) return val_type;
            if (sub.slice == .index) {
                const idx_type = try analyzeParamUsage(self, param_name, sub.slice.index.*);
                if (!std.mem.eql(u8, idx_type, "i64")) return idx_type;
            }
            return "i64";
        },

        // If param is used in string operations, it's a string
        .binop => |b| {
            const left_type = try analyzeParamUsage(self, param_name, b.left.*);
            const right_type = try analyzeParamUsage(self, param_name, b.right.*);

            // If either side inferred non-i64, propagate that
            if (!std.mem.eql(u8, left_type, "i64")) return left_type;
            if (!std.mem.eql(u8, right_type, "i64")) return right_type;

            return "i64";
        },

        // If param is called as attribute method: param.method()
        .attribute => |attr| {
            if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, param_name)) {
                // Check common string methods
                if (StringMethodsMap.has(attr.attr)) return "[]const u8";
                // Check list methods
                if (ListMethodsMap.has(attr.attr)) return "std.ArrayList(i64)";
            }
            return try analyzeParamUsage(self, param_name, attr.value.*);
        },

        // If it's just the parameter name by itself
        .name => |n| {
            if (std.mem.eql(u8, n.id, param_name)) {
                // Can't determine type from name alone
                return "i64"; // Default
            }
            return "i64";
        },

        // If used in comparison
        .compare => |cmp| {
            const left_type = try analyzeParamUsage(self, param_name, cmp.left.*);
            if (!std.mem.eql(u8, left_type, "i64")) return left_type;

            for (cmp.comparators) |comp| {
                const comp_type = try analyzeParamUsage(self, param_name, comp);
                if (!std.mem.eql(u8, comp_type, "i64")) return comp_type;
            }
            return "i64";
        },

        // Recurse into other node types
        .call => |c| {
            const func_type = try analyzeParamUsage(self, param_name, c.func.*);
            if (!std.mem.eql(u8, func_type, "i64")) return func_type;

            for (c.args) |arg| {
                const arg_type = try analyzeParamUsage(self, param_name, arg);
                if (!std.mem.eql(u8, arg_type, "i64")) return arg_type;
            }
            return "i64";
        },

        .unaryop => |u| {
            return try analyzeParamUsage(self, param_name, u.operand.*);
        },

        else => return "i64", // Default fallback
    }
}

/// Infer return type from lambda body expression
fn inferReturnType(self: *NativeCodegen, body: ast.Node) CodegenError![]const u8 {
    // Special case: closure (lambda returning lambda)
    if (body == .lambda) {
        // Generate closure name to match what will be generated
        const closure_name = try std.fmt.allocPrint(
            self.allocator,
            "__Closure_{d}",
            .{self.lambda_counter},
        );
        return closure_name; // Caller must free this
    }

    // Special case: string[index] in Python returns string (single char string)
    // In Zig, we return []const u8 slice
    if (body == .subscript) {
        const sub = body.subscript;
        if (sub.slice == .index) {
            // Check if the value being subscripted is a string
            const value_type = self.type_inferrer.inferExpr(sub.value.*) catch .unknown;
            if (value_type == .string) {
                // Python: s[0] returns "h" (string)
                // Zig: return []const u8 slice
                return "[]const u8";
            }
        }
    }

    const inferred_type = self.type_inferrer.inferExpr(body) catch {
        return "i64"; // Default fallback
    };

    return switch (inferred_type) {
        .list => |_| "std.ArrayList(i64)", // Simplified - would need element type
        .dict => "hashmap_helper.StringHashMap(i64)", // Simplified
        else => inferred_type.toSimpleZigType(),
    };
}

/// Check if an AST node references any nested class names
/// Nested classes are types defined inside the enclosing function - they cannot be
/// referenced from module-level hoisted lambda functions because the type isn't in scope.
fn referencesNestedClass(self: *NativeCodegen, node: ast.Node) bool {
    // Skip if no nested classes are tracked
    if (self.nested_class_names.count() == 0) return false;

    switch (node) {
        .name => |n| {
            // Check if this name is a nested class
            return self.nested_class_names.contains(n.id);
        },
        .call => |c| {
            // Check function name (e.g., CustomStr(...))
            if (referencesNestedClass(self, c.func.*)) return true;
            // Check arguments
            for (c.args) |arg| {
                if (referencesNestedClass(self, arg)) return true;
            }
            for (c.keyword_args) |kw| {
                if (referencesNestedClass(self, kw.value)) return true;
            }
            return false;
        },
        .binop => |b| {
            return referencesNestedClass(self, b.left.*) or
                referencesNestedClass(self, b.right.*);
        },
        .compare => |cmp| {
            if (referencesNestedClass(self, cmp.left.*)) return true;
            for (cmp.comparators) |comp| {
                if (referencesNestedClass(self, comp)) return true;
            }
            return false;
        },
        .attribute => |attr| {
            return referencesNestedClass(self, attr.value.*);
        },
        .subscript => |sub| {
            if (referencesNestedClass(self, sub.value.*)) return true;
            if (sub.slice == .index) {
                return referencesNestedClass(self, sub.slice.index.*);
            }
            return false;
        },
        .if_expr => |ie| {
            return referencesNestedClass(self, ie.condition.*) or
                referencesNestedClass(self, ie.body.*) or
                referencesNestedClass(self, ie.orelse_value.*);
        },
        .unaryop => |u| {
            return referencesNestedClass(self, u.operand.*);
        },
        .list => |l| {
            for (l.elts) |elt| {
                if (referencesNestedClass(self, elt)) return true;
            }
            return false;
        },
        .tuple => |t| {
            for (t.elts) |elt| {
                if (referencesNestedClass(self, elt)) return true;
            }
            return false;
        },
        .dict => |d| {
            for (d.keys) |key| {
                if (referencesNestedClass(self, key)) return true;
            }
            for (d.values) |val| {
                if (referencesNestedClass(self, val)) return true;
            }
            return false;
        },
        .lambda => |lam| {
            return referencesNestedClass(self, lam.body.*);
        },
        .boolop => |bo| {
            for (bo.values) |v| {
                if (referencesNestedClass(self, v)) return true;
            }
            return false;
        },
        else => return false,
    }
}

/// Generate an inline struct lambda for lambdas that reference nested types
/// This keeps the type in scope instead of hoisting to module level.
///
/// Python: lambda x: CustomStr(x)
/// Zig:    (struct { fn call(x: i64) CustomStr { return CustomStr.init(x); } }).call
fn genInlineLambda(self: *NativeCodegen, lambda: ast.Node.Lambda) CodegenError!void {
    // Start inline struct
    try self.emit("(struct { fn call(");

    // First pass: Infer parameter types
    var param_types = try self.allocator.alloc([]const u8, lambda.args.len);
    defer self.allocator.free(param_types);

    for (lambda.args, 0..) |arg, i| {
        param_types[i] = try inferParamType(self, arg.name, lambda.body.*);

        // Register parameter with type inferrer
        const native_type = stringToNativeType(param_types[i]);
        try self.type_inferrer.var_types.put(arg.name, native_type);
    }

    // Generate parameter list
    for (lambda.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        const is_used = isParamUsedInBody(arg.name, lambda.body.*);
        if (is_used) {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
            try self.emit(": ");
            try self.emit(param_types[i]);
        } else {
            try self.emit("_: ");
            try self.emit(param_types[i]);
        }
    }

    // Return type
    const return_type = try inferReturnType(self, lambda.body.*);
    try self.emit(") ");
    try self.emit(return_type);
    try self.emit(" { return ");

    // Generate body expression
    const expressions = @import("../expressions.zig");
    try expressions.genExpr(self, lambda.body.*);

    try self.emit("; } }).call");

    // Clean up registered parameters
    for (lambda.args) |arg| {
        _ = self.type_inferrer.var_types.swapRemove(arg.name);
    }
}
