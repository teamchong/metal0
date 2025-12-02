/// Function call code generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const dispatch = @import("../dispatch.zig");
const lambda_mod = @import("lambda.zig");
const zig_keywords = @import("zig_keywords");
const function_traits = @import("../../../analysis/function_traits.zig");
const import_registry = @import("../import_registry.zig");
const generators = @import("../statements/functions/generators.zig");
const shared = @import("../shared_maps.zig");
const RuntimeExceptions = shared.RuntimeExceptions;

fn isRuntimeExceptionType(name: []const u8) bool {
    return RuntimeExceptions.has(name);
}

/// Generate function call - dispatches to specialized handlers or fallback
pub fn genCall(self: *NativeCodegen, call: ast.Node.Call) CodegenError!void {
    // Forward declare genExpr - it's in parent module
    const parent = @import("../expressions.zig");
    const genExpr = parent.genExpr;
    const producesBlockExpression = parent.producesBlockExpression;

    // Try to dispatch to specialized handler
    const dispatched = try dispatch.dispatchCall(self, call);
    if (dispatched) return;

    // Handle from-imported json.loads: from json import loads -> loads()
    // The generated wrapper function takes []const u8, not PyObject
    if (call.func.* == .name) {
        const func_name = call.func.name.id;
        if (std.mem.eql(u8, func_name, "loads") and call.args.len == 1) {
            // Just call the wrapper function directly with the string
            try self.emit("try loads(");
            try genExpr(self, call.args[0]);
            try self.emit(", allocator)");
            return;
        }
        // Handle from-imported array.array: from array import array -> array("B", data)
        // Returns bytes as []const u8 (Python array("B", ...) is byte array)
        if (std.mem.eql(u8, func_name, "array") and call.args.len >= 1) {
            // array("B", data) - typecode and optional initializer
            // For "B" (unsigned byte), just return the data as bytes
            if (call.args.len >= 2) {
                // array("B", "abc") -> "abc" (bytes representation)
                try genExpr(self, call.args[1]);
            } else {
                // array("B") with no initializer -> empty bytes
                try self.emit("\"\"");
            }
            return;
        }
    }

    // Handle chained calls: func(args1)(args2)
    // e.g., functools.lru_cache(1)(testfunction)
    // In this case func is itself a call expression
    if (call.func.* == .call) {
        // Generate: inner_call(outer_args)
        // The inner call returns a callable which is then called with outer args
        try genExpr(self, call.func.*);
        try self.emit("(");

        for (call.args, 0..) |arg, i| {
            if (i > 0) try self.emit(", ");
            try genExpr(self, arg);
        }

        for (call.keyword_args, 0..) |kwarg, i| {
            if (i > 0 or call.args.len > 0) try self.emit(", ");
            try genExpr(self, kwarg.value);
        }

        try self.emit(")");
        return;
    }

    // Handle immediate lambda calls: (lambda x: x * 2)(5)
    if (call.func.* == .lambda) {
        // For immediate calls, we need the function name WITHOUT the & prefix
        // Generate lambda function and get its name
        const lambda = call.func.lambda;

        // Generate unique lambda function name
        const lambda_name = try std.fmt.allocPrint(
            self.allocator,
            "__lambda_{d}",
            .{self.lambda_counter},
        );
        defer self.allocator.free(lambda_name);
        self.lambda_counter += 1;

        // Generate the lambda function definition using lambda_mod
        // We'll do this manually to avoid the & prefix
        var lambda_func = std.ArrayList(u8){};
        const lambda_writer = lambda_func.writer(self.allocator);

        // Function signature
        try lambda_writer.print("fn {s}(", .{lambda_name});

        for (lambda.args, 0..) |arg, i| {
            if (i > 0) try lambda_writer.writeAll(", ");
            try lambda_writer.print("{s}: i64", .{arg.name});
        }

        try lambda_writer.print(") i64 {{\n    return ", .{});

        // Generate body expression
        const saved_output = self.output;
        self.output = std.ArrayList(u8){};
        try genExpr(self, lambda.body.*);
        const body_code = try self.output.toOwnedSlice(self.allocator);
        self.output = saved_output;

        try lambda_writer.writeAll(body_code);
        self.allocator.free(body_code);
        try lambda_writer.writeAll(";\n}\n\n");

        // Store lambda function
        try self.lambda_functions.append(self.allocator, try lambda_func.toOwnedSlice(self.allocator));

        // Generate direct function call (no & prefix for immediate calls)
        try self.emit(lambda_name);
        try self.emit("(");
        for (call.args, 0..) |arg, i| {
            if (i > 0) try self.emit(", ");
            try genExpr(self, arg);
        }
        for (call.keyword_args, 0..) |kwarg, i| {
            if (i > 0 or call.args.len > 0) try self.emit(", ");
            try genExpr(self, kwarg.value);
        }
        try self.emit(")");
        return;
    }

    // Handle method calls (obj.method())
    if (call.func.* == .attribute) {
        const attr = call.func.attribute;

        // Handle object.__hash__(value) - Python's base hash implementation
        // This is equivalent to runtime.pyHash(value) or id(value) for identity hash
        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "object")) {
            if (std.mem.eql(u8, attr.attr, "__hash__")) {
                // object.__hash__(x) -> runtime.pyHash(x) for consistency with hash()
                try self.emit("runtime.pyHash(");
                if (call.args.len > 0) {
                    try genExpr(self, call.args[0]);
                }
                try self.emit(")");
                return;
            }
        }

        // Handle float.__getformat__(typestr) - Python float format introspection
        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "float")) {
            if (std.mem.eql(u8, attr.attr, "__getformat__")) {
                // float.__getformat__('double') -> runtime.floatGetFormat("double")
                try self.emit("runtime.floatGetFormat(");
                if (call.args.len > 0) {
                    try genExpr(self, call.args[0]);
                }
                try self.emit(")");
                return;
            }
        }

        // Handle int.from_bytes(bytes, byteorder) and bool.from_bytes(bytes, byteorder)
        // Python: int.from_bytes(b'\x00\x01', 'big') -> 1
        // Python: bool.from_bytes(b'\x00', 'big') -> False
        if (attr.value.* == .name) {
            const type_name = attr.value.name.id;
            const is_int_type = std.mem.eql(u8, type_name, "int");
            const is_bool_type = std.mem.eql(u8, type_name, "bool");

            if (is_int_type or is_bool_type) {
                if (std.mem.eql(u8, attr.attr, "from_bytes")) {
                    // int.from_bytes(bytes, byteorder) -> runtime.intFromBytes(bytes, byteorder)
                    // bool.from_bytes(bytes, byteorder) -> (runtime.intFromBytes(bytes, byteorder) != 0)
                    if (is_bool_type) {
                        try self.emit("(runtime.intFromBytes(");
                    } else {
                        try self.emit("runtime.intFromBytes(");
                    }
                    if (call.args.len > 0) {
                        try genExpr(self, call.args[0]);
                    }
                    if (call.args.len > 1) {
                        try self.emit(", ");
                        try genExpr(self, call.args[1]);
                    } else {
                        try self.emit(", \"big\"");
                    }
                    if (is_bool_type) {
                        try self.emit(") != 0)");
                    } else {
                        try self.emit(")");
                    }
                    return;
                }

                if (std.mem.eql(u8, attr.attr, "to_bytes") and is_int_type) {
                    // int.to_bytes(value, length, byteorder) -> runtime.intToBytes(value, length, byteorder)
                    // Note: In Python it's value.to_bytes(length, byteorder)
                    // but int.to_bytes(value, length, byteorder) is also valid
                    try self.emit("runtime.intToBytes(__global_allocator, ");
                    for (call.args, 0..) |arg, i| {
                        if (i > 0) try self.emit(", ");
                        try genExpr(self, arg);
                    }
                    try self.emit(")");
                    return;
                }
            }
        }

        // Check if this is a class-level type attribute call (e.g., self.int_class(...))
        // Type attributes are static functions, not methods, so we call them via @This()
        if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
            // Check if current_class_name is set and if this attr is a type attribute
            if (self.current_class_name) |class_name| {
                const type_attr_key = std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class_name, attr.attr }) catch null;
                if (type_attr_key) |key| {
                    if (self.class_type_attrs.get(key)) |type_value| {
                        // This is a type attribute - call as @This().attr_name(args)
                        try self.emit("@This().");
                        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
                        try self.emit("(");
                        for (call.args, 0..) |arg, i| {
                            if (i > 0) try self.emit(", ");
                            try genExpr(self, arg);
                        }
                        // For int type attributes with optional base param, add null if not provided
                        if (std.mem.eql(u8, type_value, "int") and call.args.len == 1) {
                            try self.emit(", null");
                        }
                        try self.emit(")");
                        return;
                    }
                }
            }
        }

        // Helper to check if attribute chain starts with imported module
        // Track module name and function name for registry lookup
        var is_module_call = false;
        var module_name: ?[]const u8 = null;
        const func_name = attr.attr;
        {
            var current = attr.value;
            while (true) {
                if (current.* == .name) {
                    // Found base name - check if it's an imported module
                    const base_name = current.*.name.id;
                    is_module_call = self.imported_modules.contains(base_name);
                    if (is_module_call) {
                        module_name = base_name;
                    }
                    break;
                } else if (current.* == .attribute) {
                    // Keep traversing the chain
                    current = current.*.attribute.value;
                } else {
                    // Not a name or attribute (e.g., a method call result)
                    break;
                }
            }
        }

        // Check if this is a user-defined class method call (f.run() where f is a Foo instance)
        var is_class_method_call = false;
        var class_method_needs_alloc = false;
        var is_nested_class_method_call = false;
        {
            // FIRST: Check if this is a self.method() call within the current class
            // This must be checked BEFORE the generic type inferrer check because
            // var_types["self"] may contain the wrong class when multiple classes exist
            // (it stores the LAST class analyzed, not the current one).
            // When we're inside a class, self always refers to the current class.
            if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                if (self.current_class_name) |class_name| {
                    // Look up method in class registry for current class
                    if (self.class_registry.getClass(class_name)) |class_def| {
                        for (class_def.body) |stmt| {
                            if (stmt == .function_def and std.mem.eql(u8, stmt.function_def.name, attr.attr)) {
                                is_class_method_call = true;
                                // Use analyzeNeedsAllocator (same as signature generation)
                                // to ensure call-site allocator passing matches method signature
                                class_method_needs_alloc = function_traits.analyzeNeedsAllocator(stmt.function_def, class_name);
                                break;
                            }
                        }
                    }
                }
            }
            // SECOND: Check generic class instance method calls (f.run() where f is a Foo instance)
            if (!is_class_method_call) {
                const obj_type = self.type_inferrer.inferExpr(attr.value.*) catch .unknown;
                if (obj_type == .class_instance) {
                    const class_name = obj_type.class_instance;
                    // Look up method in class registry
                    if (self.class_registry.findMethod(class_name, attr.attr)) |method_info| {
                        is_class_method_call = true;
                        // Get the method's FunctionDef from the class and check if it needs allocator
                        // Use analyzeNeedsAllocator to match method signature generation
                        if (self.class_registry.getClass(method_info.class_name)) |class_def| {
                            for (class_def.body) |stmt| {
                                if (stmt == .function_def and std.mem.eql(u8, stmt.function_def.name, attr.attr)) {
                                    class_method_needs_alloc = function_traits.analyzeNeedsAllocator(stmt.function_def, class_name);
                                    break;
                                }
                            }
                        }
                    }
                }
            }
            // THIRD: Check if this is a nested class instance method call (obj.method() where obj = Inner())
            // Nested classes aren't in class_registry, so check nested_class_instances
            if (!is_class_method_call and attr.value.* == .name) {
                const obj_name = attr.value.name.id;
                if (self.nested_class_instances.get(obj_name)) |class_name| {
                    // This is a method call on a nested class instance
                    // Check if this specific method needs allocator
                    is_nested_class_method_call = true;
                    var method_key_buf: [512]u8 = undefined;
                    const method_key = std.fmt.bufPrint(&method_key_buf, "{s}.{s}", .{ class_name, attr.attr }) catch null;
                    if (method_key) |key| {
                        class_method_needs_alloc = self.nested_class_method_needs_alloc.contains(key);
                    }
                }
            }
        }

        // Determine allocator/try requirements from registry or class method analysis
        var needs_alloc = false;
        var needs_try = false;

        if (module_name) |mod| {
            // Look up function metadata in registry
            if (self.import_registry.getFunctionMeta(mod, func_name)) |meta| {
                needs_alloc = !meta.no_alloc; // no_alloc=true means DON'T need allocator
                needs_try = meta.returns_error;
            } else {
                // No metadata - assume needs allocator (conservative)
                needs_alloc = true;
            }
        } else if (is_class_method_call or is_nested_class_method_call) {
            needs_alloc = class_method_needs_alloc;
        }
        // else: other method calls (string, list, etc.) don't need allocator

        // Add 'try' for calls that need allocator (they can error) OR explicitly return errors
        const emit_try = (is_module_call or is_class_method_call or is_nested_class_method_call) and (needs_alloc or needs_try);

        // Check if the object expression produces a block expression (e.g., subscript, list literal)
        // Block expressions cannot have methods called on them directly in Zig
        const needs_temp_var = producesBlockExpression(attr.value.*);

        if (needs_temp_var) {
            // Wrap in block with intermediate variable using unique label:
            // mcall_{id}: { const __obj = <expr>; break :mcall_{id} __obj.method(args); }
            const mcall_label_id = self.block_label_counter;
            self.block_label_counter += 1;
            try self.emitFmt("mcall_{d}: {{ const __obj = ", .{mcall_label_id});
            try genExpr(self, attr.value.*);
            try self.emitFmt("; break :mcall_{d} ", .{mcall_label_id});
            // In defer blocks, 'try' is not allowed - use catch {} instead
            if (emit_try and !self.inside_defer) {
                try self.emit("try ");
            }
            try self.emit("__obj.");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
            try self.emit("(");

            // For module calls or class method calls, add allocator as first argument only if needed
            if ((is_module_call or is_class_method_call or is_nested_class_method_call) and needs_alloc) {
                const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
                try self.emit(alloc_name);
                if (call.args.len > 0 or call.keyword_args.len > 0) {
                    try self.emit(", ");
                }
            }

            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try genExpr(self, arg);
            }

            // Add keyword arguments as positional arguments
            for (call.keyword_args, 0..) |kwarg, i| {
                if (i > 0 or call.args.len > 0) try self.emit(", ");
                try genExpr(self, kwarg.value);
            }

            // In defer blocks, append 'catch {}' to silence errors
            if (emit_try and self.inside_defer) {
                try self.emit(") catch {}; }");
            } else {
                try self.emit("); }");
            }
        } else {
            // Normal path - no wrapping needed
            // In defer blocks, 'try' is not allowed - use catch {} at the end instead
            if (emit_try and !self.inside_defer) {
                try self.emit("try ");
            }

            // Generic method call: obj.method(args)
            // Escape method name if it's a Zig keyword (e.g., "test" -> @"test")
            // IMPORTANT: Numeric literals need parentheses: 1.__round__() -> (1).__round__()
            // Otherwise Zig parses "1." as start of a float literal
            const needs_parens = attr.value.* == .constant and
                (attr.value.constant.value == .int or attr.value.constant.value == .float);
            if (needs_parens) try self.emit("(");
            try genExpr(self, attr.value.*);
            if (needs_parens) try self.emit(")");
            try self.emit(".");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
            try self.emit("(");

            // For module calls or class method calls, add allocator as first argument only if needed
            if ((is_module_call or is_class_method_call or is_nested_class_method_call) and needs_alloc) {
                const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
                try self.emit(alloc_name);
                if (call.args.len > 0 or call.keyword_args.len > 0) {
                    try self.emit(", ");
                }
            }

            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try genExpr(self, arg);
            }

            // Add keyword arguments as positional arguments
            for (call.keyword_args, 0..) |kwarg, i| {
                if (i > 0 or call.args.len > 0) try self.emit(", ");
                try genExpr(self, kwarg.value);
            }

            // Add null for missing optional parameters when calling self.method()
            // Look up method signature to check if we need to fill in defaults
            if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                if (self.current_class_name) |class_name| {
                    var method_key_buf: [512]u8 = undefined;
                    const method_key = std.fmt.bufPrint(&method_key_buf, "{s}.{s}", .{ class_name, attr.attr }) catch null;
                    if (method_key) |key| {
                        if (self.function_signatures.get(key)) |sig| {
                            const provided_args = call.args.len + call.keyword_args.len;
                            const missing_args = if (sig.total_params > provided_args) sig.total_params - provided_args else 0;
                            for (0..missing_args) |j| {
                                if (provided_args > 0 or j > 0) try self.emit(", ");
                                try self.emit("null");
                            }
                        }
                    }
                }
            }

            // In defer blocks, append 'catch {}' to silence errors
            if (emit_try and self.inside_defer) {
                try self.emit(") catch {}");
            } else {
                try self.emit(")");
            }
        }
        return;
    }

    // Check for class instantiation or closure calls
    if (call.func.* == .name) {
        const raw_func_name = call.func.name.id;
        // Check if variable has been renamed (for try/except captured variables)
        const func_name = self.var_renames.get(raw_func_name) orelse raw_func_name;

        // Check if this is a simple lambda (function pointer)
        if (self.lambda_vars.contains(raw_func_name)) {
            // Lambda call: square(5) -> square(5)
            // Function pointers in Zig are called directly
            try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), func_name);
            try self.emit("(");

            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try genExpr(self, arg);
            }

            for (call.keyword_args, 0..) |kwarg, i| {
                if (i > 0 or call.args.len > 0) try self.emit(", ");
                try genExpr(self, kwarg.value);
            }

            try self.emit(")");
            return;
        }

        // Check if this is a closure variable
        if (self.closure_vars.contains(raw_func_name)) {
            // Closure call: add_five(3) -> add_five.call(3)
            // Use the variable name which was already assigned the closure
            // Use writeEscapedIdent (not writeLocalVarName) to match how the closure was defined
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), func_name);
            try self.emit(".call(");

            // Pass args directly - closure fn params are anytype so accept all types
            // Pass class instances by pointer for Python reference semantics
            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                const arg_type = self.inferExprScoped(arg) catch .unknown;
                if (arg_type == .class_instance) {
                    // Don't add & for renamed variables (param reassignment creates var, already a value)
                    const is_renamed_var = if (arg == .name)
                        self.var_renames.contains(arg.name.id)
                    else
                        false;
                    // Don't add & for anytype params - they need actual value for type checking
                    const is_anytype_param = if (arg == .name)
                        self.anytype_params.contains(arg.name.id)
                    else
                        false;
                    if (!is_renamed_var and !is_anytype_param) {
                        try self.emit("&");
                    }
                }
                try genExpr(self, arg);
            }

            for (call.keyword_args, 0..) |kwarg, i| {
                if (i > 0 or call.args.len > 0) try self.emit(", ");
                try genExpr(self, kwarg.value);
            }

            try self.emit(")");
            return;
        }

        // Check if this is a callable variable (PyCallable - from iterating over callable list)
        if (self.callable_vars.contains(raw_func_name)) {
            // Callable call: f("100") -> f.call("100")
            try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), func_name);
            try self.emit(".call(");

            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try genExpr(self, arg);
            }

            for (call.keyword_args, 0..) |kwarg, i| {
                if (i > 0 or call.args.len > 0) try self.emit(", ");
                try genExpr(self, kwarg.value);
            }

            try self.emit(")");
            return;
        }

        // FIRST: Check if this is a callable class instance (variable holding instance with __call__)
        // e.g., AbstractSuper = AbstractClass(bases=()) then AbstractSuper() should call __call__
        const var_type = self.getVarType(raw_func_name);
        if (var_type) |vt| {
            if (vt == .class_instance) {
                const class_name = vt.class_instance;
                // Check if this class has __call__ method
                if (self.class_registry.findMethod(class_name, "__call__") != null) {
                    // Generate: instance.__call__()
                    try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), func_name);
                    try self.emit(".__call__(");
                    for (call.args, 0..) |arg, i| {
                        if (i > 0) try self.emit(", ");
                        try genExpr(self, arg);
                    }
                    try self.emit(")");
                    return;
                }
            }
        }

        // Check if this is a class constructor:
        // 1. Name starts with uppercase (Python convention), OR
        // 2. Name is in class registry (handles lowercase class names like "base_set")
        // Use raw_func_name for checking class registry (original Python name)
        // Also check nested_class_names - nested classes inside functions won't be in class_registry
        // Also check symbol_table for locally defined classes (const MyClass = struct{...})
        // Also check current_class_name - when inside a class method calling own class constructor
        const in_class_registry = self.class_registry.getClass(raw_func_name) != null;
        const in_nested_names = self.nested_class_names.contains(raw_func_name);
        const in_local_scope = self.symbol_table.lookup(raw_func_name) != null;
        // Check if we're calling our own class constructor from within the class
        const is_self_class_call = if (self.current_class_name) |cn|
            std.mem.eql(u8, cn, raw_func_name)
        else
            false;
        const is_user_class = in_class_registry or in_nested_names or in_local_scope or is_self_class_call;
        const is_class_constructor = is_user_class or (raw_func_name.len > 0 and std.ascii.isUpper(raw_func_name[0]));

        // Check if this is a runtime exception type that needs runtime. prefix
        const is_runtime_exception = isRuntimeExceptionType(raw_func_name);

        if (is_class_constructor) {
            // Class instantiation: Counter(10) -> Counter.init(__global_allocator, 10)
            // User-defined classes return the struct directly, library classes like Path may return error unions

            // Use is_self_class_call computed earlier - calling our own class constructor uses @This()
            // e.g., `return aug_test(self.val + val)` inside aug_test.__add__

            // Determine if allocator should be passed to init
            // User-defined classes (in class_registry or nested_names) need allocator
            // Local structs (namedtuples, etc.) don't need allocator
            const needs_allocator = in_class_registry or in_nested_names or is_self_class_call;

            // Nested classes have init() returning !*@This() (error union with pointer)
            // So we need try for: nested class calls, or self-class calls when inside a nested class
            // Also need try for classes with type-check patterns in __init__ (returns !@This())
            const current_class_is_nested = if (self.current_class_name) |ccn| self.nested_class_names.contains(ccn) else false;
            const needs_try_for_nested = in_nested_names or (is_self_class_call and current_class_is_nested);
            const has_error_init = self.error_init_classes.contains(raw_func_name);
            const needs_try = needs_try_for_nested or has_error_init;

            if (is_user_class) {
                // User-defined class: nested classes and error init classes need try
                if (needs_try) {
                    try self.emit("(try ");
                }
                if (is_self_class_call) {
                    try self.emit("@This()");
                } else {
                    try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), func_name);
                    // Track that we actually used this nested class in generated Zig code
                    // This is used to determine which classes need _ = ClassName; suppression
                    if (in_nested_names) {
                        try self.nested_class_zig_refs.put(raw_func_name, {});
                    }
                }
                if (needs_allocator) {
                    try self.emit(".init(__global_allocator");
                } else {
                    try self.emit(".init(");
                }
            } else if (is_runtime_exception) {
                // Runtime exception type: Exception(arg) -> runtime.Exception.initWithArg(__global_allocator, arg)
                try self.emit("(try runtime.");
                try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), func_name);
                // Use initWithArg for single arg, initWithArgs for multiple, init for no args
                if (call.args.len == 0 and call.keyword_args.len == 0) {
                    try self.emit(".init(__global_allocator))");
                    return;
                } else if (call.args.len == 1 and call.keyword_args.len == 0) {
                    try self.emit(".initWithArg(__global_allocator, ");
                    try genExpr(self, call.args[0]);
                    try self.emit("))");
                    return;
                } else {
                    // Multiple args - build PyValue array
                    try self.emit(".initWithArgs(__global_allocator, &[_]runtime.PyValue{");
                    for (call.args, 0..) |arg, i| {
                        if (i > 0) try self.emit(", ");
                        try self.emit("runtime.PyValue.from(");
                        try genExpr(self, arg);
                        try self.emit(")");
                    }
                    try self.emit("}))");
                    return;
                }
            } else {
                // Unknown class: assume user-defined class with non-error init
                // Library classes like Path are dispatched separately, so if we reach here
                // it's likely a local class that wasn't tracked in nested_class_names
                // (e.g., due to scoping issues). User-defined init() returns struct directly.
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), func_name);
                if (call.args.len == 0 and call.keyword_args.len == 0) {
                    try self.emit(".init(__global_allocator");
                } else {
                    try self.emit(".init(__global_allocator, ");
                }
            }

            // Check if this class has captured variables - pass pointers to them
            if (self.nested_class_captures.get(raw_func_name)) |captured_vars| {
                for (captured_vars) |var_name| {
                    try self.emit(", &");
                    // Use renamed variable if inside TryHelper or other scope
                    if (self.var_renames.get(var_name)) |renamed| {
                        try self.emit(renamed);
                    } else {
                        try self.emit(var_name);
                    }
                }
            }

            // Check if class inherits from builtin type and needs default args
            // e.g., BadIndex(int) called as BadIndex() should supply default 0
            const builtin_base_info: ?generators.BuiltinBaseInfo = blk: {
                if (call.args.len == 0 and call.keyword_args.len == 0) {
                    // No args provided - check if class has builtin base with defaults
                    // First check class_registry (for top-level classes)
                    if (self.class_registry.getClass(raw_func_name)) |class_def| {
                        if (class_def.bases.len > 0) {
                            break :blk generators.getBuiltinBaseInfo(class_def.bases[0]);
                        }
                    }
                    // Then check nested_class_bases (for nested classes inside methods)
                    if (self.nested_class_bases.get(raw_func_name)) |base_name| {
                        break :blk generators.getBuiltinBaseInfo(base_name);
                    }
                }
                break :blk null;
            };

            // Add args: either user-provided or defaults from builtin base
            if (builtin_base_info) |base_info| {
                // No user args but class inherits from builtin - use defaults
                for (base_info.init_args) |arg| {
                    try self.emit(", ");
                    if (arg.default) |default_val| {
                        try self.emit(default_val);
                    } else {
                        // Required arg with no default - shouldn't happen for proper Python code
                        try self.emit("undefined");
                    }
                }
            } else {
                // User-provided args
                // Only add comma if allocator was emitted
                if ((call.args.len > 0 or call.keyword_args.len > 0) and needs_allocator) {
                    try self.emit(", ");
                }

                // Check if class inherits from builtin type (int, float, etc.)
                // If so, we need to convert class instance args to primitive type
                const inherits_float = blk: {
                    if (self.class_registry.getClass(raw_func_name)) |class_def| {
                        if (class_def.bases.len > 0) {
                            if (std.mem.eql(u8, class_def.bases[0], "float")) {
                                break :blk true;
                            }
                        }
                    }
                    if (self.nested_class_bases.get(raw_func_name)) |base_name| {
                        if (std.mem.eql(u8, base_name, "float")) {
                            break :blk true;
                        }
                    }
                    break :blk false;
                };

                for (call.args, 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");

                    // Handle starred expression: *tuple unpacks to tuple.@"0", tuple.@"1", ...
                    if (arg == .starred) {
                        // For starred expressions in class constructors, unpack the tuple
                        // Generate: tuple.@"0", tuple.@"1" (assuming 2-element tuple for Fraction)
                        // We use block expressions with unique labels
                        const label1 = self.block_label_counter;
                        self.block_label_counter += 1;
                        const label2 = self.block_label_counter;
                        self.block_label_counter += 1;
                        try self.emitFmt("unpack_{d}: {{ const __t = ", .{label1});
                        try genExpr(self, arg.starred.value.*);
                        try self.emitFmt("; break :unpack_{d} __t.@\"0\"; }}, unpack_{d}: {{ const __t = ", .{ label1, label2 });
                        try genExpr(self, arg.starred.value.*);
                        try self.emitFmt("; break :unpack_{d} __t.@\"1\"; }}", .{label2});
                        continue;
                    }

                    // Check if arg type is known at compile time
                    const arg_type = self.type_inferrer.inferExpr(arg) catch .unknown;

                    // For float subclass constructors, we may need runtime conversion
                    // of class instances to float values
                    if (inherits_float) {
                        // Check if arg is definitely a float/number - no conversion needed
                        const is_definitely_float = (arg_type == .float) or (arg_type == .int) or
                            (arg == .constant and (arg.constant.value == .float or arg.constant.value == .int));

                        if (is_definitely_float) {
                            try genExpr(self, arg);
                        } else if (arg_type == .class_instance) {
                            // Known class instance - use floatBuiltinCall
                            try self.emit("(runtime.floatBuiltinCall(");
                            try genExpr(self, arg);
                            try self.emit(", .{}) catch 0.0)");
                        } else {
                            // Unknown type - use runtime conversion that handles both
                            try self.emit("runtime.toFloat(");
                            try genExpr(self, arg);
                            try self.emit(")");
                        }
                    } else {
                        // Check if passing 'self' from method context to class constructor
                        // In Zig, 'self' in methods is *const @This(), but constructors expect value type
                        // So we need to dereference: self -> self.*
                        const is_self_in_method = arg == .name and
                            std.mem.eql(u8, arg.name.id, "self") and
                            self.current_class_name != null;
                        if (is_self_in_method) {
                            try self.emit("self.*");
                        } else {
                            try genExpr(self, arg);
                        }
                    }
                }

                for (call.keyword_args, 0..) |kwarg, i| {
                    if (i > 0 or call.args.len > 0) try self.emit(", ");

                    // Check if parameter type is *runtime.PyObject (widened from incompatible types)
                    // If so, wrap tuple/list literals in runtime.PyValue.tuple(...).toObject()
                    var kwarg_key_buf: [256]u8 = undefined;
                    const kwarg_key = std.fmt.bufPrint(&kwarg_key_buf, "{s}.{s}", .{ raw_func_name, kwarg.name }) catch null;
                    const param_type = if (kwarg_key) |key| self.type_inferrer.var_types.get(key) else null;

                    if (param_type) |pt| {
                        if (pt == .unknown and kwarg.value == .tuple) {
                            // Tuple arg to PyObject param - dynamically typed, use undefined placeholder
                            // This field will be set at runtime via __dict__ or similar mechanism
                            try self.emit("undefined");
                            continue;
                        }
                    }

                    try genExpr(self, kwarg.value);
                }

                // Fill in missing default arguments from __init__ method
                // e.g., Rat(7) should become Rat.init(allocator, 7, 1) if def __init__(num=0, den=1)
                if (self.class_registry.findMethod(raw_func_name, "__init__")) |init_info| {
                    // Skip 'self' parameter (first param in __init__)
                    const init_params = init_info.params;
                    const num_provided = call.args.len + call.keyword_args.len;
                    // num_required_params excludes 'self'
                    const num_init_params = if (init_params.len > 0) init_params.len - 1 else 0;

                    // If we provided fewer args than params (excluding self), fill in defaults
                    if (num_provided < num_init_params) {
                        // Start from the first missing param
                        var param_idx: usize = num_provided + 1; // +1 to skip 'self'
                        while (param_idx < init_params.len) : (param_idx += 1) {
                            const param = init_params[param_idx];
                            if (param.default) |default_expr| {
                                try self.emit(", ");
                                try genExpr(self, default_expr.*);
                            }
                        }
                    }
                }
            }

            // All paths here use single closing paren for .init(...)
            // Runtime exception path with (try ...) already returned earlier at line 588/592/603
            try self.emit(")");
            // Close the (try ...) wrapper for nested class or error-init constructors
            if (needs_try) {
                try self.emit(")");
            }
            return;
        }

        // Fallback: regular function call
        // Use raw_func_name for registry lookups (original Python name)
        // Check if this is a user-defined function that needs allocator
        // Use BOTH: registry (for already-processed functions) AND funcNeedsAllocator (for forward references)
        // This handles cases where function is called before it's defined in file order
        const user_func_needs_alloc = self.functions_needing_allocator.contains(raw_func_name) or
            self.funcNeedsAllocator(raw_func_name);

        // Check if this is a from-imported function that needs allocator
        const from_import_needs_alloc = self.from_import_needs_allocator.contains(raw_func_name);

        // Check if this is an async function (needs _async suffix)
        const is_async_func = self.async_functions.contains(raw_func_name);

        // Check if this is a vararg function (needs args wrapped in slice)
        const is_vararg_func = self.vararg_functions.contains(raw_func_name);

        // Check if this is a kwarg function (needs args wrapped in PyDict)
        const is_kwarg_func = self.kwarg_functions.contains(raw_func_name);

        // Add 'try' if function needs allocator or is async (both return errors)
        // Note: kwarg functions don't need try - the block expression handles errors
        if (user_func_needs_alloc or is_async_func) {
            try self.emit("try ");
        }

        // Use renamed func_name for output, with special handling for main
        const output_name = if (std.mem.eql(u8, raw_func_name, "main")) "__user_main" else func_name;

        // Async functions need _async suffix for the wrapper function
        // Escape Zig reserved keywords (e.g., "test" -> @"test")
        try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), output_name);
        if (is_async_func) {
            try self.emit("_async");
        }
        try self.emit("(");

        // For user-defined functions: inject allocator as FIRST argument
        // BUT NOT for async functions - the _async wrapper doesn't take allocator
        if (user_func_needs_alloc and !is_async_func) {
            const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
            try self.emit(alloc_name);
            if (call.args.len > 0 or call.keyword_args.len > 0 or is_vararg_func) {
                try self.emit(", ");
            }
        }

        // Check if function has default parameters
        const func_sig = self.function_signatures.get(raw_func_name);
        const has_defaults = if (func_sig) |sig| sig.total_params > sig.required_params else false;

        // Add regular arguments - wrap in slice for vararg functions
        if (is_vararg_func) {
            // Check if any args are starred (unpacked)
            var has_starred = false;
            for (call.args) |arg| {
                if (arg == .starred) {
                    has_starred = true;
                    break;
                }
            }

            if (has_starred) {
                // Build slice at runtime by concatenating unpacked arrays
                // For now: if there's a starred arg, just pass it directly (assume single starred arg)
                var found_starred = false;
                for (call.args) |arg| {
                    if (arg == .starred) {
                        // Generate the value with & prefix to convert array to slice
                        // *[1,2] becomes &[_]i64{1, 2} which is []const i64
                        try self.emit("&");
                        try genExpr(self, arg.starred.value.*);
                        found_starred = true;
                        break;
                    }
                }
                if (!found_starred) {
                    // Shouldn't happen, but handle gracefully
                    try self.emit("&[_]i64{}");
                }
            } else {
                // Normal case: wrap args in slice
                try self.emit("&[_]i64{");
                for (call.args, 0..) |arg, i| {
                    if (i > 0) try self.emit(", ");
                    try genExpr(self, arg);
                }
                try self.emit("}");
            }
        } else {
            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                // Check if argument is a class instance - pass by pointer for Python semantics
                const arg_type = self.inferExprScoped(arg) catch .unknown;
                if (arg_type == .class_instance) {
                    // Don't add & for renamed variables (param reassignment creates var, already a value)
                    const is_renamed_var = if (arg == .name)
                        self.var_renames.contains(arg.name.id)
                    else
                        false;
                    // Don't add & for anytype params - they need actual value for type checking
                    const is_anytype_param = if (arg == .name)
                        self.anytype_params.contains(arg.name.id)
                    else
                        false;
                    if (!is_renamed_var and !is_anytype_param) {
                        // Pass class instances by pointer to allow mutations to propagate
                        try self.emit("&");
                    }
                }
                try genExpr(self, arg);
            }

            // For kwarg functions: build PyDict from keyword arguments
            if (is_kwarg_func) {
                // Generate a block expression that creates and populates a PyDict
                if (call.args.len > 0) try self.emit(", ");
                try self.emit("blk: {\n");
                self.indent_level += 1;
                try self.emitIndent();
                try self.emit("const __kwargs = try runtime.PyDict.create(__global_allocator);\n");

                // Add each keyword argument to the dict
                for (call.keyword_args) |kwarg| {
                    try self.emitIndent();
                    try self.emit("try runtime.PyDict.set(__kwargs, \"");
                    try self.emit(kwarg.name);
                    try self.emit("\", ");

                    // Wrap the value in a PyObject - for now assume int
                    // TODO: Handle other types
                    try self.emit("try runtime.PyInt.create(__global_allocator, ");
                    try genExpr(self, kwarg.value);
                    try self.emit("));\n");
                }

                try self.emitIndent();
                try self.emit("break :blk __kwargs;\n");
                self.indent_level -= 1;
                try self.emitIndent();
                try self.emit("}");
            } else {
                // Add keyword arguments as positional arguments (non-kwarg functions)
                // TODO: Map keyword args to correct parameter positions
                for (call.keyword_args, 0..) |kwarg, i| {
                    if (i > 0 or call.args.len > 0) try self.emit(", ");
                    try genExpr(self, kwarg.value);
                }

                // Pad with null for missing default parameters
                if (has_defaults) {
                    if (func_sig) |sig| {
                        const provided_args = call.args.len + call.keyword_args.len;
                        if (provided_args < sig.total_params) {
                            var i: usize = provided_args;
                            while (i < sig.total_params) : (i += 1) {
                                if (i > 0) try self.emit(", ");
                                try self.emit("null");
                            }
                        }
                    }
                }

                // Special case: calling a variable that's a renamed type attribute (e.g., int_class -> _local_int_class)
                // If this is an int type attribute, it needs a second null arg for the base parameter
                if (self.var_renames.get(raw_func_name)) |_| {
                    // Check if this is a type attribute of int type
                    if (self.current_class_name) |class_name| {
                        var type_attr_key_buf: [512]u8 = undefined;
                        const type_attr_key = std.fmt.bufPrint(&type_attr_key_buf, "{s}.{s}", .{ class_name, raw_func_name }) catch null;
                        if (type_attr_key) |key| {
                            if (self.class_type_attrs.get(key)) |type_value| {
                                if (std.mem.eql(u8, type_value, "int") and call.args.len == 1) {
                                    try self.emit(", null");
                                }
                            }
                        }
                    }
                }
            }
        }

        // For from-imported functions: inject allocator as LAST argument
        if (from_import_needs_alloc) {
            if (call.args.len > 0 or call.keyword_args.len > 0) {
                try self.emit(", ");
            }
            const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
            try self.emit(alloc_name);
        }

        try self.emit(")");
        return;
    }

    // Fallback for any other func type (e.g., subscript like dict['key']() or other expressions)
    // Generate a generic call expression
    try genExpr(self, call.func.*);
    try self.emit("(");

    for (call.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try genExpr(self, arg);
    }

    for (call.keyword_args, 0..) |kwarg, i| {
        if (i > 0 or call.args.len > 0) try self.emit(", ");
        try genExpr(self, kwarg.value);
    }

    try self.emit(")");
}
