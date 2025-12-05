/// Enhanced lambda with closure support using Zig comptime
/// Handles: lambda returning lambda, variable capture, higher-order functions
const std = @import("std");
const hashmap_helper = @import("hashmap_helper");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const native_types = @import("../../../analysis/native_types.zig");
const NativeType = native_types.NativeType;
const zig_keywords = @import("zig_keywords");
const shared = @import("../shared_maps.zig");
const BinOpStrings = shared.BinOpStrings;
const CompOpStrings = shared.CompOpStrings;
const method_calls = @import("../dispatch/method_calls.zig");

const ClosureError = error{
    NotAClosure,
} || CodegenError;

/// Check if lambda body is itself a lambda (closure case)
fn isClosureLambda(body: ast.Node) bool {
    return body == .lambda;
}

/// Analyze which outer variables are captured by inner lambda
fn findCapturedVars(self: *NativeCodegen, outer_params: []ast.Arg, inner_lambda: ast.Node.Lambda) ![][]const u8 {
    var captured = std.ArrayList([]const u8){};

    // For each outer parameter, check if it's referenced in inner lambda body
    for (outer_params) |param| {
        if (try isVarReferenced(self, param.name, inner_lambda.body.*)) {
            try captured.append(self.allocator, param.name);
        }
    }

    return captured.toOwnedSlice(self.allocator);
}

/// Check if variable name is referenced in AST node
fn isVarReferenced(self: *NativeCodegen, var_name: []const u8, node: ast.Node) CodegenError!bool {
    switch (node) {
        .name => |n| return std.mem.eql(u8, n.id, var_name),
        .binop => |b| {
            return (try isVarReferenced(self, var_name, b.left.*)) or
                (try isVarReferenced(self, var_name, b.right.*));
        },
        .call => |c| {
            if (try isVarReferenced(self, var_name, c.func.*)) return true;
            for (c.args) |arg| {
                if (try isVarReferenced(self, var_name, arg)) return true;
            }
            return false;
        },
        .compare => |c| {
            if (try isVarReferenced(self, var_name, c.left.*)) return true;
            for (c.comparators) |comp| {
                if (try isVarReferenced(self, var_name, comp)) return true;
            }
            return false;
        },
        else => return false,
    }
}

/// Generate closure lambda (returns struct with captured state)
/// Example: make_adder = lambda x: lambda y: x + y
pub fn genClosureLambda(self: *NativeCodegen, outer_lambda: ast.Node.Lambda) ClosureError!void {
    const closure_name = try std.fmt.allocPrint(
        self.allocator,
        "__Closure_{d}",
        .{self.lambda_counter},
    );
    self.lambda_counter += 1;

    // Check if body is a lambda (closure case)
    if (!isClosureLambda(outer_lambda.body.*)) {
        // Not a closure, fall back to regular lambda
        return error.NotAClosure;
    }

    const inner_lambda = outer_lambda.body.lambda;

    // Find captured variables
    const captured_vars = try findCapturedVars(self, outer_lambda.args, inner_lambda);
    defer self.allocator.free(captured_vars);

    // Check if we're inside a function - if so, use inline struct pattern
    const inside_function = self.current_function_name != null or self.indent_level > 0;
    if (inside_function) {
        // Generate inline struct: struct { x: i64, pub fn call(self: @This(), y: i64) i64 { ... } }.call
        try genInlineClosureLambda(self, outer_lambda, captured_vars);
        self.allocator.free(closure_name);
        return;
    }

    // Module-level hoisting - save current output
    const current_output = try self.output.toOwnedSlice(self.allocator);
    defer self.allocator.free(current_output);

    // Generate closure struct to separate buffer
    var closure_code = std.ArrayList(u8){};
    const writer = closure_code.writer(self.allocator);

    // Struct definition
    try writer.print("const {s} = struct {{\n", .{closure_name});

    // Captured fields - use concrete types from type inference
    for (captured_vars) |var_name| {
        // Get type from type inference
        const var_type = self.getVarType(var_name) orelse .unknown;
        const zig_type = try self.nativeTypeToZigType(var_type);
        defer self.allocator.free(zig_type);

        try writer.print("    {s}: {s},\n", .{ var_name, zig_type });
    }
    try writer.writeAll("\n");

    // Call method (inner lambda)
    try writer.writeAll("    pub fn call(self: @This()");
    for (inner_lambda.args) |arg| {
        try writer.writeAll(", ");
        try zig_keywords.writeEscapedIdent(writer, arg.name);
        try writer.writeAll(": anytype");
    }

    // Infer return type from inner lambda body
    const return_type = try inferReturnType(self, inner_lambda.body.*);
    try writer.print(") {s} {{\n", .{return_type});
    try writer.writeAll("        return ");

    // Generate inner lambda body with captured variable references
    const saved_output = self.output;
    self.output = std.ArrayList(u8){};

    // Generate expression with captured vars prefixed with "self."
    try genExprWithCapture(self, inner_lambda.body.*, captured_vars);

    const body_code = try self.output.toOwnedSlice(self.allocator);
    self.output = saved_output;

    try writer.writeAll(body_code);
    self.allocator.free(body_code);

    try writer.writeAll(";\n    }\n};\n");

    // Generate factory function (outer lambda)
    const factory_name = try std.fmt.allocPrint(
        self.allocator,
        "__lambda_{d}",
        .{self.lambda_counter},
    );
    defer self.allocator.free(factory_name);
    self.lambda_counter += 1;

    try writer.print("fn {s}(", .{factory_name});
    for (outer_lambda.args, 0..) |arg, i| {
        if (i > 0) try writer.writeAll(", ");
        try zig_keywords.writeEscapedIdent(writer, arg.name);
        try writer.writeAll(": anytype");
    }
    try writer.print(") {s} {{\n", .{closure_name});
    try writer.writeAll("    return .{\n");

    // Initialize captured fields
    for (captured_vars) |var_name| {
        try writer.print("        .{s} = {s},\n", .{ var_name, var_name });
    }

    try writer.writeAll("    };\n}\n");

    // Store closure code at module level
    try self.lambda_functions.append(self.allocator, try closure_code.toOwnedSlice(self.allocator));

    // Restore output
    self.output = std.ArrayList(u8){};
    try self.emit(current_output);

    // Generate factory call (just the function name, not & prefix for closures)
    try self.emit(factory_name);

    self.allocator.free(closure_name);
}

/// Generate inline closure lambda for use inside functions
/// Generates: (struct { x: i64, fn init(x: i64) @This() { return .{ .x = x }; } pub fn call(self: @This(), y: i64) i64 { ... } }).init(x)
fn genInlineClosureLambda(self: *NativeCodegen, outer_lambda: ast.Node.Lambda, captured_vars: [][]const u8) ClosureError!void {
    const inner_lambda = outer_lambda.body.lambda;

    // Start inline struct with call being the inner lambda
    try self.emit("(struct {\n");

    // Fields for captured vars
    for (captured_vars) |var_name| {
        const var_type = self.getVarType(var_name) orelse .unknown;
        const zig_type = try self.nativeTypeToZigType(var_type);
        defer self.allocator.free(zig_type);
        try self.output.writer(self.allocator).print("    {s}: {s},\n", .{ var_name, zig_type });
    }
    try self.emit("\n");

    // Init function to create closure from outer lambda args
    try self.emit("    fn init(");
    for (outer_lambda.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
        try self.emit(": anytype");
    }
    try self.emit(") @This() {\n        return .{\n");
    for (captured_vars) |var_name| {
        try self.output.writer(self.allocator).print("            .{s} = {s},\n", .{ var_name, var_name });
    }
    try self.emit("        };\n    }\n\n");

    // Call method (inner lambda)
    try self.emit("    pub fn call(self: @This()");
    for (inner_lambda.args) |arg| {
        try self.emit(", ");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
        try self.emit(": anytype");
    }

    // Return type
    const return_type = try inferReturnType(self, inner_lambda.body.*);
    try self.output.writer(self.allocator).print(") {s} {{\n        return ", .{return_type});

    // Generate inner body with captured vars prefixed with self.
    try genExprWithCapture(self, inner_lambda.body.*, captured_vars);

    try self.emit(";\n    }\n}).init");
}

/// Mark a variable as holding a closure (so we generate .call())
pub fn markAsClosure(self: *NativeCodegen, var_name: []const u8) !void {
    const owned_name = try self.allocator.dupe(u8, var_name);
    try self.closure_vars.put(owned_name, {});
}

/// Mark a variable as holding a void-returning closure (no catch needed)
pub fn markAsVoidClosure(self: *NativeCodegen, var_name: []const u8) !void {
    const owned_name = try self.allocator.dupe(u8, var_name);
    try self.void_closure_vars.put(owned_name, {});
}

/// Mark a variable as a closure factory (returns closures)
pub fn markAsClosureFactory(self: *NativeCodegen, var_name: []const u8) !void {
    const owned_name = try self.allocator.dupe(u8, var_name);
    try self.closure_factories.put(owned_name, {});
}

/// Check if lambda body returns void (e.g., calls self.assertRaises)
pub fn lambdaReturnsVoid(lambda: ast.Node.Lambda) bool {
    // Check if body is a call on self.unittest_method
    if (lambda.body.* == .call) {
        const call = lambda.body.call;
        if (call.func.* == .attribute) {
            const attr = call.func.attribute;
            if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                return isUnittestMethod(attr.attr);
            }
        }
    }
    return false;
}

/// Generate simple closure for lambda capturing outer variables
/// Example: x = 10; f = lambda y: y + x
pub fn genSimpleClosureLambda(self: *NativeCodegen, lambda: ast.Node.Lambda, captured_vars: [][]const u8) ClosureError!void {
    const closure_name = try std.fmt.allocPrint(
        self.allocator,
        "__Closure_{d}",
        .{self.lambda_counter},
    );
    self.lambda_counter += 1;

    // Check if we're inside a function - if so, generate inline instead of hoisting
    const inside_function = self.current_function_name != null or self.indent_level > 0;
    if (inside_function) {
        try genInlineSimpleClosureLambda(self, lambda, captured_vars);
        self.allocator.free(closure_name);
        return;
    }

    // Module-level: save current output
    const current_output = try self.output.toOwnedSlice(self.allocator);
    defer self.allocator.free(current_output);

    // Generate closure struct to separate buffer
    var closure_code = std.ArrayList(u8){};
    const writer = closure_code.writer(self.allocator);

    // Generate closure struct with concrete types
    try writer.print("const {s} = struct {{\n", .{closure_name});

    // Captured fields with concrete types from type inference
    for (captured_vars) |var_name| {
        // Get type from type inference
        const var_type = self.getVarType(var_name) orelse .unknown;
        const zig_type = try self.nativeTypeToZigType(var_type);
        defer self.allocator.free(zig_type);

        try writer.print("    {s}: {s},\n", .{ var_name, zig_type });
    }
    try writer.writeAll("\n");

    // Check if self is only used for unittest methods (in which case we don't need the captured self)
    const self_only_for_unittest = isSelfOnlyForUnittest(lambda.body.*, captured_vars);

    // Call method - use _ or self as parameter name depending on usage
    if (self_only_for_unittest) {
        try writer.writeAll("    pub fn call(_: @This()");
    } else {
        try writer.writeAll("    pub fn call(self: @This()");
    }
    for (lambda.args) |arg| {
        try writer.writeAll(", ");
        try zig_keywords.writeEscapedIdent(writer, arg.name);
        try writer.writeAll(": anytype");
    }

    // Infer return type
    const return_type = try inferReturnType(self, lambda.body.*);
    try writer.print(") {s} {{\n", .{return_type});
    // Don't use return for void functions
    if (std.mem.eql(u8, return_type, "void")) {
        try writer.writeAll("        ");
    } else {
        try writer.writeAll("        return ");
    }

    // Generate body with captured vars prefixed with "self."
    // For inline mode, we need a temp buffer; for module level we use closure_code
    const saved_output = self.output;
    self.output = std.ArrayList(u8){};

    try genExprWithCapture(self, lambda.body.*, captured_vars);

    const body_code = try self.output.toOwnedSlice(self.allocator);
    self.output = saved_output;

    try writer.writeAll(body_code);

    // Don't add semicolon if body already ends with } (block expressions like assertRaises)
    const needs_semicolon = body_code.len == 0 or body_code[body_code.len - 1] != '}';
    self.allocator.free(body_code);

    if (needs_semicolon) {
        try writer.writeAll(";\n    }\n};\n");
    } else {
        try writer.writeAll("\n    }\n};\n");
    }

    // Store closure struct at module level
    try self.lambda_functions.append(self.allocator, try closure_code.toOwnedSlice(self.allocator));

    // Restore output
    self.output = std.ArrayList(u8){};
    try self.emit(current_output);

    // Generate closure instantiation: Closure{ .f = f, .g = g }
    // For "self", we need to dereference since it's a pointer in methods (*const @This() or *@This())
    try self.output.writer(self.allocator).print("{s}{{ ", .{closure_name});
    for (captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        if (std.mem.eql(u8, var_name, "self")) {
            // Dereference self pointer to get the struct value
            try self.output.writer(self.allocator).print(".{s} = {s}.*", .{ var_name, var_name });
        } else {
            try self.output.writer(self.allocator).print(".{s} = {s}", .{ var_name, var_name });
        }
    }
    try self.emit(" }");

    self.allocator.free(closure_name);

    // Return success - caller should mark this variable as a closure
}

/// Generate inline simple closure for use inside functions
/// Generates: (struct { x: i64, pub fn call(self: @This(), y: anytype) type { ... } }){ .x = x }
fn genInlineSimpleClosureLambda(self: *NativeCodegen, lambda: ast.Node.Lambda, captured_vars: [][]const u8) ClosureError!void {
    // Start inline struct
    try self.emit("(struct {\n");

    // Fields for captured vars
    for (captured_vars) |var_name| {
        // For 'self' in a class method, use current class name (not type inferrer which may have nested class)
        const zig_type = if (std.mem.eql(u8, var_name, "self") and self.current_class_name != null)
            self.current_class_name.?
        else blk: {
            const var_type = self.getVarType(var_name) orelse .unknown;
            break :blk try self.nativeTypeToZigType(var_type);
        };
        const should_free = !std.mem.eql(u8, var_name, "self") or self.current_class_name == null;
        defer if (should_free) self.allocator.free(zig_type);
        try self.output.writer(self.allocator).print("    {s}: {s},\n", .{ var_name, zig_type });
    }
    try self.emit("\n");

    // Check if self is only used for unittest methods
    const self_only_for_unittest = isSelfOnlyForUnittest(lambda.body.*, captured_vars);

    // Call method - use __cl to avoid shadowing outer 'self' parameter
    if (self_only_for_unittest) {
        try self.emit("    pub fn call(_: @This()");
    } else {
        try self.emit("    pub fn call(__cl: @This()");
    }
    for (lambda.args) |arg| {
        try self.emit(", ");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
        try self.emit(": anytype");
    }

    // Return type
    const return_type = try inferReturnType(self, lambda.body.*);
    try self.output.writer(self.allocator).print(") {s} {{\n", .{return_type});

    // Body - don't use return for void functions
    if (std.mem.eql(u8, return_type, "void")) {
        try self.emit("        ");
    } else {
        try self.emit("        return ");
    }

    // Generate body with captured vars prefixed with __cl. (inline closure param name)
    try genExprWithCapturePrefix(self, lambda.body.*, captured_vars, "__cl");

    try self.emit(";\n    }\n}){ ");

    // Initialize captured fields
    for (captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        if (std.mem.eql(u8, var_name, "self")) {
            try self.output.writer(self.allocator).print(".{s} = {s}.*", .{ var_name, var_name });
        } else {
            try self.output.writer(self.allocator).print(".{s} = {s}", .{ var_name, var_name });
        }
    }
    try self.emit(" }");
}

/// Wrapper for backwards compatibility - uses "self" as default prefix
fn genExprWithCapture(self: *NativeCodegen, node: ast.Node, captured_vars: [][]const u8) CodegenError!void {
    return genExprWithCapturePrefix(self, node, captured_vars, "self");
}

/// Generate expression with captured variable references prefixed with specified name
fn genExprWithCapturePrefix(self: *NativeCodegen, node: ast.Node, captured_vars: [][]const u8, prefix: []const u8) CodegenError!void {
    const expressions = @import("../expressions.zig");

    switch (node) {
        .name => |n| {
            // Check if this variable is captured
            for (captured_vars) |captured| {
                if (std.mem.eql(u8, n.id, captured)) {
                    // Prefix with closure struct parameter name
                    try self.emit(prefix);
                    try self.emit(".");
                    try self.emit(n.id);
                    return;
                }
            }
            // Check if it's a Python exception type
            if (expressions.isPythonExceptionType(n.id)) {
                try self.emit("@intFromEnum(runtime.ExceptionTypeId.");
                try self.emit(n.id);
                try self.emit(")");
                return;
            }
            // Check if it's a builtin type/function
            if (std.mem.eql(u8, n.id, "bool")) {
                try self.emit("runtime.builtins.boolType");
                return;
            }
            // Check for builtin functions (isinstance, len, etc.) - need runtime.builtins prefix
            if (shared.PythonBuiltinNames.has(n.id)) {
                try self.emit("runtime.builtins.");
                try self.emit(n.id);
                return;
            }
            // Not captured, use directly
            try self.emit(n.id);
        },
        .binop => |b| {
            // Use @mod for modulo to handle signed integers properly
            if (b.op == .Mod) {
                try self.emit("@mod(");
                try genExprWithCapturePrefix(self, b.left.*, captured_vars, prefix);
                try self.emit(", ");
                try genExprWithCapturePrefix(self, b.right.*, captured_vars, prefix);
                try self.emit(")");
            } else if (b.op == .Pow) {
                // Zig doesn't have ** operator, use std.math.pow
                try self.emit("std.math.pow(i64, ");
                try genExprWithCapturePrefix(self, b.left.*, captured_vars, prefix);
                try self.emit(", ");
                try genExprWithCapturePrefix(self, b.right.*, captured_vars, prefix);
                try self.emit(")");
            } else if (b.op == .FloorDiv) {
                // Floor division uses @divFloor for Python semantics
                try self.emit("@divFloor(");
                try genExprWithCapturePrefix(self, b.left.*, captured_vars, prefix);
                try self.emit(", ");
                try genExprWithCapturePrefix(self, b.right.*, captured_vars, prefix);
                try self.emit(")");
            } else {
                try self.emit("(");
                try genExprWithCapturePrefix(self, b.left.*, captured_vars, prefix);
                try self.emit(BinOpStrings.get(@tagName(b.op)) orelse " ? ");
                try genExprWithCapturePrefix(self, b.right.*, captured_vars, prefix);
                try self.emit(")");
            }
        },
        .constant => |c| {
            // Constants don't need capture handling
            const saved_output = self.output;
            self.output = std.ArrayList(u8){};
            try expressions.genConstant(self, c);
            const const_code = try self.output.toOwnedSlice(self.allocator);
            self.output = saved_output;
            try self.emit(const_code);
            self.allocator.free(const_code);
        },
        .call => |c| {
            // Check for self.assertRaises(...) etc - unittest assertion methods on captured self
            if (c.func.* == .attribute) {
                const func_attr = c.func.attribute;
                if (func_attr.value.* == .name) {
                    const base_name = func_attr.value.name.id;
                    // Check if this is a call on captured 'self' variable
                    for (captured_vars) |captured| {
                        if (std.mem.eql(u8, base_name, captured) and std.mem.eql(u8, captured, "self")) {
                            // Check if method is a unittest assertion method
                            if (isUnittestMethod(func_attr.attr)) {
                                // Use existing method dispatch which handles unittest assertions properly
                                // Build call args with captured vars - need to generate these first
                                var temp_args = std.ArrayList(u8){};
                                for (c.args, 0..) |arg, i| {
                                    if (i > 0) try temp_args.writer(self.allocator).writeAll(", ");
                                    // Generate arg to temp buffer
                                    const saved = self.output;
                                    self.output = std.ArrayList(u8){};
                                    try genExprWithCapturePrefix(self, arg, captured_vars, prefix);
                                    const arg_code = try self.output.toOwnedSlice(self.allocator);
                                    self.output = saved;
                                    try temp_args.writer(self.allocator).writeAll(arg_code);
                                    self.allocator.free(arg_code);
                                }
                                // Call the unittest assertion generator via dispatch
                                if (method_calls.UnittestMethods.get(func_attr.attr)) |handler| {
                                    try handler(self, func_attr.value.*, c.args);
                                } else {
                                    // Unknown unittest method - generate as-is
                                    try genExprWithCapturePrefix(self, c.func.*, captured_vars, prefix);
                                    try self.emit("(");
                                    for (c.args, 0..) |arg, i| {
                                        if (i > 0) try self.emit(", ");
                                        try genExprWithCapturePrefix(self, arg, captured_vars, prefix);
                                    }
                                    try self.emit(")");
                                }
                                temp_args.deinit(self.allocator);
                                return;
                            }
                        }
                    }
                }
            }
            try genExprWithCapturePrefix(self, c.func.*, captured_vars, prefix);
            try self.emit("(");
            for (c.args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try genExprWithCapturePrefix(self, arg, captured_vars, prefix);
            }
            try self.emit(")");
        },
        .compare => |cmp| {
            try genExprWithCapturePrefix(self, cmp.left.*, captured_vars, prefix);
            for (cmp.ops, 0..) |op, i| {
                try self.emit(CompOpStrings.get(@tagName(op)) orelse " == ");
                try genExprWithCapturePrefix(self, cmp.comparators[i], captured_vars, prefix);
            }
        },
        .attribute => |attr| {
            // First check if the base is a captured variable (e.g., self.assertRaises)
            if (attr.value.* == .name) {
                const base_name = attr.value.name.id;
                // Check if this is a captured variable
                for (captured_vars) |captured| {
                    if (std.mem.eql(u8, base_name, captured)) {
                        // It's a captured variable - use the provided prefix
                        try self.emit(prefix);
                        try self.emit(".");
                        try self.emit(base_name);
                        try self.emit(".");
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
                        return;
                    }
                }
                // Not captured - treat as module.function reference
                // Use proper module function dispatch with keyword escaping
                try self.emit("runtime.");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), base_name);
                try self.emit(".");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
                return;
            }
            // Handle regular attribute access (e.g., obj.foo) - recurse into value with capture
            try genExprWithCapturePrefix(self, attr.value.*, captured_vars, prefix);
            try self.emit(".");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
        },
        .subscript => |sub| {
            try genExprWithCapturePrefix(self, sub.value.*, captured_vars, prefix);
            try self.emit("[");
            if (sub.slice == .index) {
                try genExprWithCapturePrefix(self, sub.slice.index.*, captured_vars, prefix);
            }
            try self.emit("]");
        },
        else => {
            // For other node types, fall back to regular generation
            try expressions.genExpr(self, node);
        },
    }
}

/// Check if 'self' captured variable is only used for unittest assertion methods
/// In this case, we don't need the closure to actually access self, since we dispatch
/// to runtime.unittest.* functions directly
fn isSelfOnlyForUnittest(body: ast.Node, captured_vars: [][]const u8) bool {
    // Check if self is in captured vars
    var has_self = false;
    for (captured_vars) |v| {
        if (std.mem.eql(u8, v, "self")) {
            has_self = true;
            break;
        }
    }
    if (!has_self) return false;

    // Check if body is a call on self.unittest_method
    if (body == .call) {
        const call = body.call;
        if (call.func.* == .attribute) {
            const attr = call.func.attribute;
            if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                return isUnittestMethod(attr.attr);
            }
        }
    }
    return false;
}

/// Check if a method name is a unittest assertion method
fn isUnittestMethod(method_name: []const u8) bool {
    return method_calls.UnittestMethods.has(method_name);
}

/// Infer return type from lambda body expression
fn inferReturnType(self: *NativeCodegen, body: ast.Node) CodegenError![]const u8 {
    // Check for unittest assertion calls which return void
    if (body == .call) {
        const call = body.call;
        if (call.func.* == .attribute) {
            const attr = call.func.attribute;
            if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                // Check if it's a unittest assertion method
                if (isUnittestMethod(attr.attr)) {
                    return "void";
                }
            }
        }
    }

    const inferred_type = self.type_inferrer.inferExpr(body) catch {
        return "i64";
    };

    return switch (inferred_type) {
        .list => |_| "std.ArrayList(i64)",
        .dict => "hashmap_helper.StringHashMap(i64)",
        else => inferred_type.toSimpleZigType(),
    };
}
