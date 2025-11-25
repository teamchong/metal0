/// Type conversion builtins: len(), str(), int(), float(), bool()
const std = @import("std");
const ast = @import("../../../ast.zig");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

/// Generate code for len(obj)
/// Works with: strings, lists, dicts, tuples
pub fn genLen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        // TODO: Error handling
        return;
    }

    // Check if the object has __len__ magic method (custom class support)
    const has_magic_method = blk: {
        if (args[0] == .name) {
            // Check all registered classes to see if any have __len__
            var class_iter = self.class_registry.iterator();
            while (class_iter.next()) |entry| {
                if (self.classHasMethod(entry.key_ptr.*, "__len__")) {
                    break :blk true;
                }
            }
        }
        break :blk false;
    };

    // If we found a __len__ method, generate method call
    if (has_magic_method and args[0] == .name) {
        try self.genExpr(args[0]);
        try self.emit(".__len__()");
        return;
    }

    // Check if argument is dict or tuple
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    const is_dict = switch (arg_type) {
        .dict => true,
        else => false,
    };
    const is_set = switch (arg_type) {
        .set => true,
        else => false,
    };
    const is_tuple = switch (arg_type) {
        .tuple => true,
        else => false,
    };

    // Check if this is a tracked ArrayList variable (must check BEFORE dict/set type check)
    // Dict comprehensions generate ArrayList but are typed as .dict
    const is_arraylist = blk: {
        if (args[0] == .name) {
            const var_name = args[0].name.id;
            if (self.isArrayListVar(var_name)) {
                break :blk true;
            }
        }
        break :blk false;
    };

    // Check if this is a **kwargs parameter (PyObject wrapper around PyDict)
    const is_kwarg_param = blk: {
        if (args[0] == .name) {
            const var_name = args[0].name.id;
            if (self.kwarg_params.contains(var_name)) {
                break :blk true;
            }
        }
        break :blk false;
    };

    // Generate:
    // - runtime.PyDict.len(obj) for **kwargs parameters
    // - obj.items.len for ArrayList (including dict comprehensions)
    // - obj.count() for HashMap/dict/set
    // - @typeInfo(...).fields.len for tuples
    // - obj.len for slices/arrays/strings
    // All results are cast to i64 since Python len() returns int
    try self.emit("@as(i64, @intCast(");
    if (is_kwarg_param) {
        // **kwargs is a *runtime.PyObject (PyDict), use runtime.PyDict.len()
        try self.emit("runtime.PyDict.len(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else if (is_arraylist) {
        try self.genExpr(args[0]);
        try self.emit(".items.len");
    } else if (is_tuple) {
        try self.emit("@typeInfo(@TypeOf(");
        try self.genExpr(args[0]);
        try self.emit(")).@\"struct\".fields.len");
    } else if (is_dict or is_set) {
        try self.genExpr(args[0]);
        try self.emit(".count()");
    } else {
        // For arrays, slices, strings - just use .len
        try self.genExpr(args[0]);
        try self.emit(".len");
    }
    try self.emit("))");
}

/// Generate code for str(obj)
/// Converts to string representation
pub fn genStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Already a string - just return it
    if (arg_type == .string) {
        try self.genExpr(args[0]);
        return;
    }

    // Convert number to string
    try self.emit("blk: {\n");
    try self.emit("var buf = std.ArrayList(u8){};\n");

    if (arg_type == .int) {
        try self.emit("try buf.writer(allocator).print(\"{}\", .{");
    } else if (arg_type == .float) {
        try self.emit("try buf.writer(allocator).print(\"{d}\", .{");
    } else if (arg_type == .bool) {
        // Python bool to string: True/False
        try self.emit("try buf.writer(allocator).print(\"{s}\", .{if (");
        try self.genExpr(args[0]);
        try self.emit(") \"True\" else \"False\"});\n");
        try self.emit("break :blk try buf.toOwnedSlice(allocator);\n");
        try self.emit("}");
        return;
    } else {
        try self.emit("try buf.writer(allocator).print(\"{any}\", .{");
    }

    try self.genExpr(args[0]);
    try self.emit("});\n");
    try self.emit("break :blk try buf.toOwnedSlice(allocator);\n");
    try self.emit("}");
}

/// Generate code for int(obj)
/// Converts to i64
pub fn genInt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Already an int - just return it
    if (arg_type == .int) {
        try self.genExpr(args[0]);
        return;
    }

    // Parse string to int
    if (arg_type == .string) {
        try self.emit("try std.fmt.parseInt(i64, ");
        try self.genExpr(args[0]);
        try self.emit(", 10)");
        return;
    }

    // Cast float to int
    if (arg_type == .float) {
        try self.emit("@as(i64, @intFromFloat(");
        try self.genExpr(args[0]);
        try self.emit("))");
        return;
    }

    // Cast bool to int (True -> 1, False -> 0)
    if (arg_type == .bool) {
        try self.emit("@as(i64, @intFromBool(");
        try self.genExpr(args[0]);
        try self.emit("))");
        return;
    }

    // Generic cast for unknown types
    try self.emit("@intCast(");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate code for float(obj)
/// Converts to f64
pub fn genFloat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Already a float - just return it
    if (arg_type == .float) {
        try self.genExpr(args[0]);
        return;
    }

    // Parse string to float
    if (arg_type == .string) {
        try self.emit("try std.fmt.parseFloat(f64, ");
        try self.genExpr(args[0]);
        try self.emit(")");
        return;
    }

    // Cast int to float
    if (arg_type == .int) {
        try self.emit("@as(f64, @floatFromInt(");
        try self.genExpr(args[0]);
        try self.emit("))");
        return;
    }

    // Cast bool to float (True -> 1.0, False -> 0.0)
    if (arg_type == .bool) {
        try self.emit("@as(f64, @floatFromInt(@intFromBool(");
        try self.genExpr(args[0]);
        try self.emit(")))");
        return;
    }

    // Generic cast for unknown types
    try self.emit("@floatCast(");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate code for bool(obj)
/// Converts to bool
/// Python truthiness rules: 0, "", [], {} are False, everything else is True
pub fn genBool(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    // For now: simple cast for numbers
    // TODO: Implement truthiness for strings/lists/dicts
    // - Empty string "" -> false
    // - Empty list [] -> false
    // - Zero 0 -> false
    // - Non-zero numbers -> true
    // Wrap in parens to avoid chained comparison issues when used in expressions
    try self.emit("(");
    try self.genExpr(args[0]);
    try self.emit(" != 0)");
}

/// Generate code for type(obj)
/// Returns compile-time type name as string
pub fn genType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) return;

    // Generate: @typeName(@TypeOf(obj))
    try self.emit("@typeName(@TypeOf(");
    try self.genExpr(args[0]);
    try self.emit("))");
}

/// Generate code for isinstance(obj, type)
/// Checks if object matches expected type at compile time
/// For native codegen, this is a compile-time type check
pub fn genIsinstance(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 2) return;

    // For native codegen, check if types match
    // Generate: @TypeOf(obj) == expected_type
    // Since we can't easily get the type from the second arg (it's a name like "int"),
    // we'll do a simple runtime check for common cases

    // For now, just return true (type checking happens at compile time in Zig)
    // A proper implementation would need type inference on both arguments
    try self.emit("true");
}

/// Generate code for repr(obj)
/// Returns string representation with quotes for strings
/// repr(True) -> "True", repr("hello") -> "'hello'"
pub fn genRepr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // For strings, wrap with quotes: "'string'"
    if (arg_type == .string) {
        try self.emit("blk: {\n");
        try self.emit("var buf = std.ArrayList(u8){};\n");
        try self.emit("try buf.appendSlice(allocator, \"'\");\n");
        try self.emit("try buf.appendSlice(allocator, ");
        try self.genExpr(args[0]);
        try self.emit(");\n");
        try self.emit("try buf.appendSlice(allocator, \"'\");\n");
        try self.emit("break :blk try buf.toOwnedSlice(allocator);\n");
        try self.emit("}");
        return;
    }

    // For bools: True/False
    if (arg_type == .bool) {
        try self.emit("(if (");
        try self.genExpr(args[0]);
        try self.emit(") \"True\" else \"False\")");
        return;
    }

    // For numbers, same as str()
    try self.emit("blk: {\n");
    try self.emit("var buf = std.ArrayList(u8){};\n");

    if (arg_type == .int) {
        try self.emit("try buf.writer(allocator).print(\"{}\", .{");
    } else if (arg_type == .float) {
        try self.emit("try buf.writer(allocator).print(\"{d}\", .{");
    } else {
        try self.emit("try buf.writer(allocator).print(\"{any}\", .{");
    }

    try self.genExpr(args[0]);
    try self.emit("});\n");
    try self.emit("break :blk try buf.toOwnedSlice(allocator);\n");
    try self.emit("}");
}
