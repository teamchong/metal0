/// Python builtins module - Built-in functions exposed as module
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;
const collections = @import("builtins/collections.zig");
const builtins = @import("builtins.zig");

// Comptime generators
fn genFmt(comptime prefix: []const u8, comptime fmt: []const u8, comptime default: []const u8) h.H {
    return struct {
        fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            if (args.len > 0) { try self.emit("(try std.fmt.allocPrint(__global_allocator, \"" ++ prefix ++ "{" ++ fmt ++ "}\", .{"); try self.genExpr(args[0]); try self.emit("}))"); }
            else try self.emit("\"" ++ default ++ "\"");
        }
    }.f;
}
fn genTrueWithSideEffect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 1 and args[0] == .call) { try self.emit("blk: { _ = "); try self.genExpr(args[0]); try self.emit("; break :blk true; }"); } else try self.emit("true");
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
    .{ "len", genLen }, .{ "abs", genAbs },
    .{ "isinstance", genIsinstance }, .{ "issubclass", genTrueWithSideEffect }, .{ "hasattr", genTrueWithSideEffect },
    .{ "getattr", genGetattr }, .{ "setattr", genVoidWithSideEffect }, .{ "delattr", genVoidWithSideEffect }, .{ "callable", genTrueWithSideEffect },
    .{ "repr", h.c("\"\"") }, .{ "ascii", h.c("\"\"") },
    .{ "hex", genFmt("0x", "x", "0x0") }, .{ "oct", genFmt("0o", "o", "0o0") }, .{ "bin", genFmt("0b", "b", "0b0") },
    .{ "id", h.I64(0) }, .{ "type", h.c("type") },
    .{ "dir", h.c("&[_][]const u8{}") }, .{ "vars", h.c(".{}") }, .{ "globals", h.c(".{}") }, .{ "locals", h.c(".{}") },
    .{ "eval", h.c("@as(?*anyopaque, null)") }, .{ "exec", h.c("{}") }, .{ "compile", h.c("@as(?*anyopaque, null)") },
    .{ "input", h.c("\"\"") }, .{ "format", h.c("\"\"") },
    .{ "iter", h.pass("@as(?*anyopaque, null)") }, .{ "next", h.c("@as(?*anyopaque, null)") },
    .{ "slice", h.c(".{ .start = @as(?i64, null), .stop = @as(?i64, null), .step = @as(?i64, null) }") },
    .{ "staticmethod", h.pass("@as(?*anyopaque, null)") }, .{ "classmethod", h.pass("@as(?*anyopaque, null)") },
    .{ "property", h.c(".{ .fget = @as(?*anyopaque, null), .fset = @as(?*anyopaque, null), .fdel = @as(?*anyopaque, null), .doc = @as(?[]const u8, null) }") },
    .{ "super", genSuper }, .{ "object", h.c(".{}") }, .{ "breakpoint", h.c("{}") }, .{ "__import__", h.c("@as(?*anyopaque, null)") },
    // Exception types
    .{ "Exception", h.err("Exception") }, .{ "BaseException", h.err("BaseException") },
    .{ "TypeError", h.err("TypeError") }, .{ "ValueError", h.err("ValueError") },
    .{ "KeyError", h.err("KeyError") }, .{ "IndexError", h.err("IndexError") },
    .{ "AttributeError", h.err("AttributeError") }, .{ "NameError", h.err("NameError") },
    .{ "RuntimeError", h.err("RuntimeError") }, .{ "StopIteration", h.err("StopIteration") },
    .{ "GeneratorExit", h.err("GeneratorExit") }, .{ "ArithmeticError", h.err("ArithmeticError") },
    .{ "ZeroDivisionError", h.err("ZeroDivisionError") }, .{ "OverflowError", h.err("OverflowError") },
    .{ "FloatingPointError", h.err("FloatingPointError") }, .{ "LookupError", h.err("LookupError") },
    .{ "AssertionError", h.err("AssertionError") }, .{ "ImportError", h.err("ImportError") },
    .{ "ModuleNotFoundError", h.err("ModuleNotFoundError") }, .{ "OSError", h.err("OSError") },
    .{ "FileNotFoundError", h.err("FileNotFoundError") }, .{ "FileExistsError", h.err("FileExistsError") },
    .{ "PermissionError", h.err("PermissionError") }, .{ "IsADirectoryError", h.err("IsADirectoryError") },
    .{ "NotADirectoryError", h.err("NotADirectoryError") }, .{ "TimeoutError", h.err("TimeoutError") },
    .{ "ConnectionError", h.err("ConnectionError") }, .{ "BrokenPipeError", h.err("BrokenPipeError") },
    .{ "ConnectionAbortedError", h.err("ConnectionAbortedError") }, .{ "ConnectionRefusedError", h.err("ConnectionRefusedError") },
    .{ "ConnectionResetError", h.err("ConnectionResetError") }, .{ "EOFError", h.err("EOFError") },
    .{ "MemoryError", h.err("MemoryError") }, .{ "RecursionError", h.err("RecursionError") },
    .{ "SystemError", h.err("SystemError") }, .{ "SystemExit", h.err("SystemExit") },
    .{ "KeyboardInterrupt", h.err("KeyboardInterrupt") }, .{ "NotImplementedError", h.err("NotImplementedError") },
    .{ "IndentationError", h.err("IndentationError") }, .{ "TabError", h.err("TabError") },
    .{ "SyntaxError", h.err("SyntaxError") }, .{ "UnicodeError", h.err("UnicodeError") },
    .{ "UnicodeDecodeError", h.err("UnicodeDecodeError") }, .{ "UnicodeEncodeError", h.err("UnicodeEncodeError") },
    .{ "UnicodeTranslateError", h.err("UnicodeTranslateError") }, .{ "BufferError", h.err("BufferError") },
    // Warnings
    .{ "Warning", h.err("Warning") }, .{ "UserWarning", h.err("UserWarning") },
    .{ "DeprecationWarning", h.err("DeprecationWarning") }, .{ "PendingDeprecationWarning", h.err("PendingDeprecationWarning") },
    .{ "SyntaxWarning", h.err("SyntaxWarning") }, .{ "RuntimeWarning", h.err("RuntimeWarning") },
    .{ "FutureWarning", h.err("FutureWarning") }, .{ "ImportWarning", h.err("ImportWarning") },
    .{ "UnicodeWarning", h.err("UnicodeWarning") }, .{ "BytesWarning", h.err("BytesWarning") },
    .{ "ResourceWarning", h.err("ResourceWarning") },
    // Constants
    .{ "True", h.c("true") }, .{ "False", h.c("false") }, .{ "None", h.c("null") },
    .{ "Ellipsis", h.c(".{}") }, .{ "NotImplemented", h.c(".{}") },
});

fn genLen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("@as(i64, "); try self.genExpr(args[0]); try self.emit(".len)"); } else try self.emit("@as(i64, 0)");
}

fn genAbs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) { try self.emit("@abs("); try self.genExpr(args[0]); try self.emit(")"); } else try self.emit("@as(i64, 0)");
}

pub fn genIsinstance(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        const has_side_effects = args[0] == .call or args[1] == .call;
        if (has_side_effects) {
            try self.emit("blk: { ");
            if (args[0] == .call) { try self.emit("_ = "); try self.genExpr(args[0]); try self.emit("; "); }
            if (args[1] == .call) { try self.emit("_ = "); try self.genExpr(args[1]); try self.emit("; "); }
            try self.emit("break :blk true; }");
        } else try self.emit("true");
    } else if (args.len >= 1 and args[0] == .call) {
        try self.emit("blk: { _ = "); try self.genExpr(args[0]); try self.emit("; break :blk true; }");
    } else try self.emit("true");
}

fn genGetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 1 and args[0] == .call) { try self.emit("blk: { _ = "); try self.genExpr(args[0]); try self.emit("; break :blk @as(?*anyopaque, null); }"); }
    else try self.emit("@as(?*anyopaque, null)");
}

fn genVoidWithSideEffect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 1 and args[0] == .call) { try self.emit("blk: { _ = "); try self.genExpr(args[0]); try self.emit("; break :blk {}; }"); }
    else try self.emit("{}");
}

pub const genSlice = h.c(".{ .start = @as(?i64, null), .stop = @as(?i64, null), .step = @as(?i64, null) }");

pub fn genSuper(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    if (self.current_class_name) |current_class| {
        if (self.getParentClassName(current_class)) |parent_class| {
            try self.emit("@as(*const "); try self.emit(parent_class); try self.emit(", @ptrCast(__self))");
            return;
        }
    }
    const id = self.block_label_counter;
    self.block_label_counter += 1;
    try self.output.writer(self.allocator).print("super_{d}: {{ break :super_{d} .{{}}; }}", .{ id, id });
}
