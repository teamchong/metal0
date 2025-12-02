/// Python functools module - partial, reduce, lru_cache, wraps
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const genLruCache = h.c("struct { pub fn wrap(f: anytype) @TypeOf(f) { return f; } }.wrap");
pub const genCache = genLruCache;
pub const genWraps = genLruCache;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "partial", genPartial }, .{ "reduce", genReduce },
    .{ "lru_cache", genLruCache }, .{ "cache", genLruCache },
    .{ "wraps", genLruCache }, .{ "total_ordering", genLruCache },
    .{ "cmp_to_key", genCmpToKey },
});

pub fn genPartial(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("@compileError(\"functools.partial requires at least 1 argument\")"); return; }
    try self.emit("partial_blk: { const _func = "); try self.genExpr(args[0]);
    if (args.len > 1) {
        try self.emit("; const _partial_args = .{ ");
        for (args[1..], 0..) |arg, i| { if (i > 0) try self.emit(", "); try self.genExpr(arg); }
        try self.emit(" }; _ = _partial_args");
    }
    try self.emit("; break :partial_blk _func; }");
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

fn genCmpToKey(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]);
}
