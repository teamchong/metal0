/// PyThread_* Functions
/// Thread management and synchronization primitives.

const std = @import("std");
const cpython = @import("../include/object.zig");
const pydict = @import("../objects/dictobject.zig");
const pyunicode = @import("../objects/unicodeobject.zig");

/// PyMutex - Compatible with CPython's PyMutex
pub const PyMutex = struct {
    mutex: std.Thread.Mutex = .{},
};

/// Thread-local storage implementation
const TLSStorage = struct {
    const MAX_KEYS = 128;
    var next_key: c_int = 1;
    var key_values: [MAX_KEYS]?*anyopaque = [_]?*anyopaque{null} ** MAX_KEYS;
    var key_valid: [MAX_KEYS]bool = [_]bool{false} ** MAX_KEYS;
    var mutex: std.Thread.Mutex = .{};
};

/// Thread tracking
const ThreadTracker = struct {
    var next_id: c_ulong = 2; // Main thread is 1
    var mutex: std.Thread.Mutex = .{};
};

/// Thread wrapper for proper C calling convention
const ThreadWrapper = struct {
    func: *const fn (?*anyopaque) callconv(.c) void,
    arg: ?*anyopaque,

    fn run(self: *ThreadWrapper) void {
        self.func(self.arg);
        std.heap.c_allocator.destroy(self);
    }
};

// --- Lock Functions ---

export fn PyThread_acquire_lock(lock: ?*anyopaque, waitflag: c_int) callconv(.c) c_int {
    if (lock) |ptr| {
        const pymutex: *PyMutex = @ptrCast(@alignCast(ptr));
        if (waitflag != 0) {
            pymutex.mutex.lock();
            return 1; // PY_LOCK_ACQUIRED
        } else {
            if (pymutex.mutex.tryLock()) {
                return 1;
            }
            return 0; // PY_LOCK_FAILURE
        }
    }
    return 0;
}

export fn PyThread_release_lock(lock: ?*anyopaque) callconv(.c) void {
    if (lock) |ptr| {
        const pymutex: *PyMutex = @ptrCast(@alignCast(ptr));
        pymutex.mutex.unlock();
    }
}

export fn PyThread_allocate_lock() callconv(.c) ?*anyopaque {
    const mutex = std.heap.c_allocator.create(PyMutex) catch return null;
    mutex.* = .{};
    return @ptrCast(mutex);
}

export fn PyThread_free_lock(lock: ?*anyopaque) callconv(.c) void {
    if (lock) |ptr| {
        const pymutex: *PyMutex = @ptrCast(@alignCast(ptr));
        std.heap.c_allocator.destroy(pymutex);
    }
}

export fn PyThread_acquire_lock_timed(lock: ?*anyopaque, microseconds: i64, intr_flag: c_int) callconv(.c) c_int {
    _ = intr_flag;
    if (lock) |ptr| {
        const pymutex: *PyMutex = @ptrCast(@alignCast(ptr));
        if (microseconds == 0) {
            if (pymutex.mutex.tryLock()) {
                return 1;
            }
            return 0;
        } else if (microseconds < 0) {
            pymutex.mutex.lock();
            return 1;
        } else {
            if (pymutex.mutex.tryLock()) {
                return 1;
            }
            pymutex.mutex.lock();
            return 1;
        }
    }
    return 0;
}

// --- TLS Functions ---

export fn PyThread_create_key() callconv(.c) c_int {
    TLSStorage.mutex.lock();
    defer TLSStorage.mutex.unlock();

    const key = TLSStorage.next_key;
    if (key < TLSStorage.MAX_KEYS) {
        TLSStorage.key_valid[@intCast(key)] = true;
        TLSStorage.next_key += 1;
        return key;
    }
    return -1;
}

export fn PyThread_delete_key(key: c_int) callconv(.c) void {
    if (key > 0 and key < TLSStorage.MAX_KEYS) {
        TLSStorage.mutex.lock();
        defer TLSStorage.mutex.unlock();
        TLSStorage.key_valid[@intCast(key)] = false;
        TLSStorage.key_values[@intCast(key)] = null;
    }
}

export fn PyThread_delete_key_value(key: c_int) callconv(.c) void {
    if (key > 0 and key < TLSStorage.MAX_KEYS) {
        TLSStorage.mutex.lock();
        defer TLSStorage.mutex.unlock();
        TLSStorage.key_values[@intCast(key)] = null;
    }
}

export fn PyThread_get_key_value(key: c_int) callconv(.c) ?*anyopaque {
    if (key > 0 and key < TLSStorage.MAX_KEYS) {
        TLSStorage.mutex.lock();
        defer TLSStorage.mutex.unlock();
        if (TLSStorage.key_valid[@intCast(key)]) {
            return TLSStorage.key_values[@intCast(key)];
        }
    }
    return null;
}

export fn PyThread_set_key_value(key: c_int, value: ?*anyopaque) callconv(.c) c_int {
    if (key > 0 and key < TLSStorage.MAX_KEYS) {
        TLSStorage.mutex.lock();
        defer TLSStorage.mutex.unlock();
        if (TLSStorage.key_valid[@intCast(key)]) {
            TLSStorage.key_values[@intCast(key)] = value;
            return 0;
        }
    }
    return -1;
}

export fn PyThread_ReInitTLS() callconv(.c) void {
    TLSStorage.mutex.lock();
    defer TLSStorage.mutex.unlock();
    for (0..TLSStorage.MAX_KEYS) |i| {
        TLSStorage.key_values[i] = null;
    }
}

// --- Thread Functions ---

export fn PyThread_exit_thread() callconv(.c) void {
    // Can't directly exit a thread from here
}

export fn PyThread_get_stacksize() callconv(.c) usize {
    return 1024 * 1024; // 1MB default
}

export fn PyThread_set_stacksize(size: usize) callconv(.c) c_int {
    _ = size;
    return 0;
}

export fn PyThread_get_thread_ident() callconv(.c) c_ulong {
    const current = std.Thread.getCurrentId();
    return @intCast(current);
}

export fn PyThread_get_thread_native_id() callconv(.c) c_ulong {
    return PyThread_get_thread_ident();
}

export fn PyThread_GetInfo() callconv(.c) ?*cpython.PyObject {
    const info = pydict.PyDict_New() orelse return null;
    _ = pydict.PyDict_SetItemString(info, "name", pyunicode.PyUnicode_FromString("pthread") orelse return info);
    _ = pydict.PyDict_SetItemString(info, "lock", pyunicode.PyUnicode_FromString("mutex") orelse return info);
    _ = pydict.PyDict_SetItemString(info, "version", pyunicode.PyUnicode_FromString("metal0") orelse return info);
    return info;
}

export fn PyThread_init_thread() callconv(.c) void {}

export fn PyThread_start_new_thread(func: ?*const fn (?*anyopaque) callconv(.c) void, arg: ?*anyopaque) callconv(.c) c_ulong {
    if (func) |f| {
        const wrapper = std.heap.c_allocator.create(ThreadWrapper) catch return 0;
        wrapper.* = .{ .func = f, .arg = arg };

        const thread = std.Thread.spawn(.{}, ThreadWrapper.run, .{wrapper}) catch {
            std.heap.c_allocator.destroy(wrapper);
            return 0;
        };
        thread.detach();

        ThreadTracker.mutex.lock();
        defer ThreadTracker.mutex.unlock();
        const id = ThreadTracker.next_id;
        ThreadTracker.next_id += 1;
        return id;
    }
    return 0;
}

// --- Memory Tracking ---

export fn PyTraceMalloc_Track(domain: c_uint, ptr: usize, size: usize) callconv(.c) c_int {
    _ = domain;
    _ = ptr;
    _ = size;
    return 0;
}

export fn PyTraceMalloc_Untrack(domain: c_uint, ptr: usize) callconv(.c) c_int {
    _ = domain;
    _ = ptr;
    return 0;
}

// --- String Utilities ---

export fn PyOS_strtol(str: [*:0]const u8, ptr: ?*[*:0]u8, base: c_int) callconv(.c) c_long {
    return std.c.strtol(str, @ptrCast(ptr), base);
}

export fn PyOS_strtoul(str: [*:0]const u8, ptr: ?*[*:0]u8, base: c_int) callconv(.c) c_ulong {
    return std.c.strtoul(str, @ptrCast(ptr), base);
}
