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
    // Skip entire functions that reference skipped modules to avoid undeclared variable errors.
    // E.g., `result = subprocess.run(...)` skips assignment but `return result.stderr` still
    // references `result` - causing compilation errors. Better to skip the whole function.
    const assign = @import("../assign.zig");
    if (assign.functionBodyRefersToSkippedModule(self, func.body)) {
        // Mark this function as skipped so calls to it are also skipped
        try self.markSkippedFunction(func.name);
        return;
    }

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
                    // Check for skip docstring: first statement is string starting with "skip:"
                    const skip_reason = getSkipReason(method);
                    // Check if method body has fallible operations (needs allocator param)
                    const method_needs_allocator = allocator_analyzer.functionNeedsAllocator(method);
                    try test_methods.append(self.allocator, core.TestMethodInfo{
                        .name = method_name,
                        .skip_reason = skip_reason,
                        .needs_allocator = method_needs_allocator,
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
    if (self.class_nesting_depth > 1) {
        // Copy current func_local_uses
        var it = self.func_local_uses.iterator();
        while (it.next()) |entry| {
            try saved_func_local_uses.put(entry.key_ptr.*, {});
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

    // Generate regular methods (non-__init__)
    try body.genClassMethods(self, class, captured_vars);

    // Restore func_local_uses from saved state (for nested classes)
    // This is critical: nested class methods call analyzeFunctionLocalUses which clears
    // the map. We need to restore the parent scope's uses so isVarUnused() works correctly.
    if (self.class_nesting_depth > 1) {
        self.func_local_uses.clearRetainingCapacity();
        var restore_it = saved_func_local_uses.iterator();
        while (restore_it.next()) |entry| {
            try self.func_local_uses.put(entry.key_ptr.*, {});
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

/// Check if a test method has a skip docstring
/// Returns the skip reason if found, null otherwise
/// Looks for: """skip: reason""" or "skip: reason" as first statement
pub fn getSkipReason(method: ast.Node.FunctionDef) ?[]const u8 {
    // Check for hypothesis decorators (@hypothesis.given, @hypothesis.example)
    // These tests require the hypothesis library which we don't support
    for (method.decorators) |dec| {
        // Check for @hypothesis.given or @hypothesis.example
        if (dec == .call) {
            const call = dec.call;
            if (call.func.* == .attribute) {
                const attr = call.func.attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "hypothesis")) {
                    return "requires hypothesis library";
                }
            }
        }
        // Check for bare @hypothesis.something
        if (dec == .attribute) {
            const attr = dec.attribute;
            if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "hypothesis")) {
                return "requires hypothesis library";
            }
        }
    }

    // Check if body references hypothesis (e.g., helper functions that use hypothesis.strategies)
    if (bodyUsesHypothesis(method.body)) {
        return "requires hypothesis library";
    }

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

/// Check if any expression in the body references 'hypothesis' module
fn bodyUsesHypothesis(stmts: []ast.Node) bool {
    for (stmts) |stmt| {
        if (stmtUsesHypothesis(stmt)) return true;
    }
    return false;
}

fn stmtUsesHypothesis(node: ast.Node) bool {
    return switch (node) {
        .assign => |assign| exprUsesHypothesis(assign.value.*),
        .aug_assign => |aug| exprUsesHypothesis(aug.value.*),
        .expr_stmt => |expr| exprUsesHypothesis(expr.value.*),
        .return_stmt => |ret| if (ret.value) |val| exprUsesHypothesis(val.*) else false,
        .if_stmt => |if_stmt| {
            if (exprUsesHypothesis(if_stmt.condition.*)) return true;
            if (bodyUsesHypothesis(if_stmt.body)) return true;
            if (bodyUsesHypothesis(if_stmt.else_body)) return true;
            return false;
        },
        .while_stmt => |while_stmt| {
            if (exprUsesHypothesis(while_stmt.condition.*)) return true;
            return bodyUsesHypothesis(while_stmt.body);
        },
        .for_stmt => |for_stmt| bodyUsesHypothesis(for_stmt.body),
        else => false,
    };
}

fn exprUsesHypothesis(node: ast.Node) bool {
    return switch (node) {
        .name => |name| std.mem.eql(u8, name.id, "hypothesis"),
        .attribute => |attr| exprUsesHypothesis(attr.value.*),
        .call => |call| {
            if (exprUsesHypothesis(call.func.*)) return true;
            for (call.args) |arg| {
                if (exprUsesHypothesis(arg)) return true;
            }
            return false;
        },
        .binop => |binop| exprUsesHypothesis(binop.left.*) or exprUsesHypothesis(binop.right.*),
        .compare => |comp| {
            if (exprUsesHypothesis(comp.left.*)) return true;
            for (comp.comparators) |c| {
                if (exprUsesHypothesis(c)) return true;
            }
            return false;
        },
        .listcomp => |lc| {
            if (exprUsesHypothesis(lc.elt.*)) return true;
            for (lc.generators) |gen| {
                if (exprUsesHypothesis(gen.iter.*)) return true;
                for (gen.ifs) |cond| {
                    if (exprUsesHypothesis(cond)) return true;
                }
            }
            return false;
        },
        .tuple => |tup| {
            for (tup.elts) |elt| {
                if (exprUsesHypothesis(elt)) return true;
            }
            return false;
        },
        .list => |list| {
            for (list.elts) |elt| {
                if (exprUsesHypothesis(elt)) return true;
            }
            return false;
        },
        else => false,
    };
}
