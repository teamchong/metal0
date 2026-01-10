//! test.test_importlib.test_locks - Tests for import locks
//! Reference: cpython/Lib/test/test_importlib/test_locks.py

const std = @import("std");

pub const ImportLock = struct {
    const Self = @This();
    
    mutex: std.Thread.Mutex = .{},
    owner: ?std.Thread.Id = null,
    count: usize = 0,
    
    pub fn acquire(self: *Self) void {
        self.mutex.lock();
        self.owner = std.Thread.getCurrentId();
        self.count += 1;
    }
    
    pub fn release(self: *Self) void {
        if (self.count > 0) {
            self.count -= 1;
            if (self.count == 0) self.owner = null;
        }
        self.mutex.unlock();
    }
    
    pub fn is_held(self: *Self) bool {
        return self.count > 0;
    }
    
    pub fn held_by_current_thread(self: *Self) bool {
        if (self.owner) |owner| {
            return owner == std.Thread.getCurrentId();
        }
        return false;
    }
};

pub const ImportLockContext = struct {
    lock: *ImportLock,
    
    pub fn init(lock: *ImportLock) @This() {
        lock.acquire();
        return .{ .lock = lock };
    }
    
    pub fn deinit(self: @This()) void {
        self.lock.release();
    }
};

fn testImportLock() !void {
    var lock = ImportLock{};
    
    try std.testing.expect(!lock.is_held());
    
    lock.acquire();
    try std.testing.expect(lock.is_held());
    try std.testing.expect(lock.held_by_current_thread());
    try std.testing.expectEqual(@as(usize, 1), lock.count);
    
    lock.acquire();
    try std.testing.expectEqual(@as(usize, 2), lock.count);
    
    lock.release();
    try std.testing.expectEqual(@as(usize, 1), lock.count);
    
    lock.release();
    try std.testing.expect(!lock.is_held());
}

fn testImportLockContext() !void {
    var lock = ImportLock{};
    
    {
        const ctx = ImportLockContext.init(&lock);
        defer ctx.deinit();
        try std.testing.expect(lock.is_held());
    }
    
    try std.testing.expect(!lock.is_held());
}

test "import_lock" { try testImportLock(); }
test "import_lock_context" { try testImportLockContext(); }
