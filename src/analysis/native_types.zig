const std = @import("std");
const ast = @import("../ast.zig");

/// Native Zig types inferred from Python code
pub const NativeType = union(enum) {
    // Primitives - stack allocated, zero overhead
    int: void, // i64
    float: void, // f64
    bool: void, // bool
    string: void, // []const u8

    // Composites
    list: *const NativeType, // []T or ArrayList(T)
    dict: struct {
        key: *const NativeType,
        value: *const NativeType,
    }, // StringHashMap(V)
    tuple: []const NativeType, // Zig tuple struct

    // Special
    none: void, // void or ?T
    unknown: void, // Fallback to PyObject* (should be rare)

    /// Convert to Zig type string
    pub fn toZigType(self: NativeType, allocator: std.mem.Allocator, buf: *std.ArrayList(u8)) !void {
        switch (self) {
            .int => try buf.appendSlice(allocator, "i64"),
            .float => try buf.appendSlice(allocator, "f64"),
            .bool => try buf.appendSlice(allocator, "bool"),
            .string => try buf.appendSlice(allocator, "[]const u8"),
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
            .none => try buf.appendSlice(allocator, "void"),
            .unknown => try buf.appendSlice(allocator, "*runtime.PyObject"),
        }
    }
};

/// Error set for type inference
pub const InferError = error{
    OutOfMemory,
};

/// Convert Python type hint string to NativeType
fn pythonTypeHintToNative(type_hint: ?[]const u8) NativeType {
    if (type_hint) |hint| {
        if (std.mem.eql(u8, hint, "int")) return .int;
        if (std.mem.eql(u8, hint, "float")) return .float;
        if (std.mem.eql(u8, hint, "bool")) return .bool;
        if (std.mem.eql(u8, hint, "str")) return .string;
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

    pub fn init(allocator: std.mem.Allocator) InferError!TypeInferrer {
        return TypeInferrer{
            .allocator = allocator,
            .var_types = std.StringHashMap(NativeType).init(allocator),
            .class_fields = std.StringHashMap(ClassInfo).init(allocator),
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
    }

    /// Analyze a module to infer all variable types
    pub fn analyze(self: *TypeInferrer, module: ast.Node.Module) InferError!void {
        // Register __name__ as a string constant (for if __name__ == "__main__" support)
        try self.var_types.put("__name__", .string);

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
                                                    const field_type = pythonTypeHintToNative(arg.type_annotation);
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
                            // First var is always int (index)
                            if (targets[0] == .name) {
                                try self.var_types.put(targets[0].name.id, .int);
                            }
                            // Second var type comes from the list being enumerated
                            if (targets[1] == .name and for_stmt.iter.call.args.len > 0) {
                                const arg = for_stmt.iter.call.args[0];
                                // Only handle simple cases to avoid side effects
                                if (arg == .name) {
                                        // Get type from variable
                                    const list_type = self.var_types.get(arg.name.id) orelse .unknown;
                                    const elem_type = if (list_type == .list) list_type.list.* else .unknown;
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
                                        const elem_type = if (list_type == .list) list_type.list.* else .unknown;
                                        try self.var_types.put(targets[i].name.id, elem_type);
                                    }
                                }
                            }
                        }
                    }
                } else if (for_stmt.target.* == .name) {
                    // Single loop var: for item in items
                    if (for_stmt.iter.* == .name) {
                        const iter_type = self.var_types.get(for_stmt.iter.name.id) orelse .unknown;
                        const elem_type = if (iter_type == .list) iter_type.list.* else .unknown;
                        try self.var_types.put(for_stmt.target.name.id, elem_type);
                    }
                }

                for (for_stmt.body) |s| try self.visitStmt(s);
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
                            break :blk .string;
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
                        // list[1:4] -> list
                        if (obj_type == .string) {
                            break :blk .string;
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
                // Infer element type from first element if available
                const elem_type = if (l.elts.len > 0)
                    try self.inferExpr(l.elts[0])
                else
                    .unknown;

                // Allocate on heap to avoid dangling pointer
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

                // For now, always use string keys (most common case)
                break :blk .{ .dict = .{
                    .key = &.string,
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
            else => .unknown,
        };
    }

    fn inferConstant(self: *TypeInferrer, value: ast.Value) InferError!NativeType {
        _ = self;
        return switch (value) {
            .int => .int,
            .float => .float,
            .string => .string,
            .bool => .bool,
        };
    }

    fn inferBinOp(self: *TypeInferrer, binop: ast.Node.BinOp) InferError!NativeType {
        const left_type = try self.inferExpr(binop.left.*);
        const right_type = try self.inferExpr(binop.right.*);

        // Simplified type inference - just use left operand type
        // TODO: Handle type promotion (int + float = float)
        _ = right_type;
        return left_type;
    }

    fn inferCall(self: *TypeInferrer, call: ast.Node.Call) InferError!NativeType {
        // Built-in type conversion functions
        if (call.func.* == .name) {
            const func_name = call.func.name.id;
            if (std.mem.eql(u8, func_name, "str")) return .string;
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
            if (std.mem.eql(u8, func_name, "chr")) return .string;
            if (std.mem.eql(u8, func_name, "ord")) return .int;
        }

        // Check if this is a method call (attribute access)
        if (call.func.* == .attribute) {
            const attr = call.func.attribute;
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
                        return .string;
                    }
                }

                // Boolean-returning methods
                if (std.mem.eql(u8, attr.attr, "startswith")) return .bool;
                if (std.mem.eql(u8, attr.attr, "endswith")) return .bool;

                // Integer-returning methods
                if (std.mem.eql(u8, attr.attr, "find")) return .int;

                // split() returns list of strings
                if (std.mem.eql(u8, attr.attr, "split")) {
                    const elem_ptr = try self.allocator.create(NativeType);
                    elem_ptr.* = .string;
                    return .{ .list = elem_ptr };
                }
            }

            // Dict methods
            if (obj_type == .dict) {
                // keys() returns list of strings (dict keys are always strings)
                if (std.mem.eql(u8, attr.attr, "keys")) {
                    const elem_ptr = try self.allocator.create(NativeType);
                    elem_ptr.* = .string;
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
                    tuple_types[0] = .string; // key
                    tuple_types[1] = obj_type.dict.value.*; // value
                    const tuple_ptr = try self.allocator.create(NativeType);
                    tuple_ptr.* = .{ .tuple = tuple_types };
                    return .{ .list = tuple_ptr };
                }
            }
        }

        // For other calls, return unknown
        return .unknown;
    }
};
