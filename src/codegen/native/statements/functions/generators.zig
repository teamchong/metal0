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

    // Track functions with varargs (for call site generation)
    if (func.vararg) |vararg_name| {
        const func_name_copy = try self.allocator.dupe(u8, func.name);
        try self.vararg_functions.put(func_name_copy, {});
        // Also track the parameter name (e.g., "args") for type inference
        const vararg_param_copy = try self.allocator.dupe(u8, vararg_name);
        try self.vararg_params.put(vararg_param_copy, {});
    }

    // Track functions with kwargs (for call site generation)
    if (func.kwarg) |kwarg_name| {
        const func_name_copy = try self.allocator.dupe(u8, func.name);
        try self.kwarg_functions.put(func_name_copy, {});
        // Also track the parameter name (e.g., "kwargs") for len() builtin
        const kwarg_param_copy = try self.allocator.dupe(u8, kwarg_name);
        try self.kwarg_params.put(kwarg_param_copy, {});
    }

    // Track function signature (param counts for default parameter handling)
    var required_count: usize = 0;
    for (func.args) |arg| {
        if (arg.default == null) required_count += 1;
    }
    const func_name_sig = try self.allocator.dupe(u8, func.name);
    try self.function_signatures.put(func_name_sig, .{
        .total_params = func.args.len,
        .required_params = required_count,
    });

    // Generate function signature
    try signature.genFunctionSignature(self, func, needs_allocator);

    // Set current function name for tail-call optimization detection
    self.current_function_name = func.name;

    // Generate function body
    try body.genFunctionBody(self, func, needs_allocator, actually_uses_allocator);

    // Clear current function name after body generation
    self.current_function_name = null;

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
    // Find __init__ and setUp methods to determine struct fields
    var init_method: ?ast.Node.FunctionDef = null;
    var setUp_method: ?ast.Node.FunctionDef = null;
    for (class.body) |stmt| {
        if (stmt == .function_def) {
            if (std.mem.eql(u8, stmt.function_def.name, "__init__")) {
                init_method = stmt.function_def;
            } else if (std.mem.eql(u8, stmt.function_def.name, "setUp")) {
                setUp_method = stmt.function_def;
            }
        }
    }

    // Check for base classes - we support single inheritance
    var parent_class: ?ast.Node.ClassDef = null;
    var is_unittest_class = false;
    if (class.bases.len > 0) {
        // Look up parent class in registry (populated in Phase 2 of generate())
        // Order doesn't matter - all classes are registered before code generation
        parent_class = self.class_registry.getClass(class.bases[0]);

        // Check if this class inherits from unittest.TestCase
        if (std.mem.eql(u8, class.bases[0], "unittest.TestCase")) {
            is_unittest_class = true;
        }
    }

    // Track unittest TestCase classes and their test methods
    if (is_unittest_class) {
        const core = @import("../../main/core.zig");
        var test_methods = std.ArrayList(core.TestMethodInfo){};
        var has_setUp = false;
        var has_tearDown = false;
        var has_setup_class = false;
        var has_teardown_class = false;
        for (class.body) |stmt| {
            if (stmt == .function_def) {
                const method = stmt.function_def;
                const method_name = method.name;
                if (std.mem.startsWith(u8, method_name, "test_") or std.mem.startsWith(u8, method_name, "test")) {
                    // Check for skip docstring: first statement is string starting with "skip:"
                    const skip_reason = getSkipReason(method);
                    try test_methods.append(self.allocator, core.TestMethodInfo{
                        .name = method_name,
                        .skip_reason = skip_reason,
                    });
                } else if (std.mem.eql(u8, method_name, "setUp")) {
                    has_setUp = true;
                } else if (std.mem.eql(u8, method_name, "tearDown")) {
                    has_tearDown = true;
                } else if (std.mem.eql(u8, method_name, "setUpClass")) {
                    has_setup_class = true;
                } else if (std.mem.eql(u8, method_name, "tearDownClass")) {
                    has_teardown_class = true;
                }
            }
        }
        try self.unittest_classes.append(self.allocator, core.TestClassInfo{
            .class_name = class.name,
            .test_methods = try test_methods.toOwnedSlice(self.allocator),
            .has_setUp = has_setUp,
            .has_tearDown = has_tearDown,
            .has_setup_class = has_setup_class,
            .has_teardown_class = has_teardown_class,
        });
    }

    // Generate: const ClassName = struct {
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{class.name});
    self.indent();

    // Extract fields from __init__ body (self.x = ...)
    if (init_method) |init| {
        try body.genClassFields(self, class.name, init);
    }

    // For unittest classes, also extract fields from setUp method (without adding __dict__ again)
    if (is_unittest_class) {
        if (setUp_method) |setUp| {
            try body.genClassFieldsNoDict(self, class.name, setUp);
        }
    }

    // Generate init() method from __init__, or default init if no __init__
    if (init_method) |init| {
        try body.genInitMethod(self, class.name, init);
    } else {
        // No __init__ defined, generate default init method
        try body.genDefaultInitMethod(self, class.name);
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
    try self.emit("};\n");
}

/// Check if a test method has a skip docstring
/// Returns the skip reason if found, null otherwise
/// Looks for: """skip: reason""" or "skip: reason" as first statement
fn getSkipReason(method: ast.Node.FunctionDef) ?[]const u8 {
    if (method.body.len == 0) return null;

    // Check if first statement is an expression statement with a string constant
    const first = method.body[0];
    if (first != .expr_stmt) return null;

    const expr = first.expr_stmt.value.*;
    if (expr != .constant) return null;

    const val = expr.constant.value;
    if (val != .string) return null;

    var docstring = val.string;

    // The parser stores strings with their original Python quotes
    // Single-quoted: "skip: reason" (with surrounding quotes)
    // Triple-quoted: """skip: reason""" becomes ""skip: reason"" in storage
    // We need to strip these outer quotes first

    // Strip leading quotes (" or "")
    while (docstring.len > 0 and docstring[0] == '"') {
        docstring = docstring[1..];
    }
    // Strip trailing quotes
    while (docstring.len > 0 and docstring[docstring.len - 1] == '"') {
        docstring = docstring[0 .. docstring.len - 1];
    }

    // Check for "skip:" prefix (case insensitive for the prefix)
    if (docstring.len >= 5) {
        const prefix = docstring[0..5];
        if (std.mem.eql(u8, prefix, "skip:") or std.mem.eql(u8, prefix, "SKIP:")) {
            // Return the reason (everything after "skip:")
            const reason = std.mem.trim(u8, docstring[5..], " \t\n\r");
            return if (reason.len > 0) reason else "skipped";
        }
    }
    return null;
}
