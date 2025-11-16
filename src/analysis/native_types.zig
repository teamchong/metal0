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

/// Type inferrer - analyzes AST to determine native Zig types
pub const TypeInferrer = struct {
    allocator: std.mem.Allocator,
    var_types: std.StringHashMap(NativeType),

    pub fn init(allocator: std.mem.Allocator) InferError!TypeInferrer {
        return TypeInferrer{
            .allocator = allocator,
            .var_types = std.StringHashMap(NativeType).init(allocator),
        };
    }

    pub fn deinit(self: *TypeInferrer) void {
        self.var_types.deinit();
    }

    /// Analyze a module to infer all variable types
    pub fn analyze(self: *TypeInferrer, module: ast.Node.Module) InferError!void {
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
            .list => .{ .list = &.unknown },
            .dict => |d| blk: {
                // Infer value type from first value if available
                const val_type = if (d.values.len > 0)
                    try self.inferExpr(d.values[0])
                else
                    .unknown;

                // For now, always use string keys (most common case)
                break :blk .{ .dict = .{
                    .key = &.string,
                    .value = &val_type,
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
        _ = self;
        _ = call;
        // TODO: Infer return types for built-in functions
        // For now, assume unknown
        return .unknown;
    }
};
