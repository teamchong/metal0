/// Python calendar module - Calendar-related functions
const std = @import("std");
const ast = @import("ast");
const CodegenError = @import("main.zig").CodegenError;
const NativeCodegen = @import("main.zig").NativeCodegen;

const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "isleap", genIsleap },
    .{ "leapdays", genLeapdays },
    .{ "weekday", genWeekday },
    .{ "monthrange", genMonthrange },
    .{ "month", genMonth },
    .{ "monthcalendar", genMonthcalendar },
    .{ "prmonth", genPrmonth },
    .{ "calendar", genCalendar },
    .{ "prcal", genPrcal },
    .{ "setfirstweekday", genSetfirstweekday },
    .{ "firstweekday", genFirstweekday },
    .{ "timegm", genTimegm },
    .{ "Calendar", genCalendarClass },
    .{ "TextCalendar", genTextCalendar },
    .{ "HTMLCalendar", genHTMLCalendar },
    .{ "LocaleTextCalendar", genLocaleTextCalendar },
    .{ "LocaleHTMLCalendar", genLocaleHTMLCalendar },
    .{ "MONDAY", genMONDAY },
    .{ "TUESDAY", genTUESDAY },
    .{ "WEDNESDAY", genWEDNESDAY },
    .{ "THURSDAY", genTHURSDAY },
    .{ "FRIDAY", genFRIDAY },
    .{ "SATURDAY", genSATURDAY },
    .{ "SUNDAY", genSUNDAY },
    .{ "day_name", genDay_name },
    .{ "day_abbr", genDay_abbr },
    .{ "month_name", genMonth_name },
    .{ "month_abbr", genMonth_abbr },
    .{ "IllegalMonthError", genIllegalMonthError },
    .{ "IllegalWeekdayError", genIllegalWeekdayError },
});

/// Generate calendar.isleap(year) - check if year is leap year
pub fn genIsleap(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len > 0) {
        try self.emit("blk: { const y = ");
        try self.genExpr(args[0]);
        try self.emit("; break :blk (@rem(y, 4) == 0 and @rem(y, 100) != 0) or @rem(y, 400) == 0; }");
    } else {
        try self.emit("false");
    }
}

/// Generate calendar.leapdays(y1, y2) - number of leap years in range
pub fn genLeapdays(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len >= 2) {
        try self.emit("blk: { const y1 = ");
        try self.genExpr(args[0]);
        try self.emit("; const y2 = ");
        try self.genExpr(args[1]);
        try self.emit("; const a = y1 - 1; const b = y2 - 1; break :blk @divFloor(b, 4) - @divFloor(a, 4) - (@divFloor(b, 100) - @divFloor(a, 100)) + (@divFloor(b, 400) - @divFloor(a, 400)); }");
    } else {
        try self.emit("@as(i32, 0)");
    }
}

/// Generate calendar.weekday(year, month, day) - return weekday (0=Monday)
pub fn genWeekday(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

/// Generate calendar.monthrange(year, month) - (first weekday, days in month)
pub fn genMonthrange(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ @as(i32, 0), @as(i32, 30) }");
}

/// Generate calendar.month(theyear, themonth, w=0, l=0) - month calendar string
pub fn genMonth(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate calendar.monthcalendar(year, month) - matrix of days
pub fn genMonthcalendar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const i32{}");
}

/// Generate calendar.prmonth(theyear, themonth, w=0, l=0) - print month
pub fn genPrmonth(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate calendar.calendar(year, w=2, l=1, c=6, m=3) - year calendar string
pub fn genCalendar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("\"\"");
}

/// Generate calendar.prcal(year, w=0, l=0, c=6, m=3) - print year calendar
pub fn genPrcal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate calendar.setfirstweekday(firstweekday)
pub fn genSetfirstweekday(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("{}");
}

/// Generate calendar.firstweekday() - get current first weekday
pub fn genFirstweekday(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)"); // Monday
}

/// Generate calendar.timegm(tuple) - inverse of time.gmtime
pub fn genTimegm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i64, 0)");
}

/// Generate calendar.Calendar class
pub fn genCalendarClass(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .firstweekday = @as(i32, 0) }");
}

/// Generate calendar.TextCalendar class
pub fn genTextCalendar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .firstweekday = @as(i32, 0) }");
}

/// Generate calendar.HTMLCalendar class
pub fn genHTMLCalendar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .firstweekday = @as(i32, 0) }");
}

/// Generate calendar.LocaleTextCalendar class
pub fn genLocaleTextCalendar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .firstweekday = @as(i32, 0), .locale = null }");
}

/// Generate calendar.LocaleHTMLCalendar class
pub fn genLocaleHTMLCalendar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit(".{ .firstweekday = @as(i32, 0), .locale = null }");
}

// ============================================================================
// Day constants
// ============================================================================

pub fn genMONDAY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 0)");
}

pub fn genTUESDAY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 1)");
}

pub fn genWEDNESDAY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 2)");
}

pub fn genTHURSDAY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 3)");
}

pub fn genFRIDAY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 4)");
}

pub fn genSATURDAY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 5)");
}

pub fn genSUNDAY(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("@as(i32, 6)");
}

// ============================================================================
// Month and day name lists
// ============================================================================

pub fn genDay_name(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"Monday\", \"Tuesday\", \"Wednesday\", \"Thursday\", \"Friday\", \"Saturday\", \"Sunday\" }");
}

pub fn genDay_abbr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"Mon\", \"Tue\", \"Wed\", \"Thu\", \"Fri\", \"Sat\", \"Sun\" }");
}

pub fn genMonth_name(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"\", \"January\", \"February\", \"March\", \"April\", \"May\", \"June\", \"July\", \"August\", \"September\", \"October\", \"November\", \"December\" }");
}

pub fn genMonth_abbr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("&[_][]const u8{ \"\", \"Jan\", \"Feb\", \"Mar\", \"Apr\", \"May\", \"Jun\", \"Jul\", \"Aug\", \"Sep\", \"Oct\", \"Nov\", \"Dec\" }");
}

// ============================================================================
// Error class
// ============================================================================

pub fn genIllegalMonthError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.IllegalMonth");
}

pub fn genIllegalWeekdayError(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    _ = args;
    try self.emit("error.IllegalWeekday");
}
