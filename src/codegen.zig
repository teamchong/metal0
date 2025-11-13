const std = @import("std");
const ast = @import("ast.zig");

/// Codegen errors
pub const CodegenError = error{
    ExpectedModule,
    UnsupportedExpression,
    UnsupportedStatement,
    UnsupportedTarget,
    InvalidAssignment,
    InvalidCompare,
    EmptyTargets,
    UnsupportedFunction,
    UnsupportedCall,
    UnsupportedForLoop,
    InvalidLoopVariable,
    InvalidRangeArgs,
    MissingLenArg,
    NotImplemented,
    OutOfMemory,
};

/// Generate Zig code from AST
pub fn generate(allocator: std.mem.Allocator, tree: ast.Node) ![]const u8 {
    // Initialize code generator
    var generator = try ZigCodeGenerator.init(allocator);
    defer generator.deinit();

    // Generate code from AST
    switch (tree) {
        .module => |module| try generator.generate(module),
        else => return error.ExpectedModule,
    }

    return try generator.output.toOwnedSlice(allocator);
}

/// Expression evaluation result
const ExprResult = struct {
    code: []const u8,
    needs_try: bool,
};

/// Zig code generator - ports Python ZigCodeGenerator class
pub const ZigCodeGenerator = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),
    indent_level: usize,

    // State tracking (matching Python codegen)
    var_types: std.StringHashMap([]const u8),
    declared_vars: std.StringHashMap(void),
    reassigned_vars: std.StringHashMap(void),
    list_element_types: std.StringHashMap([]const u8),
    tuple_element_types: std.StringHashMap([]const u8),

    needs_runtime: bool,
    needs_allocator: bool,

    pub fn init(allocator: std.mem.Allocator) !*ZigCodeGenerator {
        const self = try allocator.create(ZigCodeGenerator);
        self.* = ZigCodeGenerator{
            .allocator = allocator,
            .output = std.ArrayList(u8){},
            .indent_level = 0,
            .var_types = std.StringHashMap([]const u8).init(allocator),
            .declared_vars = std.StringHashMap(void).init(allocator),
            .reassigned_vars = std.StringHashMap(void).init(allocator),
            .list_element_types = std.StringHashMap([]const u8).init(allocator),
            .tuple_element_types = std.StringHashMap([]const u8).init(allocator),
            .needs_runtime = false,
            .needs_allocator = false,
        };
        return self;
    }

    pub fn deinit(self: *ZigCodeGenerator) void {
        self.output.deinit(self.allocator);
        self.var_types.deinit();
        self.declared_vars.deinit();
        self.reassigned_vars.deinit();
        self.list_element_types.deinit();
        self.tuple_element_types.deinit();
        self.allocator.destroy(self);
    }

    /// Emit a line of code with proper indentation
    pub fn emit(self: *ZigCodeGenerator, code: []const u8) CodegenError!void {
        // Add indentation
        for (0..self.indent_level) |_| {
            try self.output.appendSlice(self.allocator, "    ");
        }
        try self.output.appendSlice(self.allocator, code);
        try self.output.append(self.allocator, '\n');
    }

    /// Increase indentation level
    pub fn indent(self: *ZigCodeGenerator) void {
        self.indent_level += 1;
    }

    /// Decrease indentation level
    pub fn dedent(self: *ZigCodeGenerator) void {
        if (self.indent_level > 0) {
            self.indent_level -= 1;
        }
    }

    /// Generate code from parsed AST
    pub fn generate(self: *ZigCodeGenerator, module: ast.Node.Module) CodegenError!void {
        // Phase 1: Detect runtime needs and collect declarations
        for (module.body) |node| {
            try self.detectRuntimeNeeds(node);
            try self.collectDeclarations(node);
        }

        // Phase 2: Detect reassignments
        var assignments_seen = std.StringHashMap(void).init(self.allocator);
        defer assignments_seen.deinit();

        for (module.body) |node| {
            try self.detectReassignments(node, &assignments_seen);
        }

        // Reset declared_vars for code generation
        self.declared_vars.clearRetainingCapacity();

        // Phase 3: Generate code
        try self.emit("const std = @import(\"std\");");
        if (self.needs_runtime) {
            try self.emit("const runtime = @import(\"runtime.zig\");");
        }
        try self.emit("");

        try self.emit("pub fn main() CodegenError!void {");
        self.indent();

        if (self.needs_allocator) {
            try self.emit("var gpa = std.heap.GeneralPurposeAllocator(.{}){};");
            try self.emit("defer _ = gpa.deinit();");
            try self.emit("const allocator = gpa.allocator();");
            try self.emit("");
        }

        for (module.body) |node| {
            try self.visitNode(node);
        }

        self.dedent();
        try self.emit("}");
    }

    /// Detect if node requires PyObject runtime
    fn detectRuntimeNeeds(self: *ZigCodeGenerator, node: ast.Node) CodegenError!void {
        switch (node) {
            .constant => |constant| {
                if (constant.value == .string) {
                    self.needs_runtime = true;
                    self.needs_allocator = true;
                }
            },
            .list => {
                self.needs_runtime = true;
                self.needs_allocator = true;
            },
            else => {},
        }
    }

    /// Collect all variable declarations
    fn collectDeclarations(self: *ZigCodeGenerator, node: ast.Node) CodegenError!void {
        switch (node) {
            .assign => |assign| {
                for (assign.targets) |target| {
                    switch (target) {
                        .name => |name| {
                            try self.declared_vars.put(name.id, {});
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    /// Detect variables that are reassigned
    fn detectReassignments(self: *ZigCodeGenerator, node: ast.Node, assignments_seen: *std.StringHashMap(void)) CodegenError!void {
        switch (node) {
            .assign => |assign| {
                for (assign.targets) |target| {
                    switch (target) {
                        .name => |name| {
                            if (assignments_seen.contains(name.id)) {
                                try self.reassigned_vars.put(name.id, {});
                            } else {
                                try assignments_seen.put(name.id, {});
                            }
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    /// Visit a node and generate code
    fn visitNode(self: *ZigCodeGenerator, node: ast.Node) CodegenError!void {
        switch (node) {
            .assign => |assign| try self.visitAssign(assign),
            .expr_stmt => |expr_stmt| {
                const result = try self.visitExpr(expr_stmt.value.*);
                // Expression statement - emit it
                if (result.code.len > 0) {
                    try self.emit(result.code);
                }
            },
            .if_stmt => |if_node| try self.visitIf(if_node),
            .for_stmt => |for_node| try self.visitFor(for_node),
            .while_stmt => |while_node| try self.visitWhile(while_node),
            .function_def => |func| try self.visitFunctionDef(func),
            .return_stmt => |ret| try self.visitReturn(ret),
            else => {}, // Ignore other node types for now
        }
    }

    // Helper methods
    fn visitCompareOp(self: *ZigCodeGenerator, op: ast.CompareOp) []const u8 {
        _ = self;
        return switch (op) {
            .Lt => "<",
            .LtEq => "<=",
            .Gt => ">",
            .GtEq => ">=",
            .Eq => "==",
            .NotEq => "!=",
            .In => "in", // Will need special handling
            .NotIn => "not in", // Will need special handling
        };
    }

    fn visitBinOpHelper(self: *ZigCodeGenerator, op: ast.Operator) []const u8 {
        _ = self;
        return switch (op) {
            .Add => "+",
            .Sub => "-",
            .Mult => "*",
            .Div => "/",
            .Mod => "%",
            .FloorDiv => "//",
            .Pow => "**",
        };
    }

    // Visitor methods
    fn visitAssign(self: *ZigCodeGenerator, assign: ast.Node.Assign) CodegenError!void {
        if (assign.targets.len == 0) return error.EmptyTargets;

        // For now, handle single target
        const target = assign.targets[0];

        switch (target) {
            .name => |name| {
                const var_name = name.id;

                // Determine if this is first assignment or reassignment
                const is_first_assignment = !self.declared_vars.contains(var_name);
                const var_keyword = if (self.reassigned_vars.contains(var_name)) "var" else "const";

                if (is_first_assignment) {
                    try self.declared_vars.put(var_name, {});
                }

                // Evaluate the value expression
                const value_result = try self.visitExpr(assign.value.*);

                // Infer type from value
                switch (assign.value.*) {
                    .constant => |constant| {
                        switch (constant.value) {
                            .string => try self.var_types.put(var_name, "string"),
                            .int => try self.var_types.put(var_name, "int"),
                            else => {},
                        }
                    },
                    .binop => {
                        // Binary operation - assume int for now
                        try self.var_types.put(var_name, "int");
                    },
                    .name => |source_name| {
                        // Assigning from another variable - copy its type
                        const source_type = self.var_types.get(source_name.id);
                        if (source_type) |stype| {
                            try self.var_types.put(var_name, stype);
                        }
                    },
                    .list => {
                        try self.var_types.put(var_name, "list");
                    },
                    else => {},
                }

                // Generate assignment code
                var buf = std.ArrayList(u8){};

                if (is_first_assignment) {
                    if (value_result.needs_try) {
                        try buf.writer(self.allocator).print("{s} {s} = try {s};", .{ var_keyword, var_name, value_result.code });
                        try self.emit(try buf.toOwnedSlice(self.allocator));

                        // Add defer for strings
                        const var_type = self.var_types.get(var_name);
                        if (var_type != null and std.mem.eql(u8, var_type.?, "string")) {
                            var defer_buf = std.ArrayList(u8){};
                            try defer_buf.writer(self.allocator).print("defer runtime.decref({s}, allocator);", .{var_name});
                            try self.emit(try defer_buf.toOwnedSlice(self.allocator));
                        }
                    } else {
                        try buf.writer(self.allocator).print("{s} {s} = {s};", .{ var_keyword, var_name, value_result.code });
                        try self.emit(try buf.toOwnedSlice(self.allocator));
                    }
                } else {
                    // Reassignment
                    const var_type = self.var_types.get(var_name);
                    if (var_type != null and std.mem.eql(u8, var_type.?, "string")) {
                        var decref_buf = std.ArrayList(u8){};
                        try decref_buf.writer(self.allocator).print("runtime.decref({s}, allocator);", .{var_name});
                        try self.emit(try decref_buf.toOwnedSlice(self.allocator));
                    }

                    if (value_result.needs_try) {
                        try buf.writer(self.allocator).print("{s} = try {s};", .{ var_name, value_result.code });
                    } else {
                        try buf.writer(self.allocator).print("{s} = {s};", .{ var_name, value_result.code });
                    }
                    try self.emit(try buf.toOwnedSlice(self.allocator));
                }
            },
            else => return error.UnsupportedTarget,
        }
    }

    fn visitExpr(self: *ZigCodeGenerator, node: ast.Node) CodegenError!ExprResult {
        return switch (node) {
            .name => |name| ExprResult{
                .code = name.id,
                .needs_try = false,
            },

            .constant => |constant| self.visitConstant(constant),

            .binop => |binop| self.visitBinOp(binop),

            .call => |call| self.visitCall(call),

            .compare => |compare| self.visitCompare(compare),

            else => error.UnsupportedExpression,
        };
    }

    fn visitConstant(self: *ZigCodeGenerator, constant: ast.Node.Constant) CodegenError!ExprResult {
        switch (constant.value) {
            .string => |str| {
                var buf = std.ArrayList(u8){};
                try buf.writer(self.allocator).print("runtime.PyString.create(allocator, \"{s}\")", .{str});
                return ExprResult{
                    .code = try buf.toOwnedSlice(self.allocator),
                    .needs_try = true,
                };
            },
            .int => |num| {
                var buf = std.ArrayList(u8){};
                try buf.writer(self.allocator).print("{d}", .{num});
                return ExprResult{
                    .code = try buf.toOwnedSlice(self.allocator),
                    .needs_try = false,
                };
            },
            .bool => |b| {
                return ExprResult{
                    .code = if (b) "true" else "false",
                    .needs_try = false,
                };
            },
            .float => |f| {
                var buf = std.ArrayList(u8){};
                try buf.writer(self.allocator).print("{d}", .{f});
                return ExprResult{
                    .code = try buf.toOwnedSlice(self.allocator),
                    .needs_try = false,
                };
            },
        }
    }

    fn visitBinOp(self: *ZigCodeGenerator, binop: ast.Node.BinOp) CodegenError!ExprResult {
        const left_result = try self.visitExpr(binop.left.*);
        const right_result = try self.visitExpr(binop.right.*);

        const op_str = self.visitBinOpHelper(binop.op);

        var buf = std.ArrayList(u8){};
        try buf.writer(self.allocator).print("{s} {s} {s}", .{ left_result.code, op_str, right_result.code });

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = left_result.needs_try or right_result.needs_try,
        };
    }

    fn visitCompare(self: *ZigCodeGenerator, compare: ast.Node.Compare) CodegenError!ExprResult {
        if (compare.ops.len == 0 or compare.comparators.len == 0) {
            return error.InvalidCompare;
        }

        const left_result = try self.visitExpr(compare.left.*);
        const right_result = try self.visitExpr(compare.comparators[0]);

        const op_str = self.visitCompareOp(compare.ops[0]);

        var buf = std.ArrayList(u8){};
        try buf.writer(self.allocator).print("{s} {s} {s}", .{ left_result.code, op_str, right_result.code });

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = false,
        };
    }

    fn visitCall(self: *ZigCodeGenerator, call: ast.Node.Call) CodegenError!ExprResult {
        switch (call.func.*) {
            .name => |func_name| {
                // Handle built-in functions
                if (std.mem.eql(u8, func_name.id, "print")) {
                    return self.visitPrintCall(call.args);
                } else if (std.mem.eql(u8, func_name.id, "len")) {
                    return self.visitLenCall(call.args);
                } else {
                    // User-defined function call
                    return error.UnsupportedFunction;
                }
            },
            else => return error.UnsupportedCall,
        }
    }

    fn visitPrintCall(self: *ZigCodeGenerator, args: []ast.Node) CodegenError!ExprResult {
        if (args.len == 0) {
            return ExprResult{
                .code = "std.debug.print(\"\\n\", .{})",
                .needs_try = false,
            };
        }

        const arg = args[0];
        const arg_result = try self.visitExpr(arg);

        var buf = std.ArrayList(u8){};

        // Determine print format based on variable type
        switch (arg) {
            .name => |name| {
                const var_type = self.var_types.get(name.id);
                if (var_type) |vtype| {
                    if (std.mem.eql(u8, vtype, "string")) {
                        try buf.writer(self.allocator).print("std.debug.print(\"{{s}}\\n\", .{{runtime.PyString.getValue({s})}})", .{arg_result.code});
                    } else {
                        try buf.writer(self.allocator).print("std.debug.print(\"{{}}\\n\", .{{{s}}})", .{arg_result.code});
                    }
                } else {
                    try buf.writer(self.allocator).print("std.debug.print(\"{{}}\\n\", .{{{s}}})", .{arg_result.code});
                }
            },
            else => {
                try buf.writer(self.allocator).print("std.debug.print(\"{{}}\\n\", .{{{s}}})", .{arg_result.code});
            },
        }

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = false,
        };
    }

    fn visitLenCall(self: *ZigCodeGenerator, args: []ast.Node) CodegenError!ExprResult {
        if (args.len == 0) return error.MissingLenArg;

        const arg = args[0];
        const arg_result = try self.visitExpr(arg);

        var buf = std.ArrayList(u8){};

        // Check variable type to determine which len() to call
        switch (arg) {
            .name => |name| {
                const var_type = self.var_types.get(name.id);
                if (var_type) |vtype| {
                    if (std.mem.eql(u8, vtype, "list")) {
                        try buf.writer(self.allocator).print("runtime.PyList.len({s})", .{arg_result.code});
                    } else if (std.mem.eql(u8, vtype, "string")) {
                        try buf.writer(self.allocator).print("runtime.PyString.len({s})", .{arg_result.code});
                    } else {
                        try buf.writer(self.allocator).print("runtime.PyList.len({s})", .{arg_result.code});
                    }
                } else {
                    try buf.writer(self.allocator).print("runtime.PyList.len({s})", .{arg_result.code});
                }
            },
            else => {
                try buf.writer(self.allocator).print("runtime.PyList.len({s})", .{arg_result.code});
            },
        }

        return ExprResult{
            .code = try buf.toOwnedSlice(self.allocator),
            .needs_try = false,
        };
    }

    fn visitIf(self: *ZigCodeGenerator, if_node: ast.Node.If) CodegenError!void {
        const test_result = try self.visitExpr(if_node.condition.*);

        var buf = std.ArrayList(u8){};
        try buf.writer(self.allocator).print("if ({s}) {{", .{test_result.code});
        try self.emit(try buf.toOwnedSlice(self.allocator));

        self.indent();

        for (if_node.body) |stmt| {
            try self.visitNode(stmt);
        }

        self.dedent();

        if (if_node.else_body.len > 0) {
            try self.emit("} else {");
            self.indent();

            for (if_node.else_body) |stmt| {
                try self.visitNode(stmt);
            }

            self.dedent();
        }

        try self.emit("}");
    }

    fn visitFor(self: *ZigCodeGenerator, for_node: ast.Node.For) CodegenError!void {
        // Check if this is a range() call
        switch (for_node.iter.*) {
            .call => |call| {
                switch (call.func.*) {
                    .name => |func_name| {
                        if (std.mem.eql(u8, func_name.id, "range")) {
                            return self.visitRangeFor(for_node, call.args);
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }

        return error.UnsupportedForLoop;
    }

    fn visitRangeFor(self: *ZigCodeGenerator, for_node: ast.Node.For, args: []ast.Node) CodegenError!void {
        // Get loop variable name
        switch (for_node.target.*) {
            .name => |target_name| {
                const loop_var = target_name.id;
                try self.var_types.put(loop_var, "int");

                // Parse range arguments
                var start: []const u8 = "0";
                var end: []const u8 = undefined;
                var step: []const u8 = "1";

                if (args.len == 1) {
                    const end_result = try self.visitExpr(args[0]);
                    end = end_result.code;
                } else if (args.len == 2) {
                    const start_result = try self.visitExpr(args[0]);
                    const end_result = try self.visitExpr(args[1]);
                    start = start_result.code;
                    end = end_result.code;
                } else if (args.len == 3) {
                    const start_result = try self.visitExpr(args[0]);
                    const end_result = try self.visitExpr(args[1]);
                    const step_result = try self.visitExpr(args[2]);
                    start = start_result.code;
                    end = end_result.code;
                    step = step_result.code;
                } else {
                    return error.InvalidRangeArgs;
                }

                // Check if loop variable already declared
                const is_first_use = !self.declared_vars.contains(loop_var);

                var buf = std.ArrayList(u8){};

                if (is_first_use) {
                    try buf.writer(self.allocator).print("var {s}: i64 = {s};", .{ loop_var, start });
                    try self.emit(try buf.toOwnedSlice(self.allocator));
                    try self.declared_vars.put(loop_var, {});
                } else {
                    try buf.writer(self.allocator).print("{s} = {s};", .{ loop_var, start });
                    try self.emit(try buf.toOwnedSlice(self.allocator));
                }

                buf = std.ArrayList(u8){};
                try buf.writer(self.allocator).print("while ({s} < {s}) {{", .{ loop_var, end });
                try self.emit(try buf.toOwnedSlice(self.allocator));

                self.indent();

                for (for_node.body) |stmt| {
                    try self.visitNode(stmt);
                }

                buf = std.ArrayList(u8){};
                try buf.writer(self.allocator).print("{s} += {s};", .{ loop_var, step });
                try self.emit(try buf.toOwnedSlice(self.allocator));

                self.dedent();
                try self.emit("}");
            },
            else => return error.InvalidLoopVariable,
        }
    }

    fn visitWhile(self: *ZigCodeGenerator, while_node: ast.Node.While) CodegenError!void {
        const test_result = try self.visitExpr(while_node.condition.*);

        var buf = std.ArrayList(u8){};
        try buf.writer(self.allocator).print("while ({s}) {{", .{test_result.code});
        try self.emit(try buf.toOwnedSlice(self.allocator));

        self.indent();

        for (while_node.body) |stmt| {
            try self.visitNode(stmt);
        }

        self.dedent();
        try self.emit("}");
    }

    fn visitFunctionDef(self: *ZigCodeGenerator, func: ast.Node.FunctionDef) CodegenError!void {
        _ = self;
        _ = func;
        // TODO: Implement function definitions
        // This requires:
        // 1. Parse function name, parameters, and return type
        // 2. Generate Zig function signature
        // 3. Visit function body
        // 4. Track function in function_signatures for later calls
        return error.NotImplemented;
    }

    fn visitReturn(self: *ZigCodeGenerator, ret: ast.Node.Return) CodegenError!void {
        if (ret.value) |value| {
            const value_result = try self.visitExpr(value.*);
            var buf = std.ArrayList(u8){};

            if (value_result.needs_try) {
                try buf.writer(self.allocator).print("return try {s};", .{value_result.code});
            } else {
                try buf.writer(self.allocator).print("return {s};", .{value_result.code});
            }

            try self.emit(try buf.toOwnedSlice(self.allocator));
        } else {
            try self.emit("return;");
        }
    }
};
