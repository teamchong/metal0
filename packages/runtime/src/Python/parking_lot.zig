/// parking_lot - Parking Lot for Thread Synchronization
/// Mirrors cpython/Python/parking_lot.c
///
/// This module implements a parking lot for efficient thread synchronization:
/// - Wait/wake primitives for thread parking
/// - Hash-based thread registration
/// - Support for timed waits
/// - Integration with Python's GIL and free-threading

const std = @import("std");
const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Value;

// ============================================================================
// Constants
// ============================================================================

/// Number of buckets in the parking lot hash table
const BUCKET_COUNT: usize = 251; // Prime number for better distribution

/// Maximum threads that can wait on a single address
const MAX_WAITERS_PER_ADDRESS: usize = 1024;

/// Default timeout for timed waits (infinite)
pub const WAIT_FOREVER: i64 = -1;

// ============================================================================
// Wait Result
// ============================================================================

/// Result of a wait operation
pub const WaitResult = enum {
    ok, // Woken normally
    timeout, // Timed out
    interrupted, // Interrupted by signal
    invalid, // Invalid address or state
};

// ============================================================================
// Parked Thread
// ============================================================================

/// State of a parked thread
const ParkedThread = struct {
    /// Address being waited on
    address: usize,
    /// Thread-local event for waking
    wakeup: std.Thread.ResetEvent,
    /// Next thread in same bucket
    next: ?*ParkedThread,
    /// Previous thread in same bucket
    prev: ?*ParkedThread,
    /// Whether this thread has been unparked
    unparked: Atomic(bool),

    const Self = @This();

    fn init(address: usize) Self {
        return .{
            .address = address,
            .wakeup = .{},
            .next = null,
            .prev = null,
            .unparked = Atomic(bool).init(false),
        };
    }
};

// ============================================================================
// Bucket
// ============================================================================

/// Hash bucket for parked threads
const Bucket = struct {
    /// Head of the linked list
    head: ?*ParkedThread,
    /// Lock for this bucket
    mutex: std.Thread.Mutex,
    /// Number of threads in this bucket
    count: usize,

    const Self = @This();

    fn init() Self {
        return .{
            .head = null,
            .mutex = .{},
            .count = 0,
        };
    }

    fn addThread(self: *Self, thread: *ParkedThread) void {
        thread.next = self.head;
        thread.prev = null;
        if (self.head) |head| {
            head.prev = thread;
        }
        self.head = thread;
        self.count += 1;
    }

    fn removeThread(self: *Self, thread: *ParkedThread) void {
        if (thread.prev) |prev| {
            prev.next = thread.next;
        } else {
            self.head = thread.next;
        }
        if (thread.next) |next| {
            next.prev = thread.prev;
        }
        self.count -= 1;
    }
};

// ============================================================================
// Parking Lot
// ============================================================================

/// Global parking lot for thread synchronization
pub const ParkingLot = struct {
    buckets: [BUCKET_COUNT]Bucket,

    const Self = @This();

    pub fn init() Self {
        var buckets: [BUCKET_COUNT]Bucket = undefined;
        for (&buckets) |*bucket| {
            bucket.* = Bucket.init();
        }
        return .{ .buckets = buckets };
    }

    /// Get bucket for an address
    fn getBucket(self: *Self, address: usize) *Bucket {
        const index = address % BUCKET_COUNT;
        return &self.buckets[index];
    }

    /// Park the current thread until woken or timeout
    pub fn park(self: *Self, address: *const anyopaque, timeout_ns: i64) WaitResult {
        const addr = @intFromPtr(address);
        var parked = ParkedThread.init(addr);

        const bucket = self.getBucket(addr);

        // Add to bucket
        bucket.mutex.lock();
        bucket.addThread(&parked);
        bucket.mutex.unlock();

        // Wait for wakeup
        const result = if (timeout_ns == WAIT_FOREVER) blk: {
            parked.wakeup.wait();
            break :blk WaitResult.ok;
        } else if (timeout_ns <= 0) blk: {
            break :blk WaitResult.timeout;
        } else blk: {
            const timeout_ns_u64: u64 = @intCast(timeout_ns);
            parked.wakeup.timedWait(timeout_ns_u64) catch |err| {
                if (err == error.Timeout) {
                    break :blk WaitResult.timeout;
                }
            };
            break :blk WaitResult.ok;
        };

        // Remove from bucket
        bucket.mutex.lock();
        if (!parked.unparked.load(.acquire)) {
            bucket.removeThread(&parked);
        }
        bucket.mutex.unlock();

        return result;
    }

    /// Wake one thread waiting on address
    pub fn unparkOne(self: *Self, address: *const anyopaque) bool {
        const addr = @intFromPtr(address);
        const bucket = self.getBucket(addr);

        bucket.mutex.lock();
        defer bucket.mutex.unlock();

        // Find first thread waiting on this address
        var current = bucket.head;
        while (current) |thread| {
            if (thread.address == addr) {
                // Found one - wake it
                thread.unparked.store(true, .release);
                bucket.removeThread(thread);
                thread.wakeup.set();
                return true;
            }
            current = thread.next;
        }

        return false;
    }

    /// Wake all threads waiting on address
    pub fn unparkAll(self: *Self, address: *const anyopaque) usize {
        const addr = @intFromPtr(address);
        const bucket = self.getBucket(addr);

        bucket.mutex.lock();
        defer bucket.mutex.unlock();

        var count: usize = 0;
        var current = bucket.head;

        while (current) |thread| {
            const next = thread.next;
            if (thread.address == addr) {
                thread.unparked.store(true, .release);
                bucket.removeThread(thread);
                thread.wakeup.set();
                count += 1;
            }
            current = next;
        }

        return count;
    }

    /// Get number of waiters on an address
    pub fn getWaiterCount(self: *Self, address: *const anyopaque) usize {
        const addr = @intFromPtr(address);
        const bucket = self.getBucket(addr);

        bucket.mutex.lock();
        defer bucket.mutex.unlock();

        var count: usize = 0;
        var current = bucket.head;
        while (current) |thread| {
            if (thread.address == addr) {
                count += 1;
            }
            current = thread.next;
        }

        return count;
    }
};

// ============================================================================
// Global Instance
// ============================================================================

var global_parking_lot: ?ParkingLot = null;

/// Get or initialize global parking lot
pub fn getParkingLot() *ParkingLot {
    if (global_parking_lot == null) {
        global_parking_lot = ParkingLot.init();
    }
    return &global_parking_lot.?;
}

// ============================================================================
// Public API
// ============================================================================

/// Park current thread on an address
pub fn park(address: *const anyopaque, timeout_ns: i64) WaitResult {
    return getParkingLot().park(address, timeout_ns);
}

/// Wake one waiter on address
pub fn unparkOne(address: *const anyopaque) bool {
    return getParkingLot().unparkOne(address);
}

/// Wake all waiters on address
pub fn unparkAll(address: *const anyopaque) usize {
    return getParkingLot().unparkAll(address);
}

/// Get count of waiters on address
pub fn getWaiterCount(address: *const anyopaque) usize {
    return getParkingLot().getWaiterCount(address);
}

// ============================================================================
// Futex-like Operations
// ============================================================================

/// Wait if value at address matches expected
pub fn futexWait(addr: *const Atomic(u32), expected: u32, timeout_ns: i64) WaitResult {
    // Check current value
    if (addr.load(.acquire) != expected) {
        return .invalid;
    }

    return park(addr, timeout_ns);
}

/// Wake waiters on a futex
pub fn futexWake(addr: *const Atomic(u32), count: usize) usize {
    if (count == 0) return 0;
    if (count == 1) {
        return if (unparkOne(addr)) 1 else 0;
    }
    return unparkAll(addr);
}

// ============================================================================
// Condition Variable
// ============================================================================

/// Simple condition variable built on parking lot
pub const CondVar = struct {
    seq: Atomic(u32) = Atomic(u32).init(0),

    const Self = @This();

    /// Wait for signal (must hold mutex)
    pub fn wait(self: *Self, mutex: *std.Thread.Mutex) void {
        self.timedWait(mutex, WAIT_FOREVER);
    }

    /// Wait with timeout
    pub fn timedWait(self: *Self, mutex: *std.Thread.Mutex, timeout_ns: i64) WaitResult {
        const seq = self.seq.load(.acquire);

        // Release mutex
        mutex.unlock();

        // Wait for signal or timeout
        const result = park(&self.seq, timeout_ns);

        // Reacquire mutex
        mutex.lock();

        // Check if we were signaled
        if (self.seq.load(.acquire) != seq) {
            return .ok;
        }

        return result;
    }

    /// Signal one waiter
    pub fn signal(self: *Self) void {
        _ = self.seq.fetchAdd(1, .release);
        _ = unparkOne(&self.seq);
    }

    /// Signal all waiters
    pub fn broadcast(self: *Self) void {
        _ = self.seq.fetchAdd(1, .release);
        _ = unparkAll(&self.seq);
    }
};

// ============================================================================
// Semaphore
// ============================================================================

/// Counting semaphore built on parking lot
pub const Semaphore = struct {
    count: Atomic(i32),

    const Self = @This();

    pub fn init(initial: u32) Self {
        return .{
            .count = Atomic(i32).init(@intCast(initial)),
        };
    }

    /// Acquire (decrement)
    pub fn acquire(self: *Self) void {
        while (true) {
            const count = self.count.load(.acquire);
            if (count > 0) {
                if (self.count.cmpxchgWeak(count, count - 1, .acq_rel, .acquire) == null) {
                    return;
                }
            } else {
                // Wait for release
                _ = park(&self.count, WAIT_FOREVER);
            }
        }
    }

    /// Try to acquire without blocking
    pub fn tryAcquire(self: *Self) bool {
        const count = self.count.load(.acquire);
        if (count > 0) {
            return self.count.cmpxchgWeak(count, count - 1, .acq_rel, .acquire) == null;
        }
        return false;
    }

    /// Release (increment)
    pub fn release(self: *Self) void {
        _ = self.count.fetchAdd(1, .release);
        _ = unparkOne(&self.count);
    }

    /// Get current count
    pub fn getCount(self: *const Self) i32 {
        return self.count.load(.acquire);
    }
};

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {
    _ = getParkingLot();
}

// ============================================================================
// Tests
// ============================================================================

test "parking lot basic" {
    var lot = ParkingLot.init();
    var address: u32 = 0;

    // No waiters initially
    try std.testing.expectEqual(@as(usize, 0), lot.getWaiterCount(&address));

    // unpark with no waiters should return false
    try std.testing.expect(!lot.unparkOne(&address));
    try std.testing.expectEqual(@as(usize, 0), lot.unparkAll(&address));
}

test "semaphore basic" {
    var sem = Semaphore.init(2);

    try std.testing.expectEqual(@as(i32, 2), sem.getCount());

    try std.testing.expect(sem.tryAcquire());
    try std.testing.expectEqual(@as(i32, 1), sem.getCount());

    try std.testing.expect(sem.tryAcquire());
    try std.testing.expectEqual(@as(i32, 0), sem.getCount());

    // Can't acquire more
    try std.testing.expect(!sem.tryAcquire());

    sem.release();
    try std.testing.expectEqual(@as(i32, 1), sem.getCount());

    try std.testing.expect(sem.tryAcquire());
}

test "condvar basic" {
    var cv = CondVar{};
    var mutex = std.Thread.Mutex{};

    // Signal with no waiters should be fine
    cv.signal();
    cv.broadcast();

    // Timed wait with zero timeout should return immediately
    mutex.lock();
    const result = cv.timedWait(&mutex, 0);
    mutex.unlock();

    try std.testing.expect(result == .timeout or result == .ok);
}

test "futex operations" {
    var value = Atomic(u32).init(0);

    // Wait with wrong expected value should return invalid
    const result = futexWait(&value, 1, 0);
    try std.testing.expectEqual(WaitResult.invalid, result);

    // Wake with no waiters
    const woken = futexWake(&value, 1);
    try std.testing.expectEqual(@as(usize, 0), woken);
}
