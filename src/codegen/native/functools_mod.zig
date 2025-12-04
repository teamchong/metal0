/// Python functools module - partial, reduce, lru_cache, wraps, cached_property
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

// Identity decorator helper - returns a function that returns its argument unchanged
const IdentityDecorator = "struct { pub fn identity(f: anytype) @TypeOf(f) { return f; } }.identity";

// lru_cache/cache: For AOT compilation, we pass through the function since true
// memoization requires runtime state. The decorated function works correctly,
// just without caching. This matches Python semantics where @lru_cache(func) == func
// in terms of behavior (just slower without caching).
pub const genLruCache = h.c(IdentityDecorator);
pub const genCache = genLruCache;

// wraps: Decorator to copy metadata - for AOT just return the function
pub const genWraps = h.c(IdentityDecorator);

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "partial", genPartial },
    .{ "reduce", genReduce },
    .{ "lru_cache", genLruCache },
    .{ "cache", genLruCache },
    .{ "wraps", genWraps },
    .{ "total_ordering", genWraps },
    .{ "cmp_to_key", h.pass("null") },
    .{ "cached_property", genCachedProperty },
    .{ "singledispatch", genWraps },
    .{ "update_wrapper", genWraps },
});

/// Generate code for functools.partial(func, *args)
/// Creates a partial function application - returns a callable struct
pub fn genPartial(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("@compileError(\"functools.partial requires at least 1 argument\")");
        return;
    }
    // Emit a struct that wraps the function and its captured arguments
    // When called, it calls func with captured args first, then new args
    try self.emit("partial_blk: {\n");
    self.indent();
    try self.emitIndent();
    try self.emit("const _func = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");

    if (args.len > 1) {
        try self.emitIndent();
        try self.emit("const _captured = .{ ");
        for (args[1..], 0..) |arg, i| {
            if (i > 0) try self.emit(", ");
            try self.genExpr(arg);
        }
        try self.emit(" };\n");
        try self.emitIndent();
        // Return a struct that can be called with additional args
        try self.emit("const Partial = struct {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("captured: @TypeOf(_captured),\n");
        try self.emitIndent();
        try self.emit("func: @TypeOf(_func),\n");
        try self.emitIndent();
        try self.emit("pub fn call(self: @This(), extra_args: anytype) @TypeOf(_func(_captured ++ extra_args)) {\n");
        self.indent();
        try self.emitIndent();
        try self.emit("return @call(.auto, self.func, self.captured ++ extra_args);\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("}\n");
        self.dedent();
        try self.emitIndent();
        try self.emit("};\n");
        try self.emitIndent();
        try self.emit("break :partial_blk Partial{ .captured = _captured, .func = _func };\n");
    } else {
        try self.emitIndent();
        try self.emit("break :partial_blk _func;\n");
    }
    self.dedent();
    try self.emitIndent();
    try self.emit("}");
}

/// Generate code for functools.cached_property decorator
/// A property that caches its computed value
pub fn genCachedProperty(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    // Just return the function - caching would require runtime state per instance
    try self.genExpr(args[0]);
}

pub fn genReduce(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@compileError(\"functools.reduce requires at least 2 arguments\")"); return; }
    const iter_type = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    try self.emit("reduce_blk: { const _func = "); try self.genExpr(args[0]);
    try self.emit("; const _iterable = "); try self.genExpr(args[1]);
    if (iter_type == .list or iter_type == .deque) try self.emit(".items");
    try self.emit("; ");
    if (args.len > 2) {
        try self.emit("var _acc: @TypeOf(_iterable[0]) = "); try self.genExpr(args[2]);
        try self.emit("; for (_iterable) |item| { _acc = _func(_acc, item); }");
    } else try self.emit("var _first = true; var _acc: @TypeOf(_iterable[0]) = undefined; for (_iterable) |item| { if (_first) { _acc = item; _first = false; } else { _acc = _func(_acc, item); } }");
    try self.emit(" break :reduce_blk _acc; }");
}
