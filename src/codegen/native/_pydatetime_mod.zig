/// Python _pydatetime module - Pure Python datetime implementation
const std = @import("std");
const h = @import("mod_helper.zig");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "date", genDate },
    .{ "time", h.c(".{ .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }") },
    .{ "datetime", genDatetime },
    .{ "timedelta", h.c(".{ .days = 0, .seconds = 0, .microseconds = 0 }") },
    .{ "timezone", h.c(".{ .offset = .{ .days = 0, .seconds = 0, .microseconds = 0 }, .name = null }") },
});

const ast = @import("analysis.ast");
const NativeCodegen = h.NativeCodegen;
const CodegenError = h.CodegenError;

fn genDate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) { try self.emit(".{ .year = 1970, .month = 1, .day = 1 }"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_date: {{ const y = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const m = "); try self.genExpr(args[1]);
    try self.emit("; const d = "); try self.genExpr(args[2]);
    try self.emitFmt("; break :__m{d}_date .{{ .year = y, .month = m, .day = d }}; }})", .{id});
}

fn genDatetime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) { try self.emit(".{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }"); return; }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_dt: {{ const y = ", .{id}); try self.genExpr(args[0]);
    try self.emit("; const m = "); try self.genExpr(args[1]);
    try self.emit("; const d = "); try self.genExpr(args[2]);
    try self.emitFmt("; break :__m{d}_dt .{{ .year = y, .month = m, .day = d, .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }}; }})", .{id});
}
