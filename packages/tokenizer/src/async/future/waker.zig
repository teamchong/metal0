const std = @import("std");
const Task = @import("../task.zig").Task;
const TaskState = @import("../task.zig").TaskState;

/// Waker data (opaque pointer to task or other wake mechanism)
pub const WakerData = struct {
    ptr: *anyopaque,
    vtable: *const WakerVTable,

    pub fn init(ptr: *anyopaque, vtable: *const WakerVTable) WakerData {
        return WakerData{
            .ptr = ptr,
            .vtable = vtable,
        };
    }

    pub fn wake(self: WakerData) void {
        self.vtable.wake(self.ptr);
    }

    pub fn wakeByRef(self: *const WakerData) void {
        self.vtable.wake_by_ref(self.ptr);
    }

    pub fn drop(self: WakerData) void {
        self.vtable.drop(self.ptr);
    }

    pub fn clone(self: *const WakerData, allocator: std.mem.Allocator) !WakerData {
        const new_ptr = try self.vtable.clone(self.ptr, allocator);
        return WakerData{
            .ptr = new_ptr,
            .vtable = self.vtable,
        };
    }
};

/// Waker virtual table
pub const WakerVTable = struct {
    /// Wake the task (consumes waker)
    wake: *const fn (*anyopaque) void,

    /// Wake the task (by reference)
    wake_by_ref: *const fn (*anyopaque) void,

    /// Drop the waker
    drop: *const fn (*anyopaque) void,

    /// Clone the waker
    clone: *const fn (*anyopaque, std.mem.Allocator) anyerror!*anyopaque,
};

/// Task-based waker (default implementation)
pub const TaskWaker = struct {
    task: *Task,

    const vtable = WakerVTable{
        .wake = wake,
        .wake_by_ref = wakeByRef,
        .drop = drop,
        .clone = clone,
    };

    pub fn init(task: *Task) TaskWaker {
        return TaskWaker{ .task = task };
    }

    pub fn toWakerData(self: *TaskWaker) WakerData {
        return WakerData.init(@ptrCast(self), &vtable);
    }

    fn wake(ptr: *anyopaque) void {
        const self: *TaskWaker = @ptrCast(@alignCast(ptr));
        self.task.state = .runnable;
    }

    fn wakeByRef(ptr: *anyopaque) void {
        const self: *TaskWaker = @ptrCast(@alignCast(ptr));
        self.task.state = .runnable;
    }

    fn drop(_: *anyopaque) void {
        // No-op for task waker
    }

    fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) !*anyopaque {
        const self: *TaskWaker = @ptrCast(@alignCast(ptr));
        const new_waker = try allocator.create(TaskWaker);
        new_waker.* = TaskWaker{ .task = self.task };
        return @ptrCast(new_waker);
    }
};

/// Waker list for managing multiple wakers
pub const WakerList = struct {
    wakers: std.ArrayList(WakerData),
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) WakerList {
        return WakerList{
            .wakers = std.ArrayList(WakerData){},
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *WakerList) void {
        // Drop all wakers
        for (self.wakers.items) |waker| {
            waker.drop();
        }
        self.wakers.deinit(self.allocator);
    }

    /// Register a waker
    pub fn register(self: *WakerList, waker: WakerData) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.wakers.append(self.allocator, waker);
    }

    /// Wake all registered wakers
    pub fn wakeAll(self: *WakerList) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.wakers.items) |waker| {
            waker.wakeByRef();
        }
    }

    /// Wake all and clear list
    pub fn wakeAllAndClear(self: *WakerList) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.wakers.items) |waker| {
            waker.wake();
        }
        self.wakers.clearRetainingCapacity();
    }

    /// Clear all wakers without waking
    pub fn clear(self: *WakerList) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.wakers.items) |waker| {
            waker.drop();
        }
        self.wakers.clearRetainingCapacity();
    }

    /// Get number of registered wakers
    pub fn count(self: *WakerList) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.wakers.items.len;
    }
};

/// Callback-based waker
pub const CallbackWaker = struct {
    callback: *const fn (*anyopaque) void,
    context: *anyopaque,
    allocator: ?std.mem.Allocator,

    const vtable = WakerVTable{
        .wake = wake,
        .wake_by_ref = wakeByRef,
        .drop = drop,
        .clone = clone,
    };

    pub fn init(callback: *const fn (*anyopaque) void, context: *anyopaque) CallbackWaker {
        return CallbackWaker{
            .callback = callback,
            .context = context,
            .allocator = null,
        };
    }

    pub fn toWakerData(self: *CallbackWaker) WakerData {
        return WakerData.init(@ptrCast(self), &vtable);
    }

    fn wake(ptr: *anyopaque) void {
        const self: *CallbackWaker = @ptrCast(@alignCast(ptr));
        self.callback(self.context);
    }

    fn wakeByRef(ptr: *anyopaque) void {
        const self: *CallbackWaker = @ptrCast(@alignCast(ptr));
        self.callback(self.context);
    }

    fn drop(ptr: *anyopaque) void {
        const self: *CallbackWaker = @ptrCast(@alignCast(ptr));
        if (self.allocator) |alloc| {
            alloc.destroy(self);
        }
    }

    fn clone(ptr: *anyopaque, allocator: std.mem.Allocator) !*anyopaque {
        const self: *CallbackWaker = @ptrCast(@alignCast(ptr));
        const new_waker = try allocator.create(CallbackWaker);
        new_waker.* = CallbackWaker{
            .callback = self.callback,
            .context = self.context,
            .allocator = allocator,
        };
        return @ptrCast(new_waker);
    }
};

/// No-op waker (for testing)
pub const NoopWaker = struct {
    const vtable = WakerVTable{
        .wake = wake,
        .wake_by_ref = wakeByRef,
        .drop = drop,
        .clone = clone,
    };

    pub fn init() NoopWaker {
        return NoopWaker{};
    }

    pub fn toWakerData(self: *NoopWaker) WakerData {
        return WakerData.init(@ptrCast(self), &vtable);
    }

    fn wake(_: *anyopaque) void {}
    fn wakeByRef(_: *anyopaque) void {}
    fn drop(_: *anyopaque) void {}

    fn clone(_: *anyopaque, allocator: std.mem.Allocator) !*anyopaque {
        const new_waker = try allocator.create(NoopWaker);
        new_waker.* = NoopWaker{};
        return @ptrCast(new_waker);
    }
};

/// Atomic waker (thread-safe single waker storage)
pub const AtomicWaker = struct {
    waker: ?WakerData,
    mutex: std.Thread.Mutex,

    pub fn init() AtomicWaker {
        return AtomicWaker{
            .waker = null,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *AtomicWaker) void {
        if (self.waker) |w| {
            w.drop();
        }
    }

    /// Register new waker (replaces old one)
    pub fn register(self: *AtomicWaker, waker: WakerData) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Drop old waker if exists
        if (self.waker) |old| {
            old.drop();
        }

        self.waker = waker;
    }

    /// Wake registered waker
    pub fn wake(self: *AtomicWaker) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.waker) |w| {
            w.wake();
            self.waker = null;
        }
    }

    /// Take waker without waking
    pub fn take(self: *AtomicWaker) ?WakerData {
        self.mutex.lock();
        defer self.mutex.unlock();

        const waker = self.waker;
        self.waker = null;
        return waker;
    }
};

/// Waker queue for batching wake operations
pub const WakerQueue = struct {
    queue: std.ArrayList(WakerData),
    allocator: std.mem.Allocator,
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) WakerQueue {
        return WakerQueue{
            .queue = std.ArrayList(WakerData){},
            .allocator = allocator,
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn deinit(self: *WakerQueue) void {
        for (self.queue.items) |waker| {
            waker.drop();
        }
        self.queue.deinit(self.allocator);
    }

    /// Enqueue waker
    pub fn enqueue(self: *WakerQueue, waker: WakerData) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.queue.append(self.allocator, waker);
    }

    /// Wake all enqueued wakers
    pub fn flush(self: *WakerQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.queue.items) |waker| {
            waker.wake();
        }
        self.queue.clearRetainingCapacity();
    }

    /// Get queue length
    pub fn len(self: *WakerQueue) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.queue.items.len;
    }
};
