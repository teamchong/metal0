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

                // split() returns list of strings
                if (std.mem.eql(u8, attr.attr, "split")) {
                    const elem_ptr = try self.allocator.create(NativeType);
                    elem_ptr.* = .string;
                    return .{ .list = elem_ptr };
                }
            }
        }

        // For other calls, return unknown
        return .unknown;
    }
};
