/// Function and method signature generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const param_analyzer = @import("../param_analyzer.zig");
const allocator_analyzer = @import("../allocator_analyzer.zig");
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
            if (arg.default != null) {
                try self.emit("?");
            }
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
    try self.emit("\n");
    try self.emitIndent();

    // Check if self is actually used in the method body
    const uses_self = self_analyzer.usesSelf(method.body);

    // For __new__ methods, the first Python parameter is 'cls' not 'self', and the body often
    // does 'self = super().__new__(cls)' which would shadow a 'self' parameter.
    // Use '_' to avoid shadowing.
    const is_new_method = std.mem.eql(u8, method.name, "__new__");

    // Use *const for methods that don't mutate self (read-only methods)
    // Use _ for self param if it's not actually used in the body, or if it's __new__
    const self_param_name = if (is_new_method) "_" else if (uses_self) "self" else "_";

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

    // Add allocator parameter if method needs it
    // Use _ if allocator is needed for return type but not actually used in body
    if (needs_allocator) {
        const actually_uses = allocator_analyzer.functionActuallyUsesAllocatorParam(method);
        if (actually_uses) {
            try self.emit(", allocator: std.mem.Allocator");
        } else {
            try self.emit(", _: std.mem.Allocator");
        }
    }

    // Add other parameters (skip 'self')
    for (method.args) |arg| {
        if (std.mem.eql(u8, arg.name, "self")) continue;
        try self.emit(", ");
        // Use writeParamName to handle Zig keywords AND method shadowing (e.g., "init" -> "init_arg")
        try zig_keywords.writeParamName(self.output.writer(self.allocator), arg.name);
        try self.emit(": ");
        // Use anytype for method params without type annotation to support string literals
        // This lets Zig infer the type from the call site
        if (arg.type_annotation) |_| {
            const param_type = pythonTypeToZig(arg.type_annotation);
            try self.emit(param_type);
        } else if (self.getVarType(arg.name)) |var_type| {
            // Try inferred type from type inferrer
            const var_type_tag = @as(std.meta.Tag(@TypeOf(var_type)), var_type);
            if (var_type_tag != .unknown) {
                const zig_type = try self.nativeTypeToZigType(var_type);
                defer self.allocator.free(zig_type);
                try self.emit(zig_type);
            } else {
                try self.emit("anytype");
            }
        } else {
            try self.emit("anytype");
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
