//! test.test_capi.test_module4 - C API Module Tests Part 4 - Memory Management
const std = @import("std");

/// Object header with refcount
pub const PyObjectHeader = struct {
    ob_refcnt: usize = 1,
    ob_type: ?*const TypeInfo = null,

    pub fn incref(self: *PyObjectHeader) void {
        self.ob_refcnt += 1;
    }

    pub fn decref(self: *PyObjectHeader) bool {
        if (self.ob_refcnt > 0) {
            self.ob_refcnt -= 1;
            return self.ob_refcnt == 0;
        }
        return true;
    }
};

/// Type info for runtime type checking
pub const TypeInfo = struct {
    name: []const u8,
    size: usize,
    flags: u32 = 0,
};

/// Memory pool for small allocations
pub const PyMemoryPool = struct {
    pools: [NUM_POOLS]Pool,
    allocator: std.mem.Allocator,

    const NUM_POOLS = 8;
    const POOL_SIZE = 4096;

    const Pool = struct {
        data: []u8,
        used: usize = 0,
        block_size: usize,

        pub fn alloc(self: *Pool) ?[]u8 {
            if (self.used + self.block_size <= self.data.len) {
                const result = self.data[self.used..][0..self.block_size];
                self.used += self.block_size;
                return result;
            }
            return null;
        }

        pub fn reset(self: *Pool) void {
            self.used = 0;
        }
    };

    pub fn init(allocator: std.mem.Allocator) !PyMemoryPool {
        var result = PyMemoryPool{
            .pools = undefined,
            .allocator = allocator,
        };

        for (&result.pools, 0..) |*pool, i| {
            const block_size = (i + 1) * 8;
            pool.data = try allocator.alloc(u8, POOL_SIZE);
            pool.used = 0;
            pool.block_size = block_size;
        }

        return result;
    }

    pub fn deinit(self: *PyMemoryPool) void {
        for (&self.pools) |*pool| {
            self.allocator.free(pool.data);
        }
    }

    pub fn alloc(self: *PyMemoryPool, size: usize) ?[]u8 {
        const pool_idx = (size + 7) / 8;
        if (pool_idx > 0 and pool_idx <= NUM_POOLS) {
            return self.pools[pool_idx - 1].alloc();
        }
        return null;
    }
};

/// Object allocator
pub const PyObjectAllocator = struct {
    allocator: std.mem.Allocator,
    allocated_count: usize = 0,
    freed_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator) PyObjectAllocator {
        return .{ .allocator = allocator };
    }

    pub fn alloc(self: *PyObjectAllocator, comptime T: type) !*T {
        const obj = try self.allocator.create(T);
        self.allocated_count += 1;
        return obj;
    }

    pub fn free(self: *PyObjectAllocator, ptr: anytype) void {
        self.allocator.destroy(ptr);
        self.freed_count += 1;
    }

    pub fn stats(self: *const PyObjectAllocator) struct { allocated: usize, freed: usize, live: usize } {
        return .{
            .allocated = self.allocated_count,
            .freed = self.freed_count,
            .live = self.allocated_count - self.freed_count,
        };
    }
};

/// GC tracked object
pub const GCObject = struct {
    header: PyObjectHeader = .{},
    gc_next: ?*GCObject = null,
    gc_prev: ?*GCObject = null,
    gc_refs: i32 = 0,
    tracked: bool = false,

    pub fn track(self: *GCObject, list: *GCList) void {
        if (list.head) |head| {
            self.gc_next = head;
            head.gc_prev = self;
        }
        list.head = self;
        self.tracked = true;
        list.count += 1;
    }

    pub fn untrack(self: *GCObject, list: *GCList) void {
        if (self.gc_prev) |prev| {
            prev.gc_next = self.gc_next;
        } else {
            list.head = self.gc_next;
        }
        if (self.gc_next) |next| {
            next.gc_prev = self.gc_prev;
        }
        self.tracked = false;
        list.count -= 1;
    }
};

/// GC object list
pub const GCList = struct {
    head: ?*GCObject = null,
    count: usize = 0,

    pub fn init() GCList {
        return .{};
    }

    pub fn len(self: *const GCList) usize {
        return self.count;
    }
};

test "PyObjectHeader refcount" {
    var header = PyObjectHeader{};
    try std.testing.expectEqual(@as(usize, 1), header.ob_refcnt);

    header.incref();
    try std.testing.expectEqual(@as(usize, 2), header.ob_refcnt);

    try std.testing.expect(!header.decref());
    try std.testing.expectEqual(@as(usize, 1), header.ob_refcnt);

    try std.testing.expect(header.decref());
}

test "PyMemoryPool" {
    const allocator = std.testing.allocator;
    var pool = try PyMemoryPool.init(allocator);
    defer pool.deinit();

    const block = pool.alloc(16);
    try std.testing.expect(block != null);
    try std.testing.expectEqual(@as(usize, 16), block.?.len);
}

test "PyObjectAllocator" {
    const allocator = std.testing.allocator;
    var obj_alloc = PyObjectAllocator.init(allocator);

    const TestStruct = struct { value: i32 };
    const obj = try obj_alloc.alloc(TestStruct);
    obj.value = 42;

    var stats = obj_alloc.stats();
    try std.testing.expectEqual(@as(usize, 1), stats.allocated);
    try std.testing.expectEqual(@as(usize, 1), stats.live);

    obj_alloc.free(obj);
    stats = obj_alloc.stats();
    try std.testing.expectEqual(@as(usize, 0), stats.live);
}

test "GCList tracking" {
    var list = GCList.init();
    var obj1 = GCObject{};
    var obj2 = GCObject{};

    obj1.track(&list);
    try std.testing.expectEqual(@as(usize, 1), list.len());
    try std.testing.expect(obj1.tracked);

    obj2.track(&list);
    try std.testing.expectEqual(@as(usize, 2), list.len());

    obj1.untrack(&list);
    try std.testing.expectEqual(@as(usize, 1), list.len());
    try std.testing.expect(!obj1.tracked);
}
