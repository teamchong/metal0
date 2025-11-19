/// Function and class definition code generation
const std = @import("std");
const ast = @import("../../../../ast.zig");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const DecoratedFunction = @import("../../main.zig").DecoratedFunction;
const CodegenError = @import("../../main.zig").CodegenError;
const CodeBuilder = @import("../../code_builder.zig").CodeBuilder;
const self_analyzer = @import("self_analyzer.zig");
const param_analyzer = @import("param_analyzer.zig");

/// Check if function returns a lambda (closure)
fn returnsLambda(body: []ast.Node) bool {
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
fn hasReturnStatement(body: []ast.Node) bool {
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

/// Convert Python type hint to Zig type
fn pythonTypeToZig(type_hint: ?[]const u8) []const u8 {
    if (type_hint) |hint| {
        if (std.mem.eql(u8, hint, "int")) return "i64";
        if (std.mem.eql(u8, hint, "float")) return "f64";
        if (std.mem.eql(u8, hint, "bool")) return "bool";
        if (std.mem.eql(u8, hint, "str")) return "[]const u8";
        if (std.mem.eql(u8, hint, "list")) return "anytype";
    }
    return "i64"; // Default to i64 instead of anytype (most class fields are integers)
}

/// Generate function definition
pub fn genFunctionDef(self: *NativeCodegen, func: ast.Node.FunctionDef) CodegenError!void {
    // Generate function signature: fn name(param: type, ...) return_type {
    try self.emit("fn ");
    try self.emit(func.name);
    try self.emit("(");

    // Generate parameters
    for (func.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try self.emit(arg.name);
        try self.emit(": ");

        // Check if this parameter is used as a function (called or returned - decorator pattern)
        // For decorators, use anytype to accept any function type
        const is_func = param_analyzer.isParameterUsedAsFunction(func.body, arg.name);
        if (is_func) {
            try self.emit("anytype"); // For decorators and higher-order functions
        } else if (arg.type_annotation) |_| {
            // Use explicit type annotation if provided
            const zig_type = pythonTypeToZig(arg.type_annotation);
            try self.emit(zig_type);
        } else if (self.getVarType(arg.name)) |var_type| {
            // Only use inferred type if it's not .unknown
            const var_type_tag = @as(std.meta.Tag(@TypeOf(var_type)), var_type);
            if (var_type_tag != .unknown) {
                const zig_type = try self.nativeTypeToZigType(var_type);
                defer self.allocator.free(zig_type);
                try self.emit(zig_type);
            } else {
                // .unknown means we don't know - default to i64
                try self.emit("i64");
            }
        } else {
            // No type hint and no inference - default to i64
            try self.emit("i64");
        }
    }

    try self.emit(") ");

    // Determine return type based on type annotation or return statements
    if (func.return_type) |_| {
        // Use explicit return type annotation if provided
        const zig_return_type = pythonTypeToZig(func.return_type);
        try self.emit(zig_return_type);
        try self.emit(" {\n");
    } else if (hasReturnStatement(func.body)) {
        // Check if this returns a parameter (decorator pattern)
        var returned_param_name: ?[]const u8 = null;
        for (func.body) |stmt| {
            if (stmt == .return_stmt) {
                if (stmt.return_stmt.value) |val| {
                    if (val.* == .name) {
                        // Check if returned value is a parameter that's anytype
                        for (func.args) |arg| {
                            if (std.mem.eql(u8, arg.name, val.name.id)) {
                                if (param_analyzer.isParameterUsedAsFunction(func.body, arg.name)) {
                                    returned_param_name = arg.name;
                                    break;
                                }
                            }
                        }
                    }
                }
            }
        }

        if (returned_param_name) |param_name| {
            // Decorator pattern: return @TypeOf(param)
            try self.emit("@TypeOf(");
            try self.emit(param_name);
            try self.emit(") {\n");
        } else {
            try self.emit("i64 {\n"); // Default return type
        }
    } else {
        try self.emit("void {\n");
    }

    self.indent();

    // Push new scope for function body
    try self.pushScope();

    // Declare function parameters in the scope so closures can capture them
    for (func.args) |arg| {
        try self.declareVar(arg.name);
    }

    // Generate function body
    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting function
    self.popScope();

    var builder = CodeBuilder.init(self);
    _ = try builder.endBlock();

    // Register decorated functions for application in main()
    if (func.decorators.len > 0) {
        const decorated_func = DecoratedFunction{
            .name = func.name,
            .decorators = func.decorators,
        };
        try self.decorated_functions.append(self.allocator, decorated_func);
    }
}

/// Check if a method mutates self (assigns to self.field)
fn methodMutatesSelf(method: ast.Node.FunctionDef) bool {
    for (method.body) |stmt| {
        if (stmt == .assign) {
            for (stmt.assign.targets) |target| {
                if (target == .attribute) {
                    const attr = target.attribute;
                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                        return true; // Assigns to self.field
                    }
                }
            }
        }
    }
    return false;
}

/// Generate class definition with __init__ constructor
pub fn genClassDef(self: *NativeCodegen, class: ast.Node.ClassDef) CodegenError!void {
    // Find __init__ method to determine struct fields
    var init_method: ?ast.Node.FunctionDef = null;
    for (class.body) |stmt| {
        if (stmt == .function_def and std.mem.eql(u8, stmt.function_def.name, "__init__")) {
            init_method = stmt.function_def;
            break;
        }
    }

    // Check for base classes - we support single inheritance
    var parent_class: ?ast.Node.ClassDef = null;
    if (class.bases.len > 0) {
        // Look up parent class in registry (populated in Phase 2 of generate())
        // Order doesn't matter - all classes are registered before code generation
        parent_class = self.class_registry.getClass(class.bases[0]);
    }

    // Generate: const ClassName = struct {
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{class.name});
    self.indent();

    // Extract fields from __init__ body (self.x = ...)
    // We map field assignments to parameter types
    if (init_method) |init| {
        for (init.body) |stmt| {
            if (stmt == .assign) {
                const assign = stmt.assign;
                // Check if target is self.attribute
                if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                    const attr = assign.targets[0].attribute;
                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                        // Found field: self.x = y
                        const field_name = attr.attr;

                        // Determine field type
                        // If value is a parameter name, use parameter's type annotation
                        var field_type_str: []const u8 = "i64"; // default
                        if (assign.value.* == .name) {
                            const value_name = assign.value.name.id;
                            // Look up parameter type
                            for (init.args) |arg| {
                                if (std.mem.eql(u8, arg.name, value_name)) {
                                    field_type_str = pythonTypeToZig(arg.type_annotation);
                                    break;
                                }
                            }
                        } else {
                            // For non-parameter values, try to infer
                            const inferred = try self.type_inferrer.inferExpr(assign.value.*);
                            field_type_str = switch (inferred) {
                                .int => "i64",
                                .float => "f64",
                                .bool => "bool",
                                .string => "[]const u8",
                                else => "i64",
                            };
                        }

                        try self.emitIndent();
                        try self.output.writer(self.allocator).print("{s}: {s},\n", .{ field_name, field_type_str });
                    }
                }
            }
        }
    }

    // Generate init() method from __init__
    if (init_method) |init| {
        try self.output.appendSlice(self.allocator, "\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("pub fn init(allocator: std.mem.Allocator", .{});

        // Parameters (skip 'self')
        for (init.args) |arg| {
            if (std.mem.eql(u8, arg.name, "self")) continue;

            try self.output.appendSlice(self.allocator, ", ");

            try self.output.writer(self.allocator).print("{s}: ", .{arg.name});

            // Type annotation
            const param_type = pythonTypeToZig(arg.type_annotation);
            try self.output.appendSlice(self.allocator, param_type);
        }

        try self.output.writer(self.allocator).print(") {s} {{\n", .{class.name});
        self.indent();

        // Mark allocator as potentially unused (suppress Zig warning)
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "_ = allocator;\n");

        // Generate return statement with field initializers
        try self.emitIndent();
        try self.output.writer(self.allocator).print("return {s}{{\n", .{class.name});
        self.indent();

        // Extract field assignments from __init__ body
        for (init.body) |stmt| {
            if (stmt == .assign) {
                const assign = stmt.assign;
                if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                    const attr = assign.targets[0].attribute;
                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                        const field_name = attr.attr;

                        try self.emitIndent();
                        try self.output.writer(self.allocator).print(".{s} = ", .{field_name});
                        try self.genExpr(assign.value.*);
                        try self.output.appendSlice(self.allocator, ",\n");
                    }
                }
            }
        }

        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "};\n");

        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
    }

    // Build list of child method names for override detection
    var child_method_names = std.ArrayList([]const u8){};
    defer child_method_names.deinit(self.allocator);
    for (class.body) |stmt| {
        if (stmt == .function_def) {
            try child_method_names.append(self.allocator, stmt.function_def.name);
        }
    }

    // Generate regular methods (non-__init__)
    for (class.body) |stmt| {
        if (stmt == .function_def) {
            const method = stmt.function_def;
            if (std.mem.eql(u8, method.name, "__init__")) continue;

            try self.output.appendSlice(self.allocator, "\n");
            try self.emitIndent();
            // Use *const for methods that don't mutate self (read-only methods)
            const mutates_self = methodMutatesSelf(method);
            if (mutates_self) {
                try self.output.writer(self.allocator).print("pub fn {s}(self: *", .{method.name});
            } else {
                try self.output.writer(self.allocator).print("pub fn {s}(self: *const ", .{method.name});
            }
            try self.output.appendSlice(self.allocator, class.name);

            // Add other parameters (skip 'self')
            for (method.args) |arg| {
                if (std.mem.eql(u8, arg.name, "self")) continue;
                try self.output.appendSlice(self.allocator, ", ");
                try self.output.writer(self.allocator).print("{s}: ", .{arg.name});
                const param_type = pythonTypeToZig(arg.type_annotation);
                try self.output.appendSlice(self.allocator, param_type);
            }

            try self.output.appendSlice(self.allocator, ") ");

            // Determine return type
            if (method.return_type) |_| {
                // Use explicit return type annotation if provided
                const zig_return_type = pythonTypeToZig(method.return_type);
                try self.output.appendSlice(self.allocator, zig_return_type);
            } else if (hasReturnStatement(method.body)) {
                try self.output.appendSlice(self.allocator, "i64");
            } else {
                try self.output.appendSlice(self.allocator, "void");
            }

            try self.output.appendSlice(self.allocator, " {\n");
            self.indent();

            // Mark self as intentionally unused if not used in method body
            if (!self_analyzer.usesSelf(method.body)) {
                try self.emitIndent();
                try self.output.appendSlice(self.allocator, "_ = self;\n");
            }

            // Push new scope for method body
            try self.pushScope();

            // Generate method body
            for (method.body) |method_stmt| {
                try self.generateStmt(method_stmt);
            }

            // Pop scope when exiting method
            self.popScope();

            self.dedent();
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "}\n");
        }
    }

    // Inherit parent methods that aren't overridden
    if (parent_class) |parent| {
        for (parent.body) |parent_stmt| {
            if (parent_stmt == .function_def) {
                const parent_method = parent_stmt.function_def;
                if (std.mem.eql(u8, parent_method.name, "__init__")) continue;

                // Check if child overrides this method
                var is_overridden = false;
                for (child_method_names.items) |child_name| {
                    if (std.mem.eql(u8, child_name, parent_method.name)) {
                        is_overridden = true;
                        break;
                    }
                }

                if (!is_overridden) {
                    // Copy parent method to child class
                    try self.output.appendSlice(self.allocator, "\n");
                    try self.emitIndent();
                    // Use *const for methods that don't mutate self
                    const mutates_self = methodMutatesSelf(parent_method);
                    if (mutates_self) {
                        try self.output.writer(self.allocator).print("pub fn {s}(self: *", .{parent_method.name});
                    } else {
                        try self.output.writer(self.allocator).print("pub fn {s}(self: *const ", .{parent_method.name});
                    }
                    try self.output.appendSlice(self.allocator, class.name);

                    // Add other parameters (skip 'self')
                    for (parent_method.args) |arg| {
                        if (std.mem.eql(u8, arg.name, "self")) continue;
                        try self.output.appendSlice(self.allocator, ", ");
                        try self.output.writer(self.allocator).print("{s}: ", .{arg.name});
                        const param_type = pythonTypeToZig(arg.type_annotation);
                        try self.output.appendSlice(self.allocator, param_type);
                    }

                    try self.output.appendSlice(self.allocator, ") ");

                    // Determine return type
                    if (parent_method.return_type) |_| {
                        // Use explicit return type annotation if provided
                        const zig_return_type = pythonTypeToZig(parent_method.return_type);
                        try self.output.appendSlice(self.allocator, zig_return_type);
                    } else if (hasReturnStatement(parent_method.body)) {
                        try self.output.appendSlice(self.allocator, "i64");
                    } else {
                        try self.output.appendSlice(self.allocator, "void");
                    }

                    try self.output.appendSlice(self.allocator, " {\n");
                    self.indent();

                    // Mark self as intentionally unused if not used in method body
                    if (!self_analyzer.usesSelf(parent_method.body)) {
                        try self.emitIndent();
                        try self.output.appendSlice(self.allocator, "_ = self;\n");
                    }

                    // Push new scope for method body
                    try self.pushScope();

                    // Generate method body
                    for (parent_method.body) |method_stmt| {
                        try self.generateStmt(method_stmt);
                    }

                    // Pop scope when exiting method
                    self.popScope();

                    self.dedent();
                    try self.emitIndent();
                    try self.output.appendSlice(self.allocator, "}\n");
                }
            }
        }
    }

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "};\n");
}
