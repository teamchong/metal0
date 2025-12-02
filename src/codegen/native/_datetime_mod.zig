/// Python _datetime module - C accelerator for datetime (internal)
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "datetime", genDatetime }, .{ "date", genDate }, .{ "time", genTime },
    .{ "timedelta", genTimedelta }, .{ "timezone", genTimezone },
    .{ "MINYEAR", genConst("@as(i32, 1)") }, .{ "MAXYEAR", genConst("@as(i32, 9999)") },
    .{ "timezone_utc", genConst(".{ .offset = 0, .name = \"UTC\" }") },
});

fn emitIntCast(self: *NativeCodegen, args: []ast.Node, idx: usize, default: []const u8) CodegenError!void {
    if (args.len > idx) { try self.emit("@intCast("); try self.genExpr(args[idx]); try self.emit(")"); } else try self.emit(default);
}

fn genDatetime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) {
        try self.emit(".{ .year = @intCast("); try self.genExpr(args[0]);
        try self.emit("), .month = @intCast("); try self.genExpr(args[1]);
        try self.emit("), .day = @intCast("); try self.genExpr(args[2]);
        try self.emit("), .hour = "); try emitIntCast(self, args, 3, "0");
        try self.emit(", .minute = "); try emitIntCast(self, args, 4, "0");
        try self.emit(", .second = "); try emitIntCast(self, args, 5, "0");
        try self.emit(", .microsecond = "); try emitIntCast(self, args, 6, "0");
        try self.emit(" }");
    } else try self.emit(".{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0 }");
}

fn genDate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) {
        try self.emit(".{ .year = @intCast("); try self.genExpr(args[0]);
        try self.emit("), .month = @intCast("); try self.genExpr(args[1]);
        try self.emit("), .day = @intCast("); try self.genExpr(args[2]); try self.emit(") }");
    } else try self.emit(".{ .year = 1970, .month = 1, .day = 1 }");
}

fn genTime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit(".{ .hour = "); try emitIntCast(self, args, 0, "0");
    try self.emit(", .minute = "); try emitIntCast(self, args, 1, "0");
    try self.emit(", .second = "); try emitIntCast(self, args, 2, "0");
    try self.emit(", .microsecond = "); try emitIntCast(self, args, 3, "0");
    try self.emit(" }");
}

fn genTimedelta(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    try self.emit(".{ .days = "); try emitIntCast(self, args, 0, "0");
    try self.emit(", .seconds = "); try emitIntCast(self, args, 1, "0");
    try self.emit(", .microseconds = "); try emitIntCast(self, args, 2, "0");
    try self.emit(" }");
}

fn genTimezone(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit(".{ .offset = "); try self.genExpr(args[0]);
        try self.emit(", .name = "); if (args.len > 1) try self.genExpr(args[1]) else try self.emit("null");
        try self.emit(" }");
    } else try self.emit(".{ .offset = 0, .name = null }");
}
