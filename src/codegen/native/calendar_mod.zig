/// Python calendar module - Calendar-related functions
/// MIGRATED TO ZIGBUILDER
const std = @import("std");
const ast = @import("analysis.ast");
const h = @import("mod_helper.zig");
const CodegenError = h.CodegenError;
const NativeCodegen = h.NativeCodegen;

pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    .{ "isleap", genIsleap }, .{ "leapdays", genLeapdays },
    .{ "weekday", genWeekday }, .{ "monthrange", genMonthrange },
    .{ "month", h.c("\"\"") }, .{ "monthcalendar", genMonthcalendar }, .{ "prmonth", h.discard("{}") }, .{ "calendar", h.c("\"\"") },
    .{ "prcal", h.discard("{}") }, .{ "setfirstweekday", h.discard("{}") }, .{ "firstweekday", h.I32(0) }, .{ "timegm", h.discard("@as(i64, 0)") },
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

const genIsleap = h.checkCond("(@rem(x, 4) == 0 and @rem(x, 100) != 0) or @rem(x, 400) == 0");
fn genLeapdays(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write("@as(i32, 0)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("leapdays", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const y1 = ");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write("; const y2 = ");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.writeFmt("; break :{s} @divFloor(y2 - 1, 4) - @divFloor(y1 - 1, 4) - (@divFloor(y2 - 1, 100) - @divFloor(y1 - 1, 100)) + (@divFloor(y2 - 1, 400) - @divFloor(y1 - 1, 400)); ", .{label});
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}

const zeller = " const __m = if (__month < 3) __month + 12 else __month; const __y = if (__month < 3) __year - 1 else __year; const __k = @rem(__y, 100); const __j = @divFloor(__y, 100);";

fn genWeekday(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) {
        const b = try self.getBuilder();
        try b.write("@as(i32, 0)");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("weekday", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const __year = @as(i32, @intCast(");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write(")); const __month = @as(i32, @intCast(");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.write(")); const __day = @as(i32, @intCast(");
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
            try c.genExpr(a[2]);
            {
                const b4 = try c.getBuilder();
                try b4.write("));" ++ zeller);
                try b4.writeFmt(" const __h = @rem(@as(i32, __day + @divFloor(13 * (__m + 1), 5) + __k + @divFloor(__k, 4) + @divFloor(__j, 4) - 2 * __j + 700), 7); break :{s} @rem(__h + 5, 7); ", .{label});
                const output4 = b4.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output4);
            }
        }
    }.emit);
}

fn genMonthrange(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) {
        const b = try self.getBuilder();
        try b.write(".{ @as(i32, 0), @as(i32, 30) }");
        const output = b.getBodyAndClear();
        try self.output.appendSlice(self.allocator, output);
        return;
    }
    try self.withInlineBlock("monthrange", args, struct {
        fn emit(c: *NativeCodegen, label: []const u8, a: []ast.Node) !void {
            const b = try c.getBuilder();
            try b.write("const __year = @as(i32, @intCast(");
            const output1 = b.getBodyAndClear();
            try c.output.appendSlice(c.allocator, output1);
            try c.genExpr(a[0]);
            {
                const b2 = try c.getBuilder();
                try b2.write(")); const __month = @as(i32, @intCast(");
                const output2 = b2.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output2);
            }
            try c.genExpr(a[1]);
            {
                const b3 = try c.getBuilder();
                try b3.write("));");
                try b3.write(" const __days_in_month = [_]i32{ 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };");
                try b3.write(" const __is_leap = (@rem(__year, 4) == 0 and @rem(__year, 100) != 0) or @rem(__year, 400) == 0;");
                try b3.write(" const __ndays = if (__month == 2 and __is_leap) 29 else __days_in_month[@intCast(__month)];" ++ zeller);
                try b3.write(" const __h = @rem(@as(i32, 1 + @divFloor(13 * (__m + 1), 5) + __k + @divFloor(__k, 4) + @divFloor(__j, 4) - 2 * __j + 700), 7);");
                try b3.writeFmt(" break :{s} .{{ @rem(__h + 5, 7), __ndays }}; ", .{label});
                const output3 = b3.getBodyAndClear();
                try c.output.appendSlice(c.allocator, output3);
            }
        }
    }.emit);
}

/// calendar.monthcalendar(year, month) - returns matrix of weeks
const genMonthcalendar = h.wrap2("runtime.calendar.monthcalendar(__global_allocator, ", ", ", ")", "&[_][]const i32{}");
