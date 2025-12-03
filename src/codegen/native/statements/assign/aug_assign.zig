/// Augmented assignment code generation (+=, -=, *=, /=, etc.)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const shared = @import("../../shared_maps.zig");
const BinaryDunders = shared.BinaryDunders;
const InplaceDunders = shared.InplaceDunders;

/// Simple binary operator strings (with spaces for assignment context)
const SimpleOpStrings = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Add", " + " }, .{ "Sub", " - " }, .{ "Mult", " * " },
    .{ "BitAnd", " & " }, .{ "BitOr", " | " }, .{ "BitXor", " ^ " },
    .{ "Div", " / " }, .{ "FloorDiv", " / " },
});

/// Compact binary operator strings (no spaces, for dict context)
const CompactOpStrings = std.StaticStringMap([]const u8).initComptime(.{
    .{ "Add", "+" }, .{ "Sub", "-" }, .{ "Mult", "*" },
    .{ "BitAnd", "&" }, .{ "BitOr", "|" }, .{ "BitXor", "^" },
});

/// Generate augmented assignment (+=, -=, *=, /=, //=, **=, %=)
pub fn genAugAssign(self: *NativeCodegen, aug: ast.Node.AugAssign) CodegenError!void {
    try self.emitIndent();

    // Handle self.attr augmented assignment
    // For static fields: __self.count = __self.count + 1
    // For dynamic fields: try __self.__dict__.put("count", .{ .int = ... + 1 });
    if (aug.target.* == .attribute) {
        const attr = aug.target.attribute;
        if (attr.value.* == .name) {
            const obj_name = attr.value.name.id;
            // Check if this is self.field
            if (std.mem.eql(u8, obj_name, "self") or std.mem.eql(u8, obj_name, "__self")) {
                // Determine correct self name for nested classes
                const self_name = if (self.method_nesting_depth > 0) "__self" else "self";

                // Check if attribute is dynamic (stored in __dict__) vs static (struct field)
                // A field is static if:
                // 1. It's in class_fields registry for current class, OR
                // 2. It's in parent class fields (for nested classes)
                const is_static = blk: {
                    if (self.current_class_name) |class_name| {
                        // Check own class fields
                        if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                            if (class_info.fields.contains(attr.attr)) {
                                break :blk true;
                            }
                        }
                        // Check parent class fields for nested classes
                        if (self.nested_class_bases.get(class_name)) |parent_name| {
                            if (self.type_inferrer.class_fields.get(parent_name)) |parent_info| {
                                if (parent_info.fields.contains(attr.attr)) {
                                    break :blk true;
                                }
                            }
                        }
                    }
                    // For nested classes not in registry, check nested_class_names
                    // These classes will have all init fields as static
                    if (self.nested_class_names.contains(attr.attr)) {
                        break :blk false; // The attr itself is a nested class, not static field
                    }
                    // If we can't determine, assume static (direct field access)
                    // This works because nested classes generate static fields from __init__
                    break :blk true;
                };

                if (is_static) {
                    // Static field: direct field access assignment
                    try self.emit(self_name);
                    try self.emit(".");
                    try self.emit(attr.attr);
                    try self.emit(" = ");
                    try self.emit(self_name);
                    try self.emit(".");
                    try self.emit(attr.attr);
                    try self.emit(SimpleOpStrings.get(@tagName(aug.op)) orelse if (aug.op == .Mod) " % " else " ? ");
                    try self.genExpr(aug.value.*);
                    try self.emit(";\n");
                    return;
                } else {
                    // Dynamic attribute aug assign: put the new value
                    try self.emit("try ");
                    try self.emit(self_name);
                    try self.output.writer(self.allocator).print(".__dict__.put(\"{s}\", .{{ .int = ", .{attr.attr});
                    try self.emit(self_name);
                    try self.output.writer(self.allocator).print(".__dict__.get(\"{s}\").?.int", .{attr.attr});
                    try self.emit(SimpleOpStrings.get(@tagName(aug.op)) orelse if (aug.op == .Mod) " % " else " ? ");
                    try self.genExpr(aug.value.*);
                    try self.emit(" });\n");
                    return;
                }
            }
        }
    }

    // Handle subscript with slice augmented assignment: x[1:2] *= 2, x[1:2] += [3]
    // This modifies the list in place by replacing the slice with the result
    if (aug.target.* == .subscript and aug.target.subscript.slice == .slice) {
        const subscript = aug.target.subscript;
        const slice = subscript.slice.slice;

        // Generate a block for the slice aug assign operation
        try self.emit("{\n");
        self.indent();

        // Get slice bounds - handle ArrayList aliases (need to dereference)
        try self.emitIndent();
        try self.emit("const __list = ");
        if (subscript.value.* == .name) {
            const var_name = subscript.value.name.id;
            if (self.isArrayListAlias(var_name)) {
                // Alias is already a pointer, just use it directly
                try self.genExpr(subscript.value.*);
            } else {
                // Regular ArrayList, take address
                try self.emit("&");
                try self.genExpr(subscript.value.*);
            }
        } else {
            try self.emit("&");
            try self.genExpr(subscript.value.*);
        }
        try self.emit(";\n");

        // Calculate start index
        try self.emitIndent();
        if (slice.lower) |lower| {
            try self.emit("const __start: usize = @intCast(");
            try self.genExpr(lower.*);
            try self.emit(");\n");
        } else {
            try self.emit("const __start: usize = 0;\n");
        }

        // Calculate end index
        try self.emitIndent();
        if (slice.upper) |upper| {
            try self.emit("const __end: usize = @intCast(");
            try self.genExpr(upper.*);
            try self.emit(");\n");
        } else {
            try self.emit("const __end: usize = __list.items.len;\n");
        }

        // Extract the slice to operate on
        try self.emitIndent();
        try self.emit("const __slice = __list.items[__start..__end];\n");

        // Generate the operation based on operator
        if (aug.op == .Mult) {
            // x[start:end] *= n - repeat the slice n times
            try self.emitIndent();
            try self.emit("const __repeat_count: usize = @intCast(");
            try self.genExpr(aug.value.*);
            try self.emit(");\n");

            // Create new slice content (repeated)
            try self.emitIndent();
            try self.emit("var __new_items = std.ArrayList(@TypeOf(__list.items[0])){};\n");
            try self.emitIndent();
            try self.emit("for (0..__repeat_count) |_| {\n");
            self.indent();
            try self.emitIndent();
            try self.emit("for (__slice) |item| {\n");
            self.indent();
            try self.emitIndent();
            try self.emit("try __new_items.append(__global_allocator, item);\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");

            // Replace the slice in the original list
            try self.emitIndent();
            try self.emit("try __list.replaceRange(__global_allocator, __start, __end - __start, __new_items.items);\n");

            // Cleanup
            try self.emitIndent();
            try self.emit("__new_items.deinit(__global_allocator);\n");
        } else if (aug.op == .Add) {
            // x[start:end] += [items] - extend the slice with items
            try self.emitIndent();
            try self.emit("var __new_items = std.ArrayList(@TypeOf(__list.items[0])){};\n");

            // First add original slice items
            try self.emitIndent();
            try self.emit("for (__slice) |item| {\n");
            self.indent();
            try self.emitIndent();
            try self.emit("try __new_items.append(__global_allocator, item);\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");

            // Then add the extension items
            try self.emitIndent();
            try self.emit("const __extend_items = ");
            try self.genExpr(aug.value.*);
            try self.emit(";\n");
            try self.emitIndent();
            try self.emit("for (__extend_items) |item| {\n");
            self.indent();
            try self.emitIndent();
            try self.emit("try __new_items.append(__global_allocator, item);\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");

            // Replace the slice in the original list
            try self.emitIndent();
            try self.emit("try __list.replaceRange(__global_allocator, __start, __end - __start, __new_items.items);\n");

            // Cleanup
            try self.emitIndent();
            try self.emit("__new_items.deinit(__global_allocator);\n");
        } else {
            // Other operators not commonly used with slice aug assign
            try self.emitIndent();
            try self.emit("_ = __slice; // TODO: unsupported slice aug assign op\n");
        }

        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        return;
    }

    // Handle subscript augmented assignment on dicts and ArrayLists: x[key] += value
    if (aug.target.* == .subscript) {
        const subscript = aug.target.subscript;
        if (subscript.slice == .index) {
            // Check if base is a dict or ArrayList
            const base_type = try self.inferExprScoped(subscript.value.*);
            const is_tracked_dict = if (subscript.value.* == .name)
                self.isDictVar(subscript.value.name.id)
            else
                false;
            const is_arraylist = if (subscript.value.* == .name)
                self.isArrayListVar(subscript.value.name.id)
            else
                false;

            // Handle ArrayList subscript aug assign: x[i] += value
            // Generates: x.items[@as(usize, @intCast(i))] = x.items[...] OP value;
            // IMPORTANT: Check dict FIRST since dict also uses subscript
            if (is_arraylist and !is_tracked_dict and base_type != .dict) {
                // Special cases that need function calls
                if (aug.op == .Pow) {
                    try self.genExpr(subscript.value.*);
                    try self.emit(".items[@as(usize, @intCast(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit("))] = std.math.pow(i64, ");
                    try self.genExpr(subscript.value.*);
                    try self.emit(".items[@as(usize, @intCast(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit("))], ");
                    try self.genExpr(aug.value.*);
                    try self.emit(");\n");
                    return;
                }
                if (aug.op == .FloorDiv) {
                    try self.genExpr(subscript.value.*);
                    try self.emit(".items[@as(usize, @intCast(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit("))] = @divFloor(");
                    try self.genExpr(subscript.value.*);
                    try self.emit(".items[@as(usize, @intCast(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit("))], ");
                    try self.genExpr(aug.value.*);
                    try self.emit(");\n");
                    return;
                }
                if (aug.op == .Div) {
                    try self.genExpr(subscript.value.*);
                    try self.emit(".items[@as(usize, @intCast(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit("))] = @divTrunc(");
                    try self.genExpr(subscript.value.*);
                    try self.emit(".items[@as(usize, @intCast(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit("))], ");
                    try self.genExpr(aug.value.*);
                    try self.emit(");\n");
                    return;
                }
                if (aug.op == .Mod) {
                    try self.genExpr(subscript.value.*);
                    try self.emit(".items[@as(usize, @intCast(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit("))] = @mod(");
                    try self.genExpr(subscript.value.*);
                    try self.emit(".items[@as(usize, @intCast(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit("))], ");
                    try self.genExpr(aug.value.*);
                    try self.emit(");\n");
                    return;
                }

                try self.genExpr(subscript.value.*);
                try self.emit(".items[@as(usize, @intCast(");
                try self.genExpr(subscript.slice.index.*);
                try self.emit("))] = ");
                try self.genExpr(subscript.value.*);
                try self.emit(".items[@as(usize, @intCast(");
                try self.genExpr(subscript.slice.index.*);
                try self.emit("))]");
                try self.emit(SimpleOpStrings.get(@tagName(aug.op)) orelse " ? ");
                try self.genExpr(aug.value.*);
                try self.emit(";\n");
                return;
            }

            if (base_type == .dict or is_tracked_dict) {
                // Dict subscript aug assign: x[key] += value
                // Generates: try base.put(key, (base.get(key).? OP value));
                try self.emit("try ");
                try self.genExpr(subscript.value.*);
                try self.emit(".put(");
                try self.genExpr(subscript.slice.index.*);
                try self.emit(", ");

                // Special cases for operators that need function calls
                if (aug.op == .FloorDiv) {
                    try self.emit("@divFloor(");
                    try self.genExpr(subscript.value.*);
                    try self.emit(".get(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit(").?, ");
                    try self.genExpr(aug.value.*);
                    try self.emit("));\n");
                    return;
                }
                if (aug.op == .Pow) {
                    try self.emit("std.math.pow(i64, ");
                    try self.genExpr(subscript.value.*);
                    try self.emit(".get(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit(").?, ");
                    try self.genExpr(aug.value.*);
                    try self.emit("));\n");
                    return;
                }
                if (aug.op == .Mod) {
                    try self.emit("@mod(");
                    try self.genExpr(subscript.value.*);
                    try self.emit(".get(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit(").?, ");
                    try self.genExpr(aug.value.*);
                    try self.emit("));\n");
                    return;
                }
                if (aug.op == .Div) {
                    try self.emit("@divTrunc(");
                    try self.genExpr(subscript.value.*);
                    try self.emit(".get(");
                    try self.genExpr(subscript.slice.index.*);
                    try self.emit(").?, ");
                    try self.genExpr(aug.value.*);
                    try self.emit("));\n");
                    return;
                }

                // Generate the value expression with operation
                try self.emit("(");
                try self.genExpr(subscript.value.*);
                try self.emit(".get(");
                try self.genExpr(subscript.slice.index.*);
                try self.emit(").?) ");
                try self.emit(CompactOpStrings.get(@tagName(aug.op)) orelse "?");
                try self.emit(" ");
                try self.genExpr(aug.value.*);
                try self.emit(");\n");
                return;
            }
        }
    }

    // Special handling for list/array concatenation: x += [1, 2]
    // Check if RHS is a list literal
    // IMPORTANT: Must be before "Emit target" to avoid generating "x = try x.appendSlice"
    if (aug.op == .Add and aug.value.* == .list) {
        // Check if target is an ArrayList (will be mutated)
        const is_arraylist = if (aug.target.* == .name)
            self.isArrayListVar(aug.target.name.id)
        else
            false;

        if (is_arraylist) {
            // ArrayList: extend in place via appendSlice
            try self.emit("try ");
            try self.genExpr(aug.target.*);
            try self.emit(".appendSlice(__global_allocator, &");
            try self.genExpr(aug.value.*);
            try self.emit(");\n");
        } else {
            // Static array: use comptime concat
            try self.genExpr(aug.target.*);
            try self.emit(" = runtime.concat(");
            try self.genExpr(aug.target.*);
            try self.emit(", ");
            try self.genExpr(aug.value.*);
            try self.emit(");\n");
        }
        return;
    }

    // Special handling for list/array multiplication: x *= 2
    // Check if LHS is actually an ArrayList (NOT a class instance with __imul__)
    // IMPORTANT: Must be before "Emit target" to avoid generating "x = { block }"
    if (aug.op == .Mult) {
        // First check if this is a class instance - if so, use dunder methods
        const target_type_for_mult = try self.inferExprScoped(aug.target.*);
        if (target_type_for_mult == .class_instance) {
            // Fall through to class instance handler below
        } else {
            const is_arraylist = if (aug.target.* == .name)
                self.isArrayListVar(aug.target.name.id)
            else
                false;

            if (is_arraylist) {
            // ArrayList: repeat in place by copying original items n-1 more times
            try self.emit("{\n");
            self.indent();
            try self.emitIndent();
            try self.emit("const __orig_len = ");
            try self.genExpr(aug.target.*);
            try self.emit(".items.len;\n");
            try self.emitIndent();
            try self.emit("var __i: usize = 1;\n");
            try self.emitIndent();
            try self.emit("while (__i < @as(usize, @intCast(");
            try self.genExpr(aug.value.*);
            try self.emit("))) : (__i += 1) {\n");
            self.indent();
            try self.emitIndent();
            try self.emit("try ");
            try self.genExpr(aug.target.*);
            try self.emit(".appendSlice(__global_allocator, ");
            try self.genExpr(aug.target.*);
            try self.emit(".items[0..__orig_len]);\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
            return;
            }
        }
    }

    // Handle class instance operators: x += val calls x.__iadd__(val) or x = x.__add__(val)
    const target_type = try self.inferExprScoped(aug.target.*);
    if (target_type == .class_instance) {
        const class_name = target_type.class_instance;
        const op_name = @tagName(aug.op);
        const iadd_method = InplaceDunders.get(op_name);
        const add_method = BinaryDunders.get(op_name);

        if (iadd_method != null or add_method != null) {
            // Check if class has __iadd__ method
            // For global classes, search in class_registry (includes inheritance)
            // For nested classes, check nested_class_names (we'll generate optimistically)
            const is_nested_class = self.nested_class_names.contains(class_name);
            const has_iadd = iadd_method != null and (is_nested_class or
                self.class_registry.findMethod(class_name, iadd_method.?) != null);

            if (has_iadd) {
                // x += val => x = x.__iadd__(allocator, val)
                // For nested classes, use @hasDecl runtime check to fallback to __add__
                if (is_nested_class) {
                    // In assertRaises context, catch errors instead of propagating
                    if (self.in_assert_raises_context) {
                        // Generate: _ = (if (@hasDecl(...)) x.__iadd__(...) else x.__add__(...)) catch null;
                        try self.emit("_ = (if (@hasDecl(@TypeOf(");
                        try self.genExpr(aug.target.*);
                        try self.emitFmt(".*), \"{s}\")) ", .{iadd_method.?});
                        try self.genExpr(aug.target.*);
                        try self.emitFmt(".{s}(__global_allocator, ", .{iadd_method.?});
                        try self.genExpr(aug.value.*);
                        try self.emit(") else ");
                        try self.genExpr(aug.target.*);
                        try self.emitFmt(".{s}(__global_allocator, ", .{add_method.?});
                        try self.genExpr(aug.value.*);
                        try self.emit(")) catch null;\n");
                    } else {
                        // Generate: x = if (@hasDecl(@TypeOf(x.*), "__iadd__")) try x.__iadd__(allocator, val) else try x.__add__(allocator, val);
                        // Note: x is a pointer (*ClassName) for heap-allocated nested classes, so use x.* to get struct type
                        try self.genExpr(aug.target.*);
                        try self.emit(" = if (@hasDecl(@TypeOf(");
                        try self.genExpr(aug.target.*);
                        try self.emitFmt(".*), \"{s}\")) try ", .{iadd_method.?});
                        try self.genExpr(aug.target.*);
                        try self.emitFmt(".{s}(__global_allocator, ", .{iadd_method.?});
                        try self.genExpr(aug.value.*);
                        try self.emit(") else try ");
                        try self.genExpr(aug.target.*);
                        try self.emitFmt(".{s}(__global_allocator, ", .{add_method.?});
                        try self.genExpr(aug.value.*);
                        try self.emit(");\n");
                    }
                } else {
                    try self.genExpr(aug.target.*);
                    try self.emit(" = try ");
                    try self.genExpr(aug.target.*);
                    try self.emitFmt(".{s}(__global_allocator, ", .{iadd_method.?});
                    try self.genExpr(aug.value.*);
                    try self.emit(");\n");
                }
                return;
            } else if (add_method != null) {
                // Check if class has __add__ method (fallback)
                const has_add = is_nested_class or
                    self.class_registry.findMethod(class_name, add_method.?) != null;

                if (has_add) {
                    // x += val => x = try x.__add__(allocator, val)
                    try self.genExpr(aug.target.*);
                    try self.emit(" = try ");
                    try self.genExpr(aug.target.*);
                    try self.emitFmt(".{s}(__global_allocator, ", .{add_method.?});
                    try self.genExpr(aug.value.*);
                    try self.emit(");\n");
                    return;
                }
            }
        }
    }

    // Emit target (variable name)
    try self.genExpr(aug.target.*);
    try self.emit(" = ");

    // Special handling for floor division and power
    if (aug.op == .FloorDiv) {
        try self.emit("@divFloor(");
        try self.genExpr(aug.target.*);
        try self.emit(", ");
        try self.genExpr(aug.value.*);
        try self.emit(");\n");
        return;
    }

    if (aug.op == .Pow) {
        try self.emit("std.math.pow(i64, ");
        try self.genExpr(aug.target.*);
        try self.emit(", ");
        try self.genExpr(aug.value.*);
        try self.emit(");\n");
        return;
    }

    if (aug.op == .Mod) {
        try self.emit("@mod(");
        try self.genExpr(aug.target.*);
        try self.emit(", ");
        try self.genExpr(aug.value.*);
        try self.emit(");\n");
        return;
    }

    // Handle true division - Python's /= on integers returns float but we're in-place
    // For integer division assignment, use @divTrunc to truncate to integer
    if (aug.op == .Div) {
        try self.emit("@divTrunc(");
        try self.genExpr(aug.target.*);
        try self.emit(", ");
        try self.genExpr(aug.value.*);
        try self.emit(");\n");
        return;
    }

    // Handle bitwise shift operators separately due to RHS type casting
    if (aug.op == .LShift or aug.op == .RShift) {
        const shift_fn = if (aug.op == .LShift) "std.math.shl" else "std.math.shr";
        try self.emitFmt("{s}(i64, ", .{shift_fn});
        try self.genExpr(aug.target.*);
        try self.emit(", @as(u6, @intCast(");
        try self.genExpr(aug.value.*);
        try self.emit(")));\n");
        return;
    }

    // Regular operators: +=, -=, *=, /=, &=, |=, ^=
    // Handle matrix multiplication separately
    if (aug.op == .MatMul) {
        // MatMul: target @= value => call __imatmul__ method
        try self.emit("try ");
        try self.genExpr(aug.target.*);
        try self.emit(".__imatmul__(__global_allocator, ");
        try self.genExpr(aug.value.*);
        try self.emit(");\n");
        return;
    }

    try self.genExpr(aug.target.*);
    try self.emit(SimpleOpStrings.get(@tagName(aug.op)) orelse " ? ");
    try self.genExpr(aug.value.*);
    try self.emit(";\n");
}
