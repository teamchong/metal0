/// @logic_table class code generation
///
/// Transforms Python @logic_table decorated classes into high-performance
/// Zig batch functions with GPU/SIMD dispatch.
///
/// Example input:
/// ```python
/// @logic_table
/// class VectorOps:
///     def cosine_sim(self):
///         return sum(query.embedding * docs.embedding) / (norm(query.embedding) * norm(docs.embedding))
/// ```
///
/// Generated output:
/// ```zig
/// pub const VectorOps = struct {
///     pub const __logic_table__ = true;
///     pub const methods = [_]MethodMeta{ ... };
///     pub fn cosine_sim(query_embedding: []const f32, docs_embedding: []const f32) f32 { ... }
/// };
/// ```

const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

/// Table.column dependency extracted from method body
pub const TableColumnDep = struct {
    table: []const u8,
    column: []const u8,
};

/// Check if a class has @logic_table decorator
pub fn hasLogicTableDecorator(class: ast.Node.ClassDef) bool {
    for (class.decorators) |decorator| {
        // Check for simple name: @logic_table
        if (decorator == .name) {
            if (std.mem.eql(u8, decorator.name.id, "logic_table")) {
                return true;
            }
        }
        // Check for attribute access: @module.logic_table
        if (decorator == .attribute) {
            if (std.mem.eql(u8, decorator.attribute.attr, "logic_table")) {
                return true;
            }
        }
        // Check for call: @logic_table()
        if (decorator == .call) {
            if (decorator.call.func.* == .name) {
                if (std.mem.eql(u8, decorator.call.func.name.id, "logic_table")) {
                    return true;
                }
            }
        }
    }
    return false;
}

/// Extract table.column dependencies from an expression
/// Finds patterns like: query.embedding, docs.vector, etc.
/// Excludes self.* patterns
fn extractDependencies(
    allocator: std.mem.Allocator,
    node: ast.Node,
    deps: *std.ArrayListUnmanaged(TableColumnDep),
) !void {
    switch (node) {
        .attribute => |attr| {
            // Check if this is table.column (not self.*)
            if (attr.value.* == .name) {
                const table_name = attr.value.name.id;
                // Skip self references
                if (!std.mem.eql(u8, table_name, "self")) {
                    // This is a table.column reference
                    try deps.append(allocator, .{
                        .table = table_name,
                        .column = attr.attr,
                    });
                }
            }
            // Recurse into nested expressions
            try extractDependencies(allocator, attr.value.*, deps);
        },
        .binop => |bin| {
            try extractDependencies(allocator, bin.left.*, deps);
            try extractDependencies(allocator, bin.right.*, deps);
        },
        .unaryop => |un| {
            try extractDependencies(allocator, un.operand.*, deps);
        },
        .call => |call| {
            // Check function name
            try extractDependencies(allocator, call.func.*, deps);
            // Check arguments
            for (call.args) |arg| {
                try extractDependencies(allocator, arg, deps);
            }
        },
        .if_expr => |ie| {
            try extractDependencies(allocator, ie.condition.*, deps);
            try extractDependencies(allocator, ie.body.*, deps);
            try extractDependencies(allocator, ie.orelse_value.*, deps);
        },
        .subscript => |sub| {
            try extractDependencies(allocator, sub.value.*, deps);
        },
        .list => |l| {
            for (l.elts) |elt| {
                try extractDependencies(allocator, elt, deps);
            }
        },
        .tuple => |t| {
            for (t.elts) |elt| {
                try extractDependencies(allocator, elt, deps);
            }
        },
        else => {},
    }
}

/// Extract all dependencies from a method body
fn extractMethodDependencies(
    allocator: std.mem.Allocator,
    body: []const ast.Node,
) ![]TableColumnDep {
    var deps: std.ArrayListUnmanaged(TableColumnDep) = .{};
    errdefer deps.deinit(allocator);

    for (body) |stmt| {
        switch (stmt) {
            .return_stmt => |ret| {
                if (ret.value) |val| {
                    try extractDependencies(allocator, val.*, &deps);
                }
            },
            .assign => |assign| {
                try extractDependencies(allocator, assign.value.*, &deps);
            },
            .expr_stmt => |expr| {
                try extractDependencies(allocator, expr.value.*, &deps);
            },
            else => {},
        }
    }

    // Deduplicate dependencies
    var unique: std.ArrayListUnmanaged(TableColumnDep) = .{};
    for (deps.items) |dep| {
        var found = false;
        for (unique.items) |u| {
            if (std.mem.eql(u8, u.table, dep.table) and std.mem.eql(u8, u.column, dep.column)) {
                found = true;
                break;
            }
        }
        if (!found) {
            try unique.append(allocator, dep);
        }
    }
    deps.deinit(allocator);

    return unique.toOwnedSlice(allocator);
}

/// Generate @logic_table class as a Zig struct with batch functions
pub fn genLogicTableClass(self: *NativeCodegen, class: ast.Node.ClassDef) CodegenError!void {
    const allocator = self.allocator;

    // Emit struct definition
    try self.emitIndent();
    try self.emit("pub const ");
    try self.emit(class.name);
    try self.emit(" = struct {\n");

    self.indent_level += 1;

    // Emit __logic_table__ marker
    try self.emitIndent();
    try self.emit("pub const __logic_table__ = true;\n\n");

    // Collect method metadata for the methods array
    var method_names: std.ArrayListUnmanaged([]const u8) = .{};
    defer method_names.deinit(allocator);

    // Generate batch functions for each method
    for (class.body) |stmt| {
        if (stmt == .function_def) {
            const method = stmt.function_def;

            // Skip __init__ and dunder methods
            if (std.mem.startsWith(u8, method.name, "__")) continue;

            try method_names.append(allocator, method.name);

            // Extract dependencies from method body
            const deps = try extractMethodDependencies(allocator, method.body);
            defer allocator.free(deps);

            // Generate dependency metadata
            try self.emitIndent();
            try self.emitFmt("pub const {s}_deps = [_]struct {{ table: []const u8, column: []const u8 }}{{\n", .{method.name});
            self.indent_level += 1;
            for (deps) |dep| {
                try self.emitIndent();
                try self.emitFmt(".{{ .table = \"{s}\", .column = \"{s}\" }},\n", .{ dep.table, dep.column });
            }
            self.indent_level -= 1;
            try self.emitIndent();
            try self.emit("};\n\n");

            // Generate batch function
            try genBatchFunction(self, method, deps);
        }
    }

    // Emit methods registry
    try self.emitIndent();
    try self.emit("pub const methods = [_][]const u8{\n");
    self.indent_level += 1;
    for (method_names.items) |name| {
        try self.emitIndent();
        try self.emitFmt("\"{s}\",\n", .{name});
    }
    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("};\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("};\n");
}

/// Generate a batch function from a method definition
fn genBatchFunction(
    self: *NativeCodegen,
    method: ast.Node.FunctionDef,
    deps: []const TableColumnDep,
) CodegenError!void {
    try self.emitIndent();
    try self.emitFmt("pub fn {s}(", .{method.name});

    // Generate parameters from dependencies
    var first = true;
    for (deps) |dep| {
        if (!first) try self.emit(", ");
        first = false;
        try self.emitFmt("{s}_{s}: []const f32", .{ dep.table, dep.column });
    }

    // Add output parameter
    if (deps.len > 0) try self.emit(", ");
    try self.emit("out: []f32) void {\n");

    self.indent_level += 1;

    // Generate batch loop
    try self.emitIndent();
    try self.emit("const len = out.len;\n");
    try self.emitIndent();
    try self.emit("var i: usize = 0;\n");
    try self.emitIndent();
    try self.emit("while (i < len) : (i += 1) {\n");

    self.indent_level += 1;

    // Generate body - for now emit a placeholder
    // The actual expression transformation is complex and depends on the operation
    try self.emitIndent();

    // Check if method has a return statement with a simple expression
    for (method.body) |stmt| {
        if (stmt == .return_stmt) {
            if (stmt.return_stmt.value) |val| {
                try self.emit("out[i] = ");
                try genBatchExpr(self, val.*, deps);
                try self.emit(";\n");
                break;
            }
        }
    }

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n");

    self.indent_level -= 1;
    try self.emitIndent();
    try self.emit("}\n\n");
}

/// Generate batch expression - transform Python expr to Zig with indexing
fn genBatchExpr(
    self: *NativeCodegen,
    node: ast.Node,
    deps: []const TableColumnDep,
) CodegenError!void {
    switch (node) {
        .attribute => |attr| {
            if (attr.value.* == .name) {
                const table_name = attr.value.name.id;
                if (!std.mem.eql(u8, table_name, "self")) {
                    // table.column -> table_column[i]
                    try self.emitFmt("{s}_{s}[i]", .{ table_name, attr.attr });
                    return;
                }
            }
            // Fallback
            try self.emit("0.0");
        },
        .binop => |bin| {
            try self.emit("(");
            try genBatchExpr(self, bin.left.*, deps);
            switch (bin.op) {
                .Add => try self.emit(" + "),
                .Sub => try self.emit(" - "),
                .Mult => try self.emit(" * "),
                .Div => try self.emit(" / "),
                .Mod => try self.emit(" % "),
                .Pow => try self.emit(" ** "),
                else => try self.emit(" ? "),
            }
            try genBatchExpr(self, bin.right.*, deps);
            try self.emit(")");
        },
        .call => |call| {
            // Handle special functions
            if (call.func.* == .name) {
                const func_name = call.func.name.id;

                if (std.mem.eql(u8, func_name, "sum")) {
                    // sum(a * b) -> dot product
                    if (call.args.len > 0) {
                        try self.emit("blk: { var __sum: f32 = 0.0; var __j: usize = 0; while (__j < ");
                        // Get dimension from first arg if it's an attribute
                        if (call.args[0] == .binop) {
                            if (call.args[0].binop.left.* == .attribute) {
                                const attr = call.args[0].binop.left.attribute;
                                if (attr.value.* == .name) {
                                    try self.emitFmt("{s}_{s}.len", .{ attr.value.name.id, attr.attr });
                                }
                            }
                        } else {
                            try self.emit("384"); // Default dim
                        }
                        try self.emit(") : (__j += 1) { __sum += ");
                        try genBatchExpr(self, call.args[0], deps);
                        try self.emit("; } break :blk __sum; }");
                    }
                    return;
                }

                if (std.mem.eql(u8, func_name, "norm")) {
                    // norm(x) -> sqrt of sum of squares
                    if (call.args.len > 0) {
                        try self.emit("@sqrt(blk: { var __sum: f32 = 0.0; var __j: usize = 0; while (__j < ");
                        if (call.args[0] == .attribute) {
                            const attr = call.args[0].attribute;
                            if (attr.value.* == .name) {
                                try self.emitFmt("{s}_{s}.len", .{ attr.value.name.id, attr.attr });
                            }
                        } else {
                            try self.emit("384");
                        }
                        try self.emit(") : (__j += 1) { const __v = ");
                        try genBatchExpr(self, call.args[0], deps);
                        try self.emit("; __sum += __v * __v; } break :blk __sum; })");
                    }
                    return;
                }

                if (std.mem.eql(u8, func_name, "sqrt")) {
                    try self.emit("@sqrt(");
                    if (call.args.len > 0) {
                        try genBatchExpr(self, call.args[0], deps);
                    }
                    try self.emit(")");
                    return;
                }

                if (std.mem.eql(u8, func_name, "abs")) {
                    try self.emit("@abs(");
                    if (call.args.len > 0) {
                        try genBatchExpr(self, call.args[0], deps);
                    }
                    try self.emit(")");
                    return;
                }
            }
            // Generic function call - emit placeholder
            try self.emit("0.0");
        },
        .constant => |c| {
            switch (c.value) {
                .int => |i| try self.emitFmt("@as(f32, {d})", .{i}),
                .float => |f| try self.emitFmt("@as(f32, {d})", .{f}),
                else => try self.emit("0.0"),
            }
        },
        .name => |n| {
            // Local variable reference
            try self.emit(n.id);
        },
        else => {
            try self.emit("0.0");
        },
    }
}

test "hasLogicTableDecorator" {
    // Test with simple decorator
    const class1 = ast.Node.ClassDef{
        .name = "Test",
        .bases = &[_][]const u8{},
        .body = &[_]ast.Node{},
        .decorators = &[_]ast.Node{
            .{ .name = .{ .id = "logic_table" } },
        },
    };
    try std.testing.expect(hasLogicTableDecorator(class1));

    // Test without decorator
    const class2 = ast.Node.ClassDef{
        .name = "Test",
        .bases = &[_][]const u8{},
        .body = &[_]ast.Node{},
        .decorators = &[_]ast.Node{},
    };
    try std.testing.expect(!hasLogicTableDecorator(class2));
}
