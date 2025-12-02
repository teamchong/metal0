/// Python itertools module - chain, cycle, repeat, count, zip_longest, etc.
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

fn needsItems(self: *NativeCodegen, arg: ast.Node) bool {
    const t = self.type_inferrer.inferExpr(arg) catch return false;
    return t == .list or t == .deque;
}

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "chain", genChain }, .{ "repeat", genRepeat }, .{ "count", genCount },
    .{ "cycle", genPassthrough }, .{ "islice", genIslice }, .{ "enumerate", genPassthrough },
    .{ "zip_longest", genZipLongest }, .{ "product", genPassthrough }, .{ "permutations", genPassthrough },
    .{ "combinations", genPassthrough }, .{ "groupby", genPassthrough },
    .{ "takewhile", genTakewhile }, .{ "dropwhile", genDropwhile }, .{ "filterfalse", genFilterfalse },
    .{ "accumulate", genAccumulate }, .{ "starmap", genStarmap }, .{ "compress", genCompress },
    .{ "tee", genTee }, .{ "pairwise", genPairwise },
    .{ "batched", h.c(".{ std.ArrayList(i64){} }") },
});

fn genPassthrough(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) try self.genExpr(args[0]) else try self.emit("std.ArrayList(i64){}");
}

pub fn genCycle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) try self.emit("std.ArrayList(i64){}") else try self.genExpr(args[0]);
}

fn genTakewhile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("std.ArrayList(i64){}"); return; }
    try self.emit("takewhile_blk: { const _pred = "); try self.genExpr(args[0]);
    try self.emit("; const _iter = "); try self.genExpr(args[1]);
    if (needsItems(self, args[1])) try self.emit(".items");
    try self.emit("; var _result = std.ArrayList(@TypeOf(_iter[0])){}; for (_iter) |item| { if (!_pred(item)) break; _result.append(__global_allocator, item) catch continue; } break :takewhile_blk _result; }");
}

fn genDropwhile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("std.ArrayList(i64){}"); return; }
    try self.emit("dropwhile_blk: { const _pred = "); try self.genExpr(args[0]);
    try self.emit("; const _iter = "); try self.genExpr(args[1]);
    if (needsItems(self, args[1])) try self.emit(".items");
    try self.emit("; var _result = std.ArrayList(@TypeOf(_iter[0])){}; var _dropping = true; for (_iter) |item| { if (_dropping and _pred(item)) continue; _dropping = false; _result.append(__global_allocator, item) catch continue; } break :dropwhile_blk _result; }");
}

fn genFilterfalse(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("std.ArrayList(i64){}"); return; }
    try self.emit("filterfalse_blk: { const _pred = "); try self.genExpr(args[0]);
    try self.emit("; const _iter = "); try self.genExpr(args[1]);
    if (needsItems(self, args[1])) try self.emit(".items");
    try self.emit("; var _result = std.ArrayList(@TypeOf(_iter[0])){}; for (_iter) |item| { if (!_pred(item)) _result.append(__global_allocator, item) catch continue; } break :filterfalse_blk _result; }");
}

pub fn genChain(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("std.ArrayList(i64){}"); return; }
    try self.emit("chain_blk: { var _result = std.ArrayList(i64){}; ");
    for (args) |arg| {
        try self.emit("for ("); try self.genExpr(arg);
        if (needsItems(self, arg)) try self.emit(".items");
        try self.emit(") |item| { _result.append(__global_allocator, item) catch continue; } ");
    }
    try self.emit("break :chain_blk _result; }");
}

pub fn genRepeat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("repeat_blk: { var _result = std.ArrayList(i64){}; ");
    if (args.len > 1) {
        try self.emit("var _i: usize = 0; while (_i < @as(usize, @intCast("); try self.genExpr(args[1]);
        try self.emit("))) : (_i += 1) { _result.append(__global_allocator, "); try self.genExpr(args[0]); try self.emit(") catch continue; }");
    } else { try self.emit("_result.append(__global_allocator, "); try self.genExpr(args[0]); try self.emit(") catch {};"); }
    try self.emit(" break :repeat_blk _result; }");
}

pub fn genCount(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit("count_blk: { const _start = ");
    if (args.len >= 1) try self.genExpr(args[0]) else try self.emit("@as(i64, 0)");
    try self.emit("; const _step = ");
    if (args.len >= 2) try self.genExpr(args[1]) else try self.emit("@as(i64, 1)");
    try self.emit("; break :count_blk .{ .start = _start, .step = _step }; }");
}

pub fn genIslice(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("std.ArrayList(i64){}"); return; }
    try self.emit("islice_blk: { const _iter = "); try self.genExpr(args[0]);
    try self.emit("; const _stop = @as(usize, @intCast("); try self.genExpr(args[1]);
    try self.emit(")); var _result = std.ArrayList(i64){}; for (_iter.items[0..@min(_stop, _iter.items.len)]) |item| { _result.append(__global_allocator, item) catch continue; } break :islice_blk _result; }");
}

pub fn genZipLongest(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("std.ArrayList(struct { @\"0\": i64 }){}"); return; }
    if (args.len >= 2) {
        try self.emit("zip_longest_blk: { const _a = "); try self.genExpr(args[0]);
        try self.emit("; const _b = "); try self.genExpr(args[1]);
        try self.emit("; const _len = @max(_a.items.len, _b.items.len); var _result = std.ArrayList(struct { @\"0\": i64, @\"1\": i64 }){}; for (0.._len) |i| { const _va = if (i < _a.items.len) _a.items[i] else 0; const _vb = if (i < _b.items.len) _b.items[i] else 0; _result.append(__global_allocator, .{ .@\"0\" = _va, .@\"1\" = _vb }) catch continue; } break :zip_longest_blk _result; }");
    } else try self.genExpr(args[0]);
}

fn genAccumulate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayList(i64){}"); return; }
    try self.emit("accumulate_blk: { const _iter = "); try self.genExpr(args[0]);
    if (needsItems(self, args[0])) try self.emit(".items");
    try self.emit("; var _result = std.ArrayList(@TypeOf(_iter[0])){}; var _acc: @TypeOf(_iter[0]) = _iter[0]; _result.append(__global_allocator, _acc) catch {}; for (_iter[1..]) |item| { _acc = ");
    if (args.len > 1) { try self.genExpr(args[1]); try self.emit("(_acc, item)"); } else try self.emit("_acc + item");
    try self.emit("; _result.append(__global_allocator, _acc) catch continue; } break :accumulate_blk _result; }");
}

fn genStarmap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("std.ArrayList(i64){}"); return; }
    try self.emit("starmap_blk: { const _func = "); try self.genExpr(args[0]);
    try self.emit("; const _iter = "); try self.genExpr(args[1]);
    if (needsItems(self, args[1])) try self.emit(".items");
    try self.emit("; var _result = std.ArrayList(@TypeOf(_func(_iter[0].@\"0\", _iter[0].@\"1\"))){}; for (_iter) |item| { _result.append(__global_allocator, _func(item.@\"0\", item.@\"1\")) catch continue; } break :starmap_blk _result; }");
}

fn genCompress(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("std.ArrayList(i64){}"); return; }
    try self.emit("compress_blk: { const _data = "); try self.genExpr(args[0]);
    if (needsItems(self, args[0])) try self.emit(".items");
    try self.emit("; const _selectors = "); try self.genExpr(args[1]);
    if (needsItems(self, args[1])) try self.emit(".items");
    try self.emit("; var _result = std.ArrayList(@TypeOf(_data[0])){}; const _len = @min(_data.len, _selectors.len); for (0.._len) |i| { if (_selectors[i] != 0) _result.append(__global_allocator, _data[i]) catch continue; } break :compress_blk _result; }");
}

fn genTee(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit(".{ std.ArrayList(i64){}, std.ArrayList(i64){} }"); return; }
    try self.emit(".{ "); try self.genExpr(args[0]); try self.emit(", "); try self.genExpr(args[0]); try self.emit(" }");
}

fn genPairwise(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 1) { try self.emit("std.ArrayList(struct { @\"0\": i64, @\"1\": i64 }){}"); return; }
    try self.emit("pairwise_blk: { const _iter = "); try self.genExpr(args[0]);
    if (needsItems(self, args[0])) try self.emit(".items");
    try self.emit("; var _result = std.ArrayList(struct { @\"0\": @TypeOf(_iter[0]), @\"1\": @TypeOf(_iter[0]) }){}; if (_iter.len > 1) { for (0.._iter.len - 1) |i| { _result.append(__global_allocator, .{ .@\"0\" = _iter[i], .@\"1\" = _iter[i + 1] }) catch continue; } } break :pairwise_blk _result; }");
}
