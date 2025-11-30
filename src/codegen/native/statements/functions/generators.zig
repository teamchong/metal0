/// Function and class definition code generation
const std = @import("std");
const ast = @import("ast");
const hashmap_helper = @import("hashmap_helper");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const DecoratedFunction = @import("../../main.zig").DecoratedFunction;
const CodegenError = @import("../../main.zig").CodegenError;
const allocator_analyzer = @import("allocator_analyzer.zig");
const signature = @import("generators/signature.zig");
const body = @import("generators/body.zig");

/// Builtin types that can be inherited from
pub const BuiltinBaseInfo = struct {
    zig_type: []const u8,
    zig_init: []const u8, // Zig code to initialize the base value
    init_args: []const InitArg, // Arguments for the init function

    pub const InitArg = struct {
        name: []const u8,
        zig_type: []const u8,
        default: ?[]const u8 = null,
    };
};

/// Get builtin base info if the class inherits from a builtin type
pub fn getBuiltinBaseInfo(base_name: []const u8) ?BuiltinBaseInfo {
    const builtin_bases = std.StaticStringMap(BuiltinBaseInfo).initComptime(.{
        .{ "complex", BuiltinBaseInfo{
            .zig_type = "runtime.PyComplex",
            .zig_init = "runtime.PyComplex.create(real, imag)",
            .init_args = &.{
                .{ .name = "real", .zig_type = "f64", .default = "0.0" },
                .{ .name = "imag", .zig_type = "f64", .default = "0.0" },
            },
        } },
        .{ "int", BuiltinBaseInfo{
            .zig_type = "i64",
            .zig_init = "value",
            .init_args = &.{
                .{ .name = "value", .zig_type = "i64", .default = "0" },
            },
        } },
        .{ "float", BuiltinBaseInfo{
            .zig_type = "f64",
            .zig_init = "value",
            .init_args = &.{
                .{ .name = "value", .zig_type = "f64", .default = "0.0" },
            },
        } },
        .{ "str", BuiltinBaseInfo{
            .zig_type = "[]const u8",
            .zig_init = "value",
            .init_args = &.{
                .{ .name = "value", .zig_type = "[]const u8", .default = "\"\"" },
            },
        } },
        .{ "bool", BuiltinBaseInfo{
            .zig_type = "bool",
            .zig_init = "value",
            .init_args = &.{
                .{ .name = "value", .zig_type = "bool", .default = "false" },
            },
        } },
        .{ "bytes", BuiltinBaseInfo{
            .zig_type = "[]const u8",
            .zig_init = "value",
            .init_args = &.{
                .{ .name = "value", .zig_type = "[]const u8", .default = "\"\"" },
            },
        } },
    });

    return builtin_bases.get(base_name);
}

/// Complex parent types with multiple fields (like array.array)
pub const ComplexParentInfo = struct {
    /// Fields to add to child class (in order)
    fields: []const FieldInfo,
    /// Methods inherited from parent (for parent method call resolution)
    methods: []const MethodInfo,
    /// Constructor arguments (for default init generation)
    init_args: []const InitArg,
    /// Zig code to initialize fields from constructor args
    /// Use {alloc} for allocator, {0}, {1}, etc. for init args
    field_init: []const FieldInit,

    pub const FieldInfo = struct {
        name: []const u8,
        zig_type: []const u8,
        default: []const u8,
    };

    pub const MethodInfo = struct {
        name: []const u8,
        /// The Zig code to inline when calling parent.method(self, ...)
        /// Use {self} for the self parameter, {0}, {1}, etc. for other args
        inline_code: []const u8,
    };

    pub const InitArg = struct {
        name: []const u8,
        zig_type: []const u8,
    };

    pub const FieldInit = struct {
        field_name: []const u8,
        /// Zig code to initialize the field, use {0}, {1} for args, {alloc} for allocator
        init_code: []const u8,
    };
};

/// Get complex parent info for module.class patterns (e.g., "array.array")
pub fn getComplexParentInfo(base_name: []const u8) ?ComplexParentInfo {
    const complex_parents = std.StaticStringMap(ComplexParentInfo).initComptime(.{
        .{ "array.array", ComplexParentInfo{
            .fields = &.{
                .{ .name = "typecode", .zig_type = "u8", .default = "'l'" },
                .{ .name = "__array_items", .zig_type = "std.ArrayList(i64)", .default = "std.ArrayList(i64){}" },
            },
            .methods = &.{
                // __getitem__(self, i) -> self.__array_items.items[i]
                .{ .name = "__getitem__", .inline_code = "{self}.__array_items.items[@as(usize, @intCast({0}))]" },
                // __setitem__(self, i, v) -> self.__array_items.items[i] = v
                .{ .name = "__setitem__", .inline_code = "{self}.__array_items.items[@as(usize, @intCast({0}))] = {1}" },
                // __len__(self) -> self.__array_items.items.len
                .{ .name = "__len__", .inline_code = "{self}.__array_items.items.len" },
                // append(self, x) -> self.__array_items.append(x)
                .{ .name = "append", .inline_code = "try {self}.__array_items.append(__global_allocator, {0})" },
            },
            .init_args = &.{
                .{ .name = "typecode", .zig_type = "u8" },
                .{ .name = "data", .zig_type = "[]const i64" },
            },
            .field_init = &.{
                .{ .field_name = "typecode", .init_code = "typecode" },
                .{ .field_name = "__array_items", .init_code = "blk: { var arr = std.ArrayList(i64){}; arr.appendSlice({alloc}, data) catch {}; break :blk arr; }" },
            },
        } },
    });

    return complex_parents.get(base_name);
}

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
            parent_class = self.class_registry.getClass(class.bases[0]);
        }

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
                    // Check if method body has fallible operations (needs allocator param)
                    const method_needs_allocator = allocator_analyzer.functionNeedsAllocator(method);

                    // Check for decorators that indicate test should be skipped on non-CPython:
                    // 1. @support.cpython_only - tests CPython implementation details
                    // 2. @unittest.skipUnless(_pylong, ...) - requires CPython's _pylong module
                    // 3. @unittest.skipUnless(_decimal, ...) - requires CPython's _decimal module
                    // This is NOT us artificially skipping tests - it's respecting Python's own test annotations
                    const skip_reason: ?[]const u8 = if (hasCPythonOnlyDecorator(method.decorators))
                        "CPython implementation test (not applicable to metal0)"
                    else if (hasSkipUnlessCPythonModule(method.decorators))
                        "Requires CPython-only module (_pylong or _decimal)"
                    else
                        null;

                    // Count @mock.patch.object decorators (each injects a mock param)
                    const mock_count = countMockPatchDecorators(method.decorators);

                    try test_methods.append(self.allocator, core.TestMethodInfo{
                        .name = method_name,
                        .skip_reason = skip_reason,
                        .needs_allocator = method_needs_allocator,
                        .is_skipped = skip_reason != null,
                        .mock_patch_count = mock_count,
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

    // Also save nested_class_names - nested class methods will clear it
    // This prevents parent method's nested class tracking from being lost
    // (e.g., MyIndexable defined in outer scope, used later after nested class's methods are generated)
    var saved_nested_class_names = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer saved_nested_class_names.deinit();

    // Also save nested_class_bases - for base class default args
    var saved_nested_class_bases = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
    defer saved_nested_class_bases.deinit();

    if (self.class_nesting_depth > 1) {
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
    }

    // If we're entering a class while inside a method with 'self',
    // increment method_nesting_depth so nested class methods use __self
    const bump_method_depth = self.inside_method_with_self;
    if (bump_method_depth) self.method_nesting_depth += 1;
    defer if (bump_method_depth) {
        self.method_nesting_depth -= 1;
    };

    // Check if this class captures outer mutable variables
    const captured_vars = self.nested_class_captures.get(class.name);

    // Generate: const ClassName = struct {
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{class.name});
    self.indent();

    // Add pointer fields for captured outer variables
    if (captured_vars) |vars| {
        try self.emitIndent();
        try self.emit("// Captured outer scope variables (pointers)\n");
        for (vars) |var_name| {
            try self.emitIndent();
            // Use *anyopaque as a generic pointer type for captured vars
            // The type will be inferred from usage
            try self.output.writer(self.allocator).print("__captured_{s}: *std.ArrayList(i64),\n", .{var_name});
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
        try body.genInitMethodWithBuiltinBase(self, class.name, init, builtin_base, complex_parent, captured_vars);
    } else {
        // No __init__ defined, generate default init method
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
                    if (std.mem.eql(u8, type_name, "int") or
                        std.mem.eql(u8, type_name, "float") or
                        std.mem.eql(u8, type_name, "str") or
                        std.mem.eql(u8, type_name, "bool") or
                        std.mem.eql(u8, type_name, "list") or
                        std.mem.eql(u8, type_name, "dict"))
                    {
                        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class.name, attr_name });
                        try self.class_type_attrs.put(key, type_name);
                    }
                }
            }
        }
    }

    // Generate regular methods (non-__init__)
    try body.genClassMethods(self, class, captured_vars);

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
                    if (std.mem.eql(u8, type_name, "int") or
                        std.mem.eql(u8, type_name, "float") or
                        std.mem.eql(u8, type_name, "str") or
                        std.mem.eql(u8, type_name, "bool") or
                        std.mem.eql(u8, type_name, "list") or
                        std.mem.eql(u8, type_name, "dict"))
                    {
                        try self.emit("\n");
                        try self.emitIndent();
                        try self.emit("// Class-level type attribute\n");
                        try self.emitIndent();
                        // For int type, support optional base parameter: int(value, base=None)
                        if (std.mem.eql(u8, type_name, "int")) {
                            try self.output.writer(self.allocator).print("pub fn {s}(value: anytype, base: ?i64) i64 {{\n", .{attr_name});
                            self.indent();
                            try self.emitIndent();
                            try self.emit("_ = base; // TODO: support base conversion\n");
                            try self.emitIndent();
                            try self.emit("return runtime.pyIntFromAny(value);\n");
                        } else {
                            try self.output.writer(self.allocator).print("pub fn {s}(value: anytype) i64 {{\n", .{attr_name});
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

    // Restore func_local_uses from saved state (for nested classes)
    // This is critical: nested class methods call analyzeFunctionLocalUses which clears
    // the map. We need to restore the parent scope's uses so isVarUnused() works correctly.
    if (self.class_nesting_depth > 1) {
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
    }

    // Inherit parent methods that aren't overridden
    if (parent_class) |parent| {
        try body.genInheritedMethods(self, class, parent, child_method_names.items);
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");
    // For nested classes (inside functions), suppress unused warning only if truly unused
    // Note: class_nesting_depth > 1 means we're inside a method/function
    if (self.class_nesting_depth > 1 and self.isVarUnused(class.name)) {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("_ = {s};\n", .{class.name});
    }
}

/// Check if test has @support.cpython_only decorator
/// These tests are CPython implementation details and should be skipped by non-CPython implementations
fn hasCPythonOnlyDecorator(decorators: []const ast.Node) bool {
    for (decorators) |decorator| {
        if (decorator == .attribute) {
            const attr = decorator.attribute;
            // Check for support.cpython_only
            if (std.mem.eql(u8, attr.attr, "cpython_only")) {
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "support")) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Check if test has @unittest.skipUnless with CPython-only module (_pylong, _decimal)
/// These modules are C extensions internal to CPython and not available in metal0
fn hasSkipUnlessCPythonModule(decorators: []const ast.Node) bool {
    for (decorators) |decorator| {
        if (decorator == .call) {
            const call = decorator.call;
            // Check if it's unittest.skipUnless
            if (call.func.* == .attribute) {
                const func_attr = call.func.attribute;
                if (std.mem.eql(u8, func_attr.attr, "skipUnless")) {
                    if (func_attr.value.* == .name and std.mem.eql(u8, func_attr.value.name.id, "unittest")) {
                        // Check first argument for _pylong or _decimal
                        if (call.args.len > 0) {
                            if (call.args[0] == .name) {
                                const arg_name = call.args[0].name.id;
                                if (std.mem.eql(u8, arg_name, "_pylong") or
                                    std.mem.eql(u8, arg_name, "_decimal"))
                                {
                                    return true;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return false;
}

/// Count @mock.patch.object and @mock.patch decorators (each injects a mock param)
fn countMockPatchDecorators(decorators: []const ast.Node) usize {
    var count: usize = 0;
    for (decorators) |decorator| {
        if (isMockPatchDecorator(decorator)) {
            count += 1;
        }
    }
    return count;
}

/// Check if a decorator is @mock.patch.object, @mock.patch, @unittest.mock.patch.object, etc.
fn isMockPatchDecorator(decorator: ast.Node) bool {
    // Decorator can be a call like @mock.patch.object(target, attr) or @mock.patch(target)
    if (decorator == .call) {
        const call = decorator.call;
        return isMockPatchFunc(call.func.*);
    }
    // Or a bare attribute like @mock.patch (though less common)
    return isMockPatchFunc(decorator);
}

/// Check if a node represents mock.patch.object or mock.patch
fn isMockPatchFunc(node: ast.Node) bool {
    if (node == .attribute) {
        const attr = node.attribute;
        // Check for patterns like:
        // - mock.patch.object -> attr = "object", value = mock.patch
        // - mock.patch -> attr = "patch", value = mock
        // - unittest.mock.patch.object -> attr = "object", value = unittest.mock.patch
        if (std.mem.eql(u8, attr.attr, "object")) {
            // Check if it's mock.patch.object or unittest.mock.patch.object
            if (attr.value.* == .attribute) {
                const parent = attr.value.attribute;
                if (std.mem.eql(u8, parent.attr, "patch")) {
                    // Check if parent is mock or unittest.mock
                    if (parent.value.* == .name) {
                        return std.mem.eql(u8, parent.value.name.id, "mock");
                    } else if (parent.value.* == .attribute) {
                        // unittest.mock
                        const grandparent = parent.value.attribute;
                        return std.mem.eql(u8, grandparent.attr, "mock");
                    }
                }
            }
        } else if (std.mem.eql(u8, attr.attr, "patch")) {
            // Check for mock.patch or unittest.mock.patch (without .object)
            if (attr.value.* == .name) {
                return std.mem.eql(u8, attr.value.name.id, "mock");
            } else if (attr.value.* == .attribute) {
                const parent = attr.value.attribute;
                return std.mem.eql(u8, parent.attr, "mock");
            }
        }
    }
    return false;
}

