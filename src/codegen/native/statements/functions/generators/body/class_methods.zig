/// Class method generation (init, regular methods, inherited methods)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../../main.zig").CodegenError;
const hashmap_helper = @import("hashmap_helper");
const signature = @import("../signature.zig");
const class_fields = @import("class_fields.zig");
const allocator_analyzer = @import("../../allocator_analyzer.zig");
const zig_keywords = @import("zig_keywords");
const generators = @import("../../generators.zig");

// Import from parent for methodMutatesSelf and genMethodBody
const body = @import("../body.zig");

// Type alias for builtin base info
const BuiltinBaseInfo = generators.BuiltinBaseInfo;

/// Generate default init() method for classes without __init__
pub fn genDefaultInitMethod(self: *NativeCodegen, _: []const u8) CodegenError!void {
    // Default __dict__ field for dynamic attributes
    try self.emitIndent();
    try self.emit("// Dynamic attributes dictionary\n");
    try self.emitIndent();
    try self.emit("__dict__: hashmap_helper.StringHashMap(runtime.PyValue),\n");

    // Use __alloc for nested classes to avoid shadowing outer allocator
    // class_nesting_depth: 1 = top-level class, 2+ = nested class
    const alloc_name = if (self.class_nesting_depth > 1) "__alloc" else "allocator";

    try self.emit("\n");
    try self.emitIndent();
    // Use @This() for self-referential return type instead of class name
    try self.output.writer(self.allocator).print("pub fn init({s}: std.mem.Allocator) @This() {{\n", .{alloc_name});
    self.indent();

    try self.emitIndent();
    // Use @This(){} for struct literal initialization
    try self.emit("return @This(){\n");
    self.indent();

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

/// Generate default init() method with builtin/complex parent type support
pub fn genDefaultInitMethodWithBuiltinBase(self: *NativeCodegen, _: []const u8, builtin_base: ?BuiltinBaseInfo, complex_parent: ?generators.ComplexParentInfo, captured_vars: ?[][]const u8) CodegenError!void {
    // Default __dict__ field for dynamic attributes
    try self.emitIndent();
    try self.emit("// Dynamic attributes dictionary\n");
    try self.emitIndent();
    try self.emit("__dict__: hashmap_helper.StringHashMap(runtime.PyValue),\n");

    // Use __alloc for nested classes to avoid shadowing outer allocator
    const alloc_name = if (self.class_nesting_depth > 1) "__alloc" else "allocator";

    try self.emit("\n");
    try self.emitIndent();

    // Generate function signature with builtin base args if present
    try self.output.writer(self.allocator).print("pub fn init({s}: std.mem.Allocator", .{alloc_name});

    // Add captured variable pointer parameters
    if (captured_vars) |vars| {
        for (vars) |var_name| {
            try self.emit(", ");
            try self.output.writer(self.allocator).print("__cap_{s}: *std.ArrayList(i64)", .{var_name});
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

    try self.emit(") @This() {\n");
    self.indent();

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

    self.dedent();
    try self.emitIndent();
    try self.emit("}\n");
}

/// Generate init() method from __init__
pub fn genInitMethod(
    self: *NativeCodegen,
    class_name: []const u8,
    init: ast.Node.FunctionDef,
) CodegenError!void {
    // Use __alloc for nested classes to avoid shadowing outer allocator
    // class_nesting_depth: 1 = top-level class, 2+ = nested class
    const alloc_name = if (self.class_nesting_depth > 1) "__alloc" else "allocator";

    try self.emit("\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("pub fn init({s}: std.mem.Allocator", .{alloc_name});

    // Parameters (skip 'self')
    const param_analyzer = @import("../../param_analyzer.zig");
    for (init.args) |arg| {
        if (std.mem.eql(u8, arg.name, "self")) continue;

        try self.emit(", ");

        // Check if parameter is used in init body (excluding parent __init__ calls)
        // Parent calls are skipped in codegen, so params only used there are unused
        const is_used = param_analyzer.isNameUsedInInitBody(init.body, arg.name);
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
            const param_type = try class_fields.inferParamType(self, class_name, init, arg.name);
            defer self.allocator.free(param_type);
            try self.emit(param_type);
        }
    }

    // Use @This() for self-referential return type
    try self.emit(") @This() {\n");
    self.indent();

    // Note: allocator is always used for __dict__ initialization, so no discard needed

    // First pass: generate non-field assignments (local variables, control flow, etc.)
    // These need to be executed BEFORE the struct is created
    for (init.body) |stmt| {
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
    try self.emitIndent();
    // Use @This(){} for struct literal initialization
    try self.emit("return @This(){\n");
    self.indent();

    // Second pass: extract field assignments from __init__ body
    for (init.body) |stmt| {
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
) CodegenError!void {
    // Use __alloc for nested classes to avoid shadowing outer allocator
    const alloc_name = if (self.class_nesting_depth > 1) "__alloc" else "allocator";

    try self.emit("\n");
    try self.emitIndent();
    try self.output.writer(self.allocator).print("pub fn init({s}: std.mem.Allocator", .{alloc_name});

    // Add captured variable pointer parameters
    if (captured_vars) |vars| {
        for (vars) |var_name| {
            try self.emit(", ");
            try self.output.writer(self.allocator).print("__cap_{s}: *std.ArrayList(i64)", .{var_name});
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
        for (init.args) |arg| {
            if (std.mem.eql(u8, arg.name, "self")) continue;

            try self.emit(", ");

            // Check if parameter is used in init body (excluding parent __init__ calls)
            // Parent calls are skipped in codegen, so params only used there are unused
            const is_used = param_analyzer.isNameUsedInInitBody(init.body, arg.name);
            if (!is_used) {
                try self.emit("_");
            }
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), arg.name);
            try self.emit(": ");

            // Type annotation: prefer type hints, fallback to inference
            if (arg.type_annotation) |_| {
                try self.emit(signature.pythonTypeToZig(arg.type_annotation));
            } else {
                const param_type = try class_fields.inferParamType(self, class_name, init, arg.name);
                defer self.allocator.free(param_type);
                try self.emit(param_type);
            }
        }
    }

    // Use @This() for self-referential return type
    try self.emit(") @This() {\n");
    self.indent();

    // Set captured vars context for expression generation
    // In init, captured vars are accessed via __cap_* params, not self.__captured_*
    self.current_class_captures = captured_vars;
    self.inside_init_method = true;
    defer self.current_class_captures = null;
    defer self.inside_init_method = false;

    // First pass: generate non-field assignments (local variables, control flow, etc.)
    // These need to be executed BEFORE the struct is created
    for (init.body) |stmt| {
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
    if (builtin_base) |base_info| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print(".__base_value__ = {s},\n", .{base_info.zig_init});
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
    for (init.body) |stmt| {
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
    // Set current class name for super() support
    self.current_class_name = class.name;
    defer self.current_class_name = null;

    // Set current class's captured variables for expression generation
    // This allows the expression generator to convert `var_name` to `self.__captured_var_name.*`
    self.current_class_captures = captured_vars;
    defer self.current_class_captures = null;

    // Set current class parent for parent method call resolution (e.g., array.array.__getitem__(self, i))
    if (class.bases.len > 0) {
        self.current_class_parent = class.bases[0];
    }
    defer self.current_class_parent = null;

    for (class.body) |stmt| {
        if (stmt == .function_def) {
            const method = stmt.function_def;
            if (std.mem.eql(u8, method.name, "__init__")) continue;

            // Check if this is a skipped test method (has "skip:" docstring)
            // Use the same getSkipReason function used by the test runner to ensure consistency
            const is_skipped = generators.getSkipReason(method) != null;

            const mutates_self = body.methodMutatesSelf(method);
            // Skipped methods don't need allocator since their body is empty
            // Use methodNeedsAllocatorInClass to detect same-class constructor calls like Rat(x)
            const needs_allocator = if (is_skipped) false else allocator_analyzer.methodNeedsAllocatorInClass(method, class.name);
            const actually_uses_allocator = if (is_skipped) false else allocator_analyzer.functionActuallyUsesAllocatorParamInClass(method, class.name);

            // Generate method signature
            // Note: method_nesting_depth tracks whether we're inside a NESTED class inside a method
            // It's incremented when we enter a class inside a method body, not when we enter a method itself
            try signature.genMethodSignatureWithSkip(self, class.name, method, mutates_self, needs_allocator, is_skipped, actually_uses_allocator);

            // Check if this method returns a lambda that captures self (closure)
            // Register it so that callers can mark the variable as a closure
            if (!is_skipped) {
                if (signature.getReturnedLambda(method.body)) |lambda| {
                    if (signature.lambdaCapturesSelf(lambda.body.*)) {
                        // Register as "ClassName.method_name"
                        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class.name, method.name });
                        try self.closure_returning_methods.put(key, {});
                    }
                }
            }

            if (is_skipped) {
                // Generate empty body for skipped test methods
                self.indent();
                try self.emitIndent();
                try self.emit("// skipped test\n");
                self.dedent();
                try self.emitIndent();
                try self.emit("}\n");
            } else {
                try body.genMethodBodyWithAllocatorInfo(self, method, needs_allocator, actually_uses_allocator);
            }
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
                const mutates_self = body.methodMutatesSelf(parent_method);
                // Use methodNeedsAllocatorInClass with parent class name for inherited methods
                const needs_allocator = allocator_analyzer.methodNeedsAllocatorInClass(parent_method, parent.name);
                const actually_uses_allocator = allocator_analyzer.functionActuallyUsesAllocatorParamInClass(parent_method, parent.name);
                // Use genMethodSignatureWithSkip to properly pass actually_uses_allocator flag
                try signature.genMethodSignatureWithSkip(self, class.name, parent_method, mutates_self, needs_allocator, false, actually_uses_allocator);
                try body.genMethodBodyWithAllocatorInfo(self, parent_method, needs_allocator, actually_uses_allocator);
            }
        }
    }
}
