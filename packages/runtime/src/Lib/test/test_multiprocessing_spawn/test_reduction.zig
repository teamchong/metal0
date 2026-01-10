//! test.test_multiprocessing_spawn.test_reduction - Multiprocessing reduction tests
const std = @import("std");

/// Reduction registry for pickling objects
pub const ForkingPickler = struct {
    buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ForkingPickler {
        return .{
            .buffer = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ForkingPickler) void {
        self.buffer.deinit();
    }

    pub fn dumps(self: *ForkingPickler, obj: anytype) ![]u8 {
        // Simple serialization
        const T = @TypeOf(obj);
        const bytes = std.mem.asBytes(&obj);
        try self.buffer.appendSlice(bytes);
        _ = T;
        return self.buffer.toOwnedSlice();
    }

    pub fn loads(self: *ForkingPickler, comptime T: type, data: []const u8) !T {
        _ = self;
        if (data.len < @sizeOf(T)) {
            return error.InvalidData;
        }
        return std.mem.bytesToValue(T, data[0..@sizeOf(T)]);
    }
};

/// Reduce registry for custom reduction functions
pub const ReduceRegistry = struct {
    const ReduceFn = *const fn (anytype) anyerror![]u8;
    const ReconstructFn = *const fn ([]const u8) anyerror!void;

    reducers: std.StringHashMap(ReduceFn),
    reconstructors: std.StringHashMap(ReconstructFn),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ReduceRegistry {
        return .{
            .reducers = std.StringHashMap(ReduceFn).init(allocator),
            .reconstructors = std.StringHashMap(ReconstructFn).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ReduceRegistry) void {
        self.reducers.deinit();
        self.reconstructors.deinit();
    }

    pub fn register(self: *ReduceRegistry, type_name: []const u8, reducer: ReduceFn, reconstructor: ReconstructFn) !void {
        try self.reducers.put(type_name, reducer);
        try self.reconstructors.put(type_name, reconstructor);
    }

    pub fn get_reducer(self: *ReduceRegistry, type_name: []const u8) ?ReduceFn {
        return self.reducers.get(type_name);
    }

    pub fn get_reconstructor(self: *ReduceRegistry, type_name: []const u8) ?ReconstructFn {
        return self.reconstructors.get(type_name);
    }
};

/// Abstract reducer for common types
pub fn AbstractReducer(comptime T: type) type {
    return struct {
        pub fn reduce(obj: T, allocator: std.mem.Allocator) ![]u8 {
            const bytes = std.mem.asBytes(&obj);
            const result = try allocator.alloc(u8, bytes.len);
            @memcpy(result, bytes);
            return result;
        }

        pub fn reconstruct(data: []const u8) !T {
            if (data.len < @sizeOf(T)) {
                return error.InvalidData;
            }
            return std.mem.bytesToValue(T, data[0..@sizeOf(T)]);
        }
    };
}

/// Dump object for sending between processes
pub fn dump(obj: anytype, allocator: std.mem.Allocator) ![]u8 {
    const T = @TypeOf(obj);
    const Reducer = AbstractReducer(T);
    return Reducer.reduce(obj, allocator);
}

/// Load object from received data
pub fn load(comptime T: type, data: []const u8) !T {
    const Reducer = AbstractReducer(T);
    return Reducer.reconstruct(data);
}

/// Rebuild connection from reduced form
pub const RebuildConnection = struct {
    handle: i32,
    readable: bool,
    writable: bool,

    pub fn rebuild(self: RebuildConnection) Connection {
        return .{
            .handle = self.handle,
            .readable = self.readable,
            .writable = self.writable,
        };
    }
};

/// Connection stub for reduction
pub const Connection = struct {
    handle: i32,
    readable: bool = true,
    writable: bool = true,

    pub fn reduce(self: Connection) RebuildConnection {
        return .{
            .handle = self.handle,
            .readable = self.readable,
            .writable = self.writable,
        };
    }
};

/// Reduce a file handle
pub const FileReduction = struct {
    fd: i32,
    mode: []const u8,
    offset: i64,

    pub fn from_file(fd: i32, mode: []const u8, offset: i64) FileReduction {
        return .{
            .fd = fd,
            .mode = mode,
            .offset = offset,
        };
    }

    pub fn to_file(self: FileReduction) struct { fd: i32, mode: []const u8 } {
        return .{
            .fd = self.fd,
            .mode = self.mode,
        };
    }
};

/// Reduce a socket
pub const SocketReduction = struct {
    fd: i32,
    family: i32,
    sock_type: i32,
    protocol: i32,

    pub fn from_socket(fd: i32, family: i32, sock_type: i32, protocol: i32) SocketReduction {
        return .{
            .fd = fd,
            .family = family,
            .sock_type = sock_type,
            .protocol = protocol,
        };
    }
};

/// Reduce a lock
pub const LockReduction = struct {
    locked: bool,
    owner: ?i32,

    pub fn from_lock(locked: bool, owner: ?i32) LockReduction {
        return .{
            .locked = locked,
            .owner = owner,
        };
    }

    pub fn to_lock(self: LockReduction) struct { locked: bool, owner: ?i32 } {
        return .{
            .locked = self.locked,
            .owner = self.owner,
        };
    }
};

test "forking pickler" {
    const allocator = std.testing.allocator;
    var pickler = ForkingPickler.init(allocator);
    defer pickler.deinit();

    const value: i32 = 42;
    const data = try pickler.dumps(value);
    defer allocator.free(data);

    var pickler2 = ForkingPickler.init(allocator);
    defer pickler2.deinit();
    const restored = try pickler2.loads(i32, data);
    try std.testing.expectEqual(@as(i32, 42), restored);
}

test "abstract reducer" {
    const allocator = std.testing.allocator;

    const Point = struct { x: i32, y: i32 };
    const Reducer = AbstractReducer(Point);

    const p = Point{ .x = 10, .y = 20 };
    const data = try Reducer.reduce(p, allocator);
    defer allocator.free(data);

    const restored = try Reducer.reconstruct(data);
    try std.testing.expectEqual(@as(i32, 10), restored.x);
    try std.testing.expectEqual(@as(i32, 20), restored.y);
}

test "dump and load" {
    const allocator = std.testing.allocator;

    const value: f64 = 3.14159;
    const data = try dump(value, allocator);
    defer allocator.free(data);

    const restored = try load(f64, data);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14159), restored, 0.00001);
}

test "connection reduction" {
    const conn = Connection{ .handle = 5, .readable = true, .writable = false };
    const reduced = conn.reduce();

    try std.testing.expectEqual(@as(i32, 5), reduced.handle);
    try std.testing.expect(reduced.readable);
    try std.testing.expect(!reduced.writable);

    const rebuilt = reduced.rebuild();
    try std.testing.expectEqual(@as(i32, 5), rebuilt.handle);
}

test "file reduction" {
    const reduced = FileReduction.from_file(7, "r", 100);
    try std.testing.expectEqual(@as(i32, 7), reduced.fd);
    try std.testing.expectEqualStrings("r", reduced.mode);
    try std.testing.expectEqual(@as(i64, 100), reduced.offset);

    const restored = reduced.to_file();
    try std.testing.expectEqual(@as(i32, 7), restored.fd);
}

test "socket reduction" {
    const reduced = SocketReduction.from_socket(8, 2, 1, 0);
    try std.testing.expectEqual(@as(i32, 8), reduced.fd);
    try std.testing.expectEqual(@as(i32, 2), reduced.family);
    try std.testing.expectEqual(@as(i32, 1), reduced.sock_type);
}

test "lock reduction" {
    const reduced = LockReduction.from_lock(true, 1234);
    try std.testing.expect(reduced.locked);
    try std.testing.expectEqual(@as(?i32, 1234), reduced.owner);

    const restored = reduced.to_lock();
    try std.testing.expect(restored.locked);
}
