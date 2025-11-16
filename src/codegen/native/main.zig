/// Native Zig code generation - No PyObject overhead
/// Generates stack-allocated native types based on type inference
/// Core module - delegates to json/http/builtins/methods/async
const std = @import("std");
const ast = @import("../../ast.zig");
const native_types = @import("../../analysis/native_types.zig");
const NativeType = native_types.NativeType;
const TypeInferrer = native_types.TypeInferrer;

// Import specialized modules
const json = @import("json.zig");
const http = @import("http.zig");
const async_mod = @import("async.zig");
const builtins = @import("builtins.zig");
const methods = @import("methods.zig");
const analyzer = @import("analyzer.zig");

/// Error set for code generation
pub const CodegenError = error{
    OutOfMemory,
} || native_types.InferError;

pub const NativeCodegen = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),
    type_inferrer: *TypeInferrer,
    indent_level: usize,

    pub fn init(allocator: std.mem.Allocator, type_inferrer: *TypeInferrer) !*NativeCodegen {
        const self = try allocator.create(NativeCodegen);
        self.* = .{
            .allocator = allocator,
            .output = std.ArrayList(u8){},
            .type_inferrer = type_inferrer,
            .indent_level = 0,
        };
        return self;
    }

    pub fn deinit(self: *NativeCodegen) void {
        self.output.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    /// Generate native Zig code for module
    pub fn generate(self: *NativeCodegen, module: ast.Node.Module) ![]const u8 {
        // PHASE 1: Analyze module to determine requirements
        const analysis = try analyzer.analyzeModule(module, self.allocator);

        // PHASE 2: Generate imports based on analysis
        try self.emit("const std = @import(\"std\");\n");
        if (analysis.needs_runtime) {
            // Use relative import since runtime.zig is in /tmp with generated file
            try self.emit("const runtime = @import(\"./runtime.zig\");\n");
        }
        try self.emit("\n");

        // PHASE 3: Generate main function
        try self.emit("pub fn main() !void {\n");
        self.indent();

        // Setup allocator (only if needed)
        if (analysis.needs_allocator) {
            try self.emitIndent();
            try self.emit("var gpa = std.heap.GeneralPurposeAllocator(.{}){};\n");
            try self.emitIndent();
            try self.emit("defer _ = gpa.deinit();\n");
            try self.emitIndent();
            try self.emit("const allocator = gpa.allocator();\n\n");
        }

        // PHASE 4: Generate statements
        for (module.body) |stmt| {
            try self.generateStmt(stmt);
        }

        self.dedent();
        try self.emit("}\n");

        return self.output.toOwnedSlice(self.allocator);
    }

    fn generateStmt(self: *NativeCodegen, node: ast.Node) CodegenError!void {
        switch (node) {
            .assign => |assign| try self.genAssign(assign),
            .expr_stmt => |expr| try self.genExprStmt(expr.value.*),
            .if_stmt => |if_stmt| try self.genIf(if_stmt),
            .while_stmt => |while_stmt| try self.genWhile(while_stmt),
            .for_stmt => |for_stmt| try self.genFor(for_stmt),
            .import_stmt => {},  // Native modules - no import needed
            else => {},
        }
    }

    fn genAssign(self: *NativeCodegen, assign: ast.Node.Assign) CodegenError!void {
        const value_type = try self.type_inferrer.inferExpr(assign.value.*);

        for (assign.targets) |target| {
            if (target == .name) {
                const var_name = target.name.id;

                // Use const for all variables (simple approach - works for most Python code)
                // TODO: Track mutations to determine const vs var
                try self.emitIndent();
                try self.output.appendSlice(self.allocator, "const ");
                try self.output.appendSlice(self.allocator, var_name);

                // Only emit type annotation for known types
                // For unknown types (json.loads, etc.), let Zig infer
                if (value_type != .unknown) {
                    try self.output.appendSlice(self.allocator, ": ");
                    try value_type.toZigType(self.allocator, &self.output);
                }

                try self.output.appendSlice(self.allocator, " = ");

                // Emit value
                try self.genExpr(assign.value.*);

                try self.output.appendSlice(self.allocator, ";\n");
            }
        }
    }

    fn genExprStmt(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
        try self.emitIndent();

        // Special handling for print()
        if (expr == .call and expr.call.func.* == .name) {
            const func_name = expr.call.func.name.id;
            if (std.mem.eql(u8, func_name, "print")) {
                try self.genPrint(expr.call.args);
                return;
            }
        }

        try self.genExpr(expr);
        try self.output.appendSlice(self.allocator, ";\n");
    }

    fn genPrint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
        if (args.len == 0) {
            try self.output.appendSlice(self.allocator, "std.debug.print(\"\\n\", .{});\n");
            return;
        }

        try self.output.appendSlice(self.allocator, "std.debug.print(\"");

        // Generate format string
        for (args, 0..) |arg, i| {
            const arg_type = try self.type_inferrer.inferExpr(arg);
            const fmt = switch (arg_type) {
                .int => "{d}",
                .float => "{d}",
                .bool => "{}",
                .string => "{s}",
                else => "{any}",
            };
            try self.output.appendSlice(self.allocator, fmt);

            if (i < args.len - 1) {
                try self.output.appendSlice(self.allocator, " ");
            }
        }

        try self.output.appendSlice(self.allocator, "\\n\", .{");

        // Generate arguments
        for (args, 0..) |arg, i| {
            try self.genExpr(arg);
            if (i < args.len - 1) {
                try self.output.appendSlice(self.allocator, ", ");
            }
        }

        try self.output.appendSlice(self.allocator, "});\n");
    }

    fn genIf(self: *NativeCodegen, if_stmt: ast.Node.If) CodegenError!void {
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "if (");
        try self.genExpr(if_stmt.condition.*);
        try self.output.appendSlice(self.allocator, ") {\n");

        self.indent();
        for (if_stmt.body) |stmt| {
            try self.generateStmt(stmt);
        }
        self.dedent();

        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}");

        if (if_stmt.else_body.len > 0) {
            try self.output.appendSlice(self.allocator, " else {\n");
            self.indent();
            for (if_stmt.else_body) |stmt| {
                try self.generateStmt(stmt);
            }
            self.dedent();
            try self.emitIndent();
            try self.output.appendSlice(self.allocator, "}");
        }

        try self.output.appendSlice(self.allocator, "\n");
    }

    fn genWhile(self: *NativeCodegen, while_stmt: ast.Node.While) CodegenError!void {
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "while (");
        try self.genExpr(while_stmt.condition.*);
        try self.output.appendSlice(self.allocator, ") {\n");

        self.indent();
        for (while_stmt.body) |stmt| {
            try self.generateStmt(stmt);
        }
        self.dedent();

        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
    }

    fn genFor(self: *NativeCodegen, for_stmt: ast.Node.For) CodegenError!void {
        const target_name = if (for_stmt.target.* == .name) for_stmt.target.*.name.id else "_";

        try self.emitIndent();

        // Handle range() specially
        if (for_stmt.iter.* == .call and for_stmt.iter.call.func.* == .name) {
            const func_name = for_stmt.iter.call.func.name.id;
            if (std.mem.eql(u8, func_name, "range")) {
                try self.genRangeLoop(target_name, for_stmt.iter.call.args, for_stmt.body);
                return;
            }
        }

        // Generic iteration
        try self.output.appendSlice(self.allocator, "for (");
        try self.genExpr(for_stmt.iter.*);
        try self.output.writer(self.allocator).print(") |{s}| {{\n", .{target_name});

        self.indent();
        for (for_stmt.body) |stmt| {
            try self.generateStmt(stmt);
        }
        self.dedent();

        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
    }

    fn genRangeLoop(self: *NativeCodegen, var_name: []const u8, args: []ast.Node, body: []ast.Node) CodegenError!void {
        // range(n) or range(start, end) or range(start, end, step)
        try self.output.writer(self.allocator).print("var {s}: i64 = ", .{var_name});

        if (args.len == 1) {
            try self.output.appendSlice(self.allocator, "0");
        } else {
            try self.genExpr(args[0]);
        }

        try self.output.writer(self.allocator).print(";\nwhile ({s} < ", .{var_name});

        if (args.len == 1) {
            try self.genExpr(args[0]);
        } else {
            try self.genExpr(args[1]);
        }

        try self.output.writer(self.allocator).print(") {{\n", .{});

        self.indent();
        for (body) |stmt| {
            try self.generateStmt(stmt);
        }

        // Increment
        try self.emitIndent();
        try self.output.writer(self.allocator).print("{s} += ", .{var_name});
        if (args.len == 3) {
            try self.genExpr(args[2]);
        } else {
            try self.output.appendSlice(self.allocator, "1");
        }
        try self.output.appendSlice(self.allocator, ";\n");

        self.dedent();
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, "}\n");
    }

    pub fn genExpr(self: *NativeCodegen, node: ast.Node) CodegenError!void {
        switch (node) {
            .constant => |c| try self.genConstant(c),
            .name => |n| try self.output.appendSlice(self.allocator, n.id),
            .binop => |b| try self.genBinOp(b),
            .unaryop => |u| try self.genUnaryOp(u),
            .compare => |c| try self.genCompare(c),
            .boolop => |b| try self.genBoolOp(b),
            .call => |c| try self.genCall(c),
            .list => |l| try self.genList(l),
            .subscript => |s| try self.genSubscript(s),
            else => {},
        }
    }

    fn genConstant(self: *NativeCodegen, constant: ast.Node.Constant) CodegenError!void {
        switch (constant.value) {
            .int => try self.output.writer(self.allocator).print("{d}", .{constant.value.int}),
            .float => try self.output.writer(self.allocator).print("{d}", .{constant.value.float}),
            .bool => try self.output.appendSlice(self.allocator, if (constant.value.bool) "true" else "false"),
            .string => |s| {
                // Strip Python quotes
                const content = if (s.len >= 2) s[1..s.len-1] else s;

                // Escape quotes and backslashes for Zig string literal
                try self.output.appendSlice(self.allocator, "\"");
                for (content) |c| {
                    switch (c) {
                        '"' => try self.output.appendSlice(self.allocator, "\\\""),
                        '\\' => try self.output.appendSlice(self.allocator, "\\\\"),
                        '\n' => try self.output.appendSlice(self.allocator, "\\n"),
                        '\r' => try self.output.appendSlice(self.allocator, "\\r"),
                        '\t' => try self.output.appendSlice(self.allocator, "\\t"),
                        else => try self.output.writer(self.allocator).print("{c}", .{c}),
                    }
                }
                try self.output.appendSlice(self.allocator, "\"");
            },
        }
    }

    fn genBinOp(self: *NativeCodegen, binop: ast.Node.BinOp) CodegenError!void {
        try self.output.appendSlice(self.allocator, "(");
        try self.genExpr(binop.left.*);

        const op_str = switch (binop.op) {
            .Add => " + ",
            .Sub => " - ",
            .Mult => " * ",
            .Div => " / ",
            .Mod => " % ",
            .FloorDiv => " / ",  // Zig doesn't distinguish
            else => " ? ",
        };
        try self.output.appendSlice(self.allocator, op_str);

        try self.genExpr(binop.right.*);
        try self.output.appendSlice(self.allocator, ")");
    }

    fn genUnaryOp(self: *NativeCodegen, unaryop: ast.Node.UnaryOp) CodegenError!void {
        const op_str = switch (unaryop.op) {
            .Not => "!",
            .USub => "-",
            else => "?",
        };
        try self.output.appendSlice(self.allocator, op_str);
        try self.genExpr(unaryop.operand.*);
    }

    fn genCompare(self: *NativeCodegen, compare: ast.Node.Compare) CodegenError!void {
        try self.genExpr(compare.left.*);

        for (compare.ops, 0..) |op, i| {
            const op_str = switch (op) {
                .Eq => " == ",
                .NotEq => " != ",
                .Lt => " < ",
                .LtEq => " <= ",
                .Gt => " > ",
                .GtEq => " >= ",
                else => " ? ",
            };
            try self.output.appendSlice(self.allocator, op_str);
            try self.genExpr(compare.comparators[i]);
        }
    }

    fn genBoolOp(self: *NativeCodegen, boolop: ast.Node.BoolOp) CodegenError!void {
        const op_str = if (boolop.op == .And) " and " else " or ";

        for (boolop.values, 0..) |value, i| {
            if (i > 0) try self.output.appendSlice(self.allocator, op_str);
            try self.genExpr(value);
        }
    }

    fn genCall(self: *NativeCodegen, call: ast.Node.Call) CodegenError!void {
        // Check for module.function() calls (json.loads, http.get, etc.)
        if (call.func.* == .attribute) {
            const attr = call.func.attribute;
            if (attr.value.* == .name) {
                const module_name = attr.value.name.id;
                const func_name = attr.attr;

                // Handle json.loads()
                if (std.mem.eql(u8, module_name, "json") and std.mem.eql(u8, func_name, "loads")) {
                    try json.genJsonLoads(self, call.args);
                    return;
                }

                // Handle json.dumps()
                if (std.mem.eql(u8, module_name, "json") and std.mem.eql(u8, func_name, "dumps")) {
                    try json.genJsonDumps(self, call.args);
                    return;
                }

                // Handle http.get()
                if (std.mem.eql(u8, module_name, "http") and std.mem.eql(u8, func_name, "get")) {
                    try http.genHttpGet(self, call.args);
                    return;
                }

                // Handle http.post()
                if (std.mem.eql(u8, module_name, "http") and std.mem.eql(u8, func_name, "post")) {
                    try http.genHttpPost(self, call.args);
                    return;
                }

                // Handle asyncio.run()
                if (std.mem.eql(u8, module_name, "asyncio") and std.mem.eql(u8, func_name, "run")) {
                    try async_mod.genAsyncioRun(self, call.args);
                    return;
                }

                // Handle asyncio.gather()
                if (std.mem.eql(u8, module_name, "asyncio") and std.mem.eql(u8, func_name, "gather")) {
                    try async_mod.genAsyncioGather(self, call.args);
                    return;
                }

                // Handle asyncio.create_task()
                if (std.mem.eql(u8, module_name, "asyncio") and std.mem.eql(u8, func_name, "create_task")) {
                    try async_mod.genAsyncioCreateTask(self, call.args);
                    return;
                }

                // Handle asyncio.sleep()
                if (std.mem.eql(u8, module_name, "asyncio") and std.mem.eql(u8, func_name, "sleep")) {
                    try async_mod.genAsyncioSleep(self, call.args);
                    return;
                }
            }
        }

        // Handle method calls (obj.method())
        if (call.func.* == .attribute) {
            const method_name = call.func.attribute.attr;

            if (std.mem.eql(u8, method_name, "split")) {
                try methods.genSplit(self, call.func.attribute.value.*, call.args);
                return;
            }

            if (std.mem.eql(u8, method_name, "append")) {
                try methods.genAppend(self, call.func.attribute.value.*, call.args);
                return;
            }

            if (std.mem.eql(u8, method_name, "upper")) {
                try methods.genUpper(self, call.func.attribute.value.*, call.args);
                return;
            }

            if (std.mem.eql(u8, method_name, "lower")) {
                try methods.genLower(self, call.func.attribute.value.*, call.args);
                return;
            }

            if (std.mem.eql(u8, method_name, "strip")) {
                try methods.genStrip(self, call.func.attribute.value.*, call.args);
                return;
            }

            if (std.mem.eql(u8, method_name, "replace")) {
                try methods.genReplace(self, call.func.attribute.value.*, call.args);
                return;
            }
        }

        // Check for built-in functions (len, str, int, float, etc.)
        if (call.func.* == .name) {
            const func_name = call.func.name.id;

            // Handle len()
            if (std.mem.eql(u8, func_name, "len")) {
                try builtins.genLen(self, call.args);
                return;
            }

            // Handle str()
            if (std.mem.eql(u8, func_name, "str")) {
                try builtins.genStr(self, call.args);
                return;
            }

            // Handle int()
            if (std.mem.eql(u8, func_name, "int")) {
                try builtins.genInt(self, call.args);
                return;
            }

            // Handle float()
            if (std.mem.eql(u8, func_name, "float")) {
                try builtins.genFloat(self, call.args);
                return;
            }

            // Handle bool()
            if (std.mem.eql(u8, func_name, "bool")) {
                try builtins.genBool(self, call.args);
                return;
            }

            // Fallback: regular function call
            try self.output.appendSlice(self.allocator, func_name);
            try self.output.appendSlice(self.allocator, "(");

            for (call.args, 0..) |arg, i| {
                if (i > 0) try self.output.appendSlice(self.allocator, ", ");
                try self.genExpr(arg);
            }

            try self.output.appendSlice(self.allocator, ")");
        }
    }


    fn genList(self: *NativeCodegen, list: ast.Node.List) CodegenError!void {
        try self.output.appendSlice(self.allocator, "&[_]");

        // Infer element type
        const elem_type = if (list.elts.len > 0)
            try self.type_inferrer.inferExpr(list.elts[0])
        else
            .unknown;

        try elem_type.toZigType(self.allocator, &self.output);

        try self.output.appendSlice(self.allocator, "{");

        for (list.elts, 0..) |elem, i| {
            if (i > 0) try self.output.appendSlice(self.allocator, ", ");
            try self.genExpr(elem);
        }

        try self.output.appendSlice(self.allocator, "}");
    }

    fn genSubscript(self: *NativeCodegen, subscript: ast.Node.Subscript) CodegenError!void {
        try self.genExpr(subscript.value.*);
        try self.output.appendSlice(self.allocator, "[");

        switch (subscript.slice) {
            .index => |idx| try self.genExpr(idx.*),
            else => {},  // TODO: Slice support
        }

        try self.output.appendSlice(self.allocator, "]");
    }

    fn emit(self: *NativeCodegen, s: []const u8) CodegenError!void {
        try self.output.appendSlice(self.allocator, s);
    }

    fn emitIndent(self: *NativeCodegen) CodegenError!void {
        var i: usize = 0;
        while (i < self.indent_level) : (i += 1) {
            try self.output.appendSlice(self.allocator, "    ");
        }
    }

    fn indent(self: *NativeCodegen) void {
        self.indent_level += 1;
    }

    fn dedent(self: *NativeCodegen) void {
        self.indent_level -= 1;
    }
};
