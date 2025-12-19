/// Python _datetime module - C accelerator for datetime (internal)
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const h = @import("mod_helper.zig");
const ast = @import("analysis.ast");

// Helper for simple constant output
fn emitConst(self: *h.NativeCodegen, val: []const u8) h.CodegenError!void {
    const b = try self.getBuilder();
    try b.write(val);
    const output = b.getBodyAndClear();
    try self.output.appendSlice(self.allocator, output);
}

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
        try emitConst(self, "@intCast(");
        try self.genExpr(args[idx]);
        try emitConst(self, ")");
    } else {
        try emitConst(self, "0");
    }
}

fn genDatetime(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len >= 3) {
        try emitConst(self, ".{ .year = @intCast(");
        try self.genExpr(args[0]);
        try emitConst(self, "), .month = @intCast(");
        try self.genExpr(args[1]);
        try emitConst(self, "), .day = @intCast(");
        try self.genExpr(args[2]);
        try emitConst(self, "), .hour = ");
        try ic(self, args, 3);
        try emitConst(self, ", .minute = ");
        try ic(self, args, 4);
        try emitConst(self, ", .second = ");
        try ic(self, args, 5);
        try emitConst(self, ", .microsecond = ");
        try ic(self, args, 6);
        try emitConst(self, " }");
    } else {
        try emitConst(self, ".{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0 }");
    }
}

fn genDate(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len >= 3) {
        try emitConst(self, ".{ .year = @intCast(");
        try self.genExpr(args[0]);
        try emitConst(self, "), .month = @intCast(");
        try self.genExpr(args[1]);
        try emitConst(self, "), .day = @intCast(");
        try self.genExpr(args[2]);
        try emitConst(self, ") }");
    } else {
        try emitConst(self, ".{ .year = 1970, .month = 1, .day = 1 }");
    }
}

fn genTime(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    try emitConst(self, ".{ .hour = ");
    try ic(self, args, 0);
    try emitConst(self, ", .minute = ");
    try ic(self, args, 1);
    try emitConst(self, ", .second = ");
    try ic(self, args, 2);
    try emitConst(self, ", .microsecond = ");
    try ic(self, args, 3);
    try emitConst(self, " }");
}

fn genTimedelta(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    try emitConst(self, ".{ .days = ");
    try ic(self, args, 0);
    try emitConst(self, ", .seconds = ");
    try ic(self, args, 1);
    try emitConst(self, ", .microseconds = ");
    try ic(self, args, 2);
    try emitConst(self, " }");
}

fn genTimezone(self: *h.NativeCodegen, args: []ast.Node) h.CodegenError!void {
    if (args.len > 0) {
        try emitConst(self, ".{ .offset = ");
        try self.genExpr(args[0]);
        try emitConst(self, ", .name = ");
        if (args.len > 1) {
            try self.genExpr(args[1]);
        } else {
            try emitConst(self, "null");
        }
        try emitConst(self, " }");
    } else {
        try emitConst(self, ".{ .offset = 0, .name = null }");
    }
}

fn genMinyear(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(i32, 1)");
}

fn genMaxyear(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, "@as(i32, 9999)");
}

fn genTimezoneUtc(self: *h.NativeCodegen, _: []ast.Node) h.CodegenError!void {
    try emitConst(self, ".{ .offset = 0, .name = \"UTC\" }");
}
