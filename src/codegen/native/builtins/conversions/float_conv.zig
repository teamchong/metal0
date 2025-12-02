/// Float conversion builtins: float()
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;

/// Generate code for float(obj)
/// Converts to f64
pub fn genFloat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // float() with no args returns 0.0
    if (args.len == 0) {
        try self.emit("@as(f64, 0.0)");
        return;
    }
    if (args.len != 1) {
        try self.emit("@as(f64, 0.0)");
        return;
    }

    var arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // For variable names, also check local var types (from for-loop, assignment, etc.)
    // which may have more accurate scoped type info
    if (args[0] == .name) {
        const var_name = args[0].name.id;
        if (self.getVarType(var_name)) |local_type| {
            // Prefer local type if it's more specific (not int/unknown)
            if (local_type == .string or @as(std.meta.Tag(@TypeOf(local_type)), local_type) == .class_instance) {
                arg_type = local_type;
            }
        }
    }

    // Already a float - just return it
    if (arg_type == .float) {
        try self.genExpr(args[0]);
        return;
    }

    // Parse string to float
    if (arg_type == .string) {
        // Check for special float literals that can be used at module level without try
        if (args[0] == .constant) {
            if (args[0].constant.value == .string) {
                const str_val = args[0].constant.value.string;
                // Handle special float values that can be expressed as comptime constants
                if (std.mem.eql(u8, str_val, "nan")) {
                    try self.emit("std.math.nan(f64)");
                    return;
                } else if (std.mem.eql(u8, str_val, "-nan")) {
                    try self.emit("-std.math.nan(f64)");
                    return;
                } else if (std.mem.eql(u8, str_val, "inf") or std.mem.eql(u8, str_val, "infinity")) {
                    try self.emit("std.math.inf(f64)");
                    return;
                } else if (std.mem.eql(u8, str_val, "-inf") or std.mem.eql(u8, str_val, "-infinity")) {
                    try self.emit("-std.math.inf(f64)");
                    return;
                }
                // Try to parse as a numeric literal at comptime
                if (std.fmt.parseFloat(f64, str_val)) |_| {
                    // Valid numeric string - emit as literal
                    try self.emit("@as(f64, ");
                    try self.emit(str_val);
                    try self.emit(")");
                    return;
                } else |_| {}
            }
        }
        // For non-literal strings, use runtime.parseFloatWithUnicode (handles Unicode digits)
        try self.emit("(runtime.parseFloatWithUnicode(");
        try self.genExpr(args[0]);
        try self.emit(") catch 0.0)");
        return;
    }

    // Cast int to float
    // BUT only if we're confident it's an int (not a variable that might be bytes/string)
    if (arg_type == .int) {
        // If this is a variable, be cautious - type inference may be wrong for loop vars
        // Use runtime fallback instead which handles all types
        if (args[0] == .name) {
            try self.emit("(runtime.floatBuiltinCall(");
            try self.genExpr(args[0]);
            try self.emit(", .{}) catch 0.0)");
            return;
        }
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

    // Check if the object is a class instance with __float__ magic method
    const has_magic_method = blk: {
        if (args[0] == .name) {
            const var_name = args[0].name.id;
            // First check if this variable's type is a class instance
            if (self.getVarType(var_name)) |var_type| {
                if (var_type == .class_instance) {
                    const class_name = var_type.class_instance;
                    if (self.classHasMethod(class_name, "__float__")) {
                        break :blk true;
                    }
                }
            }
        }
        break :blk false;
    };

    // If we found a __float__ method, generate method call
    // Use try since __float__ may return error union
    if (has_magic_method and args[0] == .name) {
        try self.emit("(try ");
        try self.genExpr(args[0]);
        try self.emit(".__float__(__global_allocator))");
        return;
    }

    // For strings, use runtime.parseFloatWithUnicode (handles Unicode digits)
    if (arg_type == .string) {
        try self.emit("(runtime.parseFloatWithUnicode(");
        try self.genExpr(args[0]);
        try self.emit(") catch 0.0)");
        return;
    }

    // Generic fallback for unknown types - use runtime.floatBuiltinCall which handles all types
    try self.emit("(runtime.floatBuiltinCall(");
    try self.genExpr(args[0]);
    try self.emit(", .{}) catch 0.0)");
}
