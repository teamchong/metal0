/// Python functools module - partial, reduce, lru_cache, wraps, cached_property
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;
const container_traits = @import("../../analysis/traits/container_traits.zig");

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
    try self.withInlineBlock("partial", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("\n");
            c.indent();
            try c.emitIndent();
            try c.emit("const _func = ");
            try c.genExpr(a[0]);
            try c.emit(";\n");

            if (a.len > 1) {
                try c.emitIndent();
                try c.emit("const _captured = .{ ");
                for (a[1..], 0..) |arg, i| {
                    if (i > 0) {
                        try c.emit(", ");
                    }
                    try c.genExpr(arg);
                }
                try c.emit(" };\n");
                try c.emitIndent();
                // Use runtime.closure_impl.Partial - compiled once, not per call site
                // This eliminates O(n²) compilation from inline struct definitions
                try c.emit("const PartialType = runtime.closure_impl.Partial(@TypeOf(_func), @TypeOf(_captured));\n");
                try c.emitIndent();
                try c.emitFmt("break :{s} PartialType{{ .func = _func, .captured = _captured }}\n", .{label});
            } else {
                try c.emitIndent();
                try c.emitFmt("break :{s} _func\n", .{label});
            }
            c.dedent();
            try c.emitIndent();
        }
    }.emit);
}

/// Generate code for functools.cached_property decorator
/// A property that caches its computed value
pub fn genCachedProperty(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return error.UnsupportedSyntax;
    // Just return the function - caching would require runtime state per instance
    try self.genExpr(args[0]);
}

pub fn genReduce(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        try self.emit("@compileError(\"functools.reduce requires at least 2 arguments\")");
        return;
    }
    const iter_type = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const needs_items = container_traits.isList(iter_type) or iter_type == .deque;
    try self.withInlineBlock("reduce", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            // Re-infer to get type (captured in closure isn't possible)
            const it = c.type_inferrer.inferExpr(a[1]) catch .unknown;
            const need_items = container_traits.isList(it) or it == .deque;
            try c.emit("const _func = ");
            try c.genExpr(a[0]);
            try c.emit("; const _iterable = ");
            try c.genExpr(a[1]);
            if (need_items) try c.emit(".items");
            try c.emit("; ");
            if (a.len > 2) {
                try c.emit("var _acc: @TypeOf(_iterable[0]) = ");
                try c.genExpr(a[2]);
                try c.emit("; for (_iterable) |item| { _acc = _func(_acc, item); }");
            } else {
                try c.emit("var _first = true; var _acc: @TypeOf(_iterable[0]) = undefined; for (_iterable) |item| { if (_first) { _acc = item; _first = false; } else { _acc = _func(_acc, item); } }");
            }
            try c.emitFmt(" break :{s} _acc", .{label});
        }
    }.emit);
    _ = needs_items;
}
