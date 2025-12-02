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
    // Exception types - use comptime generator
    .{ "Exception", genError("Exception") },
    .{ "BaseException", genError("BaseException") },
    .{ "TypeError", genError("TypeError") },
    .{ "ValueError", genError("ValueError") },
    .{ "KeyError", genError("KeyError") },
    .{ "IndexError", genError("IndexError") },
    .{ "AttributeError", genError("AttributeError") },
    .{ "NameError", genError("NameError") },
    .{ "RuntimeError", genError("RuntimeError") },
    .{ "StopIteration", genError("StopIteration") },
    .{ "GeneratorExit", genError("GeneratorExit") },
    .{ "ArithmeticError", genError("ArithmeticError") },
    .{ "ZeroDivisionError", genError("ZeroDivisionError") },
    .{ "OverflowError", genError("OverflowError") },
    .{ "FloatingPointError", genError("FloatingPointError") },
    .{ "LookupError", genError("LookupError") },
    .{ "AssertionError", genError("AssertionError") },
    .{ "ImportError", genError("ImportError") },
    .{ "ModuleNotFoundError", genError("ModuleNotFoundError") },
    .{ "OSError", genError("OSError") },
    .{ "FileNotFoundError", genError("FileNotFoundError") },
    .{ "FileExistsError", genError("FileExistsError") },
    .{ "PermissionError", genError("PermissionError") },
    .{ "IsADirectoryError", genError("IsADirectoryError") },
    .{ "NotADirectoryError", genError("NotADirectoryError") },
    .{ "TimeoutError", genError("TimeoutError") },
    .{ "ConnectionError", genError("ConnectionError") },
    .{ "BrokenPipeError", genError("BrokenPipeError") },
    .{ "ConnectionAbortedError", genError("ConnectionAbortedError") },
    .{ "ConnectionRefusedError", genError("ConnectionRefusedError") },
    .{ "ConnectionResetError", genError("ConnectionResetError") },
    .{ "EOFError", genError("EOFError") },
    .{ "MemoryError", genError("MemoryError") },
    .{ "RecursionError", genError("RecursionError") },
    .{ "SystemError", genError("SystemError") },
    .{ "SystemExit", genError("SystemExit") },
    .{ "KeyboardInterrupt", genError("KeyboardInterrupt") },
    .{ "NotImplementedError", genError("NotImplementedError") },
    .{ "IndentationError", genError("IndentationError") },
    .{ "TabError", genError("TabError") },
    .{ "SyntaxError", genError("SyntaxError") },
    .{ "UnicodeError", genError("UnicodeError") },
    .{ "UnicodeDecodeError", genError("UnicodeDecodeError") },
    .{ "UnicodeEncodeError", genError("UnicodeEncodeError") },
    .{ "UnicodeTranslateError", genError("UnicodeTranslateError") },
    .{ "BufferError", genError("BufferError") },
    // Warning types
    .{ "Warning", genError("Warning") },
    .{ "UserWarning", genError("UserWarning") },
    .{ "DeprecationWarning", genError("DeprecationWarning") },
    .{ "PendingDeprecationWarning", genError("PendingDeprecationWarning") },
    .{ "SyntaxWarning", genError("SyntaxWarning") },
    .{ "RuntimeWarning", genError("RuntimeWarning") },
    .{ "FutureWarning", genError("FutureWarning") },
    .{ "ImportWarning", genError("ImportWarning") },
    .{ "UnicodeWarning", genError("UnicodeWarning") },
    .{ "BytesWarning", genError("BytesWarning") },
    .{ "ResourceWarning", genError("ResourceWarning") },
    // Constants
    .{ "True", genConst("true") },
    .{ "False", genConst("false") },
    .{ "None", genConst("null") },
    .{ "Ellipsis", genConst(".{}") },
    .{ "NotImplemented", genConst(".{}") },
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

// Comptime generators for error types and constants
fn genError(comptime name: []const u8) ModuleHandler {
    return struct {
        fn handler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            _ = args;
            try self.emit("error." ++ name);
        }
    }.handler;
}

fn genConst(comptime value: []const u8) ModuleHandler {
    return struct {
        fn handler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            _ = args;
            try self.emit(value);
        }
    }.handler;
}
