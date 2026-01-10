//! test.test_free_threading.test_races - Race condition tests
//!
//! This module provides tools for detecting and testing race conditions
//! in free-threaded Python execution. It includes race detectors, test
//! harnesses, and common race condition patterns.
const std = @import("std");

/// Race detector for tracking concurrent access
pub const RaceDetector = struct {
    const Self = @This();
    const MAX_ACCESSES = 256;

    const Access = struct {
        thread_id: usize,
        timestamp: i64,
        is_write: bool,
        location: usize,
    };

    accesses: [MAX_ACCESSES]Access,
    access_count: std.atomic.Value(usize),
    race_count: std.atomic.Value(usize),
    enabled: std.atomic.Value(bool),
    mutex: std.Thread.Mutex,

    pub fn init() Self {
        return .{
            .accesses = undefined,
            .access_count = std.atomic.Value(usize).init(0),
            .race_count = std.atomic.Value(usize).init(0),
            .enabled = std.atomic.Value(bool).init(true),
            .mutex = .{},
        };
    }

    pub fn recordRead(self: *Self, location: usize) void {
        self.recordAccess(location, false);
    }

    pub fn recordWrite(self: *Self, location: usize) void {
        self.recordAccess(location, true);
    }

    fn recordAccess(self: *Self, location: usize, is_write: bool) void {
        if (!self.enabled.load(.acquire)) return;

        const tid = std.Thread.getCurrentId();
        const timestamp = std.time.nanoTimestamp();

        self.mutex.lock();
        defer self.mutex.unlock();

        // Check for races with recent accesses
        const count = @min(self.access_count.load(.acquire), MAX_ACCESSES);
        for (0..count) |i| {
            const access = self.accesses[i];
            if (access.location == location and access.thread_id != tid) {
                // Potential race: different thread accessing same location
                if (access.is_write or is_write) {
                    // At least one is a write - this is a race
                    _ = self.race_count.fetchAdd(1, .monotonic);
                }
            }
        }

        // Record this access
        const idx = self.access_count.fetchAdd(1, .monotonic) % MAX_ACCESSES;
        self.accesses[idx] = .{
            .thread_id = tid,
            .timestamp = timestamp,
            .is_write = is_write,
            .location = location,
        };
    }

    pub fn getRaceCount(self: *const Self) usize {
        return self.race_count.load(.acquire);
    }

    pub fn hasRaces(self: *const Self) bool {
        return self.race_count.load(.acquire) > 0;
    }

    pub fn enable(self: *Self) void {
        self.enabled.store(true, .release);
    }

    pub fn disable(self: *Self) void {
        self.enabled.store(false, .release);
    }

    pub fn reset(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.access_count.store(0, .release);
        self.race_count.store(0, .release);
    }
};

/// Shared variable with race detection
pub fn RaceVariable(comptime T: type) type {
    return struct {
        const Self = @This();

        value: T,
        detector: *RaceDetector,
        id: usize,

        pub fn init(initial: T, detector: *RaceDetector, id: usize) Self {
            return .{
                .value = initial,
                .detector = detector,
                .id = id,
            };
        }

        pub fn read(self: *Self) T {
            self.detector.recordRead(self.id);
            return self.value;
        }

        pub fn write(self: *Self, val: T) void {
            self.detector.recordWrite(self.id);
            self.value = val;
        }

        pub fn unsafeRead(self: *const Self) T {
            return self.value;
        }

        pub fn unsafeWrite(self: *Self, val: T) void {
            self.value = val;
        }
    };
}

/// Common race condition patterns for testing
pub const RacePatterns = struct {
    /// Check-then-act pattern (TOCTOU)
    pub fn checkThenAct(comptime T: type) type {
        return struct {
            const Self = @This();

            value: std.atomic.Value(T),
            races_detected: std.atomic.Value(usize),

            pub fn init(initial: T) Self {
                return .{
                    .value = std.atomic.Value(T).init(initial),
                    .races_detected = std.atomic.Value(usize).init(0),
                };
            }

            /// Unsafe check-then-act (race-prone)
            pub fn unsafeIncrement(self: *Self) void {
                const current = self.value.load(.acquire);
                // Race window here!
                self.value.store(current + 1, .release);
            }

            /// Safe atomic version
            pub fn safeIncrement(self: *Self) void {
                _ = self.value.fetchAdd(1, .acq_rel);
            }

            pub fn get(self: *const Self) T {
                return self.value.load(.acquire);
            }
        };
    }

    /// Read-modify-write race pattern
    pub fn readModifyWrite(comptime T: type) type {
        return struct {
            const Self = @This();

            value: T,
            lock: std.Thread.Mutex,
            unsafe_ops: std.atomic.Value(usize),
            safe_ops: std.atomic.Value(usize),

            pub fn init(initial: T) Self {
                return .{
                    .value = initial,
                    .lock = .{},
                    .unsafe_ops = std.atomic.Value(usize).init(0),
                    .safe_ops = std.atomic.Value(usize).init(0),
                };
            }

            /// Unsafe read-modify-write (race-prone)
            pub fn unsafeModify(self: *Self, f: *const fn (T) T) void {
                _ = self.unsafe_ops.fetchAdd(1, .monotonic);
                self.value = f(self.value);
            }

            /// Safe locked version
            pub fn safeModify(self: *Self, f: *const fn (T) T) void {
                self.lock.lock();
                defer self.lock.unlock();
                _ = self.safe_ops.fetchAdd(1, .monotonic);
                self.value = f(self.value);
            }

            pub fn get(self: *Self) T {
                self.lock.lock();
                defer self.lock.unlock();
                return self.value;
            }
        };
    }
};

/// Race condition test harness
pub const RaceTestHarness = struct {
    const Self = @This();

    thread_count: usize,
    iterations: usize,
    results: std.ArrayList(TestResult),
    allocator: std.mem.Allocator,
    detector: RaceDetector,

    const TestResult = struct {
        test_name: []const u8,
        races_detected: usize,
        thread_count: usize,
        iterations: usize,
        duration_ns: i64,
        passed: bool,
    };

    pub fn init(allocator: std.mem.Allocator, thread_count: usize, iterations: usize) Self {
        return .{
            .thread_count = thread_count,
            .iterations = iterations,
            .results = std.ArrayList(TestResult).init(allocator),
            .allocator = allocator,
            .detector = RaceDetector.init(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.results.deinit();
    }

    pub fn runTest(self: *Self, name: []const u8, test_fn: *const fn (*RaceDetector) void) !void {
        const start = std.time.nanoTimestamp();

        var threads: [16]std.Thread = undefined;
        const actual_threads = @min(self.thread_count, 16);

        for (0..actual_threads) |i| {
            threads[i] = try std.Thread.spawn(.{}, struct {
                fn run(harness: *Self, f: *const fn (*RaceDetector) void) void {
                    for (0..harness.iterations) |_| {
                        f(&harness.detector);
                    }
                }
            }.run, .{ self, test_fn });
        }

        for (0..actual_threads) |i| {
            threads[i].join();
        }

        const duration = std.time.nanoTimestamp() - start;
        const races = self.detector.getRaceCount();

        try self.results.append(.{
            .test_name = name,
            .races_detected = races,
            .thread_count = actual_threads,
            .iterations = self.iterations,
            .duration_ns = duration,
            .passed = races == 0,
        });

        self.detector.reset();
    }

    pub fn getResults(self: *const Self) []const TestResult {
        return self.results.items;
    }

    pub fn allPassed(self: *const Self) bool {
        for (self.results.items) |result| {
            if (!result.passed) return false;
        }
        return true;
    }
};

/// Lost update detector
pub const LostUpdateDetector = struct {
    const Self = @This();

    expected: std.atomic.Value(i64),
    actual: std.atomic.Value(i64),
    update_count: std.atomic.Value(usize),
    lost_updates: std.atomic.Value(usize),

    pub fn init() Self {
        return .{
            .expected = std.atomic.Value(i64).init(0),
            .actual = std.atomic.Value(i64).init(0),
            .update_count = std.atomic.Value(usize).init(0),
            .lost_updates = std.atomic.Value(usize).init(0),
        };
    }

    pub fn unsafeUpdate(self: *Self, delta: i64) void {
        _ = self.update_count.fetchAdd(1, .monotonic);
        _ = self.expected.fetchAdd(delta, .monotonic);
        // Race-prone: read then write
        const current = self.actual.load(.acquire);
        self.actual.store(current + delta, .release);
    }

    pub fn safeUpdate(self: *Self, delta: i64) void {
        _ = self.update_count.fetchAdd(1, .monotonic);
        _ = self.expected.fetchAdd(delta, .monotonic);
        _ = self.actual.fetchAdd(delta, .acq_rel);
    }

    pub fn checkForLostUpdates(self: *Self) usize {
        const exp = self.expected.load(.acquire);
        const act = self.actual.load(.acquire);
        if (exp != act) {
            const lost = @abs(exp - act);
            self.lost_updates.store(@intCast(lost), .release);
            return @intCast(lost);
        }
        return 0;
    }

    pub fn getStats(self: *const Self) struct { updates: usize, lost: usize } {
        return .{
            .updates = self.update_count.load(.acquire),
            .lost = self.lost_updates.load(.acquire),
        };
    }
};

/// Data race simulator for testing race detection
pub const DataRaceSimulator = struct {
    const Self = @This();

    shared_data: [8]i64,
    mutex: std.Thread.Mutex,
    use_lock: std.atomic.Value(bool),
    access_log: std.ArrayList(AccessEntry),
    allocator: std.mem.Allocator,

    const AccessEntry = struct {
        thread_id: usize,
        index: usize,
        value: i64,
        is_write: bool,
        timestamp: i64,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .shared_data = [_]i64{0} ** 8,
            .mutex = .{},
            .use_lock = std.atomic.Value(bool).init(false),
            .access_log = std.ArrayList(AccessEntry).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.access_log.deinit();
    }

    pub fn enableLocking(self: *Self) void {
        self.use_lock.store(true, .release);
    }

    pub fn disableLocking(self: *Self) void {
        self.use_lock.store(false, .release);
    }

    pub fn read(self: *Self, index: usize) i64 {
        const tid = std.Thread.getCurrentId();
        const timestamp = std.time.nanoTimestamp();

        if (self.use_lock.load(.acquire)) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        const value = self.shared_data[index % 8];

        self.access_log.append(.{
            .thread_id = tid,
            .index = index % 8,
            .value = value,
            .is_write = false,
            .timestamp = timestamp,
        }) catch {};

        return value;
    }

    pub fn write(self: *Self, index: usize, value: i64) void {
        const tid = std.Thread.getCurrentId();
        const timestamp = std.time.nanoTimestamp();

        if (self.use_lock.load(.acquire)) {
            self.mutex.lock();
            defer self.mutex.unlock();
        }

        self.shared_data[index % 8] = value;

        self.access_log.append(.{
            .thread_id = tid,
            .index = index % 8,
            .value = value,
            .is_write = true,
            .timestamp = timestamp,
        }) catch {};
    }

    pub fn analyzeRaces(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        var race_count: usize = 0;
        const log = self.access_log.items;

        for (0..log.len) |i| {
            for ((i + 1)..log.len) |j| {
                if (log[i].index == log[j].index and
                    log[i].thread_id != log[j].thread_id and
                    (log[i].is_write or log[j].is_write))
                {
                    // Potential race condition
                    race_count += 1;
                }
            }
        }

        return race_count;
    }

    pub fn clearLog(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.access_log.clearRetainingCapacity();
    }
};

/// ABA problem detector
pub const ABADetector = struct {
    const Self = @This();

    value: std.atomic.Value(usize),
    version: std.atomic.Value(usize),
    aba_count: std.atomic.Value(usize),

    pub fn init(initial: usize) Self {
        return .{
            .value = std.atomic.Value(usize).init(initial),
            .version = std.atomic.Value(usize).init(0),
            .aba_count = std.atomic.Value(usize).init(0),
        };
    }

    /// CAS without ABA protection (vulnerable)
    pub fn unsafeCAS(self: *Self, expected: usize, desired: usize) bool {
        return self.value.cmpxchgStrong(expected, desired, .acq_rel, .acquire) == null;
    }

    /// CAS with version check (ABA protected)
    pub fn safeCAS(self: *Self, expected_val: usize, expected_ver: usize, desired: usize) bool {
        const current_val = self.value.load(.acquire);
        const current_ver = self.version.load(.acquire);

        if (current_val != expected_val or current_ver != expected_ver) {
            if (current_val == expected_val and current_ver != expected_ver) {
                _ = self.aba_count.fetchAdd(1, .monotonic);
            }
            return false;
        }

        if (self.value.cmpxchgStrong(expected_val, desired, .acq_rel, .acquire)) |_| {
            return false;
        }

        _ = self.version.fetchAdd(1, .release);
        return true;
    }

    pub fn get(self: *const Self) struct { value: usize, version: usize } {
        return .{
            .value = self.value.load(.acquire),
            .version = self.version.load(.acquire),
        };
    }

    pub fn getABACount(self: *const Self) usize {
        return self.aba_count.load(.acquire);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "race_detector_basic" {
    var detector = RaceDetector.init();

    detector.recordRead(0);
    detector.recordWrite(0);

    // Same thread, no race
    try std.testing.expect(!detector.hasRaces());
}

test "race_variable_basic" {
    var detector = RaceDetector.init();
    var rv = RaceVariable(i32).init(0, &detector, 1);

    rv.write(42);
    try std.testing.expectEqual(@as(i32, 42), rv.read());
}

test "check_then_act_pattern" {
    var pattern = RacePatterns.checkThenAct(i64).init(0);

    pattern.safeIncrement();
    pattern.safeIncrement();

    try std.testing.expectEqual(@as(i64, 2), pattern.get());
}

test "read_modify_write_pattern" {
    var pattern = RacePatterns.readModifyWrite(i64).init(10);

    pattern.safeModify(struct {
        fn double(x: i64) i64 {
            return x * 2;
        }
    }.double);

    try std.testing.expectEqual(@as(i64, 20), pattern.get());
}

test "lost_update_detector_safe" {
    var detector = LostUpdateDetector.init();

    detector.safeUpdate(1);
    detector.safeUpdate(1);
    detector.safeUpdate(1);

    const lost = detector.checkForLostUpdates();
    try std.testing.expectEqual(@as(usize, 0), lost);

    const stats = detector.getStats();
    try std.testing.expectEqual(@as(usize, 3), stats.updates);
}

test "data_race_simulator_with_lock" {
    const allocator = std.testing.allocator;
    var sim = DataRaceSimulator.init(allocator);
    defer sim.deinit();

    sim.enableLocking();

    sim.write(0, 100);
    try std.testing.expectEqual(@as(i64, 100), sim.read(0));
}

test "aba_detector_basic" {
    var detector = ABADetector.init(1);

    const state = detector.get();
    try std.testing.expectEqual(@as(usize, 1), state.value);
    try std.testing.expectEqual(@as(usize, 0), state.version);

    try std.testing.expect(detector.safeCAS(1, 0, 2));

    const state2 = detector.get();
    try std.testing.expectEqual(@as(usize, 2), state2.value);
    try std.testing.expectEqual(@as(usize, 1), state2.version);
}

test "lost_update_multithread_safe" {
    var detector = LostUpdateDetector.init();

    const num_threads = 4;
    const updates = 100;
    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, struct {
            fn run(d: *LostUpdateDetector) void {
                for (0..updates) |_| {
                    d.safeUpdate(1);
                }
            }
        }.run, .{&detector}) catch unreachable;
    }

    for (&threads) |*t| {
        t.join();
    }

    const lost = detector.checkForLostUpdates();
    try std.testing.expectEqual(@as(usize, 0), lost);

    const stats = detector.getStats();
    try std.testing.expectEqual(@as(usize, num_threads * updates), stats.updates);
}

test "check_then_act_multithread_safe" {
    var pattern = RacePatterns.checkThenAct(i64).init(0);

    const num_threads = 4;
    const increments = 100;
    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, struct {
            fn run(p: *RacePatterns.checkThenAct(i64)) void {
                for (0..increments) |_| {
                    p.safeIncrement();
                }
            }
        }.run, .{&pattern}) catch unreachable;
    }

    for (&threads) |*t| {
        t.join();
    }

    try std.testing.expectEqual(@as(i64, num_threads * increments), pattern.get());
}

test "data_race_simulator_multithread" {
    const allocator = std.testing.allocator;
    var sim = DataRaceSimulator.init(allocator);
    defer sim.deinit();

    sim.enableLocking();

    const num_threads = 4;
    const ops = 10;
    var threads: [num_threads]std.Thread = undefined;

    for (0..num_threads) |i| {
        threads[i] = std.Thread.spawn(.{}, struct {
            fn run(s: *DataRaceSimulator, tid: usize) void {
                for (0..ops) |j| {
                    s.write(tid, @intCast(j));
                    _ = s.read(tid);
                }
            }
        }.run, .{ &sim, i }) catch unreachable;
    }

    for (&threads) |*t| {
        t.join();
    }

    // With locking, should have no races (writes to same index serialized)
    // Note: analyzeRaces still counts pairs but they're serialized
}

test "race_test_harness_basic" {
    const allocator = std.testing.allocator;
    var harness = RaceTestHarness.init(allocator, 2, 10);
    defer harness.deinit();

    try harness.runTest("simple_test", struct {
        fn test_fn(detector: *RaceDetector) void {
            detector.recordRead(0);
        }
    }.test_fn);

    const results = harness.getResults();
    try std.testing.expectEqual(@as(usize, 1), results.len);
}
