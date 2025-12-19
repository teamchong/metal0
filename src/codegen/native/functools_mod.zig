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
        const b = try self.getBuilder();
        try b.write("@compileError(\"functools.partial requires at least 1 argument\")");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    // Emit a struct that wraps the function and its captured arguments
    // When called, it calls func with captured args first, then new args
    try self.withInlineBlock("partial", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("\n");
            c.indent();
            try c.emitIndent();
            try b.write("const _func = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write(";\n");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }

            if (a.len > 1) {
                try c.emitIndent();
                {
                    const b3 = try c.getBuilder();
                    try b3.write("const _captured = .{ ");
                    const output3 = b3.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output3);
                }
                for (a[1..], 0..) |arg, i| {
                    if (i > 0) {
                        const b4 = try c.getBuilder();
                        try b4.write(", ");
                        const out4 = b4.getBodyAndClear();
                        try c.output.appendSlice(c.allocator, out4);
                    }
                    try c.genExpr(arg);
                }
                {
                    const b5 = try c.getBuilder();
                    try b5.write(" };\n");
                    const output5 = b5.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output5);
                }
                try c.emitIndent();
                // Use runtime.closure_impl.Partial - compiled once, not per call site
                // This eliminates O(n²) compilation from inline struct definitions
                {
                    const b6 = try c.getBuilder();
                    try b6.write("const PartialType = runtime.closure_impl.Partial(@TypeOf(_func), @TypeOf(_captured));\n");
                    const output6 = b6.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output6);
                }
                try c.emitIndent();
                {
                    const b7 = try c.getBuilder();
                    try b7.writeFmt("break :{s} PartialType{{ .func = _func, .captured = _captured }}\n", .{label});
                    const output7 = b7.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output7);
                }
            } else {
                try c.emitIndent();
                {
                    const b8 = try c.getBuilder();
                    try b8.writeFmt("break :{s} _func\n", .{label});
                    const output8 = b8.getBodyAndClear();
                    try c.output.appendSlice(c.allocator, output8);
                }
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
        const b = try self.getBuilder();
        try b.write("@compileError(\"functools.reduce requires at least 2 arguments\")");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    const iter_type = self.type_inferrer.inferExpr(args[1]) catch .unknown;
    const needs_items = container_traits.isList(iter_type) or iter_type == .deque;
    try self.withInlineBlock("reduce", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            // Re-infer to get type (captured in closure isn't possible)
            const it = c.type_inferrer.inferExpr(a[1]) catch .unknown;
            const need_items = container_traits.isList(it) or it == .deque;
            const b = try c.getBuilder();
            try b.write("const _func = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const _iterable = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                if (need_items) try b3.write(".items");
                try b3.write("; ");
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
            if (a.len > 2) {
                const b4 = try c.getBuilder();
                try b4.write("var _acc: @TypeOf(_iterable[0]) = ");
                const output4 = b4.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output4);
                try c.genExpr(a[2]);
                const b5 = try c.getBuilder();
                try b5.write("; for (_iterable) |item| { _acc = _func(_acc, item); }");
                const output5 = b5.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output5);
            } else {
                const b4 = try c.getBuilder();
                try b4.write("var _first = true; var _acc: @TypeOf(_iterable[0]) = undefined; for (_iterable) |item| { if (_first) { _acc = item; _first = false; } else { _acc = _func(_acc, item); } }");
                const output4 = b4.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output4);
            }
            {
                const b6 = try c.getBuilder();
                try b6.writeFmt(" break :{s} _acc", .{label});
                const output6 = b6.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output6);
            }
        }
    }.emit);
    _ = needs_items;
}
