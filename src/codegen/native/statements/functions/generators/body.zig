/// Function and class body generation
const std = @import("std");
const ast = @import("../../../../../ast.zig");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const CodeBuilder = @import("../../../code_builder.zig").CodeBuilder;
const self_analyzer = @import("../self_analyzer.zig");
const signature = @import("signature.zig");
const hashmap_helper = @import("../../../../../utils/hashmap_helper.zig");

/// Check if a method mutates self (assigns to self.field)
pub fn methodMutatesSelf(method: ast.Node.FunctionDef) bool {
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

/// Analyze function body for mutated variables (variables assigned more than once)
fn analyzeFunctionLocalMutations(self: *NativeCodegen, func: ast.Node.FunctionDef) !void {
    // Track how many times each variable is assigned
    var assign_counts = hashmap_helper.StringHashMap(usize).init(self.allocator);
    defer assign_counts.deinit();

    // Count assignments in the function body
    for (func.body) |stmt| {
        try countAssignmentsInStmt(&assign_counts, stmt, self.allocator);
    }

    // Variables assigned more than once are mutated
    var iter = assign_counts.iterator();
    while (iter.next()) |entry| {
        if (entry.value_ptr.* > 1) {
            try self.func_local_mutations.put(entry.key_ptr.*, {});
        }
    }
}

/// Count assignments in a statement (recursive)
fn countAssignmentsInStmt(counts: *hashmap_helper.StringHashMap(usize), stmt: ast.Node, allocator: std.mem.Allocator) !void {
    switch (stmt) {
        .assign => |assign| {
            for (assign.targets) |target| {
                if (target == .name) {
                    const name = target.name.id;
                    const current = counts.get(name) orelse 0;
                    try counts.put(name, current + 1);
                }
            }
        },
        .aug_assign => |aug| {
            // Augmented assignment (+=, -=, etc.) counts as a mutation
            if (aug.target.* == .name) {
                const name = aug.target.name.id;
                const current = counts.get(name) orelse 0;
                // Count as 2 (initial + mutation) to ensure it's marked as mutated
                try counts.put(name, current + 2);
            }
        },
        .if_stmt => |if_stmt| {
            for (if_stmt.body) |body_stmt| {
                try countAssignmentsInStmt(counts, body_stmt, allocator);
            }
            for (if_stmt.else_body) |else_stmt| {
                try countAssignmentsInStmt(counts, else_stmt, allocator);
            }
        },
        .while_stmt => |while_stmt| {
            for (while_stmt.body) |body_stmt| {
                try countAssignmentsInStmt(counts, body_stmt, allocator);
            }
        },
        .for_stmt => |for_stmt| {
            // Loop variable is assigned each iteration
            if (for_stmt.target.* == .name) {
                const name = for_stmt.target.name.id;
                try counts.put(name, 2); // Mark as mutated
            }
            for (for_stmt.body) |body_stmt| {
                try countAssignmentsInStmt(counts, body_stmt, allocator);
            }
        },
        .try_stmt => |try_stmt| {
            for (try_stmt.body) |body_stmt| {
                try countAssignmentsInStmt(counts, body_stmt, allocator);
            }
            for (try_stmt.handlers) |handler| {
                for (handler.body) |body_stmt| {
                    try countAssignmentsInStmt(counts, body_stmt, allocator);
                }
            }
        },
        else => {},
    }
}

/// Generate function body with scope management
pub fn genFunctionBody(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    has_allocator_param: bool,
    actually_uses_allocator: bool,
) CodegenError!void {
    // For async functions, generate task spawn wrapper
    if (func.is_async) {
        try genAsyncFunctionBody(self, func);
        return;
    }

    // Analyze function body for mutated variables BEFORE generating code
    // This populates func_local_mutations so emitVarDeclaration can make correct var/const decisions
    self.func_local_mutations.clearRetainingCapacity();
    try analyzeFunctionLocalMutations(self, func);

    self.indent();

    // Push new scope for function body
    try self.pushScope();

    // If allocator param was added but not actually used, suppress warning
    if (has_allocator_param and !actually_uses_allocator) {
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "_ = allocator;\n");
    }

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

    // Clear function-local mutations after exiting function
    self.func_local_mutations.clearRetainingCapacity();

    var builder = CodeBuilder.init(self);
    _ = try builder.endBlock();
}

/// Generate async function body (implementation function for green thread scheduler)
fn genAsyncFunctionBody(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
) CodegenError!void {
    self.indent();

    // Push new scope for function body
    try self.pushScope();

    // Declare function parameters in the scope
    for (func.args) |arg| {
        try self.declareVar(arg.name);
    }

    // Generate function body directly (no task wrapping needed)
    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Pop scope when exiting function
    self.popScope();

    var builder = CodeBuilder.init(self);
    _ = try builder.endBlock();
}

/// Generate method body with self-usage detection
pub fn genMethodBody(self: *NativeCodegen, method: ast.Node.FunctionDef) CodegenError!void {
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

/// Generate struct fields from __init__ method
pub fn genClassFields(self: *NativeCodegen, init: ast.Node.FunctionDef) CodegenError!void {
    for (init.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            // Check if target is self.attribute
            if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                const attr = assign.targets[0].attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                    // Found field: self.x = y
                    const field_name = attr.attr;

                    // Determine field type by inferring the value's type
                    var inferred = try self.type_inferrer.inferExpr(assign.value.*);

                    // If unknown and value is a parameter reference, check parameter annotation
                    if (inferred == .unknown and assign.value.* == .name) {
                        const param_name = assign.value.name.id;
                        for (init.args) |arg| {
                            if (std.mem.eql(u8, arg.name, param_name)) {
                                // Use type annotation if available
                                inferred = signature.pythonTypeToNativeType(arg.type_annotation);
                                break;
                            }
                        }
                    }

                    const field_type_str = switch (inferred) {
                        .int => "i64",
                        .float => "f64",
                        .bool => "bool",
                        .string => "[]const u8",
                        else => "i64",
                    };

                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("{s}: {s},\n", .{ field_name, field_type_str });
                }
            }
        }
    }

    // Add __dict__ for dynamic attributes (always enabled)
    try self.output.appendSlice(self.allocator, "\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "// Dynamic attributes dictionary\n");
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "__dict__: hashmap_helper.StringHashMap(runtime.PyValue),\n");
}

/// Infer parameter type by looking at how it's used in __init__
fn inferParamType(self: *NativeCodegen, init: ast.Node.FunctionDef, param_name: []const u8) ![]const u8 {
    // Look for assignments like self.field = param_name
    for (init.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.value.* == .name and std.mem.eql(u8, assign.value.name.id, param_name)) {
                // Found usage - infer type from the value
                const inferred = try self.type_inferrer.inferExpr(assign.value.*);
                return switch (inferred) {
                    .int => "i64",
                    .float => "f64",
                    .bool => "bool",
                    .string => "[]const u8",
                    else => "i64",
                };
            }
        }
    }
    // Fallback: use i64 as default
    return "i64";
}

/// Generate init() method from __init__
pub fn genInitMethod(
    self: *NativeCodegen,
    class_name: []const u8,
    init: ast.Node.FunctionDef,
) CodegenError!void {
    try self.output.appendSlice(self.allocator, "\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("pub fn init(allocator: std.mem.Allocator", .{});

    // Parameters (skip 'self')
    for (init.args) |arg| {
        if (std.mem.eql(u8, arg.name, "self")) continue;

        try self.output.appendSlice(self.allocator, ", ");

        try self.output.writer(self.allocator).print("{s}: ", .{arg.name});

        // Type annotation: prefer type hints, fallback to inference
        const param_type = if (arg.type_annotation) |_|
            signature.pythonTypeToZig(arg.type_annotation)
        else
            try inferParamType(self, init, arg.name);
        try self.output.appendSlice(self.allocator, param_type);
    }

    try self.output.writer(self.allocator).print(") {s} {{\n", .{class_name});
    self.indent();

    // Note: allocator is always used for __dict__ initialization, so no discard needed

    // Generate return statement with field initializers
    try self.emitIndent();
    try self.output.writer(self.allocator).print("return {s}{{\n", .{class_name});
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

    // Initialize __dict__ for dynamic attributes
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, ".__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init(allocator),\n");

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "};\n");

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}\n");
}

/// Generate regular class methods (non-__init__)
pub fn genClassMethods(
    self: *NativeCodegen,
    class: ast.Node.ClassDef,
) CodegenError!void {
    for (class.body) |stmt| {
        if (stmt == .function_def) {
            const method = stmt.function_def;
            if (std.mem.eql(u8, method.name, "__init__")) continue;

            const mutates_self = methodMutatesSelf(method);
            try signature.genMethodSignature(self, class.name, method, mutates_self);
            try genMethodBody(self, method);
        }
    }
}

/// Generate inherited methods from parent class
pub fn genInheritedMethods(
    self: *NativeCodegen,
    class: ast.Node.ClassDef,
    parent: ast.Node.ClassDef,
    child_method_names: []const []const u8,
) CodegenError!void {
    for (parent.body) |parent_stmt| {
        if (parent_stmt == .function_def) {
            const parent_method = parent_stmt.function_def;
            if (std.mem.eql(u8, parent_method.name, "__init__")) continue;

            // Check if child overrides this method
            var is_overridden = false;
            for (child_method_names) |child_name| {
                if (std.mem.eql(u8, child_name, parent_method.name)) {
                    is_overridden = true;
                    break;
                }
            }

            if (!is_overridden) {
                // Copy parent method to child class
                const mutates_self = methodMutatesSelf(parent_method);
                try signature.genMethodSignature(self, class.name, parent_method, mutates_self);
                try genMethodBody(self, parent_method);
            }
        }
    }
}
