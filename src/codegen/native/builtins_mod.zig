/// Python builtins module - Built-in functions exposed as module
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;
const collections = @import("builtins/collections.zig");
const builtins = @import("builtins.zig");

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

// Comptime generators
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}
fn genError(comptime name: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit("error." ++ name); } }.f;
}
fn genFmt(comptime prefix: []const u8, comptime fmt: []const u8, comptime default: []const u8) ModuleHandler {
    return struct {
        fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            if (args.len > 0) { try self.emit("(try std.fmt.allocPrint(__global_allocator, \"" ++ prefix ++ "{" ++ fmt ++ "}\", .{"); try self.genExpr(args[0]); try self.emit("}))"); }
            else try self.emit("\"" ++ default ++ "\"");
        }
    }.f;
}
fn genPassFirst(comptime default: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { if (args.len > 0) try self.genExpr(args[0]) else try self.emit(default); } }.f;
}
fn genTrueWithSideEffect(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 1 and args[0] == .call) { try self.emit("blk: { _ = "); try self.genExpr(args[0]); try self.emit("; break :blk true; }"); } else try self.emit("true");
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    // Forwarding to collections.zig
    .{ "range", collections.genRange }, .{ "enumerate", collections.genEnumerate }, .{ "zip", collections.genZip },
    .{ "map", collections.genMap }, .{ "filter", collections.genFilter }, .{ "sorted", collections.genSorted },
    .{ "reversed", collections.genReversed }, .{ "sum", collections.genSum }, .{ "all", collections.genAll }, .{ "any", collections.genAny },
    // Forwarding to builtins.zig
    .{ "min", builtins.genMin }, .{ "max", builtins.genMax }, .{ "chr", builtins.genChr }, .{ "ord", builtins.genOrd },
    .{ "pow", builtins.genPow }, .{ "round", builtins.genRound }, .{ "divmod", builtins.genDivmod }, .{ "hash", builtins.genHash },
    // Simple implementations
    .{ "open", genConst("@as(?*anyopaque, null)") }, .{ "print", genConst("{}") },
    .{ "len", genLen }, .{ "abs", genAbs },
    .{ "isinstance", genIsinstance }, .{ "issubclass", genTrueWithSideEffect }, .{ "hasattr", genTrueWithSideEffect },
    .{ "getattr", genGetattr }, .{ "setattr", genVoidWithSideEffect }, .{ "delattr", genVoidWithSideEffect }, .{ "callable", genTrueWithSideEffect },
    .{ "repr", genConst("\"\"") }, .{ "ascii", genConst("\"\"") },
    .{ "hex", genFmt("0x", "x", "0x0") }, .{ "oct", genFmt("0o", "o", "0o0") }, .{ "bin", genFmt("0b", "b", "0b0") },
    .{ "id", genConst("@as(i64, 0)") }, .{ "type", genConst("type") },
    .{ "dir", genConst("&[_][]const u8{}") }, .{ "vars", genConst(".{}") }, .{ "globals", genConst(".{}") }, .{ "locals", genConst(".{}") },
    .{ "eval", genConst("@as(?*anyopaque, null)") }, .{ "exec", genConst("{}") }, .{ "compile", genConst("@as(?*anyopaque, null)") },
    .{ "input", genConst("\"\"") }, .{ "format", genConst("\"\"") },
    .{ "iter", genPassFirst("@as(?*anyopaque, null)") }, .{ "next", genConst("@as(?*anyopaque, null)") },
    .{ "slice", genConst(".{ .start = @as(?i64, null), .stop = @as(?i64, null), .step = @as(?i64, null) }") },
    .{ "staticmethod", genPassFirst("@as(?*anyopaque, null)") }, .{ "classmethod", genPassFirst("@as(?*anyopaque, null)") },
    .{ "property", genConst(".{ .fget = @as(?*anyopaque, null), .fset = @as(?*anyopaque, null), .fdel = @as(?*anyopaque, null), .doc = @as(?[]const u8, null) }") },
    .{ "super", genSuper }, .{ "object", genConst(".{}") }, .{ "breakpoint", genConst("{}") }, .{ "__import__", genConst("@as(?*anyopaque, null)") },
    // Exception types
    .{ "Exception", genError("Exception") }, .{ "BaseException", genError("BaseException") },
    .{ "TypeError", genError("TypeError") }, .{ "ValueError", genError("ValueError") },
    .{ "KeyError", genError("KeyError") }, .{ "IndexError", genError("IndexError") },
    .{ "AttributeError", genError("AttributeError") }, .{ "NameError", genError("NameError") },
    .{ "RuntimeError", genError("RuntimeError") }, .{ "StopIteration", genError("StopIteration") },
    .{ "GeneratorExit", genError("GeneratorExit") }, .{ "ArithmeticError", genError("ArithmeticError") },
    .{ "ZeroDivisionError", genError("ZeroDivisionError") }, .{ "OverflowError", genError("OverflowError") },
    .{ "FloatingPointError", genError("FloatingPointError") }, .{ "LookupError", genError("LookupError") },
    .{ "AssertionError", genError("AssertionError") }, .{ "ImportError", genError("ImportError") },
    .{ "ModuleNotFoundError", genError("ModuleNotFoundError") }, .{ "OSError", genError("OSError") },
    .{ "FileNotFoundError", genError("FileNotFoundError") }, .{ "FileExistsError", genError("FileExistsError") },
    .{ "PermissionError", genError("PermissionError") }, .{ "IsADirectoryError", genError("IsADirectoryError") },
    .{ "NotADirectoryError", genError("NotADirectoryError") }, .{ "TimeoutError", genError("TimeoutError") },
    .{ "ConnectionError", genError("ConnectionError") }, .{ "BrokenPipeError", genError("BrokenPipeError") },
    .{ "ConnectionAbortedError", genError("ConnectionAbortedError") }, .{ "ConnectionRefusedError", genError("ConnectionRefusedError") },
    .{ "ConnectionResetError", genError("ConnectionResetError") }, .{ "EOFError", genError("EOFError") },
    .{ "MemoryError", genError("MemoryError") }, .{ "RecursionError", genError("RecursionError") },
    .{ "SystemError", genError("SystemError") }, .{ "SystemExit", genError("SystemExit") },
    .{ "KeyboardInterrupt", genError("KeyboardInterrupt") }, .{ "NotImplementedError", genError("NotImplementedError") },
    .{ "IndentationError", genError("IndentationError") }, .{ "TabError", genError("TabError") },
    .{ "SyntaxError", genError("SyntaxError") }, .{ "UnicodeError", genError("UnicodeError") },
    .{ "UnicodeDecodeError", genError("UnicodeDecodeError") }, .{ "UnicodeEncodeError", genError("UnicodeEncodeError") },
    .{ "UnicodeTranslateError", genError("UnicodeTranslateError") }, .{ "BufferError", genError("BufferError") },
    // Warnings
    .{ "Warning", genError("Warning") }, .{ "UserWarning", genError("UserWarning") },
    .{ "DeprecationWarning", genError("DeprecationWarning") }, .{ "PendingDeprecationWarning", genError("PendingDeprecationWarning") },
    .{ "SyntaxWarning", genError("SyntaxWarning") }, .{ "RuntimeWarning", genError("RuntimeWarning") },
    .{ "FutureWarning", genError("FutureWarning") }, .{ "ImportWarning", genError("ImportWarning") },
    .{ "UnicodeWarning", genError("UnicodeWarning") }, .{ "BytesWarning", genError("BytesWarning") },
    .{ "ResourceWarning", genError("ResourceWarning") },
    // Constants
    .{ "True", genConst("true") }, .{ "False", genConst("false") }, .{ "None", genConst("null") },
    .{ "Ellipsis", genConst(".{}") }, .{ "NotImplemented", genConst(".{}") },
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

pub const genSlice = genConst(".{ .start = @as(?i64, null), .stop = @as(?i64, null), .step = @as(?i64, null) }");

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
