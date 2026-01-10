//! test.test_multiprocessing_spawn.test_manager - Multiprocessing manager tests
const std = @import("std");

/// Manager for sharing data between processes
pub const Manager = struct {
    allocator: std.mem.Allocator,
    address: ?[]const u8 = null,
    authkey: ?[]const u8 = null,
    started: bool = false,

    pub fn init(allocator: std.mem.Allocator) Manager {
        return .{ .allocator = allocator };
    }

    pub fn start(self: *Manager) !void {
        self.started = true;
        self.address = "localhost:5000";
    }

    pub fn shutdown(self: *Manager) void {
        self.started = false;
        self.address = null;
    }

    pub fn connect(self: *Manager) !void {
        if (!self.started) return error.ManagerNotStarted;
    }

    /// Create a shared dict
    pub fn dict(self: *Manager) !ManagedDict {
        if (!self.started) return error.ManagerNotStarted;
        return ManagedDict.init(self.allocator);
    }

    /// Create a shared list
    pub fn list(self: *Manager) !ManagedList {
        if (!self.started) return error.ManagerNotStarted;
        return ManagedList.init(self.allocator);
    }

    /// Create a shared value
    pub fn Value(self: *Manager, comptime T: type, initial: T) !ManagedValue(T) {
        if (!self.started) return error.ManagerNotStarted;
        return ManagedValue(T){ .value = initial };
    }

    /// Create a shared namespace
    pub fn Namespace(self: *Manager) !ManagedNamespace {
        if (!self.started) return error.ManagerNotStarted;
        return ManagedNamespace.init(self.allocator);
    }

    /// Create a shared queue
    pub fn Queue(self: *Manager) !ManagedQueue {
        if (!self.started) return error.ManagerNotStarted;
        return ManagedQueue.init(self.allocator);
    }

    /// Create a shared lock
    pub fn Lock(self: *Manager) !ManagedLock {
        if (!self.started) return error.ManagerNotStarted;
        return ManagedLock{};
    }

    /// Create a shared event
    pub fn Event(self: *Manager) !ManagedEvent {
        if (!self.started) return error.ManagerNotStarted;
        return ManagedEvent{};
    }
};

/// Managed dictionary
pub const ManagedDict = struct {
    data: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) ManagedDict {
        return .{ .data = std.StringHashMap([]const u8).init(allocator) };
    }

    pub fn deinit(self: *ManagedDict) void {
        self.data.deinit();
    }

    pub fn get(self: *ManagedDict, key: []const u8) ?[]const u8 {
        return self.data.get(key);
    }

    pub fn put(self: *ManagedDict, key: []const u8, value: []const u8) !void {
        try self.data.put(key, value);
    }

    pub fn remove(self: *ManagedDict, key: []const u8) bool {
        return self.data.remove(key);
    }

    pub fn keys(self: *ManagedDict) std.StringHashMap([]const u8).KeyIterator {
        return self.data.keyIterator();
    }

    pub fn len(self: *ManagedDict) usize {
        return self.data.count();
    }
};

/// Managed list
pub const ManagedList = struct {
    items: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) ManagedList {
        return .{ .items = std.ArrayList([]const u8).init(allocator) };
    }

    pub fn deinit(self: *ManagedList) void {
        self.items.deinit();
    }

    pub fn append(self: *ManagedList, item: []const u8) !void {
        try self.items.append(item);
    }

    pub fn get(self: *ManagedList, index: usize) ?[]const u8 {
        if (index >= self.items.items.len) return null;
        return self.items.items[index];
    }

    pub fn pop(self: *ManagedList) ?[]const u8 {
        return self.items.popOrNull();
    }

    pub fn len(self: *ManagedList) usize {
        return self.items.items.len;
    }
};

/// Managed value
pub fn ManagedValue(comptime T: type) type {
    return struct {
        value: T,
        mutex: std.Thread.Mutex = .{},

        pub fn get(self: *@This()) T {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.value;
        }

        pub fn set(self: *@This(), v: T) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            self.value = v;
        }
    };
}

/// Managed namespace for attribute storage
pub const ManagedNamespace = struct {
    attrs: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) ManagedNamespace {
        return .{ .attrs = std.StringHashMap([]const u8).init(allocator) };
    }

    pub fn deinit(self: *ManagedNamespace) void {
        self.attrs.deinit();
    }

    pub fn setAttr(self: *ManagedNamespace, name: []const u8, value: []const u8) !void {
        try self.attrs.put(name, value);
    }

    pub fn getAttr(self: *ManagedNamespace, name: []const u8) ?[]const u8 {
        return self.attrs.get(name);
    }
};

/// Managed queue
pub const ManagedQueue = struct {
    items: std.ArrayList([]const u8),
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator) ManagedQueue {
        return .{ .items = std.ArrayList([]const u8).init(allocator) };
    }

    pub fn deinit(self: *ManagedQueue) void {
        self.items.deinit();
    }

    pub fn put(self: *ManagedQueue, item: []const u8) !void {
        self.mutex.lock();
        defer self.mutex.unlock();
        try self.items.append(item);
    }

    pub fn get(self: *ManagedQueue) ![]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.items.items.len == 0) return error.Empty;
        return self.items.orderedRemove(0);
    }
};

/// Managed lock
pub const ManagedLock = struct {
    mutex: std.Thread.Mutex = .{},

    pub fn acquire(self: *ManagedLock) void {
        self.mutex.lock();
    }

    pub fn release(self: *ManagedLock) void {
        self.mutex.unlock();
    }

    pub fn locked(self: *ManagedLock) bool {
        if (self.mutex.tryLock()) {
            self.mutex.unlock();
            return false;
        }
        return true;
    }
};

/// Managed event
pub const ManagedEvent = struct {
    is_set: bool = false,
    mutex: std.Thread.Mutex = .{},

    pub fn set(self: *ManagedEvent) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.is_set = true;
    }

    pub fn clear(self: *ManagedEvent) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.is_set = false;
    }

    pub fn isSet(self: *ManagedEvent) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.is_set;
    }
};

/// Sync manager for remote connections
pub const SyncManager = struct {
    address: []const u8,
    authkey: ?[]const u8,
    connected: bool = false,

    pub fn init(address: []const u8, authkey: ?[]const u8) SyncManager {
        return .{ .address = address, .authkey = authkey };
    }

    pub fn connect(self: *SyncManager) !void {
        self.connected = true;
    }

    pub fn shutdown(self: *SyncManager) void {
        self.connected = false;
    }
};

test "manager lifecycle" {
    const allocator = std.testing.allocator;
    var mgr = Manager.init(allocator);

    try std.testing.expect(!mgr.started);
    try mgr.start();
    try std.testing.expect(mgr.started);

    mgr.shutdown();
    try std.testing.expect(!mgr.started);
}

test "managed dict" {
    const allocator = std.testing.allocator;
    var mgr = Manager.init(allocator);
    try mgr.start();
    defer mgr.shutdown();

    var d = try mgr.dict();
    defer d.deinit();

    try d.put("key1", "value1");
    try std.testing.expectEqualStrings("value1", d.get("key1").?);
    try std.testing.expectEqual(@as(usize, 1), d.len());
}

test "managed list" {
    const allocator = std.testing.allocator;
    var mgr = Manager.init(allocator);
    try mgr.start();
    defer mgr.shutdown();

    var l = try mgr.list();
    defer l.deinit();

    try l.append("item1");
    try l.append("item2");
    try std.testing.expectEqual(@as(usize, 2), l.len());
    try std.testing.expectEqualStrings("item1", l.get(0).?);
}

test "managed value" {
    const allocator = std.testing.allocator;
    var mgr = Manager.init(allocator);
    try mgr.start();
    defer mgr.shutdown();

    var v = try mgr.Value(i32, 42);
    try std.testing.expectEqual(@as(i32, 42), v.get());
    v.set(100);
    try std.testing.expectEqual(@as(i32, 100), v.get());
}

test "managed event" {
    const allocator = std.testing.allocator;
    var mgr = Manager.init(allocator);
    try mgr.start();
    defer mgr.shutdown();

    var e = try mgr.Event();
    try std.testing.expect(!e.isSet());
    e.set();
    try std.testing.expect(e.isSet());
}
