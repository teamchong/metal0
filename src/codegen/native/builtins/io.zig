/// File I/O builtins - open(), read, write, close
const std = @import("std");
const ast = @import("analysis.ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;
const builder_mod = @import("codegen.builder");

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

/// Helper to emit expression, extracting string from PyValue if uncertain
fn emitStringExpr(self: *NativeCodegen, expr: ast.Node) CodegenError!void {
    if (isExprUncertain(self, expr)) {
        try self.genExpr(expr);
        const b = try self.getBuilder();
        try b.write(".asString()");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    } else {
        try self.genExpr(expr);
    }
}

/// Generate code for open(filename, mode)
/// Returns a file handle that supports .read(), .write(), .close()
/// Two-Flow: Extracts filename string from PyValue if uncertain
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        const id = self.nextNameId();
        const b = try self.getBuilder();
        try b.writeFmt("(__m{d}_open: {{ @panic(\"open() requires at least 1 argument\"); }})", .{id});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
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
    // Use a wrapper struct that provides Python-like file API
    const id = self.nextNameId();
    {
        const b = try self.getBuilder();
        try b.writeFmt("__m{d}_open: {{\n", .{id});
        try b.write("    const __filename = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    // Two-Flow: Extract string from PyValue if filename is uncertain
    try emitStringExpr(self, filename);
    {
        const b = try self.getBuilder();
        try b.write(";\n");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }

    // Determine if read or write mode
    const is_write = std.mem.indexOf(u8, mode_str, "w") != null or
        std.mem.indexOf(u8, mode_str, "a") != null;

    {
        const b = try self.getBuilder();
        if (is_write) {
            try b.write("    const __file = try std.fs.cwd().createFile(__filename, .{});\n");
        } else {
            try b.write("    const __file = try std.fs.cwd().openFile(__filename, .{});\n");
        }
        try b.writeFmt("    break :__m{d}_open try runtime.PyFile.create(__global_allocator, __file, ", .{id});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    if (mode) |m| {
        // Two-Flow: Extract string from PyValue if mode is uncertain
        try emitStringExpr(self, m);
    } else {
        const b = try self.getBuilder();
        try b.write("\"r\"");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    {
        const b = try self.getBuilder();
        try b.write(");\n}");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

/// Generate code for input([prompt]) - read line from stdin
/// Two-Flow: Extracts prompt string from PyValue if uncertain
pub fn genInput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 1) {
        const id = self.nextNameId();
        const b = try self.getBuilder();
        try b.writeFmt("(__m{d}_input: {{ @panic(\"input() takes at most 1 argument\"); }})", .{id});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    {
        const b = try self.getBuilder();
        try b.write("runtime.builtins.input(__global_allocator, ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    if (args.len == 1) {
        // Two-Flow: Extract string from PyValue if prompt is uncertain
        try emitStringExpr(self, args[0]);
    } else {
        const b = try self.getBuilder();
        try b.write("\"\"");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    {
        const b = try self.getBuilder();
        try b.write(")");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

/// Generate code for breakpoint() - drop into debugger
pub fn genBreakpoint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    const b = try self.getBuilder();
    try b.write("runtime.builtins.breakpoint()");
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
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
        {
            const b = try self.getBuilder();
            try b.write("runtime.builtins.print(__global_allocator, &.{");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        for (args, 0..) |arg, i| {
            if (i > 0) {
                const b = try self.getBuilder();
                try b.write(", ");
                const output = b.getBodyAndClear();
                try self.output.appendSlice(self.allocator, output);
            }
            try self.genExpr(arg);
        }
        {
            const b = try self.getBuilder();
            try b.write("})");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        return;
    }

    // Use printWithOptions for keyword args
    {
        const b = try self.getBuilder();
        try b.write("runtime.builtins.printWithOptions(__global_allocator, &.{");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    for (args, 0..) |arg, i| {
        if (i > 0) {
            const b = try self.getBuilder();
            try b.write(", ");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(arg);
    }
    {
        const b = try self.getBuilder();
        try b.write("}, ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }

    // sep argument
    if (sep_expr) |sep| {
        try self.genExpr(sep);
    } else {
        const b = try self.getBuilder();
        try b.write("\" \"");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    {
        const b = try self.getBuilder();
        try b.write(", ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }

    // end argument
    if (end_expr) |end| {
        try self.genExpr(end);
    } else {
        const b = try self.getBuilder();
        try b.write("\"\\n\"");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    {
        const b = try self.getBuilder();
        try b.write(", ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }

    // file argument (null for stdout)
    if (file_expr) |file| {
        try self.genExpr(file);
    } else {
        const b = try self.getBuilder();
        try b.write("null");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    {
        const b = try self.getBuilder();
        try b.write(")");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

/// Generate code for aiter(async_iterable) - async iterator
/// Returns an async iterator object
pub fn genAiter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        const id = self.nextNameId();
        const b = try self.getBuilder();
        try b.writeFmt("(__m{d}_aiter: {{ @panic(\"aiter() takes exactly one argument\"); }})", .{id});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
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
        const b = try self.getBuilder();
        try b.writeFmt("(__m{d}_anext: {{ @panic(\"anext() missing required argument\"); }})", .{id});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    // For now, call __anext__ on the object
    try self.genExpr(args[0]);
    {
        const b = try self.getBuilder();
        try b.write(".__anext__()");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
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
        const b = try self.getBuilder();
        try b.writeFmt("(__m{d}_staticmethod: {{ @panic(\"staticmethod requires an argument\"); }})", .{id});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.genExpr(args[0]);
}

/// classmethod(func) - mark method as class method (cls as first arg)
/// In AOT, we just pass through since decoration is handled elsewhere
pub fn genClassmethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        const id = self.nextNameId();
        const b = try self.getBuilder();
        try b.writeFmt("(__m{d}_classmethod: {{ @panic(\"classmethod requires an argument\"); }})", .{id});
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.genExpr(args[0]);
}

/// property(fget=None, fset=None, fdel=None, doc=None) - create property descriptor
/// In AOT, creates a property struct with getter/setter/deleter
pub fn genProperty(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    {
        const b = try self.getBuilder();
        try b.write(".{ .fget = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        const b = try self.getBuilder();
        try b.write("null");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    {
        const b = try self.getBuilder();
        try b.write(", .fset = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        const b = try self.getBuilder();
        try b.write("null");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    {
        const b = try self.getBuilder();
        try b.write(", .fdel = ");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    if (args.len > 2) {
        try self.genExpr(args[2]);
    } else {
        const b = try self.getBuilder();
        try b.write("null");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
    {
        const b = try self.getBuilder();
        try b.write(" }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

// ============================================================================
// Interactive/REPL builtins - no-ops in AOT compiled code
// ============================================================================

/// help([object]) - display help (no-op in compiled code)
pub fn genHelp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    const b = try self.getBuilder();
    try b.write("{}"); // void
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

/// exit([code]) - exit the interpreter
pub fn genExit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        {
            const b = try self.getBuilder();
            try b.write("std.process.exit(@intCast(");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
        try self.genExpr(args[0]);
        {
            const b = try self.getBuilder();
            try b.write("))");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
        }
    } else {
        const b = try self.getBuilder();
        try b.write("std.process.exit(0)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
    }
}

/// quit([code]) - same as exit()
pub fn genQuit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try genExit(self, args);
}

/// license() - display license (no-op in compiled code)
pub fn genLicense(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    const b = try self.getBuilder();
    try b.write("{}"); // void
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

/// credits() - display credits (no-op in compiled code)
pub fn genCredits(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    const b = try self.getBuilder();
    try b.write("{}"); // void
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

/// copyright() - display copyright (no-op in compiled code)
pub fn genCopyright(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    const b = try self.getBuilder();
    try b.write("{}"); // void
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
