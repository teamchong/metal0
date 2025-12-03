/// Recursive closure generation using Y-combinator style pattern
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const hashmap_helper = @import("hashmap_helper");
const var_tracking = @import("var_tracking.zig");

/// Generate a recursive closure using Y-combinator style pattern
/// For recursive closures, we use a struct with a function that receives itself via @This()
pub fn genRecursiveClosure(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    captured_vars: [][]const u8,
) CodegenError!void {
    const saved_counter = self.lambda_counter;
    self.lambda_counter += 1;

    // For recursive closures, we generate:
    // const inner = struct {
    //     var limit: i64 = undefined;  // captures as static vars
    //     var seen: ... = undefined;
    //     pub fn call(w: i64) void {
    //         // body can reference limit, seen, and call itself via call(...)
    //     }
    // };
    // inner.limit = limit;  // initialize captures
    // inner.seen = seen;
    // inner.call(w);  // initial call

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{func.name});
    self.indent();

    // Static capture variables (prefixed with __c_ to avoid shadowing)
    for (captured_vars) |var_name| {
        try self.emitIndent();
        // Use @TypeOf to get the correct type from the outer variable
        const outer_var_name = blk: {
            if (self.var_renames.get(var_name)) |renamed| {
                break :blk renamed;
            }
            break :blk var_name;
        };
        try self.output.writer(self.allocator).print("var __c_{s}: @TypeOf({s}) = undefined;\n", .{ var_name, outer_var_name });
    }

    // The recursive function
    // Use anytype for parameters to accept any type (int, bool, etc.)
    try self.emitIndent();
    try self.emit("pub fn call(");
    for (func.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        const is_used = var_tracking.isParamUsedInStmts(arg.name, func.body);
        if (is_used) {
            try self.output.writer(self.allocator).print("__p_{s}_{d}: anytype", .{ arg.name, saved_counter });
        } else {
            try self.emit("_: anytype");
        }
    }
    try self.emit(") void {\n");
    self.indent();

    // Generate body
    try self.pushScope();

    // Mark that we're inside a nested function body - this affects isDeclared()
    const saved_inside_nested = self.inside_nested_function;
    self.inside_nested_function = true;
    defer self.inside_nested_function = saved_inside_nested;

    // Save and restore func_local_uses
    const saved_func_local_uses = self.func_local_uses;
    self.func_local_uses = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.func_local_uses.deinit();
        self.func_local_uses = saved_func_local_uses;
    }
    try var_tracking.collectUsedNames(func.body, &self.func_local_uses);

    // Save and clear hoisted_vars - nested function has its own hoisting context
    const saved_hoisted_vars = self.hoisted_vars;
    self.hoisted_vars = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.hoisted_vars.deinit();
        self.hoisted_vars = saved_hoisted_vars;
    }

    // Save outer scope renames for captured variables (to restore later)
    var saved_outer_renames = std.ArrayList(?[]const u8){};
    defer saved_outer_renames.deinit(self.allocator);

    for (captured_vars) |var_name| {
        try saved_outer_renames.append(self.allocator, self.var_renames.get(var_name));
    }

    // Capture variable renames (use __c_ prefix to reference struct fields)
    var capture_renames = std.ArrayList([]const u8){};
    defer capture_renames.deinit(self.allocator);

    for (captured_vars) |var_name| {
        const rename = try std.fmt.allocPrint(self.allocator, "__c_{s}", .{var_name});
        try capture_renames.append(self.allocator, rename);
        try self.var_renames.put(var_name, rename);
    }

    // Save outer scope param renames (to restore later)
    var saved_param_renames = std.ArrayList(?[]const u8){};
    defer saved_param_renames.deinit(self.allocator);

    for (func.args) |arg| {
        try saved_param_renames.append(self.allocator, self.var_renames.get(arg.name));
    }

    // Param renames
    var param_renames = std.ArrayList([]const u8){};
    defer param_renames.deinit(self.allocator);

    // Track which parameters are reassigned and need var copies
    var reassigned_params = std.ArrayList([]const u8){};
    defer reassigned_params.deinit(self.allocator);

    for (func.args) |arg| {
        try self.declareVar(arg.name);
        const is_used = var_tracking.isParamUsedInStmts(arg.name, func.body);
        const is_reassigned = var_tracking.isParamReassignedInStmts(arg.name, func.body);

        if (is_used) {
            const rename = try std.fmt.allocPrint(self.allocator, "__p_{s}_{d}", .{ arg.name, saved_counter });
            try param_renames.append(self.allocator, rename);

            // If the parameter is reassigned, we need a var copy
            if (is_reassigned) {
                // Create a mutable variable name
                const var_name = try std.fmt.allocPrint(self.allocator, "__v_{s}_{d}", .{ arg.name, saved_counter });
                try reassigned_params.append(self.allocator, var_name);
                try self.var_renames.put(arg.name, var_name);
            } else {
                try self.var_renames.put(arg.name, rename);
            }
        }
    }

    // Emit var copies for reassigned parameters
    for (func.args) |arg| {
        if (var_tracking.isParamReassignedInStmts(arg.name, func.body)) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("var __v_{s}_{d} = __p_{s}_{d};\n", .{ arg.name, saved_counter, arg.name, saved_counter });
        }
    }

    // Rename the function name itself to just 'call' for recursive calls
    try self.var_renames.put(func.name, "call");

    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    // Free the reassigned param var names
    for (reassigned_params.items) |var_name| {
        self.allocator.free(var_name);
    }

    // Clean up renames
    _ = self.var_renames.swapRemove(func.name);

    for (func.args, 0..) |arg, i| {
        // Restore outer scope param rename if there was one
        if (saved_param_renames.items[i]) |outer_rename| {
            try self.var_renames.put(arg.name, outer_rename);
        } else {
            _ = self.var_renames.swapRemove(arg.name);
        }
        if (i < param_renames.items.len) {
            self.allocator.free(param_renames.items[i]);
        }
    }

    for (captured_vars, 0..) |var_name, i| {
        // Restore outer scope rename if there was one
        if (saved_outer_renames.items[i]) |outer_rename| {
            try self.var_renames.put(var_name, outer_rename);
        } else {
            _ = self.var_renames.swapRemove(var_name);
        }
        self.allocator.free(capture_renames.items[i]);
    }

    self.popScope();
    self.dedent();

    try self.emitIndent();
    try self.emit("}\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // Initialize the capture variables (use __c_ prefix)
    // Now var_renames has been restored so outer scope renames work
    for (captured_vars) |var_name| {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("{s}.__c_{s} = ", .{ func.name, var_name });
        if (self.var_renames.get(var_name)) |renamed| {
            try self.emit(renamed);
        } else {
            try self.emit(var_name);
        }
        try self.emit(";\n");
    }

    // Mark inner as a closure for .call() syntax
    const inner_name_copy = try self.allocator.dupe(u8, func.name);
    try self.closure_vars.put(inner_name_copy, {});
}
