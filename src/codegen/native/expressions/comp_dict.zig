//! Dictionary comprehension code generation
//! Split from comprehensions.zig for maintainability

const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const zig_keywords = @import("utils.zig_keywords");

// MIGRATED TO ZIGBUILDER

// Trait imports for type checking
const type_traits = @import("../../../analysis/traits/type_traits.zig");
const string_traits = @import("../../../analysis/traits/string_traits.zig");
const NativeType = @import("../../../analysis/native_types/core.zig").NativeType;

const comp_conditions = @import("comp_conditions.zig");
const comp_utils = @import("comp_utils.zig");

/// Generate dict comprehension: {k: v for k, v in items}
pub fn genDictComp(self: *NativeCodegen, dictcomp: ast.Node.DictComp) CodegenError!void {
    const genExpr = @import("../expressions.zig").genExpr;

    const comp_id = self.output.items.len;
    var em = self.exprEmitter();
    const label_id = em.reserveLabelId();

    // Set up temp vars for loop variables for type inference
    var saved_types: [8]SavedTypeInfo = undefined;
    var saved_count: usize = 0;

    for (dictcomp.generators) |gen| {
        if (gen.target.* == .name) {
            const var_name = gen.target.name.id;
            const loop_var_type = inferLoopVarType(self, gen);

            if (saved_count < saved_types.len) {
                saved_types[saved_count] = .{
                    .name = var_name,
                    .old_type = self.type_inferrer.putTempVar(var_name, loop_var_type) catch null,
                };
                saved_count += 1;
            }
        } else if (gen.target.* == .tuple or gen.target.* == .list) {
            saved_count = handleTupleUnpackTypes(self, gen, &saved_types, saved_count);
        }
    }

    // Now infer key and value types with loop vars visible
    const key_type = self.type_inferrer.inferExpr(dictcomp.key.*) catch .unknown;
    const key_classification = type_traits.getDictKeyType(key_type);

    const value_type_str = if (self.target_dict_value_type) |target_type|
        target_type
    else blk: {
        const value_type = self.type_inferrer.inferExpr(dictcomp.value.*) catch .unknown;
        break :blk comp_utils.nativeTypeToZigStr(value_type);
    };

    // Generate: (dict_N: { ... })
    try self.emit(try std.fmt.allocPrint(self.allocator, "(dict_{d}: {{\n", .{label_id}));
    self.indent();

    // Generate HashMap with properly inferred key/value types
    try self.emitIndent();
    switch (key_classification) {
        .int => {
            try self.output.writer(self.allocator).print("var __dict_result = std.AutoArrayHashMap(i64, {s}).init(__global_allocator);\n", .{value_type_str});
        },
        .string => {
            try self.output.writer(self.allocator).print("var __dict_result = hashmap_helper.StringHashMap({s}).init(__global_allocator);\n", .{value_type_str});
        },
        .pyvalue => {
            // Use PyValueHashMap for non-string keys (Zig 0.15 managed style)
            try self.output.writer(self.allocator).print("var __dict_result = runtime.PyValueHashMap(runtime.PyValue).init(__global_allocator);\n", .{});
        },
    }

    // Track variables renamed in this comprehension
    var renamed_vars: std.ArrayListUnmanaged([]const u8) = .{};
    defer renamed_vars.deinit(self.allocator);

    // Generate nested loops for each generator
    for (dictcomp.generators, 0..) |gen, gen_idx| {
        try genDictCompGenerator(self, gen, gen_idx, label_id, comp_id, &renamed_vars);
    }

    // Generate: try __dict_result.put(<key>, <value>);
    try self.emitIndent();
    if (key_classification == .pyvalue) {
        // PyValueHashMap uses managed ArrayHashMap - put() uses stored allocator
        try self.emit("try __dict_result.put(try runtime.toPyValue(__global_allocator, ");
        try genExpr(self, dictcomp.key.*);
        try self.emit("), try runtime.toPyValue(__global_allocator, ");
        try genExpr(self, dictcomp.value.*);
        try self.emit("));\n");
    } else {
        try self.emit("try __dict_result.put(");
        try genExpr(self, dictcomp.key.*);
        try self.emit(", ");
        if (self.target_dict_value_type != null) {
            try self.emitCallCtx("try runtime.toPyValue", dictcomp.value.*, struct {
                pub fn f(s: *NativeCodegen, e: ast.Node) CodegenError!void {
                    try s.emit("__global_allocator, ");
                    try genExpr(s, e);
                }
            }.f);
        } else {
            try genExpr(self, dictcomp.value.*);
        }
        try self.emit(");\n");
    }

    // Close all if conditions and for loops
    for (dictcomp.generators) |gen| {
        for (gen.ifs) |_| {
            self.dedent();
            try self.emitIndent();
            try self.emit("}\n");
        }
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    // Generate: break :dict_N __dict_result;
    try self.emitIndent();
    try self.emit(try std.fmt.allocPrint(self.allocator, "break :dict_{d} __dict_result;\n", .{label_id}));

    self.dedent();
    try self.emitIndent();
    try self.emit("})");

    // Restore original types for loop variables
    for (saved_types[0..saved_count]) |saved| {
        self.type_inferrer.restoreTempVar(saved.name, saved.old_type);
    }

    // Clean up var_renames
    for (renamed_vars.items) |var_name| {
        _ = self.var_renames.swapRemove(var_name);
    }
}

/// Saved type info struct - used to restore types after comprehension
pub const SavedTypeInfo = struct { name: []const u8, old_type: ?NativeType };

/// Infer loop variable type from iterator
fn inferLoopVarType(self: *NativeCodegen, gen: ast.Node.Comprehension) NativeType {
    // Check if iterator is range() - gives i64 loop variable
    if (gen.iter.* == .call and gen.iter.call.func.* == .name) {
        const func_name = gen.iter.call.func.name.id;
        if (std.mem.eql(u8, func_name, "range")) {
            return .{ .int = .bounded };
        }
    }
    // Check if iterator is [*range(n)] or (*range(n),) pattern
    if (gen.iter.* == .list) {
        const list = gen.iter.list;
        if (list.elts.len == 1 and list.elts[0] == .starred) {
            const starred_val = list.elts[0].starred.value;
            if (starred_val.* == .call and starred_val.call.func.* == .name and
                std.mem.eql(u8, starred_val.call.func.name.id, "range"))
            {
                return .{ .int = .bounded };
            }
        } else if (list.elts.len > 0 and list.elts[0] != .starred) {
            const elem_type = self.type_inferrer.inferExpr(list.elts[0]) catch .unknown;
            if (type_traits.isIntegral(elem_type)) {
                return .{ .int = .bounded };
            }
            return elem_type;
        }
    }
    if (gen.iter.* == .tuple) {
        const tup = gen.iter.tuple;
        if (tup.elts.len == 1 and tup.elts[0] == .starred) {
            const starred_val = tup.elts[0].starred.value;
            if (starred_val.* == .call and starred_val.call.func.* == .name and
                std.mem.eql(u8, starred_val.call.func.name.id, "range"))
            {
                return .{ .int = .bounded };
            }
        }
    }
    // For other iterators, infer from type
    const iter_type = self.type_inferrer.inferExpr(gen.iter.*) catch .unknown;
    if (iter_type == .list) {
        return iter_type.list.*;
    } else if (iter_type == .array) {
        return iter_type.array.element_type.*;
    }
    return .{ .int = .bounded };
}

/// Handle tuple unpacking types for dict comp
fn handleTupleUnpackTypes(
    self: *NativeCodegen,
    gen: ast.Node.Comprehension,
    saved_types: *[8]SavedTypeInfo,
    start_count: usize,
) usize {
    var saved_count = start_count;
    const target_elts = if (gen.target.* == .tuple) gen.target.tuple.elts else gen.target.list.elts;

    if (gen.iter.* == .list and gen.iter.list.elts.len > 0) {
        const first_elem = gen.iter.list.elts[0];
        if (first_elem == .tuple) {
            const tuple_elts = first_elem.tuple.elts;
            for (target_elts, 0..) |target_elt, idx| {
                if (target_elt == .name and idx < tuple_elts.len) {
                    const var_name = target_elt.name.id;
                    const elem_type = self.type_inferrer.inferExpr(tuple_elts[idx]) catch .unknown;
                    const loop_var_type: NativeType = if (type_traits.isIntegral(elem_type))
                        .{ .int = .bounded }
                    else
                        elem_type;

                    if (saved_count < saved_types.len) {
                        saved_types[saved_count] = .{
                            .name = var_name,
                            .old_type = self.type_inferrer.putTempVar(var_name, loop_var_type) catch null,
                        };
                        saved_count += 1;
                    }
                }
            }
        }
    }
    return saved_count;
}

/// Generate a single generator (for loop) in dict comprehension
fn genDictCompGenerator(
    self: *NativeCodegen,
    gen: ast.Node.Comprehension,
    gen_idx: usize,
    label_id: usize,
    comp_id: usize,
    renamed_vars: *std.ArrayListUnmanaged([]const u8),
) CodegenError!void {
    // Check if this is a range() call or starred range pattern
    const is_range = gen.iter.* == .call and gen.iter.call.func.* == .name and
        std.mem.eql(u8, gen.iter.call.func.name.id, "range");

    const is_starred_range = isStarredRangePattern(gen);
    const range_args_for_starred = getStarredRangeArgs(gen);

    if (is_range or is_starred_range) {
        try genDictCompRangeLoop(self, gen, gen_idx, label_id, comp_id, is_starred_range, range_args_for_starred, renamed_vars);
    } else {
        try genDictCompIterLoop(self, gen, gen_idx, label_id, comp_id, renamed_vars);
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

/// Check if iterator is [*range(n)] or (*range(n),) pattern
fn isStarredRangePattern(gen: ast.Node.Comprehension) bool {
    if (gen.iter.* == .list) {
        const list = gen.iter.list;
        if (list.elts.len == 1 and list.elts[0] == .starred) {
            const starred_val = list.elts[0].starred.value;
            if (starred_val.* == .call and starred_val.call.func.* == .name and
                std.mem.eql(u8, starred_val.call.func.name.id, "range"))
            {
                return true;
            }
        }
    }
    if (gen.iter.* == .tuple) {
        const tup = gen.iter.tuple;
        if (tup.elts.len == 1 and tup.elts[0] == .starred) {
            const starred_val = tup.elts[0].starred.value;
            if (starred_val.* == .call and starred_val.call.func.* == .name and
                std.mem.eql(u8, starred_val.call.func.name.id, "range"))
            {
                return true;
            }
        }
    }
    return false;
}

/// Get range args from starred pattern
fn getStarredRangeArgs(gen: ast.Node.Comprehension) ?[]ast.Node {
    if (gen.iter.* == .list) {
        if (gen.iter.list.elts.len == 1 and gen.iter.list.elts[0] == .starred) {
            return gen.iter.list.elts[0].starred.value.call.args;
        }
    }
    if (gen.iter.* == .tuple) {
        if (gen.iter.tuple.elts.len == 1 and gen.iter.tuple.elts[0] == .starred) {
            return gen.iter.tuple.elts[0].starred.value.call.args;
        }
    }
    return null;
}

/// Generate range loop for dict comprehension
fn genDictCompRangeLoop(
    self: *NativeCodegen,
    gen: ast.Node.Comprehension,
    gen_idx: usize,
    label_id: usize,
    comp_id: usize,
    is_starred_range: bool,
    range_args_for_starred: ?[]ast.Node,
    renamed_vars: *std.ArrayListUnmanaged([]const u8),
) CodegenError!void {
    const genExpr = @import("../expressions.zig").genExpr;

    const orig_var_name = gen.target.name.id;
    const args = if (is_starred_range) range_args_for_starred.? else gen.iter.call.args;

    const mangled_name = try std.fmt.allocPrint(self.allocator, "__comp_{s}_{d}", .{ orig_var_name, comp_id });
    try self.var_renames.put(orig_var_name, mangled_name);
    try renamed_vars.append(self.allocator, orig_var_name);

    // Parse range arguments
    var start_val: i64 = 0;
    var stop_val: i64 = 0;
    var step_val: i64 = 1;
    var has_constant_start = false;
    var has_constant_stop = false;
    var has_constant_step = false;

    if (args.len >= 1) {
        if (args.len == 1) {
            if (args[0] == .constant and args[0].constant.value == .int) {
                stop_val = args[0].constant.value.int;
                has_constant_stop = true;
            }
        } else {
            if (args[0] == .constant and args[0].constant.value == .int) {
                start_val = args[0].constant.value.int;
                has_constant_start = true;
            }
            if (args[1] == .constant and args[1].constant.value == .int) {
                stop_val = args[1].constant.value.int;
                has_constant_stop = true;
            }
            if (args.len >= 3 and args[2] == .constant and args[2].constant.value == .int) {
                step_val = args[2].constant.value.int;
                has_constant_step = true;
            }
        }
    }

    // Generate: var __comp_<orig>_<id>: i64 = <start>;
    try self.emitIndent();
    if (has_constant_start or args.len == 1) {
        try self.output.writer(self.allocator).print("var {s}: i64 = {d};\n", .{ mangled_name, start_val });
    } else {
        try self.output.writer(self.allocator).print("var {s}: i64 = @intCast(", .{mangled_name});
        try genExpr(self, args[0]);
        try self.emit(");\n");
    }

    // Generate stop variable if needed
    if (!has_constant_stop) {
        try self.emitIndent();
        try self.output.writer(self.allocator).print("const __stop_{d}_{d}: i64 = @intCast(", .{ label_id, gen_idx });
        if (args.len == 1) {
            try genExpr(self, args[0]);
        } else {
            try genExpr(self, args[1]);
        }
        try self.emit(");\n");
    }

    // Generate while loop
    try self.emitIndent();
    if (has_constant_stop) {
        try self.output.writer(self.allocator).print("while ({s} < {d}) {{\n", .{ mangled_name, stop_val });
    } else {
        try self.output.writer(self.allocator).print("while ({s} < __stop_{d}_{d}) {{\n", .{ mangled_name, label_id, gen_idx });
    }
    self.indent();

    // Defer increment
    try self.emitIndent();
    if (has_constant_step or args.len < 3) {
        try self.output.writer(self.allocator).print("defer {s} += {d};\n", .{ mangled_name, step_val });
    } else {
        try self.output.writer(self.allocator).print("defer {s} += @intCast(", .{mangled_name});
        try genExpr(self, args[2]);
        try self.emit(");\n");
    }
}

/// Generate iterator loop for dict comprehension
fn genDictCompIterLoop(
    self: *NativeCodegen,
    gen: ast.Node.Comprehension,
    gen_idx: usize,
    label_id: usize,
    _: usize, // comp_id - unused
    renamed_vars: *std.ArrayListUnmanaged([]const u8),
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
        try genDictCompTupleUnpack(self, gen, gen_idx, label_id, renamed_vars);
    } else {
        try self.output.writer(self.allocator).print("for (__iter_{d}_{d}) |", .{ label_id, gen_idx });
        const unique_id = self.nextLabelId();
        const maybe_mangled = try comp_conditions.emitForLoopTarget(self, gen.target.*, unique_id);
        try self.emit("| {\n");
        self.indent();

        // Emit discard for loop variable to handle cases where it's not used in body
        // This prevents "unused capture" errors in Zig
        if (gen.target.* == .name) {
            const loop_var_name = gen.target.name.id;
            // Don't emit discard for explicit _ capture
            if (!std.mem.eql(u8, loop_var_name, "_")) {
                try self.emitIndent();
                try self.emit("_ = &");
                if (maybe_mangled) |mangled| {
                    try self.emit(mangled);
                } else {
                    // Use Pass 2.5 name to match declaration
                    try zig_keywords.writeEscapedIdent(self.output.writer(self.allocator), self.getZigName(loop_var_name));
                }
                try self.emit(";\n");
            }
        }

        if (maybe_mangled) |mangled_name| {
            if (gen.target.* == .name) {
                const target_name = gen.target.name.id;
                try self.var_renames.put(target_name, mangled_name);
            }
        }
    }
}

/// Generate tuple unpacking for dict comprehension
fn genDictCompTupleUnpack(
    self: *NativeCodegen,
    gen: ast.Node.Comprehension,
    gen_idx: usize,
    label_id: usize,
    renamed_vars: *std.ArrayListUnmanaged([]const u8),
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
                const actual_name = if (self.isDeclared(var_name)) blk: {
                    const renamed = try std.fmt.allocPrint(self.allocator, "__comp_{s}_{d}", .{ var_name, label_id });
                    try self.var_renames.put(var_name, renamed);
                    try renamed_vars.append(self.allocator, var_name);
                    try self.output.writer(self.allocator).print("const {s} = __tuple_{d}_{d}__.@\"{d}\";\n", .{ renamed, label_id, gen_idx, idx });
                    break :blk renamed;
                } else blk: {
                    // Use Pass 2.5 name to match what references will use via getZigName()
                    const zig_name = self.getZigName(var_name);
                    try self.output.writer(self.allocator).print("const {s} = __tuple_{d}_{d}__.@\"{d}\";\n", .{ zig_name, label_id, gen_idx, idx });
                    break :blk zig_name;
                };
                try self.emitIndent();
                try self.emit("_ = &");
                try self.emit(actual_name);
                try self.emit(";\n");
            }
        } else if (elt == .tuple or elt == .list) {
            // Handle nested tuple unpacking: for size, (left, right) in zip(...)
            const nested_elts = if (elt == .tuple) elt.tuple.elts else elt.list.elts;
            try self.output.writer(self.allocator).print("const __nested_{d}_{d}_{d} = __tuple_{d}_{d}__.@\"{d}\";\n", .{ label_id, gen_idx, idx, label_id, gen_idx, idx });

            for (nested_elts, 0..) |nested_elt, nested_idx| {
                if (nested_elt == .name) {
                    const var_name = nested_elt.name.id;
                    try self.emitIndent();
                    if (std.mem.eql(u8, var_name, "_")) {
                        try self.output.writer(self.allocator).print("_ = __nested_{d}_{d}_{d}.@\"{d}\";\n", .{ label_id, gen_idx, idx, nested_idx });
                    } else {
                        const actual_name = if (self.isDeclared(var_name)) blk: {
                            const renamed = try std.fmt.allocPrint(self.allocator, "__comp_{s}_{d}", .{ var_name, label_id });
                            try self.var_renames.put(var_name, renamed);
                            try renamed_vars.append(self.allocator, var_name);
                            try self.output.writer(self.allocator).print("const {s} = __nested_{d}_{d}_{d}.@\"{d}\";\n", .{ renamed, label_id, gen_idx, idx, nested_idx });
                            break :blk renamed;
                        } else blk: {
                            // Use Pass 2.5 name to match what references will use via getZigName()
                            const zig_name = self.getZigName(var_name);
                            try self.output.writer(self.allocator).print("const {s} = __nested_{d}_{d}_{d}.@\"{d}\";\n", .{ zig_name, label_id, gen_idx, idx, nested_idx });
                            break :blk zig_name;
                        };
                        try self.emitIndent();
                        try self.emit("_ = &");
                        try self.emit(actual_name);
                        try self.emit(";\n");
                    }
                }
            }
        }
    }
}
