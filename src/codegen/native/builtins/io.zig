/// File I/O builtins - open(), read, write, close
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const builder_mod = @import("codegen.builder");

// MIGRATED TO ZIGBUILDER

/// Check if an expression is uncertain (needs PyValue operations)
/// Two-Flow: routes uncertain values to PyValue extraction
fn isExprUncertain(self: *NativeCodegen, expr: ast.Node) bool {
    if (expr == .name) {
        const name = expr.name.id;
        const var_type = self.type_inferrer.getScopedVar(name) orelse
            self.type_inferrer.var_types.get(name);
        if (var_type) |vt| {
            switch (vt) {
                .pyvalue, .unknown => return true,
                else => {},
            }
        }
        return false;
    }
    return false;
}

/// Helper to emit expression, extracting string using runtime.container_dispatch.toPathStr
/// This handles all cases: []const u8 (passthrough), PyValue (.string field), eval() results
/// Uses emitCallCtx for guaranteed bracket matching
fn emitStringExpr(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    // Use toPathStr for robust type extraction - works with any input type
    try self.emitCallCtx("runtime.container_dispatch.toPathStr", expr, struct {
        pub fn f(s: *NativeCodegen, e: ast.Node) CodegenError!void {
            try s.emitCallCtx("@TypeOf", e, struct {
                pub fn g(s2: *NativeCodegen, e2: ast.Node) CodegenError!void {
                    try s2.genExpr(e2);
                }
            }.g);
            try s.emit(", ");
            try s.genExpr(e);
        }
    }.f);
}

/// Generate code for open(filename, mode)
/// Returns a file handle that supports .read(), .write(), .close()
/// Two-Flow: Extracts filename string from PyValue if uncertain
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_open: {{ @panic(\"open() requires at least 1 argument\"); }})", .{id});
        return;
    }

    // Get filename argument
    const filename = args[0];

    // Get mode argument (default "r")
    const mode = if (args.len >= 2) args[1] else null;

    // Determine mode string
    var mode_str: []const u8 = "r";
    if (mode) |m| {
        if (m == .constant) {
            if (m.constant.value == .string) {
                mode_str = m.constant.value.string;
            }
        }
    }

    // Generate Zig code for file opening
    const id = self.nextNameId();
    try self.emitFmt("__m{d}_open: {{\n", .{id});
    try self.emit("    const __filename = ");
    // Two-Flow: Extract string from PyValue if filename is uncertain
    try emitStringExpr(self, filename);
    try self.emit(";\n");

    // Determine if read or write mode
    const is_write = std.mem.indexOf(u8, mode_str, "w") != null or
        std.mem.indexOf(u8, mode_str, "a") != null;

    if (is_write) {
        try self.emit("    const __file = try std.fs.cwd().createFile(__filename, .{});\n");
    } else {
        try self.emit("    const __file = try std.fs.cwd().openFile(__filename, .{});\n");
    }
    try self.emitFmt("    break :__m{d}_open try runtime.PyFile.create(__global_allocator, __file, ", .{id});

    if (mode) |m| {
        // Two-Flow: Extract string from PyValue if mode is uncertain
        try emitStringExpr(self, m);
    } else {
        try self.emit("\"r\"");
    }
    try self.emit(");\n}");
}

/// Generate code for input([prompt]) - read line from stdin
/// Two-Flow: Extracts prompt string from PyValue if uncertain
pub fn genInput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 1) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_input: {{ @panic(\"input() takes at most 1 argument\"); }})", .{id});
        return;
    }
    // Use emitCallCtx for guaranteed bracket matching
    const Ctx = struct { a: []ast.Node };
    try self.emitCallCtx("runtime.builtins.input", Ctx{ .a = args }, struct {
        pub fn f(s: *NativeCodegen, ctx: Ctx) CodegenError!void {
            try s.emit("__global_allocator, ");
            if (ctx.a.len == 1) {
                // Two-Flow: Extract string from PyValue if prompt is uncertain
                try emitStringExpr(s, ctx.a[0]);
            } else {
                try s.emit("\"\"");
            }
        }
    }.f);
}

/// Generate code for breakpoint() - drop into debugger
pub fn genBreakpoint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("runtime.builtins.breakpoint()");
}

/// Generate code for print(*args, sep=" ", end="\\n", file=sys.stdout, flush=False)
pub fn genPrint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genPrintWithKeywords(self, args, &.{});
}

/// Generate code for print() with keyword arguments support
pub fn genPrintWithKeywords(self: *NativeCodegen, args: []ast.Node, keyword_args: []const ast.Node.KeywordArg) CodegenError!void {
    // Extract keyword arguments
    var sep_expr: ?ast.Node = null;
    var end_expr: ?ast.Node = null;
    var file_expr: ?ast.Node = null;

    for (keyword_args) |kw| {
        if (std.mem.eql(u8, kw.name, "sep")) {
            sep_expr = kw.value;
        } else if (std.mem.eql(u8, kw.name, "end")) {
            end_expr = kw.value;
        } else if (std.mem.eql(u8, kw.name, "file")) {
            file_expr = kw.value;
        }
        // Ignore flush= for now (Zig stdout is unbuffered)
    }

    // If no keyword args, use simple print for efficiency
    if (sep_expr == null and end_expr == null and file_expr == null) {
        try self.emit("runtime.builtins.print(__global_allocator, &.{");
        for (args, 0..) |arg, i| {
            if (i > 0) try self.emit(", ");
            try self.genExpr(arg);
        }
        try self.emit("})");
        return;
    }

    // Use printWithOptions for keyword args
    try self.emit("runtime.builtins.printWithOptions(__global_allocator, &.{");
    for (args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try self.genExpr(arg);
    }
    try self.emit("}, ");

    // sep argument
    if (sep_expr) |sep| {
        try self.genExpr(sep);
    } else {
        try self.emit("\" \"");
    }
    try self.emit(", ");

    // end argument
    if (end_expr) |end| {
        try self.genExpr(end);
    } else {
        try self.emit("\"\\n\"");
    }
    try self.emit(", ");

    // file argument (null for stdout)
    if (file_expr) |file| {
        try self.genExpr(file);
    } else {
        try self.emit("null");
    }
    try self.emit(")");
}

/// Generate code for aiter(async_iterable) - async iterator
/// Returns an async iterator object
pub fn genAiter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_aiter: {{ @panic(\"aiter() takes exactly one argument\"); }})", .{id});
        return;
    }
    // For now, just return the object (which should have __aiter__)
    try self.genExpr(args[0]);
}

/// Generate code for anext(async_iterator[, default]) - get next from async iterator
/// Returns the next item from async iterator
pub fn genAnext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_anext: {{ @panic(\"anext() missing required argument\"); }})", .{id});
        return;
    }
    // For now, call __anext__ on the object
    try self.genExpr(args[0]);
    try self.emit(".__anext__()");
}

// ============================================================================
// Decorator builtins - pass through the function/method in AOT compilation
// The actual decoration is handled at class/function definition time
// ============================================================================

/// staticmethod(func) - mark method as static (no self)
/// In AOT, we just pass through since decoration is handled elsewhere
pub fn genStaticmethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_staticmethod: {{ @panic(\"staticmethod requires an argument\"); }})", .{id});
        return;
    }
    try self.genExpr(args[0]);
}

/// classmethod(func) - mark method as class method (cls as first arg)
/// In AOT, we just pass through since decoration is handled elsewhere
pub fn genClassmethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        const id = self.nextNameId();
        try self.emitFmt("(__m{d}_classmethod: {{ @panic(\"classmethod requires an argument\"); }})", .{id});
        return;
    }
    try self.genExpr(args[0]);
}

/// property(fget=None, fset=None, fdel=None, doc=None) - create property descriptor
/// In AOT, creates a property struct with getter/setter/deleter
pub fn genProperty(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit(".{ .fget = ");
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("null");
    }
    try self.emit(", .fset = ");
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("null");
    }
    try self.emit(", .fdel = ");
    if (args.len > 2) {
        try self.genExpr(args[2]);
    } else {
        try self.emit("null");
    }
    try self.emit(" }");
}

// ============================================================================
// Interactive/REPL builtins - no-ops in AOT compiled code
// ============================================================================

/// help([object]) - display help (no-op in compiled code)
pub fn genHelp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}"); // void
}

/// exit([code]) - exit the interpreter
pub fn genExit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("std.process.exit(@intCast(");
        try self.genExpr(args[0]);
        try self.emit("))");
    } else {
        try self.emit("std.process.exit(0)");
    }
}

/// quit([code]) - same as exit()
pub fn genQuit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genExit(self, args);
}

/// license() - display license (no-op in compiled code)
pub fn genLicense(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}"); // void
}

/// credits() - display credits (no-op in compiled code)
pub fn genCredits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}"); // void
}

/// copyright() - display copyright (no-op in compiled code)
pub fn genCopyright(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}"); // void
}
