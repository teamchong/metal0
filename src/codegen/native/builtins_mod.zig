/// Python builtins module - Built-in functions exposed as module
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;
const collections = @import("builtins/collections.zig");
const builtins = @import("builtins.zig");
const expressions = @import("expressions.zig");
const expr_emitter = @import("expr_emitter.zig");

// Helper for simple constant output
fn emitConst(self: *NativeCodegen, val: []const u8) CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

// Comptime generators
fn genFmt(comptime prefix: []const u8, comptime fmt: []const u8, comptime default: []const u8) h.H {
    return struct {
        fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            if (args.len > 0) {
                {
                    const b = try self.getBuilder();
                    try b.write("(try std.fmt.allocPrint(__global_allocator, \"" ++ prefix ++ "{" ++ fmt ++ "}\", .{");
                    const output = b.getBodyAndClear();
                    try self.output.appendSlice(self.allocator, output);
                }
                try self.genExpr(args[0]);
                try emitConst(self, "}))");
            } else try emitConst(self, "\"" ++ default ++ "\"");
        }
    }.f;
}

fn sideEffect(self: *NativeCodegen, args: []ast.Node, comptime default: []const u8) CodegenError!void {
    if (args.len >= 1 and args[0] == .call) {
        try self.withInlineBlock("side", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                const b = try c.getBuilder();
                try b.write("_ = ");
                const output1 = b.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output1);
                try c.genExpr(a[0]);
                {
                    const b2 = try c.getBuilder();
                    try b2.writeFmt("; break :{s} " ++ default, .{label});
                    const output2 = b2.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output2);
                }
            }
        }.emit);
    } else {
        try emitConst(self, default);
    }
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Forwarding to collections.zig
    .{ "range", collections.genRange }, .{ "enumerate", collections.genEnumerate }, .{ "zip", collections.genZip },
    .{ "map", collections.genMap }, .{ "filter", collections.genFilter }, .{ "sorted", collections.genSorted },
    .{ "reversed", collections.genReversed }, .{ "sum", collections.genSum }, .{ "all", collections.genAll }, .{ "any", collections.genAny },
    // Forwarding to builtins.zig
    .{ "min", builtins.genMin }, .{ "max", builtins.genMax }, .{ "chr", builtins.genChr }, .{ "ord", builtins.genOrd },
    .{ "pow", builtins.genPow }, .{ "round", builtins.genRound }, .{ "divmod", builtins.genDivmod }, .{ "hash", builtins.genHash },
    // Simple implementations
    .{ "open", h.c("@as(?*anyopaque, null)") }, .{ "print", h.c("{}") },
    .{ "len", h.wrap("@as(i64, ", ".len)", "@as(i64, 0)") },
    .{ "abs", h.wrap("@abs(", ")", "@as(i64, 0)") },
    .{ "isinstance", genIsinstance }, .{ "issubclass", genTrue }, .{ "hasattr", genTrue },
    .{ "getattr", genNull }, .{ "setattr", genVoid }, .{ "delattr", genVoid }, .{ "callable", genTrue },
    .{ "repr", h.c("\"\"") }, .{ "ascii", h.c("\"\"") },
    .{ "hex", genFmt("0x", "x", "0x0") }, .{ "oct", genFmt("0o", "o", "0o0") }, .{ "bin", genFmt("0b", "b", "0b0") },
    .{ "id", h.I64(0) }, .{ "type", h.c("type") },
    .{ "dir", h.c("&[_][]const u8{}") }, .{ "vars", h.c(".{}") }, .{ "globals", h.c(".{}") }, .{ "locals", h.c(".{}") },
    .{ "eval", h.c("@as(?*anyopaque, null)") }, .{ "exec", h.c("{}") }, .{ "compile", h.c("@as(?*anyopaque, null)") },
    .{ "input", h.c("\"\"") }, .{ "format", h.c("\"\"") },
    .{ "iter", h.pass("@as(?*anyopaque, null)") }, .{ "next", h.c("@as(?*anyopaque, null)") },
    .{ "slice", genSlice },
    .{ "staticmethod", h.pass("@as(?*anyopaque, null)") }, .{ "classmethod", h.pass("@as(?*anyopaque, null)") },
    .{ "property", h.c(".{ .fget = @as(?*anyopaque, null), .fset = @as(?*anyopaque, null), .fdel = @as(?*anyopaque, null), .doc = @as(?[]const u8, null) }") },
    .{ "super", genSuper }, .{ "object", h.c(".{}") }, .{ "breakpoint", h.c("{}") }, .{ "__import__", h.c("@as(?*anyopaque, null)") },
    // Exception types
    .{ "Exception", h.err("Exception") }, .{ "BaseException", h.err("BaseException") }, .{ "TypeError", h.err("TypeError") }, .{ "ValueError", h.err("ValueError") },
    .{ "KeyError", h.err("KeyError") }, .{ "IndexError", h.err("IndexError") }, .{ "AttributeError", h.err("AttributeError") }, .{ "NameError", h.err("NameError") },
    .{ "RuntimeError", h.err("RuntimeError") }, .{ "StopIteration", h.err("StopIteration") }, .{ "GeneratorExit", h.err("GeneratorExit") }, .{ "ArithmeticError", h.err("ArithmeticError") },
    .{ "ZeroDivisionError", h.err("ZeroDivisionError") }, .{ "OverflowError", h.err("OverflowError") }, .{ "FloatingPointError", h.err("FloatingPointError") }, .{ "LookupError", h.err("LookupError") },
    .{ "AssertionError", h.err("AssertionError") }, .{ "ImportError", h.err("ImportError") }, .{ "ModuleNotFoundError", h.err("ModuleNotFoundError") }, .{ "OSError", h.err("OSError") },
    .{ "FileNotFoundError", h.err("FileNotFoundError") }, .{ "FileExistsError", h.err("FileExistsError") }, .{ "PermissionError", h.err("PermissionError") }, .{ "IsADirectoryError", h.err("IsADirectoryError") },
    .{ "NotADirectoryError", h.err("NotADirectoryError") }, .{ "TimeoutError", h.err("TimeoutError") }, .{ "ConnectionError", h.err("ConnectionError") }, .{ "BrokenPipeError", h.err("BrokenPipeError") },
    .{ "ConnectionAbortedError", h.err("ConnectionAbortedError") }, .{ "ConnectionRefusedError", h.err("ConnectionRefusedError") }, .{ "ConnectionResetError", h.err("ConnectionResetError") }, .{ "EOFError", h.err("EOFError") },
    .{ "MemoryError", h.err("MemoryError") }, .{ "RecursionError", h.err("RecursionError") }, .{ "SystemError", h.err("SystemError") }, .{ "SystemExit", h.err("SystemExit") },
    .{ "KeyboardInterrupt", h.err("KeyboardInterrupt") }, .{ "NotImplementedError", h.err("NotImplementedError") }, .{ "IndentationError", h.err("IndentationError") }, .{ "TabError", h.err("TabError") },
    .{ "SyntaxError", h.err("SyntaxError") }, .{ "UnicodeError", h.err("UnicodeError") }, .{ "UnicodeDecodeError", h.err("UnicodeDecodeError") }, .{ "UnicodeEncodeError", h.err("UnicodeEncodeError") },
    .{ "UnicodeTranslateError", h.err("UnicodeTranslateError") }, .{ "BufferError", h.err("BufferError") },
    // Additional exceptions
    .{ "BlockingIOError", h.err("BlockingIOError") }, .{ "UnboundLocalError", h.err("UnboundLocalError") },
    .{ "WindowsError", h.err("OSError") },  // WindowsError is an alias for OSError
    .{ "InterruptedError", h.err("InterruptedError") }, .{ "ChildProcessError", h.err("ChildProcessError") },
    .{ "ProcessLookupError", h.err("ProcessLookupError") }, .{ "EnvironmentError", h.err("OSError") },  // EnvironmentError is an alias for OSError
    // Exception groups (Python 3.11+)
    .{ "ExceptionGroup", h.err("ExceptionGroup") }, .{ "BaseExceptionGroup", h.err("BaseExceptionGroup") },
    // Warnings
    .{ "Warning", h.err("Warning") }, .{ "UserWarning", h.err("UserWarning") }, .{ "DeprecationWarning", h.err("DeprecationWarning") }, .{ "PendingDeprecationWarning", h.err("PendingDeprecationWarning") },
    .{ "SyntaxWarning", h.err("SyntaxWarning") }, .{ "RuntimeWarning", h.err("RuntimeWarning") }, .{ "FutureWarning", h.err("FutureWarning") }, .{ "ImportWarning", h.err("ImportWarning") },
    .{ "UnicodeWarning", h.err("UnicodeWarning") }, .{ "BytesWarning", h.err("BytesWarning") }, .{ "ResourceWarning", h.err("ResourceWarning") },
    // Constants
    .{ "True", h.c("true") }, .{ "False", h.c("false") }, .{ "None", h.c("null") },
    .{ "Ellipsis", h.c(".{}") }, .{ "NotImplemented", h.c(".{}") },
});

fn genIsinstance(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2 and (args[0] == .call or args[1] == .call)) {
        try self.withInlineBlock("isinstance", args, struct {
            fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
                if (a[0] == .call) {
                    const b = try c.getBuilder();
                    try b.write("_ = ");
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                    try c.genExpr(a[0]);
                    try emitConst(c, "; ");
                }
                if (a[1] == .call) {
                    const b = try c.getBuilder();
                    try b.write("_ = ");
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                    try c.genExpr(a[1]);
                    try emitConst(c, "; ");
                }
                {
                    const b = try c.getBuilder();
                    try b.writeFmt("break :{s} true", .{label});
                    const output = b.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output);
                }
            }
        }.emit);
    } else try sideEffect(self, args, "true");
}
fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try sideEffect(self, args, "true"); }
fn genNull(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try sideEffect(self, args, "@as(?*anyopaque, null)"); }
fn genVoid(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try sideEffect(self, args, "{{}}"); }

pub fn genSlice(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // slice(stop) or slice(start, stop) or slice(start, stop, step)
    try emitConst(self, ".{ .start = ");
    if (args.len >= 2) {
        try emitConst(self, "@as(?i64, ");
        try expressions.genExpr(self, args[0]);
        try emitConst(self, ")");
    } else {
        try emitConst(self, "@as(?i64, null)");
    }
    try emitConst(self, ", .stop = ");
    if (args.len >= 1) {
        try emitConst(self, "@as(?i64, ");
        if (args.len == 1) {
            try expressions.genExpr(self, args[0]);
        } else {
            try expressions.genExpr(self, args[1]);
        }
        try emitConst(self, ")");
    } else {
        try emitConst(self, "@as(?i64, null)");
    }
    try emitConst(self, ", .step = ");
    if (args.len >= 3) {
        try emitConst(self, "@as(?i64, ");
        try expressions.genExpr(self, args[2]);
        try emitConst(self, ")");
    } else {
        try emitConst(self, "@as(?i64, null)");
    }
    try emitConst(self, " }");
}

pub fn genSuper(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    if (self.current_class_name) |current_class| {
        if (self.getParentClassName(current_class)) |parent_class| {
            const b = try self.getBuilder();
            try b.write("@as(*const ");
            try b.write(parent_class);
            try b.write(", @ptrCast(__self))");
            const output = b.getBodyAndClear();
            try self.output.appendSlice(self.allocator, output);
            return;
        }
    }
    var em = self.exprEmitter();
    const id = em.reserveLabelId();
    const b = try self.getBuilder();
    try b.writeFmt("super_{d}: {{ break :super_{d} .{{}}; }}", .{ id, id });
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}
