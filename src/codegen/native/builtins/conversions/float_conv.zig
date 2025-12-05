/// Float conversion builtins: float()
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;

/// Generate the error handling suffix for failable float operations.
/// Inside try blocks, use "try" to propagate errors to handlers.
/// Otherwise, use "catch 0.0" to silently handle errors.
fn emitFloatErrorHandling(self: *NativeCodegen, expr_start: []const u8, expr_end: []const u8) CodegenError!void {
    if (self.inside_try_body) {
        // Inside try block - propagate errors up
        try self.emit("(try ");
        try self.emit(expr_start);
        try self.emit(expr_end);
        try self.emit(")");
    } else {
        // Outside try block - catch and return default
        try self.emit("(");
        try self.emit(expr_start);
        try self.emit(expr_end);
        try self.emit(" catch 0.0)");
    }
}

/// Check if a string is a special float literal (case-insensitive)
/// Returns the corresponding Zig constant or null if not a special literal
fn getSpecialFloatLiteral(str: []const u8) ?[]const u8 {
    // Handle empty string
    if (str.len == 0) return null;

    // Check for leading sign
    var idx: usize = 0;
    var is_negative = false;
    if (str[0] == '+') {
        idx = 1;
    } else if (str[0] == '-') {
        idx = 1;
        is_negative = true;
    }

    // Get the rest of the string (after sign)
    const rest = str[idx..];
    if (rest.len == 0) return null;

    // Case-insensitive check for inf/infinity/nan
    if (std.ascii.eqlIgnoreCase(rest, "inf") or std.ascii.eqlIgnoreCase(rest, "infinity")) {
        return if (is_negative) "-std.math.inf(f64)" else "std.math.inf(f64)";
    }
    if (std.ascii.eqlIgnoreCase(rest, "nan")) {
        // IEEE 754 NaN has a sign bit - Python's copysign() can detect it
        return if (is_negative) "-std.math.nan(f64)" else "std.math.nan(f64)";
    }

    return null;
}

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
        if (args[0] == .constant and args[0].constant.value == .string) {
            const str_val = args[0].constant.value.string;
            // Handle special float values (inf, nan, etc.) case-insensitively
            if (getSpecialFloatLiteral(str_val)) |zig_const| {
                try self.emit(zig_const);
                return;
            }
            // Try to parse as a numeric literal at comptime
            // Strip leading + for Zig compatibility (Zig doesn't accept "+123")
            const parse_str = if (str_val.len > 0 and str_val[0] == '+') str_val[1..] else str_val;
            if (std.fmt.parseFloat(f64, parse_str)) |_| {
                try self.emit("@as(f64, ");
                try self.emit(parse_str);
                try self.emit(")");
                return;
            } else |_| {}
        }
        // For non-literal strings, use runtime float parsing (handles Unicode digits)
        if (self.inside_try_body) {
            // Use parseFloatStr which sets proper error message for except handlers
            try self.emit("(try runtime.parseFloatStr(");
            try self.genExpr(args[0]);
            try self.emit("))");
        } else {
            try self.emit("(runtime.parseFloatWithUnicode(");
            try self.genExpr(args[0]);
            try self.emit(") catch 0.0)");
        }
        return;
    }

    // Cast int to float
    // BUT only if we're confident it's an int (not a variable that might be bytes/string)
    if (arg_type == .int) {
        // If this is a variable, be cautious - type inference may be wrong for loop vars
        // Use runtime fallback instead which handles all types
        if (args[0] == .name) {
            if (self.inside_try_body) {
                try self.emit("(try runtime.floatBuiltinCall(");
                try self.genExpr(args[0]);
                try self.emit(", .{}))");
            } else {
                try self.emit("(runtime.floatBuiltinCall(");
                try self.genExpr(args[0]);
                try self.emit(", .{}) catch 0.0)");
            }
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
    // __float__ returns f64 - signature varies (some take allocator, some don't)
    // Use runtime.floatBuiltinCall which handles both cases via @hasDecl
    if (has_magic_method and args[0] == .name) {
        if (self.inside_try_body) {
            try self.emit("(try runtime.floatBuiltinCall(");
            try self.genExpr(args[0]);
            try self.emit(", .{}))");
        } else {
            try self.emit("(runtime.floatBuiltinCall(");
            try self.genExpr(args[0]);
            try self.emit(", .{}) catch 0.0)");
        }
        return;
    }

    // For strings, use runtime.parseFloatWithUnicode (handles Unicode digits)
    if (arg_type == .string) {
        if (self.inside_try_body) {
            try self.emit("(try runtime.parseFloatWithUnicode(");
            try self.genExpr(args[0]);
            try self.emit("))");
        } else {
            try self.emit("(runtime.parseFloatWithUnicode(");
            try self.genExpr(args[0]);
            try self.emit(") catch 0.0)");
        }
        return;
    }

    // Generic fallback for unknown types - use runtime.floatBuiltinCall which handles all types
    if (self.inside_try_body) {
        try self.emit("(try runtime.floatBuiltinCall(");
        try self.genExpr(args[0]);
        try self.emit(", .{}))");
    } else {
        try self.emit("(runtime.floatBuiltinCall(");
        try self.genExpr(args[0]);
        try self.emit(", .{}) catch 0.0)");
    }
}
