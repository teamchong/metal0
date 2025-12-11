/// strftime/strptime formatting functions

const std = @import("std");
const Datetime = @import("datetime_impl.zig").Datetime;

fn isLeapYear(year: u32) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

/// strftime - format datetime according to format string
/// Supports: %Y, %m, %d, %H, %M, %S, %f (microseconds), %A, %a, %B, %b, %j, %U, %W, %w, %y, %p, %I, %%
pub fn strftime(allocator: std.mem.Allocator, dt: Datetime, format: []const u8) ![]const u8 {
    const weekdays_full = [_][]const u8{ "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" };
    const weekdays_abbr = [_][]const u8{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
    const months_full = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
    const months_abbr = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

    var result = std.ArrayList(u8){};

    var i: usize = 0;
    while (i < format.len) {
        if (format[i] == '%' and i + 1 < format.len) {
            const spec = format[i + 1];
            switch (spec) {
                'Y' => try result.writer(allocator).print("{d:0>4}", .{dt.year}),
                'y' => try result.writer(allocator).print("{d:0>2}", .{@mod(dt.year, 100)}),
                'm' => try result.writer(allocator).print("{d:0>2}", .{dt.month}),
                'd' => try result.writer(allocator).print("{d:0>2}", .{dt.day}),
                'H' => try result.writer(allocator).print("{d:0>2}", .{dt.hour}),
                'I' => try result.writer(allocator).print("{d:0>2}", .{if (dt.hour == 0) 12 else if (dt.hour > 12) dt.hour - 12 else dt.hour}),
                'M' => try result.writer(allocator).print("{d:0>2}", .{dt.minute}),
                'S' => try result.writer(allocator).print("{d:0>2}", .{dt.second}),
                'f' => try result.writer(allocator).print("{d:0>6}", .{dt.microsecond}),
                'p' => try result.appendSlice(allocator, if (dt.hour < 12) "AM" else "PM"),
                'A' => try result.appendSlice(allocator, weekdays_full[@intCast(dt.weekday())]),
                'a' => try result.appendSlice(allocator, weekdays_abbr[@intCast(dt.weekday())]),
                'B' => try result.appendSlice(allocator, months_full[@intCast(dt.month - 1)]),
                'b' => try result.appendSlice(allocator, months_abbr[@intCast(dt.month - 1)]),
                'w' => try result.writer(allocator).print("{d}", .{@mod(dt.weekday() + 1, 7)}), // Sunday=0
                'j' => {
                    // Day of year
                    const days_in_months = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
                    var doy: u32 = dt.day;
                    var m: u8 = 1;
                    while (m < dt.month) : (m += 1) {
                        doy += days_in_months[m - 1];
                        if (m == 2 and isLeapYear(dt.year)) doy += 1;
                    }
                    try result.writer(allocator).print("{d:0>3}", .{doy});
                },
                '%' => try result.append(allocator, '%'),
                else => {
                    try result.append(allocator, '%');
                    try result.append(allocator, spec);
                },
            }
            i += 2;
        } else {
            try result.append(allocator, format[i]);
            i += 1;
        }
    }

    return result.toOwnedSlice(allocator);
}

/// strptime - parse string to datetime using format
/// Supports: %Y, %m, %d, %H, %M, %S, %f
pub fn strptime(str: []const u8, format: []const u8) !Datetime {
    var year: u32 = 1900;
    var month: u8 = 1;
    var day: u8 = 1;
    var hour: u8 = 0;
    var minute: u8 = 0;
    var second: u8 = 0;
    var microsecond: u32 = 0;

    var str_idx: usize = 0;
    var fmt_idx: usize = 0;

    while (fmt_idx < format.len and str_idx < str.len) {
        if (format[fmt_idx] == '%' and fmt_idx + 1 < format.len) {
            const spec = format[fmt_idx + 1];
            switch (spec) {
                'Y' => {
                    if (str_idx + 4 > str.len) return error.InvalidFormat;
                    year = std.fmt.parseInt(u32, str[str_idx .. str_idx + 4], 10) catch return error.InvalidFormat;
                    str_idx += 4;
                },
                'y' => {
                    if (str_idx + 2 > str.len) return error.InvalidFormat;
                    const y = std.fmt.parseInt(u8, str[str_idx .. str_idx + 2], 10) catch return error.InvalidFormat;
                    year = if (y >= 69) 1900 + @as(u32, y) else 2000 + @as(u32, y);
                    str_idx += 2;
                },
                'm' => {
                    if (str_idx + 2 > str.len) return error.InvalidFormat;
                    month = std.fmt.parseInt(u8, str[str_idx .. str_idx + 2], 10) catch return error.InvalidFormat;
                    str_idx += 2;
                },
                'd' => {
                    if (str_idx + 2 > str.len) return error.InvalidFormat;
                    day = std.fmt.parseInt(u8, str[str_idx .. str_idx + 2], 10) catch return error.InvalidFormat;
                    str_idx += 2;
                },
                'H' => {
                    if (str_idx + 2 > str.len) return error.InvalidFormat;
                    hour = std.fmt.parseInt(u8, str[str_idx .. str_idx + 2], 10) catch return error.InvalidFormat;
                    str_idx += 2;
                },
                'I' => {
                    if (str_idx + 2 > str.len) return error.InvalidFormat;
                    hour = std.fmt.parseInt(u8, str[str_idx .. str_idx + 2], 10) catch return error.InvalidFormat;
                    str_idx += 2;
                },
                'M' => {
                    if (str_idx + 2 > str.len) return error.InvalidFormat;
                    minute = std.fmt.parseInt(u8, str[str_idx .. str_idx + 2], 10) catch return error.InvalidFormat;
                    str_idx += 2;
                },
                'S' => {
                    if (str_idx + 2 > str.len) return error.InvalidFormat;
                    second = std.fmt.parseInt(u8, str[str_idx .. str_idx + 2], 10) catch return error.InvalidFormat;
                    str_idx += 2;
                },
                'f' => {
                    // Microseconds - up to 6 digits
                    var end = str_idx;
                    while (end < str.len and end < str_idx + 6 and std.ascii.isDigit(str[end])) : (end += 1) {}
                    const usec_str = str[str_idx..end];
                    microsecond = std.fmt.parseInt(u32, usec_str, 10) catch 0;
                    // Pad to 6 digits
                    var mult: u32 = 1;
                    var i: usize = usec_str.len;
                    while (i < 6) : (i += 1) mult *= 10;
                    microsecond *= mult;
                    str_idx = end;
                },
                'p' => {
                    // AM/PM
                    if (str_idx + 2 > str.len) return error.InvalidFormat;
                    const ampm = str[str_idx .. str_idx + 2];
                    if (std.mem.eql(u8, ampm, "PM") or std.mem.eql(u8, ampm, "pm")) {
                        if (hour != 12) hour += 12;
                    } else if (std.mem.eql(u8, ampm, "AM") or std.mem.eql(u8, ampm, "am")) {
                        if (hour == 12) hour = 0;
                    }
                    str_idx += 2;
                },
                '%' => {
                    if (str[str_idx] != '%') return error.InvalidFormat;
                    str_idx += 1;
                },
                else => {
                    // Unknown format code - skip
                    str_idx += 1;
                },
            }
            fmt_idx += 2;
        } else {
            // Literal character must match
            if (str[str_idx] != format[fmt_idx]) return error.InvalidFormat;
            str_idx += 1;
            fmt_idx += 1;
        }
    }

    return Datetime{
        .year = year,
        .month = month,
        .day = day,
        .hour = hour,
        .minute = minute,
        .second = second,
        .microsecond = microsecond,
    };
}
