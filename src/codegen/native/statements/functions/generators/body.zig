/// Function and class body generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const CodeBuilder = @import("../../../code_builder.zig").CodeBuilder;
const self_analyzer = @import("../self_analyzer.zig");
const param_analyzer = @import("../param_analyzer.zig");
const allocator_analyzer = @import("../allocator_analyzer.zig");
const signature = @import("signature.zig");
const hashmap_helper = @import("hashmap_helper");

// Re-export from submodules
const class_fields = @import("body/class_fields.zig");
const class_methods = @import("body/class_methods.zig");

pub const genClassFields = class_fields.genClassFields;
pub const genClassFieldsNoDict = class_fields.genClassFieldsNoDict;
pub const inferParamType = class_fields.inferParamType;

pub const genDefaultInitMethod = class_methods.genDefaultInitMethod;
pub const genInitMethod = class_methods.genInitMethod;
pub const genClassMethods = class_methods.genClassMethods;
pub const genInheritedMethods = class_methods.genInheritedMethods;

/// Check if a method mutates self (assigns to self.field or self.field[key])
pub fn methodMutatesSelf(method: ast.Node.FunctionDef) bool {
    for (method.body) |stmt| {
        if (stmt == .assign) {
            for (stmt.assign.targets) |target| {
                if (target == .attribute) {
                    const attr = target.attribute;
                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                        return true; // Assigns to self.field
                    }
                } else if (target == .subscript) {
                    // Check if subscript base is self.something: self.routes[key] = value
                    const subscript = target.subscript;
                    if (subscript.value.* == .attribute) {
                        const attr = subscript.value.attribute;
                        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                            return true; // Assigns to self.field[key]
                        }
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
    self.hoisted_vars.clearRetainingCapacity();
    try analyzeFunctionLocalMutations(self, func);

    self.indent();

    // Push new scope for function body
    try self.pushScope();

    // If allocator param was added but not actually used, suppress warning
    if (has_allocator_param and !actually_uses_allocator) {
        try self.emitIndent();
        try self.emit("_ = allocator;\n");
    }

    // Suppress warnings for unused function parameters (skip params with defaults - they get renamed)
    for (func.args) |arg| {
        if (arg.default == null and !param_analyzer.isNameUsedInBody(func.body, arg.name)) {
            try self.emitIndent();
            try self.emit("_ = ");
            try self.emit(arg.name);
            try self.emit(";\n");
        }
    }

    // Generate default parameter initialization (before declaring them in scope)
    for (func.args) |arg| {
        if (arg.default) |default_expr| {
            try self.emitIndent();
            try self.emit("const ");
            try self.emit(arg.name);
            try self.emit(" = ");
            try self.emit(arg.name);
            try self.emit("_param orelse ");
            const expressions = @import("../../../expressions.zig");
            try expressions.genExpr(self, default_expr.*);
            try self.emit(";\n");
        }
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

    // Async impl functions use __global_allocator directly in generated code (e.g., createTask).
    // The `allocator` alias is provided for consistency but often unused.
    // Always suppress warning since analysis can't distinguish direct vs aliased use.
    try self.emitIndent();
    try self.emit("const allocator = __global_allocator; _ = allocator;\n");

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

    // Note: self-usage is now handled in signature generation by using `_` as param name
    // No need to add `_ = self;` here anymore

    // Clear local variable types (new method scope)
    self.clearLocalVarTypes();

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
    try self.emit("}\n");
}
