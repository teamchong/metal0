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

/// Generate builtins.range
pub fn genRange(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]i64{}");
}

/// Generate builtins.enumerate
pub fn genEnumerate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]struct { @\"0\": i64, @\"1\": i64 }{}");
}

/// Generate builtins.zip
pub fn genZip(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]struct { @\"0\": i64, @\"1\": i64 }{}");
}

/// Generate builtins.map
pub fn genMap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]i64{}");
}

/// Generate builtins.filter
pub fn genFilter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_]i64{}");
}

/// Generate builtins.sorted
pub fn genSorted(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("&[_]i64{}");
    }
}

/// Generate builtins.reversed
pub fn genReversed(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.genExpr(args[0]);
    } else {
        try self.emit("&[_]i64{}");
    }
}

/// Generate builtins.sum
pub fn genSum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate builtins.min
pub fn genMin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate builtins.max
pub fn genMax(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
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

/// Generate builtins.all
pub fn genAll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("true");
}

/// Generate builtins.any
pub fn genAny(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("false");
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

/// Generate builtins.chr
pub fn genChr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate builtins.ord
pub fn genOrd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate builtins.hex
pub fn genHex(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"0x0\"");
}

/// Generate builtins.oct
pub fn genOct(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"0o0\"");
}

/// Generate builtins.bin
pub fn genBin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"0b0\"");
}

/// Generate builtins.pow
pub fn genPow(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 1)");
}

/// Generate builtins.round
pub fn genRound(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("@round(");
        try self.genExpr(args[0]);
        try self.emit(")");
    } else {
        try self.emit("@as(f64, 0.0)");
    }
}

/// Generate builtins.divmod
pub fn genDivmod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i64, 0), @as(i64, 0) }");
}

/// Generate builtins.hash
pub fn genHash(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

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
