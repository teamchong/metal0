/// Python _pydatetime module - Pure Python datetime implementation
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "date", genDate }, .{ "time", genTime }, .{ "datetime", genDatetime }, .{ "timedelta", genTD }, .{ "timezone", genTZ },
});

fn genConst(self: *NativeCodegen, args: []ast.Node, v: []const u8) CodegenError!void { _ = args; try self.emit(v); }
fn genTime(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }"); }
fn genTD(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .days = 0, .seconds = 0, .microseconds = 0 }"); }
fn genTZ(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .offset = .{ .days = 0, .seconds = 0, .microseconds = 0 }, .name = null }"); }

fn genDate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) { try self.emit("blk: { const y = "); try self.genExpr(args[0]); try self.emit("; const m = "); try self.genExpr(args[1]); try self.emit("; const d = "); try self.genExpr(args[2]); try self.emit("; break :blk .{ .year = y, .month = m, .day = d }; }"); } else { try self.emit(".{ .year = 1970, .month = 1, .day = 1 }"); }
}

fn genDatetime(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 3) { try self.emit("blk: { const y = "); try self.genExpr(args[0]); try self.emit("; const m = "); try self.genExpr(args[1]); try self.emit("; const d = "); try self.genExpr(args[2]); try self.emit("; break :blk .{ .year = y, .month = m, .day = d, .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }; }"); } else { try self.emit(".{ .year = 1970, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0, .tzinfo = null }"); }
}
