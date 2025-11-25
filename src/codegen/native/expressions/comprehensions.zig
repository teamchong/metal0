/// List and dict comprehension code generation
const std = @import("std");
const ast = @import("../../../ast.zig");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

/// Generate list comprehension: [x * 2 for x in range(5)]
/// Generates as imperative loop that builds ArrayList
pub fn genListComp(self: *NativeCodegen, listcomp: ast.Node.ListComp) CodegenError!void {
    // Forward declare genExpr - it's in parent module
    const parent = @import("../expressions.zig");
    const genExpr = parent.genExpr;

    // Generate: blk: { ... }
    try self.output.appendSlice(self.allocator, "blk: {\n");
    self.indent();

    // Generate: var __comp_result = std.ArrayList(i64){};
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var __comp_result = std.ArrayList(i64){};\n");

    // Generate nested loops for each generator
    for (listcomp.generators, 0..) |gen, gen_idx| {
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
            // Regular iteration - check if source is constant array or ArrayList
            const is_const_array_var = blk: {
                if (gen.iter.* == .name) {
                    const var_name = gen.iter.name.id;
                    break :blk self.isArrayVar(var_name);
                }
                break :blk false;
            };

            try self.emitIndent();
            if (is_const_array_var) {
                // Constant array variable - iterate directly
                try self.output.writer(self.allocator).print("const __iter_{d} = ", .{gen_idx});
                try genExpr(self, gen.iter.*);
                try self.output.appendSlice(self.allocator, ";\n");
            } else {
                // ArrayList - use .items
                try self.output.writer(self.allocator).print("const __iter_{d} = ", .{gen_idx});
                try genExpr(self, gen.iter.*);
                try self.output.appendSlice(self.allocator, ".items;\n");
            }

            try self.emitIndent();
            try self.output.writer(self.allocator).print("for (__iter_{d}) |", .{gen_idx});
            try genExpr(self, gen.target.*);
            try self.output.appendSlice(self.allocator, "| {\n");
            self.indent();
        }

        // Generate if conditions for this generator
        for (gen.ifs) |if_cond| {
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "if (");
            try genExpr(self, if_cond);
            try self.output.appendSlice(self.allocator, ") {\n");
            self.indent();
        }
    }

    // Generate: try __comp_result.append(allocator, <elt_expr>);
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "try __comp_result.append(allocator, ");
    try genExpr(self, listcomp.elt.*);
    try self.output.appendSlice(self.allocator, ");\n");

    // Close all if conditions and for loops
    for (listcomp.generators) |gen| {
        // Close if conditions for this generator
        for (gen.ifs) |_| {
            self.dedent();
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "}\n");
        }

        // Close for loop
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
    }

    // Generate: break :blk try __comp_result.toOwnedSlice(allocator);
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :blk try __comp_result.toOwnedSlice(allocator);\n");

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

pub fn genDictComp(self: *NativeCodegen, dictcomp: ast.Node.DictComp) CodegenError!void {
    // Forward declare genExpr - it's in parent module
    const parent = @import("../expressions.zig");
    const genExpr = parent.genExpr;

    // Determine if key is an integer expression
    const key_is_int = isIntExpr(dictcomp.key.*);

    // Generate: blk: { ... }
    try self.output.appendSlice(self.allocator, "blk: {\n");
    self.indent();

    // Generate: const KV = struct { key: <type>, value: i64 };
    try self.emitIndent();
    if (key_is_int) {
        try self.output.appendSlice(self.allocator, "const KV = struct { key: i64, value: i64 };\n");
    } else {
        try self.output.appendSlice(self.allocator, "const KV = struct { key: []const u8, value: i64 };\n");
    }

    // Generate: var __dict_result = std.ArrayList(KV){};
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var __dict_result = std.ArrayList(KV){};\n");

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
            // Regular iteration - check if source is constant array or ArrayList
            const is_const_array_var = blk: {
                if (gen.iter.* == .name) {
                    const var_name = gen.iter.name.id;
                    break :blk self.isArrayVar(var_name);
                }
                break :blk false;
            };

            try self.emitIndent();
            if (is_const_array_var) {
                // Constant array variable - iterate directly
                try self.output.writer(self.allocator).print("const __iter_{d} = ", .{gen_idx});
                try genExpr(self, gen.iter.*);
                try self.output.appendSlice(self.allocator, ";\n");
            } else {
                // ArrayList - use .items
                try self.output.writer(self.allocator).print("const __iter_{d} = ", .{gen_idx});
                try genExpr(self, gen.iter.*);
                try self.output.appendSlice(self.allocator, ".items;\n");
            }

            try self.emitIndent();
            try self.output.writer(self.allocator).print("for (__iter_{d}) |", .{gen_idx});
            try genExpr(self, gen.target.*);
            try self.output.appendSlice(self.allocator, "| {\n");
            self.indent();
        }

        // Generate if conditions for this generator
        for (gen.ifs) |if_cond| {
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "if (");
            try genExpr(self, if_cond);
            try self.output.appendSlice(self.allocator, ") {\n");
            self.indent();
        }
    }

    // Generate: try __dict_result.append(allocator, .{ .key = <key>, .value = <value> });
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "try __dict_result.append(allocator, .{ .key = ");

    // Generate key expression based on type
    if (key_is_int) {
        // Integer key - emit directly
        try genExpr(self, dictcomp.key.*);
    } else if (dictcomp.key.* == .name) {
        // Variable name, assume string (might need conversion for non-string vars)
        try genExpr(self, dictcomp.key.*);
    } else {
        // Assume it's already a string or constant
        try genExpr(self, dictcomp.key.*);
    }

    try self.output.appendSlice(self.allocator, ", .value = ");
    try genExpr(self, dictcomp.value.*);
    try self.output.appendSlice(self.allocator, " });\n");

    // Close all if conditions and for loops
    for (dictcomp.generators) |gen| {
        // Close if conditions for this generator
        for (gen.ifs) |_| {
            self.dedent();
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "}\n");
        }

        // Close for loop
        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
    }

    // Generate: break :blk __dict_result;
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "break :blk __dict_result;\n");

    self.dedent();
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "}");
}

/// Check if an expression evaluates to an integer type
fn isIntExpr(node: ast.Node) bool {
    return switch (node) {
        .binop => true, // Arithmetic operations yield int
        .constant => |c| c.value == .int,
        .name => true, // Assume loop vars from range() are int (could be smarter)
        .call => |c| {
            // len(), int(), etc return int
            if (c.func.* == .name) {
                const name = c.func.name.id;
                return std.mem.eql(u8, name, "len") or
                    std.mem.eql(u8, name, "int") or
                    std.mem.eql(u8, name, "ord");
            }
            return false;
        },
        else => false,
    };
}
