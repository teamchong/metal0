/// Python calendar module - Calendar-related functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "isleap", genIsleap }, .{ "leapdays", genLeapdays }, .{ "weekday", genI32_0 }, .{ "monthrange", genMonthrange },
    .{ "month", genEmptyStr }, .{ "monthcalendar", genEmptyMatrix }, .{ "prmonth", genUnit }, .{ "calendar", genEmptyStr },
    .{ "prcal", genUnit }, .{ "setfirstweekday", genUnit }, .{ "firstweekday", genI32_0 }, .{ "timegm", genI64_0 },
    .{ "Calendar", genCalendarClass }, .{ "TextCalendar", genCalendarClass }, .{ "HTMLCalendar", genCalendarClass },
    .{ "LocaleTextCalendar", genLocaleCalendar }, .{ "LocaleHTMLCalendar", genLocaleCalendar },
    .{ "MONDAY", genI32_0 }, .{ "TUESDAY", genI32_1 }, .{ "WEDNESDAY", genI32_2 }, .{ "THURSDAY", genI32_3 },
    .{ "FRIDAY", genI32_4 }, .{ "SATURDAY", genI32_5 }, .{ "SUNDAY", genI32_6 },
    .{ "day_name", genDayName }, .{ "day_abbr", genDayAbbr }, .{ "month_name", genMonthName }, .{ "month_abbr", genMonthAbbr },
    .{ "IllegalMonthError", genIllegalMonth }, .{ "IllegalWeekdayError", genIllegalWeekday },
});

// Helpers
fn genConst(self: *NativeCodegen, args: []ast.Node, value: []const u8) CodegenError!void { _ = args; try self.emit(value); }
fn genUnit(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "{}"); }
fn genEmptyStr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "\"\""); }
fn genEmptyMatrix(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const i32{}"); }
fn genMonthrange(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ @as(i32, 0), @as(i32, 30) }"); }
fn genCalendarClass(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .firstweekday = @as(i32, 0) }"); }
fn genLocaleCalendar(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, ".{ .firstweekday = @as(i32, 0), .locale = null }"); }
fn genIllegalMonth(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.IllegalMonth"); }
fn genIllegalWeekday(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "error.IllegalWeekday"); }
fn genDayName(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"Monday\", \"Tuesday\", \"Wednesday\", \"Thursday\", \"Friday\", \"Saturday\", \"Sunday\" }"); }
fn genDayAbbr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"Mon\", \"Tue\", \"Wed\", \"Thu\", \"Fri\", \"Sat\", \"Sun\" }"); }
fn genMonthName(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"\", \"January\", \"February\", \"March\", \"April\", \"May\", \"June\", \"July\", \"August\", \"September\", \"October\", \"November\", \"December\" }"); }
fn genMonthAbbr(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "&[_][]const u8{ \"\", \"Jan\", \"Feb\", \"Mar\", \"Apr\", \"May\", \"Jun\", \"Jul\", \"Aug\", \"Sep\", \"Oct\", \"Nov\", \"Dec\" }"); }

// Integer constants
fn genI32_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 0)"); }
fn genI32_1(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 1)"); }
fn genI32_2(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 2)"); }
fn genI32_3(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 3)"); }
fn genI32_4(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 4)"); }
fn genI32_5(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 5)"); }
fn genI32_6(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i32, 6)"); }
fn genI64_0(self: *NativeCodegen, args: []ast.Node) CodegenError!void { try genConst(self, args, "@as(i64, 0)"); }

// Functions with logic
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
