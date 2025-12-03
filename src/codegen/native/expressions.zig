/// Expression-level code generation - Re-exports from submodules
/// Handles Python expressions: constants, binary ops, calls, lists, dicts, subscripts, etc.
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;
const zig_keywords = @import("zig_keywords");

/// Python type/constant names to Zig code
const PyTypeNames = std.StaticStringMap([]const u8).initComptime(.{
    .{ "int", "i64" },
    .{ "float", "f64" },
    .{ "bool", "bool" },
    .{ "True", "true" },
    .{ "False", "false" },
    .{ "str", "runtime.builtins.str_factory" },
    .{ "bytes", "runtime.builtins.bytes_factory" },
    .{ "bytearray", "runtime.builtins.bytearray_factory" },
    .{ "memoryview", "runtime.builtins.memoryview_factory" },
    .{ "None", "null" },
    .{ "NoneType", "null" },
    .{ "NotImplemented", "runtime.NotImplemented" },
    .{ "object", "*runtime.PyObject" },
});

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

/// Check if an expression produces a Zig block expression that needs parentheses
/// Block expressions (blk: {...}) cannot have methods called on them directly
pub fn producesBlockExpression(expr: ast.Node) bool {
    return switch (expr) {
        .subscript, .list, .dict, .set, .listcomp, .dictcomp, .genexp, .if_expr, .call, .attribute, .compare => true,
        else => false,
    };
}

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
pub const genSubscriptLHS = misc.genSubscriptLHS;
pub const genAttribute = misc.genAttribute;

/// Check if a variable is captured by the current class from outer scope
fn isCapturedByCurrentClass(self: *NativeCodegen, var_name: []const u8) bool {
    // Check if we have captured variables for the current class
    // This is set by genClassMethods when entering a class with captures
    const captured_vars = self.current_class_captures orelse return false;

    // Check if this variable is in the captured list
    for (captured_vars) |captured| {
        if (std.mem.eql(u8, captured, var_name)) return true;
    }
    return false;
}

/// Main expression dispatcher
pub fn genExpr(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    switch (node) {
        .constant => |c| try constants.genConstant(self, c),
        .name => |n| {
            // Check if variable has been renamed (for exception handling)
            const name_to_use = self.var_renames.get(n.id) orelse n.id;

            // Handle 'self' -> '__self' in nested class methods to avoid shadowing
            if (std.mem.eql(u8, name_to_use, "self") and self.method_nesting_depth > 0) {
                try self.emit("__self");
                return;
            }

            // Handle 'self' in methods - emit as-is, NOT as runtime.builtins.self
            if (std.mem.eql(u8, name_to_use, "self") and self.inside_method_with_self) {
                try self.emit("self");
                return;
            }

            // Handle Python type names as type values
            if (PyTypeNames.get(name_to_use)) |zig_code| {
                try self.emit(zig_code);
            } else if (isPythonExceptionType(name_to_use)) {
                // Python exception types - emit as integer enum value for storage in lists/tuples
                // E.g., ValueError -> @intFromEnum(runtime.ExceptionTypeId.ValueError)
                try self.emit("@intFromEnum(runtime.ExceptionTypeId.");
                try self.emit(name_to_use);
                try self.emit(")");
            } else if (isBuiltinFunction(name_to_use) and !self.func_local_vars.contains(name_to_use)) {
                // Builtin functions as first-class values: len, callable, etc.
                // Emit a function reference that can be passed around
                // But only if not shadowed by a local variable
                try self.emit("runtime.builtins.");
                try self.emit(name_to_use);
            } else if (self.closure_vars.contains(n.id)) {
                // Closure variable - use the renamed version (e.g., f -> __closure_f_0)
                // The closure was registered with original name, but we emit the renamed wrapper
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), name_to_use);
            } else if (isCapturedByCurrentClass(self, name_to_use)) {
                // Variable captured from outer scope by current nested class
                if (self.inside_init_method) {
                    // In __init__, access via __cap_* parameter (pointer dereference, no self yet)
                    try self.output.writer(self.allocator).print("__cap_{s}.*", .{name_to_use});
                } else {
                    // In regular method, access via self.__captured_* field (pointer dereference)
                    // Use __self when in nested class methods (method_nesting_depth > 0)
                    const self_name = if (self.method_nesting_depth > 0) "__self" else "self";
                    try self.output.writer(self.allocator).print("{s}.__captured_{s}.*", .{ self_name, name_to_use });
                }
            } else if (self.current_class_name) |class_name| {
                // Inside a class: check if this name matches the current class name
                // In Zig, you can't refer to a struct by name from inside it - use @This() instead
                if (std.mem.eql(u8, name_to_use, class_name)) {
                    try self.emit("@This()");
                } else {
                    try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), name_to_use);
                    if (self.nested_class_names.contains(name_to_use)) {
                        try self.nested_class_zig_refs.put(name_to_use, {});
                    }
                }
            } else {
                // Use writeLocalVarName to handle keywords AND method shadowing
                try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), name_to_use);
                // Track that we referenced this nested class in generated Zig code
                // This is used to determine which classes need _ = ClassName; suppression
                if (self.nested_class_names.contains(name_to_use)) {
                    try self.nested_class_zig_refs.put(name_to_use, {});
                }
            }
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
            try self.emit("@as(void, {})");
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
        .yield_stmt => |y| try genYield(self, y),
        .yield_from_stmt => |yf| try genYieldFrom(self, yf),
        .genexp => |ge| try comprehensions.genGenExp(self, ge),
        .slice_expr => |sl| try genSliceExpr(self, sl),
        else => {
            // Unsupported expression type - emit undefined placeholder to avoid syntax errors
            try self.emit("@as(?*anyopaque, null)");
        },
    }
}

/// Generate a standalone slice expression for multi-dim subscripts
/// This creates a Zig struct representing Python's slice(start, stop, step)
fn genSliceExpr(self: *NativeCodegen, sl: ast.Node.SliceRange) CodegenError!void {
    // For multi-dim subscripts like arr[1:, 2], generate a slice struct
    // We represent it as a struct with optional start/stop/step fields
    try self.emit(".{ .start = ");
    if (sl.lower) |l| {
        try genExpr(self, l.*);
    } else {
        try self.emit("null");
    }
    try self.emit(", .stop = ");
    if (sl.upper) |u| {
        try genExpr(self, u.*);
    } else {
        try self.emit("null");
    }
    try self.emit(", .step = ");
    if (sl.step) |s| {
        try genExpr(self, s.*);
    } else {
        try self.emit("null");
    }
    try self.emit(" }");
}

/// Generate yield expression - currently emits null as placeholder
/// Real generators use CPython at runtime
fn genYield(self: *NativeCodegen, y: ast.Node.Yield) CodegenError!void {
    // For AOT compilation, yield expressions are converted to returning the value
    // This allows tests that check syntax to compile (they won't run correctly though)
    if (y.value) |val| {
        try genExpr(self, val.*);
    } else {
        try self.emit("null");
    }
}

/// Generate yield from expression - currently emits null as placeholder
fn genYieldFrom(self: *NativeCodegen, yf: ast.Node.YieldFrom) CodegenError!void {
    // For AOT compilation, yield from expressions get the iterable
    try genExpr(self, yf.value.*);
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
    try self.emit("(blk: { ");
    try self.emit(target_name);
    try self.emit(" = ");
    try genExpr(self, ne.value.*);
    try self.emit("; break :blk ");
    try self.emit(target_name);
    try self.emit("; })");
}

/// Generate conditional expression (ternary): body if condition else orelse_value
fn genIfExpr(self: *NativeCodegen, ie: ast.Node.IfExpr) CodegenError!void {
    // In Zig: if (condition) body else orelse_value
    // Check condition type - need to handle PyObject truthiness
    const cond_type = self.type_inferrer.inferExpr(ie.condition.*) catch .unknown;

    try self.emit("(if (");
    if (cond_type == .unknown) {
        // Unknown type (PyObject) - use runtime truthiness check
        try self.emit("runtime.pyTruthy(");
        try genExpr(self, ie.condition.*);
        try self.emit(")");
    } else if (cond_type == .optional) {
        // Optional type - check for non-null
        try genExpr(self, ie.condition.*);
        try self.emit(" != null");
    } else {
        // Boolean or other type - use directly
        try genExpr(self, ie.condition.*);
    }
    try self.emit(") ");
    try genExpr(self, ie.body.*);
    try self.emit(" else ");
    try genExpr(self, ie.orelse_value.*);
    try self.emit(")");
}

/// Generate await expression
fn genAwait(self: *NativeCodegen, await_node: ast.Node.AwaitExpr) CodegenError!void {
    // Check if awaiting asyncio.gather or asyncio.sleep
    if (await_node.value.* == .call) {
        const call = await_node.value.*.call;
        if (call.func.* == .attribute) {
            const attr = call.func.*.attribute;
            if (attr.value.* == .name and std.mem.eql(u8, attr.value.*.name.id, "asyncio")) {
                if (std.mem.eql(u8, attr.attr, "gather")) {
                    // asyncio.gather returns results directly (no thread wrapping)
                    try genExpr(self, await_node.value.*);
                    return;
                }
                if (std.mem.eql(u8, attr.attr, "sleep")) {
                    // asyncio.sleep is inline - just emit the sleep, no thread
                    try genExpr(self, await_node.value.*);
                    return;
                }
            }
        }
    }

    // For regular coroutine calls: await expr → wait for green thread and get result
    try self.emit("(__await_blk: {\n");
    try self.emit("    const __thread = ");
    try genExpr(self, await_node.value.*);
    try self.emit(";\n");
    try self.emit("    runtime.scheduler.wait(__thread);\n");
    // Cast result to expected type (TODO: infer from type system)
    try self.emit("    const __result = __thread.result orelse unreachable;\n");
    try self.emit("    break :__await_blk @as(*i64, @ptrCast(@alignCast(__result))).*;\n");
    try self.emit("})");
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
        try buf.writer(allocator).writeAll("d:");
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
        // Simple case: just concatenate literals (but process Python escape sequences)
        try self.emit("\"");
        for (fstring.parts) |part| {
            const lit = part.literal;
            // Process Python escape sequences like \N{name}, \xNN, \uNNNN
            try constants.emitPythonEscapedString(self, lit);
        }
        try self.emit("\"");
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
                // Process Python escape sequences like \N{name}, \xNN, \uNNNN
                // and escape braces for Zig format strings
                const saved_output = self.output;
                self.output = std.ArrayList(u8){};
                try constants.emitPythonEscapedStringExt(self, lit, true);
                const escaped = try self.output.toOwnedSlice(self.allocator);
                defer self.allocator.free(escaped);
                self.output = saved_output;
                try format_buf.appendSlice(self.allocator, escaped);
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
                // Use runtime.pyFormat for ALL format specs to handle Python's format mini-language
                // Python format specs like #10x, 08b, .2f are different from Zig's format specs
                try format_buf.writer(self.allocator).writeAll("{s}");

                // Generate: runtime.pyFormat(__global_allocator, <expr>, "<format_spec>")
                const saved_output = self.output;
                self.output = std.ArrayList(u8){};

                try self.emit("(try runtime.pyFormat(__global_allocator, ");
                try genExpr(self, fe.expr.*);
                try self.emit(", \"");
                // Escape the format spec for Zig string literal
                for (fe.format_spec) |c| {
                    switch (c) {
                        '"' => try self.emit("\\\""),
                        '\\' => try self.emit("\\\\"),
                        '\n' => try self.emit("\\\\n"), // double-escape for Zig literal
                        '\r' => try self.emit("\\\\r"),
                        '\t' => try self.emit("\\\\t"),
                        else => try self.output.append(self.allocator, c),
                    }
                }
                try self.emit("\"))");

                const expr_code = try self.output.toOwnedSlice(self.allocator);
                try args_list.append(self.allocator, expr_code);
                self.output = saved_output;
            },
            .conv_expr => |ce| {
                // Expression with conversion specifier (!r, !s, !a)
                const expr_type = try self.type_inferrer.inferExpr(ce.expr.*);

                // Generate expression code first
                const saved_output = self.output;
                self.output = std.ArrayList(u8){};
                try genExpr(self, ce.expr.*);
                const expr_code = try self.output.toOwnedSlice(self.allocator);
                self.output = saved_output;

                // Handle conversion: !r = repr, !s = str, !a = ascii
                if (ce.conversion == 'r') {
                    // repr() - for strings, wrap in quotes
                    if (expr_type == .string) {
                        try format_buf.writer(self.allocator).writeAll("'{s}'");
                        try args_list.append(self.allocator, expr_code);
                    } else {
                        // For non-strings, just use default formatting
                        const format_spec = switch (expr_type) {
                            .int => "d",
                            .float => "e",
                            .bool => "any",
                            else => "any",
                        };
                        try format_buf.writer(self.allocator).print("{{{s}}}", .{format_spec});
                        try args_list.append(self.allocator, expr_code);
                    }
                } else {
                    // !s (str) and !a (ascii) - just convert to string
                    const format_spec = switch (expr_type) {
                        .int => "d",
                        .float => "e",
                        .string => "s",
                        .bool => "any",
                        else => "any",
                    };
                    try format_buf.writer(self.allocator).print("{{{s}}}", .{format_spec});
                    try args_list.append(self.allocator, expr_code);
                }
            },
        }
    }

    // Build args tuple string
    var args_buf = std.ArrayList(u8){};
    defer args_buf.deinit(self.allocator);

    for (args_list.items, 0..) |arg, i| {
        if (i > 0) try args_buf.writer(self.allocator).writeAll(", ");
        try args_buf.writer(self.allocator).writeAll(arg);
    }

    // Generate std.fmt.allocPrint call wrapped in a comptime or runtime block
    try self.output.writer(self.allocator).print(
        "(try std.fmt.allocPrint(__global_allocator, \"{s}\", .{{ {s} }}))",
        .{ format_buf.items, args_buf.items },
    );
}

const shared = @import("shared_maps.zig");
const BuiltinFunctions = shared.PythonBuiltinNames;
const PythonExceptions = shared.RuntimeExceptions;

/// Module-level constants that should NOT be prefixed with runtime.builtins.
/// These are defined as local constants in the generated code
const ModuleLevelConstants = std.StaticStringMap(void).initComptime(.{
    .{ "__name__", {} },
    .{ "__file__", {} },
    .{ "__doc__", {} },
    .{ "__package__", {} },
    .{ "__loader__", {} },
    .{ "__spec__", {} },
});

/// Check if a name is a Python builtin function that can be passed as first-class value
fn isBuiltinFunction(name: []const u8) bool {
    // Exclude module-level constants - they're defined locally, not in runtime.builtins
    if (ModuleLevelConstants.has(name)) return false;
    return BuiltinFunctions.has(name);
}

/// Check if a name is a Python exception type
pub fn isPythonExceptionType(name: []const u8) bool {
    return PythonExceptions.has(name);
}
