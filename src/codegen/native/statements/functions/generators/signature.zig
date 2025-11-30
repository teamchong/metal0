/// Function and method signature generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const param_analyzer = @import("../param_analyzer.zig");
const self_analyzer = @import("../self_analyzer.zig");
const zig_keywords = @import("zig_keywords");

/// Python type hint to Zig type mapping (comptime optimized)
const TypeHints = std.StaticStringMap([]const u8).initComptime(.{
    .{ "int", "i64" },
    .{ "float", "f64" },
    .{ "bool", "bool" },
    .{ "str", "[]const u8" },
    .{ "list", "anytype" },
});

/// Convert Python type hint to Zig type
pub fn pythonTypeToZig(type_hint: ?[]const u8) []const u8 {
    if (type_hint) |hint| {
        if (TypeHints.get(hint)) |zig_type| return zig_type;
    }
    return "i64"; // Default to i64 instead of anytype (most class fields are integers)
}

/// Import NativeType for pythonTypeToNativeType
const core = @import("../../../../../analysis/native_types/core.zig");
const NativeType = core.NativeType;

/// Check if an expression produces BigInt (for determining parameter types)
fn expressionProducesBigInt(expr: ast.Node) bool {
    switch (expr) {
        .binop => |b| {
            // Large left shift: 1 << N where N >= 63
            if (b.op == .LShift) {
                if (b.right.* == .constant and b.right.constant.value == .int) {
                    if (b.right.constant.value.int >= 63) return true;
                }
            }
            // Large power: N ** M where M >= 20
            if (b.op == .Pow) {
                if (b.right.* == .constant and b.right.constant.value == .int) {
                    if (b.right.constant.value.int >= 20) return true;
                }
            }
            // Arithmetic on BigInt also produces BigInt
            if (expressionProducesBigInt(b.left.*) or expressionProducesBigInt(b.right.*)) {
                return true;
            }
        },
        .unaryop => |u| {
            // Negation of BigInt is BigInt
            return expressionProducesBigInt(u.operand.*);
        },
        else => {},
    }
    return false;
}

/// Check if any call to a method in the class body passes BigInt to a specific parameter index
fn methodReceivesBigIntArg(class_body: []const ast.Node, method_name: []const u8, param_index: usize) bool {
    for (class_body) |stmt| {
        if (checkStmtForBigIntMethodCall(stmt, method_name, param_index)) {
            return true;
        }
    }
    return false;
}

fn checkStmtForBigIntMethodCall(stmt: ast.Node, method_name: []const u8, param_index: usize) bool {
    switch (stmt) {
        .expr_stmt => |e| return checkExprForBigIntMethodCall(e.value.*, method_name, param_index),
        .function_def => |f| {
            for (f.body) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
        },
        .class_def => |c| {
            for (c.body) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
        },
        .for_stmt => |f| {
            for (f.body) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
        },
        .if_stmt => |i| {
            for (i.body) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
            for (i.else_body) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
        },
        .try_stmt => |t| {
            for (t.body) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
        },
        .with_stmt => |w| {
            for (w.body) |s| {
                if (checkStmtForBigIntMethodCall(s, method_name, param_index)) return true;
            }
        },
        else => {},
    }
    return false;
}

fn checkExprForBigIntMethodCall(expr: ast.Node, method_name: []const u8, param_index: usize) bool {
    switch (expr) {
        .call => |c| {
            // Check if this is a call to self.method_name
            if (c.func.* == .attribute) {
                const attr = c.func.attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                    if (std.mem.eql(u8, attr.attr, method_name)) {
                        // Found call to self.method_name - check the argument at param_index
                        if (param_index < c.args.len) {
                            if (expressionProducesBigInt(c.args[param_index])) {
                                return true;
                            }
                        }
                    }
                }
            }
            // Also check arguments recursively
            for (c.args) |arg| {
                if (checkExprForBigIntMethodCall(arg, method_name, param_index)) return true;
            }
        },
        .binop => |b| {
            if (checkExprForBigIntMethodCall(b.left.*, method_name, param_index)) return true;
            if (checkExprForBigIntMethodCall(b.right.*, method_name, param_index)) return true;
        },
        .unaryop => |u| {
            if (checkExprForBigIntMethodCall(u.operand.*, method_name, param_index)) return true;
        },
        else => {},
    }
    return false;
}

/// Convert Python type hint to NativeType (for type inference)
pub fn pythonTypeToNativeType(type_hint: ?[]const u8) NativeType {
    if (type_hint) |hint| {
        if (std.mem.eql(u8, hint, "int")) return .int;
        if (std.mem.eql(u8, hint, "float")) return .float;
        if (std.mem.eql(u8, hint, "bool")) return .bool;
        if (std.mem.eql(u8, hint, "str")) return .{ .string = .runtime };
    }
    return .unknown;
}

/// Check if function returns a lambda (closure)
pub fn returnsLambda(body: []ast.Node) bool {
    for (body) |stmt| {
        if (stmt == .return_stmt) {
            if (stmt.return_stmt.value) |val| {
                if (val.* == .lambda) return true;
            }
        }
        // Check nested statements
        if (stmt == .if_stmt) {
            if (returnsLambda(stmt.if_stmt.body)) return true;
            if (returnsLambda(stmt.if_stmt.else_body)) return true;
        }
        if (stmt == .while_stmt) {
            if (returnsLambda(stmt.while_stmt.body)) return true;
        }
        if (stmt == .for_stmt) {
            if (returnsLambda(stmt.for_stmt.body)) return true;
        }
    }
    return false;
}

/// Check if lambda references 'self' in its body (captures self from method scope)
pub fn lambdaCapturesSelf(lambda_body: ast.Node) bool {
    return switch (lambda_body) {
        .name => |n| std.mem.eql(u8, n.id, "self"),
        .attribute => |attr| lambdaCapturesSelf(attr.value.*),
        .binop => |b| lambdaCapturesSelf(b.left.*) or lambdaCapturesSelf(b.right.*),
        .compare => |cmp| blk: {
            if (lambdaCapturesSelf(cmp.left.*)) break :blk true;
            for (cmp.comparators) |comp| {
                if (lambdaCapturesSelf(comp)) break :blk true;
            }
            break :blk false;
        },
        .call => |c| blk: {
            if (lambdaCapturesSelf(c.func.*)) break :blk true;
            for (c.args) |arg| {
                if (lambdaCapturesSelf(arg)) break :blk true;
            }
            break :blk false;
        },
        .subscript => |sub| blk: {
            if (lambdaCapturesSelf(sub.value.*)) break :blk true;
            if (sub.slice == .index) {
                if (lambdaCapturesSelf(sub.slice.index.*)) break :blk true;
            }
            break :blk false;
        },
        .if_expr => |ie| lambdaCapturesSelf(ie.condition.*) or
            lambdaCapturesSelf(ie.body.*) or lambdaCapturesSelf(ie.orelse_value.*),
        .unaryop => |u| lambdaCapturesSelf(u.operand.*),
        else => false,
    };
}

/// Get returned lambda from method body (for closure type detection)
pub fn getReturnedLambda(body: []ast.Node) ?ast.Node.Lambda {
    for (body) |stmt| {
        if (stmt == .return_stmt) {
            if (stmt.return_stmt.value) |val| {
                if (val.* == .lambda) return val.lambda;
            }
        }
    }
    return null;
}

/// Check if function has a return statement (recursively)
pub fn hasReturnStatement(body: []ast.Node) bool {
    for (body) |stmt| {
        if (stmt == .return_stmt) return true;
        // Check nested statements
        if (stmt == .if_stmt) {
            if (hasReturnStatement(stmt.if_stmt.body)) return true;
            if (hasReturnStatement(stmt.if_stmt.else_body)) return true;
        }
        if (stmt == .while_stmt) {
            if (hasReturnStatement(stmt.while_stmt.body)) return true;
        }
        if (stmt == .for_stmt) {
            if (hasReturnStatement(stmt.for_stmt.body)) return true;
        }
    }
    return false;
}

/// Generate function signature: fn name(params...) return_type {
pub fn genFunctionSignature(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    needs_allocator: bool,
) CodegenError!void {
    // For async functions, generate wrapper that returns a Task
    if (func.is_async) {
        try genAsyncFunctionSignature(self, func, needs_allocator);
        return;
    }

    // Generate function signature: fn name(param: type, ...) return_type {
    // Rename "main" to "__user_main" to avoid conflict with entry point
    try self.emit("fn ");
    if (std.mem.eql(u8, func.name, "main")) {
        try self.emit("__user_main");
    } else {
        // Escape Zig reserved keywords (e.g., "test" -> @"test")
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), func.name);
    }
    try self.emit("(");

    // Add allocator as first parameter if needed
    var param_offset: usize = 0;
    if (needs_allocator) {
        // Check if allocator is actually used in function body
        const allocator_used = param_analyzer.isNameUsedInBody(func.body, "allocator");
        if (!allocator_used) {
            try self.emit("_: std.mem.Allocator");
        } else {
            try self.emit("allocator: std.mem.Allocator");
        }
        param_offset = 1;
        if (func.args.len > 0) {
            try self.emit(", ");
        }
    }

    // Generate parameters
    for (func.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");

        // Check if parameter is used in function body - prefix unused with "_"
        const is_used = param_analyzer.isNameUsedInBody(func.body, arg.name);
        if (!is_used) {
            try self.emit("_");
        }

        // Escape Zig reserved keywords (e.g., "fn" -> @"fn", "test" -> @"test")
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);

        // Parameters with defaults become optional (suffix with '_param')
        if (arg.default != null) {
            try self.emit("_param");
        }
        try self.emit(": ");

        // Check if this parameter is used as a function (called or returned - decorator pattern)
        // For decorators, use anytype to accept any function type
        const is_func = param_analyzer.isParameterUsedAsFunction(func.body, arg.name);
        const is_iter = param_analyzer.isParameterUsedAsIterator(func.body, arg.name);
        if (is_func and arg.default == null) {
            try self.emit("anytype"); // For decorators and higher-order functions (without defaults)
            try self.anytype_params.put(arg.name, {});
        } else if (is_iter and arg.type_annotation == null) {
            // Parameter used as iterator (for x in param:) - use anytype for slice inference
            // Note: ?anytype is not valid in Zig, so we don't add ? prefix for anytype params
            try self.emit("anytype");
            try self.anytype_params.put(arg.name, {});
        } else if (arg.type_annotation) |_| {
            // Use explicit type annotation if provided
            const zig_type = pythonTypeToZig(arg.type_annotation);
            // Make optional if has default value
            if (arg.default != null) {
                try self.emit("?");
            }
            try self.emit(zig_type);
        } else if (self.getVarType(arg.name)) |var_type| {
            // Only use inferred type if it's not .unknown
            const var_type_tag = @as(std.meta.Tag(@TypeOf(var_type)), var_type);
            if (var_type_tag != .unknown) {
                const zig_type = try self.nativeTypeToZigType(var_type);
                defer self.allocator.free(zig_type);
                // Make optional if has default value
                if (arg.default != null) {
                    try self.emit("?");
                }
                try self.emit(zig_type);
            } else {
                // .unknown means we don't know - default to i64
                if (arg.default != null) {
                    try self.emit("?");
                }
                try self.emit("i64");
            }
        } else {
            // No type hint and no inference - default to i64
            if (arg.default != null) {
                try self.emit("?");
            }
            try self.emit("i64");
        }
    }

    // Add *args parameter as a slice if present
    if (func.vararg) |vararg_name| {
        if (func.args.len > 0 or needs_allocator) try self.emit(", ");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), vararg_name);
        try self.emit(": []const i64"); // For now, assume varargs are integers
    }

    // Add **kwargs parameter as a HashMap if present
    if (func.kwarg) |kwarg_name| {
        if (func.args.len > 0 or func.vararg != null or needs_allocator) try self.emit(", ");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), kwarg_name);
        try self.emit(": *runtime.PyObject"); // PyDict wrapped in PyObject
    }

    try self.emit(") ");

    // Determine return type based on type annotation or return statements
    try genReturnType(self, func, needs_allocator);
}

/// Generate async function signature that spawns green threads
fn genAsyncFunctionSignature(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    needs_allocator: bool,
) CodegenError!void {
    _ = needs_allocator; // Async functions always need allocator

    // Rename "main" to "__user_main" to avoid conflict with entry point
    const func_name = if (std.mem.eql(u8, func.name, "main")) "__user_main" else func.name;

    // Generate wrapper function that spawns green thread
    try self.emit("fn ");
    try self.emit(func_name);
    try self.emit("_async(");

    // Generate parameters for wrapper
    for (func.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
        try self.emit(": ");

        if (arg.type_annotation) |_| {
            const zig_type = pythonTypeToZig(arg.type_annotation);
            try self.emit(zig_type);
        } else {
            try self.emit("i64");
        }
    }

    try self.emit(") !*runtime.GreenThread {\n");

    // Use spawn0() for zero-parameter functions, spawn() for functions with parameters
    if (func.args.len == 0) {
        try self.emit("    return try runtime.scheduler.spawn0(");
        try self.emit(func_name);
        try self.emit("_impl);\n");
    } else {
        try self.emit("    return try runtime.scheduler.spawn(");
        try self.emit(func_name);
        try self.emit("_impl, .{");

        // Pass parameters to implementation
        for (func.args, 0..) |arg, i| {
            if (i > 0) try self.emit(", ");
            try self.emit(arg.name);
        }

        try self.emit("});\n");
    }

    try self.emit("}\n\n");

    // Generate implementation function
    try self.emit("fn ");
    try self.emit(func_name);
    try self.emit("_impl(");

    // Generate parameters for implementation
    for (func.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
        try self.emit(": ");

        if (arg.type_annotation) |_| {
            const zig_type = pythonTypeToZig(arg.type_annotation);
            try self.emit(zig_type);
        } else {
            try self.emit("i64");
        }
    }

    try self.emit(") !");

    // Determine return type for implementation
    if (func.return_type) |_| {
        const zig_return_type = pythonTypeToZig(func.return_type);
        try self.emit(zig_return_type);
    } else if (hasReturnStatement(func.body)) {
        try self.emit("i64");
    } else {
        try self.emit("void");
    }

    try self.emit(" {\n");
}

/// Generate return type for function signature
fn genReturnType(self: *NativeCodegen, func: ast.Node.FunctionDef, needs_allocator: bool) CodegenError!void {
    if (func.return_type) |type_hint| {
        // Use explicit return type annotation if provided
        // First try simple type mapping
        const simple_zig_type = pythonTypeToZig(func.return_type);
        const is_simple_type = !std.mem.eql(u8, simple_zig_type, "i64") or
            std.mem.eql(u8, type_hint, "int");

        if (is_simple_type) {
            // Add error union if function needs allocator (allocations can fail)
            if (needs_allocator) {
                try self.emit("!");
            }
            try self.emit(simple_zig_type);
            try self.emit(" {\n");
        } else {
            // Complex type (like tuple[str, str]) - use inferred type from type inferrer
            const inferred_type = self.type_inferrer.func_return_types.get(func.name);
            const return_type_str = if (inferred_type) |inf_type| blk: {
                if (inf_type == .int or inf_type == .unknown) {
                    break :blk "i64";
                }
                break :blk try self.nativeTypeToZigType(inf_type);
            } else "i64";
            defer if (inferred_type != null and inferred_type.? != .int and inferred_type.? != .unknown) {
                self.allocator.free(return_type_str);
            };

            if (needs_allocator) {
                try self.emit("!");
            }
            try self.emit(return_type_str);
            try self.emit(" {\n");
        }
    } else if (hasReturnStatement(func.body)) {
        // Check if this returns a parameter (decorator pattern)
        var returned_param_name: ?[]const u8 = null;
        var returned_param_has_default = false;
        for (func.body) |stmt| {
            if (stmt == .return_stmt) {
                if (stmt.return_stmt.value) |val| {
                    if (val.* == .name) {
                        // Check if returned value is a parameter that's anytype
                        for (func.args) |arg| {
                            if (std.mem.eql(u8, arg.name, val.name.id)) {
                                if (param_analyzer.isParameterUsedAsFunction(func.body, arg.name)) {
                                    returned_param_name = arg.name;
                                    returned_param_has_default = arg.default != null;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }

        // Only use @TypeOf(param) for decorator pattern IF param doesn't have defaults
        // Params with defaults use anytype/?type which breaks @TypeOf inference
        if (returned_param_name != null and !returned_param_has_default) {
            const param_name = returned_param_name.?;
            // Decorator pattern: return @TypeOf(param)
            try self.emit("@TypeOf(");
            try self.emit(param_name);
            try self.emit(") {\n");
        } else {
            // Try to infer return type from func_return_types
            const inferred_type = self.type_inferrer.func_return_types.get(func.name);
            const return_type_str = if (inferred_type) |inf_type| blk: {
                // Don't use .int or .unknown - those are defaults
                if (inf_type == .int or inf_type == .unknown) {
                    break :blk "i64";
                }
                break :blk try self.nativeTypeToZigType(inf_type);
            } else "i64";
            defer if (inferred_type != null and inferred_type.? != .int and inferred_type.? != .unknown) {
                self.allocator.free(return_type_str);
            };

            // Add error union if function needs allocator
            if (needs_allocator) {
                try self.emit("!");
            }
            try self.emit(return_type_str);
            try self.emit(" {\n");
        }
    } else {
        // Functions with allocator but no return still need error union for void
        if (needs_allocator) {
            try self.emit("!void {\n");
        } else {
            try self.emit("void {\n");
        }
    }
}

/// Generate method signature for class methods
pub fn genMethodSignature(
    self: *NativeCodegen,
    class_name: []const u8,
    method: ast.Node.FunctionDef,
    mutates_self: bool,
    needs_allocator: bool,
) CodegenError!void {
    return genMethodSignatureWithSkip(self, class_name, method, mutates_self, needs_allocator, false, true);
}

/// Generate method signature with skip flag for skipped test methods
pub fn genMethodSignatureWithSkip(
    self: *NativeCodegen,
    class_name: []const u8,
    method: ast.Node.FunctionDef,
    mutates_self: bool,
    needs_allocator: bool,
    is_skipped: bool,
    actually_uses_allocator: bool,
) CodegenError!void {
    try self.emit("\n");
    try self.emitIndent();

    // Check if self is actually used in the method body
    // If method is skipped, self is never used since body is replaced with empty stub
    // Also, if this class has captured variables, methods need self to access them
    const class_has_captures = self.current_class_captures != null;
    const uses_self = if (is_skipped) false else (class_has_captures or self_analyzer.usesSelf(method.body));

    // For __new__ methods, the first Python parameter is 'cls' not 'self', and the body often
    // does 'self = super().__new__(cls)' which would shadow a 'self' parameter.
    // Use '_' to avoid shadowing.
    const is_new_method = std.mem.eql(u8, method.name, "__new__");

    // Use *const for methods that don't mutate self (read-only methods)
    // Use _ for self param if it's not actually used in the body, or if it's __new__
    // Use __self for nested classes inside methods to avoid shadowing outer self parameter
    // IMPORTANT: Check uses_self BEFORE checking nesting depth - unused self should be _
    const self_param_name = if (is_new_method or !uses_self) "_" else if (self.method_nesting_depth > 0) "__self" else "self";

    // Generate "pub fn methodname(self_param: *[const] @This()"
    // Use @This() instead of class name to handle nested classes and forward references
    // Escape method name if it's a Zig keyword (e.g., "test" -> @"test")
    try self.emit("pub fn ");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), method.name);
    try self.output.writer(self.allocator).print("({s}: ", .{self_param_name});
    if (mutates_self) {
        try self.emit("*@This()");
    } else {
        try self.emit("*const @This()");
    }

    // Add allocator parameter if method needs it (for error union return type)
    // Use "_" if allocator is not actually used in the body to avoid unused parameter error
    // Use __alloc for nested classes to avoid shadowing outer allocator
    // Note: Check if "allocator" name is literally used in Python source - the allocator param
    // is added by codegen, so if Python code doesn't use it, we should use "_"
    if (needs_allocator) {
        // Check if any code in the method body actually references "allocator" by name
        // (This handles cases where Python code explicitly uses allocator, though rare)
        const allocator_literally_used = param_analyzer.isNameUsedInBody(method.body, "allocator");
        if (actually_uses_allocator and allocator_literally_used) {
            const alloc_name = if (self.class_nesting_depth > 1) "__alloc" else "allocator";
            try self.output.writer(self.allocator).print(", {s}: std.mem.Allocator", .{alloc_name});
        } else {
            try self.emit(", _: std.mem.Allocator");
        }
    }

    // Add other parameters (skip 'self')
    // For skipped methods or unused parameters, use "_:" to suppress unused warnings
    // Get class body for BigInt call site checking
    const class_body: ?[]const ast.Node = if (self.class_registry.getClass(class_name)) |cd| cd.body else null;

    var param_index: usize = 0;
    for (method.args) |arg| {
        if (std.mem.eql(u8, arg.name, "self")) continue;
        defer param_index += 1;

        try self.emit(", ");
        // Check if parameter is used in method body
        const is_param_used = param_analyzer.isNameUsedInBody(method.body, arg.name);
        if (is_skipped or !is_param_used) {
            // Use anonymous parameter for unused
            try self.emit("_: ");
        } else {
            // Use writeParamName to handle Zig keywords AND method shadowing (e.g., "init" -> "init_arg")
            try zig_keywords.writeParamName(self.output.writer(self.allocator), arg.name);
            try self.emit(": ");
        }
        // Use anytype for method params without type annotation to support string literals
        // This lets Zig infer the type from the call site
        // Parameters with defaults become optional (? prefix)

        // Check if any call site passes BigInt to this parameter
        const receives_bigint = if (class_body) |cb|
            methodReceivesBigIntArg(cb, method.name, param_index)
        else
            false;

        if (receives_bigint) {
            // Parameter receives BigInt at some call site - use anytype
            try self.emit("anytype");
        } else if (arg.type_annotation) |_| {
            if (arg.default != null) {
                try self.emit("?");
            }
            const param_type = pythonTypeToZig(arg.type_annotation);
            try self.emit(param_type);
        } else if (self.getVarType(arg.name)) |var_type| {
            // Try inferred type from type inferrer
            const var_type_tag = @as(std.meta.Tag(@TypeOf(var_type)), var_type);
            if (var_type_tag != .unknown) {
                if (arg.default != null) {
                    try self.emit("?");
                }
                const zig_type = try self.nativeTypeToZigType(var_type);
                defer self.allocator.free(zig_type);
                try self.emit(zig_type);
            } else {
                // For anytype, we can't use ? prefix, so use anytype as-is
                // The caller must handle the optionality
                try self.emit("anytype");
            }
        } else {
            try self.emit("anytype");
        }
    }

    // Add *args parameter as a slice if present
    if (method.vararg) |vararg_name| {
        try self.emit(", ");
        const is_vararg_used = param_analyzer.isNameUsedInBody(method.body, vararg_name);
        if (is_skipped or !is_vararg_used) {
            try self.emit("_: anytype"); // Use anonymous for unused
        } else {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), vararg_name);
            try self.emit(": anytype"); // Use anytype for flexibility
        }
    }

    // Add **kwargs parameter if present
    if (method.kwarg) |kwarg_name| {
        try self.emit(", ");
        const is_kwarg_used = param_analyzer.isNameUsedInBody(method.body, kwarg_name);
        if (is_skipped or !is_kwarg_used) {
            try self.emit("_: anytype"); // Use anonymous for unused
        } else {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), kwarg_name);
            try self.emit(": anytype");
        }
    }

    try self.emit(") ");

    // Determine return type (add error union if allocator needed)
    if (needs_allocator) {
        try self.emit("!");
    }
    if (method.return_type) |type_hint| {
        // Use explicit return type annotation if provided
        // If return type is class name, use @This() instead for self-reference
        if (std.mem.eql(u8, type_hint, class_name)) {
            try self.emit("@This()");
        } else {
            const zig_return_type = pythonTypeToZig(method.return_type);
            try self.emit(zig_return_type);
        }
    } else if (hasReturnStatement(method.body)) {
        // Check if method returns a lambda that captures self (closure)
        if (getReturnedLambda(method.body)) |lambda| {
            if (lambdaCapturesSelf(lambda.body.*)) {
                // Method returns a closure - use closure type name
                // The closure will be generated with current lambda_counter value
                const closure_type = try std.fmt.allocPrint(
                    self.allocator,
                    "__Closure_{d}",
                    .{self.lambda_counter},
                );
                defer self.allocator.free(closure_type);
                try self.emit(closure_type);
                try self.emit(" {\n");
                return;
            }
        }

        // Check if method returns a parameter directly (for anytype params)
        var returned_param_name: ?[]const u8 = null;
        for (method.body) |stmt| {
            if (stmt == .return_stmt) {
                if (stmt.return_stmt.value) |val| {
                    if (val.* == .name) {
                        // Check if returned value is a parameter (not 'self')
                        for (method.args) |arg| {
                            if (!std.mem.eql(u8, arg.name, "self") and
                                std.mem.eql(u8, arg.name, val.name.id) and
                                arg.type_annotation == null)
                            {
                                returned_param_name = arg.name;
                                break;
                            }
                        }
                    }
                }
            }
        }

        if (returned_param_name) |param_name| {
            // Method returns an anytype param - use @TypeOf(param)
            // Use writeParamName to handle renamed params (e.g., init -> init_arg)
            try self.emit("@TypeOf(");
            try zig_keywords.writeParamName(self.output.writer(self.allocator), param_name);
            try self.emit(")");
        } else {
            // Try to get inferred return type from class_fields.methods
            const class_info = self.type_inferrer.class_fields.get(class_name);
            const inferred_type = if (class_info) |info| info.methods.get(method.name) else null;

            if (inferred_type) |inf_type| {
                // Use inferred type (skip if .int or .unknown - those are defaults)
                if (inf_type != .int and inf_type != .unknown) {
                    const return_type_str = try self.nativeTypeToZigType(inf_type);
                    defer self.allocator.free(return_type_str);
                    // If return type matches class name, use @This() for self-reference
                    if (std.mem.eql(u8, return_type_str, class_name)) {
                        try self.emit("@This()");
                    } else {
                        try self.emit(return_type_str);
                    }
                } else {
                    try self.emit("i64");
                }
            } else {
                try self.emit("i64");
            }
        }
    } else {
        try self.emit("void");
    }

    try self.emit(" {\n");
}
