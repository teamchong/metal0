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

/// Magic method return types - these have fixed return types in Python
/// regardless of what the method body might suggest
const MagicMethodReturnTypes = std.StaticStringMap([]const u8).initComptime(.{
    .{ "__bool__", "runtime.PythonError!bool" },  // Must return bool or error
    .{ "__len__", "runtime.PythonError!i64" },  // Must return non-negative int or error
    .{ "__hash__", "i64" },
    .{ "__repr__", "[]const u8" },
    .{ "__str__", "[]const u8" },
    .{ "__bytes__", "[]const u8" },
    .{ "__format__", "[]const u8" },
    .{ "__int__", "i64" },
    .{ "__float__", "f64" },
    .{ "__index__", "i64" },
    .{ "__sizeof__", "i64" },
    .{ "__contains__", "bool" },
    .{ "__eq__", "bool" },
    .{ "__ne__", "bool" },
    .{ "__lt__", "bool" },
    .{ "__le__", "bool" },
    .{ "__gt__", "bool" },
    .{ "__ge__", "bool" },
    // __new__ should return the class instance type, but in Zig we can't determine
    // the type at compile time, especially for metaclasses. Default to i64.
    .{ "__new__", "i64" },
});

/// Get the fixed return type for a magic method, or null if not a special method
pub fn getMagicMethodReturnType(method_name: []const u8) ?[]const u8 {
    return MagicMethodReturnTypes.get(method_name);
}

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
        if (std.mem.eql(u8, hint, "int")) return .{ .int = .bounded };
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

/// Check if function returns a nested function (closure by name)
/// Returns the name of the nested function if found, null otherwise
pub fn getReturnedNestedFuncName(body: []ast.Node) ?[]const u8 {
    // First, collect all nested function names defined in this body
    var nested_funcs: [32][]const u8 = undefined;
    var nested_count: usize = 0;

    for (body) |stmt| {
        if (stmt == .function_def) {
            if (nested_count < nested_funcs.len) {
                nested_funcs[nested_count] = stmt.function_def.name;
                nested_count += 1;
            }
        }
    }

    if (nested_count == 0) return null;

    // Now check if any return statement returns one of these names
    for (body) |stmt| {
        if (stmt == .return_stmt) {
            if (stmt.return_stmt.value) |val| {
                if (val.* == .name) {
                    for (nested_funcs[0..nested_count]) |func_name| {
                        if (std.mem.eql(u8, val.name.id, func_name)) {
                            return func_name;
                        }
                    }
                }
            }
        }
        // Check nested statements
        if (stmt == .if_stmt) {
            if (getReturnedNestedFuncName(stmt.if_stmt.body)) |name| return name;
            if (getReturnedNestedFuncName(stmt.if_stmt.else_body)) |name| return name;
        }
        if (stmt == .while_stmt) {
            if (getReturnedNestedFuncName(stmt.while_stmt.body)) |name| return name;
        }
        if (stmt == .for_stmt) {
            if (getReturnedNestedFuncName(stmt.for_stmt.body)) |name| return name;
        }
    }
    return null;
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
        // Also check if parameter is captured by any nested class (used via closure)
        const is_used_directly = param_analyzer.isNameUsedInBody(func.body, arg.name);
        const is_captured = self.isVarCapturedByAnyNestedClass(arg.name);
        const is_used = is_used_directly or is_captured;
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

    // For functions with parameters, generate a context struct first
    if (func.args.len > 0) {
        try self.emit("const ");
        try self.emit(func_name);
        try self.emit("_Context = struct {\n");
        for (func.args) |arg| {
            try self.emit("    ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
            try self.emit(": ");
            if (arg.type_annotation) |_| {
                const zig_type = pythonTypeToZig(arg.type_annotation);
                try self.emit(zig_type);
            } else {
                try self.emit("i64");
            }
            try self.emit(",\n");
        }
        try self.emit("};\n\n");
    }

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

        // Pass parameters as struct fields
        for (func.args, 0..) |arg, i| {
            if (i > 0) try self.emit(", ");
            try self.emit(".");
            try self.emit(arg.name);
            try self.emit(" = ");
            try self.emit(arg.name);
        }

        try self.emit("});\n");
    }

    try self.emit("}\n\n");

    // Generate implementation function
    try self.emit("fn ");
    try self.emit(func_name);
    try self.emit("_impl(");

    // For functions with parameters, take pointer to context struct
    if (func.args.len > 0) {
        try self.emit("ctx: *");
        try self.emit(func_name);
        try self.emit("_Context");
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

    // Unpack context fields into local variables
    if (func.args.len > 0) {
        for (func.args) |arg| {
            try self.emit("    const ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
            try self.emit(" = ctx.");
            try self.emit(arg.name);
            try self.emit(";\n");
        }
    }
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
                const inf_tag = @as(std.meta.Tag(NativeType), inf_type);
                // For int types, use toSimpleZigType which checks IntKind for bounded/unbounded
                if (inf_tag == .int) {
                    break :blk inf_type.toSimpleZigType();
                }
                if (inf_tag == .unknown) {
                    break :blk "i64";
                }
                break :blk try self.nativeTypeToZigType(inf_type);
            } else "i64";
            const inf_tag = if (inferred_type) |t| @as(std.meta.Tag(NativeType), t) else null;
            defer if (inf_tag != null and inf_tag.? != .int and inf_tag.? != .unknown) {
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
        } else if (getReturnedNestedFuncName(func.body)) |nested_func_name| {
            // Function returns a nested function (closure factory pattern)
            // The closure wrapper struct must be pre-declared at module level
            // Check if we have a pre-declared closure type for this
            const closure_type_name = self.pending_closure_types.get(nested_func_name);
            if (closure_type_name) |type_name| {
                if (needs_allocator) {
                    try self.emit("!");
                }
                try self.emit(type_name);
                try self.emit(" {\n");
            } else {
                // No pre-declared type - fallback to i64 (will cause type error if actually returned)
                if (needs_allocator) {
                    try self.emit("!");
                }
                try self.emit("i64 {\n");
            }
        } else {
            // Try to infer return type from func_return_types
            const inferred_type = self.type_inferrer.func_return_types.get(func.name);
            const return_type_str = if (inferred_type) |inf_type| blk: {
                const inf_tag = @as(std.meta.Tag(NativeType), inf_type);
                // For int types, use toSimpleZigType which checks IntKind for bounded/unbounded
                if (inf_tag == .int) {
                    break :blk inf_type.toSimpleZigType();
                }
                if (inf_tag == .unknown) {
                    break :blk "i64";
                }
                break :blk try self.nativeTypeToZigType(inf_type);
            } else "i64";
            const inf_tag2 = if (inferred_type) |t| @as(std.meta.Tag(NativeType), t) else null;
            defer if (inf_tag2 != null and inf_tag2.? != .int and inf_tag2.? != .unknown) {
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
    // Also, if this class has captured variables and the method actually uses them, self is needed
    // Check if class has a known parent - if not, super() calls compile to no-ops and don't use self
    const has_known_parent = self.getParentClassName(class_name) != null;
    // Check if method body uses any captured variables (they're accessed via self.__captured_*)
    const method_uses_captures = if (self.current_class_captures) |captures| blk: {
        for (captures) |var_name| {
            if (param_analyzer.isNameUsedInBody(method.body, var_name)) {
                break :blk true;
            }
        }
        break :blk false;
    } else false;
    // Also check if the first parameter is used when it's NOT named "self"
    // This handles methods like def foo(test_self): test_self.assertEqual(...)
    // For params named "self", usesSelfWithContext handles it properly
    // IMPORTANT: Use isFirstParamUsedNonUnittest to exclude unittest method calls
    // which get dispatched to runtime.unittest.* and don't actually use the Zig self param
    const first_param_name = if (method.args.len > 0) method.args[0].name else null;
    const first_param_is_non_self = if (first_param_name) |name|
        !std.mem.eql(u8, name, "self")
    else
        false;
    const first_param_used = if (first_param_is_non_self)
        param_analyzer.isFirstParamUsedNonUnittest(method.body, first_param_name.?)
    else
        false;
    const uses_self = if (is_skipped) false else (method_uses_captures or first_param_used or self_analyzer.usesSelfWithContext(method.body, has_known_parent));

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
            const is_nested = self.nested_class_names.contains(class_name);
            const alloc_name = if (is_nested) "__alloc" else "allocator";
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
    var is_first_param = true;
    for (method.args) |arg| {
        // Skip the first parameter (self/cls/etc.) - in Python methods, first param is always the instance
        if (is_first_param) {
            is_first_param = false;
            continue;
        }
        defer param_index += 1;

        try self.emit(", ");
        // Check if parameter is used in method body
        // For __init__ and __new__ methods, exclude parent calls (they're skipped in codegen)
        const is_init_or_new = std.mem.eql(u8, method.name, "__init__") or std.mem.eql(u8, method.name, "__new__");

        // In __new__ methods, 'cls' is never used in Zig (we don't use class references)
        // The generated code returns the value directly, not cls()
        const is_cls_in_new = is_new_method and std.mem.eql(u8, arg.name, "cls");

        const is_param_used = if (is_cls_in_new)
            false // cls is never used in __new__ - we return value directly
        else if (is_init_or_new)
            param_analyzer.isNameUsedInInitBody(method.body, arg.name)
        else
            param_analyzer.isNameUsedInBody(method.body, arg.name);
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
                // Check for class_instance type - if the class isn't in the registry,
                // it's probably a locally-defined class inside the function and we can't
                // use it as a parameter type (it would be undefined at function signature scope)
                if (var_type_tag == .class_instance) {
                    const inferred_class_name = var_type.class_instance;
                    if (!self.class_registry.classes.contains(inferred_class_name)) {
                        // Class not in registry - use anytype instead
                        try self.emit("anytype");
                    } else {
                        if (arg.default != null) {
                            try self.emit("?");
                        }
                        const zig_type = try self.nativeTypeToZigType(var_type);
                        defer self.allocator.free(zig_type);
                        try self.emit(zig_type);
                    }
                } else {
                    if (arg.default != null) {
                        try self.emit("?");
                    }
                    const zig_type = try self.nativeTypeToZigType(var_type);
                    defer self.allocator.free(zig_type);
                    try self.emit(zig_type);
                }
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
    } else if (getMagicMethodReturnType(method.name)) |magic_return_type| {
        // Special dunder methods have fixed return types regardless of inference
        try self.emit(magic_return_type);
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

        // Check if method returns 'self' - for nested classes this should be pointer type
        const returns_self = blk: {
            for (method.body) |stmt| {
                if (stmt == .return_stmt) {
                    if (stmt.return_stmt.value) |val| {
                        if (val.* == .name and std.mem.eql(u8, val.name.id, "self")) {
                            break :blk true;
                        }
                    }
                }
            }
            break :blk false;
        };

        if (returns_self) {
            // For nested classes, self is a pointer, so returning self returns a pointer
            const current_class_is_nested = self.nested_class_names.contains(class_name);
            if (current_class_is_nested) {
                try self.emit("*@This() {\n");
                return;
            }
            // Top-level classes return value type
            try self.emit("@This() {\n");
            return;
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
            // First, check if method returns a constructor call to a nested class
            // This handles inherited methods like aug_test.__add__ returning aug_test(...)
            const returned_class = getReturnedNestedClassConstructor(method.body, self);
            if (returned_class) |rc| {
                // Nested classes are heap-allocated and return pointers
                // Check if the returned class OR the current class is nested
                const current_class_is_nested = self.nested_class_names.contains(class_name);
                const is_nested = self.nested_class_names.contains(rc) or current_class_is_nested;
                if (is_nested) {
                    try self.emit("*");
                }
                // If returning same class, use @This() for self-reference
                if (std.mem.eql(u8, rc, class_name)) {
                    try self.emit("@This()");
                } else {
                    try self.emit(rc);
                }
                try self.emit(" {\n");
                return;
            }

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
                        // Check if the return type is a known class or a safe Zig type
                        // Avoid using unknown names (like captured variables) as types
                        const is_known_type = blk: {
                            // Check known Zig primitive types
                            const known_types = [_][]const u8{
                                "i64", "i32", "i8", "u8", "u16", "u32", "u64", "usize", "isize",
                                "bool", "void", "f32", "f64", "[]const u8", "[]u8",
                                "*runtime.PyObject", "@This()", "anytype",
                            };
                            for (known_types) |known| {
                                if (std.mem.eql(u8, return_type_str, known)) break :blk true;
                            }
                            // Check if it's a known class from type inference
                            if (self.type_inferrer.class_fields.contains(return_type_str)) break :blk true;
                            // Check if it's a nested class in current scope
                            if (self.nested_class_names.contains(return_type_str)) break :blk true;
                            break :blk false;
                        };
                        if (is_known_type) {
                            try self.emit(return_type_str);
                        } else {
                            // Unknown type (likely a captured variable) - use i64 as safe default
                            try self.emit("i64");
                        }
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


/// Check if method returns a constructor call to a nested class
/// Returns the class name if found, null otherwise
fn getReturnedNestedClassConstructor(body: []const ast.Node, self: *NativeCodegen) ?[]const u8 {
    for (body) |stmt| {
        if (stmt == .return_stmt) {
            if (stmt.return_stmt.value) |val| {
                if (val.* == .call) {
                    const call = val.call;
                    if (call.func.* == .name) {
                        const func_name = call.func.name.id;
                        // Check if this is a nested class constructor
                        if (self.nested_class_names.contains(func_name)) {
                            return func_name;
                        }
                        // Also check if this is the current class being generated
                        if (self.current_class_name) |ccn| {
                            if (std.mem.eql(u8, func_name, ccn)) {
                                return func_name;
                            }
                        }
                    }
                }
            }
        }
    }
    return null;
}
