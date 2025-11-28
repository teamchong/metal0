/// Value generation and emission logic for assignments
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const helpers = @import("../assign_helpers.zig");
const deferCleanup = @import("../assign_defer.zig");

/// Generate tuple unpacking assignment: a, b = (1, 2)
pub fn genTupleUnpack(self: *NativeCodegen, assign: ast.Node.Assign, target_tuple: ast.Node.Tuple) CodegenError!void {
    // Generate unique temporary variable name
    const tmp_name = try std.fmt.allocPrint(self.allocator, "__unpack_tmp_{d}", .{self.unpack_counter});
    defer self.allocator.free(tmp_name);
    self.unpack_counter += 1;

    // Generate: const __unpack_tmp_N = value_expr;
    try self.emitIndent();
    try self.emit("const ");
    try self.emit(tmp_name);
    try self.emit(" = ");
    try self.genExpr(assign.value.*);
    try self.emit(";\n");

    // Generate: const a = __unpack_tmp_N.@"0";
    //           const b = __unpack_tmp_N.@"1";
    for (target_tuple.elts, 0..) |target, i| {
        if (target == .name) {
            const var_name = target.name.id;
            const is_first_assignment = !self.isDeclared(var_name);

            try self.emitIndent();
            if (is_first_assignment) {
                try self.emit("const ");
                try self.declareVar(var_name);
            }
            // Use renamed version if in var_renames map (for exception handling)
            const actual_name = self.var_renames.get(var_name) orelse var_name;
            try self.emit(actual_name);
            try self.output.writer(self.allocator).print(" = {s}.@\"{d}\";\n", .{ tmp_name, i });
        }
    }
}

/// Emit variable declaration with const/var decision
pub fn emitVarDeclaration(
    self: *NativeCodegen,
    var_name: []const u8,
    value_type: anytype,
    is_arraylist: bool,
    is_dict: bool,
    is_mutable_class_instance: bool,
) CodegenError!void {
    // Check if variable is mutated (reassigned later)
    // This checks both module-level analysis AND function-local mutations
    const is_mutated = self.isVarMutated(var_name);

    // hash_object types need var because they have mutating methods like update()
    const is_hash_object = (value_type == .hash_object);

    const needs_var = is_arraylist or is_dict or is_mutable_class_instance or is_mutated or is_hash_object;

    if (needs_var) {
        try self.emit("var ");
    } else {
        try self.emit("const ");
    }

    // Use renamed version if in var_renames map (for exception handling)
    const actual_name = self.var_renames.get(var_name) orelse var_name;

    try self.emit(actual_name);

    // Only emit type annotation for known types that aren't dicts, dictcomps, lists, tuples, closures, or ArrayLists
    // For lists/ArrayLists/dicts/dictcomps/tuples/closures, let Zig infer the type from the initializer
    // For unknown types (json.loads, etc.), let Zig infer
    const is_list = (value_type == .list);
    const is_tuple = (value_type == .tuple);
    const is_closure = (value_type == .closure);
    const is_dict_type = (value_type == .dict);
    const is_dictcomp = false; // Passed separately
    if (value_type != .unknown and !is_dict and !is_dictcomp and !is_dict_type and !is_arraylist and !is_list and !is_tuple and !is_closure) {
        try self.emit(": ");
        try value_type.toZigType(self.allocator, &self.output);
    }

    try self.emit(" = ");
}

/// Generate ArrayList initialization from list literal
pub fn genArrayListInit(self: *NativeCodegen, var_name: []const u8, list: ast.Node.List) CodegenError!void {
    // Determine element type
    const elem_type = if (list.elts.len > 0)
        try self.type_inferrer.inferExpr(list.elts[0])
    else
        .int; // Default to int for empty lists

    try self.emit("std.ArrayList(");
    try elem_type.toZigType(self.allocator, &self.output);
    try self.emit("){};\n");

    // Append elements
    for (list.elts) |elem| {
        try self.emitIndent();
        try self.emit("try ");
        const actual_name = self.var_renames.get(var_name) orelse var_name;
        try self.emit(actual_name);
        try self.emit(".append(allocator, ");
        try self.genExpr(elem);
        try self.emit(");\n");
    }

    // Track this variable as ArrayList for len() generation
    const var_name_copy = try self.allocator.dupe(u8, var_name);
    try self.arraylist_vars.put(var_name_copy, {});
}

/// Generate string concatenation with multiple parts
pub fn genStringConcat(self: *NativeCodegen, assign: ast.Node.Assign, var_name: []const u8, is_first_assignment: bool) CodegenError!void {
    // Collect all parts of the concatenation
    var parts = std.ArrayList(ast.Node){};
    defer parts.deinit(self.allocator);

    try helpers.flattenConcat(self, assign.value.*, &parts);

    // Get allocator name based on scope
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    // Generate concat with all parts at once
    try self.emit("try std.mem.concat(");
    try self.emit(alloc_name);
    try self.emit(", u8, &[_][]const u8{ ");
    for (parts.items, 0..) |part, i| {
        if (i > 0) try self.emit(", ");
        try self.genExpr(part);
    }
    try self.emit(" });\n");

    // Add defer cleanup
    try deferCleanup.emitStringConcatDefer(self, var_name, is_first_assignment);
}

/// Track variable metadata after assignment
pub fn trackVariableMetadata(
    self: *NativeCodegen,
    var_name: []const u8,
    is_first_assignment: bool,
    is_constant_array: bool,
    is_array_slice: bool,
    assign: ast.Node.Assign,
) CodegenError!void {
    // Track local variable type for current function/method scope
    // This helps avoid type shadowing issues when the same variable name is used in different methods
    const value_type = self.type_inferrer.inferExpr(assign.value.*) catch .unknown;
    try self.setLocalVarType(var_name, value_type);

    // Track if this variable holds a constant array
    if (is_constant_array) {
        const var_name_copy = try self.allocator.dupe(u8, var_name);
        try self.array_vars.put(var_name_copy, {});
    }

    // Track if this variable holds an array slice (subscript of constant array)
    if (is_array_slice) {
        const var_name_copy = try self.allocator.dupe(u8, var_name);
        try self.array_slice_vars.put(var_name_copy, {});
    }

    // Track ArrayList variables (dict.values(), dict.keys(), str.split() return ArrayList)
    if (is_first_assignment and assign.value.* == .call) {
        const call = assign.value.call;
        if (call.func.* == .attribute) {
            const attr = call.func.attribute;
            if (std.mem.eql(u8, attr.attr, "values") or
                std.mem.eql(u8, attr.attr, "keys") or
                std.mem.eql(u8, attr.attr, "split"))
            {
                // dict.values(), dict.keys(), str.split() return ArrayList
                const var_name_copy = try self.allocator.dupe(u8, var_name);
                try self.arraylist_vars.put(var_name_copy, {});
            }
        }
    }

    // Track list comprehension variables (generates ArrayList)
    if (is_first_assignment and assign.value.* == .listcomp) {
        const var_name_copy = try self.allocator.dupe(u8, var_name);
        try self.arraylist_vars.put(var_name_copy, {});
    }

    // Track dict comprehension variables (generates HashMap)
    if (is_first_assignment and assign.value.* == .dictcomp) {
        const var_name_copy = try self.allocator.dupe(u8, var_name);
        try self.arraylist_vars.put(var_name_copy, {});
    }

    const lambda_closure = @import("../../expressions/lambda_closure.zig");
    const lambda_mod = @import("../../expressions/lambda.zig");

    // Track closure factories: make_adder = lambda x: lambda y: x + y
    if (assign.value.* == .lambda and assign.value.lambda.body.* == .lambda) {
        try lambda_closure.markAsClosureFactory(self, var_name);
    }

    // Track simple closures: x = 10; f = lambda y: y + x (captures outer variable)
    if (assign.value.* == .lambda) {
        // Check if this lambda captures outer variables
        if (lambda_mod.lambdaCapturesVars(self, assign.value.lambda)) {
            // This lambda generated a closure struct, mark it
            try lambda_closure.markAsClosure(self, var_name);
        } else {
            // Simple lambda (no captures) - track as function pointer
            const key = try self.allocator.dupe(u8, var_name);
            try self.lambda_vars.put(key, {});

            // Register lambda return type for type inference
            const return_type = try lambda_mod.getLambdaReturnType(self, assign.value.lambda);
            try self.type_inferrer.func_return_types.put(var_name, return_type);
        }
    }

    // Track closure instances: add_five = make_adder(5)
    if (assign.value.* == .call and assign.value.call.func.* == .name) {
        const called_func = assign.value.call.func.name.id;
        if (self.closure_factories.contains(called_func)) {
            // This is calling a closure factory, so the result is a closure
            try lambda_closure.markAsClosure(self, var_name);
        }
    }
}
