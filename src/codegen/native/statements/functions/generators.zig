/// Function and class definition code generation
const std = @import("std");
const ast = @import("../../../../ast.zig");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const DecoratedFunction = @import("../../main.zig").DecoratedFunction;
const CodegenError = @import("../../main.zig").CodegenError;
const allocator_analyzer = @import("allocator_analyzer.zig");
const signature = @import("generators/signature.zig");
const body = @import("generators/body.zig");

/// Generate function definition
pub fn genFunctionDef(self: *NativeCodegen, func: ast.Node.FunctionDef) CodegenError!void {
    // Check if function needs allocator parameter (for error union return type)
    const needs_allocator_for_errors = allocator_analyzer.functionNeedsAllocator(func);

    // Check if function actually uses the allocator param (not just __global_allocator)
    const actually_uses_allocator = allocator_analyzer.functionActuallyUsesAllocatorParam(func);

    // In module mode, ALL functions get allocator for consistency at module boundaries
    // In script mode, only functions that need it get allocator
    const needs_allocator = if (self.mode == .module) true else needs_allocator_for_errors;

    // Track this function if it needs allocator (for call site generation)
    if (needs_allocator) {
        const func_name_copy = try self.allocator.dupe(u8, func.name);
        try self.functions_needing_allocator.put(func_name_copy, {});
    }

    // Track async functions (for calling with _async suffix)
    if (func.is_async) {
        const func_name_copy = try self.allocator.dupe(u8, func.name);
        try self.async_functions.put(func_name_copy, {});
    }

    // Generate function signature
    try signature.genFunctionSignature(self, func, needs_allocator);

    // Generate function body
    try body.genFunctionBody(self, func, needs_allocator, actually_uses_allocator);

    // Register decorated functions for application in main()
    if (func.decorators.len > 0) {
        const decorated_func = DecoratedFunction{
            .name = func.name,
            .decorators = func.decorators,
        };
        try self.decorated_functions.append(self.allocator, decorated_func);
    }

    // Clear global vars after function exits (they're function-scoped)
    self.clearGlobalVars();
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
    if (init_method) |init| {
        try body.genClassFields(self, class.name, init);
    }

    // Generate init() method from __init__
    if (init_method) |init| {
        try body.genInitMethod(self, class.name, init);
    }

    // Build list of child method names for override detection
    var child_method_names = std.ArrayList([]const u8){};
    defer child_method_names.deinit(self.allocator);
    for (class.body) |stmt| {
        if (stmt == .function_def) {
            try child_method_names.append(self.allocator, stmt.function_def.name);
        }
    }

    // Check if this class has any mutating methods (excluding __init__)
    // If so, track it in mutable_classes so instances use `var` not `const`
    var has_mutating_method = false;
    for (class.body) |stmt| {
        if (stmt == .function_def) {
            const method = stmt.function_def;
            if (std.mem.eql(u8, method.name, "__init__")) continue;
            if (body.methodMutatesSelf(method)) {
                has_mutating_method = true;
                break;
            }
        }
    }
    if (has_mutating_method) {
        const class_name_copy = try self.allocator.dupe(u8, class.name);
        try self.mutable_classes.put(class_name_copy, {});
    }

    // Generate regular methods (non-__init__)
    try body.genClassMethods(self, class);

    // Inherit parent methods that aren't overridden
    if (parent_class) |parent| {
        try body.genInheritedMethods(self, class, parent, child_method_names.items);
    }

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "};\n");
}
