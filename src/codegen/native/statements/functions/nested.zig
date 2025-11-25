/// Nested function (closure) code generation
const std = @import("std");
const ast = @import("../../../../ast.zig");
const NativeCodegen = @import("../../main.zig").NativeCodegen;
const CodegenError = @import("../../main.zig").CodegenError;
const body = @import("generators/body.zig");

/// Find variables captured from outer scope by nested function
fn findCapturedVars(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
) CodegenError![][]const u8 {
    var captured = std.ArrayList([]const u8){};

    // Collect all variables referenced in function body
    var referenced = std.ArrayList([]const u8){};
    defer referenced.deinit(self.allocator);

    try collectReferencedVars(self, func.body, &referenced);

    // Check which referenced vars are in outer scope (not params or local)
    for (referenced.items) |var_name| {
        // Skip if it's a function parameter
        var is_param = false;
        for (func.args) |arg| {
            if (std.mem.eql(u8, arg.name, var_name)) {
                is_param = true;
                break;
            }
        }
        if (is_param) continue;

        // Check if variable is in outer scope
        if (self.symbol_table.lookup(var_name) != null) {
            // Add to captured list (avoid duplicates)
            var already_captured = false;
            for (captured.items) |captured_var| {
                if (std.mem.eql(u8, captured_var, var_name)) {
                    already_captured = true;
                    break;
                }
            }
            if (!already_captured) {
                try captured.append(self.allocator, var_name);
            }
        }
    }

    return captured.toOwnedSlice(self.allocator);
}

/// Collect all variable names referenced in statements
fn collectReferencedVars(
    self: *NativeCodegen,
    stmts: []ast.Node,
    referenced: *std.ArrayList([]const u8),
) CodegenError!void {
    for (stmts) |stmt| {
        try collectReferencedVarsInNode(self, stmt, referenced);
    }
}

/// Collect variable names from a single node
fn collectReferencedVarsInNode(
    self: *NativeCodegen,
    node: ast.Node,
    referenced: *std.ArrayList([]const u8),
) CodegenError!void {
    switch (node) {
        .name => |n| {
            try referenced.append(self.allocator, n.id);
        },
        .binop => |b| {
            try collectReferencedVarsInNode(self, b.left.*, referenced);
            try collectReferencedVarsInNode(self, b.right.*, referenced);
        },
        .call => |c| {
            try collectReferencedVarsInNode(self, c.func.*, referenced);
            for (c.args) |arg| {
                try collectReferencedVarsInNode(self, arg, referenced);
            }
        },
        .return_stmt => |ret| {
            if (ret.value) |val| {
                try collectReferencedVarsInNode(self, val.*, referenced);
            }
        },
        .assign => |assign| {
            try collectReferencedVarsInNode(self, assign.value.*, referenced);
        },
        .compare => |cmp| {
            try collectReferencedVarsInNode(self, cmp.left.*, referenced);
            for (cmp.comparators) |comp| {
                try collectReferencedVarsInNode(self, comp, referenced);
            }
        },
        else => {},
    }
}

/// Generate nested function with closure support (immediate call only)
pub fn genNestedFunctionDef(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
) CodegenError!void {
    // Use captured variables from AST (pre-computed by closure analyzer)
    const captured_vars = func.captured_vars;

    if (captured_vars.len == 0) {
        // No captures - use ZeroClosure comptime pattern
        try self.emitIndent();
        try genZeroCaptureClosure(self, func);
        return;
    }

    // Generate comptime closure using runtime.Closure1 helper
    const closure_impl_name = try std.fmt.allocPrint(
        self.allocator,
        "__ClosureImpl_{s}_{d}",
        .{ func.name, self.lambda_counter },
    );
    defer self.allocator.free(closure_impl_name);
    self.lambda_counter += 1;

    // Generate the capture struct type (must be defined once and reused)
    const capture_type_name = try std.fmt.allocPrint(
        self.allocator,
        "__CaptureType_{s}_{d}",
        .{ func.name, self.lambda_counter },
    );
    defer self.allocator.free(capture_type_name);

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = struct {{", .{capture_type_name});
    for (captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        try self.output.writer(self.allocator).print(" {s}: i64", .{var_name});
    }
    try self.emit(" };\n");

    // Generate the inner function that takes (captures, args...)
    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{closure_impl_name});
    self.indent();

    // Generate static function that closure will call
    // Use unique name based on function name + counter to avoid shadowing
    const impl_fn_name = try std.fmt.allocPrint(
        self.allocator,
        "call_{s}_{d}",
        .{func.name, self.lambda_counter - 1},
    );
    defer self.allocator.free(impl_fn_name);

    try self.emitIndent();
    try self.output.writer(self.allocator).print("fn {s}(__captures: {s}", .{impl_fn_name, capture_type_name});

    for (func.args) |arg| {
        try self.output.writer(self.allocator).print(", {s}: i64", .{arg.name});
    }
    try self.emit(") i64 {\n");

    // Generate body with captures. prefix for captured vars
    self.indent();
    try self.pushScope();
    for (func.args) |arg| {
        try self.declareVar(arg.name);
    }

    for (func.body) |stmt| {
        try genStmtWithCaptureStruct(self, stmt, captured_vars);
    }

    self.popScope();
    self.dedent();

    try self.emitIndent();
    try self.emit("}\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // Create closure type using comptime helper based on arg count
    // Use unique variable name to avoid shadowing nested functions
    const closure_var_name = try std.fmt.allocPrint(
        self.allocator,
        "__closure_{s}_{d}",
        .{func.name, self.lambda_counter - 1},
    );
    defer self.allocator.free(closure_var_name);

    try self.emitIndent();
    if (func.args.len == 0) {
        // No arguments - use Closure0
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure0({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else if (func.args.len == 1) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure1({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else if (func.args.len == 2) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure2({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else if (func.args.len == 3) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure3({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    } else {
        // Fallback to single arg tuple
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.Closure1({s}, ",
            .{ closure_var_name, capture_type_name },
        );
    }

    // Arg types (skip for zero-arg closures)
    for (func.args, 0..) |_, i| {
        if (func.args.len > 1 and i > 0) try self.emit(", ");
        try self.emit("i64");
        if (func.args.len == 1 or i == func.args.len - 1) {
            try self.emit(", ");
        }
    }

    // Return type and function
    const impl_fn_ref = try std.fmt.allocPrint(
        self.allocator,
        "call_{s}_{d}",
        .{func.name, self.lambda_counter - 1},
    );
    defer self.allocator.free(impl_fn_ref);

    try self.output.writer(self.allocator).print(
        "i64, {s}.{s}){{ .captures = .{{",
        .{closure_impl_name, impl_fn_ref},
    );

    // Initialize captures
    for (captured_vars, 0..) |var_name, i| {
        if (i > 0) try self.emit(", ");
        try self.output.writer(self.allocator).print(" .{s} = {s}", .{ var_name, var_name });
    }
    try self.emit(" } };\n");

    // Create alias with original function name
    const closure_alias_name = try std.fmt.allocPrint(
        self.allocator,
        "__closure_{s}_{d}",
        .{func.name, self.lambda_counter - 1},
    );
    defer self.allocator.free(closure_alias_name);

    try self.emitIndent();
    try self.output.writer(self.allocator).print("const {s} = {s};\n", .{func.name, closure_alias_name});

    // Mark this variable as a closure so calls use .call() syntax
    const func_name_copy = try self.allocator.dupe(u8, func.name);
    try self.closure_vars.put(func_name_copy, {});
}

/// Generate zero-capture closure using comptime ZeroClosure
fn genZeroCaptureClosure(
    self: *NativeCodegen,
    func: ast.Node.FunctionDef,
) CodegenError!void {
    // Generate the inner function
    const impl_name = try std.fmt.allocPrint(
        self.allocator,
        "__ZeroImpl_{s}_{d}",
        .{ func.name, self.lambda_counter },
    );
    defer self.allocator.free(impl_name);
    self.lambda_counter += 1;

    try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{impl_name});
    self.indent();

    try self.emitIndent();
    try self.emit("fn inner(");
    for (func.args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try self.output.writer(self.allocator).print("{s}: i64", .{arg.name});
    }
    try self.emit(") i64 {\n");

    self.indent();
    try self.pushScope();
    for (func.args) |arg| {
        try self.declareVar(arg.name);
    }

    for (func.body) |stmt| {
        try self.generateStmt(stmt);
    }

    self.popScope();
    self.dedent();

    try self.emitIndent();
    try self.emit("}\n");

    self.dedent();
    try self.emitIndent();
    try self.emit("};\n");

    // Use ZeroClosure for single arg, or struct wrapper for multiple
    try self.emitIndent();
    if (func.args.len == 1) {
        try self.output.writer(self.allocator).print(
            "const {s} = runtime.ZeroClosure(i64, i64, {s}.inner){{}};\n",
            .{ func.name, impl_name },
        );
    } else {
        // Multiple args - create wrapper struct
        try self.output.writer(self.allocator).print("const {s} = struct {{\n", .{func.name});
        self.indent();
        try self.emitIndent();
        try self.emit("pub fn call(_: @This()");
        for (func.args) |arg| {
            try self.output.writer(self.allocator).print(", {s}: i64", .{arg.name});
        }
        try self.output.writer(self.allocator).print(") i64 {{\n", .{});
        self.indent();
        try self.emitIndent();
        try self.output.writer(self.allocator).print("return {s}.inner(", .{impl_name});
        for (func.args, 0..) |arg, i| {
            if (i > 0) try self.emit(", ");
            try self.emit(arg.name);
        }
        try self.emit(");\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}{};\n");
    }
}

/// Generate statement with captured variable references prefixed with "captures."
fn genStmtWithCaptureStruct(
    self: *NativeCodegen,
    stmt: ast.Node,
    captured_vars: [][]const u8,
) CodegenError!void {
    switch (stmt) {
        .return_stmt => |ret| {
            try self.emitIndent();
            try self.emit("return ");
            if (ret.value) |val| {
                try genExprWithCaptureStruct(self, val.*, captured_vars);
            }
            try self.emit(";\n");
        },
        else => {
            // For other statements, use regular generation
            try self.generateStmt(stmt);
        },
    }
}

/// Generate expression with captured variable references prefixed with "__captures."
fn genExprWithCaptureStruct(
    self: *NativeCodegen,
    node: ast.Node,
    captured_vars: [][]const u8,
) CodegenError!void {
    switch (node) {
        .name => |n| {
            // Check if this variable is captured
            for (captured_vars) |captured| {
                if (std.mem.eql(u8, n.id, captured)) {
                    try self.emit("__captures.");
                    try self.emit(n.id);
                    return;
                }
            }
            try self.emit(n.id);
        },
        .binop => |b| {
            try self.emit("(");
            try genExprWithCaptureStruct(self, b.left.*, captured_vars);

            const op_str = switch (b.op) {
                .Add => " + ",
                .Sub => " - ",
                .Mult => " * ",
                .Div => " / ",
                .FloorDiv => " / ",
                .Mod => " % ",
                .Pow => " ** ",
                .BitAnd => " & ",
                .BitOr => " | ",
                .BitXor => " ^ ",
                .LShift => " << ",
                .RShift => " >> ",
            };
            try self.emit(op_str);

            try genExprWithCaptureStruct(self, b.right.*, captured_vars);
            try self.emit(")");
        },
        .constant => |c| {
            const expressions = @import("../../expressions.zig");
            try expressions.genConstant(self, c);
        },
        .call => |c| {
            try genExprWithCaptureStruct(self, c.func.*, captured_vars);
            try self.emit("(");
            for (c.args, 0..) |arg, i| {
                if (i > 0) try self.emit(", ");
                try genExprWithCaptureStruct(self, arg, captured_vars);
            }
            try self.emit(")");
        },
        else => {
            const expressions = @import("../../expressions.zig");
            try expressions.genExpr(self, node);
        },
    }
}
