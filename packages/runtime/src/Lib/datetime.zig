/// DateTime module - Python datetime.datetime, datetime.date, datetime.timedelta support
/// Main entry point that re-exports all datetime functionality

const std = @import("std");

// Re-export all submodules
pub const constants = @import("datetime/constants.zig");
pub const date_module = @import("datetime/date.zig");
pub const time_module = @import("datetime/time.zig");
pub const timedelta_module = @import("datetime/timedelta.zig");
pub const datetime_module = @import("datetime/datetime_impl.zig");
pub const timezone_module = @import("datetime/timezone.zig");
pub const formatting = @import("datetime/formatting.zig");

// Re-export main types
pub const Date = date_module.Date;
pub const Time = time_module.Time;
pub const Timedelta = timedelta_module.Timedelta;
pub const Datetime = datetime_module.Datetime;
pub const TzInfo = timezone_module.TzInfo;
pub const Timezone = timezone_module.Timezone;
pub const UTC = timezone_module.UTC;
pub const DatetimeWithTz = timezone_module.DatetimeWithTz;

// Re-export extension types
pub const DateExt = date_module.DateExt;
pub const TimeExt = time_module.TimeExt;
pub const DatetimeExt = datetime_module.DatetimeExt;

// Re-export constants
pub const MINYEAR = constants.MINYEAR;
pub const MAXYEAR = constants.MAXYEAR;
pub const datetime_min = constants.datetime_min;
pub const datetime_max = constants.datetime_max;
pub const datetime_resolution = constants.datetime_resolution;
pub const date_min = constants.date_min;
pub const date_max = constants.date_max;
pub const date_resolution = constants.date_resolution;
pub const time_min = constants.time_min;
pub const time_max = constants.time_max;
pub const time_resolution = constants.time_resolution;
pub const timedelta_min = constants.timedelta_min;
pub const timedelta_max = constants.timedelta_max;
pub const timedelta_resolution = constants.timedelta_resolution;

// Re-export helper functions
pub const daysFromDate = date_module.daysFromDate;

// Re-export formatting functions
pub const strftime = formatting.strftime;
pub const strptime = formatting.strptime;

// Re-export public API for codegen
pub const datetimeNow = datetime_module.datetimeNow;
pub const dateToday = date_module.dateToday;
pub const date = date_module.date;
pub const time = time_module.time;
pub const timeFull = time_module.timeFull;
pub const timedelta = timedelta_module.timedelta;
pub const timedeltaFull = timedelta_module.timedeltaFull;
pub const timedeltaToPyString = timedelta_module.timedeltaToPyString;
pub const datetime = datetime_module.datetime;
pub const utcnow = datetime_module.utcnow;
pub const utcfromtimestamp = datetime_module.utcfromtimestamp;
pub const combine = datetime_module.combine;
pub const dateFromIsocalendar = date_module.dateFromIsocalendar;
pub const datetimeFromIsocalendar = datetime_module.datetimeFromIsocalendar;
pub const astimezone = timezone_module.astimezone;

// Re-export tests
test {
    std.testing.refAllDecls(@This());
}
