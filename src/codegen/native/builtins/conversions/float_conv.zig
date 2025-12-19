/// Float conversion builtins: float()
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const string_traits = @import("../../../../analysis/traits/string_traits.zig");
const builder_mod = @import("codegen.builder");

/// Generate the error handling suffix for failable float operations.
/// Inside try blocks, use "try" to propagate errors to handlers.
/// Otherwise, use "catch 0.0" to silently handle errors.
fn emitFloatErrorHandling(self: *NativeCodegen, expr_start: []const u8, expr_end: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    if (self.inside_try_body) {
        // Inside try block - propagate errors up
        try b.write("(try ");
        try b.write(expr_start);
        try b.write(expr_end);
        try b.write(")");
    } else {
        // Outside try block - catch and return default
        try b.write("(");
        try b.write(expr_start);
        try b.write(expr_end);
        try b.write(" catch 0.0)");
    }
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
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
        const b = try self.getBuilder();
        try b.write("@as(f64, 0.0)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    if (args.len != 1) {
        const b = try self.getBuilder();
        try b.write("@as(f64, 0.0)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }

    var arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // For variable names, also check local var types (from for-loop, assignment, etc.)
    // which may have more accurate scoped type info
    if (args[0] == .name) {
        const var_name = args[0].name.id;
        if (self.getVarType(var_name)) |local_type| {
            // Prefer local type if it's more specific (not int/unknown)
            if (string_traits.isString(local_type) or type_traits.isClassInstance(local_type)) {
                arg_type = local_type;
            }
        }
    }

    // Already a float - just return it
    if (type_traits.isFloating(arg_type)) {
        try self.genExpr(args[0]);
        return;
    }

    // Parse string to float
    if (string_traits.isString(arg_type)) {
        // Check for special float literals that can be used at module level without try
        if (args[0] == .constant and args[0].constant.value == .string) {
            const str_val = args[0].constant.value.string;
            // Handle special float values (inf, nan, etc.) case-insensitively
            if (getSpecialFloatLiteral(str_val)) |zig_const| {
                const b = try self.getBuilder();
                try b.write(zig_const);
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
                return;
            }
            // Try to parse as a numeric literal at comptime
            // Strip leading + for Zig compatibility (Zig doesn't accept "+123")
            const parse_str = if (str_val.len > 0 and str_val[0] == '+') str_val[1..] else str_val;
            if (std.fmt.parseFloat(f64, parse_str)) |_| {
                const b = try self.getBuilder();
                try b.write("@as(f64, ");
                try b.write(parse_str);
                try b.write(")");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
                return;
            } else |_| {}
        }
        // For non-literal strings, use runtime float parsing (handles Unicode digits)
        if (self.inside_try_body) {
            // Use parseFloatStr which sets proper error message for except handlers
            {
                const b = try self.getBuilder();
                try b.write("(try runtime.parseFloatStr(");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
            try self.genExpr(args[0]);
            {
                const b = try self.getBuilder();
                try b.write("))");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
        } else {
            {
                const b = try self.getBuilder();
                try b.write("(runtime.parseFloatWithUnicode(");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
            try self.genExpr(args[0]);
            {
                const b = try self.getBuilder();
                try b.write(") catch 0.0)");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
        }
        return;
    }

    // Cast int to float
    // BUT only if we're confident it's an int (not a variable that might be bytes/string)
    if (type_traits.isIntegral(arg_type)) {
        // If this is a variable, be cautious - type inference may be wrong for loop vars
        // Use runtime fallback instead which handles all types
        if (args[0] == .name) {
            if (self.inside_try_body) {
                {
                    const b = try self.getBuilder();
                    try b.write("(try runtime.floatBuiltinCall(");
                    const output = b.getBodyAndClear();
                    try self.output.appendSlice(self.allocator, output);
                }
                try self.genExpr(args[0]);
                {
                    const b = try self.getBuilder();
                    try b.write(", .{}))");
                    const output = b.getBodyAndClear();
                    try self.output.appendSlice(self.allocator, output);
                }
            } else {
                {
                    const b = try self.getBuilder();
                    try b.write("(runtime.floatBuiltinCall(");
                    const output = b.getBodyAndClear();
                    try self.output.appendSlice(self.allocator, output);
                }
                try self.genExpr(args[0]);
                {
                    const b = try self.getBuilder();
                    try b.write(", .{}) catch 0.0)");
                    const output = b.getBodyAndClear();
                    try self.output.appendSlice(self.allocator, output);
                }
            }
            return;
        }
        {
            const b = try self.getBuilder();
            try b.write("@as(f64, @floatFromInt(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write("))");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        return;
    }

    // Cast bool to float (True -> 1.0, False -> 0.0)
    if (type_traits.isBoolean(arg_type)) {
        {
            const b = try self.getBuilder();
            try b.write("@as(f64, @floatFromInt(@intFromBool(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(")))");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        return;
    }

    // Check if the object is a class instance with __float__ magic method
    const has_magic_method = blk: {
        if (args[0] == .name) {
            const var_name = args[0].name.id;
            // First check if this variable's type is a class instance
            if (self.getVarType(var_name)) |var_type| {
                if (type_traits.isClassInstance(var_type)) {
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
            {
                const b = try self.getBuilder();
                try b.write("(try runtime.floatBuiltinCall(");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
            try self.genExpr(args[0]);
            {
                const b = try self.getBuilder();
                try b.write(", .{}))");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
        } else {
            {
                const b = try self.getBuilder();
                try b.write("(runtime.floatBuiltinCall(");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
            try self.genExpr(args[0]);
            {
                const b = try self.getBuilder();
                try b.write(", .{}) catch 0.0)");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
        }
        return;
    }

    // For strings, use runtime.parseFloatWithUnicode (handles Unicode digits)
    if (string_traits.isString(arg_type)) {
        if (self.inside_try_body) {
            {
                const b = try self.getBuilder();
                try b.write("(try runtime.parseFloatWithUnicode(");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
            try self.genExpr(args[0]);
            {
                const b = try self.getBuilder();
                try b.write("))");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
        } else {
            {
                const b = try self.getBuilder();
                try b.write("(runtime.parseFloatWithUnicode(");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
            try self.genExpr(args[0]);
            {
                const b = try self.getBuilder();
                try b.write(") catch 0.0)");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
        }
        return;
    }

    // Generic fallback for unknown types - use runtime.floatBuiltinCall which handles all types
    if (self.inside_try_body) {
        {
            const b = try self.getBuilder();
            try b.write("(try runtime.floatBuiltinCall(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(", .{}))");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        {
            const b = try self.getBuilder();
            try b.write("(runtime.floatBuiltinCall(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write(", .{}) catch 0.0)");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    }
}
