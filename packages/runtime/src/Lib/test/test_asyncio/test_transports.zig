//! test.test_asyncio.test_transports - Tests for asyncio transports
//! Reference: cpython/Lib/test/test_asyncio/test_transports.py
//!
//! Tests for Transport, ReadTransport, WriteTransport interfaces

const std = @import("std");
const posix = std.posix;
const utils = @import("utils.zig");

// ============================================================================
// Transport Interfaces
// ============================================================================

/// Base transport interface
pub const BaseTransport = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    _extra_info: std.StringHashMap([]const u8),
    _closing: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            ._extra_info = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._extra_info.deinit();
    }

    pub fn get_extra_info(self: *const Self, name: []const u8, default: ?[]const u8) ?[]const u8 {
        return self._extra_info.get(name) orelse default;
    }

    pub fn set_extra_info(self: *Self, name: []const u8, value: []const u8) !void {
        try self._extra_info.put(name, value);
    }

    pub fn is_closing(self: *const Self) bool {
        return self._closing;
    }

    pub fn close(self: *Self) void {
        self._closing = true;
    }

    pub fn set_protocol(self: *Self, protocol: anytype) void {
        _ = protocol;
        _ = self;
    }

    pub fn get_protocol(self: *const Self) ?*anyopaque {
        _ = self;
        return null;
    }
};

/// Read-only transport
pub const ReadTransport = struct {
    const Self = @This();

    base: BaseTransport,
    _paused: bool = false,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = BaseTransport.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    pub fn is_reading(self: *const Self) bool {
        return !self._paused;
    }

    pub fn pause_reading(self: *Self) void {
        self._paused = true;
    }

    pub fn resume_reading(self: *Self) void {
        self._paused = false;
    }
};

/// Write-only transport
pub const WriteTransport = struct {
    const Self = @This();

    base: BaseTransport,
    _write_buffer: std.ArrayList(u8),
    _write_buffer_size: usize = 0,
    _high_water: usize = 64 * 1024,
    _low_water: usize = 16 * 1024,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = BaseTransport.init(allocator),
            ._write_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._write_buffer.deinit();
        self.base.deinit();
    }

    pub fn write(self: *Self, data: []const u8) !void {
        if (self.base._closing) {
            return error.TransportClosing;
        }
        try self._write_buffer.appendSlice(data);
        self._write_buffer_size += data.len;
    }

    pub fn writelines(self: *Self, lines: []const []const u8) !void {
        for (lines) |line| {
            try self.write(line);
        }
    }

    pub fn write_eof(self: *Self) void {
        _ = self;
        // Signal EOF on write side
    }

    pub fn can_write_eof(self: *const Self) bool {
        _ = self;
        return true;
    }

    pub fn get_write_buffer_size(self: *const Self) usize {
        return self._write_buffer_size;
    }

    pub fn get_write_buffer_limits(self: *const Self) struct { low: usize, high: usize } {
        return .{ .low = self._low_water, .high = self._high_water };
    }

    pub fn set_write_buffer_limits(self: *Self, high: ?usize, low: ?usize) void {
        if (high) |h| self._high_water = h;
        if (low) |l| self._low_water = l;
    }

    pub fn abort(self: *Self) void {
        self._write_buffer.clearRetainingCapacity();
        self._write_buffer_size = 0;
        self.base._closing = true;
    }
};

/// Full duplex transport (read + write)
pub const Transport = struct {
    const Self = @This();

    read: ReadTransport,
    write: WriteTransport,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .read = ReadTransport.init(allocator),
            .write = WriteTransport.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.read.deinit();
        self.write.deinit();
    }

    // Delegate to read transport
    pub fn is_reading(self: *const Self) bool {
        return self.read.is_reading();
    }

    pub fn pause_reading(self: *Self) void {
        self.read.pause_reading();
    }

    pub fn resume_reading(self: *Self) void {
        self.read.resume_reading();
    }

    // Delegate to write transport
    pub fn writeData(self: *Self, data: []const u8) !void {
        try self.write.write(data);
    }

    pub fn close(self: *Self) void {
        self.read.base.close();
        self.write.base.close();
    }

    pub fn is_closing(self: *const Self) bool {
        return self.read.base.is_closing() or self.write.base.is_closing();
    }
};

/// Datagram transport (UDP)
pub const DatagramTransport = struct {
    const Self = @This();

    base: BaseTransport,
    _datagrams_sent: std.ArrayList(SentDatagram),

    pub const SentDatagram = struct {
        data: []const u8,
        addr: ?[]const u8,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = BaseTransport.init(allocator),
            ._datagrams_sent = std.ArrayList(SentDatagram).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self._datagrams_sent.deinit();
        self.base.deinit();
    }

    pub fn sendto(self: *Self, data: []const u8, addr: ?[]const u8) !void {
        if (self.base._closing) {
            return error.TransportClosing;
        }
        try self._datagrams_sent.append(.{ .data = data, .addr = addr });
    }

    pub fn abort(self: *Self) void {
        self._datagrams_sent.clearRetainingCapacity();
        self.base._closing = true;
    }
};

/// Subprocess transport
pub const SubprocessTransport = struct {
    const Self = @This();

    base: BaseTransport,
    _pid: ?posix.pid_t = null,
    _returncode: ?i32 = null,
    _stdin_pipe: ?*WriteTransport = null,
    _stdout_pipe: ?*ReadTransport = null,
    _stderr_pipe: ?*ReadTransport = null,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .base = BaseTransport.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.base.deinit();
    }

    pub fn get_pid(self: *const Self) ?posix.pid_t {
        return self._pid;
    }

    pub fn get_returncode(self: *const Self) ?i32 {
        return self._returncode;
    }

    pub fn get_pipe_transport(self: *Self, fd: i32) ?*anyopaque {
        return switch (fd) {
            0 => if (self._stdin_pipe) |p| @ptrCast(p) else null,
            1 => if (self._stdout_pipe) |p| @ptrCast(p) else null,
            2 => if (self._stderr_pipe) |p| @ptrCast(p) else null,
            else => null,
        };
    }

    pub fn send_signal(self: *Self, sig: i32) !void {
        if (self._pid) |pid| {
            _ = posix.kill(pid, @intCast(sig)) catch {};
        }
    }

    pub fn terminate(self: *Self) !void {
        try self.send_signal(posix.SIG.TERM);
    }

    pub fn kill(self: *Self) !void {
        try self.send_signal(posix.SIG.KILL);
    }
};

// ============================================================================
// Test Cases
// ============================================================================

fn testBaseTransport() !void {
    const allocator = std.testing.allocator;
    var transport = BaseTransport.init(allocator);
    defer transport.deinit();

    try std.testing.expect(!transport.is_closing());
    transport.close();
    try std.testing.expect(transport.is_closing());
}

fn testBaseTransportExtraInfo() !void {
    const allocator = std.testing.allocator;
    var transport = BaseTransport.init(allocator);
    defer transport.deinit();

    try transport.set_extra_info("peername", "127.0.0.1:8080");
    try std.testing.expectEqualStrings(
        "127.0.0.1:8080",
        transport.get_extra_info("peername", null).?,
    );

    // Test default value
    try std.testing.expectEqualStrings(
        "default",
        transport.get_extra_info("missing", "default").?,
    );
}

fn testReadTransport() !void {
    const allocator = std.testing.allocator;
    var transport = ReadTransport.init(allocator);
    defer transport.deinit();

    try std.testing.expect(transport.is_reading());
    transport.pause_reading();
    try std.testing.expect(!transport.is_reading());
    transport.resume_reading();
    try std.testing.expect(transport.is_reading());
}

fn testWriteTransport() !void {
    const allocator = std.testing.allocator;
    var transport = WriteTransport.init(allocator);
    defer transport.deinit();

    try transport.write("hello");
    try std.testing.expectEqual(@as(usize, 5), transport.get_write_buffer_size());

    try transport.write(" world");
    try std.testing.expectEqual(@as(usize, 11), transport.get_write_buffer_size());
}

fn testWriteTransportLimits() !void {
    const allocator = std.testing.allocator;
    var transport = WriteTransport.init(allocator);
    defer transport.deinit();

    const limits = transport.get_write_buffer_limits();
    try std.testing.expectEqual(@as(usize, 16 * 1024), limits.low);
    try std.testing.expectEqual(@as(usize, 64 * 1024), limits.high);

    transport.set_write_buffer_limits(128 * 1024, 32 * 1024);
    const new_limits = transport.get_write_buffer_limits();
    try std.testing.expectEqual(@as(usize, 32 * 1024), new_limits.low);
    try std.testing.expectEqual(@as(usize, 128 * 1024), new_limits.high);
}

fn testWriteTransportAbort() !void {
    const allocator = std.testing.allocator;
    var transport = WriteTransport.init(allocator);
    defer transport.deinit();

    try transport.write("data");
    try std.testing.expect(!transport.base.is_closing());

    transport.abort();
    try std.testing.expect(transport.base.is_closing());
    try std.testing.expectEqual(@as(usize, 0), transport.get_write_buffer_size());
}

fn testTransport() !void {
    const allocator = std.testing.allocator;
    var transport = Transport.init(allocator);
    defer transport.deinit();

    try std.testing.expect(transport.is_reading());
    try std.testing.expect(!transport.is_closing());

    transport.pause_reading();
    try std.testing.expect(!transport.is_reading());

    transport.close();
    try std.testing.expect(transport.is_closing());
}

fn testDatagramTransport() !void {
    const allocator = std.testing.allocator;
    var transport = DatagramTransport.init(allocator);
    defer transport.deinit();

    try transport.sendto("hello", "127.0.0.1:8080");
    try std.testing.expectEqual(@as(usize, 1), transport._datagrams_sent.items.len);
}

fn testDatagramTransportAbort() !void {
    const allocator = std.testing.allocator;
    var transport = DatagramTransport.init(allocator);
    defer transport.deinit();

    try transport.sendto("data", null);
    transport.abort();

    try std.testing.expect(transport.base.is_closing());
    try std.testing.expectEqual(@as(usize, 0), transport._datagrams_sent.items.len);
}

fn testSubprocessTransport() !void {
    const allocator = std.testing.allocator;
    var transport = SubprocessTransport.init(allocator);
    defer transport.deinit();

    try std.testing.expect(transport.get_pid() == null);
    try std.testing.expect(transport.get_returncode() == null);
}

// ============================================================================
// Zig Test Declarations
// ============================================================================

test "BaseTransport" {
    try testBaseTransport();
}

test "BaseTransport extra_info" {
    try testBaseTransportExtraInfo();
}

test "ReadTransport" {
    try testReadTransport();
}

test "WriteTransport" {
    try testWriteTransport();
}

test "WriteTransport limits" {
    try testWriteTransportLimits();
}

test "WriteTransport abort" {
    try testWriteTransportAbort();
}

test "Transport" {
    try testTransport();
}

test "DatagramTransport" {
    try testDatagramTransport();
}

test "DatagramTransport abort" {
    try testDatagramTransportAbort();
}

test "SubprocessTransport" {
    try testSubprocessTransport();
}
