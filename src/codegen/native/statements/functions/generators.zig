/// Function and class definition code generation
const std = @import("std");
const ast = @import("ast");
const hashmap_helper = @import("hashmap_helper");
const zig_keywords = @import("zig_keywords");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const DecoratedFunction = @import("../../main.zig").DecoratedFunction;
const CodegenError = @import("../../main.zig").CodegenError;
const function_traits = @import("function_traits");
const signature = @import("generators/signature.zig");
const body = @import("generators/body.zig");
const builtin_types = @import("generators/builtin_types.zig");
const test_skip = @import("generators/test_skip.zig");
const shared = @import("../../shared_maps.zig");
const PyBuiltinTypes = shared.PythonBuiltinTypes;

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
        const func_name_copy = try self.allocator.dupe(u8, func.name);
        try self.functions_needing_allocator.put(func_name_copy, {});
    }

    // Track async functions (for calling with _async suffix)
    if (func.is_async) {
        const func_name_copy = try self.allocator.dupe(u8, func.name);
        try self.async_functions.put(func_name_copy, {});
    }

    // Check if this is a generator function (contains yield)
    // Use function_traits unified analysis
    if (self.funcIsGenerator(func.name)) {
        // TODO: Generate generator state machine when implemented
        // For now, generators fall through to normal function generation
        // with yield statements becoming pass (handled in main/generator.zig)
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

    // Analyze nested class captures BEFORE generating signature
    // This allows genFunctionSignature to know which parameters are "used" via closures
    // The nested_class_captures map is populated here and read in signature.zig
    self.func_local_vars.clearRetainingCapacity();
    self.nested_class_captures.clearRetainingCapacity();
    try body.analyzeNestedClassCaptures(self, func);

    // Generate function signature
    try signature.genFunctionSignature(self, func, needs_allocator);

    // Set current function name for tail-call optimization detection
    self.current_function_name = func.name;

    // Clear local variable types (new function scope)
    self.clearLocalVarTypes();

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
        try self.type_inferrer.var_types.put("self", .{ .class_instance = class.name });
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

                    // Check for decorators that indicate test should be skipped on non-CPython:
                    // 1. @support.cpython_only - tests CPython implementation details
                    // 2. @unittest.skipUnless(_pylong, ...) - requires CPython's _pylong module
                    // 3. @unittest.skipUnless(_decimal, ...) - requires CPython's _decimal module
                    // 4. Parameters with type defaults (cls=float) - requires runtime type manipulation
                    // 5. Calls self.method(ClassName) - passes class as runtime argument
                    // This is NOT us artificially skipping tests - it's respecting Python's own test annotations

                    // Collect all registered class names for type argument detection
                    var class_names_list = std.ArrayList([]const u8){};
                    var classes_iter = self.class_registry.classes.iterator();
                    while (classes_iter.next()) |entry| {
                        try class_names_list.append(self.allocator, entry.key_ptr.*);
                    }
                    const class_names = class_names_list.items;

                    const skip_reason: ?[]const u8 = if (test_skip.hasCPythonOnlyDecorator(method.decorators))
                        "CPython implementation test (not applicable to metal0)"
                    else if (test_skip.hasSkipUnlessCPythonModule(method.decorators))
                        "Requires CPython-only module (_pylong or _decimal)"
                    else if (test_skip.hasSkipIfModuleIsNone(method.decorators, &self.skipped_modules))
                        "Requires unavailable optional module"
                    else if (test_skip.hasTypeParameterDefault(method.args))
                        "Test uses runtime type parameters (cls=float)"
                    else if (test_skip.callsSelfMethodWithClassArg(method.body, class_names))
                        "Test passes class as runtime argument (self.method(ClassName))"
                    else if (test_skip.hasSkipDocstring(method.body))
                        "Marked skip in docstring"
                    else
                        null;

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
        if (self.nested_class_captures.get(class.bases[0])) |parent_captures| {
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
    var effective_class_name: []const u8 = class.name;
    if (self.isDeclared(class.name)) {
        // Generate a unique name based on pointer address
        const unique_name = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ class.name, @intFromPtr(class.name.ptr) });
        effective_class_name = unique_name;
        // Store the rename so references to this class name use the new name
        try self.var_renames.put(class.name, unique_name);
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

    // Add pointer fields for captured outer variables
    if (captured_vars) |vars| {
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
            var zig_type: []const u8 = if (var_type) |vt| blk: {
                vt.toZigType(self.allocator, &type_buf) catch {};
                if (type_buf.items.len > 0) {
                    break :blk type_buf.items;
                }
                break :blk "i64";
            } else "i64";
            defer type_buf.deinit(self.allocator);
            // Fix empty list type: type inferrer may detect PyObject for mixed/string lists
            // Map to appropriate Zig type: PyObject -> []const u8 for string lists
            if (std.mem.indexOf(u8, zig_type, "std.ArrayList(*runtime.PyObject)") != null) {
                // Default to string list since that's the most common case for empty lists with appends
                zig_type = "std.ArrayList([]const u8)";
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

    // Note: Class-level attributes (candidates = set1 + set2) are NOT generated as struct fields
    // They are evaluated at class definition time in Python and stored in class.__dict__
    // For now, we access them via instance.__dict__ with runtime type extraction

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
        const class_name_copy = try self.allocator.dupe(u8, class.name);
        try self.mutable_classes.put(class_name_copy, {});
    }

    // Register class-level type attributes BEFORE generating methods
    // so that self.int_class(...) can be detected and handled properly
    for (class.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .name) {
                const attr_name = assign.targets[0].name.id;
                if (assign.value.* == .name) {
                    const type_name = assign.value.name.id;
                    if (PyBuiltinTypes.has(type_name)) {
                        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class.name, attr_name });
                        try self.class_type_attrs.put(key, type_name);
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
                            try self.emit("_ = base; // TODO: support base conversion\n");
                            try self.emitIndent();
                            try self.emit("return runtime.pyIntFromAny(value);\n");
                        } else {
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
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // For nested classes (inside functions/methods), emit _ = &ClassName; immediately
    // to suppress "unused local constant" errors. We use & (address-of) to avoid
    // "pointless discard" errors when the class IS actually used elsewhere.
    // This must be done here (not at end of function) because classes inside
    // if/for/while blocks are out of scope at function end.
    if (needs_save_restore and self.indent_level > 0) {
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
    if (needs_save_restore and self.indent_level > 0) {
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
        // Nested generic class - just emit as a simple struct
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{class.name});
        self.indent();

        // Add Python class metadata
        try self.emitIndent();
        try self.emit("// Python class metadata\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("pub const __name__: []const u8 = \"{s}\";\n", .{class.name});
        try self.emitIndent();
        try self.emit("pub const __doc__: ?[]const u8 = null;\n\n");

        try self.emitIndent();
        try self.emit("pub fn init() @This() {\n");
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
        // Default init method
        try self.emitIndent();
        try self.emit("pub fn init() @This() {\n");
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

    try self.emit(") @This() {\n");
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
            return checkSelfUsedInBody(f.body);
        },
        .while_stmt => |w| {
            if (checkSelfUsedInNode(w.condition.*)) return true;
            return checkSelfUsedInBody(w.body);
        },
        .with_stmt => |w| {
            if (checkSelfUsedInNode(w.context_expr.*)) return true;
            return checkSelfUsedInBody(w.body);
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
