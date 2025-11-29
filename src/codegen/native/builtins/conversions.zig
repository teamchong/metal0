/// Type conversion builtins: len(), str(), int(), float(), bool()
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("../main.zig").CodegenError;
const NativeCodegen = @import("../main.zig").NativeCodegen;

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
    if (has_magic_method and args[0] == .name) {
        try self.genExpr(args[0]);
        try self.emit(".__len__()");
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

    // Wrap block expressions in temp variable
    if (needs_wrap) {
        try self.emit("blk: { const __obj = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk ");
    }

    if (is_pyobject) {
        // Unknown type (PyObject*) - use runtime.pyLen for dynamic dispatch
        if (needs_wrap) {
            try self.emit("runtime.pyLen(__obj)");
        } else {
            try self.emit("runtime.pyLen(");
            try self.genExpr(args[0]);
            try self.emit(")");
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
    } else if (is_arraylist) {
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
    } else if (is_dict or is_set) {
        if (needs_wrap) {
            try self.emit("__obj.count()");
        } else {
            try self.genExpr(args[0]);
            try self.emit(".count()");
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
        try self.emit("; }");
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
    // Use scope-aware allocator: __global_allocator in functions, allocator in main()
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    try self.emit("blk: {\n");
    try self.emit("var buf = std.ArrayList(u8){};\n");

    if (arg_type == .int) {
        try self.emitFmt("try buf.writer({s}).print(\"{{}}\", .{{", .{alloc_name});
    } else if (arg_type == .float) {
        try self.emitFmt("try buf.writer({s}).print(\"{{d}}\", .{{", .{alloc_name});
    } else if (arg_type == .bool) {
        // Python bool to string: True/False
        try self.emitFmt("try buf.writer({s}).print(\"{{s}}\", .{{if (", .{alloc_name});
        try self.genExpr(args[0]);
        try self.emit(") \"True\" else \"False\"});\n");
        try self.emitFmt("break :blk try buf.toOwnedSlice({s});\n", .{alloc_name});
        try self.emit("}");
        return;
    } else {
        try self.emitFmt("try buf.writer({s}).print(\"{{any}}\", .{{", .{alloc_name});
    }

    try self.genExpr(args[0]);
    try self.emit("});\n");
    try self.emitFmt("break :blk try buf.toOwnedSlice({s});\n", .{alloc_name});
    try self.emit("}");
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
    if (args.len == 2) {
        try self.emit("try std.fmt.parseInt(i64, ");
        try self.genExpr(args[0]);
        try self.emit(", @intCast(");
        try self.genExpr(args[1]);
        try self.emit("))");
        return;
    }

    if (args.len != 1) {
        // More than 2 args - not valid, emit error
        try self.emit("@compileError(\"int() takes at most 2 arguments\")");
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

    // Generic cast for unknown types - need explicit result type
    try self.emit("@as(i64, @intCast(");
    try self.genExpr(args[0]);
    try self.emit("))");
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

/// Generate code for list(iterable)
/// Converts an iterable to a list (ArrayList)
pub fn genList(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    // list() with no args returns empty list
    // Default to i64 element type since it's the most common case
    if (args.len == 0) {
        try self.emit("std.ArrayList(i64){}");
        return;
    }

    if (args.len != 1) return;

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Already an ArrayList - just return it
    switch (arg_type) {
        .list => {
            try self.genExpr(args[0]);
            return;
        },
        else => {},
    }

    // Handle generator expressions specially - they already generate ArrayList
    // So list(gen_expr) is just the generator expression itself
    if (args[0] == .genexp) {
        // Generator expression already returns an ArrayList, just use it directly
        try self.genExpr(args[0]);
        return;
    }

    // Handle list comprehensions similarly - they also generate ArrayList
    if (args[0] == .listcomp) {
        try self.genExpr(args[0]);
        return;
    }

    // Convert iterable to ArrayList
    // Assign iterable to intermediate variable first to avoid issues with block expressions
    // (Zig doesn't allow subscripting block expressions directly)
    try self.emit("list_blk: {\n");
    try self.emit("const _iterable = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emit("var _list = std.ArrayList(@TypeOf(_iterable[0])){};\n");
    try self.emit("for (_iterable) |_item| {\n");
    try self.emitFmt("try _list.append({s}, _item);\n", .{alloc_name});
    try self.emit("}\n");
    try self.emit("break :list_blk _list;\n");
    try self.emit("}");
}

/// Generate code for tuple(iterable)
/// Converts an iterable to a tuple (fixed-size)
pub fn genTuple(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // tuple() with no args returns empty tuple
    if (args.len == 0) {
        try self.emit(".{}");
        return;
    }

    if (args.len != 1) return;

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Already a tuple - just return it
    switch (arg_type) {
        .tuple => {
            try self.genExpr(args[0]);
            return;
        },
        else => {},
    }

    // For other iterables, generate inline tuple
    // This is limited since Zig tuples need comptime-known size
    try self.genExpr(args[0]);
}

/// Generate code for dict(iterable)
/// Converts key-value pairs to a dict (StringHashMap)
pub fn genDict(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // dict() with no args returns empty dict
    // Default to i64 value type since it's common (keys are strings)
    if (args.len == 0) {
        try self.emit("std.StringHashMap(i64){}");
        return;
    }

    if (args.len != 1) return;

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Already a dict - just return it
    switch (arg_type) {
        .dict => {
            try self.genExpr(args[0]);
            return;
        },
        else => {},
    }

    // For other cases, just pass through
    try self.genExpr(args[0]);
}

/// Generate code for set(iterable)
/// Converts an iterable to a set (AutoHashMap with void values)
pub fn genSet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const alloc_name = if (self.symbol_table.currentScopeLevel() > 0) "__global_allocator" else "allocator";

    // set() with no args returns empty set
    // Default to i64 key type since it's the most common case
    if (args.len == 0) {
        try self.emit("std.AutoHashMap(i64, void){}");
        return;
    }

    if (args.len != 1) return;

    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    // Already a set - just return it
    switch (arg_type) {
        .set => {
            try self.genExpr(args[0]);
            return;
        },
        else => {},
    }

    // Convert iterable to set
    // Check if arg produces a block expression that needs to be stored in temp variable
    const needs_temp = producesBlockExpression(args[0]);

    try self.emit("set_blk: {\n");

    if (needs_temp) {
        // Store block expression in temp variable first
        try self.emit("const __iterable = ");
        try self.genExpr(args[0]);
        try self.emit(";\n");
        try self.emit("var _set = std.AutoHashMap(@TypeOf(__iterable[0]), void){};\n");
        try self.emit("for (__iterable) |_item| {\n");
    } else {
        try self.emitFmt("var _set = std.AutoHashMap(@TypeOf(", .{});
        try self.genExpr(args[0]);
        try self.emit("[0]), void){};\n");
        try self.emit("for (");
        try self.genExpr(args[0]);
        try self.emit(") |_item| {\n");
    }
    try self.emitFmt("try _set.put({s}, _item, {{}});\n", .{alloc_name});
    try self.emit("}\n");
    try self.emit("break :set_blk _set;\n");
    try self.emit("}");
}

/// Generate code for frozenset(iterable)
/// Same as set() but conceptually immutable
pub fn genFrozenset(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // frozenset is the same implementation as set in AOT context
    try genSet(self, args);
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

    if (arg_type == .int) {
        try self.emitFmt("try buf.writer({s}).print(\"{{}}\", .{{", .{alloc_name});
    } else if (arg_type == .float) {
        try self.emitFmt("try buf.writer({s}).print(\"{{d}}\", .{{", .{alloc_name});
    } else {
        try self.emitFmt("try buf.writer({s}).print(\"{{any}}\", .{{", .{alloc_name});
    }

    try self.genExpr(args[0]);
    try self.emit("});\n");
    try self.emitFmt("break :blk try buf.toOwnedSlice({s});\n", .{alloc_name});
    try self.emit("}");
}

/// Generate code for callable(obj)
/// Returns True if obj appears to be callable
pub fn genCallable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("false");
        return;
    }

    // At compile time, we can check if something is a function type
    // For now, emit a runtime check or true for known callable types
    const arg_type = self.type_inferrer.inferExpr(args[0]) catch .unknown;

    switch (arg_type) {
        .function => {
            try self.emit("true");
        },
        .unknown => {
            // Runtime check - use @typeInfo
            try self.emit("runtime.isCallable(");
            try self.genExpr(args[0]);
            try self.emit(")");
        },
        else => {
            // Check if it's a class (has __call__)
            if (args[0] == .name) {
                if (self.classHasMethod(args[0].name.id, "__call__")) {
                    try self.emit("true");
                    return;
                }
            }
            // Most types are not callable
            try self.emit("false");
        },
    }
}

/// Generate code for issubclass(cls, classinfo)
/// Returns True if cls is a subclass of classinfo
pub fn genIssubclass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("false");
        return;
    }

    // For static types, we can sometimes determine at compile time
    // For runtime, we need to check type hierarchy

    // Handle common cases: issubclass(bool, int) -> true
    if (args[0] == .name and args[1] == .name) {
        const cls_name = args[0].name.id;
        const base_name = args[1].name.id;

        // Built-in type hierarchy
        if (std.mem.eql(u8, cls_name, "bool") and std.mem.eql(u8, base_name, "int")) {
            try self.emit("true");
            return;
        }
        if (std.mem.eql(u8, cls_name, base_name)) {
            try self.emit("true");
            return;
        }
    }

    // Runtime check
    try self.emit("runtime.isSubclass(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate code for complex(real, imag)
/// Creates a complex number
pub fn genComplex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // complex() with no args returns 0j
        try self.emit("runtime.PyComplex.create(0.0, 0.0)");
        return;
    }

    if (args.len == 1) {
        // complex(x) - x can be a number or string
        try self.emit("runtime.PyComplex.fromValue(");
        try self.genExpr(args[0]);
        try self.emit(")");
        return;
    }

    // complex(real, imag)
    try self.emit("runtime.PyComplex.create(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate code for object()
/// Creates a unique base object instance (used as sentinel values)
/// Each call creates a new unique instance by returning a struct with unique identity
pub fn genObject(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Generate a unique object using a struct that has unique identity per call
    // In Python, object() returns a base object that can be used as a sentinel
    // We use runtime.createObject() which returns a unique *PyObject
    try self.emit("runtime.createObject()");
}
