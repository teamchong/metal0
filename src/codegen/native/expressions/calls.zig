/// Function call code generation
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const dispatch = @import("../dispatch.zig");
const lambda_mod = @import("lambda.zig");

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
        const is_module_call = blk: {
            var current = attr.value;
            while (true) {
                if (current.* == .name) {
                    // Found base name - check if it's an imported module
                    break :blk self.imported_modules.contains(current.name.id);
                } else if (current.* == .attribute) {
                    // Keep traversing the chain
                    current = current.attribute.value;
                } else {
                    // Not a name or attribute (e.g., a method call result)
                    break :blk false;
                }
            }
            break :blk false;
        };

        // Add 'try' for module calls (they can error)
        if (is_module_call) {
            try self.output.appendSlice(self.allocator, "try ");
        }

        // Generic method call: obj.method(args)
        try genExpr(self, attr.value.*);
        try self.output.appendSlice(self.allocator, ".");
        try self.output.appendSlice(self.allocator, attr.attr);
        try self.output.appendSlice(self.allocator, "(");

        // For module calls, add allocator as first argument
        if (is_module_call) {
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

        // Add 'try' if function needs allocator (can return errors)
        if (user_func_needs_alloc) {
            try self.output.appendSlice(self.allocator, "try ");
        }

        try self.output.appendSlice(self.allocator, func_name);
        try self.output.appendSlice(self.allocator, "(");

        // For user-defined functions: inject allocator as FIRST argument
        if (user_func_needs_alloc) {
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
