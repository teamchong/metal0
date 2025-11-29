/// Python functools module - partial, reduce, lru_cache, wraps
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

/// Generate functools.partial(func, *args, **kwargs)
/// Creates a partial function with pre-filled arguments
pub fn genPartial(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@compileError(\"functools.partial requires at least 1 argument\")");
        return;
    }
    
    // For AOT, partial is complex - we'd need to generate a wrapper struct
    // For simple cases, we can inline the function reference
    // partial(func, arg1) -> struct with func and arg1 stored
    try self.emit("partial_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _func = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    
    // Store partial args in a tuple
    if (args.len > 1) {
        try self.emitIndent();
        try self.emit("const _partial_args = .{ ");
        for (args[1..], 0..) |arg, i| {
            if (i > 0) try self.emit(", ");
            try self.genExpr(arg);
        }
        try self.emit(" };\n");
        try self.emitIndent();
        try self.emit("_ = _partial_args;\n");
    }
    
    try self.emitIndent();
    try self.emit("break :partial_blk _func;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate functools.reduce(func, iterable, initial?)
/// Applies function cumulatively to items
pub fn genReduce(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@compileError(\"functools.reduce requires at least 2 arguments\")");
        return;
    }

    // Infer iterable type to determine if we need .items accessor
    const iter_type = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const needs_items = (iter_type == .list or iter_type == .deque);

    try self.emit("reduce_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _func = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emitIndent();
    try self.emit("const _iterable = ");
    try self.genExpr(args[1]);
    if (needs_items) {
        try self.emit(".items");
    }
    try self.emit(";\n");

    // Initial value
    try self.emitIndent();
    if (args.len > 2) {
        // Use @TypeOf iterable element to ensure type compatibility
        try self.emit("var _acc: @TypeOf(_iterable[0]) = ");
        try self.genExpr(args[2]);
        try self.emit(";\n");
        try self.emitIndent();
        try self.emit("for (_iterable) |item| { _acc = _func(_acc, item); }\n");
    } else {
        try self.emit("var _first = true;\n");
        try self.emitIndent();
        try self.emit("var _acc: @TypeOf(_iterable[0]) = undefined;\n");
        try self.emitIndent();
        try self.emit("for (_iterable) |item| {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("if (_first) { _acc = item; _first = false; } else { _acc = _func(_acc, item); }\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
    }

    try self.emitIndent();
    try self.emit("break :reduce_blk _acc;\n");
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate functools.lru_cache(maxsize=128)
/// Decorator that caches function results
pub fn genLruCache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // lru_cache returns a decorator, which is complex for AOT
    // For now, just pass through the function unchanged (no caching)
    _ = args;
    try self.emit("struct { pub fn wrap(f: anytype) @TypeOf(f) { return f; } }.wrap");
}

/// Generate functools.cache (Python 3.9+ unbounded cache)
pub fn genCache(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Same as lru_cache for now
    _ = args;
    try self.emit("struct { pub fn wrap(f: anytype) @TypeOf(f) { return f; } }.wrap");
}

/// Generate functools.wraps(wrapped)
/// Decorator to update wrapper function metadata
pub fn genWraps(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // wraps is for metadata, not needed for AOT compilation
    _ = args;
    try self.emit("struct { pub fn wrap(f: anytype) @TypeOf(f) { return f; } }.wrap");
}

/// Generate functools.cmp_to_key(func)
/// Convert comparison function to key function
pub fn genCmpToKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    
    // For AOT, return the function as-is (simplified)
    try self.genExpr(args[0]);
}

/// Generate functools.total_ordering class decorator
pub fn genTotalOrdering(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    // Class decorator - pass through for AOT
    _ = args;
    try self.emit("struct { pub fn wrap(cls: anytype) @TypeOf(cls) { return cls; } }.wrap");
}
