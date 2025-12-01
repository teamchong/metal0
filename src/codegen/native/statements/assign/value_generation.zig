/// Value generation and emission logic for assignments
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const helpers = @import("../assign_helpers.zig");
const deferCleanup = @import("../assign_defer.zig");
const zig_keywords = @import("zig_keywords");

/// Generate tuple unpacking assignment: a, b = (1, 2)
pub fn genTupleUnpack(self: *NativeCodegen, assign: ast.Node.Assign, target_tuple: ast.Node.Tuple) CodegenError!void {
    const core = @import("../../main/core.zig");

    // Generate unique temporary variable name
    const tmp_name = try std.fmt.allocPrint(self.allocator, "__unpack_tmp_{d}", .{self.unpack_counter});
    defer self.allocator.free(tmp_name);
    self.unpack_counter += 1;

    // Infer the type of the source tuple to track element types
    const source_type = try self.type_inferrer.inferExpr(assign.value.*);

    // Check if source is a list/array type (uses [N] indexing) vs tuple (uses .@"N")
    const source_tag = @as(std.meta.Tag(@TypeOf(source_type)), source_type);
    const is_list_type = source_tag == .list or source_tag == .array;

    // Generate: const __unpack_tmp_N = value_expr;
    try self.emitIndent();
    try self.emit("const ");
    try self.emit(tmp_name);
    try self.emit(" = ");
    try self.genExpr(assign.value.*);
    try self.emit(";\n");

    // Generate: const a = __unpack_tmp_N.@"0";  (for tuples)
    // or:       const a = __unpack_tmp_N[0];    (for lists/arrays)
    for (target_tuple.elts, 0..) |target, i| {
        if (target == .name) {
            const var_name = target.name.id;

            // Handle Python's discard pattern: `_, x = (1, 2)` or `a, _ = (1, 2)`
            // In Zig, use `_ = value;` to explicitly discard the value
            if (std.mem.eql(u8, var_name, "_")) {
                try self.emitIndent();
                if (is_list_type) {
                    try self.output.writer(self.allocator).print("_ = {s}.items[{d}];\n", .{ tmp_name, i });
                } else {
                    try self.output.writer(self.allocator).print("_ = {s}.@\"{d}\";\n", .{ tmp_name, i });
                }
                continue;
            }

            const is_first_assignment = !self.isDeclared(var_name);

            // Register the type for this unpacked variable
            // Extract element type from source tuple if available
            if (source_tag == .tuple) {
                if (i < source_type.tuple.len) {
                    try self.type_inferrer.var_types.put(var_name, source_type.tuple[i]);
                }
            } else if (source_tag == .list) {
                try self.type_inferrer.var_types.put(var_name, source_type.list.*);
            } else if (source_tag == .array) {
                try self.type_inferrer.var_types.put(var_name, source_type.array.element_type.*);
            }

            try self.emitIndent();
            if (is_first_assignment) {
                try self.emit("const ");
                try self.declareVar(var_name);
            }
            // Use renamed version if in var_renames map (for exception handling)
            const actual_name = self.var_renames.get(var_name) orelse var_name;
            // Use writeLocalVarName to handle keywords AND method shadowing
            try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), actual_name);
            if (is_list_type) {
                // Use .items[i] for ArrayLists: __unpack_tmp_N.items[i]
                try self.output.writer(self.allocator).print(" = {s}.items[{d}];\n", .{ tmp_name, i });
            } else {
                // Use tuple field access: __unpack_tmp_N.@"i"
                try self.output.writer(self.allocator).print(" = {s}.@\"{d}\";\n", .{ tmp_name, i });
            }
        }
    }

    // Check if this is a call to a test factory function (script mode)
    // If so, register the unpacked variable names as test classes
    if (assign.value.* == .call) {
        const call_node = assign.value.call;
        if (call_node.func.* == .name) {
            const func_name = call_node.func.name.id;
            if (self.test_factories.get(func_name)) |factory_info| {
                // Register each target with its corresponding class info
                for (target_tuple.elts, 0..) |target, j| {
                    if (target == .name and j < factory_info.returned_classes.len) {
                        const var_name = target.name.id;
                        const orig_class_info = factory_info.returned_classes[j];

                        // Create a new TestClassInfo with the module-level variable name
                        try self.unittest_classes.append(self.allocator, core.TestClassInfo{
                            .class_name = var_name,
                            .test_methods = orig_class_info.test_methods,
                            .has_setUp = orig_class_info.has_setUp,
                            .has_tearDown = orig_class_info.has_tearDown,
                            .has_setup_class = orig_class_info.has_setup_class,
                            .has_teardown_class = orig_class_info.has_teardown_class,
                        });
                    }
                }
            }
        }
    }
}

/// Generate list unpacking assignment: [a, b] = [1, 2] or a, b = x (when parsed as list)
pub fn genListUnpack(self: *NativeCodegen, assign: ast.Node.Assign, target_list: ast.Node.List) CodegenError!void {
    const core = @import("../../main/core.zig");

    // Generate unique temporary variable name
    const tmp_name = try std.fmt.allocPrint(self.allocator, "__unpack_tmp_{d}", .{self.unpack_counter});
    defer self.allocator.free(tmp_name);
    self.unpack_counter += 1;

    // Infer the type of the source to determine indexing style
    const source_type = try self.type_inferrer.inferExpr(assign.value.*);
    const source_tag = @as(std.meta.Tag(@TypeOf(source_type)), source_type);
    const is_list_type = source_tag == .list or source_tag == .array;

    // Generate: const __unpack_tmp_N = value_expr;
    try self.emitIndent();
    try self.emit("const ");
    try self.emit(tmp_name);
    try self.emit(" = ");
    try self.genExpr(assign.value.*);
    try self.emit(";\n");

    // Generate: const a = __unpack_tmp_N.@"0";  (for tuples)
    // or:       const a = __unpack_tmp_N[0];    (for lists/arrays)
    for (target_list.elts, 0..) |target, i| {
        if (target == .name) {
            const var_name = target.name.id;

            // Handle Python's discard pattern: `_, x = [1, 2]` or `[a, _] = [1, 2]`
            // In Zig, use `_ = value;` to explicitly discard the value
            if (std.mem.eql(u8, var_name, "_")) {
                try self.emitIndent();
                if (is_list_type) {
                    try self.output.writer(self.allocator).print("_ = {s}.items[{d}];\n", .{ tmp_name, i });
                } else {
                    try self.output.writer(self.allocator).print("_ = {s}.@\"{d}\";\n", .{ tmp_name, i });
                }
                continue;
            }

            const is_first_assignment = !self.isDeclared(var_name);

            // Register element type for unpacked variable
            if (source_tag == .tuple) {
                if (i < source_type.tuple.len) {
                    try self.type_inferrer.var_types.put(var_name, source_type.tuple[i]);
                }
            } else if (source_tag == .list) {
                try self.type_inferrer.var_types.put(var_name, source_type.list.*);
            } else if (source_tag == .array) {
                try self.type_inferrer.var_types.put(var_name, source_type.array.element_type.*);
            }

            try self.emitIndent();
            if (is_first_assignment) {
                try self.emit("const ");
                try self.declareVar(var_name);
            }
            // Use renamed version if in var_renames map (for exception handling)
            const actual_name = self.var_renames.get(var_name) orelse var_name;
            // Use writeLocalVarName to handle keywords AND method shadowing
            try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), actual_name);
            if (is_list_type) {
                // Use .items[i] for ArrayLists: __unpack_tmp_N.items[i]
                try self.output.writer(self.allocator).print(" = {s}.items[{d}];\n", .{ tmp_name, i });
            } else {
                // Use tuple field access: __unpack_tmp_N.@"i"
                try self.output.writer(self.allocator).print(" = {s}.@\"{d}\";\n", .{ tmp_name, i });
            }
        }
    }

    // Check if this is a call to a test factory function (script mode)
    // If so, register the unpacked variable names as test classes
    if (assign.value.* == .call) {
        const call_node = assign.value.call;
        if (call_node.func.* == .name) {
            const func_name = call_node.func.name.id;
            if (self.test_factories.get(func_name)) |factory_info| {
                // Register each target with its corresponding class info
                for (target_list.elts, 0..) |target, j| {
                    if (target == .name and j < factory_info.returned_classes.len) {
                        const var_name = target.name.id;
                        const orig_class_info = factory_info.returned_classes[j];

                        // Create a new TestClassInfo with the module-level variable name
                        try self.unittest_classes.append(self.allocator, core.TestClassInfo{
                            .class_name = var_name,
                            .test_methods = orig_class_info.test_methods,
                            .has_setUp = orig_class_info.has_setUp,
                            .has_tearDown = orig_class_info.has_tearDown,
                            .has_setup_class = orig_class_info.has_setup_class,
                            .has_teardown_class = orig_class_info.has_teardown_class,
                        });
                    }
                }
            }
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
    is_listcomp: bool,
    is_iterator: bool,
) CodegenError!void {
    // Check if variable was forward-declared (captured by nested class before defined)
    // If so, just emit the variable name for assignment, not a new declaration
    if (self.forward_declared_vars.contains(var_name)) {
        // Remove from forward_declared_vars so we don't suppress future shadowing declarations
        _ = self.forward_declared_vars.fetchSwapRemove(var_name);
        // Just emit variable name for assignment
        const actual_name = self.var_renames.get(var_name) orelse var_name;
        try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), actual_name);
        try self.emit(" = ");
        return;
    }

    // Check if variable is mutated (reassigned later)
    // This checks both module-level analysis AND function-local mutations
    const is_mutated = self.isVarMutated(var_name);

    // Check if value type is deque, counter, or hash_object (all are mutable collections)
    // hash_object needs var because update() mutates it
    const is_mutable_collection = (value_type == .deque or value_type == .counter or value_type == .hash_object);

    // List comprehensions return ArrayLists which need var for deinit()
    // Iterators need var because next() mutates them
    // Note: hash_object types can use const unless explicitly mutated (is_mutated check)
    // Note: We do NOT check hasAttrMutation here because the mutation analyzer is module-scoped,
    // not function-scoped. Different variables named 'o' in different functions would collide.
    // Instead, setattr/delattr codegen uses the object directly (not copying it).
    //
    // Special case for class instances: If the class doesn't have mutating methods AND the variable
    // isn't reassigned (e.g., via aug_assign), we can use const. But if the variable is reassigned
    // (e.g., x += 10 where __add__ returns new object), we need var.
    // Note: is_mutated tracks actual reassignment, not just attribute mutation.
    const is_immutable_class_instance = (value_type == .class_instance) and !is_mutable_class_instance and !is_mutated;
    const effective_is_mutated = if (is_immutable_class_instance) false else is_mutated;
    const needs_var = is_arraylist or is_dict or is_mutable_class_instance or effective_is_mutated or is_listcomp or is_mutable_collection or is_iterator;

    if (needs_var) {
        try self.emit("var ");
    } else {
        try self.emit("const ");
    }

    // Use renamed version if in var_renames map (for exception handling)
    const actual_name = self.var_renames.get(var_name) orelse var_name;

    // Use writeLocalVarName to handle keywords AND method shadowing
    try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), actual_name);

    // Only emit type annotation for known types that aren't dicts, dictcomps, lists, tuples, closures, counters, ArrayLists, or class instances
    // For lists/ArrayLists/dicts/dictcomps/tuples/closures/counters, let Zig infer the type from the initializer
    // For unknown types (json.loads, etc.), let Zig infer
    // For class instances, let Zig infer to avoid cross-method type pollution issues
    // For integers, let Zig infer to handle i64/i128 from int() calls (sys.maxsize + 1 needs i128)
    // EXCEPTION: bigint requires explicit type annotation because initial value (small int) won't match
    const is_int = (value_type == .int);
    const is_bigint = (value_type == .bigint);
    const is_list = (value_type == .list);
    const is_tuple = (value_type == .tuple);
    const is_closure = (value_type == .closure);
    const is_function = (value_type == .function); // Lambdas/closures - don't use *const fn type annotation
    const is_dict_type = (value_type == .dict);
    const is_counter = (value_type == .counter);
    const is_deque = (value_type == .deque);
    const is_class_instance = (value_type == .class_instance);
    const is_dictcomp = false; // Passed separately

    // BigInt needs explicit type annotation to declare variable as BigInt even if first value is a small int
    if (is_bigint) {
        try self.emit(": runtime.BigInt = ");
        return;
    }

    // For functions (lambdas), never emit *const fn type annotation - closures can't be coerced to function pointers
    if (value_type != .unknown and !is_dict and !is_dictcomp and !is_dict_type and !is_arraylist and !is_list and !is_tuple and !is_closure and !is_function and !is_counter and !is_deque and !is_class_instance and !is_int) {
        try self.emit(": ");
        try value_type.toZigType(self.allocator, &self.output);
    }

    try self.emit(" = ");
}

/// Generate ArrayList initialization from list literal
pub fn genArrayListInit(self: *NativeCodegen, var_name: []const u8, list: ast.Node.List) CodegenError!void {
    const native_types = @import("../../../../analysis/native_types.zig");
    const NativeType = native_types.NativeType;

    // Check if variable was declared BEFORE this current assignment (e.g., global variable with type annotation)
    // Note: isDeclared returns true even if we just declared in the same statement, so we need
    // to check isGlobalVar which indicates pre-existing type annotation
    const has_predeclared_type = self.isGlobalVar(var_name);

    // Infer element type with widening across ALL elements
    var elem_type: NativeType = if (list.elts.len > 0)
        try self.type_inferrer.inferExpr(list.elts[0])
    else blk: {
        // For empty lists, check if type inference has a better type for this variable
        // (e.g., based on later append calls with strings)
        const var_type = self.type_inferrer.getScopedVar(var_name) orelse
            self.type_inferrer.var_types.get(var_name);
        if (var_type) |vt| {
            // Extract element type from list type
            if (vt == .list) {
                // Get the element type from the list
                break :blk vt.list.*;
            }
        }
        break :blk .{ .int = .bounded }; // Default to int for empty lists
    };

    // Widen type to accommodate all elements
    if (list.elts.len > 1) {
        for (list.elts[1..]) |elem| {
            const this_type = try self.type_inferrer.inferExpr(elem);
            elem_type = elem_type.widen(this_type);
        }
    }

    if (has_predeclared_type) {
        // Variable already has a type - use .{} to inherit the declared type instead of creating a new struct type
        try self.emit(".{};\n");
    } else {
        try self.emit("std.ArrayList(");
        // Generate element type, converting PyObject to []const u8 for string lists
        var type_buf = std.ArrayList(u8){};
        defer type_buf.deinit(self.allocator);
        try elem_type.toZigType(self.allocator, &type_buf);
        const type_str = if (std.mem.eql(u8, type_buf.items, "*runtime.PyObject"))
            "[]const u8"
        else
            type_buf.items;
        try self.emit(type_str);
        try self.emit("){};\n");
    }

    // Check if this is a list of callables (needs wrapping)
    const is_callable_list = @as(std.meta.Tag(NativeType), elem_type) == .callable;

    // Append elements
    for (list.elts) |elem| {
        try self.emitIndent();
        try self.emit("try ");
        const actual_name = self.var_renames.get(var_name) orelse var_name;
        try self.emit(actual_name);
        try self.emit(".append(__global_allocator, ");

        // For tuples in pre-declared ArrayLists (with struct element type),
        // generate named field syntax: .{ .@"0" = val1, .@"1" = val2 }
        if (has_predeclared_type and elem == .tuple) {
            try self.emit(".{ ");
            for (elem.tuple.elts, 0..) |tuple_elem, i| {
                if (i > 0) try self.emit(", ");
                try self.output.writer(self.allocator).print(".@\"{d}\" = ", .{i});
                try self.genExpr(tuple_elem);
            }
            try self.emit(" }");
        } else if (is_callable_list) {
            // Wrap non-PyCallable elements for callable lists
            const this_type = try self.type_inferrer.inferExpr(elem);
            try genCallableElement(self, elem, this_type);
        } else {
            try self.genExpr(elem);
        }
        try self.emit(");\n");
    }

    // Track this variable as ArrayList for len() generation
    const var_name_copy = try self.allocator.dupe(u8, var_name);
    try self.arraylist_vars.put(var_name_copy, {});
}

/// Generate an element for a list of callables (PyCallable)
/// Wraps lambdas, classes, and other callable elements in PyCallable.fromAny
fn genCallableElement(self: *NativeCodegen, elem: ast.Node, elem_type: anytype) CodegenError!void {
    const native_types = @import("../../../../analysis/native_types.zig");
    const NativeType = native_types.NativeType;

    const elem_tag = @as(std.meta.Tag(NativeType), elem_type);

    switch (elem_tag) {
        .callable => {
            // Already a PyCallable (bytes_factory, etc.) - emit directly
            try self.genExpr(elem);
        },
        .function => {
            // Lambda or function - wrap using fromAny for type erasure
            try self.emit("runtime.builtins.PyCallable.fromAny(@TypeOf(");
            try self.genExpr(elem);
            try self.emit("), ");
            try self.genExpr(elem);
            try self.emit(")");
        },
        .class_instance => {
            // Class used as constructor - wrap in PyCallable
            const class_name = elem_type.class_instance;
            try self.emit("runtime.builtins.PyCallable.fromAny(@TypeOf(");
            try self.emit(class_name);
            try self.emit(".init), ");
            try self.emit(class_name);
            try self.emit(".init)");
        },
        else => {
            // Unknown callable type - try to wrap it generically
            // Check if it's a name node for a class
            if (elem == .name) {
                const name = elem.name.id;
                // Check if it's a known class in class_fields
                if (self.type_inferrer.class_fields.contains(name)) {
                    try self.emit("runtime.builtins.PyCallable.fromAny(@TypeOf(");
                    try self.emit(name);
                    try self.emit(".init), ");
                    try self.emit(name);
                    try self.emit(".init)");
                    return;
                }
            }
            // Fallback - wrap using fromAny for type erasure
            try self.emit("runtime.builtins.PyCallable.fromAny(@TypeOf(");
            try self.genExpr(elem);
            try self.emit("), ");
            try self.genExpr(elem);
            try self.emit(")");
        },
    }
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
        try self.dict_vars.put(var_name_copy, {});
    }

    // Track dict literal variables (generates HashMap)
    if (is_first_assignment and assign.value.* == .dict) {
        const var_name_copy = try self.allocator.dupe(u8, var_name);
        try self.dict_vars.put(var_name_copy, {});
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
            // Check if the lambda returns void (e.g., calls self.assertRaises)
            if (lambda_closure.lambdaReturnsVoid(assign.value.lambda)) {
                try lambda_closure.markAsVoidClosure(self, var_name);
            }
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

    // Track closure instances from method calls: adder = obj.get_adder()
    // where get_adder() returns a lambda that captures self
    if (assign.value.* == .call and assign.value.call.func.* == .attribute) {
        const attr = assign.value.call.func.attribute;
        // Check if obj is a class instance and method is registered as closure-returning
        // First, try to get the type of the object being called on
        if (attr.value.* == .name) {
            const obj_name = attr.value.name.id;
            const method_name = attr.attr;

            // Look up the object's type to find its class name
            if (self.getVarType(obj_name)) |obj_type| {
                if (obj_type == .class_instance) {
                    const class_name = obj_type.class_instance;
                    // Check if ClassName.method_name is registered as closure-returning
                    const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class_name, method_name });
                    defer self.allocator.free(key);

                    if (self.closure_returning_methods.contains(key)) {
                        // This method returns a closure, mark the variable
                        try lambda_closure.markAsClosure(self, var_name);
                    }
                }
            }
        }
    }
}
