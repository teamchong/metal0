/// Return statement code generation
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const builder_mod = @import("codegen.builder");
const ZigBuilder = builder_mod.ZigBuilder;

/// Check if a return value is a tail-recursive call to the current function
/// A tail call is: return func_name(args) where func_name == current function
fn isTailRecursiveCall(self: *NativeCodegen, value: ast.Node) ?ast.Node.Call {
    // Must be inside a function
    const current_func = self.current_function_name orelse return null;

    // Must be a call expression
    if (value != .call) return null;
    const call = value.call;

    // Function must be a simple name (not attribute/method call)
    if (call.func.* != .name) return null;
    const func_name = call.func.name.id;

    // Must be calling the current function
    if (!std.mem.eql(u8, func_name, current_func)) return null;

    return call;
}

/// Magic method return conversion info
const MagicMethodConversion = struct {
    prefix: []const u8,
    suffix: []const u8,
};

/// Get conversion wrapper for magic method return values
/// Some dunder methods have fixed return types that require conversion
fn getMagicMethodConversion(method_name: []const u8) ?MagicMethodConversion {
    const converters = std.StaticStringMap(MagicMethodConversion).initComptime(.{
        // Python 3: __bool__ must return exactly bool, not converted from other types
        .{ "__bool__", MagicMethodConversion{ .prefix = "runtime.validateBoolReturn(", .suffix = ")" } },
        // Use runtime.pyToInt for __len__/__hash__/__int__/__index__ to handle both int and PyValue
        .{ "__len__", MagicMethodConversion{ .prefix = "runtime.pyToInt(", .suffix = ")" } },
        .{ "__hash__", MagicMethodConversion{ .prefix = "runtime.pyToInt(", .suffix = ")" } },
        .{ "__int__", MagicMethodConversion{ .prefix = "runtime.pyToInt(", .suffix = ")" } },
        .{ "__index__", MagicMethodConversion{ .prefix = "runtime.pyToInt(", .suffix = ")" } },
        // Python 3: __float__ must return exactly float, not int - raises TypeError otherwise
        .{ "__float__", MagicMethodConversion{ .prefix = "runtime.validateFloatReturn(", .suffix = ")" } },
    });
    return converters.get(method_name);
}

/// Comparison magic methods that return bool
const ComparisonMagicMethods = std.StaticStringMap(void).initComptime(.{
    .{ "__eq__", {} },
    .{ "__ne__", {} },
    .{ "__lt__", {} },
    .{ "__le__", {} },
    .{ "__gt__", {} },
    .{ "__ge__", {} },
});

/// Check if an expression is already a PyValue (doesn't need wrapping)
fn isAlreadyPyValue(expr: ast.Node) bool {
    switch (expr) {
        // Call expressions might return PyValue (we can't tell for sure, so assume yes)
        .call => return true,
        // Names could be PyValue variables (assume yes to be safe)
        .name => return true,
        // Attribute access could be PyValue (assume yes)
        .attribute => return true,
        // Subscript access could be PyValue (assume yes)
        .subscript => return true,
        // Everything else (boolean operators, comparisons, literals) are primitives
        else => return false,
    }
}

/// Generate test execution code for factory-returned test classes
/// This runs tests inside the factory function where captured variables are accessible
fn genFactoryTestExecution(self: *NativeCodegen) CodegenError!void {
    // Check if we're inside a factory function
    const func_name = self.current_function_name orelse return;
    const factory_info = self.test_factories.get(func_name) orelse return;

    // Generate test execution for each test class in the factory
    try self.emit("\n    // Factory test execution - run tests before returning\n");

    for (factory_info.returned_classes, 0..) |class_info, class_idx| {
        const class_name = class_info.class_name;

        // Use labeled block for each class so we can skip on init failure
        try self.output.writer(self.allocator).print("    __factory_class_{d}: {{\n", .{class_idx});

        // Create instance
        try self.output.writer(self.allocator).print("        var __test_instance_{s} = {s}.init(__global_allocator", .{ class_name, class_name });

        // Add captured variable arguments if the class has them in nested_class_captures
        if (self.nested_class_captures.get(class_name)) |captures| {
            for (captures) |cap| {
                try self.output.writer(self.allocator).print(", &{s}", .{cap});
            }
        }

        try self.output.writer(self.allocator).print(") catch {{ break :__factory_class_{d}; }};\n", .{class_idx});

        // Run setUp if exists
        if (class_info.has_setUp) {
            try self.output.writer(self.allocator).print("        __test_instance_{s}.setUp(__global_allocator) catch {{}};\n", .{class_name});
        }

        // Run each test method
        for (class_info.test_methods, 0..) |method_info, test_idx| {
            if (method_info.skip_reason != null) continue;

            // Use labeled block for each test so we can skip on failure
            try self.output.writer(self.allocator).print("        __factory_test_{d}_{d}: {{\n", .{ class_idx, test_idx });
            try self.output.writer(self.allocator).print("            runtime.print(\"test_{s}_{s} ... \", .{{}});\n", .{ class_name, method_info.name });

            if (method_info.returns_error) {
                try self.output.writer(self.allocator).print("            __test_instance_{s}.{s}(__global_allocator) catch |err| {{\n", .{ class_name, method_info.name });
                try self.emit("                runtime.print(\"FAIL: {any}\\n\", .{err});\n");
                // Run tearDown on failure
                if (class_info.has_tearDown) {
                    try self.output.writer(self.allocator).print("                __test_instance_{s}.tearDown();\n", .{class_name});
                }
                try self.output.writer(self.allocator).print("                break :__factory_test_{d}_{d};\n", .{ class_idx, test_idx });
                try self.emit("            };\n");
            } else {
                try self.output.writer(self.allocator).print("            __test_instance_{s}.{s}();\n", .{ class_name, method_info.name });
            }

            // Run tearDown on success
            if (class_info.has_tearDown) {
                try self.output.writer(self.allocator).print("            __test_instance_{s}.tearDown();\n", .{class_name});
            }

            try self.emit("            runtime.print(\"ok\\n\", .{});\n");
            try self.emit("        }\n"); // close test block
        }

        try self.emit("    }\n"); // close class block
    }
}

/// Generate return statement with tail-call optimization
pub fn genReturn(self: *NativeCodegen, ret: ast.Node.Return) CodegenError!void {
    // Emit pending discards BEFORE the return statement
    // This handles unused local variables in closures that return early
    // e.g., def f(): msg = "..."; return self.assertRaisesRegex(...) -> msg unused
    try self.emitPendingDiscards();

    // Run factory tests before returning if this is a test factory function
    try genFactoryTestExecution(self);

    // Mark control flow as terminated on any exit path
    defer self.control_flow_terminated = true;

    // Return inside defer block is not allowed in Zig
    // Just skip the return - defer cleanup will still run
    if (self.inside_defer and !self.inside_finally_block) {
        const b = try self.getBuilder();
        try b.writeIndent();
        try b.emitRaw("// return inside defer - skipped (cleanup continues)\n");
        const output = try b.getBodyDupe();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    // Return inside finally block - use break to exit the labeled block
    // The actual return will happen after finally block cleanup
    if (self.inside_finally_block) {
        const b = try self.getBuilder();
        try b.writeIndent();
        // Store the return value and break out of finally block
        // The return will be handled after the finally block
        try b.writeFmt("break :__finally_blk_{d} null; // return from finally\n", .{self.current_finally_id});
        const output = try b.getBodyDupe();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    // Nuitka-style finally code duplication: emit all finally blocks BEFORE return
    // This ensures Python semantics where finally runs before any exit
    if (self.hasActiveFinallyBlocks()) {
        const b = try self.getBuilder();

        // Store return value first (to avoid multiple evaluation)
        if (ret.value) |value| {
            const val = try self.captureExpr(value.*);
            try b.writeIndent();
            try b.emitRaw("const __return_value = ");
            try b.emitValue(val, .{});
            try b.emitRaw(";\n");
        }

        const output1 = try b.getBodyDupe();
        try self.output.appendSlice(self.allocator, output1);

        // Execute all active finally blocks (innermost to outermost)
        try self.emitAllFinallyBlocks();

        // Now emit the actual return
        const b2 = try self.getBuilder();
        try b2.writeIndent();
        if (ret.value != null) {
            try b2.write("return __return_value;\n");
        } else {
            try b2.write("return;\n");
        }
        const output2 = try b2.getBodyDupe();
        try self.output.appendSlice(self.allocator, output2);
        return;
    }

    const b = try self.getBuilder();
    try b.writeIndent();

    if (ret.value) |value| {
        // Check if returning NotImplemented from a comparison method
        // In Python, comparison methods can return NotImplemented to signal fallback
        // Generate runtime.PyValue{ .not_implemented = {} } for proper protocol support
        if (value.* == .name and std.mem.eql(u8, value.name.id, "NotImplemented")) {
            if (self.current_function_name) |fn_name| {
                if (ComparisonMagicMethods.has(fn_name)) {
                    try b.emitRaw("return runtime.PyValue{ .not_implemented = {} };\n");
                    const output = try b.getBodyDupe();
                    try self.output.appendSlice(self.allocator, output);
                    return;
                }
            }
        }

        // For comparison methods that return PyValue, wrap boolean expressions
        if (self.current_function_name) |fn_name| {
            if (ComparisonMagicMethods.has(fn_name)) {
                // Check if we're returning a boolean expression that needs wrapping
                // Detect patterns like: (a == b) and (c == d), which are boolean
                const needs_wrapping = !isAlreadyPyValue(value.*);
                if (needs_wrapping) {
                    // Capture the expression value first, then emit to builder
                    const val = try self.captureExpr(value.*);
                    try b.emitRaw("return runtime.PyValue{ .bool = ");
                    try b.emitValue(val, .{});
                    try b.emitRaw(" };\n");
                    const output = try b.getBodyDupe();
                    try self.output.appendSlice(self.allocator, output);
                    return;
                }
            }
        }

        // Check if returning a pre-generated closure (e.g., return with_metaclass where with_metaclass is a nested function)
        if (value.* == .name) {
            const name = value.name.id;
            if (self.pending_closure_types.get(name)) |type_name| {
                // Return an instance of the pre-generated closure type
                try b.writeFmt("return {s}{{}};\n", .{type_name});
                const output = try b.getBodyDupe();
                try self.output.appendSlice(self.allocator, output);
                return;
            }
        }

        // Check for tail-recursive call
        if (isTailRecursiveCall(self, value.*)) |call| {
            // Emit: return @call(.always_tail, func_name, .{args})
            try b.emitRaw("return @call(.always_tail, ");
            const func_name = call.func.name.id;
            // Check if we're inside a class and the function name shadows a module function.
            // In Python, bare name `func()` calls the module function, not `self.func()`.
            // If module_level_funcs contains this name, use __mod_<name> to avoid ambiguity.
            if (self.current_class_name != null and self.module_level_funcs.contains(func_name)) {
                try b.writeFmt("__mod_{s}", .{func_name});
            } else {
                try b.emitRaw(func_name);
            }
            try b.emitRaw(", .{");

            // Generate arguments
            for (call.args, 0..) |arg, i| {
                if (i > 0) try b.emitRaw(", ");
                const arg_val = try self.captureExpr(arg);
                try b.emitValue(arg_val, .{});
            }

            try b.emitRaw("});\n");
            const output = try b.getBodyDupe();
            try self.output.appendSlice(self.allocator, output);
            return;
        }

        // Normal return - check if inside a magic method that needs conversion
        try b.emitRaw("return ");

        // Check if returning self from a method (with either *@This() or *const @This())
        // When method signature returns !@This() and we return self,
        // we need: return __self.*; (dereference the pointer)
        // This applies to both mutable (*@This()) and immutable (*const @This()) methods
        const is_self_return = self.current_class_name != null and
            value.* == .name and
            std.mem.eql(u8, value.name.id, "self");
        // For methods that return self, always dereference when inside a nested method
        // (where self is renamed to __self) or when method_self_is_mutable
        const needs_self_deref = is_self_return and (self.method_self_is_mutable or self.method_nesting_depth > 0);

        // Check if we're inside a magic method that needs return value conversion
        const conversion = if (self.current_function_name) |fn_name|
            getMagicMethodConversion(fn_name)
        else
            null;

        // Magic method conversion ALWAYS takes precedence (e.g., __bool__ must validate return type)
        if (conversion) |conv| {
            try b.emitRaw(conv.prefix);
            if (needs_self_deref) {
                const self_name = if (self.method_nesting_depth > 0) "__self" else "self";
                const current_class_is_nested = if (self.current_class_name) |ccn| self.nested_class_names.contains(ccn) else false;
                if (current_class_is_nested) {
                    try b.emitRaw(self_name);
                } else {
                    try b.writeFmt("{s}.*", .{self_name});
                }
            } else {
                const val = try self.captureExpr(value.*);
                try b.emitValue(val, .{});
            }
            try b.emitRaw(conv.suffix);
        } else if (needs_self_deref) {
            // For nested classes, return the pointer directly
            // since init() returns *@This() and methods returning self also return *@This()
            // For top-level classes, dereference to return @This() value
            const self_name = if (self.method_nesting_depth > 0) "__self" else "self";
            const current_class_is_nested = if (self.current_class_name) |ccn| self.nested_class_names.contains(ccn) else false;
            // __enter__ returns *@This() (pointer), so don't dereference
            const is_enter_method = if (self.current_function_name) |fn_name|
                std.mem.eql(u8, fn_name, "__enter__")
            else
                false;
            if (current_class_is_nested or is_enter_method) {
                // Nested class or __enter__: return pointer directly
                try b.emitRaw(self_name);
            } else {
                // Top-level class: dereference to get value
                try b.writeFmt("{s}.*", .{self_name});
            }
        } else {
            // Two-Flow: Box return values when function returns PyValue
            // This handles isinstance narrowing where local vars become raw types
            // inside if blocks but function still returns PyValue
            // BUT: Don't wrap if the value is already a PyValue container (ArrayList, etc.)
            const should_wrap = blk: {
                if (!self.current_function_returns_pyvalue) break :blk false;
                // Don't wrap variables that are PyValue containers
                if (value.* == .name) {
                    const var_name = value.name.id;
                    if (self.type_inferrer.getTypedVar(var_name)) |typed_var| {
                        const var_type = typed_var.native_type;
                        // ArrayList/slice of PyValue should not be wrapped
                        if (var_type == .array and var_type.array.element_type.* == .pyvalue) {
                            break :blk false;
                        }
                    }
                }
                break :blk true;
            };

            const val = try self.captureExpr(value.*);
            if (should_wrap) {
                try b.emitRaw("runtime.PyValue.from(");
                try b.emitValue(val, .{});
                try b.emitRaw(")");
            } else {
                try b.emitValue(val, .{});
            }
        }
    } else {
        try b.emitRaw("return ");
    }
    try b.emitRaw(";\n");

    const output = try b.getBodyDupe();
    try self.output.appendSlice(self.allocator, output);
}
