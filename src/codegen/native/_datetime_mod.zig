/// Python _datetime module - C accelerator for datetime (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const builder_mod = @import("codegen.builder");
const ast = @import("analysis.ast");

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "datetime", genDatetime },
    .{ "date", genDate },
    .{ "time", genTime },
    .{ "timedelta", genTimedelta },
    .{ "timezone", genTimezone },
    .{ "MINYEAR", genMinyear },
    .{ "MAXYEAR", genMaxyear },
    .{ "timezone_utc", genTimezoneUtc },
});

fn ic(self: *h.NativeCodegen, args: []ast.Node, idx: usize) h.CodegenError!void {
    if (args.len > idx) {
        try self.emit("@intCast(");
        try self.genExpr(args[idx]);
        try self.emit(")");
    } else {
        try self.emit("0");
    }
}

fn genDatetime(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 3) {
        try self.emit(".{ .year = @intCast(");
        try self.genExpr(args[0]);
        try self.emit("), .month = @intCast(");
        try self.genExpr(args[1]);
        try self.emit("), .day = @intCast(");
        try self.genExpr(args[2]);
        try self.emit("), .hour = ");
        try ic(self, args, 3);
        try self.emit(", .minute = ");
        try ic(self, args, 4);
        try self.emit(", .second = ");
        try ic(self, args, 5);
        try self.emit(", .microsecond = ");
        try ic(self, args, 6);
        try self.emit(" }");
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0 }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genDate(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len >= 3) {
        try self.emit(".{ .year = @intCast(");
        try self.genExpr(args[0]);
        try self.emit("), .month = @intCast(");
        try self.genExpr(args[1]);
        try self.emit("), .day = @intCast(");
        try self.genExpr(args[2]);
        try self.emit(") }");
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .year = 1970, .month = 1, .day = 1 }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genTime(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    try self.emit(".{ .hour = ");
    try ic(self, args, 0);
    try self.emit(", .minute = ");
    try ic(self, args, 1);
    try self.emit(", .second = ");
    try ic(self, args, 2);
    try self.emit(", .microsecond = ");
    try ic(self, args, 3);
    try self.emit(" }");
}

fn genTimedelta(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    try self.emit(".{ .days = ");
    try ic(self, args, 0);
    try self.emit(", .seconds = ");
    try ic(self, args, 1);
    try self.emit(", .microseconds = ");
    try ic(self, args, 2);
    try self.emit(" }");
}

fn genTimezone(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    if (args.len > 0) {
        try self.emit(".{ .offset = ");
        try self.genExpr(args[0]);
        try self.emit(", .name = ");
        if (args.len > 1) {
            try self.genExpr(args[1]);
        } else {
            try self.emit("null");
        }
        try self.emit(" }");
    } else {
        try b.emitValue(builder_mod.ZigValue.raw(".{ .offset = 0, .name = null }"), builder_mod.EmitConfig.forExpression());
    }
}

fn genMinyear(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 1)"), builder_mod.EmitConfig.forExpression());
}

fn genMaxyear(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw("@as(i32, 9999)"), builder_mod.EmitConfig.forExpression());
}

fn genTimezoneUtc(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.emitValue(builder_mod.ZigValue.raw(".{ .offset = 0, .name = \"UTC\" }"), builder_mod.EmitConfig.forExpression());
}
