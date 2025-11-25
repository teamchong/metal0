/// Expression-level code generation - Re-exports from submodules
/// Handles Python expressions: constants, binary ops, calls, lists, dicts, subscripts, etc.
const std = @import("std");
const ast = @import("../../ast.zig");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

// Import submodules
const constants = @import("expressions/constants.zig");
const operators = @import("expressions/operators.zig");
const subscript_mod = @import("expressions/subscript.zig");
const collections = @import("expressions/collections.zig");
const dict_mod = @import("expressions/dict.zig");
const lambda_mod = @import("expressions/lambda.zig");
const calls = @import("expressions/calls.zig");
const comprehensions = @import("expressions/comprehensions.zig");
const misc = @import("expressions/misc.zig");

// Re-export functions from submodules
pub const genConstant = constants.genConstant;
pub const genBinOp = operators.genBinOp;
pub const genUnaryOp = operators.genUnaryOp;
pub const genCompare = operators.genCompare;
pub const genBoolOp = operators.genBoolOp;
pub const genList = collections.genList;
pub const genDict = dict_mod.genDict;
pub const genCall = calls.genCall;
pub const genListComp = comprehensions.genListComp;
pub const genDictComp = comprehensions.genDictComp;
pub const genTuple = misc.genTuple;
pub const genSubscript = misc.genSubscript;
pub const genAttribute = misc.genAttribute;

/// Main expression dispatcher
pub fn genExpr(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    switch (node) {
        .constant => |c| try constants.genConstant(self, c),
        .name => |n| {
            // Check if variable has been renamed (for exception handling)
            const name_to_use = self.var_renames.get(n.id) orelse n.id;
            try self.output.appendSlice(self.allocator, name_to_use);
        },
        .fstring => |f| try genFString(self, f),
        .binop => |b| try operators.genBinOp(self, b),
        .unaryop => |u| try operators.genUnaryOp(self, u),
        .compare => |c| try operators.genCompare(self, c),
        .boolop => |b| try operators.genBoolOp(self, b),
        .call => |c| try calls.genCall(self, c),
        .list => |l| try collections.genList(self, l),
        .listcomp => |lc| try comprehensions.genListComp(self, lc),
        .dict => |d| try dict_mod.genDict(self, d),
        .dictcomp => |dc| try comprehensions.genDictComp(self, dc),
        .set => |s| try collections.genSet(self, s),
        .tuple => |t| try misc.genTuple(self, t),
        .subscript => |s| try misc.genSubscript(self, s),
        .attribute => |a| try misc.genAttribute(self, a),
        .lambda => |lam| lambda_mod.genLambda(self, lam) catch {},
        .await_expr => |a| try genAwait(self, a),
        .ellipsis_literal => {
            // Python Ellipsis literal (...)
            // Emit void value to avoid "unused variable" warnings
            try self.output.appendSlice(self.allocator, "@as(void, {})");
        },
        .starred => |s| {
            // Starred expression: *expr
            // Just generate the inner expression (unpacking is handled by call context)
            try genExpr(self, s.value.*);
        },
        .double_starred => |ds| {
            // Double starred expression: **expr
            // Just generate the inner expression (unpacking is handled by call context)
            try genExpr(self, ds.value.*);
        },
        .named_expr => |ne| try genNamedExpr(self, ne),
        .if_expr => |ie| try genIfExpr(self, ie),
        else => {},
    }
}

/// Generate named expression (walrus operator): (x := value)
/// Assigns value to target and returns the value
fn genNamedExpr(self: *NativeCodegen, ne: ast.Node.NamedExpr) CodegenError!void {
    // Get the target name
    const target_name = switch (ne.target.*) {
        .name => |n| n.id,
        else => return, // Should be unreachable, walrus target must be a name
    };

    // Generate: (blk: { target = value; break :blk target; })
    try self.output.appendSlice(self.allocator, "(blk: { ");
    try self.output.appendSlice(self.allocator, target_name);
    try self.output.appendSlice(self.allocator, " = ");
    try genExpr(self, ne.value.*);
    try self.output.appendSlice(self.allocator, "; break :blk ");
    try self.output.appendSlice(self.allocator, target_name);
    try self.output.appendSlice(self.allocator, "; })");
}

/// Generate conditional expression (ternary): body if condition else orelse_value
fn genIfExpr(self: *NativeCodegen, ie: ast.Node.IfExpr) CodegenError!void {
    // In Zig: if (condition) body else orelse_value
    try self.output.appendSlice(self.allocator, "(if (");
    try genExpr(self, ie.condition.*);
    try self.output.appendSlice(self.allocator, ") ");
    try genExpr(self, ie.body.*);
    try self.output.appendSlice(self.allocator, " else ");
    try genExpr(self, ie.orelse_value.*);
    try self.output.appendSlice(self.allocator, ")");
}

/// Generate await expression
fn genAwait(self: *NativeCodegen, await_node: ast.Node.AwaitExpr) CodegenError!void {
    // await expr → wait for green thread and get result
    try self.output.appendSlice(self.allocator, "(blk: {\n");
    try self.output.appendSlice(self.allocator, "    const __thread = ");
    try genExpr(self, await_node.value.*);
    try self.output.appendSlice(self.allocator, ";\n");
    try self.output.appendSlice(self.allocator, "    runtime.scheduler.wait(__thread);\n");
    // Cast result to expected type (TODO: infer from type system)
    try self.output.appendSlice(self.allocator, "    const __result = __thread.result orelse unreachable;\n");
    try self.output.appendSlice(self.allocator, "    break :blk @as(*i64, @ptrCast(@alignCast(__result))).*;\n");
    try self.output.appendSlice(self.allocator, "})");
}

/// Convert Python format specifier to Zig format specifier
fn convertFormatSpec(allocator: std.mem.Allocator, python_spec: []const u8) ![]const u8 {
    // Python: .2f  -> Zig: d:.2
    // Python: d    -> Zig: d
    // Python: s    -> Zig: s
    // Python: .3f  -> Zig: d:.3
    // Python: 10.2f -> Zig: d:10.2

    if (std.mem.indexOf(u8, python_spec, "f") != null) {
        // Float format: .2f, 10.2f, etc.
        // Remove 'f' and prepend 'd:'
        var buf = std.ArrayList(u8){};
        try buf.appendSlice(allocator, "d:");
        for (python_spec) |c| {
            if (c != 'f') try buf.append(allocator, c);
        }
        return buf.toOwnedSlice(allocator);
    }

    // Return as-is for other specs
    return allocator.dupe(u8, python_spec);
}

/// Generate f-string code
fn genFString(self: *NativeCodegen, fstring: ast.Node.FString) CodegenError!void {
    // For now, generate a compile-time concatenation if possible
    // or use std.fmt.allocPrint for runtime formatting

    // Check if all parts are literals (simple case)
    var all_literals = true;
    for (fstring.parts) |part| {
        if (part != .literal) {
            all_literals = false;
            break;
        }
    }

    if (all_literals) {
        // Simple case: just concatenate literals
        try self.output.appendSlice(self.allocator, "\"");
        for (fstring.parts) |part| {
            const lit = part.literal;
            for (lit) |c| {
                switch (c) {
                    '"' => try self.output.appendSlice(self.allocator, "\\\""),
                    '\\' => try self.output.appendSlice(self.allocator, "\\\\"),
                    '\n' => try self.output.appendSlice(self.allocator, "\\n"),
                    '\r' => try self.output.appendSlice(self.allocator, "\\r"),
                    '\t' => try self.output.appendSlice(self.allocator, "\\t"),
                    else => try self.output.writer(self.allocator).print("{c}", .{c}),
                }
            }
        }
        try self.output.appendSlice(self.allocator, "\"");
        return;
    }

    // Complex case: has expressions, need runtime formatting
    // Build format string and arguments list
    var format_buf = std.ArrayList(u8){};
    defer format_buf.deinit(self.allocator);

    var args_list = std.ArrayList([]const u8){};
    defer {
        for (args_list.items) |item| {
            self.allocator.free(item);
        }
        args_list.deinit(self.allocator);
    }

    for (fstring.parts) |part| {
        switch (part) {
            .literal => |lit| {
                // Escape braces for Zig format strings
                for (lit) |c| {
                    if (c == '{' or c == '}') {
                        try format_buf.append(self.allocator, c);
                        try format_buf.append(self.allocator, c); // Double to escape
                    } else {
                        try format_buf.append(self.allocator, c);
                    }
                }
            },
            .expr => |expr| {
                // Determine format specifier based on inferred type
                const expr_type = try self.type_inferrer.inferExpr(expr.*);
                const format_spec = switch (expr_type) {
                    .int => "d",
                    .float => "e",
                    .string => "s",
                    .bool => "any",
                    else => "any",
                };

                try format_buf.writer(self.allocator).print("{{{s}}}", .{format_spec});

                // Generate expression code and capture it
                const saved_output = self.output;
                self.output = std.ArrayList(u8){};

                try genExpr(self, expr.*);
                const expr_code = try self.output.toOwnedSlice(self.allocator);
                try args_list.append(self.allocator, expr_code);

                self.output = saved_output;
            },
            .format_expr => |fe| {
                // Convert Python format spec to Zig format spec
                const zig_spec = try convertFormatSpec(self.allocator, fe.format_spec);
                defer self.allocator.free(zig_spec);

                try format_buf.writer(self.allocator).print("{{{s}}}", .{zig_spec});

                // Generate expression code
                const saved_output = self.output;
                self.output = std.ArrayList(u8){};

                // Handle conversion specifier (!r, !s, !a)
                // For now, all conversions just pass the value - repr/str/ascii are TODO
                if (fe.conversion) |_| {
                    try genExpr(self, fe.expr.*);
                } else {
                    try genExpr(self, fe.expr.*);
                }
                const expr_code = try self.output.toOwnedSlice(self.allocator);
                try args_list.append(self.allocator, expr_code);

                self.output = saved_output;
            },
            .conv_expr => |ce| {
                // Expression with conversion but no format spec
                const expr_type = try self.type_inferrer.inferExpr(ce.expr.*);
                const format_spec = switch (expr_type) {
                    .int => "d",
                    .float => "e",
                    .string => "s",
                    .bool => "any",
                    else => "any",
                };

                try format_buf.writer(self.allocator).print("{{{s}}}", .{format_spec});

                // Generate expression code
                const saved_output = self.output;
                self.output = std.ArrayList(u8){};

                // Handle conversion specifier (!r, !s, !a)
                // For now, all conversions just pass the value - repr/str/ascii are TODO
                try genExpr(self, ce.expr.*);
                const expr_code = try self.output.toOwnedSlice(self.allocator);
                try args_list.append(self.allocator, expr_code);

                self.output = saved_output;
            },
        }
    }

    // Build args tuple string
    var args_buf = std.ArrayList(u8){};
    defer args_buf.deinit(self.allocator);

    for (args_list.items, 0..) |arg, i| {
        if (i > 0) try args_buf.appendSlice(self.allocator, ", ");
        try args_buf.appendSlice(self.allocator, arg);
    }

    // Generate std.fmt.allocPrint call wrapped in a comptime or runtime block
    try self.output.writer(self.allocator).print(
        "(try std.fmt.allocPrint(__global_allocator, \"{s}\", .{{ {s} }}))",
        .{ format_buf.items, args_buf.items },
    );
}
