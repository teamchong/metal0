/// Integer conversion builtins: int(), len(), bool()
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../../main.zig").CodegenError;
const NativeCodegen = @import("../../main.zig").NativeCodegen;

/// Check if an expression produces a Zig block expression that can't be subscripted/accessed directly
fn producesBlockExpression(expr: ast.Node) bool {
    return switch (expr) {
        .subscript => true,
        .list => true,
        .dict => true,
        .set => true,
        .listcomp => true,
        .dictcomp => true,
        .genexp => true,
        .if_expr => true,
        .call => true,
        else => false,
    };
}

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
    // __len__ returns PythonError!i64, so we need to unwrap with try
    if (has_magic_method and args[0] == .name) {
        try self.emit("(try ");
        try self.genExpr(args[0]);
        try self.emit(".__len__())");
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

    // Check if the type is unknown (PyObject*) - needs runtime dispatch
    const is_pyobject = switch (arg_type) {
        .unknown => true,
        else => false,
    };

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
    try self.emit("@as(i64, @intCast(");

    // Wrap block expressions in temp variable with unique label
    const len_label_id = self.block_label_counter;
    if (needs_wrap) {
        self.block_label_counter += 1;
        try self.emitFmt("len_{d}: {{ const __obj = ", .{len_label_id});
        try self.genExpr(args[0]);
        try self.emitFmt("; break :len_{d} ", .{len_label_id});
    }

    if (is_pyobject) {
        // Unknown type - check if it's an ArrayList (has .items) at compile time
        // Must check .@"struct" first since @hasField only works on struct types
        if (needs_wrap) {
            try self.emit("if (@typeInfo(@TypeOf(__obj)) == .@\"struct\" and @hasField(@TypeOf(__obj), \"items\")) __obj.items.len else runtime.pyLen(__obj)");
        } else {
            const pyobj_label_id = self.block_label_counter;
            self.block_label_counter += 1;
            try self.emitFmt("len_{d}: {{ const __tmp = ", .{pyobj_label_id});
            try self.genExpr(args[0]);
            try self.emitFmt("; break :len_{d} if (@typeInfo(@TypeOf(__tmp)) == .@\"struct\" and @hasField(@TypeOf(__tmp), \"items\")) __tmp.items.len else runtime.pyLen(__tmp); }}", .{pyobj_label_id});
        }
    } else if (is_kwarg_param) {
        // **kwargs is a *runtime.PyObject (PyDict), use runtime.PyDict.len()
        if (needs_wrap) {
            try self.emit("runtime.PyDict.len(__obj)");
        } else {
            try self.emit("runtime.PyDict.len(");
            try self.genExpr(args[0]);
            try self.emit(")");
        }
    } else if (is_arraylist or is_deque) {
        // ArrayList and deque both use .items.len
        if (needs_wrap) {
            try self.emit("__obj.items.len");
        } else {
            try self.genExpr(args[0]);
            try self.emit(".items.len");
        }
    } else if (is_tuple) {
        if (needs_wrap) {
            try self.emit("@typeInfo(@TypeOf(__obj)).@\"struct\".fields.len");
        } else {
            try self.emit("@typeInfo(@TypeOf(");
            try self.genExpr(args[0]);
            try self.emit(")).@\"struct\".fields.len");
        }
    } else if (is_dict or is_set or is_counter) {
        if (needs_wrap) {
            try self.emit("__obj.count()");
        } else {
            try self.genExpr(args[0]);
            try self.emit(".count()");
        }
    } else if (is_class_instance) {
        // User-defined class with __len__ method
        // __len__ returns PythonError!i64, so we need to unwrap with try
        if (needs_wrap) {
            try self.emit("(try __obj.__len__())");
        } else {
            try self.emit("(try ");
            try self.genExpr(args[0]);
            try self.emit(".__len__())");
        }
    } else {
        // For arrays, slices, strings - just use .len
        if (needs_wrap) {
            try self.emit("__obj.len");
        } else {
            try self.genExpr(args[0]);
            try self.emit(".len");
        }
    }

    if (needs_wrap) {
        try self.emitFmt("; }}", .{});
    }
    try self.emit("))");
}

/// Generate code for int(obj) or int(string, base)
/// Converts to i64
pub fn genInt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // int() with no args returns 0
        try self.emit("@as(i64, 0)");
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
            try self.emit("runtime.builtins.intWithBase(__global_allocator, ");
            try self.genExpr(args[0]);
            try self.emit(", ");
            try self.genExpr(args[1]);
            try self.emit(")");
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
            try self.emit("runtime.parseIntUnicode(");
            try self.genExpr(args[0]);
            try self.emit(", @intCast(");
            if (base_is_indexable_class) {
                try self.genExpr(args[1]);
                try self.emit(".__index__()");
            } else {
                try self.genExpr(args[1]);
            }
            try self.emit("))");
        } else {
            // Cast to i64 for normal integers (using @as for explicit type)
            try self.emit("@as(i64, @intCast(try runtime.parseIntUnicode(");
            try self.genExpr(args[0]);
            try self.emit(", @intCast(");
            if (base_is_indexable_class) {
                // For class with __index__, create instance and call __index__()
                try self.genExpr(args[1]);
                try self.emit(".__index__()");
            } else {
                try self.genExpr(args[1]);
            }
            try self.emit("))))");
        }
        return;
    }

    if (args.len != 1) {
        // More than 2 args - not valid, emit error
        try self.emit("@compileError(\"int() takes at most 2 arguments\")");
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
    if (arg_type == .int) {
        try self.genExpr(args[0]);
        return;
    }

    // Parse string to int
    if (arg_type == .string) {
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
                // Use BigInt for large numbers
                try self.emitFmt("(try runtime.bigint.parseBigIntUnicode({s}, ", .{alloc_name});
                try self.genExpr(args[0]);
                try self.emit(", 10))");
                return;
            }
            // Small literal - use i64
            if (self.in_assert_raises_context) {
                try self.emit("runtime.parseIntUnicode(");
                try self.genExpr(args[0]);
                try self.emit(", 10)");
            } else {
                try self.emit("@as(i64, @intCast(try runtime.parseIntUnicode(");
                try self.genExpr(args[0]);
                try self.emit(", 10)))");
            }
            return;
        }

        // Runtime string (variable, subscript, etc.) - use BigInt for Python compatibility
        // since we can't know at compile time if the value will overflow i64
        // Always use 'try' to allow error propagation for try/except blocks
        try self.emitFmt("(try runtime.bigint.parseBigIntUnicode({s}, ", .{alloc_name});
        try self.genExpr(args[0]);
        try self.emit(", 10))");
        return;
    }

    // Cast float to int
    if (arg_type == .float) {
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
                // Value exceeds i128 range - use BigInt
                const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";
                try self.emitFmt("(runtime.BigInt.fromFloat({s}, ", .{alloc_name});
                try self.genExpr(args[0]);
                try self.emit(") catch unreachable)");
                return;
            }
            const max_i64: f64 = 9223372036854775807.0; // 2^63 - 1
            if (@abs(float_val) > max_i64) {
                // Use i128 for values between i64 and i128 range
                try self.emit("@as(i128, @intFromFloat(");
                try self.genExpr(args[0]);
                try self.emit("))");
                return;
            }
        }
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

    // For unknown types, use runtime.toInt which handles strings and numbers
    // This handles cases where type inference couldn't determine the type
    // (e.g., variables captured by anytype in try/except helper structs)
    // toInt returns !i64 so we need try (unless in assertRaises context)
    if (!self.in_assert_raises_context) {
        try self.emit("try ");
    }
    try self.emit("runtime.toInt(");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate code for bool(obj)
/// Converts to bool
/// Python truthiness rules: 0, "", [], {} are False, everything else is True
pub fn genBool(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // bool() with no args returns False
    if (args.len == 0) {
        try self.emit("false");
        return;
    }

    if (args.len != 1) {
        return;
    }

    // Use runtime.toBool for proper Python truthiness semantics
    // Handles: integers, floats, bools, strings, slices, etc.
    try self.emit("runtime.toBool(");
    try self.genExpr(args[0]);
    try self.emit(")");
}
