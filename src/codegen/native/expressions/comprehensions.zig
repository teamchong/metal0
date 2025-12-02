/// List and dict comprehension code generation
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const hashmap_helper = @import("hashmap_helper");

/// Builtins that return int for type inference
const IntReturningBuiltins = std.StaticStringMap(void).initComptime(.{
    .{ "len", {} }, .{ "int", {} }, .{ "ord", {} },
});

/// Builtins that return bool for type inference
const BoolReturningBuiltins = std.StaticStringMap(void).initComptime(.{
    .{ "isinstance", {} }, .{ "callable", {} }, .{ "hasattr", {} }, .{ "bool", {} },
});

/// Generate expression with variable substitutions for comprehensions
fn genExprWithSubs(
    self: *NativeCodegen,
    expr: ast.Node,
    subs: *const hashmap_helper.StringHashMap([]const u8),
) CodegenError!void {
    switch (expr) {
        .name => |n| {
            // Check if this name should be substituted
            if (subs.get(n.id)) |sub_name| {
                try self.emit(sub_name);
            } else {
                try self.emit(n.id);
            }
        },
        .binop => |b| {
            try self.emit("(");
            try genExprWithSubs(self, b.left.*, subs);
            const op_str = switch (b.op) {
                .Add => " + ",
                .Sub => " - ",
                .Mult => " * ",
                .Div => " / ",
                .Mod => " % ",
                .Pow => " ** ",
                .BitAnd => " & ",
                .BitOr => " | ",
                .BitXor => " ^ ",
                .LShift => " << ",
                .RShift => " >> ",
                .FloorDiv => " / ",
                else => " ? ",
            };
            try self.emit(op_str);
            try genExprWithSubs(self, b.right.*, subs);
            try self.emit(")");
        },
        .constant => |c| {
            switch (c.value) {
                .int => |i| try self.output.writer(self.allocator).print("{d}", .{i}),
                .bigint => |s| try self.output.writer(self.allocator).print("(try runtime.parseIntToBigInt(__global_allocator, \"{s}\", 10))", .{s}),
                .float => |f| try self.output.writer(self.allocator).print("{d}", .{f}),
                .string => |s| {
                    try self.emit("\"");
                    try self.emit(s);
                    try self.emit("\"");
                },
                .bytes => |s| {
                    try self.emit("\"");
                    try self.emit(s);
                    try self.emit("\"");
                },
                .bool => |b| try self.emit(if (b) "true" else "false"),
                .none => try self.emit("null"),
                .complex => |imag| try self.output.writer(self.allocator).print("runtime.PyComplex.create(0.0, {d})", .{imag}),
            }
        },
        .call => |c| {
            // Handle call expressions with substitution for arguments
            // Check if calling an async function - needs _async suffix and try
            if (c.func.* == .name) {
                const func_name = c.func.name.id;
                if (self.async_functions.contains(func_name)) {
                    // Async function call in comprehension
                    try self.emit("try ");
                    try self.emit(func_name);
                    try self.emit("_async(");
                    for (c.args, 0..) |arg, i| {
                        if (i > 0) try self.emit(", ");
                        try genExprWithSubs(self, arg, subs);
                    }
                    try self.emit(")");
                    return;
                }
            }
            // Regular function call
            const parent = @import("../expressions.zig");
            // Generate function part
            try parent.genExpr(self, c.func.*);
            try self.emit("(");
            // Generate arguments with substitution
            for (c.args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try genExprWithSubs(self, arg, subs);
            }
            try self.emit(")");
        },
        .list => |l| {
            // Handle list literals with substitution
            // Python: [x] in comprehension element -> generate inline array or ArrayList
            // For single-element lists like bytes([x]), generate Zig array: &[_]u8{x}
            try self.emit("list_");
            const list_id = self.output.items.len;
            try self.output.writer(self.allocator).print("{d}: {{\n", .{list_id});
            self.indent();
            try self.emitIndent();
            try self.emit("var _list = std.ArrayList(i64){};\n");
            for (l.elts) |elt| {
                try self.emitIndent();
                try self.emit("try _list.append(__global_allocator, ");
                try genExprWithSubs(self, elt, subs);
                try self.emit(");\n");
            }
            try self.emitIndent();
            try self.output.writer(self.allocator).print("break :list_{d} _list;\n", .{list_id});
            self.dedent();
            try self.emitIndent();
            try self.emit("}");
        },
        else => {
            // For other expressions, fallback to regular genExpr
            const parent = @import("../expressions.zig");
            try parent.genExpr(self, expr);
        },
    }
}

/// Generate list comprehension: [x * 2 for x in range(5)]
/// Generates as imperative loop that builds ArrayList
pub fn genListComp(self: *NativeCodegen, listcomp: ast.Node.ListComp) CodegenError!void {
    // Forward declare genExpr - it's in parent module
    const parent = @import("../expressions.zig");
    const genExpr = parent.genExpr;

    // Generate unique ID for this comprehension to avoid variable shadowing
    const comp_id = self.output.items.len;

    // Get unique block label to avoid nested block conflicts
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Build variable substitution map for this comprehension
    var subs = hashmap_helper.StringHashMap([]const u8).init(self.allocator);
    defer subs.deinit();

    // Generate: comp_N: { ... }
    try self.emit(try std.fmt.allocPrint(self.allocator, "comp_{d}: {{\n", .{label_id}));
    self.indent();

    // Determine element type - check if element is an async function call
    const element_type: []const u8 = blk: {
        if (listcomp.elt.* == .call) {
            const call = listcomp.elt.call;
            if (call.func.* == .name) {
                const func_name = call.func.name.id;
                if (self.async_functions.contains(func_name)) {
                    break :blk "*runtime.GreenThread";
                }
            }
        }
        break :blk "i64";
    };

    // Generate: var __comp_result = std.ArrayList(ElementType){};
    try self.emitIndent();
    try self.emit("var __comp_result = std.ArrayList(");
    try self.emit(element_type);
    try self.emit("){};\n");

    // Generate nested loops for each generator
    for (listcomp.generators, 0..) |gen, gen_idx| {
        // Check if this is a range() call
        const is_range = gen.iter.* == .call and gen.iter.call.func.* == .name and
            std.mem.eql(u8, gen.iter.call.func.name.id, "range");

        if (is_range) {
            // Generate range loop as while loop
            // Use unique mangled name to avoid shadowing outer variables
            const orig_var_name = gen.target.name.id;
            const args = gen.iter.call.args;

            // Create mangled name and add to substitution map
            const mangled_name = try std.fmt.allocPrint(self.allocator, "__comp_{s}_{d}", .{ orig_var_name, comp_id });
            try subs.put(orig_var_name, mangled_name);

            // Parse range arguments - handle both constants and variable expressions
            const start_expr: ?ast.Node = if (args.len >= 2) args[0] else null;
            const stop_expr: ast.Node = if (args.len >= 2) args[1] else args[0];
            const step_val: i64 = 1;

            // Generate: var __comp_<orig>_<id>: i64 = <start>;
            try self.emitIndent();
            try self.output.writer(self.allocator).print("var {s}: i64 = ", .{mangled_name});
            if (start_expr) |start| {
                try genExpr(self, start);
            } else {
                try self.emit("0");
            }
            try self.emit(";\n");

            // Generate: while (__comp_<orig>_<id> < <stop>) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("while ({s} < ", .{mangled_name});
            try genExpr(self, stop_expr);
            try self.emit(") {\n");
            self.indent();

            // Defer increment: defer __comp_<orig>_<id> += <step>;
            try self.emitIndent();
            try self.output.writer(self.allocator).print("defer {s} += {d};\n", .{ mangled_name, step_val });
        } else {
            // Regular iteration - check if source is constant array, ArrayList, or anytype param
            const is_direct_iterable = blk: {
                // String literals are directly iterable (they're Zig arrays)
                if (gen.iter.* == .constant) {
                    if (gen.iter.constant.value == .string) break :blk true;
                }
                if (gen.iter.* == .name) {
                    const var_name = gen.iter.name.id;
                    // Const array variables can be iterated directly
                    if (self.isArrayVar(var_name)) break :blk true;
                    // anytype parameters should also be iterated directly (no .items)
                    if (self.anytype_params.contains(var_name)) break :blk true;
                    // String variables are directly iterable
                    if (self.getVarType(var_name)) |vt| {
                        if (vt == .string) break :blk true;
                    }
                }
                break :blk false;
            };

            try self.emitIndent();
            if (is_direct_iterable) {
                // Constant array variable, string literal, or anytype param - iterate directly
                try self.output.writer(self.allocator).print("const __iter_{d} = ", .{gen_idx});
                try genExpr(self, gen.iter.*);
                try self.emit(";\n");
            } else {
                // ArrayList - use .items
                // First emit the list to an intermediate variable, then access .items
                try self.output.writer(self.allocator).print("const __list_{d} = ", .{gen_idx});
                try genExpr(self, gen.iter.*);
                try self.emit(";\n");
                try self.emitIndent();
                try self.output.writer(self.allocator).print("const __iter_{d} = __list_{d}.items;\n", .{ gen_idx, gen_idx });
            }

            try self.emitIndent();
            // Check if target is a tuple (for tuple unpacking like `for a, b in zip(...)`)
            const is_tuple_target = switch (gen.target.*) {
                .tuple => true,
                .list => true,
                else => false,
            };
            if (is_tuple_target) {
                // Capture as single variable, unpack inside loop
                try self.output.writer(self.allocator).print("for (__iter_{d}) |__tuple_{d}__| {{\n", .{ gen_idx, gen_idx });
                self.indent();

                // Unpack tuple elements
                const elements = switch (gen.target.*) {
                    .tuple => |t| t.elts,
                    .list => |l| l.elts,
                    else => &[_]ast.Node{},
                };
                for (elements, 0..) |elt, idx| {
                    try self.emitIndent();
                    if (elt == .name) {
                        const var_name = elt.name.id;
                        // Handle underscore discard pattern
                        if (std.mem.eql(u8, var_name, "_")) {
                            try self.output.writer(self.allocator).print("_ = __tuple_{d}__.@\"{d}\";\n", .{ gen_idx, idx });
                        } else {
                            try self.output.writer(self.allocator).print("const {s} = __tuple_{d}__.@\"{d}\";\n", .{ var_name, gen_idx, idx });
                        }
                    }
                }
            } else {
                try self.output.writer(self.allocator).print("for (__iter_{d}) |", .{gen_idx});
                try genExpr(self, gen.target.*);
                try self.emit("| {\n");
                self.indent();
            }
        }

        // Generate if conditions for this generator
        for (gen.ifs) |if_cond| {
            try self.emitIndent();
            try self.emit("if (");
            try genExprWithSubs(self, if_cond, &subs);
            try self.emit(") {\n");
            self.indent();
        }
    }

    // Generate: try __comp_result.append(__global_allocator, <elt_expr>);
    try self.emitIndent();
    try self.emit("try __comp_result.append(__global_allocator, ");
    try genExprWithSubs(self, listcomp.elt.*, &subs);
    try self.emit(");\n");

    // Close all if conditions and for loops
    for (listcomp.generators) |gen| {
        // Close if conditions for this generator
        for (gen.ifs) |_| {
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
        }

        // Close for loop
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    // Generate: break :comp_N __comp_result;
    // Return the ArrayList itself (not a slice) so caller can use .items or .append
    try self.emitIndent();
    try self.emit(try std.fmt.allocPrint(self.allocator, "break :comp_{d} __comp_result;\n", .{label_id}));

    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

pub fn genDictComp(self: *NativeCodegen, dictcomp: ast.Node.DictComp) CodegenError!void {
    // Forward declare genExpr - it's in parent module
    const parent = @import("../expressions.zig");
    const genExpr = parent.genExpr;

    // Determine if key is an integer expression
    const key_is_int = isIntExpr(dictcomp.key.*);

    // Get unique block label to avoid nested block conflicts
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Generate: dict_N: { ... }
    try self.emit(try std.fmt.allocPrint(self.allocator, "dict_{d}: {{\n", .{label_id}));
    self.indent();

    // Generate HashMap instead of ArrayList for compatibility with print(dict)
    try self.emitIndent();
    if (key_is_int) {
        try self.emit("var __dict_result = std.AutoHashMap(i64, i64).init(__global_allocator);\n");
    } else {
        try self.emit("var __dict_result = hashmap_helper.StringHashMap(i64).init(__global_allocator);\n");
    }

    // Generate nested loops for each generator
    for (dictcomp.generators, 0..) |gen, gen_idx| {
        // Check if this is a range() call
        const is_range = gen.iter.* == .call and gen.iter.call.func.* == .name and
            std.mem.eql(u8, gen.iter.call.func.name.id, "range");

        if (is_range) {
            // Generate range loop as while loop
            const var_name = gen.target.name.id;
            const args = gen.iter.call.args;

            // Parse range arguments
            var start_val: i64 = 0;
            var stop_val: i64 = 0;
            const step_val: i64 = 1;

            if (args.len == 1) {
                // range(stop)
                if (args[0] == .constant and args[0].constant.value == .int) {
                    stop_val = args[0].constant.value.int;
                }
            } else if (args.len == 2) {
                // range(start, stop)
                if (args[0] == .constant and args[0].constant.value == .int) {
                    start_val = args[0].constant.value.int;
                }
                if (args[1] == .constant and args[1].constant.value == .int) {
                    stop_val = args[1].constant.value.int;
                }
            }

            // Generate: var <var_name>: i64 = <start>;
            try self.emitIndent();
            try self.output.writer(self.allocator).print("var {s}: i64 = {d};\n", .{ var_name, start_val });

            // Generate: while (<var_name> < <stop>) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("while ({s} < {d}) {{\n", .{ var_name, stop_val });
            self.indent();

            // Defer increment: defer <var_name> += <step>;
            try self.emitIndent();
            try self.output.writer(self.allocator).print("defer {s} += {d};\n", .{ var_name, step_val });
        } else {
            // Regular iteration - check if source is constant array, ArrayList, or anytype param
            const is_direct_iterable = blk: {
                // String literals are directly iterable (they're Zig arrays)
                if (gen.iter.* == .constant) {
                    if (gen.iter.constant.value == .string) break :blk true;
                }
                if (gen.iter.* == .name) {
                    const var_name_inner = gen.iter.name.id;
                    // Const array variables can be iterated directly
                    if (self.isArrayVar(var_name_inner)) break :blk true;
                    // anytype parameters should also be iterated directly (no .items)
                    if (self.anytype_params.contains(var_name_inner)) break :blk true;
                    // String variables are directly iterable
                    if (self.getVarType(var_name_inner)) |vt| {
                        if (vt == .string) break :blk true;
                    }
                }
                break :blk false;
            };

            try self.emitIndent();
            if (is_direct_iterable) {
                // Constant array variable, string literal, or anytype param - iterate directly
                try self.output.writer(self.allocator).print("const __iter_{d} = ", .{gen_idx});
                try genExpr(self, gen.iter.*);
                try self.emit(";\n");
            } else {
                // ArrayList - use .items
                // First emit the list to an intermediate variable, then access .items
                try self.output.writer(self.allocator).print("const __list_{d} = ", .{gen_idx});
                try genExpr(self, gen.iter.*);
                try self.emit(";\n");
                try self.emitIndent();
                try self.output.writer(self.allocator).print("const __iter_{d} = __list_{d}.items;\n", .{ gen_idx, gen_idx });
            }

            try self.emitIndent();
            // Check if target is a tuple (for tuple unpacking like `for a, b in zip(...)`)
            const is_tuple_target = switch (gen.target.*) {
                .tuple => true,
                .list => true,
                else => false,
            };
            if (is_tuple_target) {
                // Capture as single variable, unpack inside loop
                try self.output.writer(self.allocator).print("for (__iter_{d}) |__tuple_{d}__| {{\n", .{ gen_idx, gen_idx });
                self.indent();

                // Unpack tuple elements
                const elements = switch (gen.target.*) {
                    .tuple => |t| t.elts,
                    .list => |l| l.elts,
                    else => &[_]ast.Node{},
                };
                for (elements, 0..) |elt, idx| {
                    try self.emitIndent();
                    if (elt == .name) {
                        const var_name = elt.name.id;
                        // Handle underscore discard pattern
                        if (std.mem.eql(u8, var_name, "_")) {
                            try self.output.writer(self.allocator).print("_ = __tuple_{d}__.@\"{d}\";\n", .{ gen_idx, idx });
                        } else {
                            try self.output.writer(self.allocator).print("const {s} = __tuple_{d}__.@\"{d}\";\n", .{ var_name, gen_idx, idx });
                        }
                    }
                }
            } else {
                try self.output.writer(self.allocator).print("for (__iter_{d}) |", .{gen_idx});
                try genExpr(self, gen.target.*);
                try self.emit("| {\n");
                self.indent();
            }
        }

        // Generate if conditions for this generator
        for (gen.ifs) |if_cond| {
            try self.emitIndent();
            try self.emit("if (");
            try genExpr(self, if_cond);
            try self.emit(") {\n");
            self.indent();
        }
    }

    // Generate: try __dict_result.put(<key>, <value>);
    try self.emitIndent();
    try self.emit("try __dict_result.put(");
    try genExpr(self, dictcomp.key.*);
    try self.emit(", ");
    try genExpr(self, dictcomp.value.*);
    try self.emit(");\n");

    // Close all if conditions and for loops
    for (dictcomp.generators) |gen| {
        // Close if conditions for this generator
        for (gen.ifs) |_| {
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
        }

        // Close for loop
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    // Generate: break :dict_N __dict_result;
    try self.emitIndent();
    try self.emit(try std.fmt.allocPrint(self.allocator, "break :dict_{d} __dict_result;\n", .{label_id}));

    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate generator expression: (x * 2 for x in range(5))
/// For AOT compilation, we treat this as a list comprehension and return the list
/// (Real generators would need lazy evaluation which is complex)
pub fn genGenExp(self: *NativeCodegen, genexp: ast.Node.GenExp) CodegenError!void {
    // Forward declare genExpr - it's in parent module
    const parent = @import("../expressions.zig");
    const genExpr = parent.genExpr;

    // Get unique block label to avoid nested block conflicts
    const label_id = self.block_label_counter;
    self.block_label_counter += 1;

    // Generate: gen_N: { ... }
    try self.emit(try std.fmt.allocPrint(self.allocator, "gen_{d}: {{\n", .{label_id}));
    self.indent();

    // Determine element type from the expression being yielded
    const elem_type = getGenExpElementType(genexp.elt.*);

    // Generate: var __comp_result = std.ArrayList(<elem_type>){};
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var __comp_result = std.ArrayList({s}){{}};\n", .{elem_type});

    // Generate nested loops for each generator
    for (genexp.generators, 0..) |gen, gen_idx| {
        // Check if this is a range() call
        const is_range = gen.iter.* == .call and gen.iter.call.func.* == .name and
            std.mem.eql(u8, gen.iter.call.func.name.id, "range");

        if (is_range) {
            // Generate range loop as while loop
            const var_name = gen.target.name.id;
            const args = gen.iter.call.args;

            // Parse range arguments
            var start_val: i64 = 0;
            var stop_val: i64 = 0;
            const step_val: i64 = 1;

            if (args.len == 1) {
                // range(stop)
                if (args[0] == .constant and args[0].constant.value == .int) {
                    stop_val = args[0].constant.value.int;
                }
            } else if (args.len == 2) {
                // range(start, stop)
                if (args[0] == .constant and args[0].constant.value == .int) {
                    start_val = args[0].constant.value.int;
                }
                if (args[1] == .constant and args[1].constant.value == .int) {
                    stop_val = args[1].constant.value.int;
                }
            }

            // Generate: var <var_name>: i64 = <start>;
            try self.emitIndent();
            try self.output.writer(self.allocator).print("var {s}: i64 = {d};\n", .{ var_name, start_val });

            // Generate: while (<var_name> < <stop>) {
            try self.emitIndent();
            try self.output.writer(self.allocator).print("while ({s} < {d}) {{\n", .{ var_name, stop_val });
            self.indent();

            // Defer increment: defer <var_name> += <step>;
            try self.emitIndent();
            try self.output.writer(self.allocator).print("defer {s} += {d};\n", .{ var_name, step_val });
        } else {
            // Regular iteration - check if source is constant array, ArrayList, or anytype param
            const is_direct_iterable = blk: {
                // String literals are directly iterable (they're Zig arrays)
                if (gen.iter.* == .constant) {
                    if (gen.iter.constant.value == .string) break :blk true;
                }
                if (gen.iter.* == .name) {
                    const var_name_gen = gen.iter.name.id;
                    // Const array variables can be iterated directly
                    if (self.isArrayVar(var_name_gen)) break :blk true;
                    // anytype parameters should also be iterated directly (no .items)
                    if (self.anytype_params.contains(var_name_gen)) break :blk true;
                    // String variables are directly iterable
                    if (self.getVarType(var_name_gen)) |vt| {
                        if (vt == .string) break :blk true;
                    }
                }
                break :blk false;
            };

            try self.emitIndent();
            if (is_direct_iterable) {
                // Constant array variable, string literal, or anytype param - iterate directly
                try self.output.writer(self.allocator).print("const __iter_{d} = ", .{gen_idx});
                try genExpr(self, gen.iter.*);
                try self.emit(";\n");
            } else {
                // First emit the list to an intermediate variable, then access .items
                try self.output.writer(self.allocator).print("const __list_{d} = ", .{gen_idx});
                try genExpr(self, gen.iter.*);
                try self.emit(";\n");
                try self.emitIndent();
                try self.output.writer(self.allocator).print("const __iter_{d} = __list_{d}.items;\n", .{ gen_idx, gen_idx });
            }

            try self.emitIndent();
            // Check if target is a tuple (for tuple unpacking like `for a, b in zip(...)`)
            const is_tuple_target = switch (gen.target.*) {
                .tuple => true,
                .list => true,
                else => false,
            };
            if (is_tuple_target) {
                // Capture as single variable, unpack inside loop
                try self.output.writer(self.allocator).print("for (__iter_{d}) |__tuple_{d}__| {{\n", .{ gen_idx, gen_idx });
                self.indent();

                // Unpack tuple elements
                const elements = switch (gen.target.*) {
                    .tuple => |t| t.elts,
                    .list => |l| l.elts,
                    else => &[_]ast.Node{},
                };
                for (elements, 0..) |elt, idx| {
                    try self.emitIndent();
                    if (elt == .name) {
                        const var_name = elt.name.id;
                        // Handle underscore discard pattern
                        if (std.mem.eql(u8, var_name, "_")) {
                            try self.output.writer(self.allocator).print("_ = __tuple_{d}__.@\"{d}\";\n", .{ gen_idx, idx });
                        } else {
                            try self.output.writer(self.allocator).print("const {s} = __tuple_{d}__.@\"{d}\";\n", .{ var_name, gen_idx, idx });
                        }
                    }
                }
            } else {
                try self.output.writer(self.allocator).print("for (__iter_{d}) |", .{gen_idx});
                try genExpr(self, gen.target.*);
                try self.emit("| {\n");
                self.indent();
            }
        }

        // Generate if conditions for this generator
        for (gen.ifs) |if_cond| {
            try self.emitIndent();
            try self.emit("if (");
            try genExpr(self, if_cond);
            try self.emit(") {\n");
            self.indent();
        }
    }

    // Generate: try __comp_result.append(__global_allocator, <elt_expr>);
    try self.emitIndent();
    try self.emit("try __comp_result.append(__global_allocator, ");
    try genExpr(self, genexp.elt.*);
    try self.emit(");\n");

    // Close all if conditions and for loops
    for (genexp.generators) |gen| {
        // Close if conditions for this generator
        for (gen.ifs) |_| {
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
        }

        // Close for loop
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    // Generate: break :gen_N __comp_result;
    try self.emitIndent();
    try self.emit(try std.fmt.allocPrint(self.allocator, "break :gen_{d} __comp_result;\n", .{label_id}));

    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Check if an expression evaluates to an integer type
fn isIntExpr(node: ast.Node) bool {
    return switch (node) {
        .binop => true, // Arithmetic operations yield int
        .constant => |c| c.value == .int,
        .name => true, // Assume loop vars from range() are int (could be smarter)
        .call => |c| {
            if (c.func.* == .name) return IntReturningBuiltins.has(c.func.name.id);
            return false;
        },
        else => false,
    };
}

/// Check if an expression evaluates to a boolean type
fn isBoolExpr(node: ast.Node) bool {
    return switch (node) {
        .compare => true, // Comparisons (including 'in') yield bool
        .boolop => true, // and/or yield bool
        .unaryop => |u| u.op == .Not, // not yields bool
        .constant => |c| c.value == .bool,
        .call => |c| {
            if (c.func.* == .name) return BoolReturningBuiltins.has(c.func.name.id);
            return false;
        },
        else => false,
    };
}

/// Get the Zig element type string for a generator expression element
fn getGenExpElementType(elt: ast.Node) []const u8 {
    if (isBoolExpr(elt)) return "bool";
    if (isIntExpr(elt)) return "i64";
    // Default to i64 for unknown types
    return "i64";
}
