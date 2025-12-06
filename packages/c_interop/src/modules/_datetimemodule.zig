/// _datetime Module - DateTime C Implementation
///
/// Implements CPython's Modules/_datetimemodule.c
/// Provides date, time, datetime, timedelta types
///
/// Reference: cpython/Modules/_datetimemodule.c

const std = @import("std");
const cpython = @import("../include/object.zig");

const allocator = std.heap.c_allocator;

// ============================================================================
// CONSTANTS
// ============================================================================

pub const MINYEAR = 1;
pub const MAXYEAR = 9999;

/// Days in each month (non-leap year)
const days_in_month = [_]u8{ 0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };

/// Days before each month (cumulative)
const days_before_month = [_]u16{ 0, 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 };

// ============================================================================
// DATE OBJECT
// ============================================================================

/// PyDateTime_Date - date object
pub const PyDateTime_Date = extern struct {
    ob_base: cpython.PyObject,
    hashcode: isize, // Cached hash
    data: [4]u8, // year (2 bytes), month, day
};

/// Create a new date object
pub export fn PyDate_FromDate(year: c_int, month: c_int, day: c_int) ?*cpython.PyObject {
    if (year < MINYEAR or year > MAXYEAR) return null;
    if (month < 1 or month > 12) return null;
    if (day < 1 or day > daysInMonth(year, month)) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyDateTime_Date), @sizeOf(PyDateTime_Date)) catch return null;
    const date: *PyDateTime_Date = @ptrCast(@alignCast(mem.ptr));

    date.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyDateTime_DateType },
        .hashcode = -1,
        .data = .{
            @intCast((year >> 8) & 0xFF),
            @intCast(year & 0xFF),
            @intCast(month),
            @intCast(day),
        },
    };

    return @ptrCast(date);
}

/// Get year from date
pub export fn PyDateTime_GET_YEAR(op: ?*cpython.PyObject) c_int {
    if (op == null) return 0;
    const date: *PyDateTime_Date = @ptrCast(@alignCast(op.?));
    return (@as(c_int, date.data[0]) << 8) | @as(c_int, date.data[1]);
}

/// Get month from date
pub export fn PyDateTime_GET_MONTH(op: ?*cpython.PyObject) c_int {
    if (op == null) return 0;
    const date: *PyDateTime_Date = @ptrCast(@alignCast(op.?));
    return @as(c_int, date.data[2]);
}

/// Get day from date
pub export fn PyDateTime_GET_DAY(op: ?*cpython.PyObject) c_int {
    if (op == null) return 0;
    const date: *PyDateTime_Date = @ptrCast(@alignCast(op.?));
    return @as(c_int, date.data[3]);
}

// ============================================================================
// TIME OBJECT
// ============================================================================

/// PyDateTime_Time - time object
pub const PyDateTime_Time = extern struct {
    ob_base: cpython.PyObject,
    hashcode: isize,
    tzinfo: ?*cpython.PyObject,
    data: [6]u8, // hour, minute, second, microsecond (3 bytes)
    fold: u8,
};

/// Create a new time object
pub export fn PyTime_FromTime(hour: c_int, minute: c_int, second: c_int, usec: c_int) ?*cpython.PyObject {
    if (hour < 0 or hour > 23) return null;
    if (minute < 0 or minute > 59) return null;
    if (second < 0 or second > 59) return null;
    if (usec < 0 or usec > 999999) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyDateTime_Time), @sizeOf(PyDateTime_Time)) catch return null;
    const time: *PyDateTime_Time = @ptrCast(@alignCast(mem.ptr));

    time.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyDateTime_TimeType },
        .hashcode = -1,
        .tzinfo = null,
        .data = .{
            @intCast(hour),
            @intCast(minute),
            @intCast(second),
            @intCast((usec >> 16) & 0xFF),
            @intCast((usec >> 8) & 0xFF),
            @intCast(usec & 0xFF),
        },
        .fold = 0,
    };

    return @ptrCast(time);
}

// ============================================================================
// DATETIME OBJECT
// ============================================================================

/// PyDateTime_DateTime - datetime object
pub const PyDateTime_DateTime = extern struct {
    ob_base: cpython.PyObject,
    hashcode: isize,
    tzinfo: ?*cpython.PyObject,
    data: [10]u8, // year(2), month, day, hour, minute, second, microsecond(3)
    fold: u8,
};

/// Create a new datetime object
pub export fn PyDateTime_FromDateAndTime(year: c_int, month: c_int, day: c_int, hour: c_int, minute: c_int, second: c_int, usec: c_int) ?*cpython.PyObject {
    if (year < MINYEAR or year > MAXYEAR) return null;
    if (month < 1 or month > 12) return null;
    if (day < 1 or day > daysInMonth(year, month)) return null;
    if (hour < 0 or hour > 23) return null;
    if (minute < 0 or minute > 59) return null;
    if (second < 0 or second > 59) return null;
    if (usec < 0 or usec > 999999) return null;

    const mem = allocator.alignedAlloc(u8, @alignOf(PyDateTime_DateTime), @sizeOf(PyDateTime_DateTime)) catch return null;
    const dt: *PyDateTime_DateTime = @ptrCast(@alignCast(mem.ptr));

    dt.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyDateTime_DateTimeType },
        .hashcode = -1,
        .tzinfo = null,
        .data = .{
            @intCast((year >> 8) & 0xFF),
            @intCast(year & 0xFF),
            @intCast(month),
            @intCast(day),
            @intCast(hour),
            @intCast(minute),
            @intCast(second),
            @intCast((usec >> 16) & 0xFF),
            @intCast((usec >> 8) & 0xFF),
            @intCast(usec & 0xFF),
        },
        .fold = 0,
    };

    return @ptrCast(dt);
}

// ============================================================================
// TIMEDELTA OBJECT
// ============================================================================

/// PyDateTime_Delta - timedelta object
pub const PyDateTime_Delta = extern struct {
    ob_base: cpython.PyObject,
    hashcode: isize,
    days: c_int,
    seconds: c_int,
    microseconds: c_int,
};

/// Create a new timedelta object
pub export fn PyDelta_FromDSU(days: c_int, seconds: c_int, usec: c_int) ?*cpython.PyObject {
    const mem = allocator.alignedAlloc(u8, @alignOf(PyDateTime_Delta), @sizeOf(PyDateTime_Delta)) catch return null;
    const delta: *PyDateTime_Delta = @ptrCast(@alignCast(mem.ptr));

    // Normalize values
    var d = days;
    var s = seconds;
    var us = usec;

    // Normalize microseconds
    if (us >= 1000000 or us < 0) {
        const div = @divFloor(us, 1000000);
        s += div;
        us -= div * 1000000;
        if (us < 0) {
            us += 1000000;
            s -= 1;
        }
    }

    // Normalize seconds
    if (s >= 86400 or s < 0) {
        const div = @divFloor(s, 86400);
        d += div;
        s -= div * 86400;
        if (s < 0) {
            s += 86400;
            d -= 1;
        }
    }

    delta.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = &PyDateTime_DeltaType },
        .hashcode = -1,
        .days = d,
        .seconds = s,
        .microseconds = us,
    };

    return @ptrCast(delta);
}

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

fn isLeapYear(year: c_int) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

fn daysInMonth(year: c_int, month: c_int) c_int {
    if (month == 2 and isLeapYear(year)) {
        return 29;
    }
    return @as(c_int, days_in_month[@intCast(month)]);
}

// ============================================================================
// TYPE OBJECTS
// ============================================================================

pub export var PyDateTime_DateType: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "datetime.date",
    .tp_basicsize = @sizeOf(PyDateTime_Date),
    .tp_itemsize = 0,
    .tp_dealloc = null,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
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
};

pub export var PyDateTime_TimeType: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "datetime.time",
    .tp_basicsize = @sizeOf(PyDateTime_Time),
    .tp_itemsize = 0,
    .tp_dealloc = null,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = "time(hour, minute, second, microsecond)",
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
};

pub export var PyDateTime_DateTimeType: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "datetime.datetime",
    .tp_basicsize = @sizeOf(PyDateTime_DateTime),
    .tp_itemsize = 0,
    .tp_dealloc = null,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = "datetime(year, month, day, hour, minute, second, microsecond)",
    .tp_traverse = null,
    .tp_clear = null,
    .tp_richcompare = null,
    .tp_weaklistoffset = 0,
    .tp_iter = null,
    .tp_iternext = null,
    .tp_methods = null,
    .tp_members = null,
    .tp_getset = null,
    .tp_base = &PyDateTime_DateType,
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
};

pub export var PyDateTime_DeltaType: cpython.PyTypeObject = .{
    .ob_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = undefined }, .ob_size = 0 },
    .tp_name = "datetime.timedelta",
    .tp_basicsize = @sizeOf(PyDateTime_Delta),
    .tp_itemsize = 0,
    .tp_dealloc = null,
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
    .tp_flags = cpython.Py_TPFLAGS_DEFAULT,
    .tp_doc = "Difference between two datetime values.",
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
};

// ============================================================================
// MODULE DEFINITION
// ============================================================================

pub export var _datetimemodule: cpython.PyModuleDef = .{
    .m_base = .{ .ob_base = .{ .ob_refcnt = 1, .ob_type = null }, .m_init = null, .m_index = 0, .m_copy = null },
    .m_name = "_datetime",
    .m_doc = "Fast implementation of datetime types.",
    .m_size = -1,
    .m_methods = null,
    .m_slots = null,
    .m_traverse = null,
    .m_clear = null,
    .m_free = null,
};

pub export fn PyInit__datetime() ?*cpython.PyObject {
    const module_mod = @import("../objects/moduleobject.zig");
    const module = module_mod.PyModule_Create(&_datetimemodule);
    if (module == null) return null;

    _ = module_mod.PyModule_AddObject(module, "date", @ptrCast(&PyDateTime_DateType));
    _ = module_mod.PyModule_AddObject(module, "time", @ptrCast(&PyDateTime_TimeType));
    _ = module_mod.PyModule_AddObject(module, "datetime", @ptrCast(&PyDateTime_DateTimeType));
    _ = module_mod.PyModule_AddObject(module, "timedelta", @ptrCast(&PyDateTime_DeltaType));

    return module;
}
