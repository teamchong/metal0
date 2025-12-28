/// Py_* Core Functions
/// Core Python C API functions including pending calls, type checking, etc.

const std = @import("std");
const cpython = @import("../include/object.zig");
const pybool = @import("../objects/boolobject.zig");
const pynone = @import("../objects/noneobject.zig");
const pylong = @import("../objects/longobject.zig");
const pyfloat = @import("../objects/floatobject.zig");
const pyunicode = @import("../objects/unicodeobject.zig");
const pytuple = @import("../objects/tupleobject.zig");
const traits = @import("../objects/typetraits.zig");

// Pending call queue for main thread execution
const PendingCall = struct {
    func: *const fn (?*anyopaque) callconv(.c) c_int,
    arg: ?*anyopaque,
};

const PendingCallQueue = struct {
    const MAX_PENDING = 32;
    var queue: [MAX_PENDING]PendingCall = undefined;
    var count: usize = 0;
    var mutex: std.Thread.Mutex = .{};
};

pub export fn Py_AddPendingCall(func: ?*const fn (?*anyopaque) callconv(.c) c_int, arg: ?*anyopaque) callconv(.c) c_int {
    if (func) |f| {
        PendingCallQueue.mutex.lock();
        defer PendingCallQueue.mutex.unlock();

        if (PendingCallQueue.count >= PendingCallQueue.MAX_PENDING) {
            return -1; // Queue full
        }

        PendingCallQueue.queue[PendingCallQueue.count] = .{
            .func = f,
            .arg = arg,
        };
        PendingCallQueue.count += 1;
        return 0;
    }
    return -1;
}

pub export fn Py_BytesMain(argc: c_int, argv: [*][*:0]u8) callconv(.c) c_int {
    _ = argc;
    _ = argv;
    return 0;
}

pub export fn Py_Dealloc(obj: *cpython.PyObject) callconv(.c) void {
    const tp = cpython.Py_TYPE(obj);
    if (tp.tp_dealloc) |dealloc| {
        dealloc(obj);
    }
}

pub export fn Py_DecodeLocale(arg: [*:0]const u8, size: ?*usize) callconv(.c) ?[*:0]u8 {
    _ = size;
    // Return copy of input (simplified - real impl handles locale)
    const len = std.mem.len(arg);
    const result = std.heap.c_allocator.allocSentinel(u8, len, 0) catch return null;
    @memcpy(result[0..len], arg[0..len]);
    return result.ptr;
}

pub export fn Py_EncodeLocale(text: [*:0]const u8, error_pos: ?*usize) callconv(.c) ?[*:0]u8 {
    _ = error_pos;
    const len = std.mem.len(text);
    const result = std.heap.c_allocator.allocSentinel(u8, len, 0) catch return null;
    @memcpy(result[0..len], text[0..len]);
    return result.ptr;
}

pub export fn Py_GetConstant(constant_id: c_int) callconv(.c) ?*cpython.PyObject {
    return switch (constant_id) {
        0 => pynone.Py_None(), // Py_CONSTANT_NONE
        1 => @ptrCast(&pybool._Py_FalseStruct), // Py_CONSTANT_FALSE
        2 => @ptrCast(&pybool._Py_TrueStruct), // Py_CONSTANT_TRUE
        else => null,
    };
}

pub export fn Py_GetConstantBorrowed(constant_id: c_int) callconv(.c) ?*cpython.PyObject {
    return Py_GetConstant(constant_id);
}

/// Thread-local storage for Python thread state
const ThreadLocalState = struct {
    var tls_value: ?*anyopaque = null;
    var mutex: std.Thread.Mutex = .{};
};

pub export fn Py_GetThreadLocal_Addr() callconv(.c) ?*anyopaque {
    ThreadLocalState.mutex.lock();
    defer ThreadLocalState.mutex.unlock();
    return &ThreadLocalState.tls_value;
}

pub export fn Py_Is(x: *cpython.PyObject, y: *cpython.PyObject) callconv(.c) c_int {
    return if (x == y) 1 else 0;
}

pub export fn Py_IsFinalizing() callconv(.c) c_int {
    return 0; // Not finalizing
}

pub export fn Py_Main(argc: c_int, argv: [*][*:0]u8) callconv(.c) c_int {
    _ = argc;
    _ = argv;
    return 0;
}

pub export fn Py_MakePendingCalls() callconv(.c) c_int {
    // Execute all pending calls
    PendingCallQueue.mutex.lock();
    const count = PendingCallQueue.count;
    var calls: [PendingCallQueue.MAX_PENDING]PendingCall = undefined;
    @memcpy(calls[0..count], PendingCallQueue.queue[0..count]);
    PendingCallQueue.count = 0;
    PendingCallQueue.mutex.unlock();

    // Execute calls outside the lock
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (calls[i].func(calls[i].arg) != 0) {
            return -1; // Error in callback
        }
    }
    return 0;
}

// Repr recursion tracking (prevent infinite loops in repr)
const ReprTracker = struct {
    const MAX_TRACKED = 64;
    var objects: [MAX_TRACKED]?*cpython.PyObject = [_]?*cpython.PyObject{null} ** MAX_TRACKED;
    var mutex: std.Thread.Mutex = .{};

    fn find(obj: *cpython.PyObject) ?usize {
        for (0..MAX_TRACKED) |i| {
            if (objects[i] == obj) return i;
        }
        return null;
    }

    fn findEmpty() ?usize {
        for (0..MAX_TRACKED) |i| {
            if (objects[i] == null) return i;
        }
        return null;
    }
};

pub export fn Py_ReprEnter(obj: *cpython.PyObject) callconv(.c) c_int {
    ReprTracker.mutex.lock();
    defer ReprTracker.mutex.unlock();

    // Check if already in repr
    if (ReprTracker.find(obj)) |_| {
        return 1; // Already being repr'd (infinite loop)
    }

    // Add to tracking
    if (ReprTracker.findEmpty()) |idx| {
        ReprTracker.objects[idx] = obj;
        return 0; // OK
    }

    return 0; // Tracking full, allow anyway
}

pub export fn Py_ReprLeave(obj: *cpython.PyObject) callconv(.c) void {
    ReprTracker.mutex.lock();
    defer ReprTracker.mutex.unlock();

    if (ReprTracker.find(obj)) |idx| {
        ReprTracker.objects[idx] = null;
    }
}

pub export fn Py_SetRefcnt(obj: *cpython.PyObject, refcnt: isize) callconv(.c) void {
    obj.ob_refcnt = refcnt;
}

pub export fn Py_REFCNT(obj: *cpython.PyObject) callconv(.c) isize {
    return obj.ob_refcnt;
}

pub export fn Py_TYPE(obj: *cpython.PyObject) callconv(.c) *cpython.PyTypeObject {
    return cpython.Py_TYPE(obj);
}

pub export fn Py_VaBuildValue(format: [*:0]const u8, va: std.builtin.VaList) callconv(.c) ?*cpython.PyObject {
    const fmt = std.mem.span(format);
    if (fmt.len == 0) return pynone.Py_None();

    var va_copy = va;

    // Handle single format character
    if (fmt.len == 1) {
        switch (fmt[0]) {
            'i' => {
                const val = @cVaArg(&va_copy, c_int);
                return pylong.PyLong_FromLong(val);
            },
            'l' => {
                const val = @cVaArg(&va_copy, c_long);
                return pylong.PyLong_FromLong(val);
            },
            'L' => {
                const val = @cVaArg(&va_copy, c_longlong);
                return pylong.PyLong_FromLongLong(val);
            },
            'd', 'f' => {
                const val = @cVaArg(&va_copy, f64);
                return pyfloat.PyFloat_FromDouble(val);
            },
            's' => {
                const val = @cVaArg(&va_copy, [*:0]const u8);
                return pyunicode.PyUnicode_FromString(val);
            },
            'O', 'N' => {
                const val = @cVaArg(&va_copy, *cpython.PyObject);
                if (fmt[0] == 'O') traits.incref(val);
                return val;
            },
            else => return pynone.Py_None(),
        }
    }

    // Handle tuple format (a, b, ...)
    if (fmt[0] == '(' and fmt[fmt.len - 1] == ')') {
        // Count items
        var count: isize = 0;
        var i: usize = 1;
        while (i < fmt.len - 1) : (i += 1) {
            switch (fmt[i]) {
                'i', 'l', 'L', 'd', 'f', 's', 'O', 'N' => count += 1,
                else => {},
            }
        }
        const tuple = pytuple.PyTuple_New(count) orelse return null;
        var idx: isize = 0;
        i = 1;
        while (i < fmt.len - 1 and idx < count) : (i += 1) {
            switch (fmt[i]) {
                'i' => {
                    const val = @cVaArg(&va_copy, c_int);
                    _ = pytuple.PyTuple_SetItem(tuple, idx, pylong.PyLong_FromLong(val) orelse return null);
                    idx += 1;
                },
                'l' => {
                    const val = @cVaArg(&va_copy, c_long);
                    _ = pytuple.PyTuple_SetItem(tuple, idx, pylong.PyLong_FromLong(val) orelse return null);
                    idx += 1;
                },
                'd', 'f' => {
                    const val = @cVaArg(&va_copy, f64);
                    _ = pytuple.PyTuple_SetItem(tuple, idx, pyfloat.PyFloat_FromDouble(val) orelse return null);
                    idx += 1;
                },
                's' => {
                    const val = @cVaArg(&va_copy, [*:0]const u8);
                    _ = pytuple.PyTuple_SetItem(tuple, idx, pyunicode.PyUnicode_FromString(val) orelse return null);
                    idx += 1;
                },
                'O', 'N' => {
                    const val = @cVaArg(&va_copy, *cpython.PyObject);
                    if (fmt[i] == 'O') traits.incref(val);
                    _ = pytuple.PyTuple_SetItem(tuple, idx, val);
                    idx += 1;
                },
                else => {},
            }
        }
        return tuple;
    }

    return pynone.Py_None();
}

// --- PyAIter/PyABIInfo ---

pub export fn PyAIter_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    const tp = cpython.Py_TYPE(obj);
    return if (tp.tp_as_async != null and tp.tp_as_async.?.am_anext != null) 1 else 0;
}

pub export fn PyABIInfo_Check(obj: *cpython.PyObject) callconv(.c) c_int {
    _ = obj;
    return 0;
}
