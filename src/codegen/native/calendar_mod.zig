/// Python calendar module - Calendar-related functions
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "isleap", genIsleap }, .{ "leapdays", genLeapdays },
    .{ "weekday", h.I32(0) }, .{ "monthrange", h.c(".{ @as(i32, 0), @as(i32, 30) }") },
    .{ "month", h.c("\"\"") }, .{ "monthcalendar", h.c("&[_][]const i32{}") }, .{ "prmonth", h.c("{}") }, .{ "calendar", h.c("\"\"") },
    .{ "prcal", h.c("{}") }, .{ "setfirstweekday", h.c("{}") }, .{ "firstweekday", h.I32(0) }, .{ "timegm", h.I64(0) },
    .{ "Calendar", h.c(".{ .firstweekday = @as(i32, 0) }") }, .{ "TextCalendar", h.c(".{ .firstweekday = @as(i32, 0) }") }, .{ "HTMLCalendar", h.c(".{ .firstweekday = @as(i32, 0) }") },
    .{ "LocaleTextCalendar", h.c(".{ .firstweekday = @as(i32, 0), .locale = null }") }, .{ "LocaleHTMLCalendar", h.c(".{ .firstweekday = @as(i32, 0), .locale = null }") },
    .{ "MONDAY", h.I32(0) }, .{ "TUESDAY", h.I32(1) }, .{ "WEDNESDAY", h.I32(2) }, .{ "THURSDAY", h.I32(3) },
    .{ "FRIDAY", h.I32(4) }, .{ "SATURDAY", h.I32(5) }, .{ "SUNDAY", h.I32(6) },
    .{ "day_name", h.c("&[_][]const u8{ \"Monday\", \"Tuesday\", \"Wednesday\", \"Thursday\", \"Friday\", \"Saturday\", \"Sunday\" }") },
    .{ "day_abbr", h.c("&[_][]const u8{ \"Mon\", \"Tue\", \"Wed\", \"Thu\", \"Fri\", \"Sat\", \"Sun\" }") },
    .{ "month_name", h.c("&[_][]const u8{ \"\", \"January\", \"February\", \"March\", \"April\", \"May\", \"June\", \"July\", \"August\", \"September\", \"October\", \"November\", \"December\" }") },
    .{ "month_abbr", h.c("&[_][]const u8{ \"\", \"Jan\", \"Feb\", \"Mar\", \"Apr\", \"May\", \"Jun\", \"Jul\", \"Aug\", \"Sep\", \"Oct\", \"Nov\", \"Dec\" }") },
    .{ "IllegalMonthError", h.err("IllegalMonth") }, .{ "IllegalWeekdayError", h.err("IllegalWeekday") },
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
