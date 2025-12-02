/// Python calendar module - Calendar-related functions
const std = @import("std");
const ast = @import("ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "isleap", genIsleap }, .{ "leapdays", genLeapdays },
    .{ "weekday", genWeekday }, .{ "monthrange", genMonthrange },
    .{ "month", h.c("\"\"") }, .{ "monthcalendar", genMonthcalendar }, .{ "prmonth", h.c("{}") }, .{ "calendar", h.c("\"\"") },
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
    const id = try h.emitUniqueBlockStart(self, "isleap");
    try self.emit("const y = "); try self.genExpr(args[0]);
    try h.emitBlockBreak(self, "isleap", id);
    try self.emit("(@rem(y, 4) == 0 and @rem(y, 100) != 0) or @rem(y, 400) == 0; }");
}

fn genLeapdays(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("@as(i32, 0)"); return; }
    const id = try h.emitUniqueBlockStart(self, "leapdays");
    try self.emit("const y1 = "); try self.genExpr(args[0]);
    try self.emit("; const y2 = "); try self.genExpr(args[1]);
    try h.emitBlockBreak(self, "leapdays", id);
    try self.emit("@divFloor(y2 - 1, 4) - @divFloor(y1 - 1, 4) - (@divFloor(y2 - 1, 100) - @divFloor(y1 - 1, 100)) + (@divFloor(y2 - 1, 400) - @divFloor(y1 - 1, 400)); }");
}

/// calendar.weekday(year, month, day) - returns day of week (0=Monday to 6=Sunday)
fn genWeekday(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) { try self.emit("@as(i32, 0)"); return; }
    const id = try h.emitUniqueBlockStart(self, "weekday");
    try self.emit("const __year = @as(i32, @intCast("); try self.genExpr(args[0]); try self.emit("));");
    try self.emit(" const __month = @as(i32, @intCast("); try self.genExpr(args[1]); try self.emit("));");
    try self.emit(" const __day = @as(i32, @intCast("); try self.genExpr(args[2]); try self.emit("));");
    // Zeller's congruence adjusted for Monday=0
    try self.emit(" const __m = if (__month < 3) __month + 12 else __month;");
    try self.emit(" const __y = if (__month < 3) __year - 1 else __year;");
    try self.emit(" const __q = __day;");
    try self.emit(" const __k = @rem(__y, 100);");
    try self.emit(" const __j = @divFloor(__y, 100);");
    try self.emit(" const __h = @rem(@as(i32, __q + @divFloor(13 * (__m + 1), 5) + __k + @divFloor(__k, 4) + @divFloor(__j, 4) - 2 * __j + 700), 7)");
    try h.emitBlockBreak(self, "weekday", id);
    try self.emit("@rem(__h + 5, 7); }"); // Convert to Monday=0
}

/// calendar.monthrange(year, month) - returns (first_weekday, num_days)
fn genMonthrange(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit(".{ @as(i32, 0), @as(i32, 30) }"); return; }
    const id = try h.emitUniqueBlockStart(self, "monthrange");
    try self.emit("const __year = @as(i32, @intCast("); try self.genExpr(args[0]); try self.emit("));");
    try self.emit(" const __month = @as(i32, @intCast("); try self.genExpr(args[1]); try self.emit("));");
    // Days in month
    try self.emit(" const __days_in_month = [_]i32{ 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };");
    try self.emit(" const __is_leap = (@rem(__year, 4) == 0 and @rem(__year, 100) != 0) or @rem(__year, 400) == 0;");
    try self.emit(" const __ndays = if (__month == 2 and __is_leap) 29 else __days_in_month[@intCast(__month)];");
    // First weekday using Zeller's congruence
    try self.emit(" const __m = if (__month < 3) __month + 12 else __month;");
    try self.emit(" const __y = if (__month < 3) __year - 1 else __year;");
    try self.emit(" const __k = @rem(__y, 100);");
    try self.emit(" const __j = @divFloor(__y, 100);");
    try self.emit(" const __h = @rem(@as(i32, 1 + @divFloor(13 * (__m + 1), 5) + __k + @divFloor(__k, 4) + @divFloor(__j, 4) - 2 * __j + 700), 7);");
    try self.emit(" const __first_weekday = @rem(__h + 5, 7)");
    try h.emitBlockBreak(self, "monthrange", id);
    try self.emit(".{ __first_weekday, __ndays }; }");
}

/// calendar.monthcalendar(year, month) - returns matrix of weeks
fn genMonthcalendar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) { try self.emit("&[_][]const i32{}"); return; }
    try self.emit("runtime.calendar.monthcalendar(__global_allocator, ");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(")"    );
}
