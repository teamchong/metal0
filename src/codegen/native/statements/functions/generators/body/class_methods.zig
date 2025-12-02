/// Class method generation (init, regular methods, inherited methods)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../../main.zig").CodegenError;
const hashmap_helper = @import("hashmap_helper");
const signature = @import("../signature.zig");
const class_fields = @import("class_fields.zig");
const function_traits = @import("../../../../../../analysis/function_traits.zig");
const zig_keywords = @import("zig_keywords");
const generators = @import("../../generators.zig");

// Import from parent for methodMutatesSelf and genMethodBody
const body = @import("../body.zig");
const usage_analysis = @import("usage_analysis.zig");
const function_gen = @import("function_gen.zig");

// Type alias for builtin base info
const BuiltinBaseInfo = generators.BuiltinBaseInfo;

/// Check if a parameter name would shadow a method name in the class
/// Python allows `def __init__(self, real):` and `def real(self):` in the same class,
/// but in Zig these would conflict. We rename params that shadow methods.
fn wouldShadowMethodInClass(param_name: []const u8, class_body: []const ast.Node) bool {
    for (class_body) |stmt| {
        if (stmt == .function_def) {
            const method_name = stmt.function_def.name;
            // Skip __init__ and __new__ - those are the methods we're checking params FOR
            if (std.mem.eql(u8, method_name, "__init__") or std.mem.eql(u8, method_name, "__new__")) {
                continue;
            }
            if (std.mem.eql(u8, param_name, method_name)) {
                return true;
            }
        }
    }
    return false;
}

/// Write init parameter name, renaming if it would shadow a method in the class
fn writeInitParamName(
    self: *NativeCodegen,
    param_name: []const u8,
    class_body: []const ast.Node,
) CodegenError!void {
    // First check Zig keywords
    if (zig_keywords.isZigKeyword(param_name)) {
        try self.output.writer(self.allocator).print("@\"{s}\"", .{param_name});
    }
    // Then check if it would shadow a method in this class
    else if (wouldShadowMethodInClass(param_name, class_body)) {
        try self.output.writer(self.allocator).print("{s}_param", .{param_name});
    }
    // Finally check common method names from zig_keywords
    else if (zig_keywords.wouldShadowMethod(param_name)) {
        try self.output.writer(self.allocator).print("{s}_arg", .{param_name});
    } else {
        try self.output.writer(self.allocator).writeAll(param_name);
    }
}

/// Generate default init() method for classes without __init__
/// Nested classes (in nested_class_names) are heap-allocated for Python reference semantics
pub fn genDefaultInitMethod(self: *NativeCodegen, class_name: []const u8) CodegenError!void {
    // Default __dict__ field for dynamic attributes
    try self.emitIndent();
    try self.emit("// Dynamic attributes dictionary\n");
    try self.emitIndent();
    try self.emit("__dict__: hashmap_helper.StringHashMap(runtime.PyValue),\n");

    // Check if class is nested (defined inside a function/method)
    // Nested classes need heap allocation for Python reference semantics
    const is_nested = self.nested_class_names.contains(class_name);
    const alloc_name = if (is_nested) "__alloc" else "allocator";

    try self.emit("\n");
    try self.emitIndent();

    if (is_nested) {
        // Nested classes: heap-allocate for Python reference semantics (y = x makes y an alias)
        try self.output.writer(self.allocator).print("pub fn init({s}: std.mem.Allocator) !*@This() {{\n", .{alloc_name});
        self.indent();

        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __ptr = try {s}.create(@This());\n", .{alloc_name});
        try self.emitIndent();
        try self.emit("__ptr.* = @This(){\n");
        self.indent();

        // Initialize __dict__ for dynamic attributes
        try self.emitIndent();
        try self.output.writer(self.allocator).print(".__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init({s}),\n", .{alloc_name});

        self.dedent();
        try self.emitIndent();
        try self.emit("};\n");
        try self.emitIndent();
        try self.emit("return __ptr;\n");
    } else {
        // Top-level classes: value semantics (existing behavior)
        try self.output.writer(self.allocator).print("pub fn init({s}: std.mem.Allocator) @This() {{\n", .{alloc_name});
        self.indent();

        try self.emitIndent();
        try self.emit("return @This(){\n");
        self.indent();

        // Initialize __dict__ for dynamic attributes
        try self.emitIndent();
        try self.output.writer(self.allocator).print(".__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init({s}),\n", .{alloc_name});

        self.dedent();
        try self.emitIndent();
        try self.emit("};\n");
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate default init() method with builtin/complex parent type support
pub fn genDefaultInitMethodWithBuiltinBase(self: *NativeCodegen, class_name: []const u8, builtin_base: ?BuiltinBaseInfo, complex_parent: ?generators.ComplexParentInfo, captured_vars: ?[][]const u8) CodegenError!void {
    // Default __dict__ field for dynamic attributes
    try self.emitIndent();
    try self.emit("// Dynamic attributes dictionary\n");
    try self.emitIndent();
    try self.emit("__dict__: hashmap_helper.StringHashMap(runtime.PyValue),\n");

    // Check if class is nested (defined inside a function/method)
    const is_nested = self.nested_class_names.contains(class_name);
    const alloc_name = if (is_nested) "__alloc" else "allocator";

    try self.emit("\n");
    try self.emitIndent();

    // Generate function signature with builtin base args if present
    try self.output.writer(self.allocator).print("pub fn init({s}: std.mem.Allocator", .{alloc_name});

    // Add captured variable pointer parameters
    if (captured_vars) |vars| {
        for (vars) |var_name| {
            try self.emit(", ");
            // Look up the actual type from type inferrer - try scoped then global
            var type_buf = std.ArrayList(u8){};
            const native_types = @import("../../../../../../analysis/native_types/core.zig");
            const var_type: ?native_types.NativeType = self.type_inferrer.getScopedVar(var_name) orelse
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
                zig_type = "std.ArrayList([]const u8)";
            }
            // Check if zig_type contains a nested class name (self-referential/recursive types)
            // If so, use *anyopaque instead to avoid "use of undeclared identifier" errors
            var has_nested_class_ref = false;
            if (std.mem.indexOf(u8, zig_type, class_name) != null) {
                has_nested_class_ref = true;
            } else {
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
            // Check if this captured variable is mutated - use * instead of *const if so
            var mutation_key_buf: [256]u8 = undefined;
            const mutation_key = std.fmt.bufPrint(&mutation_key_buf, "{s}.{s}", .{ class_name, var_name }) catch var_name;
            const is_mutated = self.mutated_captures.contains(mutation_key);
            const ptr_type: []const u8 = if (is_mutated) "*" else "*const";
            try self.output.writer(self.allocator).print("__cap_{s}: {s} {s}", .{ var_name, ptr_type, zig_type });
        }
    }

    // Add builtin base constructor args
    if (builtin_base) |base_info| {
        for (base_info.init_args) |arg| {
            try self.emit(", ");
            try self.output.writer(self.allocator).print("{s}: {s}", .{ arg.name, arg.zig_type });
        }
    }

    // Add complex parent constructor args
    if (complex_parent) |parent_info| {
        for (parent_info.init_args) |arg| {
            try self.emit(", ");
            try self.output.writer(self.allocator).print("{s}: {s}", .{ arg.name, arg.zig_type });
        }
    }

    if (is_nested) {
        try self.emit(") !*@This() {\n");
    } else {
        try self.emit(") @This() {\n");
    }
    self.indent();

    if (is_nested) {
        // Nested classes: heap-allocate for Python reference semantics
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __ptr = try {s}.create(@This());\n", .{alloc_name});
        try self.emitIndent();
        try self.emit("__ptr.* = @This(){\n");
    } else {
        try self.emitIndent();
        try self.emit("return @This(){\n");
    }
    self.indent();

    // Initialize captured variable pointers first
    if (captured_vars) |vars| {
        for (vars) |var_name| {
            try self.emitIndent();
            try self.output.writer(self.allocator).print(".__captured_{s} = __cap_{s},\n", .{ var_name, var_name });
        }
    }

    // Initialize builtin base value first
    if (builtin_base) |base_info| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print(".__base_value__ = {s},\n", .{base_info.zig_init});
    }

    // Initialize complex parent fields using field_init (uses constructor args)
    if (complex_parent) |parent_info| {
        for (parent_info.field_init) |fi| {
            try self.emitIndent();
            try self.emit(".");
            try self.emit(fi.field_name);
            try self.emit(" = ");
            // Replace {alloc} with allocator name in init_code
            var i: usize = 0;
            while (i < fi.init_code.len) {
                if (i + 7 <= fi.init_code.len and std.mem.eql(u8, fi.init_code[i .. i + 7], "{alloc}")) {
                    try self.emit(alloc_name);
                    i += 7;
                } else {
                    try self.output.append(self.allocator, fi.init_code[i]);
                    i += 1;
                }
            }
            try self.emit(",\n");
        }
    }

    // Initialize __dict__ for dynamic attributes
    try self.emitIndent();
    try self.output.writer(self.allocator).print(".__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init({s}),\n", .{alloc_name});

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    if (is_nested) {
        try self.emitIndent();
        try self.emit("return __ptr;\n");
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate init() method from __init__
pub fn genInitMethod(
    self: *NativeCodegen,
    class_name: []const u8,
    init_def: ast.Node.FunctionDef,
) CodegenError!void {
    // Check if class is nested (defined inside a function/method)
    const is_nested = self.nested_class_names.contains(class_name);
    const alloc_name = if (is_nested) "__alloc" else "allocator";

    try self.emit("\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("pub fn init({s}: std.mem.Allocator", .{alloc_name});

    // Parameters (skip 'self')
    const param_analyzer = @import("../../param_analyzer.zig");
    for (init_def.args) |arg| {
        if (std.mem.eql(u8, arg.name, "self")) continue;

        try self.emit(", ");

        // Check if parameter is used in init body (excluding parent __init__ calls)
        // Parent calls are skipped in codegen, so params only used there are unused
        const is_used = param_analyzer.isNameUsedInInitBody(init_def.body, arg.name);
        if (!is_used) {
            // Zig requires unused params to be named just "_", not "_name"
            try self.emit("_: ");
        } else {
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
            try self.emit(": ");
        }

        // Type annotation: prefer type hints, fallback to inference
        if (arg.type_annotation) |_| {
            try self.emit(signature.pythonTypeToZig(arg.type_annotation));
        } else {
            const param_type = try class_fields.inferParamType(self, class_name, init_def, arg.name);
            defer self.allocator.free(param_type);
            try self.emit(param_type);

            // Track anytype params for comptime type guard detection
            if (std.mem.eql(u8, param_type, "anytype")) {
                try self.anytype_params.put(arg.name, {});
            }
        }
    }

    // Use @This() for self-referential return type - heap-allocate for nested classes
    if (is_nested) {
        try self.emit(") !*@This() {\n");
    } else {
        try self.emit(") @This() {\n");
    }
    self.indent();

    // Note: allocator is always used for __dict__ initialization, so no discard needed

    // Analyze local variable uses BEFORE generating code
    // This ensures variables like `g = gcd(...)` that are used in field assignments
    // (e.g., self.__num = num // g) are not incorrectly marked as unused
    try usage_analysis.analyzeFunctionLocalUses(self, init_def);

    // Detect type-check-raise patterns at the start of the function body for anytype params
    // These need comptime branching to prevent invalid type instantiations from being analyzed
    const type_checks = try function_gen.detectTypeCheckRaisePatterns(init_def.body, self.anytype_params, self.allocator);
    const body_start_idx = type_checks.start_idx;
    const has_type_checks = type_checks.checks.len > 0;

    if (has_type_checks) {
        // Generate comptime type guard: if (comptime istype(@TypeOf(p1), "int") and istype(@TypeOf(p2), "int")) {
        try self.emitIndent();
        try self.emit("if (comptime ");
        for (type_checks.checks, 0..) |check, i| {
            if (i > 0) try self.emit(" and ");
            try self.emit("runtime.istype(@TypeOf(");
            try self.emit(check.param_name);
            try self.emit("), \"");
            try self.emit(check.check_type);
            try self.emit("\")");
        }
        try self.emit(") {\n");
        self.indent();
    }

    // First pass: generate non-field assignments (local variables, control flow, etc.)
    // These need to be executed BEFORE the struct is created
    // Skip the type-check statements that were already handled with comptime branching
    for (init_def.body[body_start_idx..]) |stmt| {
        const is_field_assign = blk: {
            if (stmt == .assign) {
                const assign = stmt.assign;
                if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                    const attr = assign.targets[0].attribute;
                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                        break :blk true;
                    }
                }
            }
            break :blk false;
        };

        // Generate non-field statements (local var assignments, if statements, etc.)
        if (!is_field_assign) {
            try self.generateStmt(stmt);
        }
    }

    // Generate return statement with field initializers
    if (is_nested) {
        // Nested classes: heap-allocate for Python reference semantics
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __ptr = try {s}.create(@This());\n", .{alloc_name});
        try self.emitIndent();
        try self.emit("__ptr.* = @This(){\n");
    } else {
        try self.emitIndent();
        try self.emit("return @This(){\n");
    }
    self.indent();

    // Second pass: extract field assignments from __init__ body
    // Skip the type-check statements that were already handled with comptime branching
    for (init_def.body[body_start_idx..]) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                const attr = assign.targets[0].attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                    const field_name = attr.attr;

                    try self.emitIndent();
                    // Escape field name if it's a Zig keyword (e.g., "test")
                    try self.emit(".");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), field_name);
                    try self.emit(" = ");
                    try self.genExpr(assign.value.*);
                    try self.emit(",\n");
                }
            }
        }
    }

    // Initialize __dict__ for dynamic attributes
    try self.emitIndent();
    try self.output.writer(self.allocator).print(".__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init({s}),\n", .{alloc_name});

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    if (is_nested) {
        try self.emitIndent();
        try self.emit("return __ptr;\n");
    }

    // Close comptime type guard if we opened one
    if (has_type_checks) {
        self.dedent();
        try self.emitIndent();
        try self.emit("} else {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("return error.TypeError;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate init() method from __init__ with builtin/complex parent type support
pub fn genInitMethodWithBuiltinBase(
    self: *NativeCodegen,
    class_name: []const u8,
    init: ast.Node.FunctionDef,
    builtin_base: ?BuiltinBaseInfo,
    complex_parent: ?generators.ComplexParentInfo,
    captured_vars: ?[][]const u8,
    class_body: []const ast.Node,
) CodegenError!void {
    // Check if class is nested (defined inside a function/method)
    const is_nested = self.nested_class_names.contains(class_name);
    const alloc_name = if (is_nested) "__alloc" else "allocator";

    // Track renamed params for cleanup at end (params that shadow methods)
    var renamed_params = std.ArrayList([]const u8){};
    defer {
        // Clean up var_renames for renamed params
        for (renamed_params.items) |param_name| {
            _ = self.var_renames.swapRemove(param_name);
        }
        renamed_params.deinit(self.allocator);
    }

    try self.emit("\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("pub fn init({s}: std.mem.Allocator", .{alloc_name});

    // Add captured variable pointer parameters
    if (captured_vars) |vars| {
        for (vars) |var_name| {
            try self.emit(", ");
            // Look up the actual type from type inferrer - try scoped then global
            var type_buf = std.ArrayList(u8){};
            const native_types = @import("../../../../../../analysis/native_types/core.zig");
            const var_type: ?native_types.NativeType = self.type_inferrer.getScopedVar(var_name) orelse
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
                zig_type = "std.ArrayList([]const u8)";
            }
            // Check if zig_type contains a nested class name (self-referential/recursive types)
            // If so, use *anyopaque instead to avoid "use of undeclared identifier" errors
            var has_nested_class_ref = false;
            if (std.mem.indexOf(u8, zig_type, class_name) != null) {
                has_nested_class_ref = true;
            } else {
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
            // Check if this captured variable is mutated - use * instead of *const if so
            var mutation_key_buf: [256]u8 = undefined;
            const mutation_key = std.fmt.bufPrint(&mutation_key_buf, "{s}.{s}", .{ class_name, var_name }) catch var_name;
            const is_mutated = self.mutated_captures.contains(mutation_key);
            const ptr_type: []const u8 = if (is_mutated) "*" else "*const";
            try self.output.writer(self.allocator).print("__cap_{s}: {s} {s}", .{ var_name, ptr_type, zig_type });
        }
    }

    // For builtin bases without __init__ body, add the builtin's constructor args
    // Otherwise, use the __init__ parameters
    const has_user_params = init.args.len > 1; // More than just 'self'

    if (builtin_base != null and !has_user_params) {
        // Class inherits from builtin but has no custom __init__ params
        // Use the builtin's constructor args
        if (builtin_base) |base_info| {
            for (base_info.init_args) |arg| {
                try self.emit(", ");
                try self.output.writer(self.allocator).print("{s}: {s}", .{ arg.name, arg.zig_type });
            }
        }
    } else {
        // Use user-defined __init__ parameters (skip 'self')
        const param_analyzer = @import("../../param_analyzer.zig");
        var is_first_param = true;
        for (init.args) |arg| {
            if (std.mem.eql(u8, arg.name, "self")) continue;

            try self.emit(", ");

            // Check if parameter is used in init body (excluding parent __init__ calls)
            // Parent calls are skipped in codegen, so params only used there are unused
            // EXCEPTION: For builtin subclasses, the first parameter is always used for __base_value__
            const is_base_value_param = is_first_param and builtin_base != null;
            const is_used = is_base_value_param or param_analyzer.isNameUsedInInitBody(init.body, arg.name);
            if (!is_used) {
                // Zig requires unused params to be named just "_", not "_name"
                try self.emit("_: ");
            } else {
                // Check if param would shadow a method in the class
                // If so, register rename in var_renames for body generation
                if (wouldShadowMethodInClass(arg.name, class_body)) {
                    const renamed = try std.fmt.allocPrint(self.allocator, "{s}_param", .{arg.name});
                    try self.var_renames.put(arg.name, renamed);
                    try renamed_params.append(self.allocator, arg.name);
                    try self.emit(renamed);
                } else {
                    try writeInitParamName(self, arg.name, class_body);
                }
                try self.emit(": ");
            }
            is_first_param = false;

            // Type annotation: prefer type hints, fallback to inference
            if (arg.type_annotation) |_| {
                try self.emit(signature.pythonTypeToZig(arg.type_annotation));
            } else if (is_base_value_param and builtin_base != null) {
                // For builtin subclass, first param type matches the builtin type
                try self.emit(builtin_base.?.zig_type);
            } else {
                const param_type = try class_fields.inferParamType(self, class_name, init, arg.name);
                defer self.allocator.free(param_type);
                try self.emit(param_type);

                // Track anytype params for comptime type guard detection
                if (std.mem.eql(u8, param_type, "anytype")) {
                    try self.anytype_params.put(arg.name, {});
                }
            }
        }
    }

    // Detect type-check-raise patterns at the start of the function body for anytype params
    // These need comptime branching to prevent invalid type instantiations from being analyzed
    // Do this BEFORE emitting return type since it affects whether we need error union
    const type_checks = try function_gen.detectTypeCheckRaisePatterns(init.body, self.anytype_params, self.allocator);
    const body_start_idx = type_checks.start_idx;
    const has_type_checks = type_checks.checks.len > 0;

    // Track class as having error-returning init for `try` in instantiation calls
    if (has_type_checks) {
        try self.error_init_classes.put(class_name, {});
    }

    // Use @This() or !@This() for self-referential return type
    // Use error union if we have type checks that may return error.TypeError
    if (is_nested) {
        try self.emit(") !*@This() {\n");
    } else if (has_type_checks) {
        try self.emit(") !@This() {\n");
    } else {
        try self.emit(") @This() {\n");
    }
    self.indent();

    // Set captured vars context for expression generation
    // In init, captured vars are accessed via __cap_* params, not self.__captured_*
    self.current_class_captures = captured_vars;
    self.inside_init_method = true;
    defer self.current_class_captures = null;
    defer self.inside_init_method = false;

    // Analyze local variable uses BEFORE generating code
    // This ensures variables like `g = gcd(...)` that are used in field assignments
    // (e.g., self.__num = num // g) are not incorrectly marked as unused
    try usage_analysis.analyzeFunctionLocalUses(self, init);

    if (has_type_checks) {
        // Generate comptime type guard: if (comptime istype(@TypeOf(p1), "int") and istype(@TypeOf(p2), "int")) {
        try self.emitIndent();
        try self.emit("if (comptime ");
        for (type_checks.checks, 0..) |check, i| {
            if (i > 0) try self.emit(" and ");
            try self.emit("runtime.istype(@TypeOf(");
            try self.emit(check.param_name);
            try self.emit("), \"");
            try self.emit(check.check_type);
            try self.emit("\")");
        }
        try self.emit(") {\n");
        self.indent();
    }

    // First pass: generate non-field assignments (local variables, control flow, etc.)
    // These need to be executed BEFORE the struct is created
    // Skip type-check statements if we're using comptime branching
    for (init.body[body_start_idx..]) |stmt| {
        const is_field_assign = blk: {
            if (stmt == .assign) {
                const assign = stmt.assign;
                if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                    const attr = assign.targets[0].attribute;
                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                        break :blk true;
                    }
                }
            }
            break :blk false;
        };

        // Generate non-field statements (local var assignments, if statements, etc.)
        if (!is_field_assign) {
            try self.generateStmt(stmt);
        }
    }

    // Generate return statement with field initializers
    if (is_nested) {
        // Nested classes: heap-allocate for Python reference semantics
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __ptr = try {s}.create(@This());\n", .{alloc_name});
        try self.emitIndent();
        try self.emit("__ptr.* = @This(){\n");
    } else {
        try self.emitIndent();
        try self.emit("return @This(){\n");
    }
    self.indent();

    // Initialize captured variable pointers first
    if (captured_vars) |vars| {
        for (vars) |var_name| {
            try self.emitIndent();
            try self.output.writer(self.allocator).print(".__captured_{s} = __cap_{s},\n", .{ var_name, var_name });
        }
    }

    // Initialize builtin base value first if present
    if (builtin_base) |_| {
        try self.emitIndent();
        // For user-defined __init__, use the first non-self parameter as the base value
        // (e.g., class MyFloat(float): def __init__(self, arg): ... -> use arg as base value)
        // For default init without user params, use the builtin's zig_init (e.g., "value")
        if (has_user_params) {
            // Find first non-self parameter
            for (init.args) |arg| {
                if (std.mem.eql(u8, arg.name, "self")) continue;
                // Use the escaped parameter name (handles Zig keywords)
                try self.emit(".__base_value__ = ");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
                try self.emit(",\n");
                break;
            }
        } else {
            try self.output.writer(self.allocator).print(".__base_value__ = {s},\n", .{builtin_base.?.zig_init});
        }
    }

    // Initialize complex parent fields (e.g., array.array fields)
    if (complex_parent) |parent_info| {
        for (parent_info.fields) |field| {
            // Check if this field is being initialized in __init__ body
            // If so, skip the default - user's init will handle it
            const is_user_initialized = for (init.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                        const attr = assign.targets[0].attribute;
                        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                            if (std.mem.eql(u8, attr.attr, field.name)) {
                                break true;
                            }
                        }
                    }
                }
            } else false;

            if (!is_user_initialized) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print(".{s} = {s},\n", .{ field.name, field.default });
            }
        }
    }

    // Second pass: extract field assignments from __init__ body
    // Skip type-check statements if we're using comptime branching
    for (init.body[body_start_idx..]) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                const attr = assign.targets[0].attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                    const field_name = attr.attr;

                    try self.emitIndent();
                    try self.emit(".");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), field_name);
                    try self.emit(" = ");
                    try self.genExpr(assign.value.*);
                    try self.emit(",\n");
                }
            }
        }
    }

    // Initialize __dict__ for dynamic attributes
    try self.emitIndent();
    try self.output.writer(self.allocator).print(".__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init({s}),\n", .{alloc_name});

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    if (is_nested) {
        try self.emitIndent();
        try self.emit("return __ptr;\n");
    }

    // Close comptime type guard if we opened one
    if (has_type_checks) {
        self.dedent();
        try self.emitIndent();
        try self.emit("} else {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("return error.TypeError;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate init() method from __new__ when no __init__ exists
/// Python's __new__ is a class method that creates the instance, but metal0 needs
/// a regular init() function. We use __new__'s parameters (skipping cls) for init.
pub fn genInitMethodFromNew(
    self: *NativeCodegen,
    class_name: []const u8,
    new_method: ast.Node.FunctionDef,
    builtin_base: ?BuiltinBaseInfo,
    complex_parent: ?generators.ComplexParentInfo,
    captured_vars: ?[][]const u8,
    class_body: []const ast.Node,
) CodegenError!void {
    // Check if class is nested (defined inside a function/method)
    const is_nested = self.nested_class_names.contains(class_name);
    const alloc_name = if (is_nested) "__alloc" else "allocator";

    // Track renamed params for cleanup at end (params that shadow methods)
    var renamed_params = std.ArrayList([]const u8){};
    defer {
        // Clean up var_renames for renamed params
        for (renamed_params.items) |param_name| {
            _ = self.var_renames.swapRemove(param_name);
        }
        renamed_params.deinit(self.allocator);
    }

    try self.emit("\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("pub fn init({s}: std.mem.Allocator", .{alloc_name});

    // Add captured variable pointer parameters
    if (captured_vars) |vars| {
        for (vars) |var_name| {
            try self.emit(", ");
            // Look up the actual type from type inferrer - try scoped then global
            var type_buf = std.ArrayList(u8){};
            const native_types = @import("../../../../../../analysis/native_types/core.zig");
            const var_type: ?native_types.NativeType = self.type_inferrer.getScopedVar(var_name) orelse
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
                zig_type = "std.ArrayList([]const u8)";
            }
            // Check if zig_type contains a nested class name (self-referential/recursive types)
            // If so, use *anyopaque instead to avoid "use of undeclared identifier" errors
            var has_nested_class_ref = false;
            if (std.mem.indexOf(u8, zig_type, class_name) != null) {
                has_nested_class_ref = true;
            } else {
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
            // Check if this captured variable is mutated - use * instead of *const if so
            var mutation_key_buf: [256]u8 = undefined;
            const mutation_key = std.fmt.bufPrint(&mutation_key_buf, "{s}.{s}", .{ class_name, var_name }) catch var_name;
            const is_mutated = self.mutated_captures.contains(mutation_key);
            const ptr_type: []const u8 = if (is_mutated) "*" else "*const";
            try self.output.writer(self.allocator).print("__cap_{s}: {s} {s}", .{ var_name, ptr_type, zig_type });
        }
    }

    // Use __new__ parameters (skip 'cls' - first param)
    // __new__ signature: def __new__(cls, arg, newarg=None): ...
    // init signature should be: init(allocator, arg, newarg)
    const param_analyzer = @import("../../param_analyzer.zig");
    var is_first_non_cls = true;
    for (new_method.args) |arg| {
        // Skip 'cls' (first param of __new__)
        if (std.mem.eql(u8, arg.name, "cls")) continue;

        try self.emit(", ");

        // For builtin subclass, the first non-cls parameter is the base value
        const is_base_value_param = is_first_non_cls and builtin_base != null;
        // For __new__, only field assignments (self.x = param) count as "used" for init()
        // Return statements like `return meta(name, bases, d)` don't translate to init() body
        const is_used = is_base_value_param or param_analyzer.isNameUsedInNewForInit(new_method.body, arg.name);
        if (!is_used) {
            // Zig requires unused params to be named just "_", not "_name"
            try self.emit("_: ");
        } else {
            // Check if param would shadow a method in the class
            // If so, register rename in var_renames for body generation
            if (wouldShadowMethodInClass(arg.name, class_body)) {
                const renamed = try std.fmt.allocPrint(self.allocator, "{s}_param", .{arg.name});
                try self.var_renames.put(arg.name, renamed);
                try renamed_params.append(self.allocator, arg.name);
                try self.emit(renamed);
            } else {
                try writeInitParamName(self, arg.name, class_body);
            }
            try self.emit(": ");
        }
        is_first_non_cls = false;

        // Type annotation: prefer type hints, fallback to inference
        if (arg.type_annotation) |_| {
            try self.emit(signature.pythonTypeToZig(arg.type_annotation));
        } else if (is_base_value_param and builtin_base != null) {
            // For builtin subclass, first param type matches the builtin type
            try self.emit(builtin_base.?.zig_type);
        } else {
            const param_type = try class_fields.inferParamType(self, class_name, new_method, arg.name);
            defer self.allocator.free(param_type);
            try self.emit(param_type);
        }
    }

    // Use @This() for self-referential return type
    try self.emit(") @This() {\n");
    self.indent();

    // Set captured vars context for expression generation
    self.current_class_captures = captured_vars;
    self.inside_init_method = true;
    defer self.current_class_captures = null;
    defer self.inside_init_method = false;

    // Analyze local variable uses BEFORE generating code
    // This ensures variables like `g = gcd(...)` that are used in field assignments
    // (e.g., self.__num = num // g) are not incorrectly marked as unused
    try usage_analysis.analyzeFunctionLocalUses(self, new_method);

    // First pass: generate non-field statements from __new__ body
    // Skip super().__new__() calls and return statements
    for (new_method.body) |stmt| {
        const is_field_assign = blk: {
            if (stmt == .assign) {
                const assign = stmt.assign;
                if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                    const attr = assign.targets[0].attribute;
                    // Check for self.x = ... (where self might be named differently)
                    if (attr.value.* == .name) {
                        const target_name = attr.value.name.id;
                        // In __new__, 'self' is typically assigned from super().__new__()
                        if (std.mem.eql(u8, target_name, "self")) {
                            break :blk true;
                        }
                    }
                }
            }
            break :blk false;
        };

        const is_super_new_or_return = blk: {
            // Skip: self = super().__new__(cls, arg)
            if (stmt == .assign) {
                const assign = stmt.assign;
                if (assign.targets.len > 0 and assign.targets[0] == .name) {
                    if (std.mem.eql(u8, assign.targets[0].name.id, "self")) {
                        break :blk true;
                    }
                }
            }
            // Skip: return self
            if (stmt == .return_stmt) {
                break :blk true;
            }
            break :blk false;
        };

        // Generate non-field, non-super-new statements
        if (!is_field_assign and !is_super_new_or_return) {
            try self.generateStmt(stmt);
        }
    }

    // Generate return statement with field initializers
    try self.emitIndent();
    try self.emit("return @This(){\n");
    self.indent();

    // Initialize captured variable pointers first
    if (captured_vars) |vars| {
        for (vars) |var_name| {
            try self.emitIndent();
            try self.output.writer(self.allocator).print(".__captured_{s} = __cap_{s},\n", .{ var_name, var_name });
        }
    }

    // Initialize builtin base value first if present
    if (builtin_base) |_| {
        try self.emitIndent();
        // Use the first non-cls parameter as the base value
        for (new_method.args) |arg| {
            if (std.mem.eql(u8, arg.name, "cls")) continue;
            try self.emit(".__base_value__ = ");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
            try self.emit(",\n");
            break;
        }
    }

    // Initialize complex parent fields
    if (complex_parent) |parent_info| {
        for (parent_info.fields) |field| {
            const is_user_initialized = for (new_method.body) |stmt| {
                if (stmt == .assign) {
                    const assign = stmt.assign;
                    if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                        const attr = assign.targets[0].attribute;
                        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                            if (std.mem.eql(u8, attr.attr, field.name)) {
                                break true;
                            }
                        }
                    }
                }
            } else false;

            if (!is_user_initialized) {
                try self.emitIndent();
                try self.output.writer(self.allocator).print(".{s} = {s},\n", .{ field.name, field.default });
            }
        }
    }

    // Second pass: extract field assignments from __new__ body (self.x = value)
    for (new_method.body) |stmt| {
        if (stmt == .assign) {
            const assign = stmt.assign;
            if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                const attr = assign.targets[0].attribute;
                if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                    const field_name = attr.attr;

                    try self.emitIndent();
                    try self.emit(".");
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), field_name);
                    try self.emit(" = ");
                    try self.genExpr(assign.value.*);
                    try self.emit(",\n");
                }
            }
        }
    }

    // Initialize __dict__ for dynamic attributes
    try self.emitIndent();
    try self.output.writer(self.allocator).print(".__dict__ = hashmap_helper.StringHashMap(runtime.PyValue).init({s}),\n", .{alloc_name});

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate regular class methods (non-__init__)
pub fn genClassMethods(
    self: *NativeCodegen,
    class: ast.Node.ClassDef,
    captured_vars: ?[][]const u8,
) CodegenError!void {
    // Save previous class context (for nested classes inside methods)
    const prev_class_name = self.current_class_name;
    const prev_captures = self.current_class_captures;
    const prev_parent = self.current_class_parent;

    // Set current class name for super() support and self.method() allocator detection
    self.current_class_name = class.name;
    defer self.current_class_name = prev_class_name;

    // Set current class's captured variables for expression generation
    // This allows the expression generator to convert `var_name` to `self.__captured_var_name.*`
    self.current_class_captures = captured_vars;
    defer self.current_class_captures = prev_captures;

    // Set current class parent for parent method call resolution (e.g., array.array.__getitem__(self, i))
    if (class.bases.len > 0) {
        self.current_class_parent = class.bases[0];
    }
    defer self.current_class_parent = prev_parent;

    // In Python, methods can be "overridden" within the same class (e.g., @property + @foo.setter)
    // Zig doesn't allow duplicate struct member names, so we find the LAST occurrence of each method
    // and only generate that one (Python semantics: later definition shadows earlier ones)
    var last_method_indices = hashmap_helper.StringHashMap(usize).init(self.allocator);
    defer last_method_indices.deinit();

    // First pass: find the last index for each method name
    for (class.body, 0..) |stmt, idx| {
        if (stmt == .function_def) {
            const method = stmt.function_def;
            if (std.mem.eql(u8, method.name, "__init__")) continue;
            try last_method_indices.put(method.name, idx);
        }
    }

    // Second pass: only generate methods at their last occurrence index
    for (class.body, 0..) |stmt, idx| {
        if (stmt == .function_def) {
            const method = stmt.function_def;
            if (std.mem.eql(u8, method.name, "__init__")) continue;

            // Skip if this is not the last occurrence of this method name
            if (last_method_indices.get(method.name)) |last_idx| {
                if (idx != last_idx) continue;
            }

            const mutates_self = body.methodMutatesSelf(method);
            // Use analyzeNeedsAllocator to detect same-class constructor calls like Rat(x)
            const needs_allocator = function_traits.analyzeNeedsAllocator(method, class.name);
            const actually_uses_allocator = function_traits.analyzeUsesAllocatorParam(method, class.name);

            // Track allocator needs for nested class methods so call sites know whether to pass allocator
            // This is needed because nested classes are not in the class_registry
            if (self.nested_class_names.contains(class.name) and needs_allocator) {
                const method_key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class.name, method.name });
                try self.nested_class_method_needs_alloc.put(method_key, {});
            }

            // Generate method signature
            // Note: method_nesting_depth tracks whether we're inside a NESTED class inside a method
            // It's incremented when we enter a class inside a method body, not when we enter a method itself
            try signature.genMethodSignatureWithSkip(self, class.name, method, mutates_self, needs_allocator, false, actually_uses_allocator);

            // Track method signature for default parameter handling at call sites
            // Count non-self params and how many have defaults
            var required_count: usize = 0;
            var total_count: usize = 0;
            for (method.args) |arg| {
                if (std.mem.eql(u8, arg.name, "self")) continue;
                total_count += 1;
                if (arg.default == null) required_count += 1;
            }
            // Store as "ClassName.method_name" for method call lookup
            if (total_count > required_count) {
                const method_key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class.name, method.name });
                try self.function_signatures.put(method_key, .{
                    .total_params = total_count,
                    .required_params = required_count,
                });
            }

            // Check if this method returns a lambda that captures self (closure)
            // Register it so that callers can mark the variable as a closure
            if (signature.getReturnedLambda(method.body)) |lambda| {
                if (signature.lambdaCapturesSelf(lambda.body.*)) {
                    // Register as "ClassName.method_name"
                    const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class.name, method.name });
                    try self.closure_returning_methods.put(key, {});
                }
            }

            // Set current function name for comparisons in method body
            // (used for detecting optional parameter comparisons like "base is None")
            const prev_func_name = self.current_function_name;
            self.current_function_name = method.name;
            defer self.current_function_name = prev_func_name;

            // Track whether self is mutable for return dereference handling
            // When method mutates self and returns self, we need: return __self.*;
            const prev_self_mutable = self.method_self_is_mutable;
            self.method_self_is_mutable = mutates_self;
            defer self.method_self_is_mutable = prev_self_mutable;

            try body.genMethodBodyWithAllocatorInfo(self, method, needs_allocator, actually_uses_allocator);
        }
    }
}


/// Generate inherited methods from parent class (recursively includes grandparents)
pub fn genInheritedMethods(
    self: *NativeCodegen,
    class: ast.Node.ClassDef,
    parent: ast.Node.ClassDef,
    child_method_names: []const []const u8,
) CodegenError!void {
    // Track methods we've already generated to avoid duplicates from grandparents
    var generated_methods = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer generated_methods.deinit();

    // Add all child method names to avoid re-inheriting overridden methods
    for (child_method_names) |name| {
        try generated_methods.put(name, {});
    }

    // Also check for class attribute assignments that block inheritance (e.g., __iadd__ = None)
    for (class.body) |stmt| {
        if (stmt == .assign) {
            for (stmt.assign.targets) |target| {
                if (target == .name) {
                    try generated_methods.put(target.name.id, {});
                }
            }
        }
    }

    // Recursively inherit from parent chain
    try inheritMethodsFromClass(self, class, parent, &generated_methods);
}

/// Generate PolymorphicReturn__ helper functions for methods that need them
/// These functions compute return type at comptime based on the input parameter type
pub fn genPolymorphicReturnHelpers(
    self: *NativeCodegen,
    class: ast.Node.ClassDef,
) CodegenError!void {
    // First pass: collect all method parameter types we'll need
    // We need to detect which methods have polymorphic return patterns
    for (class.body) |stmt| {
        if (stmt != .function_def) continue;
        const method = stmt.function_def;
        if (std.mem.eql(u8, method.name, "__init__")) continue;

        // Check if this method has the polymorphic pattern
        if (!hasPolymorphicReturnPatternForClass(method, class.name)) continue;

        // Generate the PolymorphicReturn__ helper function
        try self.emit("\n");
        try self.emitIndent();
        try self.emit("// Comptime return type for polymorphic method\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("fn PolymorphicReturn__{s}(comptime T: type) type {{\n", .{method.name});
        self.indent();

        // Generate comptime type dispatch
        // All branches return error union for consistency (self.__float__() can fail)
        try self.emitIndent();
        try self.emit("if (comptime @typeInfo(T) == .float or @typeInfo(T) == .comptime_float) {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("return anyerror!f64;\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("} else {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("return anyerror!@This();\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");

        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }
}

/// Check if a method has polymorphic return pattern (for class context)
/// This detects methods that return different types based on input:
/// - Rat for int/Rat inputs
/// - f64 for float inputs
fn hasPolymorphicReturnPatternForClass(method: ast.Node.FunctionDef, class_name: []const u8) bool {
    _ = class_name;
    // Look for pattern: if isnum(other): return float(self) + other <- returns f64
    // when other branches return Rat via Rat.init() or @This().init()

    var has_class_return = false;
    var has_float_return = false;

    for (method.body) |stmt| {
        if (stmt != .if_stmt) continue;
        const if_stmt = stmt.if_stmt;
        if (if_stmt.condition.* != .call) continue;
        const call = if_stmt.condition.call;
        if (call.func.* != .name) continue;
        const func_name = call.func.name.id;

        // Check for isint/isRat returning class instance
        if (std.mem.eql(u8, func_name, "isint") or std.mem.eql(u8, func_name, "isRat") or std.mem.eql(u8, func_name, "isinstance")) {
            for (if_stmt.body) |body_stmt| {
                if (body_stmt == .return_stmt) {
                    if (body_stmt.return_stmt.value) |val| {
                        // Check if returning class constructor call
                        if (val.* == .call and val.call.func.* == .name) {
                            has_class_return = true;
                        }
                    }
                }
            }
        } else if (std.mem.eql(u8, func_name, "isnum")) {
            // Check if body returns float operation
            for (if_stmt.body) |body_stmt| {
                if (body_stmt != .return_stmt) continue;
                if (body_stmt.return_stmt.value) |val| {
                    if (val.* == .binop or val.* == .call) {
                        // float(self) + other or runtime.divideFloat(...) or similar
                        has_float_return = true;
                    }
                }
            }
        }
    }

    // Polymorphic pattern: both class return AND float return paths exist
    return has_class_return and has_float_return;
}

/// Recursively inherit methods from a class and its parents
fn inheritMethodsFromClass(
    self: *NativeCodegen,
    child: ast.Node.ClassDef,
    parent: ast.Node.ClassDef,
    generated_methods: *hashmap_helper.StringHashMap(void),
) CodegenError!void {
    // First, recursively inherit from grandparents (so grandparent methods come first)
    if (parent.bases.len > 0) {
        const grandparent_name = parent.bases[0];
        // Look up grandparent class
        var grandparent = self.class_registry.getClass(grandparent_name);
        if (grandparent == null) {
            grandparent = self.nested_class_defs.get(grandparent_name);
        }
        if (grandparent) |gp| {
            try inheritMethodsFromClass(self, child, gp, generated_methods);
        }
    }

    // Now inherit methods from this parent
    for (parent.body) |parent_stmt| {
        if (parent_stmt == .function_def) {
            const parent_method = parent_stmt.function_def;
            if (std.mem.eql(u8, parent_method.name, "__init__")) continue;

            // Skip if already generated (from child or earlier in chain)
            if (generated_methods.contains(parent_method.name)) continue;

            // Mark as generated
            try generated_methods.put(parent_method.name, {});

            // Copy parent method to child class
            const mutates_self = body.methodMutatesSelf(parent_method);
            // Use analyzeNeedsAllocator with parent class name for inherited methods
            const needs_allocator = function_traits.analyzeNeedsAllocator(parent_method, parent.name);
            const actually_uses_allocator = function_traits.analyzeUsesAllocatorParam(parent_method, parent.name);

            // Before generating signature, add parent to nested_class_names for return type detection
            // (e.g., aug_test.__add__ returns aug_test(...) which needs parent to be known)
            try self.nested_class_names.put(parent.name, {});

            // Use genMethodSignatureWithSkip to properly pass actually_uses_allocator flag
            try signature.genMethodSignatureWithSkip(self, child.name, parent_method, mutates_self, needs_allocator, false, actually_uses_allocator);

            // Track whether self is mutable for return dereference handling
            const prev_self_mutable = self.method_self_is_mutable;
            self.method_self_is_mutable = mutates_self;
            defer self.method_self_is_mutable = prev_self_mutable;

            // For inherited methods, pass the parent class name so method body can call its constructor
            // (e.g., aug_test.__add__ returns aug_test(...) - when inherited to aug_test4,
            // the method body needs to know aug_test is a nested class for allocator handling)
            try body.genMethodBodyWithContext(self, parent_method, &[_][]const u8{parent.name});
        }
    }
}
