/// Assignment and expression statement code generation
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const helpers = @import("assign_helpers.zig");
const comptimeHelpers = @import("assign_comptime.zig");
const deferCleanup = @import("assign_defer.zig");
const typeHandling = @import("assign/type_handling.zig");
const valueGen = @import("assign/value_generation.zig");

/// Generate annotated assignment statement (x: int = 5)
pub fn genAnnAssign(self: *NativeCodegen, ann_assign: ast.Node.AnnAssign) CodegenError!void {
    // If no value, just a declaration (x: int), skip for now
    if (ann_assign.value == null) return;

    // Convert to regular assignment and process
    const targets = try self.allocator.alloc(ast.Node, 1);
    targets[0] = ann_assign.target.*;

    const assign = ast.Node.Assign{
        .targets = targets,
        .value = ann_assign.value.?,
    };
    try genAssign(self, assign);

    // Free the temporary targets allocation
    self.allocator.free(targets);
}

/// Generate assignment statement with automatic defer cleanup
pub fn genAssign(self: *NativeCodegen, assign: ast.Node.Assign) CodegenError!void {
    const value_type = try self.type_inferrer.inferExpr(assign.value.*);

    // Handle tuple unpacking: a, b = (1, 2)
    if (assign.targets.len == 1 and assign.targets[0] == .tuple) {
        const target_tuple = assign.targets[0].tuple;
        try valueGen.genTupleUnpack(self, assign, target_tuple);
        return;
    }

    for (assign.targets) |target| {
        if (target == .name) {
            const var_name = target.name.id;

            // Check collection types and allocation behavior
            const is_constant_array = typeHandling.isConstantArray(self, assign, var_name);
            const is_arraylist = typeHandling.isArrayList(self, assign, var_name);
            const is_listcomp = (assign.value.* == .listcomp);
            const is_dict = (assign.value.* == .dict);
            _ = assign.value.* == .dictcomp; // is_dictcomp - reserved for future use
            const is_allocated_string = typeHandling.isAllocatedString(self, assign.value.*);
            const is_mutable_class_instance = typeHandling.isMutableClassInstance(self, assign.value.*);

            // Check if this is first assignment or reassignment
            // Hoisted variables should skip declaration (already declared before try block)
            // Global variables should also skip declaration (they're declared in outer scope)
            const is_hoisted = self.hoisted_vars.contains(var_name);
            const is_global = self.isGlobalVar(var_name);
            const is_first_assignment = !self.isDeclared(var_name) and !is_hoisted and !is_global;

            // Try compile-time evaluation FIRST
            if (self.comptime_evaluator.tryEval(assign.value.*)) |comptime_val| {
                // Only apply for simple types (no strings/lists that allocate during evaluation)
                // TODO: Strings and lists need proper arena allocation to avoid memory leaks
                const is_simple_type = switch (comptime_val) {
                    .int, .float, .bool => true,
                    .string, .list => false,
                };

                if (is_simple_type) {
                    // Check mutability BEFORE emitting
                    // Use isVarMutated() to check both module-level AND function-local mutations
                    const is_mutable = if (is_first_assignment)
                        self.isVarMutated(var_name)
                    else
                        false; // Reassignments don't declare

                    // Successfully evaluated at compile time!
                    try comptimeHelpers.emitComptimeAssignment(self, var_name, comptime_val, is_first_assignment, is_mutable);
                    if (is_first_assignment) {
                        try self.declareVar(var_name);
                    }
                    return;
                }
                // Fall through to runtime codegen for strings/lists
                // Don't free - these are either AST-owned or will leak (TODO: arena)
            }

            try self.emitIndent();
            if (is_first_assignment) {
                // First assignment: emit var/const declaration with type annotation
                try valueGen.emitVarDeclaration(
                    self,
                    var_name,
                    value_type,
                    is_arraylist,
                    is_dict,
                    is_mutable_class_instance,
                );

                // Mark as declared
                try self.declareVar(var_name);

                // Track array slice vars
                const is_array_slice = typeHandling.isArraySlice(self, assign.value.*);
                if (is_array_slice) {
                    const var_name_copy = try self.allocator.dupe(u8, var_name);
                    try self.array_slice_vars.put(var_name_copy, {});
                }
            } else {
                // Reassignment: x = value (no var/const keyword!)
                // Use renamed version if in var_renames map (for exception handling)
                const actual_name = self.var_renames.get(var_name) orelse var_name;
                try self.output.appendSlice(self.allocator, actual_name);
                try self.output.appendSlice(self.allocator, " = ");
                // No type annotation on reassignment
            }

            // Special handling for string concatenation with nested operations
            // s1 + " " + s2 needs intermediate temps
            if (assign.value.* == .binop and assign.value.binop.op == .Add) {
                const left_type = try self.type_inferrer.inferExpr(assign.value.binop.left.*);
                const right_type = try self.type_inferrer.inferExpr(assign.value.binop.right.*);
                if (left_type == .string or right_type == .string) {
                    try valueGen.genStringConcat(self, assign, var_name, is_first_assignment);
                    return;
                }
            }

            // Special handling for list literals that will be mutated
            // Generate ArrayList initialization directly instead of fixed array
            if (is_arraylist and assign.value.* == .list) {
                const list = assign.value.list;
                try valueGen.genArrayListInit(self, var_name, list);

                // Add defer cleanup
                try deferCleanup.emitDeferCleanups(
                    self,
                    var_name,
                    is_first_assignment,
                    is_arraylist,
                    is_listcomp,
                    is_dict,
                    is_allocated_string,
                    assign.value.*,
                );
                return;
            }

            // Emit value
            try self.genExpr(assign.value.*);

            try self.output.appendSlice(self.allocator, ";\n");

            // Track variable metadata (ArrayList vars, closures, etc.)
            try valueGen.trackVariableMetadata(
                self,
                var_name,
                is_first_assignment,
                is_constant_array,
                typeHandling.isArraySlice(self, assign.value.*),
                assign,
            );

            // Add defer cleanup based on assignment type
            try deferCleanup.emitDeferCleanups(
                self,
                var_name,
                is_first_assignment,
                is_arraylist,
                is_listcomp,
                is_dict,
                is_allocated_string,
                assign.value.*,
            );
        } else if (target == .attribute) {
            // Handle attribute assignment (self.x = value or obj.y = value)
            const attr = target.attribute;

            // Check if this is a dynamic attribute
            const is_dynamic = try isDynamicAttrAssign(self, attr);

            try self.emitIndent();
            if (is_dynamic) {
                // Dynamic attribute: use __dict__.put() with type wrapping
                const dyn_value_type = try self.type_inferrer.inferExpr(assign.value.*);
                const py_value_tag = switch (dyn_value_type) {
                    .int => "int",
                    .float => "float",
                    .bool => "bool",
                    .string => "string",
                    else => "int", // Default fallback
                };

                try self.output.appendSlice(self.allocator, "try ");
                try self.genExpr(attr.value.*);
                try self.output.writer(self.allocator).print(".__dict__.put(\"{s}\", runtime.PyValue{{ .{s} = ", .{ attr.attr, py_value_tag });
                try self.genExpr(assign.value.*);
                try self.output.appendSlice(self.allocator, " })");
            } else {
                // Known attribute: direct assignment
                try self.genExpr(target);
                try self.output.appendSlice(self.allocator, " = ");
                try self.genExpr(assign.value.*);
            }
            try self.output.appendSlice(self.allocator, ";\n");
        }
    }
}

/// Generate augmented assignment (+=, -=, *=, /=, //=, **=, %=)
pub fn genAugAssign(self: *NativeCodegen, aug: ast.Node.AugAssign) CodegenError!void {
    try self.emitIndent();

    // Emit target (variable name)
    try self.genExpr(aug.target.*);
    try self.output.appendSlice(self.allocator, " = ");

    // Special handling for floor division and power
    if (aug.op == .FloorDiv) {
        try self.output.appendSlice(self.allocator, "@divFloor(");
        try self.genExpr(aug.target.*);
        try self.output.appendSlice(self.allocator, ", ");
        try self.genExpr(aug.value.*);
        try self.output.appendSlice(self.allocator, ");\n");
        return;
    }

    if (aug.op == .Pow) {
        try self.output.appendSlice(self.allocator, "std.math.pow(i64, ");
        try self.genExpr(aug.target.*);
        try self.output.appendSlice(self.allocator, ", ");
        try self.genExpr(aug.value.*);
        try self.output.appendSlice(self.allocator, ");\n");
        return;
    }

    if (aug.op == .Mod) {
        try self.output.appendSlice(self.allocator, "@rem(");
        try self.genExpr(aug.target.*);
        try self.output.appendSlice(self.allocator, ", ");
        try self.genExpr(aug.value.*);
        try self.output.appendSlice(self.allocator, ");\n");
        return;
    }

    // Regular operators: +=, -=, *=, /=
    try self.genExpr(aug.target.*);

    const op_str = switch (aug.op) {
        .Add => " + ",
        .Sub => " - ",
        .Mult => " * ",
        .Div => " / ",
        else => " ? ",
    };
    try self.output.appendSlice(self.allocator, op_str);

    try self.genExpr(aug.value.*);
    try self.output.appendSlice(self.allocator, ";\n");
}

/// Generate expression statement (expression with semicolon)
pub fn genExprStmt(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    try self.emitIndent();

    // Special handling for print()
    if (expr == .call and expr.call.func.* == .name) {
        const func_name = expr.call.func.name.id;
        if (std.mem.eql(u8, func_name, "print")) {
            const genPrint = @import("misc.zig").genPrint;
            try genPrint(self, expr.call.args);
            return;
        }
    }

    // Discard string constants (docstrings) by assigning to _
    // Zig requires all non-void values to be used
    if (expr == .constant and expr.constant.value == .string) {
        try self.output.appendSlice(self.allocator, "_ = ");
    }

    // Discard return values from function calls (Zig requires all non-void values to be used)
    if (expr == .call and expr.call.func.* == .name) {
        const func_name = expr.call.func.name.id;
        // Check if function returns non-void type
        if (self.type_inferrer.func_return_types.get(func_name)) |return_type| {
            // Skip void returns
            if (return_type != .unknown) {
                try self.output.appendSlice(self.allocator, "_ = ");
            }
        }
    }

    const before_len = self.output.items.len;
    try self.genExpr(expr);

    // Check if generated code ends with '}' (block statement)
    // Blocks in statement position don't need semicolons
    const generated = self.output.items[before_len..];
    const ends_with_block = generated.len > 0 and generated[generated.len - 1] == '}';

    if (ends_with_block) {
        try self.output.appendSlice(self.allocator, "\n");
    } else {
        try self.output.appendSlice(self.allocator, ";\n");
    }
}

/// Check if attribute assignment is to a dynamic attribute
fn isDynamicAttrAssign(self: *NativeCodegen, attr: ast.Node.Attribute) !bool {
    // Only check for class instance attributes (self.attr or obj.attr)
    if (attr.value.* != .name) return false;

    const obj_name = attr.value.name.id;

    // Get object type
    const obj_type = try self.type_inferrer.inferExpr(attr.value.*);

    // Check if it's a class instance
    if (obj_type != .class_instance) return false;

    const class_name = obj_type.class_instance;

    // Check if class has this field
    const class_info = self.type_inferrer.class_fields.get(class_name);
    if (class_info) |info| {
        // Check if field exists in class
        if (info.fields.get(attr.attr)) |_| {
            return false; // Known field
        }
    }

    // Check for special module attributes
    if (std.mem.eql(u8, obj_name, "sys")) {
        return false;
    }

    // Unknown field - dynamic attribute
    return true;
}

// Comptime assignment functions moved to assign_comptime.zig
