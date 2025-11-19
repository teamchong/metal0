const std = @import("std");
const ast = @import("../ast.zig");

/// Check if a list contains only literal values (candidates for array optimization)
fn isConstantList(list: ast.Node.List) bool {
    if (list.elts.len == 0) return false; // Empty lists stay dynamic

    for (list.elts) |elem| {
        // Check if element is a literal constant
        const is_literal = switch (elem) {
            .constant => true,
            else => false,
        };
        if (!is_literal) return false;
    }

    return true;
}

/// Check if all elements in a list have the same type (homogeneous)
fn allSameType(elements: []ast.Node) bool {
    if (elements.len == 0) return true;

    // Get type tag of first element
    const first_const = switch (elements[0]) {
        .constant => |c| c,
        else => return false,
    };

    const first_type_tag = @as(std.meta.Tag(@TypeOf(first_const.value)), first_const.value);

    // Check all other elements match
    for (elements[1..]) |elem| {
        const elem_const = switch (elem) {
            .constant => |c| c,
            else => return false,
        };

        const elem_type_tag = @as(std.meta.Tag(@TypeOf(elem_const.value)), elem_const.value);
        if (elem_type_tag != first_type_tag) return false;
    }

    return true;
}

/// String type kinds for optimization and tracking
pub const StringKind = enum {
    literal, // Compile-time "hello" - can be optimized
    runtime, // Dynamically allocated (from methods, concat, etc.)
    slice,   // []const u8 slice from operations

    /// All string kinds map to []const u8 in Zig
    pub fn toZigType(self: StringKind) []const u8 {
        _ = self;
        return "[]const u8";
    }
};

/// Native Zig types inferred from Python code
pub const NativeType = union(enum) {
    // Primitives - stack allocated, zero overhead
    int: void, // i64
    usize: void, // usize (for array indices)
    float: void, // f64
    bool: void, // bool
    string: StringKind, // []const u8 - tracks allocation/optimization hint

    // Composites
    array: struct {
        element_type: *const NativeType,
        length: usize, // Comptime-known length
    }, // [N]T - fixed-size array
    list: *const NativeType, // ArrayList(T) - dynamic list
    dict: struct {
        key: *const NativeType,
        value: *const NativeType,
    }, // StringHashMap(V)
    tuple: []const NativeType, // Zig tuple struct

    // Functions
    closure: []const u8, // Closure struct name (__Closure_N)
    function: struct {
        params: []const NativeType,
        return_type: *const NativeType,
    }, // Function pointer type: *const fn(T, U) R

    // Library types (DEPRECATED - remove after implementing Python classes properly)
    dataframe: void, // DEPRECATED: pandas.DataFrame - should be generic class type

    // Special
    none: void, // void or ?T
    unknown: void, // Fallback to PyObject* (should be rare)

    /// Convert to Zig type string
    pub fn toZigType(self: NativeType, allocator: std.mem.Allocator, buf: *std.ArrayList(u8)) !void {
        switch (self) {
            .int => try buf.appendSlice(allocator, "i64"),
            .usize => try buf.appendSlice(allocator, "usize"),
            .float => try buf.appendSlice(allocator, "f64"),
            .bool => try buf.appendSlice(allocator, "bool"),
            .string => try buf.appendSlice(allocator, "[]const u8"),
            .array => |arr| {
                const len_str = try std.fmt.allocPrint(allocator, "[{d}]", .{arr.length});
                defer allocator.free(len_str);
                try buf.appendSlice(allocator, len_str);
                try arr.element_type.toZigType(allocator, buf);
            },
            .list => |elem_type| {
                try buf.appendSlice(allocator, "std.ArrayList(");
                try elem_type.toZigType(allocator, buf);
                try buf.appendSlice(allocator, ")");
            },
            .dict => |kv| {
                try buf.appendSlice(allocator, "std.StringHashMap(");
                try kv.value.toZigType(allocator, buf);
                try buf.appendSlice(allocator, ")");
            },
            .tuple => |types| {
                try buf.appendSlice(allocator, "struct { ");
                for (types, 0..) |t, i| {
                    const field_buf = try std.fmt.allocPrint(allocator, "@\"{d}\": ", .{i});
                    defer allocator.free(field_buf);
                    try buf.appendSlice(allocator, field_buf);
                    try t.toZigType(allocator, buf);
                    try buf.appendSlice(allocator, ", ");
                }
                try buf.appendSlice(allocator, "}");
            },
            .closure => |name| try buf.appendSlice(allocator, name),
            .function => |fn_type| {
                try buf.appendSlice(allocator, "*const fn (");
                for (fn_type.params, 0..) |param, i| {
                    if (i > 0) try buf.appendSlice(allocator, ", ");
                    try param.toZigType(allocator, buf);
                }
                try buf.appendSlice(allocator, ") ");
                try fn_type.return_type.toZigType(allocator, buf);
            },
            .dataframe => try buf.appendSlice(allocator, "pandas.DataFrame"),
            .none => try buf.appendSlice(allocator, "void"),
            .unknown => try buf.appendSlice(allocator, "*runtime.PyObject"),
        }
    }

    /// Promote/widen types for compatibility
    /// Follows Python's type promotion hierarchy: int < float < string < unknown
    pub fn widen(self: NativeType, other: NativeType) NativeType {
        // Get tags for comparison
        const self_tag = @as(std.meta.Tag(NativeType), self);
        const other_tag = @as(std.meta.Tag(NativeType), other);

        // If either is unknown, result is unknown (fallback to PyObject)
        if (self_tag == .unknown or other_tag == .unknown) return .unknown;

        // If types match, no widening needed
        if (self_tag == other_tag) {
            return self;
        }

        // String "wins" over everything (str() is universal)
        // When one is string, result is runtime string (most general)
        if (self_tag == .string or other_tag == .string) return .{ .string = .runtime };

        // Float can hold ints, so float "wins"
        if ((self_tag == .float and other_tag == .int) or
            (self_tag == .int and other_tag == .float)) return .float;

        // usize and int mix → promote to int (i64 can represent both)
        if ((self_tag == .usize and other_tag == .int) or
            (self_tag == .int and other_tag == .usize)) return .int;

        // usize and float → promote to float
        if ((self_tag == .usize and other_tag == .float) or
            (self_tag == .float and other_tag == .usize)) return .float;

        // Different incompatible types → fallback to unknown
        return .unknown;
    }
};

/// Error set for type inference
pub const InferError = error{
    OutOfMemory,
};

/// Convert Python type hint string to NativeType
/// For composite types like list, returns a marker that needs allocation
fn pythonTypeHintToNative(type_hint: ?[]const u8, allocator: std.mem.Allocator) InferError!NativeType {
    if (type_hint) |hint| {
        if (std.mem.eql(u8, hint, "int")) return .int;
        if (std.mem.eql(u8, hint, "float")) return .float;
        if (std.mem.eql(u8, hint, "bool")) return .bool;
        if (std.mem.eql(u8, hint, "str")) return .{ .string = .runtime };
        if (std.mem.eql(u8, hint, "list")) {
            // For now, assume list[int] - most common case
            // TODO: Parse generic type hints like list[str], list[float]
            const elem_ptr = try allocator.create(NativeType);
            elem_ptr.* = .int;
            return .{ .list = elem_ptr };
        }
    }
    return .unknown;
}

/// Class field information
pub const ClassInfo = struct {
    fields: std.StringHashMap(NativeType),
};

/// Type inferrer - analyzes AST to determine native Zig types
pub const TypeInferrer = struct {
    allocator: std.mem.Allocator,
    var_types: std.StringHashMap(NativeType),
    class_fields: std.StringHashMap(ClassInfo), // class_name -> field types
    func_return_types: std.StringHashMap(NativeType), // function_name -> return type

    pub fn init(allocator: std.mem.Allocator) InferError!TypeInferrer {
        return TypeInferrer{
            .allocator = allocator,
            .var_types = std.StringHashMap(NativeType).init(allocator),
            .class_fields = std.StringHashMap(ClassInfo).init(allocator),
            .func_return_types = std.StringHashMap(NativeType).init(allocator),
        };
    }

    pub fn deinit(self: *TypeInferrer) void {
        // Free class field maps
        var it = self.class_fields.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.fields.deinit();
        }
        self.class_fields.deinit();
        self.var_types.deinit();
        self.func_return_types.deinit();
    }

    /// Analyze a module to infer all variable types
    pub fn analyze(self: *TypeInferrer, module: ast.Node.Module) InferError!void {
        // Register __name__ as a string constant (for if __name__ == "__main__" support)
        try self.var_types.put("__name__", .{ .string = .literal });

        for (module.body) |stmt| {
            try self.visitStmt(stmt);
        }
    }

    fn visitStmt(self: *TypeInferrer, node: ast.Node) InferError!void {
        switch (node) {
            .assign => |assign| {
                const value_type = try self.inferExpr(assign.value.*);
                for (assign.targets) |target| {
                    if (target == .name) {
                        try self.var_types.put(target.name.id, value_type);
                    }
                }
            },
            .class_def => |class_def| {
                // Track class field types from __init__ parameters
                var fields = std.StringHashMap(NativeType).init(self.allocator);

                // Find __init__ method
                for (class_def.body) |stmt| {
                    if (stmt == .function_def and std.mem.eql(u8, stmt.function_def.name, "__init__")) {
                        const init_fn = stmt.function_def;

                        // Extract field types from __init__ parameters
                        for (init_fn.body) |init_stmt| {
                            if (init_stmt == .assign) {
                                const assign = init_stmt.assign;
                                // Check if target is self.attribute
                                if (assign.targets.len > 0 and assign.targets[0] == .attribute) {
                                    const attr = assign.targets[0].attribute;
                                    if (attr.value.* == .name and std.mem.eql(u8, attr.value.name.id, "self")) {
                                        const field_name = attr.attr;

                                        // Determine field type from parameter type annotation
                                        if (assign.value.* == .name) {
                                            const value_name = assign.value.name.id;
                                            for (init_fn.args) |arg| {
                                                if (std.mem.eql(u8, arg.name, value_name)) {
                                                    const field_type = try pythonTypeHintToNative(arg.type_annotation, self.allocator);
                                                    try fields.put(field_name, field_type);
                                                    break;
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        break;
                    }
                }

                try self.class_fields.put(class_def.name, .{ .fields = fields });
            },
            .if_stmt => |if_stmt| {
                for (if_stmt.body) |s| try self.visitStmt(s);
                for (if_stmt.else_body) |s| try self.visitStmt(s);
            },
            .while_stmt => |while_stmt| {
                for (while_stmt.body) |s| try self.visitStmt(s);
            },
            .for_stmt => |for_stmt| {
                // Register loop variables before visiting body
                // This enables proper type inference for print statements inside loops
                if (for_stmt.target.* == .list) {
                    // Multiple loop vars: for i, item in enumerate(items)
                    // Parser uses .list for tuple unpacking
                    const targets = for_stmt.target.list.elts;

                    // Check for enumerate() pattern
                    if (for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .name) {
                        const func_name = for_stmt.iter.call.func.name.id;

                        if (std.mem.eql(u8, func_name, "enumerate") and targets.len >= 2) {
                            // First var is always usize (index for array access)
                            if (targets[0] == .name) {
                                try self.var_types.put(targets[0].name.id, .usize);
                            }
                            // Second var type comes from the list being enumerated
                            if (targets[1] == .name and for_stmt.iter.call.args.len > 0) {
                                const arg = for_stmt.iter.call.args[0];
                                // Only handle simple cases to avoid side effects
                                if (arg == .name) {
                                        // Get type from variable
                                    const list_type = self.var_types.get(arg.name.id) orelse .unknown;
                                    const elem_type = switch (list_type) {
                                        .list => |l| l.*,
                                        .array => |a| a.element_type.*,
                                        else => .unknown,
                                    };
                                    try self.var_types.put(targets[1].name.id, elem_type);
                                } else if (arg == .list and arg.list.elts.len > 0) {
                                    // Infer from first list element
                                    const first_elem = arg.list.elts[0];
                                    const elem_type = if (first_elem == .constant)
                                        self.inferConstant(first_elem.constant.value) catch .unknown
                                    else .unknown;
                                    try self.var_types.put(targets[1].name.id, elem_type);
                                }
                            }
                        } else if (std.mem.eql(u8, func_name, "zip")) {
                            // zip(list1, list2, ...) - infer from each list
                            for (for_stmt.iter.call.args, 0..) |arg, i| {
                                if (i < targets.len and targets[i] == .name) {
                                    if (arg == .name) {
                                        const list_type = self.var_types.get(arg.name.id) orelse .unknown;
                                        const elem_type = switch (list_type) {
                                            .list => |l| l.*,
                                            .array => |a| a.element_type.*,
                                            else => .unknown,
                                        };
                                        try self.var_types.put(targets[i].name.id, elem_type);
                                    }
                                }
                            }
                        }
                    } else if (for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .attribute) {
                        // Generic tuple unpacking from method calls like dict.items()
                        // for k, v in dict.items(): ...
                        const iter_type = self.inferExpr(for_stmt.iter.*) catch .unknown;

                        // If method returns a list of tuples, unpack the tuple element types
                        if (iter_type == .list) {
                            const elem_type = iter_type.list.*;
                            if (elem_type == .tuple) {
                                // Unpack tuple element types to target variables
                                const tuple_types = elem_type.tuple;
                                for (targets, 0..) |target, i| {
                                    if (target == .name and i < tuple_types.len) {
                                        try self.var_types.put(target.name.id, tuple_types[i]);
                                    }
                                }
                            }
                        }
                    }
                } else if (for_stmt.target.* == .name) {
                    // Single loop var: for item in items or for i in range(...)
                    const target_name = for_stmt.target.name.id;

                    // Check for range() pattern - indices should be usize
                    if (for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .name) {
                        const func_name = for_stmt.iter.call.func.name.id;
                        if (std.mem.eql(u8, func_name, "range")) {
                            // range() produces indices → type as usize
                            try self.var_types.put(target_name, .usize);
                        }
                    } else if (for_stmt.iter.* == .name) {
                        const iter_type = self.var_types.get(for_stmt.iter.name.id) orelse .unknown;
                        const elem_type = switch (iter_type) {
                            .list => |l| l.*,
                            .array => |a| a.element_type.*,
                            else => .unknown,
                        };
                        try self.var_types.put(target_name, elem_type);
                    }
                }

                for (for_stmt.body) |s| try self.visitStmt(s);
            },
            .function_def => |func_def| {
                // Register function parameter types from type annotations
                for (func_def.args) |arg| {
                    const param_type = try pythonTypeHintToNative(arg.type_annotation, self.allocator);
                    try self.var_types.put(arg.name, param_type);
                }
                // Visit function body
                for (func_def.body) |s| try self.visitStmt(s);
            },
            else => {},
        }
    }

    pub fn inferExpr(self: *TypeInferrer, node: ast.Node) InferError!NativeType {
        return switch (node) {
            .constant => |c| self.inferConstant(c.value),
            .name => |n| self.var_types.get(n.id) orelse .unknown,
            .binop => |b| try self.inferBinOp(b),
            .call => |c| try self.inferCall(c),
            .subscript => |s| blk: {
                // Infer subscript type: obj[index] or obj[slice]
                const obj_type = try self.inferExpr(s.value.*);

                switch (s.slice) {
                    .index => |idx| {
                        // Single index access
                        // string[i] -> u8 (but we treat as string for printing)
                        // list[i] -> element type
                        // dict[key] -> value type
                        // tuple[i] -> element type at index i
                        if (obj_type == .string) {
                            // String indexing returns a single character
                            // For now, treat as string for simplicity
                            break :blk .{ .string = .slice };
                        } else if (obj_type == .array) {
                            break :blk obj_type.array.element_type.*;
                        } else if (obj_type == .list) {
                            break :blk obj_type.list.*;
                        } else if (obj_type == .dict) {
                            break :blk obj_type.dict.value.*;
                        } else if (obj_type == .tuple) {
                            // Try to get constant index
                            if (idx.* == .constant and idx.constant.value == .int) {
                                const index = @as(usize, @intCast(idx.constant.value.int));
                                if (index < obj_type.tuple.len) {
                                    break :blk obj_type.tuple[index];
                                }
                            }
                            // If we can't determine constant index, return unknown
                            break :blk .unknown;
                        } else {
                            break :blk .unknown;
                        }
                    },
                    .slice => {
                        // Slice access always returns same type as container
                        // string[1:4] -> string
                        // array[1:4] -> slice (converted to list)
                        // list[1:4] -> list
                        if (obj_type == .string) {
                            break :blk .{ .string = .slice };
                        } else if (obj_type == .array) {
                            // Array slices become lists (dynamic)
                            break :blk .{ .list = obj_type.array.element_type };
                        } else if (obj_type == .list) {
                            break :blk obj_type;
                        } else {
                            break :blk .unknown;
                        }
                    },
                }
            },
            .attribute => |a| blk: {
                // Infer attribute type: obj.attr
                // Heuristic: Check all known classes for a field with this name
                // This works when field names are unique across classes
                if (a.value.* == .name) {
                    var class_it = self.class_fields.iterator();
                    while (class_it.next()) |class_entry| {
                        if (class_entry.value_ptr.fields.get(a.attr)) |field_type| {
                            // Found a class with a field matching this attribute name
                            break :blk field_type;
                        }
                    }
                }

                // Fallback: try to infer from object type (for future enhancements)
                const obj_type = try self.inferExpr(a.value.*);
                _ = obj_type; // Currently unused, but kept for future use

                break :blk .unknown;
            },
            .list => |l| blk: {
                // Check if this is a constant, homogeneous list → use array type
                if (isConstantList(l) and allSameType(l.elts)) {
                    const elem_type = if (l.elts.len > 0)
                        try self.inferExpr(l.elts[0])
                    else
                        .unknown;

                    const elem_ptr = try self.allocator.create(NativeType);
                    elem_ptr.* = elem_type;
                    break :blk .{ .array = .{
                        .element_type = elem_ptr,
                        .length = l.elts.len,
                    } };
                }

                // Otherwise, use ArrayList for dynamic lists
                const elem_type = if (l.elts.len > 0)
                    try self.inferExpr(l.elts[0])
                else
                    .unknown;

                const elem_ptr = try self.allocator.create(NativeType);
                elem_ptr.* = elem_type;
                break :blk .{ .list = elem_ptr };
            },
            .dict => |d| blk: {
                // Infer value type from first value if available
                const val_type = if (d.values.len > 0)
                    try self.inferExpr(d.values[0])
                else
                    .unknown;

                // Allocate on heap to avoid dangling pointer
                const val_ptr = try self.allocator.create(NativeType);
                val_ptr.* = val_type;

                // Allocate key type (always string for Python dicts)
                const key_ptr = try self.allocator.create(NativeType);
                key_ptr.* = .{ .string = .runtime };

                // For now, always use string keys (most common case)
                break :blk .{ .dict = .{
                    .key = key_ptr,
                    .value = val_ptr,
                } };
            },
            .dictcomp => |dc| blk: {
                // Infer types from key and value expressions
                const key_type = try self.inferExpr(dc.key.*);
                const val_type = try self.inferExpr(dc.value.*);

                // Allocate key and value types on heap
                const key_ptr = try self.allocator.create(NativeType);
                key_ptr.* = key_type;
                const val_ptr = try self.allocator.create(NativeType);
                val_ptr.* = val_type;

                break :blk .{ .dict = .{
                    .key = key_ptr,
                    .value = val_ptr,
                } };
            },
            .tuple => |t| blk: {
                // Infer types of all tuple elements
                var elem_types = try self.allocator.alloc(NativeType, t.elts.len);
                for (t.elts, 0..) |elt, i| {
                    elem_types[i] = try self.inferExpr(elt);
                }
                break :blk .{ .tuple = elem_types };
            },
            .compare => .bool, // Comparison expressions always return bool
            .lambda => |lam| blk: {
                // Infer function type from lambda
                // For now, default all params and return to i64
                // TODO: Better type inference based on usage
                const param_types = try self.allocator.alloc(NativeType, lam.args.len);
                for (param_types) |*pt| {
                    pt.* = .int; // Default to i64
                }
                const return_ptr = try self.allocator.create(NativeType);
                return_ptr.* = .int; // Default to i64
                break :blk .{ .function = .{
                    .params = param_types,
                    .return_type = return_ptr,
                } };
            },
            else => .unknown,
        };
    }

    fn inferConstant(self: *TypeInferrer, value: ast.Value) InferError!NativeType {
        _ = self;
        return switch (value) {
            .int => .int,
            .float => .float,
            .string => .{ .string = .literal }, // String literals are compile-time constants
            .bool => .bool,
        };
    }

    fn inferBinOp(self: *TypeInferrer, binop: ast.Node.BinOp) InferError!NativeType {
        const left_type = try self.inferExpr(binop.left.*);
        const right_type = try self.inferExpr(binop.right.*);

        // Get type tags for analysis
        const left_tag = @as(std.meta.Tag(NativeType), left_type);
        const right_tag = @as(std.meta.Tag(NativeType), right_type);

        // String concatenation: str + str → runtime string
        if (binop.op == .Add and left_tag == .string and right_tag == .string) {
            return .{ .string = .runtime }; // Concatenation produces runtime string
        }

        // Type promotion: int + float → float
        if (binop.op == .Add or binop.op == .Sub or binop.op == .Mult or binop.op == .Div) {
            if (left_tag == .float or right_tag == .float) {
                return .float; // Any arithmetic with float produces float
            }
            // usize mixed with int → result is int (codegen casts both to i64)
            if ((left_tag == .usize and right_tag == .int) or (left_tag == .int and right_tag == .usize)) {
                return .int;
            }
            // usize op usize → usize
            if (left_tag == .usize and right_tag == .usize) {
                return .usize;
            }
            if (left_tag == .int and right_tag == .int) {
                return .int; // int op int produces int
            }
        }

        // Default: use widening logic
        return left_type.widen(right_type);
    }

    fn inferCall(self: *TypeInferrer, call: ast.Node.Call) InferError!NativeType {
        // Check if this is a registered function (lambda or regular function)
        if (call.func.* == .name) {
            const func_name = call.func.name.id;

            // Check for registered function return types (lambdas, etc.)
            if (self.func_return_types.get(func_name)) |return_type| {
                return return_type;
            }

            // Built-in type conversion functions

            if (std.mem.eql(u8, func_name, "str")) return .{ .string = .runtime }; // str() produces runtime string
            if (std.mem.eql(u8, func_name, "int")) return .int;
            if (std.mem.eql(u8, func_name, "float")) return .float;
            if (std.mem.eql(u8, func_name, "bool")) return .bool;

            // Built-in math functions
            if (std.mem.eql(u8, func_name, "abs")) {
                // abs() returns same type as input
                if (call.args.len > 0) {
                    return try self.inferExpr(call.args[0]);
                }
            }
            if (std.mem.eql(u8, func_name, "round")) return .int;
            if (std.mem.eql(u8, func_name, "chr")) return .{ .string = .runtime }; // chr() produces runtime string
            if (std.mem.eql(u8, func_name, "ord")) return .int;
        }

        // Check if this is a method call (attribute access)
        if (call.func.* == .attribute) {
            const attr = call.func.attribute;

            // Check for pandas.DataFrame() or pd.DataFrame()
            if (attr.value.* == .name) {
                const module_name = attr.value.name.id;
                if ((std.mem.eql(u8, module_name, "pandas") or std.mem.eql(u8, module_name, "pd")) and
                    std.mem.eql(u8, attr.attr, "DataFrame")) {
                    return .dataframe;
                }
            }

            const obj_type = try self.inferExpr(attr.value.*);

            // String methods that return strings
            if (obj_type == .string) {
                const str_methods = [_][]const u8{
                    "upper", "lower", "strip", "lstrip", "rstrip",
                    "capitalize", "title", "swapcase", "replace",
                    "join", "center", "ljust", "rjust", "zfill",
                };

                for (str_methods) |method| {
                    if (std.mem.eql(u8, attr.attr, method)) {
                        return .{ .string = .runtime }; // String methods produce runtime strings
                    }
                }

                // Boolean-returning methods
                if (std.mem.eql(u8, attr.attr, "startswith")) return .bool;
                if (std.mem.eql(u8, attr.attr, "endswith")) return .bool;

                // Integer-returning methods
                if (std.mem.eql(u8, attr.attr, "find")) return .int;

                // split() returns list of runtime strings
                if (std.mem.eql(u8, attr.attr, "split")) {
                    const elem_ptr = try self.allocator.create(NativeType);
                    elem_ptr.* = .{ .string = .runtime }; // Split produces list of runtime strings
                    return .{ .list = elem_ptr };
                }
            }

            // Dict methods
            if (obj_type == .dict) {
                // keys() returns list of strings (dict keys are always strings)
                if (std.mem.eql(u8, attr.attr, "keys")) {
                    const elem_ptr = try self.allocator.create(NativeType);
                    elem_ptr.* = .{ .string = .runtime }; // Dict keys are runtime strings
                    return .{ .list = elem_ptr };
                }

                // values() returns list of dict value type
                if (std.mem.eql(u8, attr.attr, "values")) {
                    const elem_ptr = try self.allocator.create(NativeType);
                    elem_ptr.* = obj_type.dict.value.*;
                    return .{ .list = elem_ptr };
                }

                // items() returns list of tuples (key, value)
                if (std.mem.eql(u8, attr.attr, "items")) {
                    const tuple_types = try self.allocator.alloc(NativeType, 2);
                    tuple_types[0] = .{ .string = .runtime }; // Dict keys are runtime strings
                    tuple_types[1] = obj_type.dict.value.*; // value
                    const tuple_ptr = try self.allocator.create(NativeType);
                    tuple_ptr.* = .{ .tuple = tuple_types };
                    return .{ .list = tuple_ptr };
                }
            }

            // DataFrame Column methods (when accessing df['col'].method())
            // Column methods return float (sum, mean, min, max, std)
            if (obj_type == .dataframe or
                (attr.value.* == .subscript and
                 try self.inferExpr(attr.value.subscript.value.*) == .dataframe)) {
                const column_methods = [_][]const u8{
                    "sum", "mean", "min", "max", "std",
                };
                for (column_methods) |method| {
                    if (std.mem.eql(u8, attr.attr, method)) {
                        return .float;
                    }
                }
                // describe() returns a struct with stats (treat as unknown for now)
                if (std.mem.eql(u8, attr.attr, "describe")) {
                    return .unknown;
                }
            }
        }

        // For other calls, return unknown
        return .unknown;
    }
};
