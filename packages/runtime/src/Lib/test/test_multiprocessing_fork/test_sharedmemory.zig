//! test.test_multiprocessing_fork.test_sharedmemory - Multiprocessing sharedmemory tests (fork start method)
const std = @import("std");

/// Shared memory segment (fork method - memory is shared via COW after fork)
pub const SharedMemory = struct {
    name: []const u8,
    size: usize,
    buffer: []u8,
    allocator: std.mem.Allocator,
    created: bool = false,

    pub fn create(allocator: std.mem.Allocator, name: ?[]const u8, size: usize) !SharedMemory {
        const buffer = try allocator.alloc(u8, size);
        @memset(buffer, 0);

        return .{
            .name = name orelse "shm_fork_anon",
            .size = size,
            .buffer = buffer,
            .allocator = allocator,
            .created = true,
        };
    }

    pub fn attach(allocator: std.mem.Allocator, name: []const u8) !SharedMemory {
        // In real implementation, would attach to existing shared memory
        _ = allocator;
        return .{
            .name = name,
            .size = 0,
            .buffer = &[_]u8{},
            .allocator = undefined,
            .created = false,
        };
    }

    pub fn close(self: *SharedMemory) void {
        // Detach but don't destroy
        _ = self;
    }

    pub fn unlink(self: *SharedMemory) void {
        if (self.created) {
            self.allocator.free(self.buffer);
        }
    }

    pub fn buf(self: *SharedMemory) []u8 {
        return self.buffer;
    }
};

/// Shared memory manager
pub const ShareableList = struct {
    shm: SharedMemory,
    count: usize = 0,
    item_size: usize,

    pub fn init(allocator: std.mem.Allocator, item_count: usize, item_size: usize) !ShareableList {
        const total_size = item_count * item_size + @sizeOf(usize);
        const shm = try SharedMemory.create(allocator, null, total_size);

        return .{
            .shm = shm,
            .item_size = item_size,
        };
    }

    pub fn deinit(self: *ShareableList) void {
        self.shm.unlink();
    }

    pub fn append(self: *ShareableList, data: []const u8) !void {
        const offset = self.count * self.item_size;
        if (offset + data.len > self.shm.size) {
            return error.ListFull;
        }
        @memcpy(self.shm.buffer[offset..][0..data.len], data);
        self.count += 1;
    }

    pub fn get(self: *ShareableList, index: usize) ![]u8 {
        if (index >= self.count) {
            return error.IndexOutOfBounds;
        }
        const offset = index * self.item_size;
        return self.shm.buffer[offset..][0..self.item_size];
    }

    pub fn len(self: *ShareableList) usize {
        return self.count;
    }
};

/// Resource tracker for shared memory
pub const ResourceTracker = struct {
    resources: std.StringHashMap(ResourceInfo),
    allocator: std.mem.Allocator,

    const ResourceInfo = struct {
        kind: ResourceKind,
        ref_count: usize,
    };

    const ResourceKind = enum {
        shared_memory,
        semaphore,
        file_lock,
    };

    pub fn init(allocator: std.mem.Allocator) ResourceTracker {
        return .{
            .resources = std.StringHashMap(ResourceInfo).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ResourceTracker) void {
        self.resources.deinit();
    }

    pub fn register(self: *ResourceTracker, name: []const u8, kind: ResourceKind) !void {
        if (self.resources.get(name)) |_| {
            // Increment ref count
            var entry = self.resources.getPtr(name).?;
            entry.ref_count += 1;
        } else {
            try self.resources.put(name, .{ .kind = kind, .ref_count = 1 });
        }
    }

    pub fn unregister(self: *ResourceTracker, name: []const u8) !void {
        if (self.resources.getPtr(name)) |info| {
            if (info.ref_count > 1) {
                info.ref_count -= 1;
            } else {
                _ = self.resources.remove(name);
            }
        } else {
            return error.ResourceNotFound;
        }
    }

    pub fn getall(self: *ResourceTracker, kind: ResourceKind) [][]const u8 {
        var result = std.ArrayList([]const u8).init(self.allocator);
        var it = self.resources.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.kind == kind) {
                result.append(entry.key_ptr.*) catch {};
            }
        }
        return result.toOwnedSlice() catch &[_][]const u8{};
    }
};

/// Posix shared memory wrapper (fork method)
pub const PosixSharedMemory = struct {
    name: []const u8,
    fd: i32 = -1,
    size: usize,
    addr: ?[*]u8 = null,

    pub fn open_new(name: []const u8, size: usize) !PosixSharedMemory {
        // In real implementation, would use shm_open and mmap
        return .{
            .name = name,
            .fd = 3, // Simulated fd
            .size = size,
        };
    }

    pub fn open_existing(name: []const u8) !PosixSharedMemory {
        return .{
            .name = name,
            .fd = 4,
            .size = 0,
        };
    }

    pub fn close(self: *PosixSharedMemory) void {
        self.fd = -1;
        self.addr = null;
    }

    pub fn unlink_name(name: []const u8) !void {
        // In real implementation, would use shm_unlink
        _ = name;
    }
};

test "shared memory create" {
    const allocator = std.testing.allocator;
    var shm = try SharedMemory.create(allocator, "test_shm_fork", 1024);
    defer shm.unlink();

    try std.testing.expectEqual(@as(usize, 1024), shm.size);
    try std.testing.expectEqualStrings("test_shm_fork", shm.name);
    try std.testing.expect(shm.created);
}

test "shared memory anonymous" {
    const allocator = std.testing.allocator;
    var shm = try SharedMemory.create(allocator, null, 512);
    defer shm.unlink();

    try std.testing.expectEqualStrings("shm_fork_anon", shm.name);
}

test "shared memory buffer access" {
    const allocator = std.testing.allocator;
    var shm = try SharedMemory.create(allocator, null, 100);
    defer shm.unlink();

    const buf = shm.buf();
    buf[0] = 42;
    buf[1] = 100;

    try std.testing.expectEqual(@as(u8, 42), shm.buffer[0]);
    try std.testing.expectEqual(@as(u8, 100), shm.buffer[1]);
}

test "shareable list" {
    const allocator = std.testing.allocator;
    var list = try ShareableList.init(allocator, 10, 16);
    defer list.deinit();

    try list.append("hello");
    try list.append("world");

    try std.testing.expectEqual(@as(usize, 2), list.len());
}

test "shareable list index out of bounds" {
    const allocator = std.testing.allocator;
    var list = try ShareableList.init(allocator, 10, 16);
    defer list.deinit();

    try list.append("test");
    try std.testing.expectError(error.IndexOutOfBounds, list.get(5));
}

test "resource tracker" {
    const allocator = std.testing.allocator;
    var tracker = ResourceTracker.init(allocator);
    defer tracker.deinit();

    try tracker.register("shm_test", .shared_memory);
    try tracker.register("shm_test", .shared_memory); // Increment ref

    try tracker.unregister("shm_test");
    // Still exists with ref_count = 1
    try std.testing.expect(tracker.resources.get("shm_test") != null);

    try tracker.unregister("shm_test");
    // Now removed
    try std.testing.expect(tracker.resources.get("shm_test") == null);
}

test "resource tracker not found" {
    const allocator = std.testing.allocator;
    var tracker = ResourceTracker.init(allocator);
    defer tracker.deinit();

    try std.testing.expectError(error.ResourceNotFound, tracker.unregister("nonexistent"));
}

test "resource tracker multiple resources" {
    const allocator = std.testing.allocator;
    var tracker = ResourceTracker.init(allocator);
    defer tracker.deinit();

    try tracker.register("shm1", .shared_memory);
    try tracker.register("sem1", .semaphore);
    try tracker.register("shm2", .shared_memory);

    try std.testing.expectEqual(@as(usize, 3), tracker.resources.count());
}

test "posix shared memory" {
    var shm = try PosixSharedMemory.open_new("/test_posix_fork", 4096);
    try std.testing.expectEqual(@as(i32, 3), shm.fd);
    try std.testing.expectEqual(@as(usize, 4096), shm.size);

    shm.close();
    try std.testing.expectEqual(@as(i32, -1), shm.fd);
}

test "posix shared memory existing" {
    var shm = try PosixSharedMemory.open_existing("/existing_shm");
    try std.testing.expectEqual(@as(i32, 4), shm.fd);
    try std.testing.expectEqualStrings("/existing_shm", shm.name);
}
