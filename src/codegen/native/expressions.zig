/// Expression-level code generation - Re-exports from submodules
/// Handles Python expressions: constants, binary ops, calls, lists, dicts, subscripts, etc.
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;
const zig_keywords = @import("utils.zig_keywords");
const type_traits = @import("../../analysis/traits/type_traits.zig");
const string_traits = @import("../../analysis/traits/string_traits.zig");
const container_traits = @import("../../analysis/traits/container_traits.zig");

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
pub fn isCapturedByCurrentClass(self: *NativeCodegen, var_name: []const u8) bool {
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
            // Resolve the name to use, with proper scoping rules:
            // 1. Check hoisted_local_classes first (locally-defined classes hoisted to struct level)
            // 2. Check var_renames for comprehension loop variables (__comp_*) - these MUST shadow
            //    local variables due to Python 3 comprehension scope isolation
            // 3. Don't apply OTHER var_renames to local variables/parameters - they take precedence
            //    over class attribute lazy patterns from outer scopes
            // 4. Check var_renames for transformed names (class attributes, shadows, etc.)
            const name_to_use = blk: {
                if (self.hoisted_local_classes.get(n.id)) |hoisted| break :blk hoisted;
                // Comprehension loop variables (__comp_*) MUST shadow local vars (Python 3 scope isolation)
                if (self.var_renames.get(n.id)) |renamed| {
                    if (std.mem.startsWith(u8, renamed, "__comp_")) break :blk renamed;
                }
                // Local vars/params take precedence - don't rename them with class attribute patterns
                if (self.func_local_vars.contains(n.id)) break :blk n.id;
                if (self.var_renames.get(n.id)) |renamed| break :blk renamed;
                break :blk n.id;
            };

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

            // Handle 'cls' in metaclass instance methods - 'cls' is the first param (like 'self')
            // In metaclass methods, 'cls' maps to 'self'/'__self' in Zig
            // IMPORTANT: Only do this if 'cls' is actually the first parameter name,
            // not just a local variable named 'cls' (e.g., in __new__ methods)
            if (std.mem.eql(u8, name_to_use, "cls") and self.inside_method_with_self) {
                // Check if 'cls' is actually the first parameter name for this method
                const is_first_param = if (self.current_method_first_param) |fp|
                    std.mem.eql(u8, fp, "cls")
                else
                    false;

                if (is_first_param) {
                    if (self.method_nesting_depth > 0) {
                        try self.emit("__self");
                    } else {
                        try self.emit("self");
                    }
                    return;
                }
            }

            // Handle Python builtin constants
            if (std.mem.eql(u8, name_to_use, "Ellipsis")) {
                // Python Ellipsis constant - emit void value (like ellipsis_literal)
                try self.emit("@as(void, {})");
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
                } else if (self.inside_classmethod) {
                    // In classmethod (e.g., __init_subclass__), there's no self/__self instance.
                    // Access the outer scope variable directly - this works for module-level vars.
                    try zig_keywords.writeLocalVarName(self.output.writer(self.allocator), name_to_use);
                } else {
                    // In regular method, access via self.__captured_* field (pointer dereference)
                    // Use __self for regular nested methods, __cls for __new__ methods
                    const self_name = if (self.method_nesting_depth > 0)
                        (if (self.inside_new_method) "__cls" else "__self")
                    else
                        "self";
                    try self.output.writer(self.allocator).print("{s}.__captured_{s}.*", .{ self_name, name_to_use });
                }
            } else if (self.current_class_name) |class_name| {
                // Inside a class: check if this name matches the current class name
                // In Zig, you can't refer to a struct by name from inside it - use @This() instead
                if (std.mem.eql(u8, name_to_use, class_name)) {
                    try self.emit("@This()");
                } else if (std.mem.eql(u8, name_to_use, "__class__")) {
                    // Python __class__ refers to the current class - use @This() in Zig
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
        .lambda => |lam| lambda_mod.genLambda(self, lam) catch |e| switch (e) {
            error.NotAClosure => return error.UnsupportedSyntax,
            else => |err| return err,
        },
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
            // Statement node passed to expression dispatcher - this is a bug
            return error.UnsupportedSyntax;
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
        else => return error.UnsupportedSyntax, // Walrus target must be a name
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
    // Use inferExprScoped which checks local symbol table (includes function parameters)
    const cond_type = self.inferExprScoped(ie.condition.*) catch .unknown;

    // Check if condition is comptime-evaluable (determines if we need to cast branches)
    // If condition involves runtime values (function calls, runtime vars), branches must be concrete types
    const is_runtime_condition = isRuntimeCondition(ie.condition.*);

    // Check if both branches are integer constants - need to cast to i64 for runtime conditions
    const body_is_int = ie.body.* == .constant and ie.body.constant.value == .int;
    const orelse_is_int = ie.orelse_value.* == .constant and ie.orelse_value.constant.value == .int;
    const needs_int_cast = is_runtime_condition and body_is_int and orelse_is_int;

    // Check if condition is a boolop or compare - these always generate bool result
    const cond_is_boolop = ie.condition.* == .boolop;
    const cond_is_compare = ie.condition.* == .compare;

    try self.emit("(if (");
    if (cond_is_boolop or cond_is_compare) {
        // Boolean operations and comparisons generate bool directly, use as-is
        try genExpr(self, ie.condition.*);
    } else if (type_traits.isUnknown(cond_type) or cond_type == .pyvalue) {
        // Two-Flow: Unknown/PyValue type - use runtime truthiness check
        try self.emit("runtime.pyTruthy(");
        try genExpr(self, ie.condition.*);
        try self.emit(")");
    } else if (cond_type == .optional) {
        // Optional type - check for non-null
        try genExpr(self, ie.condition.*);
        try self.emit(" != null");
    } else if (type_traits.isIntegral(cond_type)) {
        // Integer type - Python truthiness: non-zero is true
        try self.emit("(");
        try genExpr(self, ie.condition.*);
        try self.emit(") != 0");
    } else if (type_traits.isFloating(cond_type)) {
        // Float type - Python truthiness: non-zero is true
        try self.emit("(");
        try genExpr(self, ie.condition.*);
        try self.emit(") != 0.0");
    } else if (string_traits.isString(cond_type)) {
        // String type - Python truthiness: non-empty is true
        try self.emit("(");
        try genExpr(self, ie.condition.*);
        try self.emit(").len != 0");
    } else if (container_traits.isList(cond_type)) {
        // List type - Python truthiness: non-empty is true
        try self.emit("(");
        try genExpr(self, ie.condition.*);
        try self.emit(").items.len != 0");
    } else if (container_traits.isDict(cond_type)) {
        // Dict type - Python truthiness: non-empty is true
        try self.emit("(");
        try genExpr(self, ie.condition.*);
        try self.emit(").count() != 0");
    } else if (container_traits.isSet(cond_type)) {
        // Set type - Python truthiness: non-empty is true
        try self.emit("(");
        try genExpr(self, ie.condition.*);
        try self.emit(").count() != 0");
    } else if (container_traits.isTuple(cond_type)) {
        // Tuple type - Python truthiness: non-empty is true
        try self.emit("@typeInfo(@TypeOf(");
        try genExpr(self, ie.condition.*);
        try self.emit(")).@\"struct\".fields.len != 0");
    } else if (string_traits.isBytes(cond_type)) {
        // Bytes type - Python truthiness: non-empty is true
        try self.emit("(");
        try genExpr(self, ie.condition.*);
        try self.emit(").len != 0");
    } else {
        // Boolean or other type - use directly
        try genExpr(self, ie.condition.*);
    }
    try self.emit(") ");
    if (needs_int_cast) try self.emit("@as(i64, ");
    try genExpr(self, ie.body.*);
    if (needs_int_cast) try self.emit(")");
    try self.emit(" else ");
    if (needs_int_cast) try self.emit("@as(i64, ");
    try genExpr(self, ie.orelse_value.*);
    if (needs_int_cast) try self.emit(")");
    try self.emit(")");
}

/// Check if an expression involves runtime values (not comptime-evaluable)
fn isRuntimeCondition(expr: ast.Node) bool {
    return switch (expr) {
        // Constants are comptime
        .constant => false,
        // Names could be either - assume runtime for safety
        .name => true,
        // Calls are runtime (function calls, method calls)
        .call => true,
        // Binary ops with any runtime operand are runtime
        .binop => |b| isRuntimeCondition(b.left.*) or isRuntimeCondition(b.right.*),
        // Unary ops inherit from operand
        .unaryop => |u| isRuntimeCondition(u.operand.*),
        // Comparisons with any runtime operand are runtime
        .compare => |c| blk: {
            if (isRuntimeCondition(c.left.*)) break :blk true;
            for (c.comparators) |cmp| {
                if (isRuntimeCondition(cmp)) break :blk true;
            }
            break :blk false;
        },
        // Boolean ops (and/or) are runtime if any operand is
        .boolop => |b| blk: {
            for (b.values) |v| {
                if (isRuntimeCondition(v)) break :blk true;
            }
            break :blk false;
        },
        // Everything else: assume runtime for safety
        else => true,
    };
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

    // Infer the return type of the awaited coroutine
    // Default to i64, but try to infer actual type from call expression
    var result_type: []const u8 = "i64";
    if (await_node.value.* == .call) {
        const call = await_node.value.*.call;
        // Get function name to look up return type
        if (call.func.* == .name) {
            const func_name = call.func.*.name.id;
            if (self.type_inferrer.func_return_types.get(func_name)) |ret_type| {
                var type_buf = std.ArrayList(u8){};
                defer type_buf.deinit(self.allocator);
                ret_type.toZigType(self.allocator, &type_buf) catch {};
                if (type_buf.items.len > 0) {
                    result_type = self.arena.allocator().dupe(u8, type_buf.items) catch "i64";
                }
            }
        }
    }

    // For regular coroutine calls: await expr → wait for green thread and get result
    try self.emit("(__await_blk: {\n");
    try self.emit("    const __thread = ");
    try genExpr(self, await_node.value.*);
    try self.emit(";\n");
    try self.emit("    runtime.scheduler.?.wait(__thread);\n");
    try self.emit("    const __result = __thread.result orelse unreachable;\n");
    try self.output.writer(self.allocator).print("    break :__await_blk @as(*{s}, @ptrCast(@alignCast(__result))).*;\n", .{result_type});
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

/// Escape special characters for Zig string literals
/// Handles double quotes, backslashes, and braces (for format strings)
fn escapeForZigString(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, input: []const u8) !void {
    for (input) |c| {
        switch (c) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            '{' => try buf.appendSlice(allocator, "{{"),
            '}' => try buf.appendSlice(allocator, "}}"),
            else => try buf.append(allocator, c),
        }
    }
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
            .expr => |e| {
                // Prepend debug_text (e.g., "x=") if present for f"{x=}"
                if (e.debug_text) |dbg| {
                    // Escape special chars for Zig string literal
                    try escapeForZigString(&format_buf, self.allocator, dbg);
                }

                // Determine format specifier based on inferred type
                const expr_type = try self.type_inferrer.inferExpr(e.node.*);
                const format_spec = switch (expr_type) {
                    .int => "d",
                    .float => "d",
                    .string => "s",
                    .bool => "any",
                    else => "any",
                };

                try format_buf.writer(self.allocator).print("{{{s}}}", .{format_spec});

                // Generate expression code and capture it
                const saved_output = self.output;
                self.output = std.ArrayList(u8){};

                try genExpr(self, e.node.*);
                const expr_code = try self.output.toOwnedSlice(self.allocator);
                try args_list.append(self.allocator, expr_code);

                self.output = saved_output;
            },
            .format_expr => |fe| {
                // Prepend debug_text (e.g., "x=") if present for f"{x=:...}"
                if (fe.debug_text) |dbg| {
                    // Escape special chars for Zig string literal
                    try escapeForZigString(&format_buf, self.allocator, dbg);
                }

                // Use runtime.pyFormat for ALL format specs to handle Python's format mini-language
                // Python format specs like #10x, 08b, .2f are different from Zig's format specs
                try format_buf.writer(self.allocator).writeAll("{s}");

                // Generate: runtime.pyFormat(__global_allocator, <expr>, "<format_spec>")
                const saved_output = self.output;
                self.output = std.ArrayList(u8){};

                try self.emit("(try runtime.pyFormat(__global_allocator, ");
                try genExpr(self, fe.expr.*);
                try self.emit(", ");

                // Check if format spec has nested expressions (PEP 701)
                if (fe.format_spec_parts) |spec_parts| {
                    // Build format spec dynamically from parts
                    // We need to use type-appropriate format specifiers
                    try self.emit("(try std.fmt.allocPrint(__global_allocator, \"");
                    // Build format string for the parts with type-aware specifiers
                    for (spec_parts) |spec_part| {
                        switch (spec_part) {
                            .literal => |lit| {
                                for (lit) |c| {
                                    switch (c) {
                                        '"' => try self.emit("\\\""),
                                        '\\' => try self.emit("\\\\"),
                                        '{' => try self.emit("{{"),
                                        '}' => try self.emit("}}"),
                                        else => try self.output.append(self.allocator, c),
                                    }
                                }
                            },
                            .expr => |e| {
                                // Determine format specifier based on expression type
                                const expr_type = try self.type_inferrer.inferExpr(e.*);
                                switch (expr_type) {
                                    .string => try self.emit("{s}"),
                                    .int => try self.emit("{d}"),
                                    .float => try self.emit("{d}"),
                                    else => try self.emit("{any}"),
                                }
                            },
                        }
                    }
                    try self.emit("\", .{");
                    // Now generate the expression values
                    var first = true;
                    for (spec_parts) |spec_part| {
                        switch (spec_part) {
                            .literal => {},
                            .expr => |e| {
                                if (!first) try self.emit(", ");
                                first = false;
                                try genExpr(self, e.*);
                            },
                        }
                    }
                    try self.emit("}))");
                } else {
                    // Simple format spec - use literal string
                    try self.emit("\"");
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
                    try self.emit("\"");
                }
                try self.emit("))");

                const expr_code = try self.output.toOwnedSlice(self.allocator);
                try args_list.append(self.allocator, expr_code);
                self.output = saved_output;
            },
            .conv_expr => |ce| {
                // Prepend debug_text (e.g., "x=") if present for f"{x=!r}"
                if (ce.debug_text) |dbg| {
                    // Escape special chars for Zig string literal
                    try escapeForZigString(&format_buf, self.allocator, dbg);
                }

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
                    if (string_traits.isString(expr_type)) {
                        try format_buf.writer(self.allocator).writeAll("'{s}'");
                        try args_list.append(self.allocator, expr_code);
                    } else {
                        // For non-strings, just use default formatting
                        const format_spec = switch (expr_type) {
                            .int => "d",
                            .float => "d",
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
                        .float => "d",
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
