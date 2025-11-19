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

    // Generate: blk: { ... }
    try self.output.appendSlice(self.allocator, "blk: {\n");
    self.indent();

    // Generate: var __dict_result = std.StringHashMap(i64).init(allocator);
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "var __dict_result = std.StringHashMap(i64).init(allocator);\n");

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

    // Generate: try __dict_result.put(<key_expr>, <value_expr>);
    try self.emitIndent();
    try self.output.appendSlice(self.allocator, "try __dict_result.put(");

    // Generate key expression - need to convert to string if not already
    const key_is_name = dictcomp.key.* == .name;
    if (key_is_name) {
        // Convert variable to string using try std.fmt.allocPrint
        try self.output.appendSlice(self.allocator, "try std.fmt.allocPrint(allocator, \"{d}\", .{");
        try genExpr(self, dictcomp.key.*);
        try self.output.appendSlice(self.allocator, "})");
    } else {
        // Assume it's already a string or constant
        try genExpr(self, dictcomp.key.*);
    }

    try self.output.appendSlice(self.allocator, ", ");
    try genExpr(self, dictcomp.value.*);
    try self.output.appendSlice(self.allocator, ");\n");

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
