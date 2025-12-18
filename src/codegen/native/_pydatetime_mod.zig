/// Python _pydatetime module - Pure Python datetime implementation
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "date", genDate },
    .{ "time", genTime },
    .{ "datetime", genDatetime },
    .{ "timedelta", genTimedelta },
    .{ "timezone", genTimezone },
});

fn genDate(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len < 3) {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .year = 1970, .month = 1, .day = 1 }"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_date: {{ const y = ", .{id});
    try self.genExpr(args[0]);
    try self.emit("; const m = ");
    try self.genExpr(args[1]);
    try self.emit("; const d = ");
    try self.genExpr(args[2]);
    try self.emitFmt("; break :__m{d}_date .{{ .year = y, .month = m, .day = d }}; }})", .{id});
}

fn genTime(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }"), builder_mod.EmitConfig.forExpression());
}

fn genDatetime(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len < 3) {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }"), builder_mod.EmitConfig.forExpression());
        return;
    }
    const id = self.nextNameId();
    try self.emitFmt("(__m{d}_dt: {{ const y = ", .{id});
    try self.genExpr(args[0]);
    try self.emit("; const m = ");
    try self.genExpr(args[1]);
    try self.emit("; const d = ");
    try self.genExpr(args[2]);
    try self.emitFmt("; break :__m{d}_dt .{{ .year = y, .month = m, .day = d, .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }}; }})", .{id});
}

fn genTimedelta(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .days = 0, .seconds = 0, .microseconds = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genTimezone(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .offset = .{ .days = 0, .seconds = 0, .microseconds = 0 }, .name = null }"), builder_mod.EmitConfig.forExpression());
}
