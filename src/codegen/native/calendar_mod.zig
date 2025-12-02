/// Python calendar module - Calendar-related functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
fn genConst(comptime v: []const u8) ModuleHandler {
    return struct { fn f(self: *NativeCodegen, args: []ast.Node) CodegenError!void { _ = args; try self.emit(v); } }.f;
}

pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "isleap", genIsleap }, .{ "leapdays", genLeapdays },
    .{ "weekday", genConst("@as(i32, 0)") }, .{ "monthrange", genConst(".{ @as(i32, 0), @as(i32, 30) }") },
    .{ "month", genConst("\"\"") }, .{ "monthcalendar", genConst("&[_][]const i32{}") }, .{ "prmonth", genConst("{}") }, .{ "calendar", genConst("\"\"") },
    .{ "prcal", genConst("{}") }, .{ "setfirstweekday", genConst("{}") }, .{ "firstweekday", genConst("@as(i32, 0)") }, .{ "timegm", genConst("@as(i64, 0)") },
    .{ "Calendar", genConst(".{ .firstweekday = @as(i32, 0) }") }, .{ "TextCalendar", genConst(".{ .firstweekday = @as(i32, 0) }") }, .{ "HTMLCalendar", genConst(".{ .firstweekday = @as(i32, 0) }") },
    .{ "LocaleTextCalendar", genConst(".{ .firstweekday = @as(i32, 0), .locale = null }") }, .{ "LocaleHTMLCalendar", genConst(".{ .firstweekday = @as(i32, 0), .locale = null }") },
    .{ "MONDAY", genConst("@as(i32, 0)") }, .{ "TUESDAY", genConst("@as(i32, 1)") }, .{ "WEDNESDAY", genConst("@as(i32, 2)") }, .{ "THURSDAY", genConst("@as(i32, 3)") },
    .{ "FRIDAY", genConst("@as(i32, 4)") }, .{ "SATURDAY", genConst("@as(i32, 5)") }, .{ "SUNDAY", genConst("@as(i32, 6)") },
    .{ "day_name", genConst("&[_][]const u8{ \"Monday\", \"Tuesday\", \"Wednesday\", \"Thursday\", \"Friday\", \"Saturday\", \"Sunday\" }") },
    .{ "day_abbr", genConst("&[_][]const u8{ \"Mon\", \"Tue\", \"Wed\", \"Thu\", \"Fri\", \"Sat\", \"Sun\" }") },
    .{ "month_name", genConst("&[_][]const u8{ \"\", \"January\", \"February\", \"March\", \"April\", \"May\", \"June\", \"July\", \"August\", \"September\", \"October\", \"November\", \"December\" }") },
    .{ "month_abbr", genConst("&[_][]const u8{ \"\", \"Jan\", \"Feb\", \"Mar\", \"Apr\", \"May\", \"Jun\", \"Jul\", \"Aug\", \"Sep\", \"Oct\", \"Nov\", \"Dec\" }") },
    .{ "IllegalMonthError", genConst("error.IllegalMonth") }, .{ "IllegalWeekdayError", genConst("error.IllegalWeekday") },
});

fn genIsleap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) { try self.emit("false"); return; }
    try self.emit("blk: { const y = "); try self.genExpr(args[0]);
    try self.emit("; break :blk (@rem(y, 4) == 0 and @rem(y, 100) != 0) or @rem(y, 400) == 0; }");
}

fn genLeapdays(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(i32, 0)"); return; }
    try self.emit("blk: { const y1 = "); try self.genExpr(args[0]);
    try self.emit("; const y2 = "); try self.genExpr(args[1]);
    try self.emit("; const a = y1 - 1; const b = y2 - 1; break :blk @divFloor(b, 4) - @divFloor(a, 4) - (@divFloor(b, 100) - @divFloor(a, 100)) + (@divFloor(b, 400) - @divFloor(a, 400)); }");
}
