/// Recursive closure generation using Y-combinator style pattern
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../../main.zig").NativeCodegen;
const CodegenError = @import("../../../main.zig").CodegenError;
const hashmap_helper = @import("utils.hashmap_helper");
const var_tracking = @import("var_tracking.zig");

/// Generate a recursive closure using Y-combinator style pattern
/// For recursive closures, we use a struct with a function that receives itself via @This()
pub fn genRecursiveClosure(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
    captured_vars: [][]const u8,
) CodegenError!void {
    const saved_id = self.name_gen.nextId();

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

    const b = try self.getBuilder();
    try b.writeIndent();
    try b.writeFmt("const {s} = struct {{\n", .{func.name});
    const output1 = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output1);
    self.indent();

    // Static capture variables (prefixed with __c_ to avoid shadowing)
    for (captured_vars) |var_name| {
        const b2 = try self.getBuilder();
        try b2.writeIndent();
        // Use @TypeOf to get the correct type from the outer variable
        const outer_var_name = blk: {
            if (self.var_renames.get(var_name)) |renamed| {
                break :blk renamed;
            }
            break :blk var_name;
        };
        try b2.writeFmt("var __c_{s}: @TypeOf({s}) = undefined;\n", .{ var_name, outer_var_name });
        const output2 = b2.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output2);
    }

    // The recursive function
    // Use anytype for parameters to accept any type (int, bool, etc.)
    const b3 = try self.getBuilder();
    try b3.writeIndent();
    try b3.write("pub fn call(");
    for (func.args, 0..) |arg, i| {
        if (i > 0) try b3.write(", ");
        const is_used = var_tracking.isParamUsedInStmts(arg.name, func.body);
        if (is_used) {
            try b3.writeFmt("__p_{s}_{d}: anytype", .{ arg.name, saved_id });
        } else {
            try b3.write("_: anytype");
        }
    }
    try b3.write(") void {\n");
    const output3 = b3.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output3);
    self.indent();

    // Generate body
    try self.pushScope();

    // Mark that we're inside a nested function body - this affects isDeclared()
    const saved_inside_nested = self.inside_nested_function;
    self.inside_nested_function = true;
    defer self.inside_nested_function = saved_inside_nested;

    // Track the base scope level for this nested function
    const saved_nested_base_scope = self.nested_function_base_scope;
    self.nested_function_base_scope = self.symbol_table.currentScopeLevel();
    defer self.nested_function_base_scope = saved_nested_base_scope;

    // Save and reset control_flow_terminated - nested function has its own control flow
    const saved_control_flow_terminated = self.control_flow_terminated;
    self.control_flow_terminated = false;
    defer self.control_flow_terminated = saved_control_flow_terminated;

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

    // Save and clear mutation tracking for this nested function body
    const saved_func_local_mutations = self.func_local_mutations;
    const saved_func_local_aug_assigns = self.func_local_aug_assigns;
    self.func_local_mutations = hashmap_helper.StringHashMap(void).init(self.allocator);
    self.func_local_aug_assigns = hashmap_helper.StringHashMap(void).init(self.allocator);
    defer {
        self.func_local_mutations.deinit();
        self.func_local_aug_assigns.deinit();
        self.func_local_mutations = saved_func_local_mutations;
        self.func_local_aug_assigns = saved_func_local_aug_assigns;
    }

    // Analyze nested function body for local mutations (determines var vs const)
    const mutation_analysis = @import("../generators/body/mutation_analysis.zig");
    try mutation_analysis.analyzeFunctionLocalMutations(self, func);

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
            const rename = try std.fmt.allocPrint(self.allocator, "__p_{s}_{d}", .{ arg.name, saved_id });
            try param_renames.append(self.allocator, rename);

            // If the parameter is reassigned, we need a var copy
            if (is_reassigned) {
                // Create a mutable variable name
                const var_name = try std.fmt.allocPrint(self.allocator, "__v_{s}_{d}", .{ arg.name, saved_id });
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
            const b4 = try self.getBuilder();
            try b4.writeIndent();
            try b4.writeFmt("var __v_{s}_{d} = __p_{s}_{d};\n", .{ arg.name, saved_id, arg.name, saved_id });
            const output4 = b4.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output4);
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

    const b5 = try self.getBuilder();
    try b5.writeIndent();
    try b5.write("}\n");
    const output5 = b5.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output5);

    self.dedent();
    const b6 = try self.getBuilder();
    try b6.writeIndent();
    try b6.write("};\n");
    const output6 = b6.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output6);

    // Initialize the capture variables (use __c_ prefix)
    // Now var_renames has been restored so outer scope renames work
    for (captured_vars) |var_name| {
        const b7 = try self.getBuilder();
        try b7.writeIndent();
        try b7.writeFmt("{s}.__c_{s} = ", .{ func.name, var_name });
        if (self.var_renames.get(var_name)) |renamed| {
            try b7.write(renamed);
        } else {
            try b7.write(var_name);
        }
        try b7.write(";\n");
        const output7 = b7.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output7);
    }

    // Mark inner as a closure for .call() syntax
    const inner_name_copy = try self.arena.allocator().dupe(u8, func.name);
    try self.closure_vars.put(inner_name_copy, {});
}
