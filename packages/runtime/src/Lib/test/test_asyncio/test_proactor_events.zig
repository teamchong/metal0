//! test.test_asyncio.test_proactor_events - Tests for proactor event loops
//! Reference: cpython/Lib/test/test_asyncio/test_proactor_events.py
//!
//! Tests for IOCP/proactor-based event loops (Windows)

const std = @import("std");
const utils = @import("utils.zig");
const test_events = @import("test_events.zig");

// ============================================================================
// Proactor Interface
// ============================================================================

/// Abstract proactor interface
pub const AbstractProactor = struct {
    const Self = @This();

    vtable: *const VTable,

    pub const VTable = struct {
        recv: *const fn (*Self, usize) anyerror![]u8,
        send: *const fn (*Self, []const u8) anyerror!usize,
        accept: *const fn (*Self) anyerror!void,
        connect: *const fn (*Self, []const u8, u16) anyerror!void,
        close: *const fn (*Self) void,
    };
};

// ============================================================================
// Base Proactor Event Loop
// ============================================================================

/// Base class for proactor event loops
pub const BaseProactorEventLoop = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _proactor: ?*IocpProactor = null,
    _running: bool = false,
    _closed: bool = false,
    _self_reading_future: ?*test_events.Future = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self._proactor) |p| {
            p.deinit();
            self.allocator.destroy(p);
        }
    }

    pub fn is_running(self: *const Self) bool {
        return self._running;
    }

    pub fn is_closed(self: *const Self) bool {
        return self._closed;
    }

    pub fn run_forever(self: *Self) void {
        self._running = true;
        // Poll the proactor
        if (self._proactor) |p| {
            p.poll(null);
        }
        self._running = false;
    }

    pub fn stop(self: *Self) void {
        self._running = false;
    }

    pub fn close(self: *Self) void {
        self._running = false;
        self._closed = true;
    }

    pub fn set_proactor(self: *Self, proactor: *IocpProactor) void {
        self._proactor = proactor;
    }

    pub fn get_proactor(self: *const Self) ?*IocpProactor {
        return self._proactor;
    }
};

// ============================================================================
// IOCP Proactor
// ============================================================================

/// I/O Completion Port proactor
pub const IocpProactor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _iocp_handle: usize = 0,
    _registered: std.ArrayList(RegisteredHandle),
    _pending: std.ArrayList(PendingOp),
    _closed: bool = false,

    pub const RegisteredHandle = struct {
        handle: usize,
        data: ?*anyopaque,
    };

    pub const PendingOp = struct {
        op_type: OpType,
        handle: usize,
        completed: bool = false,
        result: ?usize = null,
    };

    pub const OpType = enum {
        recv,
        send,
        accept,
        connect,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._registered = std.ArrayList(RegisteredHandle).init(allocator),
            ._pending = std.ArrayList(PendingOp).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._registered.deinit();
        self._pending.deinit();
    }

    pub fn register(self: *Self, handle: usize, data: ?*anyopaque) !void {
        try self._registered.append(.{ .handle = handle, .data = data });
    }

    pub fn unregister(self: *Self, handle: usize) bool {
        for (self._registered.items, 0..) |item, i| {
            if (item.handle == handle) {
                _ = self._registered.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn poll(self: *Self, timeout: ?f64) void {
        _ = timeout;
        // Process completed operations
        var i: usize = 0;
        while (i < self._pending.items.len) {
            if (self._pending.items[i].completed) {
                _ = self._pending.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn recv(self: *Self, handle: usize, _: usize) !void {
        try self._pending.append(.{
            .op_type = .recv,
            .handle = handle,
        });
    }

    pub fn send(self: *Self, handle: usize, data: []const u8) !void {
        try self._pending.append(.{
            .op_type = .send,
            .handle = handle,
            .result = data.len,
        });
    }

    pub fn accept(self: *Self, handle: usize) !void {
        try self._pending.append(.{
            .op_type = .accept,
            .handle = handle,
        });
    }

    pub fn connect(self: *Self, handle: usize) !void {
        try self._pending.append(.{
            .op_type = .connect,
            .handle = handle,
        });
    }

    pub fn close(self: *Self) void {
        self._closed = true;
        self._pending.clearRetainingCapacity();
    }
};

// ============================================================================
// Proactor Transports
// ============================================================================

/// Base proactor transport
pub const ProactorTransport = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _proactor: *IocpProactor,
    _handle: usize,
    _closing: bool = false,
    _closed: bool = false,

    pub fn init(allocator: std.mem.Allocator, proactor: *IocpProactor, handle: usize) Self {
        return .{
            .allocator = allocator,
            ._proactor = proactor,
            ._handle = handle,
        };
    }

    pub fn is_closing(self: *const Self) bool {
        return self._closing;
    }

    pub fn close(self: *Self) void {
        self._closing = true;
        self._closed = true;
    }
};

// ============================================================================
// Test Cases
// ============================================================================

fn testBaseProactorEventLoop() !void {
    const allocator = std.testing.allocator;
    var loop = BaseProactorEventLoop.init(allocator);
    defer loop.deinit();

    try std.testing.expect(!loop.is_running());
    try std.testing.expect(!loop.is_closed());
}

fn testBaseProactorEventLoopClose() !void {
    const allocator = std.testing.allocator;
    var loop = BaseProactorEventLoop.init(allocator);
    defer loop.deinit();

    loop.close();
    try std.testing.expect(loop.is_closed());
}

fn testIocpProactor() !void {
    const allocator = std.testing.allocator;
    var proactor = IocpProactor.init(allocator);
    defer proactor.deinit();

    try proactor.register(42, null);
    try std.testing.expectEqual(@as(usize, 1), proactor._registered.items.len);
}

fn testIocpProactorUnregister() !void {
    const allocator = std.testing.allocator;
    var proactor = IocpProactor.init(allocator);
    defer proactor.deinit();

    try proactor.register(42, null);
    const removed = proactor.unregister(42);
    try std.testing.expect(removed);
}

fn testIocpProactorRecv() !void {
    const allocator = std.testing.allocator;
    var proactor = IocpProactor.init(allocator);
    defer proactor.deinit();

    try proactor.recv(42, 1024);
    try std.testing.expectEqual(@as(usize, 1), proactor._pending.items.len);
    try std.testing.expectEqual(IocpProactor.OpType.recv, proactor._pending.items[0].op_type);
}

fn testIocpProactorSend() !void {
    const allocator = std.testing.allocator;
    var proactor = IocpProactor.init(allocator);
    defer proactor.deinit();

    try proactor.send(42, "hello");
    try std.testing.expectEqual(@as(usize, 1), proactor._pending.items.len);
    try std.testing.expectEqual(IocpProactor.OpType.send, proactor._pending.items[0].op_type);
}

fn testIocpProactorPoll() !void {
    const allocator = std.testing.allocator;
    var proactor = IocpProactor.init(allocator);
    defer proactor.deinit();

    try proactor.recv(42, 1024);
    proactor._pending.items[0].completed = true;
    proactor.poll(null);

    try std.testing.expectEqual(@as(usize, 0), proactor._pending.items.len);
}

fn testProactorTransport() !void {
    const allocator = std.testing.allocator;
    var proactor = IocpProactor.init(allocator);
    defer proactor.deinit();

    var transport = ProactorTransport.init(allocator, &proactor, 42);

    try std.testing.expect(!transport.is_closing());
    transport.close();
    try std.testing.expect(transport.is_closing());
}

fn testBaseProactorWithProactor() !void {
    const allocator = std.testing.allocator;
    var loop = BaseProactorEventLoop.init(allocator);
    defer loop.deinit();

    var proactor = try allocator.create(IocpProactor);
    proactor.* = IocpProactor.init(allocator);
    loop.set_proactor(proactor);

    try std.testing.expect(loop.get_proactor() != null);
}

fn testIocpProactorClose() !void {
    const allocator = std.testing.allocator;
    var proactor = IocpProactor.init(allocator);
    defer proactor.deinit();

    try proactor.recv(42, 1024);
    proactor.close();

    try std.testing.expect(proactor._closed);
    try std.testing.expectEqual(@as(usize, 0), proactor._pending.items.len);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "BaseProactorEventLoop" {
    try testBaseProactorEventLoop();
}

test "BaseProactorEventLoop close" {
    try testBaseProactorEventLoopClose();
}

test "IocpProactor" {
    try testIocpProactor();
}

test "IocpProactor unregister" {
    try testIocpProactorUnregister();
}

test "IocpProactor recv" {
    try testIocpProactorRecv();
}

test "IocpProactor send" {
    try testIocpProactorSend();
}

test "IocpProactor poll" {
    try testIocpProactorPoll();
}

test "ProactorTransport" {
    try testProactorTransport();
}

test "BaseProactor with proactor" {
    try testBaseProactorWithProactor();
}

test "IocpProactor close" {
    try testIocpProactorClose();
}
