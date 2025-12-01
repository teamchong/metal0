/// String and bytes conversion builtins: str(), bytes(), bytearray(), memoryview(), repr()
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;

/// Check if an expression contains a simple name (likely a parameter that could be anytype)
/// We use this heuristic: if the expression is a simple name or involves a simple name in
/// a unary/binary op, treat it as potentially anytype
fn expressionContainsAnytypeParam(expr: ast.Node) bool {
    switch (expr) {
        .name => return true, // A simple name could be anytype parameter
        .unaryop => |u| return expressionContainsAnytypeParam(u.operand.*),
        .binop => |b| return expressionContainsAnytypeParam(b.left.*) or
            expressionContainsAnytypeParam(b.right.*),
        else => return false,
    }
}

/// Generate code for str(obj) or str(bytes, encoding)
/// Converts to string representation
pub fn genStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // str() with no args returns empty string
        try self.emit("\"\"");
        return;
    }

    // str(bytes, encoding) - decode bytes to string
    // In Zig, bytes are already []const u8, so just return the bytes
    // But we need to "use" the encoding arg to avoid unused variable errors
    if (args.len >= 2) {
        // str(bytes, "ascii") or str(bytes, "utf-8") etc.
        // If encoding is a variable, we need to "use" it to avoid unused variable errors
        // Generate: dec_N: { _ = encoding; break :dec_N bytes; }
        if (args[1] == .name) {
            const label = self.block_label_counter;
            self.block_label_counter += 1;
            try self.output.writer(self.allocator).print("dec_{d}: {{ _ = ", .{label});
            try self.genExpr(args[1]); // Generate the encoding variable reference
            try self.output.writer(self.allocator).print("; break :dec_{d} ", .{label});
            try self.genExpr(args[0]);
            try self.emit("; }");
        } else {
            // Encoding is a constant - just return the bytes
            try self.genExpr(args[0]);
        }
        return;
    }

    // Use scoped type inference for accuracy with anytype parameters
    var arg_type = self.inferExprScoped(args[0]) catch .unknown;

    // Check if expression contains an anytype parameter reference (e.g., -n where n: anytype)
    // In this case, use .unknown to generate safe runtime-polymorphic code
    if (expressionContainsAnytypeParam(args[0])) {
        arg_type = .unknown;
    }

    // Already a string - just return it
    if (arg_type == .string) {
        try self.genExpr(args[0]);
        return;
    }

    // Convert number to string
    // Use scope-aware allocator: __global_allocator in functions, allocator in main()
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    const str_label_id = self.block_label_counter;
    self.block_label_counter += 1;
    try self.emitFmt("str_{d}: {{\n", .{str_label_id});
    try self.emit("var buf = std.ArrayList(u8){};\n");

    // Check if this is a float() call that might return error union
    // float(string_var) generates runtime.floatBuiltinCall which returns !f64
    const is_float_error_union = if (args[0] == .call) blk: {
        const call = args[0].call;
        if (call.func.* == .name and std.mem.eql(u8, call.func.name.id, "float")) {
            // Check if the argument to float() is not already a float
            if (call.args.len > 0) {
                const inner_arg_type = self.type_inferrer.inferExpr(call.args[0]) catch .unknown;
                break :blk inner_arg_type != .float;
            }
        }
        break :blk false;
    } else false;

    if (arg_type == .bigint) {
        // BigInt needs special formatting via toDecimalString
        try self.emitFmt("break :str_{d} (", .{str_label_id});
        try self.genExpr(args[0]);
        try self.emitFmt(").toDecimalString({s}) catch unreachable;\n}}", .{alloc_name});
        return;
    } else if (arg_type == .int) {
        try self.emitFmt("try buf.writer({s}).print(\"{{}}\", .{{", .{alloc_name});
    } else if (arg_type == .float and !is_float_error_union) {
        try self.emitFmt("try buf.writer({s}).print(\"{{d}}\", .{{", .{alloc_name});
    } else if (arg_type == .bool) {
        // Python bool to string: True/False
        try self.emitFmt("try buf.writer({s}).print(\"{{s}}\", .{{if (", .{alloc_name});
        try self.genExpr(args[0]);
        try self.emit(") \"True\" else \"False\"});\n");
        try self.emitFmt("break :str_{d} try buf.toOwnedSlice({s});\n", .{ str_label_id, alloc_name });
        try self.emit("}");
        return;
    } else if (arg_type == .unknown) {
        // Unknown type (e.g., anytype parameter) - use {any} with comptime type handling
        try self.emitFmt("try buf.writer({s}).print(\"{{any}}\", .{{", .{alloc_name});
    } else {
        try self.emitFmt("try buf.writer({s}).print(\"{{any}}\", .{{", .{alloc_name});
    }

    try self.genExpr(args[0]);
    try self.emit("});\n");
    try self.emitFmt("break :str_{d} try buf.toOwnedSlice({s});\n", .{ str_label_id, alloc_name });
    try self.emit("}");
}

/// Generate code for bytes(obj) or bytes(str, encoding)
/// Converts to bytes ([]const u8 in Zig)
pub fn genBytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // bytes() with no args returns empty bytes
        try self.emit("\"\"");
        return;
    }

    // bytes(str, encoding) - encode string to bytes
    // In Zig, strings are already []const u8, so just return the string
    if (args.len >= 2) {
        try self.genExpr(args[0]);
        return;
    }

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Already a string/bytes - just return it
    if (arg_type == .string) {
        try self.genExpr(args[0]);
        return;
    }

    // For integers, create bytes of that length filled with zeros
    if (arg_type == .int) {
        // bytes(n) creates a bytes object of n null bytes
        const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
        try self.emit("blk: {\n");
        try self.emitFmt("const _len: usize = @intCast(", .{});
        try self.genExpr(args[0]);
        try self.emit(");\n");
        try self.emitFmt("const _buf = try {s}.alloc(u8, _len);\n", .{alloc_name});
        try self.emit("@memset(_buf, 0);\n");
        try self.emit("break :blk _buf;\n");
        try self.emit("}");
        return;
    }

    // For lists/iterables, convert to bytes
    try self.genExpr(args[0]);
}

/// Generate code for bytearray(obj) or bytearray(str, encoding)
/// bytearray is a mutable sequence of bytes - in Zig, same as []u8
pub fn genBytearray(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // bytearray() with no args returns empty byte array
        try self.emit("\"\"");
        return;
    }

    // bytearray(str, encoding) - encode string to bytes
    // In Zig, strings are already []const u8, so just return the string
    if (args.len >= 2) {
        try self.genExpr(args[0]);
        return;
    }

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Already a string/bytes - just return it
    if (arg_type == .string) {
        try self.genExpr(args[0]);
        return;
    }

    // For integers, create bytearray of that length filled with zeros
    if (arg_type == .int) {
        // bytearray(n) creates a bytearray of n null bytes
        const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
        try self.emit("blk: {\n");
        try self.emitFmt("const _len: usize = @intCast(", .{});
        try self.genExpr(args[0]);
        try self.emit(");\n");
        try self.emitFmt("const _buf = {s}.alloc(u8, _len) catch unreachable;\n", .{alloc_name});
        try self.emit("@memset(_buf, 0);\n");
        try self.emit("break :blk _buf;\n");
        try self.emit("}");
        return;
    }

    // For lists/iterables, convert to bytearray
    try self.genExpr(args[0]);
}

/// Generate code for memoryview(obj)
/// memoryview provides a view into a buffer - in Zig, treated as []const u8
pub fn genMemoryview(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"\"");
        return;
    }

    // memoryview(bytes) - just return the bytes/buffer
    // In Zig, this is essentially a no-op since slices are already views
    try self.genExpr(args[0]);
}

/// Generate code for repr(obj)
/// Returns string representation with quotes for strings
/// repr(True) -> "True", repr("hello") -> "'hello'"
pub fn genRepr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        return;
    }

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Use scope-aware allocator: __global_allocator in functions, allocator in main()
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    // For strings, wrap with quotes: "'string'"
    if (arg_type == .string) {
        try self.emit("blk: {\n");
        try self.emit("var buf = std.ArrayList(u8){};\n");
        try self.emitFmt("try buf.appendSlice({s}, \"'\");\n", .{alloc_name});
        try self.emitFmt("try buf.appendSlice({s}, ", .{alloc_name});
        try self.genExpr(args[0]);
        try self.emit(");\n");
        try self.emitFmt("try buf.appendSlice({s}, \"'\");\n", .{alloc_name});
        try self.emitFmt("break :blk try buf.toOwnedSlice({s});\n", .{alloc_name});
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

    // Check if this is a float() call that might return error union
    // float(string_var) generates runtime.floatBuiltinCall which returns !f64
    const is_float_error_union = if (args[0] == .call) blk: {
        const call = args[0].call;
        if (call.func.* == .name and std.mem.eql(u8, call.func.name.id, "float")) {
            // Check if the argument to float() is not already a float
            if (call.args.len > 0) {
                const inner_arg_type = self.type_inferrer.inferExpr(call.args[0]) catch .unknown;
                break :blk inner_arg_type != .float;
            }
        }
        break :blk false;
    } else false;

    if (arg_type == .int) {
        try self.emitFmt("try buf.writer({s}).print(\"{{}}\", .{{", .{alloc_name});
    } else if (arg_type == .float and !is_float_error_union) {
        try self.emitFmt("try buf.writer({s}).print(\"{{d}}\", .{{", .{alloc_name});
    } else {
        // Use {any} for error unions and unknown types
        try self.emitFmt("try buf.writer({s}).print(\"{{any}}\", .{{", .{alloc_name});
    }

    try self.genExpr(args[0]);
    try self.emit("});\n");
    try self.emitFmt("break :blk try buf.toOwnedSlice({s});\n", .{alloc_name});
    try self.emit("}");
}

/// Generate code for ascii(obj)
/// Returns a string containing a printable representation of an object,
/// but escape non-ASCII characters using \x, \u, or \U escapes
pub fn genAscii(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"\"");
        return;
    }

    // Get the repr and escape non-ASCII
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    if (arg_type == .string) {
        // For strings, wrap in quotes and escape non-ASCII
        try self.emit("runtime.asciiStr(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        // For other types, get repr first
        try self.emit("runtime.asciiRepr(");
        try self.genExpr(args[0]);
        try self.emit(")");
    }
}

/// Generate code for format(value, format_spec)
/// Returns value.__format__(format_spec)
pub fn genFormat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("\"\"");
        return;
    }

    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    if (args.len == 1) {
        // format(value) - use default format spec
        try self.emit("std.fmt.allocPrint(");
        try self.emit(alloc_name);
        try self.emit(", \"{any}\", .{");
        try self.genExpr(args[0]);
        try self.emit("}) catch \"\"");
    } else {
        // format(value, format_spec)
        // Use runtime.pyFormat for proper Python format handling
        try self.emit("runtime.pyFormat(");
        try self.emit(alloc_name);
        try self.emit(", ");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(")");
    }
}
