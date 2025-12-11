/// Pending Call System for ceval
/// Mirrors part of cpython/Python/ceval.c
const std = @import("std");

/// Maximum pending calls per interpreter
pub const PENDING_CALLS_ARRAY_SIZE = 32;

/// Maximum pending calls to process per pass
pub const MAX_PENDING_CALLS_LOOP = 100;

/// Pending call function signature
pub const PendingCallFunc = *const fn (arg: ?*anyopaque) callconv(.C) c_int;

/// Single pending call entry
const PendingCall = struct {
    func: ?PendingCallFunc = null,
    arg: ?*anyopaque = null,
};

/// Result codes for AddPendingCall
pub const AddPendingResult = enum(c_int) {
    success = 0,
    full = -1,
};

/// Pending calls state for an interpreter
pub const PendingCalls = struct {
    mutex: std.Thread.Mutex = .{},
    npending: i32 = 0,
    max: i32 = PENDING_CALLS_ARRAY_SIZE,
    maxloop: i32 = MAX_PENDING_CALLS_LOOP,
    calls: [PENDING_CALLS_ARRAY_SIZE]PendingCall = [_]PendingCall{.{}} ** PENDING_CALLS_ARRAY_SIZE,
    first: i32 = 0,
    next: i32 = 0,
    handling_thread: ?std.Thread.Id = null,

    pub fn init() PendingCalls {
        return .{};
    }

    pub fn add(self: *PendingCalls, func: PendingCallFunc, arg: ?*anyopaque) AddPendingResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.npending >= self.max) {
            return .full;
        }

        self.calls[@intCast(self.next)] = .{
            .func = func,
            .arg = arg,
        };
        self.next = @mod(self.next + 1, self.max);
        self.npending += 1;

        return .success;
    }

    pub fn makeCalls(self: *PendingCalls) c_int {
        const current_thread = std.Thread.getCurrentId();

        self.mutex.lock();
        if (self.handling_thread != null) {
            self.mutex.unlock();
            return 0;
        }
        self.handling_thread = current_thread;
        self.mutex.unlock();

        defer {
            self.mutex.lock();
            self.handling_thread = null;
            self.mutex.unlock();
        }

        var count: i32 = 0;
        const maxloop = self.maxloop;

        while (count < maxloop) {
            self.mutex.lock();
            if (self.npending == 0) {
                self.mutex.unlock();
                break;
            }

            const call = self.calls[@intCast(self.first)];
            self.first = @mod(self.first + 1, self.max);
            self.npending -= 1;
            self.mutex.unlock();

            if (call.func) |func| {
                const result = func(call.arg);
                if (result != 0) {
                    return -1;
                }
            }

            count += 1;
        }

        return 0;
    }

    pub fn hasPending(self: *PendingCalls) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.npending > 0;
    }
};

/// Global pending calls for main thread
var pending_mainthread: PendingCalls = PendingCalls.init();

/// Add a pending call (main thread)
pub fn addPendingCall(func: PendingCallFunc, arg: ?*anyopaque) c_int {
    return @intFromEnum(pending_mainthread.add(func, arg));
}

/// Process pending calls (main thread)
pub fn makePendingCalls() c_int {
    return pending_mainthread.makeCalls();
}
