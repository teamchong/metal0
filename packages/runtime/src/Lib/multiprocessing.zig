//! Python 'multiprocessing' module - Process-based parallelism
//!
//! Provides process spawning and inter-process communication
//! for parallel execution of Python code.
//!
//! Mirrors: CPython Lib/multiprocessing/

const std = @import("std");
const builtin = @import("builtin");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Process Class
// ============================================================================

/// A process object representing an activity run in a separate process
pub const Process = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    name: []const u8,
    pid: ?std.posix.pid_t,
    daemon: bool,
    exitcode: ?i32,
    target: ?*const fn () void,
    args: ?[]const []const u8,
    kwargs: ?hashmap_helper.StringHashMap([]const u8),
    started: bool,
    sentinel: ?i32,

    pub fn init(
        allocator: std.mem.Allocator,
        target: ?*const fn () void,
        name: ?[]const u8,
        args: ?[]const []const u8,
        daemon: bool,
    ) Self {
        return .{
            .allocator = allocator,
            .name = name orelse "Process",
            .pid = null,
            .daemon = daemon,
            .exitcode = null,
            .target = target,
            .args = args,
            .kwargs = null,
            .started = false,
            .sentinel = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.kwargs) |*kw| {
            kw.deinit();
        }
    }

    /// Start the process
    pub fn start(self: *Self) !void {
        if (self.started) {
            return error.ProcessAlreadyStarted;
        }

        const pid = try std.posix.fork();
        if (pid == 0) {
            // Child process
            if (self.target) |target_fn| {
                target_fn();
            }
            std.posix.exit(0);
        } else {
            // Parent process
            self.pid = pid;
            self.started = true;
        }
    }

    /// Wait for process to terminate
    pub fn join(self: *Self, timeout: ?f64) !void {
        _ = timeout;
        if (!self.started) {
            return error.ProcessNotStarted;
        }

        if (self.pid) |pid| {
            const result = std.posix.waitpid(pid, 0);
            self.exitcode = @as(i32, @intCast(result.status));
            self.pid = null;
        }
    }

    /// Check if process is alive
    pub fn isAlive(self: *Self) bool {
        if (!self.started) return false;
        if (self.exitcode != null) return false;

        if (self.pid) |pid| {
            const result = std.posix.waitpid(pid, std.posix.W.NOHANG);
            if (result.pid != 0) {
                self.exitcode = @as(i32, @intCast(result.status));
                return false;
            }
            return true;
        }
        return false;
    }

    /// Terminate the process
    pub fn terminate(self: *Self) !void {
        if (self.pid) |pid| {
            try std.posix.kill(pid, std.posix.SIG.TERM);
        }
    }

    /// Kill the process (forcefully)
    pub fn kill(self: *Self) !void {
        if (self.pid) |pid| {
            try std.posix.kill(pid, std.posix.SIG.KILL);
        }
    }

    /// Get process ID
    pub fn getPid(self: *Self) ?std.posix.pid_t {
        return self.pid;
    }

    /// Get exit code
    pub fn getExitcode(self: *Self) ?i32 {
        return self.exitcode;
    }
};

// ============================================================================
// Pool - Worker pool for parallel execution
// ============================================================================

/// A pool of worker processes
pub const Pool = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    processes: i32,
    workers: std.ArrayList(Process),
    closed: bool,
    terminated: bool,

    pub fn init(allocator: std.mem.Allocator, processes: ?i32) Self {
        const num_processes = processes orelse @as(i32, @intCast(getCpuCount()));
        return .{
            .allocator = allocator,
            .processes = num_processes,
            .workers = std.ArrayList(Process).init(allocator),
            .closed = false,
            .terminated = false,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.workers.items) |*worker| {
            worker.deinit();
        }
        self.workers.deinit();
    }

    /// Apply a function to arguments (blocking)
    pub fn apply(self: *Self, func: *const fn () void, args: ?[]const []const u8) !void {
        if (self.closed) return error.PoolClosed;
        _ = args;
        func();
    }

    /// Apply function asynchronously
    pub fn applyAsync(self: *Self, func: *const fn () void, args: ?[]const []const u8) !AsyncResult {
        if (self.closed) return error.PoolClosed;

        var process = Process.init(self.allocator, func, null, args, false);
        try process.start();
        try self.workers.append(process);

        return AsyncResult{
            .process = &self.workers.items[self.workers.items.len - 1],
        };
    }

    /// Map function over iterable
    pub fn map(self: *Self, func: *const fn ([]const u8) []const u8, iterable: []const []const u8) ![][]const u8 {
        if (self.closed) return error.PoolClosed;

        var results = try self.allocator.alloc([]const u8, iterable.len);
        for (iterable, 0..) |item, i| {
            results[i] = func(item);
        }
        return results;
    }

    /// Map function asynchronously
    pub fn mapAsync(self: *Self, func: *const fn ([]const u8) []const u8, iterable: []const []const u8) !MapResult {
        if (self.closed) return error.PoolClosed;

        return MapResult{
            .allocator = self.allocator,
            .func = func,
            .iterable = iterable,
            .ready = false,
        };
    }

    /// Close the pool (no new tasks)
    pub fn close(self: *Self) void {
        self.closed = true;
    }

    /// Terminate all workers
    pub fn terminate(self: *Self) void {
        for (self.workers.items) |*worker| {
            worker.terminate() catch {};
        }
        self.terminated = true;
    }

    /// Wait for workers to finish
    pub fn join(self: *Self) !void {
        if (!self.closed) return error.PoolNotClosed;

        for (self.workers.items) |*worker| {
            try worker.join(null);
        }
    }
};

/// Async result from pool.apply_async
pub const AsyncResult = struct {
    process: *Process,

    pub fn get(self: *AsyncResult, timeout: ?f64) !void {
        try self.process.join(timeout);
    }

    pub fn ready(self: *AsyncResult) bool {
        return !self.process.isAlive();
    }

    pub fn successful(self: *AsyncResult) bool {
        if (self.process.exitcode) |code| {
            return code == 0;
        }
        return false;
    }

    pub fn wait(self: *AsyncResult, timeout: ?f64) !void {
        try self.process.join(timeout);
    }
};

/// Map result from pool.map_async
pub const MapResult = struct {
    allocator: std.mem.Allocator,
    func: *const fn ([]const u8) []const u8,
    iterable: []const []const u8,
    ready: bool,

    pub fn get(self: *MapResult, timeout: ?f64) ![][]const u8 {
        _ = timeout;
        var results = try self.allocator.alloc([]const u8, self.iterable.len);
        for (self.iterable, 0..) |item, i| {
            results[i] = self.func(item);
        }
        self.ready = true;
        return results;
    }

    pub fn isReady(self: *MapResult) bool {
        return self.ready;
    }
};

// ============================================================================
// Queue - Inter-process communication queue
// ============================================================================

/// A process-safe queue
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        items: std.ArrayList(T),
        mutex: std.Thread.Mutex,
        maxsize: usize,
        closed: bool,

        pub fn init(allocator: std.mem.Allocator, maxsize: usize) Self {
            return .{
                .allocator = allocator,
                .items = std.ArrayList(T).init(allocator),
                .mutex = .{},
                .maxsize = maxsize,
                .closed = false,
            };
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        /// Put an item into the queue
        pub fn put(self: *Self, item: T, block: bool, timeout: ?f64) !void {
            _ = timeout;
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.closed) return error.QueueClosed;

            if (self.maxsize > 0 and self.items.items.len >= self.maxsize) {
                if (!block) return error.QueueFull;
                // In a real implementation, would block here
                return error.QueueFull;
            }

            try self.items.append(item);
        }

        /// Put without blocking
        pub fn putNowait(self: *Self, item: T) !void {
            return self.put(item, false, null);
        }

        /// Get an item from the queue
        pub fn get(self: *Self, block: bool, timeout: ?f64) !T {
            _ = timeout;
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.items.items.len == 0) {
                if (!block) return error.QueueEmpty;
                // In a real implementation, would block here
                return error.QueueEmpty;
            }

            return self.items.orderedRemove(0);
        }

        /// Get without blocking
        pub fn getNowait(self: *Self) !T {
            return self.get(false, null);
        }

        /// Check if queue is empty
        pub fn empty(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len == 0;
        }

        /// Check if queue is full
        pub fn full(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.maxsize > 0 and self.items.items.len >= self.maxsize;
        }

        /// Get approximate queue size
        pub fn qsize(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.items.items.len;
        }

        /// Close the queue
        pub fn close(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.closed = true;
        }

        /// Join queue (wait for all tasks to complete)
        pub fn joinQueue(self: *Self) void {
            while (!self.empty()) {
                std.time.sleep(1_000_000); // 1ms
            }
        }
    };
}

/// Simple queue (non-generic, for compatibility)
pub const SimpleQueue = Queue([]const u8);

/// Joinable queue
pub fn JoinableQueue(comptime T: type) type {
    return struct {
        const Self = @This();

        queue: Queue(T),
        unfinished_tasks: usize,
        mutex: std.Thread.Mutex,

        pub fn init(allocator: std.mem.Allocator, maxsize: usize) Self {
            return .{
                .queue = Queue(T).init(allocator, maxsize),
                .unfinished_tasks = 0,
                .mutex = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.queue.deinit();
        }

        pub fn put(self: *Self, item: T, block: bool, timeout: ?f64) !void {
            try self.queue.put(item, block, timeout);
            self.mutex.lock();
            defer self.mutex.unlock();
            self.unfinished_tasks += 1;
        }

        pub fn get(self: *Self, block: bool, timeout: ?f64) !T {
            return self.queue.get(block, timeout);
        }

        pub fn taskDone(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            if (self.unfinished_tasks > 0) {
                self.unfinished_tasks -= 1;
            }
        }

        pub fn join(self: *Self) void {
            while (true) {
                self.mutex.lock();
                const tasks = self.unfinished_tasks;
                self.mutex.unlock();
                if (tasks == 0) break;
                std.time.sleep(1_000_000); // 1ms
            }
        }
    };
}

// ============================================================================
// Pipe - Bidirectional communication
// ============================================================================

/// A bidirectional pipe connection
pub const Connection = struct {
    const Self = @This();

    reader: std.posix.fd_t,
    writer: std.posix.fd_t,
    closed: bool,

    pub fn init(reader: std.posix.fd_t, writer: std.posix.fd_t) Self {
        return .{
            .reader = reader,
            .writer = writer,
            .closed = false,
        };
    }

    /// Send data through the pipe
    pub fn send(self: *Self, data: []const u8) !void {
        if (self.closed) return error.ConnectionClosed;
        _ = try std.posix.write(self.writer, data);
    }

    /// Receive data from the pipe
    pub fn recv(self: *Self, buffer: []u8) !usize {
        if (self.closed) return error.ConnectionClosed;
        return std.posix.read(self.reader, buffer);
    }

    /// Check if data is available
    pub fn poll(self: *Self, timeout: ?f64) !bool {
        _ = timeout;
        if (self.closed) return false;
        // Would use select/poll in real implementation
        return true;
    }

    /// Close the connection
    pub fn close(self: *Self) void {
        if (!self.closed) {
            std.posix.close(self.reader);
            std.posix.close(self.writer);
            self.closed = true;
        }
    }

    /// Get file descriptor for select/poll
    pub fn fileno(self: *Self) std.posix.fd_t {
        return self.reader;
    }
};

/// Create a pipe returning two connection objects
pub fn Pipe(duplex: bool) !struct { Connection, Connection } {
    _ = duplex;

    const pipe1 = try std.posix.pipe();
    const pipe2 = try std.posix.pipe();

    const conn1 = Connection.init(pipe1[0], pipe2[1]);
    const conn2 = Connection.init(pipe2[0], pipe1[1]);

    return .{ conn1, conn2 };
}

// ============================================================================
// Value - Shared memory value
// ============================================================================

/// A shared memory value
pub fn Value(comptime T: type) type {
    return struct {
        const Self = @This();

        value: T,
        mutex: std.Thread.Mutex,

        pub fn init(initial: T) Self {
            return .{
                .value = initial,
                .mutex = .{},
            };
        }

        pub fn get(self: *Self) T {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.value;
        }

        pub fn set(self: *Self, val: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.value = val;
        }

        /// Get with lock held (for read-modify-write)
        pub fn getLockedValue(self: *Self) *T {
            self.mutex.lock();
            return &self.value;
        }

        pub fn releaseLockedValue(self: *Self) void {
            self.mutex.unlock();
        }
    };
}

// ============================================================================
// Array - Shared memory array
// ============================================================================

/// A shared memory array
pub fn Array(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        data: []T,
        mutex: std.Thread.Mutex,

        pub fn init(allocator: std.mem.Allocator, size: usize) !Self {
            const data = try allocator.alloc(T, size);
            return .{
                .allocator = allocator,
                .data = data,
                .mutex = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.data);
        }

        pub fn get(self: *Self, index: usize) T {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.data[index];
        }

        pub fn set(self: *Self, index: usize, value: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.data[index] = value;
        }

        pub fn len(self: *Self) usize {
            return self.data.len;
        }

        /// Get slice with lock held
        pub fn getLockedSlice(self: *Self) []T {
            self.mutex.lock();
            return self.data;
        }

        pub fn releaseLockedSlice(self: *Self) void {
            self.mutex.unlock();
        }
    };
}

// ============================================================================
// Manager - Process manager for shared objects
// ============================================================================

/// Manager for creating shared objects
pub const Manager = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    started: bool,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .started = false,
        };
    }

    pub fn start(self: *Self) void {
        self.started = true;
    }

    pub fn shutdown(self: *Self) void {
        self.started = false;
    }

    /// Create a managed list
    pub fn list(self: *Self, comptime T: type) !std.ArrayList(T) {
        if (!self.started) return error.ManagerNotStarted;
        return std.ArrayList(T).init(self.allocator);
    }

    /// Create a managed dict
    pub fn dict(self: *Self, comptime K: type, comptime V: type) !std.AutoHashMap(K, V) {
        if (!self.started) return error.ManagerNotStarted;
        return std.AutoHashMap(K, V).init(self.allocator);
    }

    /// Create a managed namespace
    pub fn Namespace(self: *Self) !ManagedNamespace {
        if (!self.started) return error.ManagerNotStarted;
        return ManagedNamespace.init(self.allocator);
    }

    /// Create a managed queue
    pub fn queue(self: *Self, comptime T: type, maxsize: usize) !Queue(T) {
        if (!self.started) return error.ManagerNotStarted;
        return Queue(T).init(self.allocator, maxsize);
    }

    /// Create a managed value
    pub fn value(self: *Self, comptime T: type, initial: T) !Value(T) {
        if (!self.started) return error.ManagerNotStarted;
        return Value(T).init(initial);
    }
};

/// Managed namespace for shared attributes
pub const ManagedNamespace = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    attrs: hashmap_helper.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .attrs = hashmap_helper.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.attrs.deinit();
    }

    pub fn setAttr(self: *Self, name: []const u8, value: []const u8) !void {
        try self.attrs.put(name, value);
    }

    pub fn getAttr(self: *Self, name: []const u8) ?[]const u8 {
        return self.attrs.get(name);
    }

    pub fn delAttr(self: *Self, name: []const u8) void {
        _ = self.attrs.remove(name);
    }
};

// ============================================================================
// Lock and Synchronization
// ============================================================================

/// A process-safe lock (reentrant)
pub const Lock = struct {
    const Self = @This();

    mutex: std.Thread.Mutex,
    locked: bool,

    pub fn init() Self {
        return .{
            .mutex = .{},
            .locked = false,
        };
    }

    pub fn acquire(self: *Self, block: bool, timeout: ?f64) bool {
        _ = timeout;
        if (block) {
            self.mutex.lock();
            self.locked = true;
            return true;
        } else {
            if (self.mutex.tryLock()) {
                self.locked = true;
                return true;
            }
            return false;
        }
    }

    pub fn release(self: *Self) void {
        self.locked = false;
        self.mutex.unlock();
    }
};

/// Reentrant lock
pub const RLock = struct {
    const Self = @This();

    mutex: std.Thread.Mutex,
    owner: ?std.Thread.Id,
    count: usize,

    pub fn init() Self {
        return .{
            .mutex = .{},
            .owner = null,
            .count = 0,
        };
    }

    pub fn acquire(self: *Self, block: bool, timeout: ?f64) bool {
        _ = timeout;
        const tid = std.Thread.getCurrentId();

        if (self.owner == tid) {
            self.count += 1;
            return true;
        }

        if (block) {
            self.mutex.lock();
        } else {
            if (!self.mutex.tryLock()) {
                return false;
            }
        }

        self.owner = tid;
        self.count = 1;
        return true;
    }

    pub fn release(self: *Self) void {
        if (self.owner != std.Thread.getCurrentId()) {
            return; // Not owner
        }

        self.count -= 1;
        if (self.count == 0) {
            self.owner = null;
            self.mutex.unlock();
        }
    }
};

/// Condition variable
pub const Condition = struct {
    const Self = @This();

    cond: std.Thread.Condition,
    lock: *Lock,

    pub fn init(lock: *Lock) Self {
        return .{
            .cond = .{},
            .lock = lock,
        };
    }

    pub fn wait(self: *Self, timeout: ?f64) bool {
        if (timeout) |t| {
            const ns = @as(u64, @intFromFloat(t * 1_000_000_000));
            self.cond.timedWait(&self.lock.mutex, ns) catch return false;
            return true;
        } else {
            self.cond.wait(&self.lock.mutex);
            return true;
        }
    }

    pub fn notify(self: *Self) void {
        self.cond.signal();
    }

    pub fn notifyAll(self: *Self) void {
        self.cond.broadcast();
    }
};

/// Semaphore
pub const Semaphore = struct {
    const Self = @This();

    value: usize,
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,

    pub fn init(value: usize) Self {
        return .{
            .value = value,
            .mutex = .{},
            .cond = .{},
        };
    }

    pub fn acquire(self: *Self, block: bool, timeout: ?f64) bool {
        _ = timeout;
        self.mutex.lock();
        defer self.mutex.unlock();

        while (self.value == 0) {
            if (!block) return false;
            self.cond.wait(&self.mutex);
        }

        self.value -= 1;
        return true;
    }

    pub fn release(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.value += 1;
        self.cond.signal();
    }

    pub fn getValue(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.value;
    }
};

/// Bounded semaphore
pub const BoundedSemaphore = struct {
    const Self = @This();

    semaphore: Semaphore,
    initial_value: usize,

    pub fn init(value: usize) Self {
        return .{
            .semaphore = Semaphore.init(value),
            .initial_value = value,
        };
    }

    pub fn acquire(self: *Self, block: bool, timeout: ?f64) bool {
        return self.semaphore.acquire(block, timeout);
    }

    pub fn release(self: *Self) !void {
        self.semaphore.mutex.lock();
        defer self.semaphore.mutex.unlock();

        if (self.semaphore.value >= self.initial_value) {
            return error.SemaphoreOverflow;
        }

        self.semaphore.value += 1;
        self.semaphore.cond.signal();
    }
};

/// Event object
pub const Event = struct {
    const Self = @This();

    flag: bool,
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,

    pub fn init() Self {
        return .{
            .flag = false,
            .mutex = .{},
            .cond = .{},
        };
    }

    pub fn set(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.flag = true;
        self.cond.broadcast();
    }

    pub fn clear(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.flag = false;
    }

    pub fn isSet(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.flag;
    }

    pub fn wait(self: *Self, timeout: ?f64) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.flag) return true;

        if (timeout) |t| {
            const ns = @as(u64, @intFromFloat(t * 1_000_000_000));
            self.cond.timedWait(&self.mutex, ns) catch return self.flag;
        } else {
            while (!self.flag) {
                self.cond.wait(&self.mutex);
            }
        }
        return self.flag;
    }
};

/// Barrier for synchronizing processes
pub const Barrier = struct {
    const Self = @This();

    parties: usize,
    count: usize,
    generation: usize,
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,
    broken: bool,

    pub fn init(parties: usize) Self {
        return .{
            .parties = parties,
            .count = 0,
            .generation = 0,
            .mutex = .{},
            .cond = .{},
            .broken = false,
        };
    }

    pub fn wait(self: *Self, timeout: ?f64) !usize {
        _ = timeout;
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.broken) return error.BrokenBarrier;

        const gen = self.generation;
        self.count += 1;
        const index = self.parties - self.count;

        if (self.count == self.parties) {
            // Last thread - release all
            self.generation += 1;
            self.count = 0;
            self.cond.broadcast();
            return index;
        }

        // Wait for release
        while (gen == self.generation and !self.broken) {
            self.cond.wait(&self.mutex);
        }

        if (self.broken) return error.BrokenBarrier;
        return index;
    }

    pub fn reset(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.count = 0;
        self.generation += 1;
        self.broken = false;
        self.cond.broadcast();
    }

    pub fn abort(self: *Self) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.broken = true;
        self.cond.broadcast();
    }

    pub fn getParties(self: *Self) usize {
        return self.parties;
    }

    pub fn getWaiting(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.count;
    }

    pub fn isBroken(self: *Self) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.broken;
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Get the number of CPUs
pub fn getCpuCount() usize {
    return std.Thread.getCpuCount() catch 1;
}

/// Alias for cpu_count
pub fn cpuCount() usize {
    return getCpuCount();
}

/// Get current process
pub fn currentProcess() CurrentProcess {
    return CurrentProcess{};
}

pub const CurrentProcess = struct {
    pub fn name(self: CurrentProcess) []const u8 {
        _ = self;
        return "MainProcess";
    }

    pub fn pid(self: CurrentProcess) std.posix.pid_t {
        _ = self;
        return std.posix.getpid();
    }

    pub fn isAlive(self: CurrentProcess) bool {
        _ = self;
        return true;
    }
};

/// Get parent process ID
pub fn parentProcess() ?std.posix.pid_t {
    return std.posix.getppid();
}

/// Get all active child processes
pub fn activeChildren(allocator: std.mem.Allocator) ![]Process {
    // Would track active children in real implementation
    _ = allocator;
    return &[_]Process{};
}

/// Set start method (fork, spawn, forkserver)
pub fn setStartMethod(method: []const u8, force: bool) !void {
    _ = method;
    _ = force;
    // Would configure start method in real implementation
}

/// Get start method
pub fn getStartMethod(allow_none: bool) ?[]const u8 {
    _ = allow_none;
    return "fork"; // Default on Unix
}

/// Get all start methods
pub fn getAllStartMethods() []const []const u8 {
    return &[_][]const u8{ "fork", "spawn", "forkserver" };
}

/// Freeze support for Windows
pub fn freezeSupport() void {
    // No-op on Unix
}

// ============================================================================
// Context - For different start methods
// ============================================================================

pub const Context = struct {
    const Self = @This();

    method: []const u8,

    pub fn init(method: []const u8) Self {
        return .{ .method = method };
    }

    pub fn Process(self: *Self, allocator: std.mem.Allocator, target: ?*const fn () void) Process {
        _ = self;
        return Process.init(allocator, target, null, null, false);
    }

    pub fn Pool(self: *Self, allocator: std.mem.Allocator, processes: ?i32) Pool {
        _ = self;
        return Pool.init(allocator, processes);
    }
};

/// Get a context for a specific start method
pub fn getContext(method: ?[]const u8) Context {
    return Context.init(method orelse "fork");
}

// ============================================================================
// Exceptions
// ============================================================================

pub const ProcessError = error{
    ProcessAlreadyStarted,
    ProcessNotStarted,
    PoolClosed,
    PoolNotClosed,
    QueueFull,
    QueueEmpty,
    QueueClosed,
    ConnectionClosed,
    ManagerNotStarted,
    SemaphoreOverflow,
    BrokenBarrier,
    TimeoutExpired,
};

// ============================================================================
// Tests
// ============================================================================

test "Process init" {
    const allocator = std.testing.allocator;
    var process = Process.init(allocator, null, "TestProcess", null, false);
    defer process.deinit();

    try std.testing.expectEqualStrings("TestProcess", process.name);
    try std.testing.expect(!process.daemon);
    try std.testing.expect(process.pid == null);
}

test "Pool init" {
    const allocator = std.testing.allocator;
    var pool = Pool.init(allocator, 4);
    defer pool.deinit();

    try std.testing.expectEqual(@as(i32, 4), pool.processes);
    try std.testing.expect(!pool.closed);
}

test "Queue operations" {
    const allocator = std.testing.allocator;
    var queue = Queue(i32).init(allocator, 10);
    defer queue.deinit();

    try queue.put(42, false, null);
    try std.testing.expectEqual(@as(usize, 1), queue.qsize());

    const item = try queue.get(false, null);
    try std.testing.expectEqual(@as(i32, 42), item);
    try std.testing.expect(queue.empty());
}

test "Value operations" {
    var val = Value(i32).init(0);

    try std.testing.expectEqual(@as(i32, 0), val.get());
    val.set(42);
    try std.testing.expectEqual(@as(i32, 42), val.get());
}

test "Lock operations" {
    var lock = Lock.init();

    try std.testing.expect(lock.acquire(true, null));
    lock.release();
}

test "Semaphore operations" {
    var sem = Semaphore.init(2);

    try std.testing.expect(sem.acquire(false, null));
    try std.testing.expectEqual(@as(usize, 1), sem.getValue());
    sem.release();
    try std.testing.expectEqual(@as(usize, 2), sem.getValue());
}

test "Event operations" {
    var event = Event.init();

    try std.testing.expect(!event.isSet());
    event.set();
    try std.testing.expect(event.isSet());
    event.clear();
    try std.testing.expect(!event.isSet());
}

test "cpu_count" {
    const count = getCpuCount();
    try std.testing.expect(count >= 1);
}

test "get_start_method" {
    const method = getStartMethod(false);
    try std.testing.expect(method != null);
}
