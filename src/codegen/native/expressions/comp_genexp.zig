//! Generator expression code generation
//! Split from comprehensions.zig for maintainability

const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const zig_keywords = @import("utils.zig_keywords");

// MIGRATED TO ZIGBUILDER

// Trait imports for type checking
const string_traits = @import("../../../analysis/traits/string_traits.zig");

const comp_conditions = @import("comp_conditions.zig");
const comp_utils = @import("comp_utils.zig");

/// Generate generator expression: (x * 2 for x in range(5))
/// For AOT compilation, we treat this as a list comprehension and return the list
/// (Real generators would need lazy evaluation which is complex)
pub fn genGenExp(self: *NativeCodegen, genexp: ast.Node.GenExp) CodegenError!void {
    const genExpr = @import("../expressions.zig").genExpr;

    // Get unique block label to avoid nested block conflicts
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Generate: (gen_N: { ... })
    try self.emit(try std.fmt.allocPrint(self.allocator, "(gen_{d}: {{\n", .{label_id}));
    self.indent();

    // Determine element type from the expression being yielded
    const elem_type = comp_utils.getGenExpElementType(genexp.elt.*);

    // Generate: var __comp_result_N = std.ArrayListUnmanaged(<elem_type>){};
    try self.emitIndent();
    try self.output.writer(self.allocator).print("var __comp_result_{d} = std.ArrayListUnmanaged({s}){{}};\n", .{ label_id, elem_type });

    // Generate nested loops for each generator
    for (genexp.generators, 0..) |gen, gen_idx| {
        // Check if this is a range() call
        const is_range = gen.iter.* == .call and gen.iter.call.func.* == .name and
            std.mem.eql(u8, gen.iter.call.func.name.id, "range");

        if (is_range) {
            try genGenExpRangeLoop(self, gen, label_id);
        } else {
            try genGenExpIterLoop(self, gen, gen_idx, label_id);
        }

        // Generate if conditions for this generator
        for (gen.ifs) |if_cond| {
            try self.emitIndent();
            try self.emit("if (");
            try comp_conditions.genComprehensionConditionNoSubs(self, if_cond);
            try self.emit(") {\n");
            self.indent();
        }
    }

    // Generate: try __comp_result_N.append(__global_allocator, <elt_expr>);
    try self.emitIndent();
    try self.output.writer(self.allocator).print("try __comp_result_{d}.append(__global_allocator, ", .{label_id});
    try genExpr(self, genexp.elt.*);
    try self.emit(");\n");

    // Close all if conditions and for loops
    for (genexp.generators) |gen| {
        for (gen.ifs) |_| {
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
        }
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    // Generate: break :gen_N __comp_result_N;
    try self.emitIndent();
    try self.output.writer(self.allocator).print("break :gen_{d} __comp_result_{d};\n", .{ label_id, label_id });

    self.dedent();
    try self.emitIndent();
    try self.emit("})");
}

/// Generate range loop for generator expression
fn genGenExpRangeLoop(
    self: *NativeCodegen,
    gen: ast.Node.Comprehension,
    _: usize, // label_id - unused
) CodegenError!void {
    const genExpr = @import("../expressions.zig").genExpr;

    const orig_var_name = gen.target.name.id;
    const var_name = if (std.mem.eql(u8, orig_var_name, "_")) "_unused" else orig_var_name;
    const args = gen.iter.call.args;

    // Check if all range args are constants
    const start_is_const = if (args.len >= 2) args[0] == .constant and args[0].constant.value == .int else true;
    const stop_is_const = if (args.len >= 1) args[if (args.len == 1) 0 else 1] == .constant and args[if (args.len == 1) 0 else 1].constant.value == .int else true;

    if (start_is_const and stop_is_const) {
        // All constants - use static values
        var start_val: i64 = 0;
        var stop_val: i64 = 0;
        const step_val: i64 = 1;

        if (args.len == 1) {
            stop_val = args[0].constant.value.int;
        } else if (args.len == 2) {
            start_val = args[0].constant.value.int;
            stop_val = args[1].constant.value.int;
        }

        try self.emitIndent();
        try self.output.writer(self.allocator).print("var {s}: i64 = {d};\n", .{ var_name, start_val });
        try self.emitIndent();
        try self.output.writer(self.allocator).print("while ({s} < {d}) {{\n", .{ var_name, stop_val });
        self.indent();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("defer {s} += {d};\n", .{ var_name, step_val });
    } else {
        // Dynamic range - generate expressions
        try self.emitIndent();
        try self.output.writer(self.allocator).print("var {s}: i64 = ", .{var_name});
        if (args.len >= 2) {
            try genExpr(self, args[0]);
        } else {
            try self.emit("0");
        }
        try self.emit(";\n");

        try self.emitIndent();
        try self.output.writer(self.allocator).print("while ({s} < ", .{var_name});
        try genExpr(self, args[if (args.len == 1) 0 else 1]);
        try self.emit(") {\n");
        self.indent();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("defer {s} += 1;\n", .{var_name});
    }
}

/// Generate iterator loop for generator expression
fn genGenExpIterLoop(
    self: *NativeCodegen,
    gen: ast.Node.Comprehension,
    gen_idx: usize,
    label_id: usize,
) CodegenError!void {
    const genExpr = @import("../expressions.zig").genExpr;

    // Check if source is directly iterable
    const is_direct_iterable = blk: {
        if (gen.iter.* == .constant) {
            const iter_const_type = self.type_inferrer.inferExpr(gen.iter.*) catch .unknown;
            if (string_traits.isString(iter_const_type)) break :blk true;
        }
        if (gen.iter.* == .name) {
            const var_name = gen.iter.name.id;
            if (self.isArrayVar(var_name)) break :blk true;
            if (self.anytype_params.contains(var_name)) break :blk true;
            if (self.getVarType(var_name)) |vt| {
                if (string_traits.isString(vt)) break :blk true;
            }
        }
        break :blk false;
    };

    try self.emitIndent();
    if (is_direct_iterable) {
        try self.output.writer(self.allocator).print("const __iter_{d}_{d} = ", .{ label_id, gen_idx });
        try genExpr(self, gen.iter.*);
        try self.emit(";\n");
    } else {
        try self.output.writer(self.allocator).print("const __list_{d}_{d} = ", .{ label_id, gen_idx });
        try genExpr(self, gen.iter.*);
        try self.emit(";\n");
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __iter_{d}_{d} = __list_{d}_{d}.items;\n", .{ label_id, gen_idx, label_id, gen_idx });
    }

    try self.emitIndent();
    const is_tuple_target = switch (gen.target.*) {
        .tuple => true,
        .list => true,
        else => false,
    };

    if (is_tuple_target) {
        try genGenExpTupleUnpack(self, gen, gen_idx, label_id);
    } else {
        try self.output.writer(self.allocator).print("for (__iter_{d}_{d}) |", .{ label_id, gen_idx });
        const unique_id = self.nextLabelId();
        const maybe_mangled = try comp_conditions.emitForLoopTarget(self, gen.target.*, unique_id);
        try self.emit("| {\n");
        self.indent();

        // If loop target shadows an imported module, register the rename mapping
        if (maybe_mangled) |mangled_name| {
            if (gen.target.* == .name) {
                const target_name = gen.target.name.id;
                try self.var_renames.put(target_name, mangled_name);
            }
        }
    }
}

/// Generate tuple unpacking for generator expression
fn genGenExpTupleUnpack(
    self: *NativeCodegen,
    gen: ast.Node.Comprehension,
    gen_idx: usize,
    label_id: usize,
) CodegenError!void {
    try self.output.writer(self.allocator).print("for (__iter_{d}_{d}) |__tuple_{d}_{d}__| {{\n", .{ label_id, gen_idx, label_id, gen_idx });
    self.indent();

    const elements = switch (gen.target.*) {
        .tuple => |t| t.elts,
        .list => |l| l.elts,
        else => &[_]ast.Node{},
    };
    for (elements, 0..) |elt, idx| {
        try self.emitIndent();
        if (elt == .name) {
            const var_name = elt.name.id;
            if (std.mem.eql(u8, var_name, "_")) {
                try self.output.writer(self.allocator).print("_ = __tuple_{d}_{d}__.@\"{d}\";\n", .{ label_id, gen_idx, idx });
            } else {
                if (self.isDeclared(var_name)) {
                    const renamed = try std.fmt.allocPrint(self.allocator, "__comp_{s}_{d}", .{ var_name, label_id });
                    try self.var_renames.put(var_name, renamed);
                    try self.output.writer(self.allocator).print("const {s} = __tuple_{d}_{d}__.@\"{d}\";\n", .{ renamed, label_id, gen_idx, idx });
                } else {
                    try self.output.writer(self.allocator).print("const {s} = __tuple_{d}_{d}__.@\"{d}\";\n", .{ var_name, label_id, gen_idx, idx });
                }
            }
        }
    }
}
