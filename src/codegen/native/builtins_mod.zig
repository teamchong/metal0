/// Python builtins module - Built-in functions exposed as module
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

// Note: Most builtins are handled directly in expressions/calls.zig
// This module handles builtins.X access patterns

/// Generate builtins.open - same as open()
pub fn genOpen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate builtins.print
pub fn genPrint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate builtins.len
pub fn genLen(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@as(i64, ");
        try self.genExpr(args[0]);
        try self.emit(".len)");
    } else {
        try self.emit("@as(i64, 0)");
    }
}

/// Generate builtins.range - forward to real implementation
pub fn genRange(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const collections = @import("builtins/collections.zig");
    try collections.genRange(self, args);
}

/// Generate builtins.enumerate - forward to real implementation
pub fn genEnumerate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const collections = @import("builtins/collections.zig");
    try collections.genEnumerate(self, args);
}

/// Generate builtins.zip - forward to real implementation
pub fn genZip(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const collections = @import("builtins/collections.zig");
    try collections.genZip(self, args);
}

/// Generate builtins.map - forward to real implementation
pub fn genMap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const collections = @import("builtins/collections.zig");
    try collections.genMap(self, args);
}

/// Generate builtins.filter - forward to real implementation
pub fn genFilter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const collections = @import("builtins/collections.zig");
    try collections.genFilter(self, args);
}

/// Generate builtins.sorted - forward to real implementation
pub fn genSorted(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const collections = @import("builtins/collections.zig");
    try collections.genSorted(self, args);
}

/// Generate builtins.reversed - forward to real implementation
pub fn genReversed(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const collections = @import("builtins/collections.zig");
    try collections.genReversed(self, args);
}

/// Generate builtins.sum - forward to real implementation
pub fn genSum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const collections = @import("builtins/collections.zig");
    try collections.genSum(self, args);
}

/// Generate builtins.min - forward to real implementation
pub fn genMin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const builtins = @import("builtins.zig");
    try builtins.genMin(self, args);
}

/// Generate builtins.max - forward to real implementation
pub fn genMax(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const builtins = @import("builtins.zig");
    try builtins.genMax(self, args);
}

/// Generate builtins.abs
pub fn genAbs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@abs(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("@as(i64, 0)");
    }
}

/// Generate builtins.all - forward to real implementation
pub fn genAll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const collections = @import("builtins/collections.zig");
    try collections.genAll(self, args);
}

/// Generate builtins.any - forward to real implementation
pub fn genAny(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const collections = @import("builtins/collections.zig");
    try collections.genAny(self, args);
}

/// Generate builtins.isinstance
pub fn genIsinstance(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // isinstance returns true unconditionally in metal0's stub implementation
    // We only need to consume args that have side effects (like calls)
    // Simple names don't need discarding - that causes "pointless discard" errors
    if (args.len >= 2) {
        const has_side_effects = args[0] == .call or args[1] == .call;
        if (has_side_effects) {
            try self.emit("blk: { ");
            if (args[0] == .call) {
                try self.emit("_ = ");
                try self.genExpr(args[0]);
                try self.emit("; ");
            }
            if (args[1] == .call) {
                try self.emit("_ = ");
                try self.genExpr(args[1]);
                try self.emit("; ");
            }
            try self.emit("break :blk true; }");
        } else {
            try self.emit("true");
        }
    } else if (args.len >= 1 and args[0] == .call) {
        try self.emit("blk: { _ = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk true; }");
    } else {
        try self.emit("true");
    }
}

/// Generate builtins.issubclass
pub fn genIssubclass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Only consume args with side effects (like calls)
    if (args.len >= 1 and args[0] == .call) {
        try self.emit("blk: { _ = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk true; }");
    } else {
        try self.emit("true");
    }
}

/// Generate builtins.hasattr
pub fn genHasattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Only consume args with side effects (like calls)
    if (args.len >= 1 and args[0] == .call) {
        try self.emit("blk: { _ = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk true; }");
    } else {
        try self.emit("true");
    }
}

/// Generate builtins.getattr
pub fn genGetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Only consume args with side effects (like calls)
    if (args.len >= 1 and args[0] == .call) {
        try self.emit("blk: { _ = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk @as(?*anyopaque, null); }");
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

/// Generate builtins.setattr
pub fn genSetattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Only consume args with side effects (like calls)
    if (args.len >= 1 and args[0] == .call) {
        try self.emit("blk: { _ = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk {}; }");
    } else {
        try self.emit("{}");
    }
}

/// Generate builtins.delattr
pub fn genDelattr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Only consume args with side effects (like calls)
    if (args.len >= 1 and args[0] == .call) {
        try self.emit("blk: { _ = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk {}; }");
    } else {
        try self.emit("{}");
    }
}

/// Generate builtins.callable
pub fn genCallable(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Only consume args with side effects (like calls)
    if (args.len >= 1 and args[0] == .call) {
        try self.emit("blk: { _ = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk true; }");
    } else {
        try self.emit("true");
    }
}

/// Generate builtins.repr
pub fn genRepr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate builtins.ascii
pub fn genAscii(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate builtins.chr - forward to real implementation
pub fn genChr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const builtins = @import("builtins.zig");
    try builtins.genChr(self, args);
}

/// Generate builtins.ord - forward to real implementation
pub fn genOrd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const builtins = @import("builtins.zig");
    try builtins.genOrd(self, args);
}

/// Generate builtins.hex - hex(n) returns hex string
pub fn genHex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("(try std.fmt.allocPrint(__global_allocator, \"0x{x}\", .{");
        try self.genExpr(args[0]);
        try self.emit("}))");
    } else {
        try self.emit("\"0x0\"");
    }
}

/// Generate builtins.oct - oct(n) returns octal string
pub fn genOct(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("(try std.fmt.allocPrint(__global_allocator, \"0o{o}\", .{");
        try self.genExpr(args[0]);
        try self.emit("}))");
    } else {
        try self.emit("\"0o0\"");
    }
}

/// Generate builtins.bin - bin(n) returns binary string
pub fn genBin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("(try std.fmt.allocPrint(__global_allocator, \"0b{b}\", .{");
        try self.genExpr(args[0]);
        try self.emit("}))");
    } else {
        try self.emit("\"0b0\"");
    }
}

/// Generate builtins.pow - forward to real implementation
pub fn genPow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const builtins = @import("builtins.zig");
    try builtins.genPow(self, args);
}

/// Generate builtins.round - forward to real implementation
pub fn genRound(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const builtins = @import("builtins.zig");
    try builtins.genRound(self, args);
}

/// Generate builtins.divmod - forward to real implementation
pub fn genDivmod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const builtins = @import("builtins.zig");
    try builtins.genDivmod(self, args);
}

/// Generate builtins.hash - forward to real implementation
pub fn genHash(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    const builtins = @import("builtins.zig");
    try builtins.genHash(self, args);
}

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "open", genOpen },
    .{ "print", genPrint },
    .{ "len", genLen },
    .{ "range", genRange },
    .{ "enumerate", genEnumerate },
    .{ "zip", genZip },
    .{ "map", genMap },
    .{ "filter", genFilter },
    .{ "sorted", genSorted },
    .{ "reversed", genReversed },
    .{ "sum", genSum },
    .{ "min", genMin },
    .{ "max", genMax },
    .{ "abs", genAbs },
    .{ "all", genAll },
    .{ "any", genAny },
    .{ "isinstance", genIsinstance },
    .{ "issubclass", genIssubclass },
    .{ "hasattr", genHasattr },
    .{ "getattr", genGetattr },
    .{ "setattr", genSetattr },
    .{ "delattr", genDelattr },
    .{ "callable", genCallable },
    .{ "repr", genRepr },
    .{ "ascii", genAscii },
    .{ "chr", genChr },
    .{ "ord", genOrd },
    .{ "hex", genHex },
    .{ "oct", genOct },
    .{ "bin", genBin },
    .{ "pow", genPow },
    .{ "round", genRound },
    .{ "divmod", genDivmod },
    .{ "hash", genHash },
    .{ "id", genId },
    .{ "type", genType },
    .{ "dir", genDir },
    .{ "vars", genVars },
    .{ "globals", genGlobals },
    .{ "locals", genLocals },
    .{ "eval", genEval },
    .{ "exec", genExec },
    .{ "compile", genCompile },
    .{ "input", genInput },
    .{ "format", genFormat },
    .{ "iter", genIter },
    .{ "next", genNext },
    .{ "slice", genSlice },
    .{ "staticmethod", genStaticmethod },
    .{ "classmethod", genClassmethod },
    .{ "property", genProperty },
    .{ "super", genSuper },
    .{ "object", genObject },
    .{ "breakpoint", genBreakpoint },
    .{ "__import__", genImport },
    .{ "Exception", genException },
    .{ "BaseException", genBaseException },
    .{ "TypeError", genTypeError },
    .{ "ValueError", genValueError },
    .{ "KeyError", genKeyError },
    .{ "IndexError", genIndexError },
    .{ "AttributeError", genAttributeError },
    .{ "NameError", genNameError },
    .{ "RuntimeError", genRuntimeError },
    .{ "StopIteration", genStopIteration },
    .{ "GeneratorExit", genGeneratorExit },
    .{ "ArithmeticError", genArithmeticError },
    .{ "ZeroDivisionError", genZeroDivisionError },
    .{ "OverflowError", genOverflowError },
    .{ "FloatingPointError", genFloatingPointError },
    .{ "LookupError", genLookupError },
    .{ "AssertionError", genAssertionError },
    .{ "ImportError", genImportError },
    .{ "ModuleNotFoundError", genModuleNotFoundError },
    .{ "OSError", genOSError },
    .{ "FileNotFoundError", genFileNotFoundError },
    .{ "FileExistsError", genFileExistsError },
    .{ "PermissionError", genPermissionError },
    .{ "IsADirectoryError", genIsADirectoryError },
    .{ "NotADirectoryError", genNotADirectoryError },
    .{ "TimeoutError", genTimeoutError },
    .{ "ConnectionError", genConnectionError },
    .{ "BrokenPipeError", genBrokenPipeError },
    .{ "ConnectionAbortedError", genConnectionAbortedError },
    .{ "ConnectionRefusedError", genConnectionRefusedError },
    .{ "ConnectionResetError", genConnectionResetError },
    .{ "EOFError", genEOFError },
    .{ "MemoryError", genMemoryError },
    .{ "RecursionError", genRecursionError },
    .{ "SystemError", genSystemError },
    .{ "SystemExit", genSystemExit },
    .{ "KeyboardInterrupt", genKeyboardInterrupt },
    .{ "NotImplementedError", genNotImplementedError },
    .{ "IndentationError", genIndentationError },
    .{ "TabError", genTabError },
    .{ "SyntaxError", genSyntaxError },
    .{ "UnicodeError", genUnicodeError },
    .{ "UnicodeDecodeError", genUnicodeDecodeError },
    .{ "UnicodeEncodeError", genUnicodeEncodeError },
    .{ "UnicodeTranslateError", genUnicodeTranslateError },
    .{ "BufferError", genBufferError },
    .{ "Warning", genWarning },
    .{ "UserWarning", genUserWarning },
    .{ "DeprecationWarning", genDeprecationWarning },
    .{ "PendingDeprecationWarning", genPendingDeprecationWarning },
    .{ "SyntaxWarning", genSyntaxWarning },
    .{ "RuntimeWarning", genRuntimeWarning },
    .{ "FutureWarning", genFutureWarning },
    .{ "ImportWarning", genImportWarning },
    .{ "UnicodeWarning", genUnicodeWarning },
    .{ "BytesWarning", genBytesWarning },
    .{ "ResourceWarning", genResourceWarning },
    .{ "True", genTrue },
    .{ "False", genFalse },
    .{ "None", genNone },
    .{ "Ellipsis", genEllipsis },
    .{ "NotImplemented", genNotImplemented },
});

/// Generate builtins.id
pub fn genId(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate builtins.type
pub fn genType(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Return a type descriptor for runtime type introspection
    try self.emit("type");
}

/// Generate builtins.dir
pub fn genDir(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{}");
}

/// Generate builtins.vars
pub fn genVars(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate builtins.globals
pub fn genGlobals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate builtins.locals
pub fn genLocals(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate builtins.eval - AOT limited
pub fn genEval(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate builtins.exec - AOT limited
pub fn genExec(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate builtins.compile - AOT limited
pub fn genCompile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate builtins.input
pub fn genInput(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate builtins.format
pub fn genFormat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate builtins.iter
pub fn genIter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

/// Generate builtins.next
pub fn genNext(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

/// Generate builtins.slice
pub fn genSlice(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .start = @as(?i64, null), .stop = @as(?i64, null), .step = @as(?i64, null) }");
}

/// Generate builtins.staticmethod
pub fn genStaticmethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

/// Generate builtins.classmethod
pub fn genClassmethod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("@as(?*anyopaque, null)");
    }
}

/// Generate builtins.property
pub fn genProperty(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .fget = @as(?*anyopaque, null), .fset = @as(?*anyopaque, null), .fdel = @as(?*anyopaque, null), .doc = @as(?[]const u8, null) }");
}

/// Generate builtins.super
/// When called as super() inside a class method, returns a proxy for the parent class
/// super() -> parent class reference that can call parent methods
pub fn genSuper(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    // Get current class and its parent
    if (self.current_class_name) |current_class| {
        if (self.getParentClassName(current_class)) |parent_class| {
            // Generate a struct that wraps the parent class reference
            // This allows super().method() to work
            try self.emit("@as(*const ");
            try self.emit(parent_class);
            try self.emit(", @ptrCast(__self))");
            return;
        }
    }
    // Fallback if not inside a class or no parent
    // Returns an empty struct for method dispatch
    // Note: We don't emit "_ = self" anymore - that causes "pointless discard" errors
    // when self IS actually used in the method body.
    // Note: We use a unique label to avoid conflicts with other blk labels
    const super_label_id = self.block_label_counter;
    self.block_label_counter += 1;
    try self.output.writer(self.allocator).print("super_{d}: {{ break :super_{d} .{{}}; }}", .{ super_label_id, super_label_id });
}

/// Generate builtins.object
pub fn genObject(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}");
}

/// Generate builtins.breakpoint
pub fn genBreakpoint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate builtins.__import__
pub fn genImport(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(?*anyopaque, null)");
}

// ============================================================================
// Exception types accessible via builtins
// ============================================================================

pub fn genException(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.Exception");
}

pub fn genBaseException(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.BaseException");
}

pub fn genTypeError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.TypeError");
}

pub fn genValueError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ValueError");
}

pub fn genKeyError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.KeyError");
}

pub fn genIndexError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.IndexError");
}

pub fn genAttributeError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.AttributeError");
}

pub fn genNameError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NameError");
}

pub fn genRuntimeError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.RuntimeError");
}

pub fn genStopIteration(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.StopIteration");
}

pub fn genGeneratorExit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.GeneratorExit");
}

pub fn genArithmeticError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ArithmeticError");
}

pub fn genZeroDivisionError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ZeroDivisionError");
}

pub fn genOverflowError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.OverflowError");
}

pub fn genFloatingPointError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.FloatingPointError");
}

pub fn genLookupError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.LookupError");
}

pub fn genAssertionError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.AssertionError");
}

pub fn genImportError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ImportError");
}

pub fn genModuleNotFoundError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ModuleNotFoundError");
}

pub fn genOSError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.OSError");
}

pub fn genFileNotFoundError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.FileNotFoundError");
}

pub fn genFileExistsError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.FileExistsError");
}

pub fn genPermissionError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.PermissionError");
}

pub fn genIsADirectoryError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.IsADirectoryError");
}

pub fn genNotADirectoryError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NotADirectoryError");
}

pub fn genTimeoutError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.TimeoutError");
}

pub fn genConnectionError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ConnectionError");
}

pub fn genBrokenPipeError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.BrokenPipeError");
}

pub fn genConnectionAbortedError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ConnectionAbortedError");
}

pub fn genConnectionRefusedError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ConnectionRefusedError");
}

pub fn genConnectionResetError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ConnectionResetError");
}

pub fn genEOFError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.EOFError");
}

pub fn genMemoryError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.MemoryError");
}

pub fn genRecursionError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.RecursionError");
}

pub fn genSystemError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SystemError");
}

pub fn genSystemExit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SystemExit");
}

pub fn genKeyboardInterrupt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.KeyboardInterrupt");
}

pub fn genNotImplementedError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.NotImplementedError");
}

pub fn genIndentationError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.IndentationError");
}

pub fn genTabError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.TabError");
}

pub fn genSyntaxError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SyntaxError");
}

pub fn genUnicodeError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.UnicodeError");
}

pub fn genUnicodeDecodeError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.UnicodeDecodeError");
}

pub fn genUnicodeEncodeError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.UnicodeEncodeError");
}

pub fn genUnicodeTranslateError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.UnicodeTranslateError");
}

pub fn genBufferError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.BufferError");
}

// ============================================================================
// Warning types
// ============================================================================

pub fn genWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.Warning");
}

pub fn genUserWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.UserWarning");
}

pub fn genDeprecationWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.DeprecationWarning");
}

pub fn genPendingDeprecationWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.PendingDeprecationWarning");
}

pub fn genSyntaxWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.SyntaxWarning");
}

pub fn genRuntimeWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.RuntimeWarning");
}

pub fn genFutureWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.FutureWarning");
}

pub fn genImportWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ImportWarning");
}

pub fn genUnicodeWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.UnicodeWarning");
}

pub fn genBytesWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.BytesWarning");
}

pub fn genResourceWarning(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.ResourceWarning");
}

// ============================================================================
// Constants
// ============================================================================

pub fn genTrue(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

pub fn genFalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
}

pub fn genNone(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("null");
}

pub fn genEllipsis(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}"); // Ellipsis singleton
}

pub fn genNotImplemented(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{}"); // NotImplemented singleton
}
