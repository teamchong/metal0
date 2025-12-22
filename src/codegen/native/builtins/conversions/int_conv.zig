/// Integer conversion builtins: int(), len(), bool()
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const producesBlockExpression = @import("../../expressions.zig").producesBlockExpression;
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


/// Generate code for len(obj)
/// Works with: strings, lists, dicts, tuples
pub fn genLen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try emitConst(self,"(blk_len: { @panic(\"len() requires exactly 1 argument\"); })");
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
    // __len__ returns PythonError!i64, so we need to unwrap with try
    if (has_magic_method and args[0] == .name) {
        try emitConst(self,"(try ");
        try self.genExpr(args[0]);
        try emitConst(self,".__len__())");
        return;
    }

    // Check if argument is dict or tuple
    // For variable names, check local scope first to avoid type shadowing from other methods
    const arg_type = blk: {
        if (args[0] == .name) {
            if (self.getVarType(args[0].name.id)) |local_type| {
                break :blk local_type;
            }
        }
        break :blk self.type_inferrer.inferExpr(args[0]) catch .unknown;
    };

    const is_dict = container_traits.isDict(arg_type);
    const is_set = container_traits.isSet(arg_type);
    const is_tuple = container_traits.isTuple(arg_type);
    const is_deque = switch (arg_type) {
        .deque => true,
        else => false,
    };
    const is_counter = switch (arg_type) {
        .counter => true,
        else => false,
    };
    const is_class_instance = switch (arg_type) {
        .class_instance => true,
        else => false,
    };
    const is_slice = switch (arg_type) {
        .slice => true,
        else => false,
    };

    // Check if this is a tracked ArrayList variable (must check BEFORE dict/set type check)
    // Dict comprehensions generate ArrayList but are typed as .dict
    // Note: Skip if type is .slice - slice variables use .len, not .items.len
    const is_arraylist = blk: {
        if (is_slice) break :blk false; // Slices are not ArrayLists
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

    // Check if the type is unknown or PyValue - needs runtime dispatch
    // TWO-FLOW: Both .unknown and .pyvalue types need runtime handling
    const is_pyobject = type_traits.isUnknown(arg_type) or arg_type == .pyvalue;

    // Check if the argument is a block expression that needs wrapping
    const needs_wrap = producesBlockExpression(args[0]);

    // Generate:
    // - runtime.pyLen(obj) for unknown/PyObject* types
    // - runtime.PyDict.len(obj) for **kwargs parameters
    // - obj.items.len for ArrayList (including dict comprehensions)
    // - obj.count() for HashMap/dict/set
    // - @typeInfo(...).fields.len for tuples
    // - obj.len for slices/arrays/strings
    // All results are cast to i64 since Python len() returns int
    try emitConst(self,"@as(i64, @intCast(");

    // Wrap block expressions in temp variable with unique label
    var em = self.exprEmitter();
    const len_label_id = em.peekLabelId();
    if (needs_wrap) {
        _ = em.reserveLabelId();
        try emitFmtConst(self, "len_{d}: {{ const __obj = ", .{len_label_id});
        try self.genExpr(args[0]);
        try emitFmtConst(self, "; break :len_{d} ", .{len_label_id});
    }

    if (is_pyobject) {
        // Unknown type - use runtime.builtinLen which handles all cases
        // (simpler than inlining comptime type checks everywhere)
        if (needs_wrap) {
            try emitConst(self,"runtime.builtinLen(__obj)");
        } else {
            try emitConst(self,"runtime.builtinLen(");
            try self.genExpr(args[0]);
            try emitConst(self,")");
        }
    } else if (is_kwarg_param) {
        // **kwargs is a *runtime.PyObject (PyDict), use runtime.PyDict.len()
        if (needs_wrap) {
            try emitConst(self,"runtime.PyDict.len(__obj)");
        } else {
            try emitConst(self,"runtime.PyDict.len(");
            try self.genExpr(args[0]);
            try emitConst(self,")");
        }
    } else if (is_arraylist or is_deque) {
        // ArrayList and deque both use .items.len
        if (needs_wrap) {
            try emitConst(self,"__obj.items.len");
        } else {
            try self.genExpr(args[0]);
            try emitConst(self,".items.len");
        }
    } else if (is_tuple) {
        if (needs_wrap) {
            try emitConst(self,"@typeInfo(@TypeOf(__obj)).@\"struct\".fields.len");
        } else {
            try emitConst(self,"@typeInfo(@TypeOf(");
            try self.genExpr(args[0]);
            try emitConst(self,")).@\"struct\".fields.len");
        }
    } else if (is_dict or is_set or is_counter) {
        if (needs_wrap) {
            try emitConst(self,"__obj.count()");
        } else {
            try self.genExpr(args[0]);
            try emitConst(self,".count()");
        }
    } else if (is_class_instance) {
        // Check if this is array.array (inline struct with non-error __len__)
        const is_python_array = std.mem.eql(u8, arg_type.class_instance, "array.array");
        if (is_python_array) {
            // array.array inline struct has __len__ returning usize (not error union)
            if (needs_wrap) {
                try emitConst(self,"__obj.__len__()");
            } else {
                try self.genExpr(args[0]);
                try emitConst(self,".__len__()");
            }
        } else {
            // User-defined class with __len__ method
            // __len__ returns PythonError!i64, so we need to unwrap with try
            if (needs_wrap) {
                try emitConst(self,"(try __obj.__len__())");
            } else {
                try emitConst(self,"(try ");
                try self.genExpr(args[0]);
                try emitConst(self,".__len__())");
            }
        }
    } else {
        // For arrays, slices, strings - use builtins.len which handles all types
        // including ArrayLists and pointers to ArrayLists
        if (needs_wrap) {
            try emitConst(self,"runtime.builtinLen(__obj)");
        } else {
            try emitConst(self,"runtime.builtinLen(");
            try self.genExpr(args[0]);
            try emitConst(self,")");
        }
    }

    if (needs_wrap) {
        try emitFmtConst(self, "; }}", .{});
    }
    try emitConst(self,"))");
}

/// Generate code for int(obj) or int(string, base)
/// Converts to i64
pub fn genInt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // int() with no args returns 0
        try emitConst(self,"@as(i64, 0)");
        return;
    }

    // Handle int(string, base) - two argument form
    // Use i128 to handle large integers like sys.maxsize + 1
    if (args.len == 2) {
        // Check if base is a negative constant, float, class call, or potentially out of range - use runtime check
        const base_needs_runtime_check = blk: {
            // Negative literal (e.g., int('0', -909))
            if (args[1] == .unaryop and args[1].unaryop.op == .USub) break :blk true;
            // Subtraction that could go negative (e.g., int('0', 0 - 2**234))
            if (args[1] == .binop and args[1].binop.op == .Sub) break :blk true;
            // Very large positive (e.g., int('0', 2**234))
            if (args[1] == .binop and args[1].binop.op == .Pow) break :blk true;
            // Large left shift (e.g., int('0', 1 << 100))
            if (args[1] == .binop and args[1].binop.op == .LShift) break :blk true;
            // Float literal (e.g., int('0', 5.5)) - TypeError
            if (args[1] == .constant and args[1].constant.value == .float) break :blk true;
            // Class call with __index__ (e.g., int('101', MyIndexable(2))) - needs __index__ call
            if (args[1] == .call) {
                if (args[1].call.keyword_args.len > 0) {
                    // Call with keyword args like base=MyIndexable(2)
                    break :blk true;
                }
                // Any function call that might return an __index__ object
                if (args[1].call.func.* == .name) {
                    // Check if it's a known class (starts with uppercase or is a user class)
                    const fn_name = args[1].call.func.name.id;
                    if (fn_name.len > 0 and fn_name[0] >= 'A' and fn_name[0] <= 'Z') {
                        break :blk true;
                    }
                }
            }
            // Check if base is inferred as BigInt (e.g., from a loop variable)
            // Use inferExprScoped to correctly handle for loop variables
            const base_type = self.inferExprScoped(args[1]) catch .unknown;
            if (base_type == .bigint) break :blk true;
            // If base is just a variable name (from loop, etc.) and we're in assertRaises,
            // use runtime check since it could be any type at runtime
            if (args[1] == .name) break :blk true;
            break :blk false;
        };

        if (base_needs_runtime_check and self.in_assert_raises_context) {
            // In assertRaises with potentially invalid base - use runtime validation
            // Must use 'try' since intWithBase returns error union and we're in an error-returning context
            try emitConst(self,"(try runtime.builtins.intWithBase(__global_allocator, ");
            try self.genExpr(args[0]);
            try emitConst(self,", ");
            try self.genExpr(args[1]);
            try emitConst(self,"))");
            return;
        }

        // Check if base is a class call that needs __index__
        const base_is_indexable_class = blk: {
            if (args[1] == .call and args[1].call.func.* == .name) {
                const fn_name = args[1].call.func.name.id;
                if (fn_name.len > 0 and fn_name[0] >= 'A' and fn_name[0] <= 'Z') {
                    break :blk true;
                }
            }
            break :blk false;
        };

        // In assertRaises context, don't emit 'try' or type casts - the outer catch will handle errors
        // Use runtime.parseIntUnicode to handle Unicode whitespace (like Python's int())
        if (self.in_assert_raises_context) {
            // Return raw error union for assertRaises to catch
            try emitConst(self,"runtime.parseIntUnicode(");
            try self.genExpr(args[0]);
            try emitConst(self,", @intCast(");
            if (base_is_indexable_class) {
                try self.genExpr(args[1]);
                try emitConst(self,".__index__()");
            } else {
                try self.genExpr(args[1]);
            }
            try emitConst(self,"))");
        } else {
            // Cast to i64 for normal integers (using @as for explicit type)
            try emitConst(self,"@as(i64, @intCast(try runtime.parseIntUnicode(");
            try self.genExpr(args[0]);
            try emitConst(self,", @intCast(");
            if (base_is_indexable_class) {
                // For class with __index__, create instance and call __index__()
                // __index__() returns !i64, so we need try to unwrap
                try emitConst(self,"(try ");
                try self.genExpr(args[1]);
                try emitConst(self,".__index__())");
            } else {
                try self.genExpr(args[1]);
            }
            try emitConst(self,"))))");
        }
        return;
    }

    if (args.len != 1) {
        // More than 2 args - not valid, emit error
        try emitConst(self,"(blk_int: { @panic(\"int() takes at most 2 arguments\"); })");
        return;
    }

    // Infer type, with fallback to local scope lookup for better accuracy
    var arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // If type is unknown but arg is a name, try local scope lookup
    // This helps with variables declared inside inline for loops
    if (arg_type == .unknown and args[0] == .name) {
        if (self.getVarType(args[0].name.id)) |local_type| {
            arg_type = local_type;
        }
    }

    // Already an int - just return it
    if (type_traits.isIntegral(arg_type)) {
        try self.genExpr(args[0]);
        return;
    }

    // Parse string to int
    if (string_traits.isString(arg_type)) {
        const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

        // Check if this is a literal string
        if (args[0] == .constant and args[0].constant.value == .string) {
            const str_val = args[0].constant.value.string;

            // Check if string might produce a number >= 19 digits
            // For Unicode digits, each digit can be multi-byte (up to 4 bytes)
            // A 19-digit number needs at least 19 bytes
            // If string has >=19 bytes, use BigInt to be safe (handles Unicode digits)
            const needs_bigint = str_val.len >= 19;

            if (needs_bigint) {
                // Use UnifiedInt for large numbers - auto-demotes to i64 if it fits
                try emitFmtConst(self, "(try runtime.UnifiedInt.parseUnicode({s}, ", .{alloc_name});
                try self.genExpr(args[0]);
                try emitConst(self,", 10))");
                return;
            }
            // Small literal - use i64
            if (self.in_assert_raises_context) {
                try emitConst(self,"runtime.parseIntUnicode(");
                try self.genExpr(args[0]);
                try emitConst(self,", 10)");
            } else {
                try emitConst(self,"@as(i64, @intCast(try runtime.parseIntUnicode(");
                try self.genExpr(args[0]);
                try emitConst(self,", 10)))");
            }
            return;
        }

        // Runtime string (variable, subscript, etc.) - use UnifiedInt for Python compatibility
        // since we can't know at compile time if the value will overflow i64
        // UnifiedInt.parseUnicode auto-demotes to i64 if value fits
        // Always use 'try' to allow error propagation for try/except blocks
        try emitFmtConst(self, "(try runtime.UnifiedInt.parseUnicode({s}, ", .{alloc_name});
        try self.genExpr(args[0]);
        try emitConst(self,", 10))");
        return;
    }

    // Cast float to int
    if (type_traits.isFloating(arg_type)) {
        // Extract float value from literal or negated literal
        const maybe_float_val: ?f64 = blk: {
            if (args[0] == .constant and args[0].constant.value == .float) {
                break :blk args[0].constant.value.float;
            }
            // Handle -1e100 which is unary minus on float literal
            if (args[0] == .unaryop) {
                const uop = args[0].unaryop;
                if (uop.op == .USub and uop.operand.* == .constant and uop.operand.*.constant.value == .float) {
                    break :blk -uop.operand.*.constant.value.float;
                }
            }
            break :blk null;
        };

        if (maybe_float_val) |float_val| {
            const max_i128: f64 = 170141183460469231731687303715884105727.0; // 2^127 - 1
            const min_i128: f64 = -170141183460469231731687303715884105728.0; // -2^127
            if (float_val > max_i128 or float_val < min_i128) {
                // Value exceeds i128 range - use UnifiedInt.fromFloat (auto-demotes to i64 if fits)
                const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
                try emitFmtConst(self, "(try runtime.UnifiedInt.fromFloat({s}, ", .{alloc_name});
                try self.genExpr(args[0]);
                try emitConst(self,"))");
                return;
            }
            const max_i64: f64 = 9223372036854775807.0; // 2^63 - 1
            if (@abs(float_val) > max_i64) {
                // Use i128 for values between i64 and i128 range
                try emitConst(self,"@as(i128, @intFromFloat(");
                try self.genExpr(args[0]);
                try emitConst(self,"))");
                return;
            }
        }
        // For runtime float values, use toIntBig which handles overflow to BigInt
        // Call .asI64() to extract i64, throws OverflowError for BigInt values
        const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
        try emitFmtConst(self, "(try (try runtime.toIntBig({s}, ", .{alloc_name});
        try self.genExpr(args[0]);
        try emitConst(self,")).asI64())");
        return;
    }

    // Cast bool to int (True -> 1, False -> 0)
    if (type_traits.isBoolean(arg_type)) {
        try emitConst(self,"@as(i64, @intFromBool(");
        try self.genExpr(args[0]);
        try emitConst(self,"))");
        return;
    }

    // Check if the object is a class instance with __int__ or __index__ magic method
    // Python protocol: int(x) calls x.__int__() if defined, else x.__index__()
    const DunderInfo = struct { has_int: bool, has_index: bool };
    const dunder_info: DunderInfo = blk: {
        if (args[0] == .name) {
            const var_name = args[0].name.id;
            if (self.getVarType(var_name)) |var_type| {
                if (type_traits.isClassInstance(var_type)) {
                    const class_name = var_type.class_instance;
                    break :blk .{
                        .has_int = self.classHasMethod(class_name, "__int__"),
                        .has_index = self.classHasMethod(class_name, "__index__"),
                    };
                }
            }
        }
        break :blk .{ .has_int = false, .has_index = false };
    };

    // If class has __int__, generate direct method call
    if (dunder_info.has_int and args[0] == .name) {
        // In try block (but not assertRaises): propagate error with try
        // In assertRaises context: return error union for expectError() to check
        // Otherwise: catch and return 0
        if (self.inside_try_body and !self.in_assert_raises_context) {
            try emitConst(self,"(try ");
            try self.genExpr(args[0]);
            try emitConst(self,".__int__())");
        } else if (self.in_assert_raises_context) {
            // Return error union as-is - statement-level expectError() will handle it
            try emitConst(self,"(");
            try self.genExpr(args[0]);
            try emitConst(self,".__int__())");
        } else {
            try emitConst(self,"(");
            try self.genExpr(args[0]);
            try emitConst(self,".__int__() catch 0)");
        }
        return;
    }

    // If class has __index__ but not __int__, use __index__
    if (dunder_info.has_index and args[0] == .name) {
        if (self.inside_try_body and !self.in_assert_raises_context) {
            try emitConst(self,"(try ");
            try self.genExpr(args[0]);
            try emitConst(self,".__index__())");
        } else if (self.in_assert_raises_context) {
            // Return error union as-is - statement-level expectError() will handle it
            try emitConst(self,"(");
            try self.genExpr(args[0]);
            try emitConst(self,".__index__())");
        } else {
            try emitConst(self,"(");
            try self.genExpr(args[0]);
            try emitConst(self,".__index__() catch 0)");
        }
        return;
    }

    // For unknown types, use runtime.toIntBig which handles strings, numbers, and overflow to BigInt
    // This handles cases where type inference couldn't determine the type
    // (e.g., variables captured by anytype in try/except helper structs, attribute access, PyValue)
    // toIntBig returns !IntResult which safely handles large floats
    // We call .asI64() to extract i64, which throws OverflowError for BigInt values
    const alloc_name_unknown = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
    try emitFmtConst(self, "(try (try runtime.toIntBig({s}, ", .{alloc_name_unknown});
    try self.genExpr(args[0]);
    try emitConst(self,")).asI64())");
}

/// Generate code for hex(x) - convert int to hex string prefixed with "0x"
/// Two-Flow: Extract int from PyValue for uncertain types
pub fn genHex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try emitConst(self,"(blk_hex: { @panic(\"hex() takes exactly one argument\"); })");
        return;
    }
    // Two-Flow: Check if argument is uncertain (PyValue)
    const arg_type = self.inferExprScoped(args[0]) catch .unknown;
    if (type_traits.isUnknown(arg_type) or arg_type == .pyvalue) {
        // Extract int from PyValue using asInt()
        try emitConst(self,"runtime.builtins.hex(__global_allocator, (");
        try self.genExpr(args[0]);
        try emitConst(self,").asInt())");
    } else {
        try emitConst(self,"runtime.builtins.hex(__global_allocator, ");
        try self.genExpr(args[0]);
        try emitConst(self,")");
    }
}

/// Generate code for oct(x) - convert int to octal string prefixed with "0o"
/// Two-Flow: Extract int from PyValue for uncertain types
pub fn genOct(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try emitConst(self,"(blk_oct: { @panic(\"oct() takes exactly one argument\"); })");
        return;
    }
    // Two-Flow: Check if argument is uncertain (PyValue)
    const arg_type = self.inferExprScoped(args[0]) catch .unknown;
    if (type_traits.isUnknown(arg_type) or arg_type == .pyvalue) {
        // Extract int from PyValue using asInt()
        try emitConst(self,"runtime.builtins.oct(__global_allocator, (");
        try self.genExpr(args[0]);
        try emitConst(self,").asInt())");
    } else {
        try emitConst(self,"runtime.builtins.oct(__global_allocator, ");
        try self.genExpr(args[0]);
        try emitConst(self,")");
    }
}

/// Generate code for bin(x) - convert int to binary string prefixed with "0b"
/// Two-Flow: Extract int from PyValue for uncertain types
pub fn genBin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try emitConst(self,"(blk_bin: { @panic(\"bin() takes exactly one argument\"); })");
        return;
    }
    // Two-Flow: Check if argument is uncertain (PyValue)
    const arg_type = self.inferExprScoped(args[0]) catch .unknown;
    if (type_traits.isUnknown(arg_type) or arg_type == .pyvalue) {
        // Extract int from PyValue using asInt()
        try emitConst(self,"runtime.builtins.bin(__global_allocator, (");
        try self.genExpr(args[0]);
        try emitConst(self,").asInt())");
    } else {
        try emitConst(self,"runtime.builtins.bin(__global_allocator, ");
        try self.genExpr(args[0]);
        try emitConst(self,")");
    }
}

/// Generate code for bool(obj)
/// Converts to bool
/// Python truthiness rules: 0, "", [], {} are False, everything else is True
/// NOTE: For simple types (int, float, string, list, array), use runtime.toBool
/// which doesn't return an error. For complex types that might have __bool__,
/// use boolBuiltinCall which returns PythonError!bool.
///
/// Python protocol for bool(x):
/// 1. If x has __bool__, call it (must return bool)
/// 2. Else if x has __len__, return len(x) != 0
/// 3. Else return True (objects are truthy by default)
pub fn genBool(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // bool() with no args returns False
    if (args.len == 0) {
        try emitConst(self,"false");
        return;
    }

    // Check if we have extra args - need error handling for TypeError
    if (args.len > 1) {
        try emitConst(self,"(try runtime.boolBuiltinCall(");
        try self.genExpr(args[0]);
        try emitConst(self,", .{");
        for (args[1..], 0..) |arg, i| {
            if (i > 0) try emitConst(self,", ");
            try self.genExpr(arg);
        }
        try emitConst(self,"}))");
        return;
    }

    // Single argument - check type to decide which function to use
    const arg_type = self.inferExprScoped(args[0]) catch .unknown;
    const arg_tag = @as(std.meta.Tag(@TypeOf(arg_type)), arg_type);

    // Simple types can use runtime.toBool (no error)
    const is_simple = switch (arg_tag) {
        .bool, .int, .float, .string, .list, .array, .tuple, .bytes => true,
        else => false,
    };

    if (is_simple) {
        // Use runtime.toBool for simple types - no error propagation needed
        try emitConst(self,"runtime.toBool(");
        try self.genExpr(args[0]);
        try emitConst(self,")");
        return;
    }

    // Check if the object is a class instance with __bool__ or __len__ magic method
    const DunderInfo = struct { has_bool: bool, has_len: bool };
    const dunder_info: DunderInfo = blk: {
        if (args[0] == .name) {
            const var_name = args[0].name.id;
            // Check if this variable's type is a class instance
            if (self.getVarType(var_name)) |var_type| {
                if (type_traits.isClassInstance(var_type)) {
                    const class_name = var_type.class_instance;
                    break :blk .{
                        .has_bool = self.classHasMethod(class_name, "__bool__"),
                        .has_len = self.classHasMethod(class_name, "__len__"),
                    };
                }
            }
        }
        break :blk .{ .has_bool = false, .has_len = false };
    };

    // If class has __bool__, generate direct method call
    if (dunder_info.has_bool and args[0] == .name) {
        // __bool__ must return bool, may raise TypeError
        if (self.inside_try_body) {
            try emitConst(self,"(try ");
            try self.genExpr(args[0]);
            try emitConst(self,".__bool__())");
        } else {
            try emitConst(self,"(");
            try self.genExpr(args[0]);
            try emitConst(self,".__bool__() catch false)");
        }
        return;
    }

    // If class has __len__ but not __bool__, use len != 0
    if (dunder_info.has_len and args[0] == .name) {
        if (self.inside_try_body) {
            try emitConst(self,"((try ");
            try self.genExpr(args[0]);
            try emitConst(self,".__len__()) != 0)");
        } else {
            try emitConst(self,"((");
            try self.genExpr(args[0]);
            try emitConst(self,".__len__() catch 0) != 0)");
        }
        return;
    }

    // Fall back to boolBuiltinCall for unknown types (runtime dispatch)
    // This handles PyValue and other dynamic types
    try emitConst(self,"(try runtime.boolBuiltinCall(");
    try self.genExpr(args[0]);
    try emitConst(self,", .{}))");
}
