/// Function call code generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const dispatch = @import("../dispatch.zig");
const lambda_mod = @import("lambda.zig");
const zig_keywords = @import("zig_keywords");
const allocator_analyzer = @import("../statements/functions/allocator_analyzer.zig");
const import_registry = @import("../import_registry.zig");

/// Check if an expression will generate a Zig block expression (blk: {...})
/// Block expressions cannot have methods called on them directly in Zig
fn producesBlockExpression(expr: ast.Node) bool {
    return switch (expr) {
        .subscript => true, // lines[idx] generates blk: {...}
        .list => true, // [1,2,3] generates block expression
        .dict => true, // {k:v} generates block expression
        .set => true, // {1,2,3} generates block expression
        .listcomp => true, // [x for x in y] generates block
        .dictcomp => true, // {k:v for...} generates block
        .genexp => true, // (x for x in y) generates block
        .if_expr => true, // a if cond else b generates block
        .call => true, // function calls may produce block expressions
        else => false,
    };
}

/// Generate function call - dispatches to specialized handlers or fallback
pub fn genCall(self: *NativeCodegen, call: ast.Node.Call) CodegenError!void {
    // Forward declare genExpr - it's in parent module
    const parent = @import("../expressions.zig");
    const genExpr = parent.genExpr;

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
        {
            const obj_type = self.type_inferrer.inferExpr(attr.value.*) catch .unknown;
            if (obj_type == .class_instance) {
                const class_name = obj_type.class_instance;
                // Look up method in class registry
                if (self.class_registry.findMethod(class_name, attr.attr)) |method_info| {
                    is_class_method_call = true;
                    // Get the method's FunctionDef from the class and check if it needs allocator
                    if (self.class_registry.getClass(method_info.class_name)) |class_def| {
                        for (class_def.body) |stmt| {
                            if (stmt == .function_def and std.mem.eql(u8, stmt.function_def.name, attr.attr)) {
                                class_method_needs_alloc = allocator_analyzer.functionNeedsAllocator(stmt.function_def);
                                break;
                            }
                        }
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
        } else if (is_class_method_call) {
            needs_alloc = class_method_needs_alloc;
        }
        // else: other method calls (string, list, etc.) don't need allocator

        // Add 'try' for calls that need allocator (they can error) OR explicitly return errors
        const emit_try = (is_module_call or is_class_method_call) and (needs_alloc or needs_try);

        // Check if the object expression produces a block expression (e.g., subscript, list literal)
        // Block expressions cannot have methods called on them directly in Zig
        const needs_temp_var = producesBlockExpression(attr.value.*);

        if (needs_temp_var) {
            // Wrap in block with intermediate variable:
            // blk: { const __obj = <expr>; break :blk __obj.method(args); }
            try self.emit("blk: { const __obj = ");
            try genExpr(self, attr.value.*);
            try self.emit("; break :blk ");
            if (emit_try) {
                try self.emit("try ");
            }
            try self.emit("__obj.");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
            try self.emit("(");

            // For module calls or class method calls, add allocator as first argument only if needed
            if ((is_module_call or is_class_method_call) and needs_alloc) {
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

            try self.emit("); }");
        } else {
            // Normal path - no wrapping needed
            if (emit_try) {
                try self.emit("try ");
            }

            // Generic method call: obj.method(args)
            // Escape method name if it's a Zig keyword (e.g., "test" -> @"test")
            try genExpr(self, attr.value.*);
            try self.emit(".");
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), attr.attr);
            try self.emit("(");

            // For module calls or class method calls, add allocator as first argument only if needed
            if ((is_module_call or is_class_method_call) and needs_alloc) {
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

            try self.emit(")");
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
            try self.emit(func_name);
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
            try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), func_name);
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

        // If name starts with uppercase, it's a class constructor
        // Use raw_func_name for checking class registry (original Python name)
        if (raw_func_name.len > 0 and std.ascii.isUpper(raw_func_name[0])) {
            // Class instantiation: Counter(10) -> Counter.init(allocator, 10)
            // User-defined classes return the struct directly, library classes like Path may return error unions
            const is_user_class = self.class_registry.getClass(raw_func_name) != null;

            if (is_user_class) {
                // User-defined class: init returns struct directly, no try needed
                // Always use __global_allocator since the method may not have allocator param
                try self.emit(func_name);
                try self.emit(".init(__global_allocator");
            } else {
                // Library class (e.g. Path): may return error union, wrap in (try ...)
                // Use __alloc for nested class methods to avoid shadowing outer allocator
                // class_nesting_depth: 1 = top-level class, 2+ = nested class
                const alloc_name = if (self.class_nesting_depth > 1) "__alloc" else "allocator";
                try self.emit("(try ");
                try self.emit(func_name);
                try self.output.writer(self.allocator).print(".init({s}", .{alloc_name});
            }

            // Add comma if there are args
            if (call.args.len > 0 or call.keyword_args.len > 0) {
                try self.emit(", ");
            }

            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try genExpr(self, arg);
            }

            for (call.keyword_args, 0..) |kwarg, i| {
                if (i > 0 or call.args.len > 0) try self.emit(", ");
                try genExpr(self, kwarg.value);
            }

            if (is_user_class) {
                try self.emit(")");
            } else {
                try self.emit("))");
            }
            return;
        }

        // Fallback: regular function call
        // Use raw_func_name for registry lookups (original Python name)
        // Check if this is a user-defined function that needs allocator
        const user_func_needs_alloc = self.functions_needing_allocator.contains(raw_func_name);

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
                try genExpr(self, arg);
            }

            // For kwarg functions: build PyDict from keyword arguments
            if (is_kwarg_func) {
                // Generate a block expression that creates and populates a PyDict
                if (call.args.len > 0) try self.emit(", ");
                try self.emit("blk: {\n");
                self.indent_level += 1;
                try self.emitIndent();
                try self.emit("const __kwargs = try runtime.PyDict.create(allocator);\n");

                // Add each keyword argument to the dict
                for (call.keyword_args) |kwarg| {
                    try self.emitIndent();
                    try self.emit("try runtime.PyDict.set(__kwargs, \"");
                    try self.emit(kwarg.name);
                    try self.emit("\", ");

                    // Wrap the value in a PyObject - for now assume int
                    // TODO: Handle other types
                    try self.emit("try runtime.PyInt.create(allocator, ");
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
