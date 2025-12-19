/// String and bytes conversion builtins: str(), bytes(), bytearray(), memoryview(), repr()
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const type_traits = @import("../../../../analysis/traits/type_traits.zig");
const string_traits = @import("../../../../analysis/traits/string_traits.zig");
const container_traits = @import("../../../../analysis/traits/container_traits.zig");
const expr_emitter = @import("../../expr_emitter.zig");

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
// Helper for formatted output
fn emitFmtConst(self: *NativeCodegen, comptime fmt: []const u8, args: anytype) CodegenError!void {
    const b = try self.getBuilder();
    try b.writeFmt(fmt, args);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}


/// Generate code for str(obj) or str(bytes, encoding)
/// Converts to string representation
pub fn genStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // str() with no args returns empty string
        try emitConst(self,"\"\"");
        return;
    }

    // str(bytes, encoding) - decode bytes to string
    // In Zig, bytes are already []const u8, so just return the bytes
    // Encoding argument is ignored (UTF-8 is the only encoding we support)
    if (args.len >= 2) {
        try self.genExpr(args[0]);
        return;
    }

    // Use scoped type inference for accuracy
    // Trust type inference - it handles typed parameters correctly (e.g., task_id: int)
    // Only fall back to unknown for genuinely untyped expressions
    const arg_type = self.inferExprScoped(args[0]) catch .unknown;

    // Already a string - just return it
    if (string_traits.isString(arg_type)) {
        try self.genExpr(args[0]);
        return;
    }

    // Convert number to string
    // Use scope-aware allocator: __global_allocator in functions, allocator in main()
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

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

    var em = self.exprEmitter();
    const str_label_id = em.reserveLabelId();

    if (arg_type == .bigint) {
        // BigInt needs special formatting via toDecimalString
        try emitFmtConst(self, "str_{d}: {{\n", .{str_label_id});
        try emitFmtConst(self, "break :str_{d} (", .{str_label_id});
        try self.genExpr(args[0]);
        try emitFmtConst(self, ").toDecimalString({s}) catch unreachable;\n}}", .{alloc_name});
        return;
    } else if (type_traits.isIntegral(arg_type)) {
        // FAST PATH: Use stack buffer for int->str conversion (common in hot loops)
        // Stack buffer: i64 max is 19 digits + sign + null = 21 bytes, use 32 for safety
        try emitFmtConst(self, "str_{d}: {{\n", .{str_label_id});
        try emitFmtConst(self, "var __str_stack_{d}: [32]u8 = undefined;\n", .{str_label_id});
        try emitFmtConst(self, "break :str_{d} std.fmt.bufPrint(&__str_stack_{d}, \"{{}}\", .{{", .{ str_label_id, str_label_id });
        try self.genExpr(args[0]);
        try emitConst(self,"}) catch unreachable;\n}");
        return;
    } else if (type_traits.isFloating(arg_type) and !is_float_error_union) {
        // Use runtime formatFloat which handles NaN/Inf properly (Python: str(nan) == "nan" not "-nan")
        try emitConst(self,"(try runtime.formatFloat(");
        try self.genExpr(args[0]);
        try emitFmtConst(self, ", {s}))", .{alloc_name});
        return;
    } else if (type_traits.isBoolean(arg_type)) {
        // Python bool to string: True/False - no allocation needed!
        try emitConst(self,"(if (");
        try self.genExpr(args[0]);
        try emitConst(self,") \"True\" else \"False\")");
        return;
    } else if (container_traits.isTuple(arg_type)) {
        // For tuples: use Python-style (a, b, c) format
        try emitConst(self,"(try runtime.builtins.tupleRepr(");
        try emitConst(self,alloc_name);
        try emitConst(self,", ");
        try self.genExpr(args[0]);
        try emitConst(self,"))");
        return;
    }

    // Check if the object is a class instance with __str__ or __repr__ magic method
    // Python protocol: str(x) calls x.__str__() if defined, else x.__repr__()
    const DunderInfo = struct { has_str: bool, has_repr: bool };
    const dunder_info: DunderInfo = blk: {
        if (args[0] == .name) {
            const var_name = args[0].name.id;
            if (self.getVarType(var_name)) |var_type| {
                if (type_traits.isClassInstance(var_type)) {
                    const class_name = var_type.class_instance;
                    break :blk .{
                        .has_str = self.classHasMethod(class_name, "__str__"),
                        .has_repr = self.classHasMethod(class_name, "__repr__"),
                    };
                }
            }
        }
        break :blk .{ .has_str = false, .has_repr = false };
    };

    // If class has __str__, generate direct method call
    if (dunder_info.has_str and args[0] == .name) {
        if (self.inside_try_body and !self.in_assert_raises_context) {
            // In try block (not assertRaises) - propagate errors with try
            try emitConst(self,"(try ");
            try self.genExpr(args[0]);
            try emitConst(self,".__str__())");
        } else if (self.in_assert_raises_context) {
            // In assertRaises - return error union as-is for expectError()
            try emitConst(self,"(");
            try self.genExpr(args[0]);
            try emitConst(self,".__str__())");
        } else {
            try emitConst(self,"(");
            try self.genExpr(args[0]);
            try emitConst(self,".__str__() catch \"\")");
        }
        return;
    }

    // If class has __repr__ but not __str__, use __repr__
    if (dunder_info.has_repr and args[0] == .name) {
        if (self.inside_try_body and !self.in_assert_raises_context) {
            // In try block (not assertRaises) - propagate errors with try
            try emitConst(self,"(try ");
            try self.genExpr(args[0]);
            try emitConst(self,".__repr__())");
        } else if (self.in_assert_raises_context) {
            // In assertRaises - return error union as-is for expectError()
            try emitConst(self,"(");
            try self.genExpr(args[0]);
            try emitConst(self,".__repr__())");
        } else {
            try emitConst(self,"(");
            try self.genExpr(args[0]);
            try emitConst(self,".__repr__() catch \"\")");
        }
        return;
    }

    // Check if this might be a C API PyObject (subscript on unknown type, function return, etc.)
    // Note: PyValue is NOT PyObject - it's our tagged union for uncertain types
    const is_c_pyobject = blk: {
        if (type_traits.isUnknown(arg_type)) {
            // Subscript on unknown type is likely a PyList/PyDict access from C API
            if (args[0] == .subscript) break :blk true;
            // Call returning unknown might be a PyObject from C API
            if (args[0] == .call) break :blk true;
        }
        break :blk false;
    };

    if (is_c_pyobject) {
        // Use runtime.pyObjToStr for C API PyObject types
        try emitFmtConst(self, "(try runtime.pyObjToStr({s}, ", .{alloc_name});
        try self.genExpr(args[0]);
        try emitConst(self,"))");
    } else {
        // For unknown types: use pyStr which handles tuples/structs with Python formatting
        try emitConst(self,"(try runtime.builtins.pyStr(");
        try emitConst(self,alloc_name);
        try emitConst(self,", ");
        try self.genExpr(args[0]);
        try emitConst(self,"))");
    }
}

/// Generate code for bytes(obj) or bytes(str, encoding)
/// Converts to bytes ([]const u8 in Zig)
pub fn genBytes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // bytes() with no args returns empty bytes
        try emitConst(self,"\"\"");
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
    if (string_traits.isString(arg_type)) {
        try self.genExpr(args[0]);
        return;
    }

    // For integers, create bytes of that length filled with zeros
    if (type_traits.isIntegral(arg_type)) {
        // bytes(n) creates a bytes object of n null bytes
        const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
        var em = self.exprEmitter();
        const bytes_label_id = em.reserveLabelId();
        try emitFmtConst(self, "bytes_{d}: {{\n", .{bytes_label_id});
        try emitFmtConst(self, "const _len: usize = @intCast(", .{});
        try self.genExpr(args[0]);
        try emitConst(self,");\n");
        try emitFmtConst(self, "const _buf = try {s}.alloc(u8, _len);\n", .{alloc_name});
        try emitConst(self,"@memset(_buf, 0);\n");
        try emitFmtConst(self, "break :bytes_{d} _buf;\n", .{bytes_label_id});
        try emitConst(self,"}");
        return;
    }

    // Two-Flow: For unknown/PyValue types, use runtime bytes conversion
    // bytes() doesn't need allocator - just converts value to bytes representation
    if (type_traits.isUnknown(arg_type) or arg_type == .pyvalue) {
        try emitConst(self,"runtime.builtins.bytes(");
        try self.genExpr(args[0]);
        try emitConst(self,")");
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
        try emitConst(self,"\"\"");
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
    if (string_traits.isString(arg_type)) {
        try self.genExpr(args[0]);
        return;
    }

    // For integers, create bytearray of that length filled with zeros
    if (type_traits.isIntegral(arg_type)) {
        // bytearray(n) creates a bytearray of n null bytes
        const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
        var em = self.exprEmitter();
        const bytearray_label_id = em.reserveLabelId();
        try emitFmtConst(self, "bytearray_{d}: {{\n", .{bytearray_label_id});
        try emitFmtConst(self, "const _len: usize = @intCast(", .{});
        try self.genExpr(args[0]);
        try emitConst(self,");\n");
        try emitFmtConst(self, "const _buf = {s}.alloc(u8, _len) catch unreachable;\n", .{alloc_name});
        try emitConst(self,"@memset(_buf, 0);\n");
        try emitFmtConst(self, "break :bytearray_{d} _buf;\n", .{bytearray_label_id});
        try emitConst(self,"}");
        return;
    }

    // Two-Flow: For unknown/PyValue types, use runtime bytearray conversion
    if (type_traits.isUnknown(arg_type) or arg_type == .pyvalue) {
        const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
        try emitConst(self,"(try runtime.builtins.bytearray(");
        try emitConst(self,alloc_name);
        try emitConst(self,", ");
        try self.genExpr(args[0]);
        try emitConst(self,"))");
        return;
    }

    // For lists/iterables, convert to bytearray
    try self.genExpr(args[0]);
}

/// Generate code for memoryview(obj)
/// memoryview provides a view into a buffer - in Zig, treated as []const u8
pub fn genMemoryview(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self,"\"\"");
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
    if (string_traits.isString(arg_type)) {
        var em = self.exprEmitter();
        const repr_label_id = em.reserveLabelId();
        try emitFmtConst(self, "repr_{d}: {{\n", .{repr_label_id});
        try emitFmtConst(self, "var __repr_buf_{d} = std.ArrayList(u8){{}};\n", .{repr_label_id});
        try emitFmtConst(self, "try __repr_buf_{d}.appendSlice({s}, \"'\");\n", .{ repr_label_id, alloc_name });
        try emitFmtConst(self, "try __repr_buf_{d}.appendSlice({s}, ", .{ repr_label_id, alloc_name });
        try self.genExpr(args[0]);
        try emitConst(self,");\n");
        try emitFmtConst(self, "try __repr_buf_{d}.appendSlice({s}, \"'\");\n", .{ repr_label_id, alloc_name });
        try emitFmtConst(self, "break :repr_{d} try __repr_buf_{d}.toOwnedSlice({s});\n", .{ repr_label_id, repr_label_id, alloc_name });
        try emitConst(self,"}");
        return;
    }

    // For bools: True/False
    if (type_traits.isBoolean(arg_type)) {
        try emitConst(self,"(if (");
        try self.genExpr(args[0]);
        try emitConst(self,") \"True\" else \"False\")");
        return;
    }

    // For tuples: use Python-style (a, b, c) format
    if (container_traits.isTuple(arg_type)) {
        try emitConst(self,"(try runtime.builtins.tupleRepr(");
        try emitConst(self,alloc_name);
        try emitConst(self,", ");
        try self.genExpr(args[0]);
        try emitConst(self,"))");
        return;
    }

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

    // For integers, use pyRepr which handles anytype params correctly
    // (closures generate anytype parameters whose actual type may differ from inference)
    if (type_traits.isIntegral(arg_type)) {
        try emitConst(self,"(try runtime.builtins.pyRepr(");
        try emitConst(self,alloc_name);
        try emitConst(self,", ");
        try self.genExpr(args[0]);
        try emitConst(self,"))");
        return;
    }

    // For floats, use runtime.builtins.pyRepr which handles nan/inf correctly
    if (type_traits.isFloating(arg_type) and !is_float_error_union) {
        try emitConst(self,"(try runtime.builtins.pyRepr(");
        try emitConst(self,alloc_name);
        try emitConst(self,", ");
        try self.genExpr(args[0]);
        try emitConst(self,"))");
        return;
    }

    // For bigint, use toDecimalString method
    if (arg_type == .bigint) {
        var em = self.exprEmitter();
        const repr_num_label_id = em.reserveLabelId();
        try emitFmtConst(self, "repr_num_{d}: {{\n", .{repr_num_label_id});
        try emitFmtConst(self, "var __repr_num_buf_{d} = std.ArrayListUnmanaged(u8){{}};\n", .{repr_num_label_id});
        try emitFmtConst(self, "try __repr_num_buf_{d}.appendSlice({s}, try (", .{ repr_num_label_id, alloc_name });
        try self.genExpr(args[0]);
        try emitFmtConst(self, ").toDecimalString({s}));\n", .{alloc_name});
        try emitFmtConst(self, "break :repr_num_{d} try __repr_num_buf_{d}.toOwnedSlice({s});\n", .{ repr_num_label_id, repr_num_label_id, alloc_name });
        try emitConst(self,"}");
        return;
    }

    // For unknown types: use pyRepr which handles tuples/structs with Python formatting
    try emitConst(self,"(try runtime.builtins.pyRepr(");
    try emitConst(self,alloc_name);
    try emitConst(self,", ");
    try self.genExpr(args[0]);
    try emitConst(self,"))");
}

/// Generate code for ascii(obj)
/// Returns a string containing a printable representation of an object,
/// but escape non-ASCII characters using \x, \u, or \U escapes
pub fn genAscii(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self,"\"\"");
        return;
    }

    // Get the repr and escape non-ASCII
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Two-Flow: Check for uncertain types first
    if (type_traits.isUnknown(arg_type) or arg_type == .pyvalue) {
        // Use runtime ascii for uncertain types
        try emitConst(self,"runtime.asciiRepr(");
        try self.genExpr(args[0]);
        try emitConst(self,")");
        return;
    }

    if (string_traits.isString(arg_type)) {
        // For strings, wrap in quotes and escape non-ASCII
        try emitConst(self,"runtime.asciiStr(");
        try self.genExpr(args[0]);
        try emitConst(self,")");
    } else {
        // For other types, get repr first
        try emitConst(self,"runtime.asciiRepr(");
        try self.genExpr(args[0]);
        try emitConst(self,")");
    }
}

/// Generate code for format(value, format_spec)
/// Returns value.__format__(format_spec)
pub fn genFormat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try emitConst(self,"\"\"");
        return;
    }

    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    // Two-Flow: Check if value is uncertain
    const arg_type = self.inferExprScoped(args[0]) catch .unknown;
    const is_uncertain = type_traits.isUnknown(arg_type) or arg_type == .pyvalue;

    if (args.len == 1) {
        // format(value) - use default format spec
        if (is_uncertain) {
            // For uncertain types, use runtime format
            try emitConst(self,"(try runtime.pyFormat(");
            try emitConst(self,alloc_name);
            try emitConst(self,", ");
            try self.genExpr(args[0]);
            try emitConst(self,", \"\"))");
        } else {
            try emitConst(self,"std.fmt.allocPrint(");
            try emitConst(self,alloc_name);
            try emitConst(self,", \"{any}\", .{");
            try self.genExpr(args[0]);
            try emitConst(self,"}) catch \"\"");
        }
    } else {
        // format(value, format_spec)
        // Use runtime.pyFormat for proper Python format handling
        try emitConst(self,"(try runtime.pyFormat(");
        try emitConst(self,alloc_name);
        try emitConst(self,", ");
        try self.genExpr(args[0]);
        try emitConst(self,", ");
        try self.genExpr(args[1]);
        try emitConst(self,"))");
    }
}
