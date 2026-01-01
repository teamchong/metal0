/// Value generation and emission logic for assignments
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const helpers = @import("../assign_helpers.zig");
const deferCleanup = @import("../assign_defer.zig");
const zig_keywords = @import("utils.zig_keywords");

// Trait imports for type checking
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const string_traits = @import("../../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../../analysis/traits/container_traits.zig");

// Import widenTupleTypes for proper nested tuple widening in lists
const collections = @import("../../expressions/collections.zig");
const widenTupleTypes = collections.widenTupleTypes;

/// PyValue method names for binary operations (must match arithmetic.zig)
const PyValueMethods = std.StaticStringMap(void).initComptime(.{
    .{ "Add", {} },
    .{ "Sub", {} },
    .{ "Mult", {} },
    .{ "Div", {} },
    .{ "FloorDiv", {} },
    .{ "Mod", {} },
    .{ "BitAnd", {} },
    .{ "BitOr", {} },
    .{ "BitXor", {} },
    .{ "LShift", {} },
    .{ "RShift", {} },
    .{ "Pow", {} },
});

/// Check if a binop expression will produce PyValue output
/// (i.e., uses genPyValueBinOp because operands are uncertain)
pub fn binopProducesPyValue(self: *NativeCodegen, expr: ast.Node) bool {
    if (expr != .binop) return false;
    const binop = expr.binop;

    // Check if operator has PyValue method
    if (PyValueMethods.get(@tagName(binop.op)) == null) return false;

    // Check if either operand is uncertain
    const arithmetic = @import("../../expressions/operators/arithmetic.zig");
    const left_uncertain = arithmetic.isOperandUncertain(self, binop.left.*);
    const right_uncertain = arithmetic.isOperandUncertain(self, binop.right.*);

    return left_uncertain or right_uncertain;
}

/// Generate tuple unpacking assignment: a, b = (1, 2)
pub fn genTupleUnpack(self: *NativeCodegen, assign: ast.Node.Assign, target_tuple: ast.Node.Tuple) CodegenError!void {
    const core = @import("../../main/core.zig");

    // Generate unique temporary variable name
    const tmp_name = try self.freshName("unpack_tmp");

    // Infer the type of the source tuple to track element types
    const source_type = try self.type_inferrer.inferExpr(assign.value.*);

    // Check if source is a list/array type (uses [N] indexing) vs tuple (uses .@"N")
    const source_tag = @as(std.meta.Tag(@TypeOf(source_type)), source_type);
    const is_list_type = source_tag == .list or type_traits.isArray(source_type);

    // Check if source needs VM fallback (returns PyValue)
    // VM fallback results are PyValue, so we need .listItems()[i] for access
    const is_pyvalue_type = self.needsVMFallback(assign.value.*) or source_tag == .pyvalue;

    // Generate: const __unpack_tmp_N = value_expr;
    // Don't add 'try' here - let genExpr handle error propagation internally
    // Blocks that construct tuples/lists from error union results handle 'try' inside the block
    // Adding 'try' here would double-wrap and cause "expected error union" errors
    try self.emitIndent();
    try self.emit("const ");
    try self.emit(tmp_name);
    try self.emit(" = ");
    try self.genExpr(assign.value.*);
    try self.emit(";\n");

    // Generate: const a = __unpack_tmp_N.@"0";  (for tuples)
    // or:       const a = __unpack_tmp_N[0];    (for lists/arrays)
    // Use comptime type dispatch to handle PyValue from generators
    for (target_tuple.elts, 0..) |target, i| {
        if (target == .name) {
            const var_name = target.name.id;

            // Handle Python's discard pattern: `_, x = (1, 2)` or `a, _ = (1, 2)`
            // Also handle unused variables to avoid Zig's "unused local constant" error
            // In Zig, use `_ = value;` to explicitly discard the value
            const is_unused = std.mem.eql(u8, var_name, "_") or self.isVarUnused(var_name);
            if (is_unused) {
                try self.emitIndent();
                if (is_pyvalue_type) {
                    // PyValue from VM fallback - use .listItems()[i]
                    try self.output.writer(self.allocator).print("_ = {s}.listItems()[{d}];\n", .{ tmp_name, i });
                } else if (is_list_type) {
                    try self.output.writer(self.allocator).print("_ = {s}.items[{d}];\n", .{ tmp_name, i });
                } else {
                    // Use runtime helper to avoid comptime explosion in loops
                    try self.output.writer(self.allocator).print("_ = runtime.tuple_ops.getField({s}, {d});\n", .{ tmp_name, i });
                }
                continue;
            }

            const is_first_assignment = !self.isDeclared(var_name);

            // Register the type for this unpacked variable
            // Extract element type from source tuple if available
            // Use putScopedVar to update both scoped and global maps (for aug_assign detection)
            //
            // IMPORTANT: When unpacking from PyValue (VM fallback), the elements are also PyValue.
            // We must register them as .pyvalue and track in pyvalue_vars so downstream usage
            // generates proper type conversions (e.g., .asString() for string functions).
            if (is_pyvalue_type) {
                // VM fallback result - elements are PyValue, not the inferred type
                try self.type_inferrer.putScopedVar(var_name, .pyvalue);
                try self.pyvalue_vars.put(var_name, {});
            } else if (container_traits.isTuple(source_type)) {
                if (i < source_type.tuple.len) {
                    try self.type_inferrer.putScopedVar(var_name, source_type.tuple[i]);
                }
            } else if (container_traits.isList(source_type)) {
                try self.type_inferrer.putScopedVar(var_name, source_type.list.*);
            } else if (source_tag == .array) {
                try self.type_inferrer.putScopedVar(var_name, source_type.array.element_type.*);
            }

            // Check if var_name would shadow module-level declarations (imports, funcs, vars, 'main')
            // getSafeLocalName handles all shadow cases and adds to var_renames if needed
            _ = try self.getSafeLocalName(var_name);

            // Use renamed version for declarations (filters out lazy attribute patterns)
            const actual_name = self.getVarDeclName(var_name);

            // Check if renamed name is a pointer dereference (ends with ".*")
            // If so, this is a pointer assignment inside a try block helper - no const/var prefix needed
            const is_pointer_deref = std.mem.endsWith(u8, actual_name, ".*");

            // Check if the renamed name contains a dot (capture struct access like __cap_foo.bar)
            // If so, sanitize for declaration (replace dots with underscores)
            const decl_name = blk: {
                if (!is_pointer_deref and std.mem.indexOfScalar(u8, actual_name, '.') != null) {
                    // Contains dot - sanitize for declaration
                    var buf = try self.allocator.alloc(u8, actual_name.len);
                    for (actual_name, 0..) |c, idx| {
                        buf[idx] = if (c == '.') '_' else c;
                    }
                    break :blk buf;
                } else {
                    break :blk actual_name;
                }
            };

            try self.emitIndent();
            if (is_first_assignment and !is_pointer_deref) {
                try self.emit("const ");
                try self.declareVar(var_name);
            }
            // Use writeLocalVarName to handle keywords AND method shadowing
            if (is_pointer_deref) {
                try self.emit(actual_name);
            } else {
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), decl_name);
            }
            if (is_pyvalue_type) {
                // PyValue from VM fallback - use .listItems()[i]
                try self.output.writer(self.allocator).print(" = {s}.listItems()[{d}];\n", .{ tmp_name, i });
            } else if (is_list_type) {
                // Use .items[i] for ArrayLists: __unpack_tmp_N.items[i]
                try self.output.writer(self.allocator).print(" = {s}.items[{d}];\n", .{ tmp_name, i });
            } else {
                // Use comptime type dispatch for PyValue from generators
                try self.output.writer(self.allocator).print(" = runtime.tuple_ops.getField({s}, {d});\n", .{ tmp_name, i });
            }

            // Emit immediate discard for tuple unpacking variables
            // This is more reliable than relying on pending_discards occurrence counting,
            // especially when variables are referenced in runtime.eval() string literals
            if (is_first_assignment and !is_pointer_deref) {
                try self.emitIndent();
                try self.emit("_ = &");
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), decl_name);
                try self.emit(";\n");
            }
        } else if (target == .subscript) {
            // Handle subscript targets: a[0], a[-1] = big, small
            // Generate proper subscript assignment using .items[] syntax or __setitem__
            const subscript = target.subscript;
            try self.emitIndent();

            // Generate the container (e.g., "a" in "a[0]")
            try self.genExpr(subscript.value.*);

            // Generate the index part - use .items[] for array access
            if (subscript.slice == .index) {
                try self.emit(".items[@as(usize, @intCast(");
                try self.genExpr(subscript.slice.index.*);
                try self.emit("))]");
            } else {
                // Slice assignment - use slice syntax
                try self.emit("[");
                if (subscript.slice.slice.lower) |lower| {
                    try self.genExpr(lower.*);
                }
                try self.emit("..");
                if (subscript.slice.slice.upper) |upper| {
                    try self.genExpr(upper.*);
                }
                try self.emit("]");
            }

            // Generate the value assignment
            if (is_pyvalue_type) {
                // PyValue from VM fallback - use .listItems()[i]
                try self.output.writer(self.allocator).print(" = {s}.listItems()[{d}];\n", .{ tmp_name, i });
            } else if (is_list_type) {
                try self.output.writer(self.allocator).print(" = {s}.items[{d}];\n", .{ tmp_name, i });
            } else {
                // Use comptime type dispatch for PyValue from generators
                try self.output.writer(self.allocator).print(" = runtime.tuple_ops.getField({s}, {d});\n", .{ tmp_name, i });
            }
        } else if (target == .attribute) {
            // Handle attribute targets: self.x, self.y = 1, 2, 3
            const attr = target.attribute;

            // Check if this is a dynamic attribute (needs __dict__.put())
            const is_dynamic = blk: {
                if (attr.value.* != .name) break :blk false;
                const obj_type = self.inferExprScoped(attr.value.*) catch break :blk false;
                if (!type_traits.isClassInstance(obj_type)) break :blk false;
                const class_name = obj_type.class_instance;
                // Check if class has this as a known field
                if (self.type_inferrer.class_fields.get(class_name)) |info| {
                    if (info.fields.get(attr.attr)) |_| {
                        break :blk false; // Known field - static
                    }
                }
                break :blk true; // Unknown field - dynamic
            };

            try self.emitIndent();
            if (is_dynamic) {
                // Dynamic attribute: use __dict__.put()
                // Generate the base object (e.g., 'a' for a.x, 'self' for self.x)
                if (self.inside_defer) {
                    try self.emit("@constCast(&");
                    try self.genExpr(attr.value.*);
                    try self.output.writer(self.allocator).print(".__dict__).put(\"{s}\", runtime.PyValue.from({s}", .{ attr.attr, tmp_name });
                    if (is_pyvalue_type) {
                        try self.output.writer(self.allocator).print(".listItems()[{d}]", .{i});
                    } else if (is_list_type) {
                        try self.output.writer(self.allocator).print(".items[{d}]", .{i});
                    } else {
                        try self.output.writer(self.allocator).print(".@\"{d}\"", .{i});
                    }
                    try self.emit(")) catch unreachable;\n");
                } else {
                    try self.emit("try @constCast(&");
                    try self.genExpr(attr.value.*);
                    try self.output.writer(self.allocator).print(".__dict__).put(\"{s}\", runtime.PyValue.from({s}", .{ attr.attr, tmp_name });
                    if (is_pyvalue_type) {
                        try self.output.writer(self.allocator).print(".listItems()[{d}]", .{i});
                    } else if (is_list_type) {
                        try self.output.writer(self.allocator).print(".items[{d}]", .{i});
                    } else {
                        try self.output.writer(self.allocator).print(".@\"{d}\"", .{i});
                    }
                    try self.emit("));\n");
                }
            } else {
                // Static attribute: direct field assignment
                try self.genExpr(target);
                if (is_pyvalue_type) {
                    try self.output.writer(self.allocator).print(" = {s}.listItems()[{d}];\n", .{ tmp_name, i });
                } else if (is_list_type) {
                    try self.output.writer(self.allocator).print(" = {s}.items[{d}];\n", .{ tmp_name, i });
                } else {
                    try self.output.writer(self.allocator).print(" = {s}.@\"{d}\";\n", .{ tmp_name, i });
                }
            }
        } else if (target == .tuple) {
            // Handle nested tuple unpacking: (x, y), (z, t) = sorted(v.items(), ...)
            // First extract the i-th element into a temp, then unpack that
            const nested_tmp = try self.freshName("nested_unpack");

            // Generate: const __nested_unpack_N = __unpack_tmp_M[i];
            try self.emitIndent();
            try self.emit("const ");
            try self.emit(nested_tmp);
            if (is_pyvalue_type) {
                try self.output.writer(self.allocator).print(" = {s}.listItems()[{d}];\n", .{ tmp_name, i });
            } else if (is_list_type) {
                try self.output.writer(self.allocator).print(" = {s}.items[{d}];\n", .{ tmp_name, i });
            } else {
                try self.output.writer(self.allocator).print(" = runtime.tuple_ops.getField({s}, {d});\n", .{ tmp_name, i });
            }

            // Now unpack nested tuple elements
            for (target.tuple.elts, 0..) |nested_target, j| {
                if (nested_target == .name) {
                    const var_name = nested_target.name.id;
                    const is_unused = std.mem.eql(u8, var_name, "_") or self.isVarUnused(var_name);
                    if (is_unused) {
                        try self.emitIndent();
                        try self.output.writer(self.allocator).print("_ = {s}.@\"{d}\";\n", .{ nested_tmp, j });
                        continue;
                    }

                    const is_first_assignment = !self.isDeclared(var_name);
                    try self.emitIndent();
                    if (is_first_assignment) {
                        try self.emit("const ");
                        try self.declareVar(var_name);
                    }
                    try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), var_name);
                    // Nested elements are typically tuples themselves, use .@"N" indexing
                    try self.output.writer(self.allocator).print(" = {s}.@\"{d}\";\n", .{ nested_tmp, j });

                    if (is_first_assignment) {
                        try self.pending_discards.put(try self.arena.allocator().dupe(u8, var_name), try self.arena.allocator().dupe(u8, var_name));
                    }
                }
            }
        } else if (target == .list) {
            // Handle nested list unpacking: [x, y], [z, t] = ...
            const nested_tmp = try self.freshName("nested_unpack");

            try self.emitIndent();
            try self.emit("const ");
            try self.emit(nested_tmp);
            if (is_pyvalue_type) {
                try self.output.writer(self.allocator).print(" = {s}.listItems()[{d}];\n", .{ tmp_name, i });
            } else if (is_list_type) {
                try self.output.writer(self.allocator).print(" = {s}.items[{d}];\n", .{ tmp_name, i });
            } else {
                try self.output.writer(self.allocator).print(" = runtime.tuple_ops.getField({s}, {d});\n", .{ tmp_name, i });
            }

            for (target.list.elts, 0..) |nested_target, j| {
                if (nested_target == .name) {
                    const var_name = nested_target.name.id;
                    const is_unused = std.mem.eql(u8, var_name, "_") or self.isVarUnused(var_name);
                    if (is_unused) {
                        try self.emitIndent();
                        try self.output.writer(self.allocator).print("_ = {s}.@\"{d}\";\n", .{ nested_tmp, j });
                        continue;
                    }

                    const is_first_assignment = !self.isDeclared(var_name);
                    try self.emitIndent();
                    if (is_first_assignment) {
                        try self.emit("const ");
                        try self.declareVar(var_name);
                    }
                    try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), var_name);
                    try self.output.writer(self.allocator).print(" = {s}.@\"{d}\";\n", .{ nested_tmp, j });

                    if (is_first_assignment) {
                        try self.pending_discards.put(try self.arena.allocator().dupe(u8, var_name), try self.arena.allocator().dupe(u8, var_name));
                    }
                }
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

                        // Create a new TestClassInfo with the renamed module-level variable name
                        // Use getVarDeclName to get the potentially renamed version (e.g., __m75_TestClass)
                        // Mark as factory-returned since it comes from tuple unpacking of factory call
                        // Preserve original_class_name and factory_name so lifecycle.zig can use the actual struct
                        try self.unittest_classes.append(self.allocator, core.TestClassInfo{
                            .class_name = self.getVarDeclName(var_name),
                            .test_methods = orig_class_info.test_methods,
                            .has_setUp = orig_class_info.has_setUp,
                            .has_tearDown = orig_class_info.has_tearDown,
                            .has_setup_class = orig_class_info.has_setup_class,
                            .has_teardown_class = orig_class_info.has_teardown_class,
                            .is_factory_returned = true,
                            .original_class_name = orig_class_info.class_name,
                            .factory_name = func_name,
                        });
                    }
                }
            }
        }
    }

    // When source uses VM fallback, unpacked variables are only referenced in VM fallback strings
    // (as Python variable names), not as Zig code. Emit discards to prevent "unused local constant" errors.
    if (self.needsVMFallback(assign.value.*)) {
        for (target_tuple.elts) |target| {
            if (target == .name) {
                const var_name = target.name.id;
                // Skip discard pattern
                if (std.mem.eql(u8, var_name, "_")) continue;
                // Skip variables that were not declared (unused in tuple unpacking)
                // These were discarded earlier and never declared, so we can't reference them
                if (self.isVarUnused(var_name)) continue;
                // Skip variables that have renames (e.g., inside TryHelper where variables
                // are captured as pointer parameters like p_order1_1.*)
                if (self.var_renames.contains(var_name)) continue;
                try self.emitIndent();
                try self.emit("_ = &");
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), var_name);
                try self.emit(";\n");
            }
        }
    }
}

/// Generate list unpacking assignment: [a, b] = [1, 2] or a, b = x (when parsed as list)
pub fn genListUnpack(self: *NativeCodegen, assign: ast.Node.Assign, target_list: ast.Node.List) CodegenError!void {
    const core = @import("../../main/core.zig");

    // Generate unique temporary variable name
    const tmp_name = try self.freshName("unpack_tmp");

    // Infer the type of the source to determine indexing style
    const source_type = try self.type_inferrer.inferExpr(assign.value.*);
    const source_tag = @as(std.meta.Tag(@TypeOf(source_type)), source_type);
    const is_list_type = source_tag == .list or type_traits.isArray(source_type);

    // Check if source needs VM fallback (returns PyValue)
    // VM fallback results are PyValue, so we need .listItems()[i] for access
    const is_pyvalue_type = self.needsVMFallback(assign.value.*) or source_tag == .pyvalue;

    // Generate: const __unpack_tmp_N = value_expr;
    // Add 'try' only if value is a function call that returns an error union
    // (blocks that construct lists from error union results are NOT error unions themselves)
    try self.emitIndent();
    try self.emit("const ");
    try self.emit(tmp_name);
    try self.emit(" = ");
    const is_call = assign.value.* == .call;
    // Only add 'try' if it's a call AND the return type is NOT a plain tuple/list
    // Tuples/lists returned from blocks don't need 'try' even if constructed from error union results
    // The error handling happens inside the block, not at the unpacking site
    const returns_tuple_or_list = source_tag == .tuple or source_tag == .list;
    const needs_try = is_call and !returns_tuple_or_list;
    if (needs_try) {
        try self.emit("try ");
    }
    try self.genExpr(assign.value.*);
    try self.emit(";\n");

    // Generate: const a = __unpack_tmp_N.@"0";  (for tuples)
    // or:       const a = __unpack_tmp_N[0];    (for lists/arrays)
    // Use comptime type dispatch to handle PyValue from generators
    for (target_list.elts, 0..) |target, i| {
        if (target == .name) {
            const var_name = target.name.id;

            // Handle Python's discard pattern: `_, x = [1, 2]` or `[a, _] = [1, 2]`
            // Also handle unused variables to avoid Zig's "unused local constant" error
            // In Zig, use `_ = value;` to explicitly discard the value
            const is_unused = std.mem.eql(u8, var_name, "_") or self.isVarUnused(var_name);
            if (is_unused) {
                try self.emitIndent();
                if (is_pyvalue_type) {
                    // PyValue from VM fallback - use .listItems()[i]
                    try self.output.writer(self.allocator).print("_ = {s}.listItems()[{d}];\n", .{ tmp_name, i });
                } else if (is_list_type) {
                    try self.output.writer(self.allocator).print("_ = {s}.items[{d}];\n", .{ tmp_name, i });
                } else {
                    // Use runtime helper to avoid comptime explosion in loops
                    try self.output.writer(self.allocator).print("_ = runtime.tuple_ops.getField({s}, {d});\n", .{ tmp_name, i });
                }
                continue;
            }

            const is_first_assignment = !self.isDeclared(var_name);

            // Register element type for unpacked variable
            // Use putScopedVar to update both scoped and global maps (for aug_assign detection)
            if (container_traits.isTuple(source_type)) {
                if (i < source_type.tuple.len) {
                    try self.type_inferrer.putScopedVar(var_name, source_type.tuple[i]);
                }
            } else if (container_traits.isList(source_type)) {
                try self.type_inferrer.putScopedVar(var_name, source_type.list.*);
            } else if (type_traits.isArray(source_type)) {
                try self.type_inferrer.putScopedVar(var_name, source_type.array.element_type.*);
            }

            // Check if var_name would shadow module-level declarations (imports, funcs, vars, 'main')
            // getSafeLocalName handles all shadow cases and adds to var_renames if needed
            _ = try self.getSafeLocalName(var_name);

            // Use renamed version for declarations (filters out lazy attribute patterns)
            const actual_name = self.getVarDeclName(var_name);

            // Check if renamed name is a pointer dereference (ends with ".*")
            // If so, this is a pointer assignment inside a try block helper - no const/var prefix needed
            const is_pointer_deref = std.mem.endsWith(u8, actual_name, ".*");

            // Check if the renamed name contains a dot (capture struct access like __cap_foo.bar)
            // If so, sanitize for declaration (replace dots with underscores)
            const decl_name2 = blk: {
                if (!is_pointer_deref and std.mem.indexOfScalar(u8, actual_name, '.') != null) {
                    // Contains dot - sanitize for declaration
                    var buf = try self.allocator.alloc(u8, actual_name.len);
                    for (actual_name, 0..) |c, idx| {
                        buf[idx] = if (c == '.') '_' else c;
                    }
                    break :blk buf;
                } else {
                    break :blk actual_name;
                }
            };

            try self.emitIndent();
            if (is_first_assignment and !is_pointer_deref) {
                try self.emit("const ");
                try self.declareVar(var_name);
            }
            // Use writeLocalVarName to handle keywords AND method shadowing
            if (is_pointer_deref) {
                try self.emit(actual_name);
            } else {
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), decl_name2);
            }
            if (is_pyvalue_type) {
                // PyValue from VM fallback - use .listItems()[i]
                try self.output.writer(self.allocator).print(" = {s}.listItems()[{d}];\n", .{ tmp_name, i });
            } else if (is_list_type) {
                // Use .items[i] for ArrayLists: __unpack_tmp_N.items[i]
                try self.output.writer(self.allocator).print(" = {s}.items[{d}];\n", .{ tmp_name, i });
            } else {
                // Use comptime type dispatch for PyValue from generators
                try self.output.writer(self.allocator).print(" = runtime.tuple_ops.getField({s}, {d});\n", .{ tmp_name, i });
            }

            // Emit immediate discard for list unpacking variables
            // This is more reliable than relying on pending_discards occurrence counting
            if (is_first_assignment and !is_pointer_deref) {
                try self.emitIndent();
                try self.emit("_ = &");
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), decl_name2);
                try self.emit(";\n");
            }
        } else if (target == .subscript) {
            // Handle subscript targets: a[0], a[-1] = big, small
            // Generate proper subscript assignment using .items[] syntax
            const subscript = target.subscript;
            try self.emitIndent();

            // Generate the container (e.g., "a" in "a[0]")
            try self.genExpr(subscript.value.*);

            // Generate the index part - use .items[] for array access
            if (subscript.slice == .index) {
                try self.emit(".items[@as(usize, @intCast(");
                try self.genExpr(subscript.slice.index.*);
                try self.emit("))]");
            } else {
                // Slice assignment - use slice syntax
                try self.emit("[");
                if (subscript.slice.slice.lower) |lower| {
                    try self.genExpr(lower.*);
                }
                try self.emit("..");
                if (subscript.slice.slice.upper) |upper| {
                    try self.genExpr(upper.*);
                }
                try self.emit("]");
            }

            // Generate the value assignment
            if (is_pyvalue_type) {
                // PyValue from VM fallback - use .listItems()[i]
                try self.output.writer(self.allocator).print(" = {s}.listItems()[{d}];\n", .{ tmp_name, i });
            } else if (is_list_type) {
                try self.output.writer(self.allocator).print(" = {s}.items[{d}];\n", .{ tmp_name, i });
            } else {
                // Use comptime type dispatch for PyValue from generators
                try self.output.writer(self.allocator).print(" = runtime.tuple_ops.getField({s}, {d});\n", .{ tmp_name, i });
            }
        } else if (target == .attribute) {
            // Handle attribute targets: self.x, self.y = 1, 2, 3
            const attr = target.attribute;

            // Check if this is a dynamic attribute (needs __dict__.put())
            const is_dynamic = blk: {
                if (attr.value.* != .name) break :blk false;
                const obj_type = self.inferExprScoped(attr.value.*) catch break :blk false;
                if (!type_traits.isClassInstance(obj_type)) break :blk false;
                const class_name = obj_type.class_instance;
                // Check if class has this as a known field
                if (self.type_inferrer.class_fields.get(class_name)) |info| {
                    if (info.fields.get(attr.attr)) |_| {
                        break :blk false; // Known field - static
                    }
                }
                break :blk true; // Unknown field - dynamic
            };

            try self.emitIndent();
            if (is_dynamic) {
                // Dynamic attribute: use __dict__.put()
                // Generate the base object (e.g., 'a' for a.x, 'self' for self.x)
                if (self.inside_defer) {
                    try self.emit("@constCast(&");
                    try self.genExpr(attr.value.*);
                    try self.output.writer(self.allocator).print(".__dict__).put(\"{s}\", runtime.PyValue.from({s}", .{ attr.attr, tmp_name });
                    if (is_pyvalue_type) {
                        try self.output.writer(self.allocator).print(".listItems()[{d}]", .{i});
                    } else if (is_list_type) {
                        try self.output.writer(self.allocator).print(".items[{d}]", .{i});
                    } else {
                        try self.output.writer(self.allocator).print(".@\"{d}\"", .{i});
                    }
                    try self.emit(")) catch unreachable;\n");
                } else {
                    try self.emit("try @constCast(&");
                    try self.genExpr(attr.value.*);
                    try self.output.writer(self.allocator).print(".__dict__).put(\"{s}\", runtime.PyValue.from({s}", .{ attr.attr, tmp_name });
                    if (is_pyvalue_type) {
                        try self.output.writer(self.allocator).print(".listItems()[{d}]", .{i});
                    } else if (is_list_type) {
                        try self.output.writer(self.allocator).print(".items[{d}]", .{i});
                    } else {
                        try self.output.writer(self.allocator).print(".@\"{d}\"", .{i});
                    }
                    try self.emit("));\n");
                }
            } else {
                // Static attribute: direct field assignment
                try self.genExpr(target);
                if (is_pyvalue_type) {
                    try self.output.writer(self.allocator).print(" = {s}.listItems()[{d}];\n", .{ tmp_name, i });
                } else if (is_list_type) {
                    try self.output.writer(self.allocator).print(" = {s}.items[{d}];\n", .{ tmp_name, i });
                } else {
                    try self.output.writer(self.allocator).print(" = {s}.@\"{d}\";\n", .{ tmp_name, i });
                }
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

                        // Create a new TestClassInfo with the renamed module-level variable name
                        // Use getVarDeclName to get the potentially renamed version (e.g., __m75_TestClass)
                        // Mark as factory-returned since it comes from list unpacking of factory call
                        // Preserve original_class_name and factory_name so lifecycle.zig can use the actual struct
                        try self.unittest_classes.append(self.allocator, core.TestClassInfo{
                            .class_name = self.getVarDeclName(var_name),
                            .test_methods = orig_class_info.test_methods,
                            .has_setUp = orig_class_info.has_setUp,
                            .has_tearDown = orig_class_info.has_tearDown,
                            .has_setup_class = orig_class_info.has_setup_class,
                            .has_teardown_class = orig_class_info.has_teardown_class,
                            .is_factory_returned = true,
                            .original_class_name = orig_class_info.class_name,
                            .factory_name = func_name,
                        });
                    }
                }
            }
        }
    }

    // When source uses VM fallback, unpacked variables are only referenced in VM fallback strings
    // (as Python variable names), not as Zig code. Emit discards to prevent "unused local constant" errors.
    if (self.needsVMFallback(assign.value.*)) {
        for (target_list.elts) |target| {
            if (target == .name) {
                const var_name = target.name.id;
                // Skip discard pattern
                if (std.mem.eql(u8, var_name, "_")) continue;
                // Skip variables that were not declared (unused in list unpacking)
                // These were discarded earlier and never declared, so we can't reference them
                if (self.isVarUnused(var_name)) continue;
                try self.emitIndent();
                try self.emit("_ = &");
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), var_name);
                try self.emit(";\n");
            }
        }
    }
}

/// Emit variable declaration with const/var decision
/// Returns true if PyValue.from() wrapper was opened and needs to be closed by caller
pub fn emitVarDeclaration(
    self: *NativeCodegen,
    var_name: []const u8,
    value_type: anytype,
    is_arraylist: bool,
    is_dict: bool,
    is_mutable_class_instance: bool,
    is_listcomp: bool,
    is_iterator: bool,
    value_expr: ?ast.Node,
) CodegenError!bool {
    // Note: Module-level constant assignments (__name__, __file__) are now handled in assign.zig
    // They're skipped before reaching this function

    // Check if variable was forward-declared (captured by nested class before defined)
    // If so, just emit the variable name for assignment, not a new declaration
    if (self.forward_declared_vars.contains(var_name)) {
        // Remove from forward_declared_vars so we don't suppress future shadowing declarations
        _ = self.forward_declared_vars.fetchSwapRemove(var_name);
        // Just emit variable name for assignment
        const actual_name = self.var_renames.get(var_name) orelse var_name;
        try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), actual_name);
        try self.emit(" = ");
        return false; // No wrapper opened
    }

    // Check if var_name would shadow a module-level import, function, global var, or 'main'
    // If so, use a prefixed name to avoid Zig's "shadows declaration" error
    const shadows_import = self.imported_modules.contains(var_name);
    const shadows_from_import = self.module_level_from_imports.contains(var_name);
    const shadows_module_func = self.module_level_funcs.contains(var_name);
    const shadows_global = self.isGlobalVar(var_name);
    const shadows_main = std.mem.eql(u8, var_name, "main");
    // Check if var_name would shadow a vararg or kwarg parameter (e.g., *args or **kwargs)
    // Python allows reassigning varargs: `if not args: args = (default,)`
    const shadows_vararg_param = self.vararg_params.contains(var_name) or self.kwarg_params.contains(var_name);
    // Also check if var_name would shadow a class-level attribute (becomes lazy method)
    // e.g., class has `MIN = fromHex(...)` → generates `pub fn MIN(...)` which local `MIN = self.MIN` would shadow
    const shadows_class_member = if (self.current_class_body) |class_body| blk: {
        for (class_body) |stmt| {
            if (stmt == .assign) {
                for (stmt.assign.targets) |target| {
                    if (target == .name and std.mem.eql(u8, target.name.id, var_name)) {
                        break :blk true;
                    }
                }
            }
        }
        break :blk false;
    } else false;

    // Check if we need to create a local rename for shadowing
    // BUT: if var_renames already has a lazy attr pattern "(try X(__alloc))", that's for READS, not declarations
    // In that case, we still need to create a local rename for the declaration
    const needs_local_rename = shadows_import or shadows_from_import or shadows_module_func or shadows_global or shadows_class_member or shadows_main or shadows_vararg_param;
    const existing_rename = self.var_renames.get(var_name);
    const has_lazy_pattern = if (existing_rename) |r| std.mem.startsWith(u8, r, "(try ") else false;
    if (needs_local_rename and (existing_rename == null or has_lazy_pattern)) {
        // Create a unique prefixed name using NameGen
        const prefixed_name = try self.name_gen.local(var_name);
        try self.var_renames.put(var_name, prefixed_name);
    }

    // Use renamed version if in var_renames map (for exception handling or shadowing)
    // BUT skip if the rename is a lazy class attribute call pattern "(try X(__alloc))"
    // Those are only for READS, not for declaring new local variables
    const actual_name = blk: {
        if (self.var_renames.get(var_name)) |renamed| {
            // Lazy attribute patterns start with "(try " - don't use for declarations
            if (std.mem.startsWith(u8, renamed, "(try ")) {
                break :blk var_name;
            }
            break :blk renamed;
        }
        break :blk var_name;
    };

    // Check if renamed name is a pointer dereference (ends with ".*")
    // If so, this is a pointer assignment inside a try block helper - no const/var prefix needed
    // Example: p_attr.* = ... (assigning through pointer, not declaring new variable)
    if (std.mem.endsWith(u8, actual_name, ".*")) {
        try self.emit(actual_name);
        try self.emit(" = ");
        return false; // No wrapper opened
    }

    // Check if variable is mutated (reassigned later)
    // This checks both module-level analysis AND function-local mutations
    const is_mutated = self.isVarMutated(var_name);

    // Check if value type is deque - deques need var because std.ArrayListUnmanaged methods (append, etc.)
    // take *Self, not self pointer. Unlike hashmaps which use *Self parameters and can be const.
    // NOTE: counter/hash_object/defaultdict use hashmaps which take *Self in method signatures,
    // so they can be const unless reassigned (like dicts). Only deque needs var for ArrayList API.
    const is_mutable_collection = (value_type == .deque);

    // Iterators need var because next() mutates them
    // Note: hash_object types can use const unless explicitly mutated (is_mutated check)
    // Note: We do NOT check hasAttrMutation here because the mutation analyzer is module-scoped,
    // not function-scoped. Different variables named 'o' in different functions would collide.
    // Instead, setattr/delattr codegen uses the object directly (not copying it).
    //
    // Class instances are stored as pointers (*Self from init()). The variable holding the pointer
    // only needs `var` if it's reassigned. Whether the object has self-mutating methods is irrelevant
    // because mutations go through the pointer, not by reassigning the variable.
    // Note: is_mutable_class_instance was previously used when closure calls added `&` for class args,
    // but now closures pass class instances directly (no &), so this flag is no longer needed.
    _ = is_mutable_class_instance; // No longer used for var/const decision
    // Dicts need `var` because defer cleanup calls .deinit() which takes *Self (mutable reference)
    // Python array module (array.array) returns inline struct with mutating methods - needs var
    // NOTE: List comprehensions (is_listcomp) don't automatically need `var` - the internal __comp_result_N
    // uses var, but the target variable like `instances = [...]` only needs var if mutated.
    // If is_mutated is false, use const to avoid "never mutated" warnings.
    const is_python_array = type_traits.isClassInstance(value_type) and
        std.mem.eql(u8, value_type.class_instance, "array.array");
    const needs_var = is_arraylist or is_mutated or is_mutable_collection or is_iterator or is_dict or is_python_array;
    _ = is_listcomp; // Listcomp target var mutability is determined by is_mutated, not by being a listcomp

    if (needs_var) {
        try self.emit("var ");
    } else {
        try self.emit("const ");
    }

    // Use writeLocalVarName to handle keywords AND method shadowing
    try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), actual_name);

    // Only emit type annotation for known types that aren't dicts, dictcomps, lists, tuples, closures, counters, ArrayLists, or class instances
    // For lists/ArrayLists/dicts/dictcomps/tuples/closures/counters, let Zig infer the type from the initializer
    // For unknown types (json.loads, etc.), let Zig infer
    // For class instances, let Zig infer to avoid cross-method type pollution issues
    // For integers, let Zig infer to handle i64/i128 from int() calls (sys.maxsize + 1 needs i128)
    // EXCEPTION: bigint requires explicit type annotation because initial value (small int) won't match
    const is_int = type_traits.isIntegral(value_type) and value_type != .bigint;
    const is_bigint = (value_type == .bigint);
    const is_list = container_traits.isList(value_type);
    const is_tuple = container_traits.isTuple(value_type);
    const is_closure = (value_type == .closure);
    const is_function = (value_type == .function); // Lambdas/closures - don't use *const fn type annotation
    const is_callable = type_traits.isCallable(value_type); // operator.mod, pow, etc. - each has different struct type
    const is_dict_type = container_traits.isDict(value_type);
    const is_counter = (value_type == .counter);
    const is_deque = (value_type == .deque);
    const is_class_instance = type_traits.isClassInstance(value_type);
    const is_dictcomp = false; // Passed separately

    // BigInt needs explicit type annotation to declare variable as BigInt even if first value is a small int
    if (is_bigint) {
        try self.emit(": runtime.BigInt = ");
        return false; // No wrapper opened
    }

    // TWO-FLOW TYPE SYSTEM: Check if variable has uncertain confidence
    // If uncertain, emit PyValue type instead of raw Zig type (safer, prevents runtime panics)
    // WHITELIST: Only wrap primitive types that PyValue supports (int, float, bool, string, none)
    // Also wrap unknown types to be safe
    //
    // IMPORTANT: If value_type is a KNOWN concrete type (string, int, float, bool, none),
    // we should NOT wrap in PyValue because the type is certain from the VALUE itself.
    // PyValue wrapping should only apply when:
    // 1. value_type is UNKNOWN (can't determine type at compile time), OR
    // 2. value_type is primitive AND the value SOURCE is uncertain (e.g., user function return)
    const is_primitive = type_traits.isIntegral(value_type) or type_traits.isFloating(value_type) or
        type_traits.isBoolean(value_type) or string_traits.isString(value_type) or
        type_traits.isNone(value_type);
    // Only wrap if value_type is unknown OR (primitive AND var is uncertain)
    // If value_type is a concrete primitive, we know the exact type from the value itself
    // EXCEPTION: If value expression already produces PyValue (e.g., binop with uncertain operands),
    // don't wrap again - the expression already returns PyValue type
    const expr_produces_pyvalue = if (value_expr) |expr| binopProducesPyValue(self, expr) else false;
    // EXCEPTION: String concatenation always produces []const u8, never needs PyValue wrapping
    // even if operand types are unknown (e.g., function parameters)
    const is_string_concat = if (value_expr) |expr| blk: {
        if (expr == .binop and expr.binop.op == .Add) {
            const left_type = self.type_inferrer.inferExpr(expr.binop.left.*) catch .unknown;
            const right_type = self.type_inferrer.inferExpr(expr.binop.right.*) catch .unknown;
            break :blk string_traits.isString(left_type) or string_traits.isString(right_type);
        }
        break :blk false;
    } else false;

    // EXCEPTION: Calls to anytype parameters with .init() return native struct types
    // that need to preserve their type for field access (e.g., staticmethod.__func__)
    // Don't wrap these in PyValue or field access will fail
    const is_anytype_init_call = if (value_expr) |expr| blk: {
        if (expr == .call and expr.call.func.* == .name) {
            const func_name = expr.call.func.name.id;
            break :blk self.anytype_params.contains(func_name);
        }
        break :blk false;
    } else false;

    // Check if containers (dict, list, tuple) also need wrapping when variable is uncertain
    const is_container = is_dict or is_dict_type or is_list or is_tuple;
    const needs_pyvalue_wrap = !expr_produces_pyvalue and !is_string_concat and !is_anytype_init_call and (type_traits.isUnknown(value_type) or
        (is_primitive and self.shouldUsePyValue(var_name) and !string_traits.isString(value_type)) or
        (is_container and self.shouldUsePyValue(var_name)));
    if (needs_pyvalue_wrap) {
        try self.emit(": runtime.PyValue = runtime.PyValue.from(");
        return true; // Wrapper opened - caller must close with ")"
    }
    // If expression produces PyValue, emit type annotation without wrapper
    if (expr_produces_pyvalue) {
        try self.emit(": runtime.PyValue = ");
        return false; // No wrapper opened
    }

    // VM fallback expressions return PyValue, so emit PyValue type annotation
    // This handles cases like `line = line.strip()` where the method call falls back to VM
    const needs_vm_fallback = if (value_expr) |expr| self.needsVMFallback(expr) else false;
    if (needs_vm_fallback) {
        try self.emit(": runtime.PyValue = ");
        return false; // No wrapper opened - genEval already wraps with PyValue.from()
    }

    // For functions (lambdas) and callables, never emit type annotation
    // - closures can't be coerced to function pointers
    // - callables like operator.mod are different struct types (OperatorMod, OperatorPow, etc.), not PyCallable
    if (!type_traits.isUnknown(value_type) and !is_dict and !is_dictcomp and !is_dict_type and !is_arraylist and !is_list and !is_tuple and !is_closure and !is_function and !is_callable and !is_counter and !is_deque and !is_class_instance and !is_int) {
        try self.emit(": ");
        try value_type.toZigType(self.allocator, &self.output);
    }

    try self.emit(" = ");
    return false; // No wrapper opened
}

/// Generate ArrayList initialization from list literal
/// If wrapper_opened is true, the caller has opened a PyValue.from() wrapper and will close it
/// so we should NOT emit the trailing semicolon on the initial assignment
pub fn genArrayListInit(self: *NativeCodegen, var_name: []const u8, list: ast.Node.List, wrapper_opened: bool) CodegenError!void {
    const native_types = @import("../../../../analysis/native_types.zig");
    const NativeType = native_types.NativeType;
    const genExpr = @import("../../expressions.zig").genExpr;

    // Check if variable was declared BEFORE this current assignment (e.g., global variable with type annotation)
    // Note: isDeclared returns true even if we just declared in the same statement, so we need
    // to check isGlobalVar which indicates pre-existing type annotation
    const has_predeclared_type = self.isGlobalVar(var_name);

    // Check if pre-declared type is an array (not ArrayList)
    // This happens when type inference returns .array for constant homogeneous lists
    const predeclared_is_array = if (has_predeclared_type) blk: {
        const var_type = self.type_inferrer.var_types.get(var_name);
        if (var_type) |vt| {
            break :blk type_traits.isArray(vt);
        }
        break :blk false;
    } else false;

    // If pre-declared as array, use array literal syntax instead of ArrayList pattern
    if (has_predeclared_type and predeclared_is_array) {
        // Generate: [_]T{elem1, elem2, ...}
        // Get element type from the pre-declared array type
        const var_type = self.type_inferrer.var_types.get(var_name);
        const elem_type_str = if (var_type) |vt| blk: {
            if (vt == .array) {
                var type_buf = std.ArrayListUnmanaged(u8){};
                defer type_buf.deinit(self.allocator);
                try vt.array.element_type.toZigType(self.allocator, &type_buf);
                break :blk try self.arena.allocator().dupe(u8, type_buf.items);
            }
            break :blk "i64";
        } else "i64";
        defer if (var_type != null and var_type.? == .array) self.allocator.free(elem_type_str);

        try self.emit("[_]");
        try self.emit(elem_type_str);
        try self.emit("{");
        for (list.elts, 0..) |elem, i| {
            if (i > 0) try self.emit(", ");
            try genExpr(self, elem);
        }
        try self.emit("};\n");
        return;
    }

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
            if (container_traits.isList(vt)) {
                // Get the element type from the list
                break :blk vt.list.*;
            }
        }
        break :blk .{ .int = .bounded }; // Default to int for empty lists
    };

    // Widen type to accommodate all elements (use recursive tuple widening for nested tuples)
    if (list.elts.len > 1) {
        for (list.elts[1..]) |elem| {
            const this_type = try self.type_inferrer.inferExpr(elem);
            elem_type = try widenTupleTypes(self.allocator, elem_type, this_type);
        }
    }

    if (has_predeclared_type) {
        // Variable already has a type - use .{} to inherit the declared type instead of creating a new struct type
        if (wrapper_opened) {
            try self.emit(".{}");  // No semicolon - caller will close wrapper and add semicolon
        } else {
            try self.emit(".{};\n");
        }
    } else {
        try self.emit("std.ArrayListUnmanaged(");
        // Generate element type
        // For unknown element types (*runtime.PyObject), use runtime.PyValue to support
        // heterogeneous elements (e.g., vararg loop class instantiation)
        var type_buf = std.ArrayListUnmanaged(u8){};
        defer type_buf.deinit(self.allocator);
        try elem_type.toZigType(self.allocator, &type_buf);
        const type_str = if (std.mem.eql(u8, type_buf.items, "*runtime.PyObject"))
            "runtime.PyValue"
        else
            type_buf.items;
        try self.emit(type_str);
        // Always close with ){};\n - caller MUST NOT add extra closing
        // because append statements follow immediately
        try self.emit("){}");
        if (wrapper_opened) {
            // Close the PyValue.from() wrapper and end statement
            try self.emit(");\n");
        } else {
            try self.emit(";\n");
        }
    }

    // Check if this is a list of callables (needs wrapping)
    const is_callable_list = type_traits.isCallable(elem_type);
    const is_pyvalue_list = (elem_type == .pyvalue);

    // Track that we're inside a list for nested list generation
    // This ensures nested lists generate as ArrayList, not fixed arrays
    self.inside_list_depth += 1;
    defer self.inside_list_depth -= 1;

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
        } else if (is_pyvalue_list) {
            // Wrap element in PyValue for heterogeneous lists
            try self.emitCallCtx("try runtime.PyValue.fromAlloc", elem, struct {
                pub fn f(s: *NativeCodegen, e: ast.Node) CodegenError!void {
                    try s.emit("__global_allocator, ");
                    try s.genExpr(e);
                }
            }.f);
        } else if (elem_type == .unified_int) {
            // Wrap elements in UnifiedInt for lists that contain mixed int sizes
            // e.g., [324, 2**31] - 324 is i64 but list type is UnifiedInt
            const this_type = try self.type_inferrer.inferExpr(elem);
            const this_tag = @as(std.meta.Tag(@TypeOf(this_type)), this_type);
            if (this_tag == .unified_int) {
                // Already UnifiedInt, emit directly
                try self.genExpr(elem);
            } else if (this_tag == .int) {
                // Wrap i64 literal/expression in UnifiedInt
                try self.emitCallCtx("runtime.UnifiedInt.fromI64", elem, struct {
                    pub fn f(s: *NativeCodegen, e: ast.Node) CodegenError!void {
                        try s.genExpr(e);
                    }
                }.f);
            } else {
                // Other types - emit directly and let Zig handle coercion
                try self.genExpr(elem);
            }
        } else {
            try self.genExpr(elem);
        }
        try self.emit(");\n");
    }

    // Track this variable as ArrayList for len() generation
    const var_name_copy = try self.arena.allocator().dupe(u8, var_name);
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
            try self.emitCallCtx("runtime.builtins.PyCallable.fromAny", elem, struct {
                pub fn f(s: *NativeCodegen, e: ast.Node) CodegenError!void {
                    try s.emitCallCtx("@TypeOf", e, struct {
                        pub fn g(s2: *NativeCodegen, e2: ast.Node) CodegenError!void {
                            try s2.genExpr(e2);
                        }
                    }.g);
                    try s.emit(", ");
                    try s.genExpr(e);
                }
            }.f);
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
            try self.emitCallCtx("runtime.builtins.PyCallable.fromAny", elem, struct {
                pub fn f(s: *NativeCodegen, e: ast.Node) CodegenError!void {
                    try s.emitCallCtx("@TypeOf", e, struct {
                        pub fn g(s2: *NativeCodegen, e2: ast.Node) CodegenError!void {
                            try s2.genExpr(e2);
                        }
                    }.g);
                    try s.emit(", ");
                    try s.genExpr(e);
                }
            }.f);
        },
    }
}

/// Generate string concatenation with multiple parts
/// If wrapper_opened is true, the caller has opened a PyValue.from() wrapper and we close it before the semicolon
pub fn genStringConcat(self: *NativeCodegen, assign: ast.Node.Assign, var_name: []const u8, is_first_assignment: bool, wrapper_opened: bool) CodegenError!void {
    // Collect all parts of the concatenation
    var parts = std.ArrayListUnmanaged(ast.Node){};
    defer parts.deinit(self.allocator);

    try helpers.flattenConcat(self, assign.value.*, &parts);

    // Get allocator name based on scope
    const at_module_level = self.symbol_table.currentScopeLevel() == 0;
    const alloc_name = "__global_allocator"; // Always use global allocator

    // Generate concat with all parts at once
    // At module level (scope 0), we can't use 'try' - use 'catch unreachable' instead
    if (at_module_level) {
        try self.emit("(std.mem.concat(");
    } else {
        try self.emit("try std.mem.concat(");
    }
    try self.emit(alloc_name);
    try self.emit(", u8, &[_][]const u8{ ");
    for (parts.items, 0..) |part, i| {
        if (i > 0) try self.emit(", ");
        try self.genExpr(part);
    }
    if (at_module_level) {
        try self.emit(" }) catch unreachable)");
    } else {
        try self.emit(" })");
    }
    // Close PyValue.from() wrapper if it was opened
    if (wrapper_opened) {
        try self.emit(")");
    }
    try self.emit(";\n");

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
        const var_name_copy = try self.arena.allocator().dupe(u8, var_name);
        try self.array_vars.put(var_name_copy, {});
    }

    // Track if this variable holds an array slice (subscript of constant array)
    if (is_array_slice) {
        const var_name_copy = try self.arena.allocator().dupe(u8, var_name);
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
                const var_name_copy = try self.arena.allocator().dupe(u8, var_name);
                try self.arraylist_vars.put(var_name_copy, {});
            }
        }
    }

    // Track list comprehension variables (generates ArrayList)
    if (is_first_assignment and assign.value.* == .listcomp) {
        const var_name_copy = try self.arena.allocator().dupe(u8, var_name);
        try self.arraylist_vars.put(var_name_copy, {});
    }

    // Track list() builtin calls (generates ArrayList)
    const type_handling = @import("type_handling.zig");
    if (is_first_assignment and type_handling.isListBuiltinCall(assign.value.*)) {
        const var_name_copy = try self.arena.allocator().dupe(u8, var_name);
        try self.arraylist_vars.put(var_name_copy, {});
    }

    // Track dict comprehension variables (generates HashMap)
    if (is_first_assignment and assign.value.* == .dictcomp) {
        const var_name_copy = try self.arena.allocator().dupe(u8, var_name);
        try self.dict_vars.put(var_name_copy, {});
    }

    // Track dict literal variables (generates HashMap)
    if (is_first_assignment and assign.value.* == .dict) {
        const var_name_copy = try self.arena.allocator().dupe(u8, var_name);
        try self.dict_vars.put(var_name_copy, {});
    }

    // Track dict-like calls: dict(), Counter(), defaultdict(), OrderedDict(), etc.
    if (is_first_assignment and type_handling.isDictLikeCall(assign.value.*)) {
        const var_name_copy = try self.arena.allocator().dupe(u8, var_name);
        try self.dict_vars.put(var_name_copy, {});
    }

    const lambda_closure = @import("../../expressions/lambda_closure.zig");
    const lambda_mod = @import("../../expressions/lambda.zig");

    // Track closure factories: make_adder = lambda x: lambda y: x + y
    // IMPORTANT: Only track if lambda was NOT generated via VM fallback
    // VM fallback lambdas are stored as PyValue, not as function pointers/closure structs
    const used_vm_fallback = self.needsVMFallback(assign.value.*);
    if (assign.value.* == .lambda and assign.value.lambda.body.* == .lambda and !used_vm_fallback) {
        try lambda_closure.markAsClosureFactory(self, var_name);
    }

    // Track simple closures: x = 10; f = lambda y: y + x (captures outer variable)
    // IMPORTANT: Skip if VM fallback was used - the variable holds PyValue, not closure
    if (assign.value.* == .lambda and !used_vm_fallback) {
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
            const key = try self.arena.allocator().dupe(u8, var_name);
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
                if (type_traits.isClassInstance(obj_type)) {
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
