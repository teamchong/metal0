/// Expression-level code generation
/// Handles Python expressions: constants, binary ops, calls, lists, dicts, subscripts, etc.
const std = @import("std");
const ast = @import("../../ast.zig");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;
const dispatch = @import("dispatch.zig");

// Import submodules
const constants = @import("expressions/constants.zig");
const operators = @import("expressions/operators.zig");
const subscript_mod = @import("expressions/subscript.zig");
const collections = @import("expressions/collections.zig");
const lambda_mod = @import("expressions/lambda.zig");

// Re-export functions from submodules for backward compatibility
pub const genConstant = constants.genConstant;
pub const genBinOp = operators.genBinOp;
pub const genUnaryOp = operators.genUnaryOp;
pub const genCompare = operators.genCompare;
pub const genBoolOp = operators.genBoolOp;
pub const genSubscript = genSubscriptLocal;
pub const genList = collections.genList;
pub const genDict = collections.genDict;

/// Main expression dispatcher
pub fn genExpr(self: *NativeCodegen, node: ast.Node) CodegenError!void {
    switch (node) {
        .constant => |c| try constants.genConstant(self, c),
        .name => |n| {
            // Check if variable has been renamed (for exception handling)
            const name_to_use = self.var_renames.get(n.id) orelse n.id;
            try self.output.appendSlice(self.allocator, name_to_use);
        },
        .binop => |b| try operators.genBinOp(self, b),
        .unaryop => |u| try operators.genUnaryOp(self, u),
        .compare => |c| try operators.genCompare(self, c),
        .boolop => |b| try operators.genBoolOp(self, b),
        .call => |c| try genCall(self, c),
        .list => |l| try collections.genList(self, l),
        .listcomp => |lc| try genListComp(self, lc),
        .dict => |d| try collections.genDict(self, d),
        .tuple => |t| try genTuple(self, t),
        .subscript => |s| try genSubscriptLocal(self, s),
        .attribute => |a| try genAttribute(self, a),
        .lambda => |lam| lambda_mod.genLambda(self, lam) catch {},
        else => {},
    }
}

/// Generate function call - dispatches to specialized handlers or fallback
fn genCall(self: *NativeCodegen, call: ast.Node.Call) CodegenError!void {
    // Try to dispatch to specialized handler
    const dispatched = try dispatch.dispatchCall(self, call);
    if (dispatched) return;

    // Handle immediate lambda calls: (lambda x: x * 2)(5)
    if (call.func.* == .lambda) {
        // For immediate calls, we need the function name WITHOUT the & prefix
        // Generate lambda function and get its name
        const lambda = call.func.lambda;

        // Generate unique lambda function name
        const lambda_name = try std.fmt.allocPrint(
            self.allocator,
            "__lambda_{d}",
            .{self.lambda_counter},
        );
        defer self.allocator.free(lambda_name);
        self.lambda_counter += 1;

        // Generate the lambda function definition using lambda_mod
        // We'll do this manually to avoid the & prefix
        var lambda_func = std.ArrayList(u8){};

        // Function signature
        try lambda_func.writer(self.allocator).print("fn {s}(", .{lambda_name});

        for (lambda.args, 0..) |arg, i| {
            if (i > 0) try lambda_func.appendSlice(self.allocator, ", ");
            try lambda_func.writer(self.allocator).print("{s}: i64", .{arg.name});
        }

        try lambda_func.writer(self.allocator).print(") i64 {{\n    return ", .{});

        // Generate body expression
        const saved_output = self.output;
        self.output = std.ArrayList(u8){};
        try genExpr(self, lambda.body.*);
        const body_code = try self.output.toOwnedSlice(self.allocator);
        self.output = saved_output;

        try lambda_func.appendSlice(self.allocator, body_code);
        self.allocator.free(body_code);
        try lambda_func.appendSlice(self.allocator, ";\n}\n\n");

        // Store lambda function
        try self.lambda_functions.append(self.allocator, try lambda_func.toOwnedSlice(self.allocator));

        // Generate direct function call (no & prefix for immediate calls)
        try self.output.appendSlice(self.allocator, lambda_name);
        try self.output.appendSlice(self.allocator, "(");
        for (call.args, 0..) |arg, i| {
            if (i > 0) try self.output.appendSlice(self.allocator, ", ");
            try genExpr(self, arg);
        }
        try self.output.appendSlice(self.allocator, ")");
        return;
    }

    // Handle method calls (obj.method())
    if (call.func.* == .attribute) {
        const attr = call.func.attribute;

        // Generic method call: obj.method(args)
        try genExpr(self, attr.value.*);
        try self.output.appendSlice(self.allocator, ".");
        try self.output.appendSlice(self.allocator, attr.attr);
        try self.output.appendSlice(self.allocator, "(");

        for (call.args, 0..) |arg, i| {
            if (i > 0) try self.output.appendSlice(self.allocator, ", ");
            try genExpr(self, arg);
        }

        try self.output.appendSlice(self.allocator, ")");
        return;
    }

    // Check for class instantiation or closure calls
    if (call.func.* == .name) {
        const func_name = call.func.name.id;

        // Check if this is a simple lambda (function pointer)
        if (self.lambda_vars.contains(func_name)) {
            // Lambda call: square(5) -> square(5)
            // Function pointers in Zig are called directly
            try self.output.appendSlice(self.allocator, func_name);
            try self.output.appendSlice(self.allocator, "(");

            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.output.appendSlice(self.allocator, ", ");
                try genExpr(self, arg);
            }

            try self.output.appendSlice(self.allocator, ")");
            return;
        }

        // Check if this is a closure variable
        if (self.closure_vars.contains(func_name)) {
            // Closure call: add_five(3) -> add_five.call(3)
            try self.output.appendSlice(self.allocator, func_name);
            try self.output.appendSlice(self.allocator, ".call(");

            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.output.appendSlice(self.allocator, ", ");
                try genExpr(self, arg);
            }

            try self.output.appendSlice(self.allocator, ")");
            return;
        }

        // If name starts with uppercase, it's a class constructor
        if (func_name.len > 0 and std.ascii.isUpper(func_name[0])) {
            // Class instantiation: Counter(10) -> Counter.init(10)
            try self.output.appendSlice(self.allocator, func_name);
            try self.output.appendSlice(self.allocator, ".init(");

            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.output.appendSlice(self.allocator, ", ");
                try genExpr(self, arg);
            }

            try self.output.appendSlice(self.allocator, ")");
            return;
        }

        // Fallback: regular function call
        try self.output.appendSlice(self.allocator, func_name);
        try self.output.appendSlice(self.allocator, "(");

        for (call.args, 0..) |arg, i| {
            if (i > 0) try self.output.appendSlice(self.allocator, ", ");
            try genExpr(self, arg);
        }

        try self.output.appendSlice(self.allocator, ")");
    }
}

/// Generate tuple literal as Zig anonymous struct
fn genTuple(self: *NativeCodegen, tuple: ast.Node.Tuple) CodegenError!void {
    // Empty tuples become empty struct
    if (tuple.elts.len == 0) {
        try self.output.appendSlice(self.allocator, ".{}");
        return;
    }

    // Non-empty tuples: .{ elem1, elem2, elem3 }
    try self.output.appendSlice(self.allocator, ".{ ");

    for (tuple.elts, 0..) |elem, i| {
        if (i > 0) try self.output.appendSlice(self.allocator, ", ");
        try genExpr(self, elem);
    }

    try self.output.appendSlice(self.allocator, " }");
}

/// Generate array/dict subscript with tuple support (a[b])
/// Wraps subscript_mod.genSubscript but adds tuple indexing support
fn genSubscriptLocal(self: *NativeCodegen, subscript: ast.Node.Subscript) CodegenError!void {
    // Check if this is tuple indexing (only for index, not slice)
    if (subscript.slice == .index) {
        const value_type = try self.type_inferrer.inferExpr(subscript.value.*);

        if (value_type == .tuple) {
            // Tuple indexing: t[0] -> t.@"0"
            // Only constant indices supported for tuples
            if (subscript.slice.index.* == .constant and subscript.slice.index.constant.value == .int) {
                const index = subscript.slice.index.constant.value.int;
                try genExpr(self, subscript.value.*);
                try self.output.writer(self.allocator).print(".@\"{d}\"", .{index});
            } else {
                // Non-constant tuple index - error
                try self.output.appendSlice(self.allocator, "@compileError(\"Tuple indexing requires constant index\")");
            }
            return;
        }
    }

    // Delegate to subscript module for all other cases
    try subscript_mod.genSubscript(self, subscript);
}

/// Generate attribute access (obj.attr)
fn genAttribute(self: *NativeCodegen, attr: ast.Node.Attribute) CodegenError!void {
    // self.x -> self.x (direct translation in Zig)
    try genExpr(self, attr.value.*);
    try self.output.appendSlice(self.allocator, ".");
    try self.output.appendSlice(self.allocator, attr.attr);
}

/// Generate list comprehension: [x * 2 for x in range(5)]
/// Generates as imperative loop that builds ArrayList
fn genListComp(self: *NativeCodegen, listcomp: ast.Node.ListComp) CodegenError!void {
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
            // Regular iteration
            try self.emitIndent();
            try self.output.writer(self.allocator).print("const __iter_{d} = ", .{gen_idx});
            try genExpr(self, gen.iter.*);
            try self.output.appendSlice(self.allocator, ".items;\n");

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
