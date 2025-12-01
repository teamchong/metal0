/// Augmented assignment code generation (+=, -=, *=, /=, etc.)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;

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
                // 2. We're in a nested class inside method and it was initialized in __init__
                const is_static = blk: {
                    if (self.current_class_name) |class_name| {
                        if (self.type_inferrer.class_fields.get(class_name)) |class_info| {
                            if (class_info.fields.contains(attr.attr)) {
                                break :blk true;
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

                    // Apply operation
                    const op_str = switch (aug.op) {
                        .Add => " + ",
                        .Sub => " - ",
                        .Mult => " * ",
                        .BitAnd => " & ",
                        .BitOr => " | ",
                        .BitXor => " ^ ",
                        .Div => " / ",
                        .FloorDiv => " / ", // TODO: proper floor div
                        .Mod => " % ",
                        else => " ? ",
                    };
                    try self.emit(op_str);
                    try self.genExpr(aug.value.*);
                    try self.emit(";\n");
                    return;
                } else {
                    // Dynamic attribute aug assign: put the new value
                    try self.emit("try ");
                    try self.emit(self_name);
                    try self.output.writer(self.allocator).print(".__dict__.put(\"{s}\", .{{ .int = ", .{attr.attr});

                    // Get current value and apply operation
                    try self.emit(self_name);
                    try self.output.writer(self.allocator).print(".__dict__.get(\"{s}\").?.int", .{attr.attr});

                    // Apply operation
                    const op_str = switch (aug.op) {
                        .Add => " + ",
                        .Sub => " - ",
                        .Mult => " * ",
                        .BitAnd => " & ",
                        .BitOr => " | ",
                        .BitXor => " ^ ",
                        .Div => " / ",
                        .FloorDiv => " / ", // TODO: proper floor div
                        .Mod => " % ",
                        else => " ? ",
                    };
                    try self.emit(op_str);
                    try self.genExpr(aug.value.*);
                    try self.emit(" });\n");
                    return;
                }
            }
        }
    }

    // Handle subscript with slice augmented assignment: x[1:2] *= 2
    // This is a complex operation that modifies the list in place
    if (aug.target.* == .subscript and aug.target.subscript.slice == .slice) {
        // For slice augmented assignment, we need runtime support
        // For now, emit a self-assignment as placeholder to suppress "never mutated" warning
        // The mutation analyzer marks this variable as mutated, so codegen uses var
        try self.genExpr(aug.target.subscript.value.*);
        try self.emit(" = ");
        try self.genExpr(aug.target.subscript.value.*);
        try self.emit("; // TODO: slice augmented assignment not yet supported\n");
        return;
    }

    // Handle subscript augmented assignment on dicts: x[key] += value
    // Dicts use .get()/.put() instead of direct indexing
    if (aug.target.* == .subscript) {
        const subscript = aug.target.subscript;
        if (subscript.slice == .index) {
            // Check if base is a dict: either by type inference or by tracking
            const base_type = try self.inferExprScoped(subscript.value.*);
            const is_tracked_dict = if (subscript.value.* == .name)
                self.isDictVar(subscript.value.name.id)
            else
                false;
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
                    try self.emit("@rem(");
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
                try self.emit(").?");
                try self.emit(") ");

                // Emit simple binary operation
                const op_str = switch (aug.op) {
                    .Add => "+",
                    .Sub => "-",
                    .Mult => "*",
                    .BitAnd => "&",
                    .BitOr => "|",
                    .BitXor => "^",
                    else => "?",
                };
                try self.emit(op_str);
                try self.emit(" ");
                try self.genExpr(aug.value.*);
                try self.emit(");\n");
                return;
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
        try self.emit("@rem(");
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
        // MatMul: target @= value => call __imatmul__ if available, else numpy.matmulAuto
        const target_type = try self.inferExprScoped(aug.target.*);
        if (target_type == .class_instance or target_type == .unknown) {
            // User class with __imatmul__: try target.__imatmul__(allocator, value)
            try self.emit("try ");
            try self.genExpr(aug.target.*);
            try self.emit(".__imatmul__(__global_allocator, ");
            try self.genExpr(aug.value.*);
            try self.emit(");\n");
        } else {
            // numpy arrays: numpy.matmulAuto(target, value, allocator)
            try self.emit("try numpy.matmulAuto(");
            try self.genExpr(aug.target.*);
            try self.emit(", ");
            try self.genExpr(aug.value.*);
            try self.emit(", allocator);\n");
        }
        return;
    }

    // Special handling for list/array concatenation: x += [1, 2]
    // Check if RHS is a list literal
    if (aug.op == .Add and aug.value.* == .list) {
        try self.emit("runtime.concat(");
        try self.genExpr(aug.target.*);
        try self.emit(", ");
        try self.genExpr(aug.value.*);
        try self.emit(");\n");
        return;
    }

    // Special handling for list/array multiplication: x *= 2
    // Check if LHS is a list type
    if (aug.op == .Mult) {
        const target_type = try self.inferExprScoped(aug.target.*);
        if (target_type == .list or aug.target.* == .list) {
            // List repeat: x *= n => runtime.listRepeat(x, n)
            try self.emit("runtime.listRepeat(");
            try self.genExpr(aug.target.*);
            try self.emit(", ");
            try self.genExpr(aug.value.*);
            try self.emit(");\n");
            return;
        }
    }

    try self.genExpr(aug.target.*);

    const op_str = switch (aug.op) {
        .Add => " + ",
        .Sub => " - ",
        .Mult => " * ",
        .Div => " / ",
        .BitAnd => " & ",
        .BitOr => " | ",
        .BitXor => " ^ ",
        else => " ? ",
    };
    try self.emit(op_str);

    try self.genExpr(aug.value.*);
    try self.emit(";\n");
}
