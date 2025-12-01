/// Augmented assignment code generation (+=, -=, *=, /=, etc.)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;

/// Generate augmented assignment (+=, -=, *=, /=, //=, **=, %=)
pub fn genAugAssign(self: *NativeCodegen, aug: ast.Node.AugAssign) CodegenError!void {
    try self.emitIndent();

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
