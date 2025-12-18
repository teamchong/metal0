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
    try self.withInlineBlock("date", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const y = ");
            try c.genExpr(a[0]);
            try c.emit("; const m = ");
            try c.genExpr(a[1]);
            try c.emit("; const d = ");
            try c.genExpr(a[2]);
            try c.emitFmt("; break :{s} .{{ .year = y, .month = m, .day = d }}", .{label});
        }
    }.emit);
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
    try self.withInlineBlock("dt", args, struct {
        fn emit(c: *h.NativeCodegen, label: []const u8, a: []ast.Node) !void {
            try c.emit("const y = ");
            try c.genExpr(a[0]);
            try c.emit("; const m = ");
            try c.genExpr(a[1]);
            try c.emit("; const d = ");
            try c.genExpr(a[2]);
            try c.emitFmt("; break :{s} .{{ .year = y, .month = m, .day = d, .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }}", .{label});
        }
    }.emit);
}

fn genTimedelta(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .days = 0, .seconds = 0, .microseconds = 0 }"), builder_mod.EmitConfig.forExpression());
}

fn genTimezone(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .offset = .{ .days = 0, .seconds = 0, .microseconds = 0 }, .name = null }"), builder_mod.EmitConfig.forExpression());
}
