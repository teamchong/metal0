/// Function call code generation
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const dispatch = @import("../dispatch.zig");
const lambda_mod = @import("lambda.zig");

/// Functions that don't require allocator parameter
const NO_ALLOC_FUNCS = [_][]const u8{
    "time.time",
    "time.monotonic",
    "time.perf_counter",
    // math module - all functions are pure and don't allocate
    "math.sqrt",
    "math.sin",
    "math.cos",
    "math.tan",
    "math.asin",
    "math.acos",
    "math.atan",
    "math.atan2",
    "math.sinh",
    "math.cosh",
    "math.tanh",
    "math.asinh",
    "math.acosh",
    "math.atanh",
    "math.log",
    "math.log10",
    "math.log2",
    "math.log1p",
    "math.exp",
    "math.expm1",
    "math.pow",
    "math.floor",
    "math.ceil",
    "math.trunc",
    "math.round",
    "math.fabs",
    "math.abs",
    "math.fmod",
    "math.remainder",
    "math.modf",
    "math.hypot",
    "math.cbrt",
    "math.copysign",
    "math.degrees",
    "math.radians",
    "math.factorial",
    "math.gcd",
    "math.lcm",
    "math.isnan",
    "math.isinf",
    "math.isfinite",
    "math.erf",
    "math.erfc",
    "math.gamma",
    "math.lgamma",
};

/// Check if qualified function name needs allocator
fn needsAllocator(qualified_name: []const u8) bool {
    for (NO_ALLOC_FUNCS) |func| {
        if (std.mem.eql(u8, qualified_name, func)) return false;
    }
    return true; // Default: assume needs allocator
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
            try self.output.appendSlice(self.allocator, "try loads(");
            try genExpr(self, call.args[0]);
            try self.output.appendSlice(self.allocator, ", allocator)");
            return;
        }
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

        // Function signature
        try lambda_func.writer(self.allocator).print("fn {s}(", .{lambda_name});

        for (lambda.args, 0..) |arg, i| {
            if (i > 0) try lambda_func.appendSlice(self.allocator, ", ");
            try lambda_func.writer(self.allocator).print("{s}: i64", .{arg.name});
        }

        try lambda_func.writer(self.allocator).print(") i64 {{\n    return ", .{});

        // Generate body expression
        const saved_output = self.output;
        self.output = std.ArrayList(u8){};
        try genExpr(self, lambda.body.*);
        const body_code = try self.output.toOwnedSlice(self.allocator);
        self.output = saved_output;

        try lambda_func.appendSlice(self.allocator, body_code);
        self.allocator.free(body_code);
        try lambda_func.appendSlice(self.allocator, ";\n}\n\n");

        // Store lambda function
        try self.lambda_functions.append(self.allocator, try lambda_func.toOwnedSlice(self.allocator));

        // Generate direct function call (no & prefix for immediate calls)
        try self.output.appendSlice(self.allocator, lambda_name);
        try self.output.appendSlice(self.allocator, "(");
        for (call.args, 0..) |arg, i| {
            if (i > 0) try self.output.appendSlice(self.allocator, ", ");
            try genExpr(self, arg);
        }
        try self.output.appendSlice(self.allocator, ")");
        return;
    }

    // Handle method calls (obj.method())
    if (call.func.* == .attribute) {
        const attr = call.func.attribute;

        // Helper to check if attribute chain starts with imported module
        // Also build qualified name for allocator check
        var is_module_call = false;
        var qualified_name: ?[]const u8 = null;
        {
            var current = attr.value;
            while (true) {
                if (current.* == .name) {
                    // Found base name - check if it's an imported module
                    is_module_call = self.imported_modules.contains(current.name.id);
                    if (is_module_call) {
                        // Build qualified name: module.function
                        qualified_name = std.fmt.allocPrint(
                            self.allocator,
                            "{s}.{s}",
                            .{ current.name.id, attr.attr },
                        ) catch null;
                    }
                    break;
                } else if (current.* == .attribute) {
                    // Keep traversing the chain
                    current = current.attribute.value;
                } else {
                    // Not a name or attribute (e.g., a method call result)
                    break;
                }
            }
        }
        defer if (qualified_name) |qn| self.allocator.free(qn);

        const needs_alloc = if (qualified_name) |qn|
            needsAllocator(qn)
        else
            true;

        // Add 'try' for module calls that need allocator (they can error)
        if (is_module_call and needs_alloc) {
            try self.output.appendSlice(self.allocator, "try ");
        }

        // Generic method call: obj.method(args)
        try genExpr(self, attr.value.*);
        try self.output.appendSlice(self.allocator, ".");
        try self.output.appendSlice(self.allocator, attr.attr);
        try self.output.appendSlice(self.allocator, "(");

        // For module calls, add allocator as first argument only if needed
        if (is_module_call and needs_alloc) {
            try self.output.appendSlice(self.allocator, "allocator");
            if (call.args.len > 0) {
                try self.output.appendSlice(self.allocator, ", ");
            }
        }

        for (call.args, 0..) |arg, i| {
            if (i > 0) try self.output.appendSlice(self.allocator, ", ");
            try genExpr(self, arg);
        }

        try self.output.appendSlice(self.allocator, ")");
        return;
    }

    // Check for class instantiation or closure calls
    if (call.func.* == .name) {
        const func_name = call.func.name.id;

        // Check if this is a simple lambda (function pointer)
        if (self.lambda_vars.contains(func_name)) {
            // Lambda call: square(5) -> square(5)
            // Function pointers in Zig are called directly
            try self.output.appendSlice(self.allocator, func_name);
            try self.output.appendSlice(self.allocator, "(");

            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.output.appendSlice(self.allocator, ", ");
                try genExpr(self, arg);
            }

            try self.output.appendSlice(self.allocator, ")");
            return;
        }

        // Check if this is a closure variable
        if (self.closure_vars.contains(func_name)) {
            // Closure call: add_five(3) -> add_five.call(3)
            try self.output.appendSlice(self.allocator, func_name);
            try self.output.appendSlice(self.allocator, ".call(");

            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.output.appendSlice(self.allocator, ", ");
                try genExpr(self, arg);
            }

            try self.output.appendSlice(self.allocator, ")");
            return;
        }

        // If name starts with uppercase, it's a class constructor
        if (func_name.len > 0 and std.ascii.isUpper(func_name[0])) {
            // Class instantiation: Counter(10) -> Counter.init(allocator, 10)
            try self.output.appendSlice(self.allocator, func_name);
            try self.output.appendSlice(self.allocator, ".init(allocator");

            // Add comma if there are args
            if (call.args.len > 0) {
                try self.output.appendSlice(self.allocator, ", ");
            }

            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.output.appendSlice(self.allocator, ", ");
                try genExpr(self, arg);
            }

            try self.output.appendSlice(self.allocator, ")");
            return;
        }

        // Fallback: regular function call
        // Check if this is a user-defined function that needs allocator
        const user_func_needs_alloc = self.functions_needing_allocator.contains(func_name);

        // Check if this is a from-imported function that needs allocator
        const from_import_needs_alloc = self.from_import_needs_allocator.contains(func_name);

        // Check if this is an async function (needs _async suffix)
        const is_async_func = self.async_functions.contains(func_name);

        // Add 'try' if function needs allocator or is async (both return errors)
        if (user_func_needs_alloc or is_async_func) {
            try self.output.appendSlice(self.allocator, "try ");
        }

        // Rename "main" to "__user_main" to match function definition renaming
        const output_name = if (std.mem.eql(u8, func_name, "main")) "__user_main" else func_name;

        // Async functions need _async suffix for the wrapper function
        try self.output.appendSlice(self.allocator, output_name);
        if (is_async_func) {
            try self.output.appendSlice(self.allocator, "_async");
        }
        try self.output.appendSlice(self.allocator, "(");

        // For user-defined functions: inject allocator as FIRST argument
        // BUT NOT for async functions - the _async wrapper doesn't take allocator
        if (user_func_needs_alloc and !is_async_func) {
            try self.output.appendSlice(self.allocator, "allocator");
            if (call.args.len > 0) {
                try self.output.appendSlice(self.allocator, ", ");
            }
        }

        // Add regular arguments
        for (call.args, 0..) |arg, i| {
            if (i > 0) try self.output.appendSlice(self.allocator, ", ");
            try genExpr(self, arg);
        }

        // For from-imported functions: inject allocator as LAST argument
        if (from_import_needs_alloc) {
            if (call.args.len > 0) {
                try self.output.appendSlice(self.allocator, ", ");
            }
            try self.output.appendSlice(self.allocator, "allocator");
        }

        try self.output.appendSlice(self.allocator, ")");
    }
}
