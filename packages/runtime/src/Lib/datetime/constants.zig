/// Constants for datetime module - MINYEAR, MAXYEAR, min/max values, resolution

const Timedelta = @import("timedelta.zig").Timedelta;
const Date = @import("date.zig").Date;
const Time = @import("time.zig").Time;
const Datetime = @import("datetime_impl.zig").Datetime;

// Year range constants
pub const MINYEAR: i64 = 1;
pub const MAXYEAR: i64 = 9999;

// Datetime min/max/resolution
pub const datetime_min = Datetime{ .year = 1, .month = 1, .day = 1, .hour = 0, .minute = 0, .second = 0, .microsecond = 0 };
pub const datetime_max = Datetime{ .year = 9999, .month = 12, .day = 31, .hour = 23, .minute = 59, .second = 59, .microsecond = 999999 };
pub const datetime_resolution = Timedelta.init(0, 0, 1);

// Date min/max/resolution
pub const date_min = Date{ .year = 1, .month = 1, .day = 1 };
pub const date_max = Date{ .year = 9999, .month = 12, .day = 31 };
pub const date_resolution = Timedelta.fromDays(1);

// Time min/max/resolution
pub const time_min = Time{ .hour = 0, .minute = 0, .second = 0, .microsecond = 0 };
pub const time_max = Time{ .hour = 23, .minute = 59, .second = 59, .microsecond = 999999 };
pub const time_resolution = Timedelta.init(0, 0, 1);

// Timedelta min/max/resolution
pub const timedelta_min = Timedelta.init(-999999999, 0, 0);
pub const timedelta_max = Timedelta.init(999999999, 86399, 999999);
pub const timedelta_resolution = Timedelta.init(0, 0, 1);
