/// Python _datetime module - C accelerator for datetime (internal)
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "datetime", genDatetime }, .{ "date", genDate }, .{ "time", genTime },
    .{ "timedelta", genTimedelta }, .{ "timezone", genTimezone },
    .{ "MINYEAR", h.I32(1) }, .{ "MAXYEAR", h.I32(9999) },
    .{ "timezone_utc", h.c(".{ .offset = 0, .name = \"UTC\" }") },
});

fn ic(self: *NativeCodegen, args: []ast.Node, idx: usize) CodegenError!void {
    if (args.len > idx) { try self.emit("@intCast("); try self.genExpr(args[idx]); try self.emit(")"); } else try self.emit("0");
}

fn genDatetime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) {
        try self.emit(".{ .year = @intCast("); try self.genExpr(args[0]); try self.emit("), .month = @intCast("); try self.genExpr(args[1]);
        try self.emit("), .day = @intCast("); try self.genExpr(args[2]); try self.emit("), .hour = "); try ic(self, args, 3);
        try self.emit(", .minute = "); try ic(self, args, 4); try self.emit(", .second = "); try ic(self, args, 5);
        try self.emit(", .microsecond = "); try ic(self, args, 6); try self.emit(" }");
    } else try self.emit(".{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0 }");
}

fn genDate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) {
        try self.emit(".{ .year = @intCast("); try self.genExpr(args[0]); try self.emit("), .month = @intCast("); try self.genExpr(args[1]);
        try self.emit("), .day = @intCast("); try self.genExpr(args[2]); try self.emit(") }");
    } else try self.emit(".{ .year = 1970, .month = 1, .day = 1 }");
}

fn genTime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit(".{ .hour = "); try ic(self, args, 0); try self.emit(", .minute = "); try ic(self, args, 1);
    try self.emit(", .second = "); try ic(self, args, 2); try self.emit(", .microsecond = "); try ic(self, args, 3); try self.emit(" }");
}

fn genTimedelta(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit(".{ .days = "); try ic(self, args, 0); try self.emit(", .seconds = "); try ic(self, args, 1);
    try self.emit(", .microseconds = "); try ic(self, args, 2); try self.emit(" }");
}

fn genTimezone(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ .offset = "); try self.genExpr(args[0]);
        try self.emit(", .name = "); if (args.len > 1) try self.genExpr(args[1]) else try self.emit("null"); try self.emit(" }");
    } else try self.emit(".{ .offset = 0, .name = null }");
}
