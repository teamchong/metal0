/// Python calendar module runtime support
const std = @import("std");

/// Returns the day of week for a given date (0=Monday, 6=Sunday)
pub fn weekday(year: i32, month: i32, day: i32) i32 {
    const m = if (month < 3) month + 12 else month;
    const y = if (month < 3) year - 1 else year;
    const k = @rem(y, 100);
    const j = @divFloor(y, 100);
    const h = @rem(@as(i32, day + @divFloor(13 * (m + 1), 5) + k + @divFloor(k, 4) + @divFloor(j, 4) - 2 * j + 700), 7);
    return @rem(h + 5, 7);
}

/// Returns true if year is a leap year
pub fn isleap(year: i32) bool {
    return (@rem(year, 4) == 0 and @rem(year, 100) != 0) or @rem(year, 400) == 0;
}

/// Returns number of days in a given month
pub fn daysInMonth(year: i32, month: i32) i32 {
    const days = [_]i32{ 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (month == 2 and isleap(year)) return 29;
    return days[@intCast(month)];
}

/// Returns (first_weekday, num_days) for a month
pub fn monthrange(year: i32, month: i32) struct { first_weekday: i32, ndays: i32 } {
    return .{
        .first_weekday = weekday(year, month, 1),
        .ndays = daysInMonth(year, month),
    };
}

/// Calendar row type - 7 days per week
pub const WeekRow = [7]i32;

/// Returns a matrix where each row represents a week, and each value is a day number (0 = not in month)
pub fn monthcalendar(allocator: std.mem.Allocator, year_val: anytype, month_val: anytype) []WeekRow {
    const year: i32 = @intCast(year_val);
    const month: i32 = @intCast(month_val);

    const first_day = weekday(year, month, 1);
    const ndays = daysInMonth(year, month);

    // Calculate number of weeks needed
    const total_cells = @as(usize, @intCast(first_day)) + @as(usize, @intCast(ndays));
    const nweeks = (total_cells + 6) / 7;

    // Allocate result
    var result = allocator.alloc(WeekRow, nweeks) catch return &[_]WeekRow{};

    var day: i32 = 1;
    for (0..nweeks) |week| {
        for (0..7) |dow| {
            const cell_index = week * 7 + dow;
            const day_offset = @as(i32, @intCast(cell_index)) - first_day;

            if (day_offset >= 0 and day_offset < ndays) {
                result[week][dow] = day_offset + 1;
            } else {
                result[week][dow] = 0;
            }
        }
        day += 7;
    }

    return result;
}
