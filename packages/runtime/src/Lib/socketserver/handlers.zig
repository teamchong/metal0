//! Request handler implementations
//!
//! Mirrors: CPython Lib/socketserver.py (BaseRequestHandler, StreamRequestHandler, DatagramRequestHandler)

const std = @import("std");

// ============================================================================
// Request Handlers
// ============================================================================

/// Base request handler
pub const BaseRequestHandler = struct {
    const Self = @This();

    request: ?*anyopaque,
    client_address: ?std.net.Address,
    server: ?*anyopaque,

    pub fn init(request: ?*anyopaque, client_address: ?std.net.Address, server: ?*anyopaque) Self {
        var self = Self{
            .request = request,
            .client_address = client_address,
            .server = server,
        };
        self.setup();
        self.handle();
        self.finish();
        return self;
    }

    pub fn setup(self: *Self) void {
        _ = self;
    }

    pub fn handle(self: *Self) void {
        _ = self;
    }

    pub fn finish(self: *Self) void {
        _ = self;
    }
};

/// Stream request handler (for TCP)
pub const StreamRequestHandler = struct {
    const Self = @This();

    base: BaseRequestHandler,
    connection: ?std.posix.socket_t,
    rbufsize: usize,
    wbufsize: usize,
    timeout: ?f64,
    disable_nagle_algorithm: bool,
    // Buffered I/O state
    read_buffer: [8192]u8,
    read_pos: usize,
    read_end: usize,
    write_buffer: [8192]u8,
    write_pos: usize,

    pub fn init(request: ?*anyopaque, client_address: ?std.net.Address, server: ?*anyopaque) Self {
        return .{
            .base = BaseRequestHandler.init(request, client_address, server),
            .connection = null,
            .rbufsize = 8192,
            .wbufsize = 8192,
            .timeout = null,
            .disable_nagle_algorithm = false,
            .read_buffer = undefined,
            .read_pos = 0,
            .read_end = 0,
            .write_buffer = undefined,
            .write_pos = 0,
        };
    }

    pub fn setup(self: *Self, conn: std.posix.socket_t) void {
        self.base.setup();
        self.connection = conn;
        self.read_pos = 0;
        self.read_end = 0;
        self.write_pos = 0;

        // Disable Nagle algorithm if requested (for lower latency)
        if (self.disable_nagle_algorithm) {
            std.posix.setsockopt(conn, std.posix.IPPROTO.TCP, std.posix.TCP.NODELAY, &std.mem.toBytes(@as(c_int, 1))) catch {};
        }

        // Set socket timeout if specified
        if (self.timeout) |timeout_secs| {
            const timeout_us: i64 = @intFromFloat(timeout_secs * 1_000_000);
            const tv = std.posix.timeval{
                .tv_sec = @intCast(@divFloor(timeout_us, 1_000_000)),
                .tv_usec = @intCast(@mod(timeout_us, 1_000_000)),
            };
            std.posix.setsockopt(conn, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&tv)) catch {};
            std.posix.setsockopt(conn, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, std.mem.asBytes(&tv)) catch {};
        }
    }

    /// Read from buffered input
    pub fn read(self: *Self, buf: []u8) !usize {
        if (self.connection == null) return error.NotConnected;

        // If buffer is empty, refill it
        if (self.read_pos >= self.read_end) {
            const n = std.posix.recv(self.connection.?, &self.read_buffer, 0) catch |err| {
                if (err == error.WouldBlock) return 0;
                return err;
            };
            if (n == 0) return 0; // EOF
            self.read_pos = 0;
            self.read_end = n;
        }

        // Copy from buffer to output
        const available = self.read_end - self.read_pos;
        const to_copy = @min(available, buf.len);
        @memcpy(buf[0..to_copy], self.read_buffer[self.read_pos..][0..to_copy]);
        self.read_pos += to_copy;
        return to_copy;
    }

    /// Read a line from buffered input
    pub fn readline(self: *Self, buf: []u8) ![]u8 {
        var pos: usize = 0;
        while (pos < buf.len) {
            var byte: [1]u8 = undefined;
            const n = try self.read(&byte);
            if (n == 0) break; // EOF
            buf[pos] = byte[0];
            pos += 1;
            if (byte[0] == '\n') break;
        }
        return buf[0..pos];
    }

    /// Write to buffered output
    pub fn write(self: *Self, data: []const u8) !usize {
        if (self.connection == null) return error.NotConnected;

        var written: usize = 0;
        for (data) |byte| {
            self.write_buffer[self.write_pos] = byte;
            self.write_pos += 1;

            // Flush if buffer is full
            if (self.write_pos >= self.write_buffer.len) {
                try self.flush();
            }
            written += 1;
        }
        return written;
    }

    /// Flush write buffer to socket
    pub fn flush(self: *Self) !void {
        if (self.connection == null) return error.NotConnected;
        if (self.write_pos == 0) return;

        var sent: usize = 0;
        while (sent < self.write_pos) {
            const n = std.posix.send(self.connection.?, self.write_buffer[sent..self.write_pos], 0) catch |err| {
                if (err == error.WouldBlock) continue;
                return err;
            };
            sent += n;
        }
        self.write_pos = 0;
    }

    pub fn finish(self: *Self) void {
        // Flush any remaining write buffer
        self.flush() catch {};
        self.base.finish();
    }
};

/// Datagram request handler (for UDP)
pub const DatagramRequestHandler = struct {
    const Self = @This();

    base: BaseRequestHandler,
    packet: ?[]const u8,
    socket: ?std.posix.socket_t,

    pub fn init(request: ?*anyopaque, client_address: ?std.net.Address, server: ?*anyopaque) Self {
        return .{
            .base = BaseRequestHandler.init(request, client_address, server),
            .packet = null,
            .socket = null,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "BaseRequestHandler" {
    const handler = BaseRequestHandler.init(null, null, null);
    try std.testing.expect(handler.request == null);
}

test "StreamRequestHandler" {
    const handler = StreamRequestHandler.init(null, null, null);
    try std.testing.expect(handler.connection == null);
    try std.testing.expectEqual(@as(usize, 8192), handler.rbufsize);
}

test "DatagramRequestHandler" {
    const handler = DatagramRequestHandler.init(null, null, null);
    try std.testing.expect(handler.packet == null);
}
