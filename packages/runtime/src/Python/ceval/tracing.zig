/// Tracing and Profiling hooks for ceval
/// Mirrors part of cpython/Python/ceval.c
const std = @import("std");

/// Trace event types
pub const TraceEvent = enum(c_int) {
    call = 0,
    exception = 1,
    line = 2,
    return_ = 3,
    c_call = 4,
    c_exception = 5,
    c_return = 6,
    opcode = 7,
};

/// Trace function signature
pub const TraceFunc = *const fn (
    obj: ?*anyopaque,
    frame: ?*anyopaque,
    what: c_int,
    arg: ?*anyopaque,
) callconv(.C) c_int;

/// Global trace function
var trace_func: ?TraceFunc = null;
var trace_arg: ?*anyopaque = null;

/// Global profile function
var profile_func: ?TraceFunc = null;
var profile_arg: ?*anyopaque = null;

/// Set trace function
pub fn setTrace(func: ?TraceFunc, arg: ?*anyopaque) void {
    trace_func = func;
    trace_arg = arg;
}

/// Get current trace function
pub fn getTrace() ?TraceFunc {
    return trace_func;
}

/// Set profile function
pub fn setProfile(func: ?TraceFunc, arg: ?*anyopaque) void {
    profile_func = func;
    profile_arg = arg;
}

/// Get current profile function
pub fn getProfile() ?TraceFunc {
    return profile_func;
}

/// Call trace function if set
pub fn callTrace(frame: ?*anyopaque, event: TraceEvent, arg: ?*anyopaque) c_int {
    if (trace_func) |func| {
        return func(trace_arg, frame, @intFromEnum(event), arg);
    }
    return 0;
}

/// Call profile function if set
pub fn callProfile(frame: ?*anyopaque, event: TraceEvent, arg: ?*anyopaque) c_int {
    if (profile_func) |func| {
        return func(profile_arg, frame, @intFromEnum(event), arg);
    }
    return 0;
}

/// Enable tracing for all threads
pub fn setTraceAllThreads(func: ?TraceFunc, arg: ?*anyopaque) void {
    setTrace(func, arg);
}

/// Enable profiling for all threads
pub fn setProfileAllThreads(func: ?TraceFunc, arg: ?*anyopaque) void {
    setProfile(func, arg);
}
