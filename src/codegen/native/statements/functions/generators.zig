/// Function and class definition code generation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const hashmap_helper = @import("utils.hashmap_helper");
const zig_keywords = @import("utils.zig_keywords");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const DecoratedFunction = @import("../../main.zig").DecoratedFunction;
const CodegenError = @import("../../main.zig").CodegenError;
const function_traits = @import("analysis.function_traits");
const signature = @import("generators/signature.zig");
const body = @import("generators/body.zig");
const builtin_types = @import("generators/builtin_types.zig");
const test_skip = @import("generators/test_skip.zig");
const shared = @import("../../shared_maps.zig");
const PyBuiltinTypes = shared.PythonBuiltinTypes;
const PythonBuiltinNames = shared.PythonBuiltinNames;

// Re-exports
pub const analyzeModuleLevelMutations = body.analyzeModuleLevelMutations;
pub const BuiltinBaseInfo = builtin_types.BuiltinBaseInfo;
pub const ComplexParentInfo = builtin_types.ComplexParentInfo;
pub const getBuiltinBaseInfo = builtin_types.getBuiltinBaseInfo;
pub const getComplexParentInfo = builtin_types.getComplexParentInfo;
pub const hasCPythonOnlyDecorator = test_skip.hasCPythonOnlyDecorator;
pub const hasSkipUnlessCPythonModule = test_skip.hasSkipUnlessCPythonModule;
pub const hasSkipIfModuleIsNone = test_skip.hasSkipIfModuleIsNone;

/// Generate function definition
pub fn genFunctionDef(self: *NativeCodegen, func: ast.Node.FunctionDef) CodegenError!void {
    // Check if this function was hoisted as a DynamicClosure (from if/else block)
    // In this case, we need to generate a closure and assign to the hoisted variable,
    // NOT generate a standalone fn (Zig doesn't allow fn inside if blocks)
    if (self.hoisted_dynamic_closures.contains(func.name)) {
        // Route to zero-capture closure generation which handles assignment to hoisted var
        const zero_capture = @import("nested/zero_capture.zig");
        return zero_capture.genZeroCaptureClosure(self, func);
    }

    // Use function_traits for allocator decision (unified analysis)
    const needs_allocator_from_traits = self.funcNeedsAllocator(func.name);
    const needs_allocator_for_errors = if (needs_allocator_from_traits) true else function_traits.analyzeNeedsAllocator(func, null);

    // Check if function actually uses the allocator param (not just __global_allocator)
    const actually_uses_allocator = function_traits.analyzeUsesAllocatorParam(func, null);

    // In module mode, ALL functions get allocator for consistency at module boundaries
    // In script mode, only functions that need it get allocator
    const needs_allocator = if (self.mode == .module) true else needs_allocator_for_errors;

    // Track this function if it needs allocator (for call site generation)
    if (needs_allocator) {
        const func_name_copy = try self.arena.allocator().dupe(u8, func.name);
        try self.functions_needing_allocator.put(func_name_copy, {});
    }

    // Track async functions (for calling with _async suffix)
    if (func.is_async) {
        const func_name_copy = try self.arena.allocator().dupe(u8, func.name);
        try self.async_functions.put(func_name_copy, {});
    }

    // Check if this is a generator function (contains yield)
    // First try call graph (for top-level functions), then fall back to AST check
    // (for nested functions which aren't registered in call graph)
    const is_generator = self.funcIsGenerator(func.name) or signature.hasYieldStatement(func.body);
    // Set flag for generator functions - must be set before signature generation
    // and persist through body generation
    if (is_generator) {
        // Generators are transformed to eager evaluation:
        // - Collect all yield values into an ArrayList
        // - Return the list at the end
        // This is not true lazy evaluation but works for most test cases
        self.in_generator_function = true;
    }
    defer if (is_generator) {
        self.in_generator_function = false;
    };

    // Track functions with varargs (for call site generation)
    // Store the vararg start index (number of regular params before *args)
    if (func.vararg) |vararg_name| {
        const func_name_copy = try self.arena.allocator().dupe(u8, func.name);
        try self.vararg_functions.put(func_name_copy, func.args.len);
        // Also track the parameter name (e.g., "args") for type inference
        const vararg_param_copy = try self.arena.allocator().dupe(u8, vararg_name);
        try self.vararg_params.put(vararg_param_copy, {});
    }

    // Track functions with kwargs (for call site generation)
    if (func.kwarg) |kwarg_name| {
        const func_name_copy = try self.arena.allocator().dupe(u8, func.name);
        try self.kwarg_functions.put(func_name_copy, {});
        // Also track the parameter name (e.g., "kwargs") for len() builtin
        const kwarg_param_copy = try self.arena.allocator().dupe(u8, kwarg_name);
        try self.kwarg_params.put(kwarg_param_copy, {});
    }

    // Track function signature (param counts for default parameter handling)
    var required_count: usize = 0;
    for (func.args) |arg| {
        if (arg.default == null) required_count += 1;
    }
    // Extract parameter names for keyword argument mapping
    var param_names = try self.allocator.alloc([]const u8, func.args.len);
    for (func.args, 0..) |arg, i| {
        param_names[i] = arg.name;
    }
    const func_name_sig = try self.arena.allocator().dupe(u8, func.name);
    try self.function_signatures.put(func_name_sig, .{
        .total_params = func.args.len,
        .required_params = required_count,
        .param_names = param_names,
    });

    // Analyze nested class captures BEFORE generating signature
    // This allows genFunctionSignature to know which parameters are "used" via closures
    // The nested_class_captures map is populated here and read in signature.zig
    self.func_local_vars.clearRetainingCapacity();
    self.nested_class_captures.clearRetainingCapacity();
    // Clear deferred closure instantiations from previous function
    // This prevents closures from one function leaking into another function's scope
    self.clearDeferredClosureInstantiations();
    try body.analyzeNestedClassCaptures(self, func);

    // Set up parameter renames BEFORE signature generation
    // These will be used by BOTH signature and body generation for consistency
    // Clear old renames first to prevent cross-function pollution
    self.var_renames.clearRetainingCapacity();
    for (func.args) |arg| {
        const shadows_module_level = self.module_level_funcs.contains(arg.name) or
            self.module_level_vars.contains(arg.name) or
            self.imported_modules.contains(arg.name) or
            zig_keywords.wouldShadowModule(arg.name);

        // Check if parameter shadows a sibling method or class-level attribute
        const shadows_class_member = if (self.current_class_body) |class_body| blk: {
            for (class_body) |stmt| {
                if (stmt == .function_def) {
                    if (std.mem.eql(u8, stmt.function_def.name, arg.name)) {
                        break :blk true;
                    }
                }
                if (stmt == .assign) {
                    for (stmt.assign.targets) |target| {
                        if (target == .name) {
                            if (std.mem.eql(u8, target.name.id, arg.name)) {
                                break :blk true;
                            }
                        }
                    }
                }
            }
            break :blk false;
        } else false;

        if (shadows_module_level or shadows_class_member) {
            // Use NameGen to generate unique name
            const unique_name = try self.name_gen.param(arg.name);
            try self.var_renames.put(arg.name, unique_name);
        }
    }

    // Two-Flow: Reset PyValue return tracking before generating each function
    self.current_function_returns_pyvalue = false;

    // Generate function signature
    try signature.genFunctionSignature(self, func, needs_allocator);

    // Set current function name for tail-call optimization detection
    self.current_function_name = func.name;

    // Reset control flow termination flag for new function
    self.control_flow_terminated = false;

    // Clear local variable types (new function scope)
    self.clearLocalVarTypes();

    // Generate function body
    try body.genFunctionBody(self, func, needs_allocator, actually_uses_allocator);

    // Clear current function name after body generation
    self.current_function_name = null;
    // Two-Flow: Reset PyValue return tracking
    self.current_function_returns_pyvalue = false;

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

    // Clear var_renames after function exits to prevent leaking into module-level code
    // (e.g., parameter `a` renamed to `__m0_p_a` should not affect module-level `a = 10`)
    self.var_renames.clearRetainingCapacity();

    // Reset control flow termination flag after function exits
    // This is critical: a raise/return inside the function body should not
    // prevent subsequent module-level statements from being generated
    self.control_flow_terminated = false;
}

/// Generate class definition with __init__ constructor
/// Types that cannot be subclassed in Python (final types)
/// Note: 'type' is NOT in this list - metaclasses (class Foo(type)) are supported
const non_subclassable_types = std.StaticStringMap(void).initComptime(.{
    .{ "bool", {} },
    .{ "NoneType", {} },
    .{ "NotImplementedType", {} },
    .{ "ellipsis", {} },
    .{ "range", {} },
    .{ "slice", {} },
});

pub fn genClassDef(self: *NativeCodegen, class: ast.Node.ClassDef) CodegenError!void {

    // Check for non-subclassable types (bool, NoneType, etc.)
    // These must raise TypeError at runtime, not compile time, because the class
    // definition might be inside a try/except block that catches the error
    if (class.bases.len > 0) {
        for (class.bases) |base| {
            if (non_subclassable_types.has(base)) {
                // When inside a nested function (zero-capture or closure), we need to
                // emit discards for any parameters that were expected to be used in the
                // class body. The analysis phase thought params were used, but since we're
                // short-circuiting with an error, they remain unused.
                if (self.inside_nested_function) {
                    // Emit discards for any __p_* parameters that might exist
                    // Iterate through var_renames looking for __p_* entries
                    var iter = self.var_renames.iterator();
                    while (iter.next()) |entry| {
                        const renamed = entry.value_ptr.*;
                        if (std.mem.startsWith(u8, renamed, "__p_")) {
                            try self.emitIndent();
                            try self.output.writer(self.allocator).print("_ = {s};\n", .{renamed});
                        }
                    }
                }
                // Generate code that raises TypeError
                // Inside a function, return error.TypeError
                // Otherwise, emit a stub struct that errors when used
                if (self.inside_nested_function or self.current_function_name != null) {
                    try self.emitIndent();
                    try self.emit("return error.TypeError; // type '");
                    try self.emit(base);
                    try self.emit("' is not an acceptable base type\n");
                    // Mark control flow as terminated so subsequent code isn't generated
                    self.control_flow_terminated = true;
                } else {
                    // Emit a stub struct that raises compile error when init() is called
                    // This is valid at any level (module, class body, etc.)
                    try self.emitIndent();
                    try self.emit("const ");
                    try self.emit(class.name);
                    try self.emit(" = struct { pub fn init(_: std.mem.Allocator) @This() { @compileError(\"Cannot subclass '");
                    try self.emit(base);
                    try self.emit("' - metaclasses are not supported\"); } };\n");
                }
                return;
            }
        }
    }

    // Handle Generic[T, U, ...] classes - generate comptime generic function
    if (class.type_params.len > 0) {
        return genGenericClassDef(self, class);
    }

    // Track nested class names for instance detection and heap allocation
    // Only add to nested_class_names if inside a function (current_function_name is set)
    // Module-level classes should NOT be in nested_class_names
    if (self.current_function_name != null) {
        try self.nested_class_names.put(class.name, {});
    }

    // Find __init__, __new__, and setUp methods to determine struct fields
    var init_method: ?ast.Node.FunctionDef = null;
    var new_method: ?ast.Node.FunctionDef = null;
    var setUp_method: ?ast.Node.FunctionDef = null;
    for (class.body) |stmt| {
        if (stmt == .function_def) {
            if (std.mem.eql(u8, stmt.function_def.name, "__init__")) {
                init_method = stmt.function_def;
            } else if (std.mem.eql(u8, stmt.function_def.name, "__new__")) {
                new_method = stmt.function_def;
            } else if (std.mem.eql(u8, stmt.function_def.name, "setUp")) {
                setUp_method = stmt.function_def;
            }
        }
    }

    // Register nested class fields in type_inferrer.class_fields
    // This is needed so isDynamicAttribute() can find fields of nested classes
    // IMPORTANT: Only do this if analysis phase didn't already populate the class info
    // (analysis phase populates property_methods/property_getters which we must preserve)
    if (init_method) |init| {
        // Check if class_fields was already populated by analysis phase
        if (self.type_inferrer.class_fields.get(class.name)) |existing_info| {
            // Analysis phase already populated this class - merge fields only
            // Extract field types from __init__ body and add to existing fields
            for (init.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                        const attr = assign.targets[0].attribute;
                        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                            // Only add if not already known
                            if (!existing_info.fields.contains(attr.attr)) {
                                const native_types = @import("../../../../analysis/native_types/core.zig");
                                var fields = existing_info.fields;
                                try fields.put(attr.attr, native_types.NativeType.unknown);
                            }
                        }
                    }
                }
            }
        } else {
            // Analysis phase didn't populate this class - create new entry
            const native_types = @import("../../../../analysis/native_types/core.zig");
            var fields = hashmap_helper.StringHashMap(native_types.NativeType).init(self.allocator);
            const methods = hashmap_helper.StringHashMap(native_types.NativeType).init(self.allocator);
            const property_methods = hashmap_helper.StringHashMap(native_types.NativeType).init(self.allocator);
            const property_getters = hashmap_helper.StringHashMap([]const u8).init(self.allocator);

            // Extract field types from __init__ body
            for (init.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                        const attr = assign.targets[0].attribute;
                        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                            // Register the field name - type doesn't matter for isDynamicAttribute check
                            // Use .unknown as a placeholder type
                            try fields.put(attr.attr, .unknown);
                        }
                    }
                }
            }

            try self.type_inferrer.class_fields.put(class.name, .{
                .fields = fields,
                .methods = methods,
                .property_methods = property_methods,
                .property_getters = property_getters,
            });
        }

        // Also register 'self' as a class_instance of this class
        // This is needed for type inference during method body generation
        // NOTE: For nested classes inside methods, we need to save/restore the outer 'self' type
        // to avoid the nested class's 'self' leaking into the enclosing class's methods
        if (self.current_function_name == null) {
            // Module-level class - just set self directly
            // Use putScopedVar to update both scoped and global maps
            try self.type_inferrer.putScopedVar("self", .{ .class_instance = class.name });
        }
        // For nested classes (inside methods), don't override 'self' in type_inferrer
        // because 'self' should refer to the enclosing class's instance, not the nested class
    } else if (new_method) |new| {
        // Similar logic for __new__ methods when there's no __init__
        // In __new__, fields are set on the local 'self' variable created by super().__new__()
        if (self.type_inferrer.class_fields.getPtr(class.name)) |existing_info_ptr| {
            // Merge fields from __new__ body into the existing entry
            const native_types = @import("../../../../analysis/native_types/core.zig");
            for (new.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                        const attr = assign.targets[0].attribute;
                        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                            if (!existing_info_ptr.fields.contains(attr.attr)) {
                                try existing_info_ptr.fields.put(attr.attr, native_types.NativeType.unknown);
                            }
                        }
                    }
                }
            }
        } else {
            // Create new entry for class
            const native_types = @import("../../../../analysis/native_types/core.zig");
            var fields = hashmap_helper.StringHashMap(native_types.NativeType).init(self.allocator);
            const methods = hashmap_helper.StringHashMap(native_types.NativeType).init(self.allocator);
            const property_methods = hashmap_helper.StringHashMap(native_types.NativeType).init(self.allocator);
            const property_getters = hashmap_helper.StringHashMap([]const u8).init(self.allocator);

            // Extract field types from __new__ body
            for (new.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                        const attr = assign.targets[0].attribute;
                        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                            try fields.put(attr.attr, .unknown);
                        }
                    }
                }
            }

            try self.type_inferrer.class_fields.put(class.name, .{
                .fields = fields,
                .methods = methods,
                .property_methods = property_methods,
                .property_getters = property_getters,
            });
        }
    }

    // Check for base classes - we support single inheritance
    var parent_class: ?ast.Node.ClassDef = null;
    var is_unittest_class = false;
    var builtin_base: ?BuiltinBaseInfo = null;
    var complex_parent: ?ComplexParentInfo = null;
    if (class.bases.len > 0) {
        // First check if it's a builtin base type (simple types like int, float)
        builtin_base = getBuiltinBaseInfo(class.bases[0]);

        // Then check for complex parent types (like array.array with multiple fields)
        if (builtin_base == null) {
            complex_parent = getComplexParentInfo(class.bases[0]);
        }

        // Look up parent class in registry (populated in Phase 2 of generate())
        // Order doesn't matter - all classes are registered before code generation
        if (builtin_base == null and complex_parent == null) {
            // First check class_registry for module-level classes
            parent_class = self.class_registry.getClass(class.bases[0]);

            // Then check nested_class_defs for nested classes defined in same scope
            if (parent_class == null) {
                parent_class = self.nested_class_defs.get(class.bases[0]);
            }
        }

        // Check if this class inherits from unittest.TestCase (directly or indirectly)
        if (std.mem.eql(u8, class.bases[0], "unittest.TestCase")) {
            is_unittest_class = true;
        } else if (self.isTestCaseSubclass(class.bases[0])) {
            // Check if parent class inherits from TestCase
            is_unittest_class = true;
        }
    }

    // Track unittest TestCase classes and their test methods
    // Only register classes defined at module level - classes inside functions
    // are not directly accessible and must be discovered through module-level bindings
    if (is_unittest_class and self.current_function_name == null) {
        const core = @import("../../main/core.zig");
        var test_methods = std.ArrayList(core.TestMethodInfo){};
        // Build class_names_list ONCE per class (not per method) - PERFORMANCE OPTIMIZATION
        // This avoids iterating through all registered classes 15+ times for large test classes
        var class_names_list: std.ArrayList([]const u8) = .{};
        defer class_names_list.deinit(self.allocator);
        var classes_iter = self.class_registry.classes.iterator();
        while (classes_iter.next()) |entry| {
            try class_names_list.append(self.allocator, entry.key_ptr.*);
        }
        const class_names = class_names_list.items;

        var has_setUp = false;
        var has_tearDown = false;
        var has_setup_class = false;
        var has_teardown_class = false;
        for (class.body) |stmt| {
            if (stmt == .function_def) {
                const method = stmt.function_def;
                const method_name = method.name;
                if (std.mem.startsWith(u8, method_name, "test_") or std.mem.startsWith(u8, method_name, "test")) {

                    // Check if method body has fallible operations (needs allocator param)
                    const method_needs_allocator = function_traits.analyzeNeedsAllocator(method, class.name);

                    // First check unittest skip decorators (skipIf, skipUnless, skip)
                    // These are evaluated at compile time for platform/module checks
                    const decorator_skip = test_skip.evaluateSkipDecorators(method.decorators, &self.skipped_modules);

                    const has_cpython_only = test_skip.hasCPythonOnlyDecorator(method.decorators);
                    const has_skip_unless = test_skip.hasSkipUnlessCPythonModule(method.decorators);
                    const has_skip_if_none = test_skip.hasSkipIfModuleIsNone(method.decorators, &self.skipped_modules);
                    const has_type_param = test_skip.hasTypeParameterDefault(method.args);

                    const skip_reason: ?[]const u8 = if (decorator_skip) |reason|
                        reason
                    else if (has_cpython_only)
                        "CPython implementation test (not applicable to metal0)"
                    else if (has_skip_unless)
                        "Requires CPython-only module (_pylong or _decimal)"
                    else if (has_skip_if_none)
                        "Requires unavailable optional module"
                    else if (has_type_param)
                        "Test uses runtime type parameters (cls=float)"
                    else blk: {
                        if (test_skip.callsSelfMethodWithClassArg(method.body, class_names)) {
                            break :blk "Test passes class as runtime argument (self.method(ClassName))";
                        }
                        if (test_skip.hasSkipDocstring(method.body)) {
                            break :blk "Marked skip in docstring";
                        }
                        if (test_skip.isPickleIteratorTest(method_name)) {
                            break :blk "Pickle iterator reconstruction not supported (requires __reduce__ protocol)";
                        }
                        if (test_skip.requiresExceptionContextManager(method_name)) {
                            break :blk "Requires exception context manager support (assertRaisesRegex)";
                        }
                        if (test_skip.hasNestedBuiltinSubclassInLambda(method.body)) {
                            break :blk "Uses nested builtin subclass (str/bytes/bytearray) in lambda factory";
                        }
                        if (test_skip.usesAssertRaisesWithOperatorEqNe(method.body)) {
                            break :blk "Uses assertRaises with operator.eq/ne (requires __eq__=None runtime dispatch)";
                        }
                        if (test_skip.usesCPythonInternalModules(method.body)) {
                            break :blk "Uses CPython internal modules (_pylong/_decimal)";
                        }
                        break :blk null;
                    };

                    // Count @mock.patch.object decorators (each injects a mock param)
                    const mock_count = test_skip.countMockPatchDecorators(method.decorators);

                    // Collect default parameters for test runner to pass
                    var default_params = std.ArrayList(core.TestDefaultParam){};
                    for (method.args) |arg| {
                        if (std.mem.eql(u8, arg.name, "self")) continue;
                        if (arg.default) |default_expr| {
                            // Convert Python default value to Zig code
                            const default_code = test_skip.convertDefaultToZig(default_expr.*);
                            if (default_code) |code| {
                                try default_params.append(self.allocator, .{
                                    .name = arg.name,
                                    .default_code = code,
                                });
                            }
                        }
                    }

                    try test_methods.append(self.allocator, core.TestMethodInfo{
                        .name = method_name,
                        .skip_reason = skip_reason,
                        .needs_allocator = method_needs_allocator,
                        .returns_error = method_needs_allocator, // Methods needing allocator typically have fallible ops
                        .is_skipped = skip_reason != null,
                        .mock_patch_count = mock_count,
                        .default_params = default_params.toOwnedSlice(self.allocator) catch &.{},
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

    // Track class nesting depth for allocator parameter naming
    self.class_nesting_depth += 1;
    defer self.class_nesting_depth -= 1;

    // Save func_local_uses before entering nested class methods
    // This is needed because nested class methods will call analyzeFunctionLocalUses
    // which clears the map - we need to restore it after generating the class
    // to correctly determine if the class itself is used in the enclosing scope
    var saved_func_local_uses = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer saved_func_local_uses.deinit();

    // Also save func_local_mutations - nested class methods will clear it
    // This prevents parent method's mutation info from being lost
    var saved_func_local_mutations = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer saved_func_local_mutations.deinit();

    // Also save func_local_aug_assigns - for shadow variable var/const decisions
    var saved_func_local_aug_assigns = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer saved_func_local_aug_assigns.deinit();

    // Also save nested_class_names - nested class methods will clear it
    // This prevents parent method's nested class tracking from being lost
    // (e.g., MyIndexable defined in outer scope, used later after nested class's methods are generated)
    var saved_nested_class_names = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer saved_nested_class_names.deinit();

    // Also save nested_class_bases - for base class default args
    var saved_nested_class_bases = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
    defer saved_nested_class_bases.deinit();

    // Also save nested_class_defs - for nested class inheritance
    var saved_nested_class_defs = hashmap_helper.StringHashMap(ast.Node.ClassDef).init(self.allocator);
    defer saved_nested_class_defs.deinit();

    // Also save nested_class_captures - for passing captured vars to class init
    var saved_nested_class_captures = hashmap_helper.StringHashMap([][]const u8).init(self.allocator);
    defer saved_nested_class_captures.deinit();

    // Also save hoisted_vars - nested class methods clear it but we need parent's hoisted vars
    // to be restored after the class is generated so assignments use var/const correctly
    var saved_hoisted_vars = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer saved_hoisted_vars.deinit();

    // Save state when inside a function scope (func_local_uses has entries)
    // OR when inside a nested class (class_nesting_depth > 1)
    // This handles: 1) classes inside functions, 2) classes inside classes
    const needs_save_restore = self.func_local_uses.count() > 0 or self.class_nesting_depth > 1;
    if (needs_save_restore) {
        // Copy current func_local_uses
        var it = self.func_local_uses.iterator();
        while (it.next()) |entry| {
            try saved_func_local_uses.put(entry.key_ptr.*, {});
        }

        // Copy current func_local_mutations
        var mut_it = self.func_local_mutations.iterator();
        while (mut_it.next()) |entry| {
            try saved_func_local_mutations.put(entry.key_ptr.*, {});
        }

        // Copy current func_local_aug_assigns
        var aug_it = self.func_local_aug_assigns.iterator();
        while (aug_it.next()) |entry| {
            try saved_func_local_aug_assigns.put(entry.key_ptr.*, {});
        }

        // Copy current nested_class_names
        var ncn_it = self.nested_class_names.iterator();
        while (ncn_it.next()) |entry| {
            try saved_nested_class_names.put(entry.key_ptr.*, {});
        }

        // Copy current nested_class_bases
        var ncb_it = self.nested_class_bases.iterator();
        while (ncb_it.next()) |entry| {
            try saved_nested_class_bases.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Copy current nested_class_defs
        var ncd_it = self.nested_class_defs.iterator();
        while (ncd_it.next()) |entry| {
            try saved_nested_class_defs.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Copy current nested_class_captures
        var ncc_it = self.nested_class_captures.iterator();
        while (ncc_it.next()) |entry| {
            try saved_nested_class_captures.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Copy current hoisted_vars - critical for nested class methods that clear it
        var hv_it = self.hoisted_vars.iterator();
        while (hv_it.next()) |entry| {
            try saved_hoisted_vars.put(entry.key_ptr.*, {});
        }
    }

    // If we're entering a class while inside a method with 'self',
    // increment method_nesting_depth so nested class methods use __self
    const bump_method_depth = self.inside_method_with_self;
    if (bump_method_depth) self.method_nesting_depth += 1;
    defer if (bump_method_depth) {
        self.method_nesting_depth -= 1;
    };

    // Check if this class captures outer mutable variables
    // If this class doesn't have captures but inherits from a parent that does,
    // and this class doesn't override the methods that use those captures,
    // then we need to inherit the parent's captures
    var captured_vars = self.nested_class_captures.get(class.name);
    if (captured_vars == null and class.bases.len > 0) {
        // Check if parent has captures that we need to inherit
        const parent_captures_opt = self.nested_class_captures.get(class.bases[0]);
        if (parent_captures_opt) |parent_captures| {
            // Check if we inherit methods that use the captures (i.e., we don't override them)
            // by checking if parent has methods that child doesn't have
            const parent_def = self.nested_class_defs.get(class.bases[0]);
            if (parent_def) |parent| {
                // Build list of child method names
                var has_methods_using_captures = false;
                for (parent.body) |stmt| {
                    if (stmt == .function_def) {
                        const parent_method_name = stmt.function_def.name;
                        // Check if child overrides this method
                        var child_has_method = false;
                        for (class.body) |child_stmt| {
                            if (child_stmt == .function_def and
                                std.mem.eql(u8, child_stmt.function_def.name, parent_method_name))
                            {
                                child_has_method = true;
                                break;
                            }
                        }
                        if (!child_has_method) {
                            // Child inherits this method - it might use captures
                            has_methods_using_captures = true;
                            break;
                        }
                    }
                }
                if (has_methods_using_captures) {
                    captured_vars = parent_captures;
                    // Store the inherited captures so they're available when generating inherited methods
                    try self.nested_class_captures.put(class.name, parent_captures);
                }
            }
        }
    }

    // Generate unique class name if this name is already declared in current scope
    // This handles Python's ability to redefine a class name in the same function:
    // class S(str): def __add__(self, o): return "3"
    // class S(str): def __iadd__(self, o): return "3"  # redefines S
    // We also need to update var_renames so references to S use the new name
    // ALSO: In Zig, local constants can't shadow module-level constants. So if we're
    // inside a function and there's a module-level class with the same name, rename local.
    var effective_class_name: []const u8 = class.name;
    const shadows_module_class = self.current_function_name != null and self.class_registry.getClass(class.name) != null;
    const is_declared = self.isDeclared(class.name);
    if (is_declared or shadows_module_class) {
        // Generate a unique name based on pointer address
        const unique_name = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ class.name, @intFromPtr(class.name.ptr) });
        effective_class_name = unique_name;
        // Store the rename so references to this class name use the new name
        try self.var_renames.put(class.name, unique_name);
        // Also update hoisted_local_classes if this class was hoisted (for return type generation)
        // hoisted_local_classes survives method body generation, unlike var_renames
        if (self.hoisted_local_classes.contains(class.name)) {
            try self.hoisted_local_classes.put(class.name, unique_name);
        }
    }

    // Track complex class attributes that need lazy-computed methods
    // Instead of pre-generating outside the struct (which breaks Zig scope rules),
    // we generate lazy-computed methods with threadlocal caching inside the struct.
    // This preserves Python's "compute once at class definition" semantics.
    const LazyAttrInfo = struct {
        value: *ast.Node,
        is_closure_list: bool,
        closure_type_idx: ?usize,  // Index for generating unique closure types at struct level
    };
    var lazy_attrs = hashmap_helper.StringHashMap(LazyAttrInfo).init(self.allocator);
    defer lazy_attrs.deinit();

    var next_closure_type_idx: usize = 0;

    for (class.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .name) {
                const attr_name = assign.targets[0].name.id;

                // Skip type attributes (handled as functions)
                if (assign.value.* == .name) {
                    const type_name = assign.value.name.id;
                    if (PyBuiltinTypes.has(type_name)) continue;
                }

                // Skip None attributes (handled as stub methods)
                if (assign.value.* == .constant and assign.value.constant.value == .none) continue;

                // Skip private/dunder attributes
                if (std.mem.startsWith(u8, attr_name, "__")) continue;

                // Skip attributes that have the same name as a method in this class
                // In Python, later definitions shadow earlier ones, so `def spam(self):`
                // after `spam = property(...)` means the method takes precedence
                var has_method_with_same_name = false;
                for (class.body) |check_stmt| {
                    if (check_stmt == .function_def) {
                        if (std.mem.eql(u8, check_stmt.function_def.name, attr_name)) {
                            has_method_with_same_name = true;
                            break;
                        }
                    }
                }
                if (has_method_with_same_name) continue;

                // Check if this is a complex expression that needs lazy computation
                const is_complex = switch (assign.value.*) {
                    .constant, .name => false, // Simple - can use pub const
                    .tuple => |t| blk: {
                        for (t.elts) |elem| {
                            if (elem != .constant and elem != .name) break :blk true;
                        }
                        break :blk false;
                    },
                    .list => |l| blk: {
                        for (l.elts) |elem| {
                            if (elem != .constant and elem != .name) break :blk true;
                        }
                        break :blk false;
                    },
                    else => true, // All other expressions need lazy computation
                };

                if (is_complex) {
                    // Check if this is a list comprehension with lambda elements
                    var is_closure_list = false;
                    var closure_type_idx: ?usize = null;

                    if (assign.value.* == .listcomp) {
                        const lc = assign.value.listcomp;
                        if (lc.elt.* == .lambda) {
                            is_closure_list = true;
                            closure_type_idx = next_closure_type_idx;
                            next_closure_type_idx += 1;

                            // Add to var_renames so subsequent attributes can reference via method call
                            const lazy_call = try std.fmt.allocPrint(self.allocator, "(try {s}(__alloc))", .{attr_name});
                            try self.var_renames.put(attr_name, lazy_call);

                            try self.closure_list_vars.put(attr_name, {});
                            try self.closure_list_vars.put(lazy_call, {});
                        }
                    }

                    // Store for lazy method generation inside the struct
                    try lazy_attrs.put(attr_name, .{
                        .value = assign.value,
                        .is_closure_list = is_closure_list,
                        .closure_type_idx = closure_type_idx,
                    });

                    // Track this lazy attr for attribute access transformation
                    // When we see C.attr, we'll generate (try C.attr(__alloc)) instead
                    const lazy_key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class.name, attr_name });
                    try self.lazy_class_attrs.put(lazy_key, {});

                    // Also register in class_type_attrs so self.attr becomes @This().attr(__alloc)
                    try self.class_type_attrs.put(lazy_key, "__lazy__");

                    // Add to var_renames so subsequent attributes can reference via method call
                    // e.g., `items` becomes `try items(__alloc)` when referenced
                    if (!is_closure_list) {
                        const lazy_call = try std.fmt.allocPrint(self.allocator, "(try {s}(__alloc))", .{attr_name});
                        try self.var_renames.put(attr_name, lazy_call);
                    }
                } else {
                    // Simple constant - register in class_type_attrs for self.attr -> @This().attr
                    const const_key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class.name, attr_name });
                    try self.class_type_attrs.put(const_key, "__const__");
                }
            }
        }
    }

    // Pre-hoist pass 0: Generate class-body-level nested classes at FILE LEVEL
    // These must be generated BEFORE the parent struct so they can be referenced from anywhere
    // e.g., class Outer: class Inner: ... (Inner needs to be accessible from child classes)
    for (class.body) |stmt| {
        if (stmt == .class_def) {
            const nested_class = stmt.class_def;

            // Generate mangled name: Outer__Inner
            const mangled_name = try std.fmt.allocPrint(self.allocator, "{s}__{s}", .{ class.name, nested_class.name });

            // Track mapping for later resolution (e.g., Inner -> Outer__Inner)
            try self.nested_class_aliases.put(nested_class.name, mangled_name);
            try self.nested_class_names.put(nested_class.name, {});

            // Skip if already generated
            if (self.hoisted_local_classes.contains(nested_class.name)) continue;
            if (self.class_registry.getClass(mangled_name) != null) continue;

            // Mark as hoisted with the mangled name
            try self.hoisted_local_classes.put(nested_class.name, mangled_name);

            // Generate nested class at file level with mangled name
            var mutable_nested = nested_class;
            mutable_nested.name = mangled_name;

            // Generate comment for clarity
            try self.emit("\n");
            try self.emitIndent();
            try self.output.writer(self.allocator).print("// Nested class: {s}.{s} (hoisted to file level as {s})\n", .{ class.name, nested_class.name, mangled_name });

            try genClassDef(self, mutable_nested);

            // Register in class registry with mangled name
            try self.class_registry.registerClass(mangled_name, nested_class);
        }
    }

    // Generate: const ClassName = struct {
    // Use pub const for top-level classes in module mode so they're accessible from importers
    try self.emitIndent();
    const pub_prefix: []const u8 = if (self.mode == .module and self.indent_level == 0) "pub " else "";
    try self.output.writer(self.allocator).print("{s}const {s} = struct {{\n", .{ pub_prefix, effective_class_name });
    self.indent();

    // Add Python class introspection attributes
    try self.emitIndent();
    try self.emit("// Python class metadata\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("pub const __name__: []const u8 = \"{s}\";\n", .{class.name});
    try self.emitIndent();
    // Extract docstring from first statement if it's a string literal
    // String values include Python quotes, so we strip them and escape for Zig
    const raw_docstring: ?[]const u8 = blk: {
        if (class.body.len > 0) {
            const first_stmt = class.body[0];
            if (first_stmt == .expr_stmt) {
                if (first_stmt.expr_stmt.value.* == .constant) {
                    if (first_stmt.expr_stmt.value.constant.value == .string) {
                        break :blk first_stmt.expr_stmt.value.constant.value.string;
                    }
                }
            }
        }
        break :blk null;
    };
    if (raw_docstring) |raw| {
        // Strip Python quotes: """...""" or '''...''' or "..." or '...'
        const doc = if (raw.len >= 6 and (std.mem.startsWith(u8, raw, "\"\"\"") or std.mem.startsWith(u8, raw, "'''")))
            raw[3 .. raw.len - 3]
        else if (raw.len >= 2)
            raw[1 .. raw.len - 1]
        else
            raw;
        // Write escaped docstring
        try self.emit("pub const __doc__: ?[]const u8 = \"");
        for (doc) |c| {
            switch (c) {
                '"' => try self.emit("\\\""),
                '\\' => try self.emit("\\\\"),
                '\n' => try self.emit("\\n"),
                '\r' => try self.emit("\\r"),
                '\t' => try self.emit("\\t"),
                else => try self.output.append(self.allocator, c),
            }
        }
        try self.emit("\";\n");
    } else {
        try self.emit("pub const __doc__: ?[]const u8 = null;\n");
    }

    // Generate __bases_vtables__ for Python rich comparison protocol subclass priority
    // This is used by PyValue.eql/lt/le/gt/ge to check if right operand is a subclass
    // and call its method first (Python's comparison protocol)
    try self.emitIndent();
    if (class.bases.len > 0) {
        // Filter out builtin types and generate vtable references for user-defined classes
        var valid_base_count: usize = 0;
        for (class.bases) |base_name| {
            // Skip builtin types that don't have vtables (int, float, str, etc.)
            if (getBuiltinBaseInfo(base_name) != null) continue;
            if (getComplexParentInfo(base_name) != null) continue;
            // Skip ABCMeta and type metaclasses
            if (std.mem.eql(u8, base_name, "ABCMeta")) continue;
            if (std.mem.eql(u8, base_name, "type")) continue;
            // Skip Python's base object type (implicit base for all classes)
            if (std.mem.eql(u8, base_name, "object")) continue;
            // Skip module-qualified names that contain dots for now (e.g., abc.ABCMeta)
            if (std.mem.indexOf(u8, base_name, ".") != null) continue;
            // Skip exception base classes (they're runtime types, not user classes)
            if (std.mem.eql(u8, base_name, "Exception")) continue;
            if (std.mem.eql(u8, base_name, "BaseException")) continue;
            if (std.mem.endsWith(u8, base_name, "Error")) continue;
            valid_base_count += 1;
        }

        if (valid_base_count > 0) {
            // Generate: pub const __bases_vtables__: []const *const runtime.PyValue.PyObjectVTable = &.{ &Parent1.__vtable__, &Parent2.__vtable__ };
            // But we need a static array, not a slice, so we generate a comptime block
            try self.emit("pub const __bases_vtables__: []const *const runtime.PyValue.PyObjectVTable = &.{");
            var first = true;
            for (class.bases) |base_name| {
                // Skip builtin types
                if (getBuiltinBaseInfo(base_name) != null) continue;
                if (getComplexParentInfo(base_name) != null) continue;
                if (std.mem.eql(u8, base_name, "ABCMeta")) continue;
                if (std.mem.eql(u8, base_name, "type")) continue;
                if (std.mem.eql(u8, base_name, "object")) continue;
                if (std.mem.indexOf(u8, base_name, ".") != null) continue;
                // Skip exception base classes (they're runtime types, not user classes)
                if (std.mem.eql(u8, base_name, "Exception")) continue;
                if (std.mem.eql(u8, base_name, "BaseException")) continue;
                if (std.mem.endsWith(u8, base_name, "Error")) continue;
                if (!first) try self.emit(", ");
                first = false;
                // Resolve nested class name to its hoisted/aliased name
                const resolved_base_name = self.nested_class_aliases.get(base_name) orelse
                    self.hoisted_local_classes.get(base_name) orelse
                    base_name;
                try self.output.writer(self.allocator).print("&{s}.__vtable__", .{resolved_base_name});
            }
            try self.emit("};\n");
            try self.emitIndent();
            // Also generate the static vtable for this class
            try self.emit("pub const __vtable__: runtime.PyValue.PyObjectVTable = runtime.PyValue.generateVTableForType(@This());\n");
        } else {
            // No valid base classes, just generate a static vtable
            try self.emit("pub const __bases_vtables__: ?[]const *const runtime.PyValue.PyObjectVTable = null;\n");
            try self.emitIndent();
            try self.emit("pub const __vtable__: runtime.PyValue.PyObjectVTable = runtime.PyValue.generateVTableForType(@This());\n");
        }
    } else {
        // No base classes
        try self.emit("pub const __bases_vtables__: ?[]const *const runtime.PyValue.PyObjectVTable = null;\n");
        try self.emitIndent();
        try self.emit("pub const __vtable__: runtime.PyValue.PyObjectVTable = runtime.PyValue.generateVTableForType(@This());\n");
    }

    // __module__ is the module where the class is defined (global __name__)
    // We use @This().__name__ to avoid ambiguity with global __name__
    try self.emit("\n");

    // Set current class name and body early so init() and all methods use @This() for self-references
    // Save previous values for nested class support
    const prev_class_name = self.current_class_name;
    const prev_class_body = self.current_class_body;
    self.current_class_name = class.name;
    self.current_class_body = class.body;
    defer self.current_class_name = prev_class_name;
    defer self.current_class_body = prev_class_body;

    // Clear hoisted_local_classes from previous class (each class has its own hoisted locals)
    // This is needed because sibling classes (e.g., multiple FailingUserDict definitions)
    // each have their own local classes that need to be hoisted independently
    // BUT: Don't clear if we're generating a hoisted class (recursive call from hoisting pass)
    // because that would remove the class from the map before we check is_hoisted at the end
    const is_hoisted_class = self.hoisted_local_classes.contains(class.name);
    if (!is_hoisted_class) {
        self.hoisted_local_classes.clearRetainingCapacity();
    }

    // Note: Class-body-level nested classes are now generated at file level (before struct definition)
    // See "Pre-hoist pass 0" above the struct opening for nested class generation

    // Pre-hoist pass 1: Hoist locally-defined classes from ALL method bodies to struct level
    // This MUST happen BEFORE generating any fields or methods, because Zig requires
    // all const declarations to appear before any pub fn declarations in a struct
    try body.hoistAllLocalClassesFromMethods(self, class);

    // Pre-generate closure types for lazy class attributes at struct level
    // This allows us to reference these types in function signatures without relying on @TypeOf
    {
        var lazy_iter = lazy_attrs.iterator();
        while (lazy_iter.next()) |entry| {
            const info = entry.value_ptr.*;
            if (info.is_closure_list) {
                if (info.closure_type_idx) |idx| {
                    const lc = info.value.listcomp;
                    const lambda = lc.elt.lambda;

                    // Determine capture field name from lambda
                    var capture_name: []const u8 = "i";
                    if (lambda.args.len > 0 and lambda.args[0].default != null) {
                        capture_name = lambda.args[0].name;
                    } else if (lambda.body.* == .name) {
                        capture_name = lambda.body.name.id;
                    }

                    try self.emit("\n");
                    try self.emitIndent();
                    try self.emit("// Closure types for class-level lambda comprehension\n");

                    // Generate: const __ClassCaptureType_N = struct { <capture_name>: i64 };
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("const __ClassCaptureType_{d} = struct {{ ", .{idx});
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), capture_name);
                    try self.emit(": i64 };\n");

                    // Generate: const __ClassClosureImpl_N = struct { fn call(__cap: __ClassCaptureType_N) i64 { ... } };
                    // Need to generate the actual lambda body, replacing capture var with __cap.<capture_name>
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("const __ClassClosureImpl_{d} = struct {{ fn call(__cap: __ClassCaptureType_{d}) i64 {{ return ", .{ idx, idx });

                    // Set up var_rename so capture_name -> __cap.<capture_name>
                    const cap_access = try std.fmt.allocPrint(self.allocator, "__cap.{s}", .{capture_name});
                    try self.var_renames.put(capture_name, cap_access);

                    // Also handle the case where the lambda param has a different name than the default
                    // e.g., lambda i=j: i -> 'i' accesses __cap.i but was captured from 'j'
                    if (lambda.args.len > 0) {
                        const param_name = lambda.args[0].name;
                        if (!std.mem.eql(u8, param_name, capture_name)) {
                            try self.var_renames.put(param_name, cap_access);
                        }
                    }

                    // Generate the lambda body
                    try self.genExpr(lambda.body.*);
                    try self.emit("; } };\n");

                    // Clean up var_renames
                    _ = self.var_renames.swapRemove(capture_name);
                    if (lambda.args.len > 0) {
                        _ = self.var_renames.swapRemove(lambda.args[0].name);
                    }

                    // Generate: const __ClassClosureType_N = runtime.Closure0(...);
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("const __ClassClosureType_{d} = runtime.Closure0(__ClassCaptureType_{d}, i64, __ClassClosureImpl_{d}.call);\n", .{ idx, idx, idx });
                }
            }
        }
    }

    // Check if any classmethod (like __init_subclass__) uses captured vars
    // If so, we need static vars in addition to instance fields
    const has_classmethod_captures = blk: {
        if (captured_vars == null) break :blk false;
        for (class.body) |stmt| {
            if (stmt == .function_def) {
                const method = stmt.function_def;
                const is_implicit_cm = std.mem.eql(u8, method.name, "__init_subclass__") or
                    std.mem.eql(u8, method.name, "__class_getitem__");
                const is_classmethod = signature.hasClassmethodDecorator(method.decorators) or is_implicit_cm;
                if (is_classmethod) break :blk true;
            }
        }
        break :blk false;
    };

    // Add pointer fields for captured outer variables
    if (captured_vars) |vars| {
        // For classmethods that need captured vars, add static vars
        // These are accessible without an instance (unlike instance fields)
        if (has_classmethod_captures) {
            try self.emitIndent();
            try self.emit("// Static captured variables (for classmethod access)\n");
            for (vars) |var_name| {
                try self.emitIndent();
                // Static vars are initialized after struct definition
                try self.output.writer(self.allocator).print("var __static_{s}: *anyopaque = undefined;\n", .{var_name});
            }
            try self.emit("\n");
        }

        try self.emitIndent();
        try self.emit("// Captured outer scope variables (pointers)\n");
        for (vars) |var_name| {
            try self.emitIndent();
            // Look up the actual type of the captured variable from type inferrer
            // If type is known, use that type; otherwise default to i64 (for loop indices etc)
            // Try scoped lookup first (for function-local variables), then fall back to global var_types
            var type_buf = std.ArrayList(u8){};
            const var_type: ?@import("../../../../analysis/native_types/core.zig").NativeType = self.type_inferrer.getScopedVar(var_name) orelse
                self.type_inferrer.var_types.get(var_name);
            // Store captured variable type in TypeInferrer for use in method body type inference
            // This allows inferExpr() to resolve types for captured variables in nested class methods
            if (var_type) |vt| {
                try self.type_inferrer.captured_var_types.put(var_name, vt);
            }
            var zig_type: []const u8 = if (var_type) |vt| blk: {
                vt.toZigType(self.allocator, &type_buf) catch {};
                if (type_buf.items.len > 0) {
                    break :blk type_buf.items;
                }
                break :blk "i64";
            } else "i64";
            defer type_buf.deinit(self.allocator);
            // Fix empty list type: use PyValue for unknown element types (heterogeneous lists)
            if (std.mem.indexOf(u8, zig_type, "std.ArrayList(*runtime.PyObject)") != null) {
                zig_type = "std.ArrayList(runtime.PyValue)";
            }

            // Check if zig_type contains a nested class name (self-referential/recursive types)
            // If so, use *anyopaque instead to avoid "use of undeclared identifier" errors
            // Example: mylist: std.ArrayList(Obj) where Obj is the current class -> use *anyopaque
            var has_nested_class_ref = false;
            if (std.mem.indexOf(u8, zig_type, class.name) != null) {
                has_nested_class_ref = true;
            } else {
                // Also check other nested class names in this scope
                var nc_iter = self.nested_class_names.iterator();
                while (nc_iter.next()) |entry| {
                    if (std.mem.indexOf(u8, zig_type, entry.key_ptr.*) != null) {
                        has_nested_class_ref = true;
                        break;
                    }
                }
            }
            if (has_nested_class_ref) {
                zig_type = "*anyopaque";
            }

            // Check if this captured variable is mutated (via append, extend, etc.)
            // If mutated, use * instead of *const
            var mutation_key_buf: [256]u8 = undefined;
            const mutation_key = std.fmt.bufPrint(&mutation_key_buf, "{s}.{s}", .{ class.name, var_name }) catch var_name;
            const is_mutated = self.mutated_captures.contains(mutation_key);
            const ptr_type: []const u8 = if (is_mutated) "*" else "*const";
            try self.output.writer(self.allocator).print("__captured_{s}: {s} {s},\n", .{ var_name, ptr_type, zig_type });
        }
        try self.emit("\n");
    }

    // For builtin base classes, add the base value field first
    if (builtin_base) |base_info| {
        try self.emitIndent();
        try self.emit("// Base value inherited from builtin type\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("__base_value__: {s},\n", .{base_info.zig_type});
    }

    // For complex parent types (like array.array), add parent fields
    if (complex_parent) |parent_info| {
        try self.emitIndent();
        try self.emit("// Fields inherited from parent type\n");
        for (parent_info.fields) |field| {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("{s}: {s} = {s},\n", .{ field.name, field.zig_type, field.default });
        }
    }

    // Extract fields from __init__ body (self.x = ...)
    // If no __init__, extract from __new__ or parent's __init__ (since they set attributes)
    if (init_method) |init| {
        try body.genClassFields(self, class.name, init);
    } else if (new_method) |new| {
        try body.genClassFields(self, class.name, new);
    } else if (parent_class) |_| {
        // No __init__ - recursively find __init__ in parent chain
        if (findInheritedInit(self, parent_class)) |inherited_init| {
            try body.genClassFields(self, class.name, inherited_init);
        }
    }

    // For unittest classes, also extract fields from setUp method (without adding __dict__ again)
    if (is_unittest_class) {
        if (setUp_method) |setUp| {
            try body.genClassFieldsNoDict(self, class.name, setUp);
        }
    }

    // Fix 35: Generate class-level attribute fields
    // Class attributes like `all_comp_classes = (...)` become struct fields
    try body.genClassAttributeFields(self, class.body);

    // Generate init() method from __init__, __new__, or inherit from parent
    // Priority: __init__ > __new__ > parent __init__ > default
    if (init_method) |init| {
        try body.genInitMethodWithBuiltinBase(self, class.name, init, builtin_base, complex_parent, captured_vars, class.body);
    } else if (new_method) |new| {
        // No __init__ but has __new__ - use __new__'s parameters for init
        try body.genInitMethodFromNew(self, class.name, new, builtin_base, complex_parent, captured_vars, class.body);
    } else if (parent_class) |_| {
        // No __init__ but has parent class - inherit parent's __init__ signature
        // Recursively search the parent chain for __init__
        const parent_init = findInheritedInit(self, parent_class);
        if (parent_init) |pinit| {
            // Use parent's __init__ signature for our init
            try body.genInitMethodWithBuiltinBase(self, class.name, pinit, builtin_base, complex_parent, captured_vars, class.body);
        } else {
            // No __init__ in parent chain, generate default
            try body.genDefaultInitMethodWithBuiltinBase(self, class.name, builtin_base, complex_parent, captured_vars);
        }
    } else {
        // No __init__ or __new__ defined, generate default init method
        try body.genDefaultInitMethodWithBuiltinBase(self, class.name, builtin_base, complex_parent, captured_vars);
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
        const class_name_copy = try self.arena.allocator().dupe(u8, class.name);
        try self.mutable_classes.put(class_name_copy, {});
    }

    // Register class-level callable builtin attributes BEFORE generating methods
    // This includes type constructors (int, str) and functions (enumerate, len, range)
    // so that self.enum(...) or self.int_class(...) can be detected and handled properly
    for (class.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .name) {
                const attr_name = assign.targets[0].name.id;
                if (assign.value.* == .name) {
                    const builtin_name = assign.value.name.id;
                    // Check if this is ANY builtin name (types + functions + constants)
                    if (PythonBuiltinNames.has(builtin_name)) {
                        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class.name, attr_name });
                        try self.class_type_attrs.put(key, builtin_name);
                    }
                }
            }
        }
    }

    // Generate polymorphic return type helper functions (before methods that use them)
    try body.genPolymorphicReturnHelpers(self, class);

    // Generate regular methods (non-__init__)
    try body.genClassMethods(self, class, captured_vars);

    // Generate blocked __bool__/__len__ methods (when assigned to None)
    // Python: __bool__ = None or __len__ = None blocks the method from being called
    for (class.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .name) {
                const attr_name = assign.targets[0].name.id;
                // Check if it's __bool__ = None or __len__ = None
                if (assign.value.* == .constant and assign.value.constant.value == .none) {
                    if (std.mem.eql(u8, attr_name, "__bool__")) {
                        try self.emit("\n");
                        try self.emitIndent();
                        try self.emit("// __bool__ = None - method is blocked\n");
                        try self.emitIndent();
                        try self.emit("pub fn __bool__(_: *const @This()) runtime.PythonError!bool {\n");
                        self.indent();
                        try self.emitIndent();
                        try self.emit("return runtime.PythonError.TypeError;\n");
                        self.dedent();
                        try self.emitIndent();
                        try self.emit("}\n");
                    } else if (std.mem.eql(u8, attr_name, "__len__")) {
                        try self.emit("\n");
                        try self.emitIndent();
                        try self.emit("// __len__ = None - method is blocked\n");
                        try self.emitIndent();
                        try self.emit("pub fn __len__(_: *const @This()) runtime.PythonError!i64 {\n");
                        self.indent();
                        try self.emitIndent();
                        try self.emit("return runtime.PythonError.TypeError;\n");
                        self.dedent();
                        try self.emitIndent();
                        try self.emit("}\n");
                    }
                }
            }
        }
    }

    // Generate method aliases (e.g., __radd__ = __add__, __rmul__ = __mul__)
    // Python allows assigning one method to another name to create an alias
    for (class.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .name) {
                const alias_name = assign.targets[0].name.id;
                // Check if value is a name referencing another method
                if (assign.value.* == .name) {
                    const target_method = assign.value.name.id;
                    // Check if target is actually a method in this class
                    var is_method = false;
                    for (class.body) |method_stmt| {
                        if (method_stmt == .function_def and
                            std.mem.eql(u8, method_stmt.function_def.name, target_method))
                        {
                            is_method = true;
                            break;
                        }
                    }
                    if (is_method) {
                        // Generate an alias method that delegates to the target
                        try self.emit("\n");
                        try self.emitIndent();
                        try self.output.writer(self.allocator).print("// {s} = {s} (method alias)\n", .{ alias_name, target_method });
                        try self.emitIndent();
                        // Escape both alias and target if they're Zig keywords (e.g., union, error)
                        try self.emit("pub const ");
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), alias_name);
                        try self.emit(" = ");
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), target_method);
                        try self.emit(";\n");
                    }
                }
            }
        }
    }

    // Generate code for class-level type attributes (e.g., int_class = int)
    // Registration already done earlier, now just generate the function code
    for (class.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .name) {
                const attr_name = assign.targets[0].name.id;
                // Check if the value is a type reference (int, float, str, etc.)
                if (assign.value.* == .name) {
                    const type_name = assign.value.name.id;
                    if (PyBuiltinTypes.has(type_name)) {
                        try self.emit("\n");
                        try self.emitIndent();
                        try self.emit("// Class-level type attribute\n");
                        try self.emitIndent();
                        // For int type, support optional base parameter: int(value, base=None)
                        if (std.mem.eql(u8, type_name, "int")) {
                            try self.emit("pub fn ");
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
                            try self.emit("(value: anytype, base: ?i64) i64 {\n");
                            self.indent();
                            try self.emitIndent();
                            try self.emit("if (base) |b| {\n");
                            self.indent();
                            try self.emitIndent();
                            try self.emit("// Parse string with specified base\n");
                            try self.emitIndent();
                            try self.emit("const str = runtime.pyStrFromAny(value);\n");
                            try self.emitIndent();
                            try self.emit("return std.fmt.parseInt(i64, str, @intCast(b)) catch 0;\n");
                            self.dedent();
                            try self.emitIndent();
                            try self.emit("}\n");
                            try self.emitIndent();
                            try self.emit("return runtime.pyIntFromAny(value);\n");
                        } else if (std.mem.eql(u8, type_name, "tuple") or std.mem.eql(u8, type_name, "list")) {
                            // tuple/list: return the input as-is (already a slice/tuple)
                            try self.emit("pub fn ");
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
                            try self.emit("(value: anytype) @TypeOf(value) {\n");
                            self.indent();
                            try self.emitIndent();
                            try self.emit("return value;\n");
                        } else if (std.mem.eql(u8, type_name, "str")) {
                            // str: convert to string
                            try self.emit("pub fn ");
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
                            try self.emit("(value: anytype) []const u8 {\n");
                            self.indent();
                            try self.emitIndent();
                            try self.emit("return runtime.pyStrFromAny(value);\n");
                        } else if (std.mem.eql(u8, type_name, "float")) {
                            // float: convert to f64
                            try self.emit("pub fn ");
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
                            try self.emit("(value: anytype) f64 {\n");
                            self.indent();
                            try self.emitIndent();
                            try self.emit("return runtime.pyFloatFromAny(value);\n");
                        } else if (std.mem.eql(u8, type_name, "bool")) {
                            // bool: convert to bool
                            try self.emit("pub fn ");
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
                            try self.emit("(value: anytype) bool {\n");
                            self.indent();
                            try self.emitIndent();
                            try self.emit("return runtime.pyTruthy(value);\n");
                        } else {
                            // Default fallback: convert to i64
                            try self.emit("pub fn ");
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
                            try self.emit("(value: anytype) i64 {\n");
                            self.indent();
                            try self.emitIndent();
                            try self.emit("return runtime.pyIntFromAny(value);\n");
                        }
                        self.dedent();
                        try self.emitIndent();
                        try self.emit("}\n");
                    }
                }
            }
        }
    }

    // Generate class-level value attributes (e.g., items = [...], y = x + 1)
    // Simple constants become pub const fields directly.
    // Complex expressions were pre-generated before the struct - reference them here.
    for (class.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .name) {
                const attr_name = assign.targets[0].name.id;

                // Skip type attributes (handled above as functions)
                if (assign.value.* == .name) {
                    const type_name = assign.value.name.id;
                    if (PyBuiltinTypes.has(type_name)) continue;
                }

                // Skip None attributes (handled below as stub methods)
                if (assign.value.* == .constant and assign.value.constant.value == .none) continue;

                // Skip private/dunder attributes (usually handled specially)
                if (std.mem.startsWith(u8, attr_name, "__")) continue;

                // Skip attributes that have the same name as a method in this class
                // In Python, later definitions shadow earlier ones (method takes precedence)
                var attr_has_method_conflict = false;
                for (class.body) |check_stmt| {
                    if (check_stmt == .function_def) {
                        if (std.mem.eql(u8, check_stmt.function_def.name, attr_name)) {
                            attr_has_method_conflict = true;
                            break;
                        }
                    }
                }
                if (attr_has_method_conflict) continue;

                // Check if this needs lazy computation (complex expression)
                if (lazy_attrs.get(attr_name)) |info| {
                    const value_node = info.value;

                    // Generate lazy-computed method with threadlocal caching
                    // This overcomes Zig's limitation where structs can't capture outer scope
                    try self.emit("\n");
                    try self.emitIndent();
                    try self.emit("// Class-level attribute (lazy-computed)\n");

                    // For closure lists, use the pre-generated struct-level closure type
                    // For other expressions, we need to handle type inference differently
                    if (info.is_closure_list) {
                        if (info.closure_type_idx) |idx| {
                            // Generate: threadlocal var __<attr>_cache: ?std.ArrayListUnmanaged(__ClassClosureType_N) = null;
                            try self.emitIndent();
                            try self.output.writer(self.allocator).print("threadlocal var __{s}_cache: ?std.ArrayListUnmanaged(__ClassClosureType_{d}) = null;\n", .{ attr_name, idx });

                            // Generate: pub fn <attr>(__alloc: std.mem.Allocator) !std.ArrayListUnmanaged(__ClassClosureType_N)
                            try self.emitIndent();
                            try self.emit("pub fn ");
                            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
                            try self.output.writer(self.allocator).print("(__alloc: std.mem.Allocator) !std.ArrayListUnmanaged(__ClassClosureType_{d}) {{\n", .{idx});
                            self.indent();

                            // Check cache
                            try self.emitIndent();
                            try self.output.writer(self.allocator).print("if (__{s}_cache) |cached| return cached;\n", .{attr_name});

                            // CRITICAL: Re-populate var_renames with ALL lazy attr mappings
                            var lazy_iter = lazy_attrs.iterator();
                            while (lazy_iter.next()) |entry| {
                                const lazy_call = try std.fmt.allocPrint(self.allocator, "(try {s}(__alloc))", .{entry.key_ptr.*});
                                try self.var_renames.put(entry.key_ptr.*, lazy_call);
                            }

                            // Generate the list comprehension manually using struct-level closure types
                            // Instead of genExpr which would generate inline closure types
                            const lc = value_node.listcomp;
                            const lambda = lc.elt.lambda;

                            // Determine capture field name
                            var capture_name: []const u8 = "i";
                            if (lambda.args.len > 0 and lambda.args[0].default != null) {
                                capture_name = lambda.args[0].name;
                            } else if (lambda.body.* == .name) {
                                capture_name = lambda.body.name.id;
                            }

                            // Get the first generator
                            if (lc.generators.len > 0) {
                                const gen = lc.generators[0];

                                try self.emitIndent();
                                try self.output.writer(self.allocator).print("var __result = std.ArrayListUnmanaged(__ClassClosureType_{d}){{}};\n", .{idx});

                                // Generate loop
                                try self.emitIndent();
                                try self.emit("var __loop_var: i64 = 0;\n");
                                try self.emitIndent();
                                try self.emit("while (__loop_var < ");
                                // Get upper bound from range(N)
                                if (gen.iter.* == .call and gen.iter.call.func.* == .name) {
                                    if (std.mem.eql(u8, gen.iter.call.func.name.id, "range")) {
                                        if (gen.iter.call.args.len > 0) {
                                            try self.genExpr(gen.iter.call.args[0]);
                                        } else {
                                            try self.emit("0");
                                        }
                                    } else {
                                        try self.emit("0");
                                    }
                                } else {
                                    try self.emit("0");
                                }
                                try self.emit(") {\n");
                                self.indent();
                                try self.emitIndent();
                                try self.emit("defer __loop_var += 1;\n");
                                try self.emitIndent();
                                try self.output.writer(self.allocator).print("try __result.append(__alloc, __ClassClosureType_{d}{{ .captures = .{{ .{s} = __loop_var }} }});\n", .{ idx, capture_name });
                                self.dedent();
                                try self.emitIndent();
                                try self.emit("}\n");
                            }

                            // Cache and return
                            try self.emitIndent();
                            try self.output.writer(self.allocator).print("__{s}_cache = __result;\n", .{attr_name});
                            try self.emitIndent();
                            try self.emit("return __result;\n");

                            self.dedent();
                            try self.emitIndent();
                            try self.emit("}\n");
                        }
                    } else {
                        // Non-closure-list complex expressions - use type inference from AST

                        // Special case: comprehension iterating over a closure list and calling the closures
                        // e.g., y = [x() for x in items] where items is a closure list
                        // The result type is std.ArrayListUnmanaged(i64) (closure return type)
                        var zig_type: []const u8 = "i64";

                        if (value_node.* == .listcomp) {
                            const lc = value_node.listcomp;
                            // Check if element is a call to the loop variable
                            if (lc.elt.* == .call and lc.elt.call.func.* == .name) {
                                if (lc.generators.len > 0) {
                                    const gen = lc.generators[0];
                                    if (gen.target.* == .name) {
                                        const loop_var = gen.target.name.id;
                                        // Check if iterating over a lazy attr that's a closure list
                                        if (gen.iter.* == .name) {
                                            const iter_name = gen.iter.name.id;
                                            if (self.closure_list_vars.contains(iter_name)) {
                                                // y = [x() for x in items] -> ArrayListUnmanaged(i64)
                                                if (std.mem.eql(u8, lc.elt.call.func.name.id, loop_var)) {
                                                    zig_type = "std.ArrayListUnmanaged(i64)";
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // If not a special case, use type inference
                        if (std.mem.eql(u8, zig_type, "i64")) {
                            const expr_type = try self.inferExprScoped(value_node.*);
                            var type_buf = std.ArrayList(u8){};
                            try expr_type.toZigType(self.allocator, &type_buf);
                            if (type_buf.items.len > 0) {
                                zig_type = type_buf.items;
                            }
                        }

                        // Generate: threadlocal var __<attr>_cache: ?<type> = null;
                        try self.emitIndent();
                        try self.output.writer(self.allocator).print("threadlocal var __{s}_cache: ?{s} = null;\n", .{ attr_name, zig_type });

                        // Generate: pub fn <attr>(__alloc: std.mem.Allocator) !<type>
                        try self.emitIndent();
                        try self.emit("pub fn ");
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
                        try self.output.writer(self.allocator).print("(__alloc: std.mem.Allocator) !{s} {{\n", .{zig_type});
                        self.indent();

                        // Discard allocator if unused (some lazy attrs don't need allocation)
                        try self.emitIndent();
                        try self.emit("_ = __alloc;\n");

                        // Check cache
                        try self.emitIndent();
                        try self.output.writer(self.allocator).print("if (__{s}_cache) |cached| return cached;\n", .{attr_name});

                        // CRITICAL: Re-populate var_renames with ALL lazy attr mappings
                        var lazy_iter = lazy_attrs.iterator();
                        while (lazy_iter.next()) |entry| {
                            const lazy_call = try std.fmt.allocPrint(self.allocator, "(try {s}(__alloc))", .{entry.key_ptr.*});
                            try self.var_renames.put(entry.key_ptr.*, lazy_call);
                        }

                        // Compute value
                        try self.emitIndent();
                        try self.emit("const __result = ");
                        try self.genExpr(value_node.*);
                        try self.emit(";\n");

                        // Cache and return
                        try self.emitIndent();
                        try self.output.writer(self.allocator).print("__{s}_cache = __result;\n", .{attr_name});
                        try self.emitIndent();
                        try self.emit("return __result;\n");

                        self.dedent();
                        try self.emitIndent();
                        try self.emit("}\n");
                    }
                } else {
                    // Simple constant - emit directly as pub const
                    try self.emit("\n");
                    try self.emitIndent();
                    try self.emit("// Class-level attribute\n");
                    try self.emitIndent();
                    try self.emit("pub const ");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
                    try self.emit(" = ");
                    try self.genExpr(assign.value.*);
                    try self.emit(";\n");
                }
            }
        }
    }

    // Generate stub methods for attributes set to None (e.g., __iadd__ = None)
    // These stub methods raise TypeError at runtime, matching Python's behavior
    for (class.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .name) {
                const attr_name = assign.targets[0].name.id;
                // Check if assigned to None
                // Skip __bool__ and __len__ as they are handled specially above
                if (assign.value.* == .constant and assign.value.constant.value == .none and
                    !std.mem.eql(u8, attr_name, "__bool__") and
                    !std.mem.eql(u8, attr_name, "__len__")) {
                    // Generate a stub method that raises TypeError
                    // Nested classes use pointer return types
                    const is_nested = self.nested_class_names.contains(class.name);
                    try self.emit("\n");
                    try self.emitIndent();
                    if (is_nested) {
                        try self.emit("pub fn ");
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
                        try self.emit("(_: *const @This(), _: std.mem.Allocator, _: anytype) !*@This() {\n");
                    } else {
                        try self.emit("pub fn ");
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr_name);
                        try self.emit("(_: *const @This(), _: std.mem.Allocator, _: anytype) !@This() {\n");
                    }
                    self.indent();
                    try self.emitIndent();
                    try self.emit("return error.TypeError; // 'NoneType' object is not callable\n");
                    self.dedent();
                    try self.emitIndent();
                    try self.emit("}\n");
                }
            }
        }
    }

    // Inherit parent methods that aren't overridden
    // NOTE: This must happen BEFORE the restore, because genInheritedMethods calls
    // genMethodBodyWithAllocatorInfo which clears func_local_uses
    if (parent_class) |parent| {
        try body.genInheritedMethods(self, class, parent, child_method_names.items);
    }

    // For classes with metaclass=ABCMeta, generate register() method
    // register(cls) is used to register virtual subclasses - we make it a no-op
    if (class.metaclass) |mc| {
        if (std.mem.eql(u8, mc, "ABCMeta")) {
            try self.emit("\n");
            try self.emitIndent();
            try self.emit("// ABCMeta.register - register virtual subclass (no-op for AOT)\n");
            try self.emitIndent();
            try self.emit("pub fn register(_: anytype) void {}\n");
        }
    }

    // Restore func_local_uses from saved state (for nested classes)
    // This is critical: nested class methods call analyzeFunctionLocalUses which clears
    // the map. We need to restore the parent scope's uses so isVarUnused() works correctly.
    if (needs_save_restore) {
        self.func_local_uses.clearRetainingCapacity();
        var restore_it = saved_func_local_uses.iterator();
        while (restore_it.next()) |entry| {
            try self.func_local_uses.put(entry.key_ptr.*, {});
        }

        // Also restore func_local_mutations so parent method's var/const decisions are correct
        self.func_local_mutations.clearRetainingCapacity();
        var restore_mut_it = saved_func_local_mutations.iterator();
        while (restore_mut_it.next()) |entry| {
            try self.func_local_mutations.put(entry.key_ptr.*, {});
        }

        // Also restore func_local_aug_assigns for shadow variable decisions
        self.func_local_aug_assigns.clearRetainingCapacity();
        var restore_aug_it = saved_func_local_aug_assigns.iterator();
        while (restore_aug_it.next()) |entry| {
            try self.func_local_aug_assigns.put(entry.key_ptr.*, {});
        }

        // Also restore nested_class_names so parent method's class tracking works correctly
        // (e.g., MyIndexable used after this nested class definition completes)
        self.nested_class_names.clearRetainingCapacity();
        var restore_ncn_it = saved_nested_class_names.iterator();
        while (restore_ncn_it.next()) |entry| {
            try self.nested_class_names.put(entry.key_ptr.*, {});
        }

        // Also restore nested_class_bases for base class default args
        self.nested_class_bases.clearRetainingCapacity();
        var restore_ncb_it = saved_nested_class_bases.iterator();
        while (restore_ncb_it.next()) |entry| {
            try self.nested_class_bases.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Also restore nested_class_defs for nested class inheritance
        self.nested_class_defs.clearRetainingCapacity();
        var restore_ncd_it = saved_nested_class_defs.iterator();
        while (restore_ncd_it.next()) |entry| {
            try self.nested_class_defs.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Also restore nested_class_captures for passing captured vars to init
        self.nested_class_captures.clearRetainingCapacity();
        var restore_ncc_it = saved_nested_class_captures.iterator();
        while (restore_ncc_it.next()) |entry| {
            try self.nested_class_captures.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Also restore hoisted_vars so parent method's hoisted variable tracking works correctly
        // (e.g., `resizing` hoisted in test_resize2, used after nested class X is generated)
        self.hoisted_vars.clearRetainingCapacity();
        var restore_hv_it = saved_hoisted_vars.iterator();
        while (restore_hv_it.next()) |entry| {
            try self.hoisted_vars.put(entry.key_ptr.*, {});
        }
    } else {
        // For top-level classes, clear func_local_uses after generating methods
        // Class methods populate func_local_uses during analysis, but these should
        // NOT be visible at module level (where _ = &ClassName; would be invalid)
        self.func_local_uses.clearRetainingCapacity();
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // Initialize static captured vars for classmethod access
    // This MUST be done after the struct definition but before the class is used
    if (has_classmethod_captures) {
        if (captured_vars) |vars| {
            for (vars) |var_name| {
                try self.emitIndent();
                // Use @ptrCast to convert the typed pointer to *anyopaque
                try self.output.writer(self.allocator).print("{s}.__static_{s} = @ptrCast(&{s});\n", .{ effective_class_name, var_name, var_name });
            }
        }
    }

    // For nested classes (inside functions/methods), emit _ = &ClassName; immediately
    // to suppress "unused local constant" errors. We use & (address-of) to avoid
    // "pointless discard" errors when the class IS actually used elsewhere.
    // This must be done here (not at end of function) because classes inside
    // if/for/while blocks are out of scope at function end.
    // NOTE: Only emit when actually inside a function body (func_local_uses > 0),
    // not when inside a class body at class-level scope. The _ = &X; statement
    // is only valid inside function bodies, not at struct level.
    // - Nested classes at class-level (e.g., class Outer: class Inner: ...) don't need this
    // - Nested classes inside methods DO need this
    const is_hoisted = self.hoisted_local_classes.contains(class.name);
    const is_inside_function_body = self.func_local_uses.count() > 0;
    if (is_inside_function_body and self.indent_level > 0 and !is_hoisted) {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("_ = &{s};\n", .{effective_class_name});
    }

    // Declare the class name in current scope to detect redefinitions
    try self.declareVar(effective_class_name);

    // For nested classes inside functions, emit _ = BaseName; for local class bases
    // This is needed because Python base classes don't generate Zig struct references -
    // the inheritance is structural (copying methods), not referential
    // e.g., "class F(float, H)" doesn't reference H in Zig, so H appears "unused"
    // BUT: Only emit if the base class is truly unused (not referenced elsewhere in the function)
    // NOTE: Only do this inside actual function bodies, not class-level scope
    if (is_inside_function_body and self.indent_level > 0) {
        for (class.bases) |base_name| {
            // Skip builtin types (int, float, str, etc.)
            if (getBuiltinBaseInfo(base_name) != null) continue;
            if (getComplexParentInfo(base_name) != null) continue;
            // Skip unittest.TestCase and similar
            if (std.mem.indexOf(u8, base_name, ".") != null) continue;
            // Skip Exception bases
            if (std.mem.endsWith(u8, base_name, "Error") or std.mem.endsWith(u8, base_name, "Exception")) continue;
            // Skip if base is used elsewhere in the function (not just as a base class)
            if (!self.isVarUnused(base_name)) continue;
            // This is likely a local class used as a base - emit _ = X; to prevent unused warning
            // Only emit if the base is in nested_class_names (i.e., defined in this scope)
            if (self.nested_class_names.contains(base_name)) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print("_ = {s};\n", .{base_name});
            }
        }
    }

    // NOTE: We do NOT emit _ = ClassName; here anymore.
    // Instead, we defer unused class suppression to the end of function body.
    // This is necessary because:
    // 1. Classes may be used later in the same scope (e.g., class D defined before being referenced)
    // 2. Classes may be used in Python statements that don't translate to Zig
    // See function_gen.zig emitNestedClassUnusedSuppression() for the deferred emit logic.
}

/// Generate Generic[T, U, ...] class as a comptime generic function
/// Python: class Box(Generic[T]): def __init__(self, value: T): self.value = value
/// Zig: fn Box(comptime T: type) type { return struct { value: T, ... }; }
fn genGenericClassDef(self: *NativeCodegen, class: ast.Node.ClassDef) CodegenError!void {
    // Register this as a generic class for instantiation handling
    try self.generic_classes.put(class.name, class.type_params.len);

    // Store type params for use in type resolution
    for (class.type_params) |tp| {
        try self.generic_type_params.put(tp, {});
    }
    defer {
        for (class.type_params) |tp| {
            _ = self.generic_type_params.swapRemove(tp);
        }
    }

    // Generate function header: fn ClassName(comptime T: type, comptime U: type) type {
    // IMPORTANT: Zig doesn't allow function definitions inside function bodies.
    // For nested generic classes inside functions, emit a simple struct instead.
    const inside_function = self.current_function_name != null or self.indent_level > 0;
    if (inside_function) {
        // Check for name collision with module-level classes
        var effective_name: []const u8 = class.name;
        if (self.class_registry.getClass(class.name) != null or self.isDeclared(class.name)) {
            effective_name = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ class.name, @intFromPtr(class.name.ptr) });
            try self.var_renames.put(class.name, effective_name);
        }
        // Nested generic class - just emit as a simple struct
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{effective_name});
        self.indent();

        // Add Python class metadata
        try self.emitIndent();
        try self.emit("// Python class metadata\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("pub const __name__: []const u8 = \"{s}\";\n", .{class.name});
        try self.emitIndent();
        try self.emit("pub const __doc__: ?[]const u8 = null;\n\n");

        try self.emitIndent();
        try self.emit("pub fn init() !@This() {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("return @This(){};\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");

        self.dedent();
        try self.emitIndent();
        try self.emit("};\n");
        return;
    }

    try self.emitIndent();
    const pub_prefix: []const u8 = if (self.mode == .module and self.indent_level == 0) "pub " else "";
    try self.output.writer(self.allocator).print("{s}fn {s}(", .{ pub_prefix, class.name });

    // Generate comptime type params
    for (class.type_params, 0..) |tp, i| {
        if (i > 0) try self.emit(", ");
        try self.output.writer(self.allocator).print("comptime {s}: type", .{tp});
    }
    try self.emit(") type {\n");
    self.indent();

    try self.emitIndent();
    try self.emit("return struct {\n");
    self.indent();

    // Set current class name and body for method generation
    const prev_class_name = self.current_class_name;
    const prev_class_body = self.current_class_body;
    self.current_class_name = class.name;
    self.current_class_body = class.body;
    defer self.current_class_name = prev_class_name;
    defer self.current_class_body = prev_class_body;

    // Add Python class introspection attributes
    try self.emitIndent();
    try self.emit("// Python class metadata\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("pub const __name__: []const u8 = \"{s}\";\n", .{class.name});
    try self.emitIndent();
    try self.emit("pub const __doc__: ?[]const u8 = null;\n\n");

    // Find __init__ method for field extraction
    var init_method: ?ast.Node.FunctionDef = null;
    for (class.body) |stmt| {
        if (stmt == .function_def and std.mem.eql(u8, stmt.function_def.name, "__init__")) {
            init_method = stmt.function_def;
            break;
        }
    }

    // Extract fields from __init__ body (self.x = ...) with generic type resolution
    if (init_method) |init| {
        try genGenericClassFields(self, init, class.type_params);
    }

    // Generate init() method
    if (init_method) |init| {
        try genGenericInitMethod(self, init, class.type_params);
    } else {
        // Default init method - returns error union for consistency
        try self.emitIndent();
        try self.emit("pub fn init() !@This() {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("return @This(){};\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    // Generate regular methods (non-__init__)
    for (class.body) |stmt| {
        if (stmt == .function_def) {
            const method = stmt.function_def;
            if (std.mem.eql(u8, method.name, "__init__")) continue;
            try self.emit("\n");
            try genGenericMethod(self, method, class.type_params);
        }
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate fields for generic class
fn genGenericClassFields(self: *NativeCodegen, init: ast.Node.FunctionDef, type_params: [][]const u8) CodegenError!void {
    for (init.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                const attr = assign.targets[0].attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                    const field_name = attr.attr;
                    // Determine field type from init parameter annotation
                    var field_type: []const u8 = "i64"; // default
                    for (init.args) |arg| {
                        if (std.mem.eql(u8, arg.name, "self")) continue;
                        // Check if this param is assigned to this field
                        if (assign.value.* == .name and std.mem.eql(u8, assign.value.name.id, arg.name)) {
                            if (arg.type_annotation) |ann| {
                                // Check if annotation is a type param
                                for (type_params) |tp| {
                                    if (std.mem.eql(u8, ann, tp)) {
                                        field_type = tp;
                                        break;
                                    }
                                }
                            }
                            break;
                        }
                    }
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print("{s}: {s},\n", .{ field_name, field_type });
                }
            }
        }
    }
}

/// Generate init method for generic class
fn genGenericInitMethod(self: *NativeCodegen, init: ast.Node.FunctionDef, type_params: [][]const u8) CodegenError!void {
    try self.emitIndent();
    try self.emit("pub fn init(");

    // Generate parameters
    var first = true;
    for (init.args) |arg| {
        if (std.mem.eql(u8, arg.name, "self")) continue;
        if (!first) try self.emit(", ");
        first = false;

        // Get parameter type
        var param_type: []const u8 = "i64";
        if (arg.type_annotation) |ann| {
            // Check if annotation is a type param
            for (type_params) |tp| {
                if (std.mem.eql(u8, ann, tp)) {
                    param_type = tp;
                    break;
                }
            }
        }
        try self.output.writer(self.allocator).print("{s}: {s}", .{ arg.name, param_type });
    }

    try self.emit(") !@This() {\n");
    self.indent();

    try self.emitIndent();
    try self.emit("return @This(){\n");
    self.indent();

    // Generate field initializations
    for (init.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                const attr = assign.targets[0].attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                    try self.emitIndent();
                    try self.output.writer(self.allocator).print(".{s} = ", .{attr.attr});
                    try self.genExpr(assign.value.*);
                    try self.emit(",\n");
                }
            }
        }
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate a method for generic class
fn genGenericMethod(self: *NativeCodegen, method: ast.Node.FunctionDef, type_params: [][]const u8) CodegenError!void {
    // Set method context so self.field generates correctly
    const prev_inside_method = self.inside_method_with_self;
    self.inside_method_with_self = true;
    defer self.inside_method_with_self = prev_inside_method;

    try self.emitIndent();
    try self.emit("pub fn ");
    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), method.name);
    try self.emit("(");

    // Check if self is used in method body
    var has_self_param = false;
    var self_is_used = false;
    for (method.args) |arg| {
        if (std.mem.eql(u8, arg.name, "self")) {
            has_self_param = true;
            break;
        }
    }
    if (has_self_param) {
        self_is_used = checkSelfUsedInBody(method.body);
    }

    // Generate parameters
    var first = true;
    for (method.args) |arg| {
        if (!first) try self.emit(", ");
        first = false;

        if (std.mem.eql(u8, arg.name, "self")) {
            // Use _ prefix if self is not used
            if (self_is_used) {
                try self.emit("self: *const @This()");
            } else {
                try self.emit("_: *const @This()");
            }
        } else {
            var param_type: []const u8 = "i64";
            if (arg.type_annotation) |ann| {
                for (type_params) |tp| {
                    if (std.mem.eql(u8, ann, tp)) {
                        param_type = tp;
                        break;
                    }
                }
            }
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
            try self.output.writer(self.allocator).print(": {s}", .{param_type});
        }
    }
    try self.emit(") ");

    // Return type
    var return_type: []const u8 = "void";
    if (method.return_type) |rt| {
        for (type_params) |tp| {
            if (std.mem.eql(u8, rt, tp)) {
                return_type = tp;
                break;
            }
        }
    } else {
        // Check for return statements to infer return type
        for (method.body) |stmt| {
            if (stmt == .return_stmt and stmt.return_stmt.value != null) {
                const ret_expr = stmt.return_stmt.value.?;
                if (ret_expr.* == .attribute and ret_expr.attribute.value.* == .name and
                    std.mem.eql(u8, ret_expr.attribute.value.name.id, "self"))
                {
                    // returning self.field - get field type from init
                    // Just use first type param for simplicity if returning a field
                    if (type_params.len > 0) {
                        return_type = type_params[0];
                    }
                }
                break;
            }
        }
    }
    try self.output.writer(self.allocator).print("{s} {{\n", .{return_type});
    self.indent();

    // Generate method body
    for (method.body) |stmt| {
        try self.generateStmt(stmt);
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Check if self is actually used in method body
fn checkSelfUsedInBody(stmts: []ast.Node) bool {
    for (stmts) |stmt| {
        if (checkSelfUsedInNode(stmt)) return true;
    }
    return false;
}

fn checkSelfUsedInNode(node: ast.Node) bool {
    switch (node) {
        .name => |n| return std.mem.eql(u8, n.id, "self"),
        .attribute => |a| return checkSelfUsedInNode(a.value.*),
        .return_stmt => |r| {
            if (r.value) |v| return checkSelfUsedInNode(v.*);
            return false;
        },
        .call => |c| {
            if (checkSelfUsedInNode(c.func.*)) return true;
            for (c.args) |arg| {
                if (checkSelfUsedInNode(arg)) return true;
            }
            return false;
        },
        .binop => |b| return checkSelfUsedInNode(b.left.*) or checkSelfUsedInNode(b.right.*),
        .expr_stmt => |e| return checkSelfUsedInNode(e.value.*),
        // Nested functions - check if they capture 'self'
        .function_def => |f| {
            // Check if self is in captured_vars (populated by closure analysis)
            for (f.captured_vars) |captured| {
                if (std.mem.eql(u8, captured, "self")) return true;
            }
            // Also recurse into body in case there are deeper nested functions
            return checkSelfUsedInBody(f.body);
        },
        .if_stmt => |i| {
            if (checkSelfUsedInNode(i.condition.*)) return true;
            if (checkSelfUsedInBody(i.body)) return true;
            if (checkSelfUsedInBody(i.else_body)) return true;
            return false;
        },
        .for_stmt => |f| {
            if (checkSelfUsedInNode(f.iter.*)) return true;
            if (checkSelfUsedInBody(f.body)) return true;
            if (f.orelse_body) |orelse_body| {
                if (checkSelfUsedInBody(orelse_body)) return true;
            }
            return false;
        },
        .while_stmt => |w| {
            if (checkSelfUsedInNode(w.condition.*)) return true;
            if (checkSelfUsedInBody(w.body)) return true;
            if (w.orelse_body) |orelse_body| {
                if (checkSelfUsedInBody(orelse_body)) return true;
            }
            return false;
        },
        .match_stmt => |m| {
            if (checkSelfUsedInNode(m.subject.*)) return true;
            for (m.cases) |case| {
                if (case.guard) |guard| {
                    if (checkSelfUsedInNode(guard.*)) return true;
                }
                if (checkSelfUsedInBody(case.body)) return true;
            }
            return false;
        },
        .with_stmt => |w| {
            if (checkSelfUsedInNode(w.context_expr.*)) return true;
            return checkSelfUsedInBody(w.body);
        },
        .listcomp => |lc| {
            // Check element expression
            if (checkSelfUsedInNode(lc.elt.*)) return true;
            // Check all generators (iter and conditions)
            for (lc.generators) |gen| {
                if (checkSelfUsedInNode(gen.iter.*)) return true;
                for (gen.ifs) |if_cond| {
                    if (checkSelfUsedInNode(if_cond)) return true;
                }
            }
            return false;
        },
        .dictcomp => |dc| {
            if (checkSelfUsedInNode(dc.key.*)) return true;
            if (checkSelfUsedInNode(dc.value.*)) return true;
            for (dc.generators) |gen| {
                if (checkSelfUsedInNode(gen.iter.*)) return true;
                for (gen.ifs) |if_cond| {
                    if (checkSelfUsedInNode(if_cond)) return true;
                }
            }
            return false;
        },
        .lambda => |lam| {
            // Lambda parameters don't shadow outer self
            return checkSelfUsedInNode(lam.body.*);
        },
        .compare => |cmp| {
            if (checkSelfUsedInNode(cmp.left.*)) return true;
            for (cmp.comparators) |comp| {
                if (checkSelfUsedInNode(comp)) return true;
            }
            return false;
        },
        .subscript => |sub| {
            if (checkSelfUsedInNode(sub.value.*)) return true;
            if (sub.slice == .index) {
                if (checkSelfUsedInNode(sub.slice.index.*)) return true;
            }
            return false;
        },
        .unaryop => |u| return checkSelfUsedInNode(u.operand.*),
        .boolop => |bo| {
            for (bo.values) |v| {
                if (checkSelfUsedInNode(v)) return true;
            }
            return false;
        },
        .if_expr => |ie| {
            return checkSelfUsedInNode(ie.condition.*) or
                checkSelfUsedInNode(ie.body.*) or
                checkSelfUsedInNode(ie.orelse_value.*);
        },
        .tuple => |t| {
            for (t.elts) |elt| {
                if (checkSelfUsedInNode(elt)) return true;
            }
            return false;
        },
        .list => |l| {
            for (l.elts) |elt| {
                if (checkSelfUsedInNode(elt)) return true;
            }
            return false;
        },
        .dict => |d| {
            for (d.keys) |key| {
                if (checkSelfUsedInNode(key)) return true;
            }
            for (d.values) |val| {
                if (checkSelfUsedInNode(val)) return true;
            }
            return false;
        },
        .assign => |a| {
            if (checkSelfUsedInNode(a.value.*)) return true;
            // Check targets for subscript/attribute assignments
            for (a.targets) |target| {
                if (target == .subscript) {
                    if (checkSelfUsedInNode(target.subscript.value.*)) return true;
                } else if (target == .attribute) {
                    if (checkSelfUsedInNode(target.attribute.value.*)) return true;
                }
            }
            return false;
        },
        .aug_assign => |a| {
            if (checkSelfUsedInNode(a.target.*)) return true;
            return checkSelfUsedInNode(a.value.*);
        },
        .try_stmt => |t| {
            if (checkSelfUsedInBody(t.body)) return true;
            for (t.handlers) |h| {
                if (checkSelfUsedInBody(h.body)) return true;
            }
            if (checkSelfUsedInBody(t.else_body)) return true;
            return checkSelfUsedInBody(t.finalbody);
        },
        else => return false,
    }
}

/// Recursively find __init__ method in parent chain
fn findInheritedInit(self: *NativeCodegen, parent_class: ?ast.Node.ClassDef) ?ast.Node.FunctionDef {
    var current = parent_class;
    while (current) |parent| {
        for (parent.body) |stmt| {
            if (stmt == .function_def and std.mem.eql(u8, stmt.function_def.name, "__init__"))
                return stmt.function_def;
        }
        if (parent.bases.len > 0) {
            current = self.class_registry.getClass(parent.bases[0]) orelse self.nested_class_defs.get(parent.bases[0]);
        } else break;
    }
    return null;
}
