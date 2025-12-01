//! Async Socket - Goroutine-style non-blocking I/O
//!
//! How it works:
//! 1. Socket is set to non-blocking mode
//! 2. When read/write would block, register fd with netpoller
//! 3. Green thread parks (yields to scheduler)
//! 4. When I/O is ready, netpoller wakes the green thread

const std = @import("std");
const builtin = @import("builtin");

// Netpoller for async I/O (kqueue on macOS, epoll on Linux)
const Netpoller = @import("netpoller").Netpoller;
const IoOp = @import("netpoller").IoOp;
const GreenThread = @import("green_thread").GreenThread;

/// Async socket with goroutine-style I/O
pub const AsyncSocket = struct {
    fd: std.posix.socket_t,
    allocator: std.mem.Allocator,
    netpoller: *Netpoller,
    green_thread: *GreenThread,

    /// Initialize async socket with netpoller and green thread
    pub fn init(
        allocator: std.mem.Allocator,
        fd: std.posix.socket_t,
        netpoller: *Netpoller,
        green_thread: *GreenThread,
    ) !AsyncSocket {
        // Set socket to non-blocking mode
        if (builtin.os.tag != .windows) {
            const flags = std.posix.fcntl(fd, std.posix.F.GETFL, 0) catch 0;
            _ = std.posix.fcntl(fd, std.posix.F.SETFL, @as(u32, @bitCast(flags)) | std.posix.O.NONBLOCK) catch {};
        }

        return .{
            .fd = fd,
            .allocator = allocator,
            .netpoller = netpoller,
            .green_thread = green_thread,
        };
    }

    pub fn deinit(self: *AsyncSocket) void {
        _ = self;
    }

    /// Park green thread until socket is readable
    fn parkForRead(self: *AsyncSocket) !void {
        try self.netpoller.register(self.fd, IoOp.read, self.green_thread);
    }

    /// Park green thread until socket is writable
    fn parkForWrite(self: *AsyncSocket) !void {
        try self.netpoller.register(self.fd, IoOp.write, self.green_thread);
    }

    /// Read data, parking if would block
    pub fn read(self: *AsyncSocket, buffer: []u8) !usize {
        while (true) {
            const result = std.posix.read(self.fd, buffer);
            if (result) |n| {
                return n;
            } else |err| {
                switch (err) {
                    error.WouldBlock => {
                        try self.parkForRead();
                        continue;
                    },
                    else => return err,
                }
            }
        }
    }

    /// Write all data, parking if would block
    pub fn writeAll(self: *AsyncSocket, data: []const u8) !void {
        var written: usize = 0;
        while (written < data.len) {
            const result = std.posix.write(self.fd, data[written..]);
            if (result) |n| {
                written += n;
            } else |err| {
                switch (err) {
                    error.WouldBlock => {
                        try self.parkForWrite();
                        continue;
                    },
                    else => return err,
                }
            }
        }
    }

    /// Connect, parking if would block
    pub fn connect(self: *AsyncSocket, addr: *const std.posix.sockaddr, len: std.posix.socklen_t) !void {
        const result = std.posix.connect(self.fd, addr, len);
        if (result) |_| {
            return;
        } else |err| {
            switch (err) {
                error.WouldBlock => {
                    try self.parkForWrite();
                    var so_error: c_int = 0;
                    var opt_len: std.posix.socklen_t = @sizeOf(c_int);
                    _ = std.posix.getsockopt(self.fd, std.posix.SOL.SOCKET, std.posix.SO.ERROR, @ptrCast(&so_error), &opt_len) catch {};
                    if (so_error != 0) return error.ConnectionRefused;
                },
                else => return err,
            }
        }
    }
};

/// Create a non-blocking socket
pub fn createNonBlockingSocket(domain: u32, socket_type: u32, protocol: u32) !std.posix.socket_t {
    return try std.posix.socket(domain, socket_type | std.posix.SOCK.NONBLOCK, protocol);
}

/// Connect to host:port with goroutine-style async
pub fn connectAsync(
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    netpoller: *Netpoller,
    green_thread: *GreenThread,
) !AsyncSocket {
    const list = std.net.getAddressList(allocator, host, port) catch return error.DnsLookupFailed;
    defer list.deinit();

    if (list.addrs.len == 0) return error.NoAddressFound;

    const fd = try createNonBlockingSocket(
        list.addrs[0].any.family,
        std.posix.SOCK.STREAM,
        0,
    );
    errdefer std.posix.close(fd);

    var socket = try AsyncSocket.init(allocator, fd, netpoller, green_thread);
    try socket.connect(&list.addrs[0].any, list.addrs[0].getOsSockLen());

    return socket;
}

test "AsyncSocket creation" {
    _ = AsyncSocket;
}
