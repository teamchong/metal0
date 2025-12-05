/// CPython DateTime API
///
/// Implements datetime module C API for date, time, datetime, timedelta objects.
/// Used by C extensions like NumPy for datetime64 support.
///
/// Reference: cpython/Include/datetime.h

const std = @import("std");
const cpython = @import("cpython_object.zig");
const traits = @import("pyobject_traits.zig");

// Use centralized extern declarations
const Py_INCREF = traits.externs.Py_INCREF;
const Py_DECREF = traits.externs.Py_DECREF;
const PyObject_Malloc = traits.externs.PyObject_Malloc;
const PyObject_Free = traits.externs.PyObject_Free;

// ============================================================================
// DATETIME STRUCTURES
// ============================================================================

/// PyDateTime_Date - Date object (year, month, day)
pub const PyDateTime_Date = extern struct {
    ob_base: cpython.PyObject,
    hashcode: isize,
    hastzinfo: u8,
    data: [4]u8, // year(2) + month(1) + day(1)
};

/// PyDateTime_Time - Time object (hour, minute, second, microsecond)
pub const PyDateTime_Time = extern struct {
    ob_base: cpython.PyObject,
    hashcode: isize,
    hastzinfo: u8,
    data: [6]u8, // hour(1) + minute(1) + second(1) + microsecond(3)
    tzinfo: ?*cpython.PyObject,
};

/// PyDateTime_DateTime - Combined date and time
pub const PyDateTime_DateTime = extern struct {
    ob_base: cpython.PyObject,
    hashcode: isize,
    hastzinfo: u8,
    data: [10]u8, // year(2) + month(1) + day(1) + hour(1) + minute(1) + second(1) + microsecond(3)
    tzinfo: ?*cpython.PyObject,
};

/// PyDateTime_Delta - Time delta (days, seconds, microseconds)
pub const PyDateTime_Delta = extern struct {
    ob_base: cpython.PyObject,
    hashcode: isize,
    days: c_int,
    seconds: c_int,
    microseconds: c_int,
};

// ============================================================================
// TYPE OBJECTS
// ============================================================================

/// Date type dealloc
fn date_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    PyObject_Free(obj);
}

/// Time type dealloc
fn time_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const time: *PyDateTime_Time = @ptrCast(@alignCast(obj));
    if (time.tzinfo) |tz| Py_DECREF(tz);
    PyObject_Free(obj);
}

/// DateTime type dealloc
fn datetime_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const dt: *PyDateTime_DateTime = @ptrCast(@alignCast(obj));
    if (dt.tzinfo) |tz| Py_DECREF(tz);
    PyObject_Free(obj);
}

/// Delta type dealloc
fn delta_dealloc(obj: *cpython.PyObject) callconv(.c) void {
    PyObject_Free(obj);
}

pub var PyDateTime_DateType: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "datetime.date",
    .tp_basicsize = @sizeOf(PyDateTime_Date),
    .tp_itemsize = 0,
    .tp_dealloc = date_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "date(year, month, day)",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = null,
    .tp_free = null,
    .tp_is_gc = null,
    .tp_bases = null,
    .tp_mro = null,
    .tp_cache = null,
    .tp_subclasses = null,
    .tp_weaklist = null,
    .tp_del = null,
    .tp_version_tag = 0,
    .tp_finalize = null,
    .tp_vectorcall = null,
    .tp_watched = 0,
    .tp_versions_used = 0,
};

pub var PyDateTime_TimeType: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "datetime.time",
    .tp_basicsize = @sizeOf(PyDateTime_Time),
    .tp_itemsize = 0,
    .tp_dealloc = time_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "time(hour=0, minute=0, second=0, microsecond=0, tzinfo=None)",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = null,
    .tp_free = null,
    .tp_is_gc = null,
    .tp_bases = null,
    .tp_mro = null,
    .tp_cache = null,
    .tp_subclasses = null,
    .tp_weaklist = null,
    .tp_del = null,
    .tp_version_tag = 0,
    .tp_finalize = null,
    .tp_vectorcall = null,
    .tp_watched = 0,
    .tp_versions_used = 0,
};

pub var PyDateTime_DateTimeType: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "datetime.datetime",
    .tp_basicsize = @sizeOf(PyDateTime_DateTime),
    .tp_itemsize = 0,
    .tp_dealloc = datetime_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "datetime(year, month, day, hour=0, minute=0, second=0, microsecond=0, tzinfo=None)",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = null,
    .tp_free = null,
    .tp_is_gc = null,
    .tp_bases = null,
    .tp_mro = null,
    .tp_cache = null,
    .tp_subclasses = null,
    .tp_weaklist = null,
    .tp_del = null,
    .tp_version_tag = 0,
    .tp_finalize = null,
    .tp_vectorcall = null,
    .tp_watched = 0,
    .tp_versions_used = 0,
};

pub var PyDateTime_DeltaType: cpython.PyTypeObject = .{
    .ob_base = .{
        .ob_base = .{ .ob_refcnt = 1000000, .ob_type = undefined },
        .ob_size = 0,
    },
    .tp_name = "datetime.timedelta",
    .tp_basicsize = @sizeOf(PyDateTime_Delta),
    .tp_itemsize = 0,
    .tp_dealloc = delta_dealloc,
    .tp_vectorcall_offset = 0,
    .tp_getattr = null,
    .tp_setattr = null,
    .tp_as_async = null,
    .tp_repr = null,
    .tp_as_number = null,
    .tp_as_sequence = null,
    .tp_as_mapping = null,
    .tp_hash = null,
    .tp_call = null,
    .tp_str = null,
    .tp_getattro = null,
    .tp_setattro = null,
    .tp_as_buffer = null,
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT | cpython.Py_TPFLAGS_BASETYPE,
    .tp_doc = "timedelta(days=0, seconds=0, microseconds=0)",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = null,
    .tp_dict = null,
    .tp_descr_get = null,
    .tp_descr_set = null,
    .tp_dictoffset = 0,
    .tp_init = null,
    .tp_alloc = null,
    .tp_new = null,
    .tp_free = null,
    .tp_is_gc = null,
    .tp_bases = null,
    .tp_mro = null,
    .tp_cache = null,
    .tp_subclasses = null,
    .tp_weaklist = null,
    .tp_del = null,
    .tp_version_tag = 0,
    .tp_finalize = null,
    .tp_vectorcall = null,
    .tp_watched = 0,
    .tp_versions_used = 0,
};

// ============================================================================
// TYPE CHECKING MACROS (as functions)
// ============================================================================

/// Check if object is a date (or subclass)
export fn PyDate_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    if (type_obj == &PyDateTime_DateType) return 1;
    if (type_obj == &PyDateTime_DateTimeType) return 1; // datetime is subclass of date
    // Check tp_name for cross-module compatibility
    if (type_obj.tp_name) |name| {
        const n = std.mem.span(name);
        if (std.mem.eql(u8, n, "datetime.date") or std.mem.eql(u8, n, "datetime.datetime")) return 1;
    }
    return 0;
}

/// Check if object is exactly a date
export fn PyDate_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyDateTime_DateType) 1 else 0;
}

/// Check if object is a datetime (or subclass)
export fn PyDateTime_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    if (type_obj == &PyDateTime_DateTimeType) return 1;
    if (type_obj.tp_name) |name| {
        const n = std.mem.span(name);
        if (std.mem.eql(u8, n, "datetime.datetime")) return 1;
    }
    return 0;
}

/// Check if object is exactly a datetime
export fn PyDateTime_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyDateTime_DateTimeType) 1 else 0;
}

/// Check if object is a time (or subclass)
export fn PyTime_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    if (type_obj == &PyDateTime_TimeType) return 1;
    if (type_obj.tp_name) |name| {
        const n = std.mem.span(name);
        if (std.mem.eql(u8, n, "datetime.time")) return 1;
    }
    return 0;
}

/// Check if object is exactly a time
export fn PyTime_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyDateTime_TimeType) 1 else 0;
}

/// Check if object is a timedelta (or subclass)
export fn PyDelta_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const type_obj = cpython.Py_TYPE(obj);
    if (type_obj == &PyDateTime_DeltaType) return 1;
    if (type_obj.tp_name) |name| {
        const n = std.mem.span(name);
        if (std.mem.eql(u8, n, "datetime.timedelta")) return 1;
    }
    return 0;
}

/// Check if object is exactly a timedelta
export fn PyDelta_CheckExact(obj: *cpython.PyObject) callconv(.c) c_int {
    return if (cpython.Py_TYPE(obj) == &PyDateTime_DeltaType) 1 else 0;
}

// ============================================================================
// CREATION FUNCTIONS
// ============================================================================

/// Create a new date object
/// CPython: PyObject* PyDate_FromDate(int year, int month, int day)
export fn PyDate_FromDate(year: c_int, month: c_int, day: c_int) callconv(.c) ?*cpython.PyObject {
    const mem = PyObject_Malloc(@sizeOf(PyDateTime_Date)) orelse return null;
    const date: *PyDateTime_Date = @ptrCast(@alignCast(mem));

    date.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyDateTime_DateType,
        },
        .hashcode = -1,
        .hastzinfo = 0,
        .data = undefined,
    };

    // Pack date into data array: year(2 bytes big-endian) + month(1) + day(1)
    const y: u16 = @intCast(year);
    date.data[0] = @truncate(y >> 8);
    date.data[1] = @truncate(y);
    date.data[2] = @intCast(month);
    date.data[3] = @intCast(day);

    return @ptrCast(&date.ob_base);
}

/// Create a new time object
/// CPython: PyObject* PyTime_FromTime(int hour, int minute, int second, int usecond)
export fn PyTime_FromTime(hour: c_int, minute: c_int, second: c_int, usecond: c_int) callconv(.c) ?*cpython.PyObject {
    return PyTime_FromTimeAndFold(hour, minute, second, usecond, 0);
}

/// Create a new time object with fold
/// CPython: PyObject* PyTime_FromTimeAndFold(int hour, int minute, int second, int usecond, int fold)
export fn PyTime_FromTimeAndFold(hour: c_int, minute: c_int, second: c_int, usecond: c_int, fold: c_int) callconv(.c) ?*cpython.PyObject {
    _ = fold;
    const mem = PyObject_Malloc(@sizeOf(PyDateTime_Time)) orelse return null;
    const time: *PyDateTime_Time = @ptrCast(@alignCast(mem));

    time.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyDateTime_TimeType,
        },
        .hashcode = -1,
        .hastzinfo = 0,
        .data = undefined,
        .tzinfo = null,
    };

    // Pack time: hour(1) + minute(1) + second(1) + microsecond(3 bytes big-endian)
    time.data[0] = @intCast(hour);
    time.data[1] = @intCast(minute);
    time.data[2] = @intCast(second);
    const us: u32 = @intCast(usecond);
    time.data[3] = @truncate(us >> 16);
    time.data[4] = @truncate(us >> 8);
    time.data[5] = @truncate(us);

    return @ptrCast(&time.ob_base);
}

/// Create a new datetime object
/// CPython: PyObject* PyDateTime_FromDateAndTime(int year, int month, int day, int hour, int minute, int second, int usecond)
export fn PyDateTime_FromDateAndTime(year: c_int, month: c_int, day: c_int, hour: c_int, minute: c_int, second: c_int, usecond: c_int) callconv(.c) ?*cpython.PyObject {
    return PyDateTime_FromDateAndTimeAndFold(year, month, day, hour, minute, second, usecond, 0);
}

/// Create a new datetime object with fold
/// CPython: PyObject* PyDateTime_FromDateAndTimeAndFold(...)
export fn PyDateTime_FromDateAndTimeAndFold(year: c_int, month: c_int, day: c_int, hour: c_int, minute: c_int, second: c_int, usecond: c_int, fold: c_int) callconv(.c) ?*cpython.PyObject {
    _ = fold;
    const mem = PyObject_Malloc(@sizeOf(PyDateTime_DateTime)) orelse return null;
    const dt: *PyDateTime_DateTime = @ptrCast(@alignCast(mem));

    dt.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyDateTime_DateTimeType,
        },
        .hashcode = -1,
        .hastzinfo = 0,
        .data = undefined,
        .tzinfo = null,
    };

    // Pack datetime: year(2) + month(1) + day(1) + hour(1) + minute(1) + second(1) + microsecond(3)
    const y: u16 = @intCast(year);
    dt.data[0] = @truncate(y >> 8);
    dt.data[1] = @truncate(y);
    dt.data[2] = @intCast(month);
    dt.data[3] = @intCast(day);
    dt.data[4] = @intCast(hour);
    dt.data[5] = @intCast(minute);
    dt.data[6] = @intCast(second);
    const us: u32 = @intCast(usecond);
    dt.data[7] = @truncate(us >> 16);
    dt.data[8] = @truncate(us >> 8);
    dt.data[9] = @truncate(us);

    return @ptrCast(&dt.ob_base);
}

/// Create a new timedelta object
/// CPython: PyObject* PyDelta_FromDSU(int days, int seconds, int useconds)
export fn PyDelta_FromDSU(days: c_int, seconds: c_int, useconds: c_int) callconv(.c) ?*cpython.PyObject {
    const mem = PyObject_Malloc(@sizeOf(PyDateTime_Delta)) orelse return null;
    const delta: *PyDateTime_Delta = @ptrCast(@alignCast(mem));

    // Normalize: microseconds should be 0..999999, seconds 0..86399
    var total_us: i64 = useconds;
    var total_sec: i64 = seconds + @divFloor(total_us, 1_000_000);
    total_us = @mod(total_us, 1_000_000);
    if (total_us < 0) {
        total_us += 1_000_000;
        total_sec -= 1;
    }

    var total_days: i64 = days + @divFloor(total_sec, 86400);
    total_sec = @mod(total_sec, 86400);
    if (total_sec < 0) {
        total_sec += 86400;
        total_days -= 1;
    }

    delta.* = .{
        .ob_base = .{
            .ob_refcnt = 1,
            .ob_type = &PyDateTime_DeltaType,
        },
        .hashcode = -1,
        .days = @intCast(total_days),
        .seconds = @intCast(total_sec),
        .microseconds = @intCast(total_us),
    };

    return @ptrCast(&delta.ob_base);
}

// ============================================================================
// ACCESSOR MACROS (as functions)
// ============================================================================

/// Get year from date/datetime
export fn PyDateTime_GET_YEAR(obj: *cpython.PyObject) callconv(.c) c_int {
    if (PyDateTime_Check(obj) != 0) {
        const dt: *PyDateTime_DateTime = @ptrCast(@alignCast(obj));
        return (@as(c_int, dt.data[0]) << 8) | @as(c_int, dt.data[1]);
    } else if (PyDate_Check(obj) != 0) {
        const date: *PyDateTime_Date = @ptrCast(@alignCast(obj));
        return (@as(c_int, date.data[0]) << 8) | @as(c_int, date.data[1]);
    }
    return 0;
}

/// Get month from date/datetime
export fn PyDateTime_GET_MONTH(obj: *cpython.PyObject) callconv(.c) c_int {
    if (PyDateTime_Check(obj) != 0) {
        const dt: *PyDateTime_DateTime = @ptrCast(@alignCast(obj));
        return dt.data[2];
    } else if (PyDate_Check(obj) != 0) {
        const date: *PyDateTime_Date = @ptrCast(@alignCast(obj));
        return date.data[2];
    }
    return 0;
}

/// Get day from date/datetime
export fn PyDateTime_GET_DAY(obj: *cpython.PyObject) callconv(.c) c_int {
    if (PyDateTime_Check(obj) != 0) {
        const dt: *PyDateTime_DateTime = @ptrCast(@alignCast(obj));
        return dt.data[3];
    } else if (PyDate_Check(obj) != 0) {
        const date: *PyDateTime_Date = @ptrCast(@alignCast(obj));
        return date.data[3];
    }
    return 0;
}

/// Get hour from time/datetime
export fn PyDateTime_DATE_GET_HOUR(obj: *cpython.PyObject) callconv(.c) c_int {
    if (PyDateTime_Check(obj) != 0) {
        const dt: *PyDateTime_DateTime = @ptrCast(@alignCast(obj));
        return dt.data[4];
    }
    return 0;
}

/// Get minute from time/datetime
export fn PyDateTime_DATE_GET_MINUTE(obj: *cpython.PyObject) callconv(.c) c_int {
    if (PyDateTime_Check(obj) != 0) {
        const dt: *PyDateTime_DateTime = @ptrCast(@alignCast(obj));
        return dt.data[5];
    }
    return 0;
}

/// Get second from time/datetime
export fn PyDateTime_DATE_GET_SECOND(obj: *cpython.PyObject) callconv(.c) c_int {
    if (PyDateTime_Check(obj) != 0) {
        const dt: *PyDateTime_DateTime = @ptrCast(@alignCast(obj));
        return dt.data[6];
    }
    return 0;
}

/// Get microsecond from time/datetime
export fn PyDateTime_DATE_GET_MICROSECOND(obj: *cpython.PyObject) callconv(.c) c_int {
    if (PyDateTime_Check(obj) != 0) {
        const dt: *PyDateTime_DateTime = @ptrCast(@alignCast(obj));
        return (@as(c_int, dt.data[7]) << 16) | (@as(c_int, dt.data[8]) << 8) | @as(c_int, dt.data[9]);
    }
    return 0;
}

/// Get hour from time object
export fn PyDateTime_TIME_GET_HOUR(obj: *cpython.PyObject) callconv(.c) c_int {
    if (PyTime_Check(obj) != 0) {
        const time: *PyDateTime_Time = @ptrCast(@alignCast(obj));
        return time.data[0];
    }
    return 0;
}

/// Get minute from time object
export fn PyDateTime_TIME_GET_MINUTE(obj: *cpython.PyObject) callconv(.c) c_int {
    if (PyTime_Check(obj) != 0) {
        const time: *PyDateTime_Time = @ptrCast(@alignCast(obj));
        return time.data[1];
    }
    return 0;
}

/// Get second from time object
export fn PyDateTime_TIME_GET_SECOND(obj: *cpython.PyObject) callconv(.c) c_int {
    if (PyTime_Check(obj) != 0) {
        const time: *PyDateTime_Time = @ptrCast(@alignCast(obj));
        return time.data[2];
    }
    return 0;
}

/// Get microsecond from time object
export fn PyDateTime_TIME_GET_MICROSECOND(obj: *cpython.PyObject) callconv(.c) c_int {
    if (PyTime_Check(obj) != 0) {
        const time: *PyDateTime_Time = @ptrCast(@alignCast(obj));
        return (@as(c_int, time.data[3]) << 16) | (@as(c_int, time.data[4]) << 8) | @as(c_int, time.data[5]);
    }
    return 0;
}

/// Get days from timedelta
export fn PyDateTime_DELTA_GET_DAYS(obj: *cpython.PyObject) callconv(.c) c_int {
    if (PyDelta_Check(obj) != 0) {
        const delta: *PyDateTime_Delta = @ptrCast(@alignCast(obj));
        return delta.days;
    }
    return 0;
}

/// Get seconds from timedelta
export fn PyDateTime_DELTA_GET_SECONDS(obj: *cpython.PyObject) callconv(.c) c_int {
    if (PyDelta_Check(obj) != 0) {
        const delta: *PyDateTime_Delta = @ptrCast(@alignCast(obj));
        return delta.seconds;
    }
    return 0;
}

/// Get microseconds from timedelta
export fn PyDateTime_DELTA_GET_MICROSECONDS(obj: *cpython.PyObject) callconv(.c) c_int {
    if (PyDelta_Check(obj) != 0) {
        const delta: *PyDateTime_Delta = @ptrCast(@alignCast(obj));
        return delta.microseconds;
    }
    return 0;
}

// ============================================================================
// DATETIME CAPSULE API
// ============================================================================

/// DateTime CAPI structure - used by datetime module's capsule
pub const PyDateTime_CAPI = extern struct {
    DateType: *cpython.PyTypeObject,
    DateTimeType: *cpython.PyTypeObject,
    TimeType: *cpython.PyTypeObject,
    DeltaType: *cpython.PyTypeObject,
    TZInfoType: *cpython.PyTypeObject,

    Date_FromDate: *const fn (c_int, c_int, c_int, *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject,
    DateTime_FromDateAndTime: *const fn (c_int, c_int, c_int, c_int, c_int, c_int, c_int, ?*cpython.PyObject, *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject,
    Time_FromTime: *const fn (c_int, c_int, c_int, c_int, ?*cpython.PyObject, *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject,
    Delta_FromDelta: *const fn (c_int, c_int, c_int, c_int, *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject,
    TimeZone_FromTimeZone: *const fn (*cpython.PyObject, ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject,

    DateTime_FromTimestamp: *const fn (*cpython.PyTypeObject, *cpython.PyObject, ?*cpython.PyObject) callconv(.c) ?*cpython.PyObject,
    Date_FromTimestamp: *const fn (*cpython.PyTypeObject, *cpython.PyObject) callconv(.c) ?*cpython.PyObject,

    DateTime_FromDateAndTimeAndFold: *const fn (c_int, c_int, c_int, c_int, c_int, c_int, c_int, ?*cpython.PyObject, c_int, *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject,
    Time_FromTimeAndFold: *const fn (c_int, c_int, c_int, c_int, ?*cpython.PyObject, c_int, *cpython.PyTypeObject) callconv(.c) ?*cpython.PyObject,
};

/// Import datetime C API
/// Returns pointer to PyDateTime_CAPI or null
export fn PyDateTime_IMPORT() callconv(.c) ?*PyDateTime_CAPI {
    // Return null - actual import would need to call PyCapsule_Import
    // This is typically done via PyDateTime_IMPORT macro in C
    return null;
}

// ============================================================================
// TIMESTAMP CONVERSION
// ============================================================================

/// Create datetime from POSIX timestamp
/// CPython: PyObject* PyDateTime_FromTimestamp(PyObject *args)
export fn PyDateTime_FromTimestamp(args: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const pytuple = @import("pyobject_tuple.zig");
    const pylong = @import("pyobject_long.zig");
    const pyfloat = @import("pyobject_float.zig");

    // Args is a tuple containing (timestamp,) or (timestamp, tz)
    if (pytuple.PyTuple_Check(args) == 0) return null;
    const size = pytuple.PyTuple_Size(args);
    if (size < 1) return null;

    const ts_obj = pytuple.PyTuple_GetItem(args, 0) orelse return null;

    // Get timestamp as float
    var timestamp: f64 = 0;
    if (pylong.PyLong_Check(ts_obj) != 0) {
        timestamp = @floatFromInt(pylong.PyLong_AsLong(ts_obj));
    } else if (pyfloat.PyFloat_Check(ts_obj) != 0) {
        timestamp = pyfloat.PyFloat_AsDouble(ts_obj);
    } else {
        return null;
    }

    // Convert POSIX timestamp to datetime components
    // timestamp is seconds since 1970-01-01 00:00:00 UTC
    const secs: i64 = @intFromFloat(timestamp);
    const frac = timestamp - @as(f64, @floatFromInt(secs));
    const usec: c_int = @intFromFloat(frac * 1_000_000);

    // Calculate date/time from seconds since epoch
    // Days since epoch (1970-01-01)
    var days = @divFloor(secs, 86400);
    var remaining = @mod(secs, 86400);
    if (remaining < 0) {
        remaining += 86400;
        days -= 1;
    }

    const hour: c_int = @intCast(@divFloor(remaining, 3600));
    remaining = @mod(remaining, 3600);
    const minute: c_int = @intCast(@divFloor(remaining, 60));
    const second: c_int = @intCast(@mod(remaining, 60));

    // Convert days since epoch to year/month/day
    var year: c_int = 1970;
    while (days >= daysInYear(year)) {
        days -= daysInYear(year);
        year += 1;
    }
    while (days < 0) {
        year -= 1;
        days += daysInYear(year);
    }

    var month: c_int = 1;
    const is_leap = isLeapYear(year);
    while (days >= daysInMonth(month, is_leap)) {
        days -= daysInMonth(month, is_leap);
        month += 1;
    }
    const day: c_int = @intCast(days + 1);

    return PyDateTime_FromDateAndTime(year, month, day, hour, minute, second, usec);
}

fn daysInYear(year: c_int) i64 {
    return if (isLeapYear(year)) 366 else 365;
}

fn isLeapYear(year: c_int) bool {
    return (@mod(year, 4) == 0 and @mod(year, 100) != 0) or @mod(year, 400) == 0;
}

fn daysInMonth(month: c_int, is_leap: bool) i64 {
    const days = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    if (month == 2 and is_leap) return 29;
    if (month < 1 or month > 12) return 0;
    return days[@intCast(month - 1)];
}

/// Create date from POSIX timestamp
/// CPython: PyObject* PyDate_FromTimestamp(PyObject *args)
export fn PyDate_FromTimestamp(args: *cpython.PyObject) callconv(.c) ?*cpython.PyObject {
    const pytuple = @import("pyobject_tuple.zig");
    const pylong = @import("pyobject_long.zig");
    const pyfloat = @import("pyobject_float.zig");

    // Args is a tuple containing (timestamp,)
    if (pytuple.PyTuple_Check(args) == 0) return null;
    const size = pytuple.PyTuple_Size(args);
    if (size < 1) return null;

    const ts_obj = pytuple.PyTuple_GetItem(args, 0) orelse return null;

    // Get timestamp as float
    var timestamp: f64 = 0;
    if (pylong.PyLong_Check(ts_obj) != 0) {
        timestamp = @floatFromInt(pylong.PyLong_AsLong(ts_obj));
    } else if (pyfloat.PyFloat_Check(ts_obj) != 0) {
        timestamp = pyfloat.PyFloat_AsDouble(ts_obj);
    } else {
        return null;
    }

    // Convert POSIX timestamp to date components
    const secs: i64 = @intFromFloat(timestamp);
    var days = @divFloor(secs, 86400);

    // Convert days since epoch to year/month/day
    var year: c_int = 1970;
    while (days >= daysInYear(year)) {
        days -= daysInYear(year);
        year += 1;
    }
    while (days < 0) {
        year -= 1;
        days += daysInYear(year);
    }

    var month: c_int = 1;
    const is_leap = isLeapYear(year);
    while (days >= daysInMonth(month, is_leap)) {
        days -= daysInMonth(month, is_leap);
        month += 1;
    }
    const day: c_int = @intCast(days + 1);

    return PyDate_FromDate(year, month, day);
}

// ============================================================================
// TESTS
// ============================================================================

test "PyDateTime types exist" {
    const testing = std.testing;
    try testing.expectEqualStrings("datetime.date", std.mem.span(PyDateTime_DateType.tp_name.?));
    try testing.expectEqualStrings("datetime.time", std.mem.span(PyDateTime_TimeType.tp_name.?));
    try testing.expectEqualStrings("datetime.datetime", std.mem.span(PyDateTime_DateTimeType.tp_name.?));
    try testing.expectEqualStrings("datetime.timedelta", std.mem.span(PyDateTime_DeltaType.tp_name.?));
}
