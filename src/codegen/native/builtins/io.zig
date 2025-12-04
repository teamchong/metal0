/// File I/O builtins - open(), read, write, close
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

/// Generate code for open(filename, mode)
/// Returns a file handle that supports .read(), .write(), .close()
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) {
        try self.emit("@compileError(\"open() requires at least 1 argument\")");
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
    try self.emit("blk: {\n");
    try self.emitIndent();
    try self.emit("    const __filename = ");
    try self.genExpr(filename);
    try self.emit(";\n");
    try self.emitIndent();

    // Determine if read or write mode
    const is_write = std.mem.indexOf(u8, mode_str, "w") != null or
        std.mem.indexOf(u8, mode_str, "a") != null;

    if (is_write) {
        try self.emit("    const __file = try std.fs.cwd().createFile(__filename, .{});\n");
    } else {
        try self.emit("    const __file = try std.fs.cwd().openFile(__filename, .{});\n");
    }

    try self.emitIndent();
    try self.emit("    break :blk try runtime.PyFile.create(__global_allocator, __file, ");
    if (mode) |m| {
        try self.genExpr(m);
    } else {
        try self.emit("\"r\"");
    }
    try self.emit(");\n");
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for input([prompt]) - read line from stdin
pub fn genInput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 1) {
        try self.emit("@compileError(\"input() takes at most 1 argument\")");
        return;
    }
    try self.emit("runtime.builtins.input(__global_allocator, ");
    if (args.len == 1) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("\"\"");
    }
    try self.emit(")");
}

/// Generate code for breakpoint() - drop into debugger
pub fn genBreakpoint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("runtime.builtins.breakpoint()");
}

/// Generate code for print(*args, sep=" ", end="\\n", file=sys.stdout, flush=False)
pub fn genPrint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("runtime.builtins.print(__global_allocator, &.{");
    for (args, 0..) |arg, i| {
        if (i > 0) try self.emit(", ");
        try self.genExpr(arg);
    }
    try self.emit("})");
}

/// Generate code for aiter(async_iterable) - async iterator
/// Returns an async iterator object
pub fn genAiter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len != 1) {
        try self.emit("@compileError(\"aiter() takes exactly one argument\")");
        return;
    }
    // For now, just return the object (which should have __aiter__)
    try self.genExpr(args[0]);
}

/// Generate code for anext(async_iterator[, default]) - get next from async iterator
/// Returns the next item from async iterator
pub fn genAnext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@compileError(\"anext() missing required argument\")");
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
        try self.emit("@compileError(\"staticmethod requires an argument\")");
        return;
    }
    try self.genExpr(args[0]);
}

/// classmethod(func) - mark method as class method (cls as first arg)
/// In AOT, we just pass through since decoration is handled elsewhere
pub fn genClassmethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@compileError(\"classmethod requires an argument\")");
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
