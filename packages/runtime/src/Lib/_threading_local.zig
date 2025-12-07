//! CPython source: Lib/_threading_local.py
//!
//! Provides thread-local storage implementation.
//!
//! Mirrors: CPython Lib/_threading_local.py

const std = @import("std");

// ============================================================================
// Thread Local Storage
// ============================================================================

/// Thread-local data storage
pub fn local(comptime T: type) type {
    return struct {
        const Self = @This();

        /// Storage per thread
        storage: std.Thread.LocalStorage(T),

        pub fn init() Self {
            return .{
                .storage = std.Thread.LocalStorage(T){},
            };
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        /// Get thread-local value
        pub fn get(self: *Self) ?*T {
            return self.storage.get();
        }

        /// Set thread-local value
        pub fn set(self: *Self, value: T) void {
            self.storage.set(value);
        }
    };
}

// ============================================================================
// _localimpl - Implementation detail
// ============================================================================

/// Implementation of thread-local storage
pub const _localimpl = struct {
    const Self = @This();

    /// Thread-specific dictionary storage
    dicts: std.AutoHashMap(std.Thread.Id, std.StringHashMap([]const u8)),
    allocator: std.mem.Allocator,
    key: []const u8,
    lock: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .dicts = std.AutoHashMap(std.Thread.Id, std.StringHashMap([]const u8)).init(allocator),
            .allocator = allocator,
            .key = "",
            .lock = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.dicts.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.dicts.deinit();
    }

    /// Get dictionary for current thread
    pub fn getDict(self: *Self) !*std.StringHashMap([]const u8) {
        self.lock.lock();
        defer self.lock.unlock();

        const tid = std.Thread.getCurrentId();

        if (self.dicts.getPtr(tid)) |dict| {
            return dict;
        }

        // Create new dictionary for this thread
        try self.dicts.put(tid, std.StringHashMap([]const u8).init(self.allocator));
        return self.dicts.getPtr(tid).?;
    }

    /// Create new dictionary for current thread
    pub fn createDict(self: *Self) !*std.StringHashMap([]const u8) {
        self.lock.lock();
        defer self.lock.unlock();

        const tid = std.Thread.getCurrentId();

        // Remove old dict if exists
        if (self.dicts.fetchRemove(tid)) |entry| {
            var dict = entry.value;
            dict.deinit();
        }

        // Create new dictionary
        try self.dicts.put(tid, std.StringHashMap([]const u8).init(self.allocator));
        return self.dicts.getPtr(tid).?;
    }
};

// ============================================================================
// Local class
// ============================================================================

/// Thread-local object that supports attribute access
pub const Local = struct {
    const Self = @This();

    impl: _localimpl,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .impl = _localimpl.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.impl.deinit();
    }

    /// Get attribute value
    pub fn getattr(self: *Self, name: []const u8) !?[]const u8 {
        const dict = try self.impl.getDict();
        return dict.get(name);
    }

    /// Set attribute value
    pub fn setattr(self: *Self, name: []const u8, value: []const u8) !void {
        const dict = try self.impl.getDict();
        try dict.put(name, value);
    }

    /// Delete attribute
    pub fn delattr(self: *Self, name: []const u8) !void {
        const dict = try self.impl.getDict();
        _ = dict.remove(name);
    }

    /// Get the thread-local dictionary
    pub fn getDict(self: *Self) !*std.StringHashMap([]const u8) {
        return self.impl.getDict();
    }
};

// ============================================================================
// RLock wrapper
// ============================================================================

/// Reentrant lock for thread safety
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

    pub fn acquire(self: *Self) void {
        const tid = std.Thread.getCurrentId();

        if (self.owner == tid) {
            self.count += 1;
            return;
        }

        self.mutex.lock();
        self.owner = tid;
        self.count = 1;
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

    /// Context manager support
    pub fn __enter__(self: *Self) *Self {
        self.acquire();
        return self;
    }

    pub fn __exit__(self: *Self) void {
        self.release();
    }
};

// ============================================================================
// Helper functions
// ============================================================================

/// Get current thread ID
pub fn currentThread() std.Thread.Id {
    return std.Thread.getCurrentId();
}

// ============================================================================
// Tests
// ============================================================================

test "Local init and deinit" {
    const allocator = std.testing.allocator;
    var l = Local.init(allocator);
    defer l.deinit();
}

test "Local setattr and getattr" {
    const allocator = std.testing.allocator;
    var l = Local.init(allocator);
    defer l.deinit();

    try l.setattr("test_key", "test_value");
    const value = try l.getattr("test_key");
    try std.testing.expectEqualStrings("test_value", value.?);
}

test "Local getattr missing" {
    const allocator = std.testing.allocator;
    var l = Local.init(allocator);
    defer l.deinit();

    const value = try l.getattr("nonexistent");
    try std.testing.expect(value == null);
}

test "Local delattr" {
    const allocator = std.testing.allocator;
    var l = Local.init(allocator);
    defer l.deinit();

    try l.setattr("key", "value");
    try l.delattr("key");
    const value = try l.getattr("key");
    try std.testing.expect(value == null);
}

test "RLock init" {
    var lock = RLock.init();
    try std.testing.expect(lock.owner == null);
    try std.testing.expectEqual(@as(usize, 0), lock.count);
}

test "RLock acquire and release" {
    var lock = RLock.init();

    lock.acquire();
    try std.testing.expect(lock.owner != null);
    try std.testing.expectEqual(@as(usize, 1), lock.count);

    lock.release();
    try std.testing.expect(lock.owner == null);
    try std.testing.expectEqual(@as(usize, 0), lock.count);
}

test "RLock reentrant" {
    var lock = RLock.init();

    lock.acquire();
    lock.acquire();
    try std.testing.expectEqual(@as(usize, 2), lock.count);

    lock.release();
    try std.testing.expectEqual(@as(usize, 1), lock.count);

    lock.release();
    try std.testing.expectEqual(@as(usize, 0), lock.count);
}

test "_localimpl init" {
    const allocator = std.testing.allocator;
    var impl = _localimpl.init(allocator);
    defer impl.deinit();
}

test "currentThread" {
    const tid = currentThread();
    try std.testing.expect(tid != 0);
}
