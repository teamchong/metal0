//! Pipe - Bidirectional communication
const std = @import("std");

/// A bidirectional pipe connection
pub const Connection = struct {
    const Self = @This();

    reader: std.posix.fd_t,
    writer: std.posix.fd_t,
    closed: bool,

    pub fn init(reader: std.posix.fd_t, writer: std.posix.fd_t) Self {
        return .{
            .reader = reader,
            .writer = writer,
            .closed = false,
        };
    }

    /// Send data through the pipe
    pub fn send(self: *Self, data: []const u8) !void {
        if (self.closed) return error.ConnectionClosed;
        _ = try std.posix.write(self.writer, data);
    }

    /// Receive data from the pipe
    pub fn recv(self: *Self, buffer: []u8) !usize {
        if (self.closed) return error.ConnectionClosed;
        return std.posix.read(self.reader, buffer);
    }

    /// Check if data is available using POSIX poll()
    pub fn poll(self: *Self, timeout: ?f64) !bool {
        if (self.closed) return false;

        // Convert timeout to milliseconds for poll()
        const timeout_ms: i32 = if (timeout) |t|
            if (t < 0) -1 else @intFromFloat(t * 1000)
        else
            -1; // Infinite wait

        var fds = [1]std.posix.pollfd{
            .{
                .fd = self.reader,
                .events = std.posix.POLL.IN,
                .revents = 0,
            },
        };

        const result = std.posix.poll(&fds, timeout_ms) catch return false;
        if (result > 0) {
            return (fds[0].revents & std.posix.POLL.IN) != 0;
        }
        return false; // Timeout
    }

    /// Close the connection
    pub fn close(self: *Self) void {
        if (!self.closed) {
            std.posix.close(self.reader);
            std.posix.close(self.writer);
            self.closed = true;
        }
    }

    /// Get file descriptor for select/poll
    pub fn fileno(self: *Self) std.posix.fd_t {
        return self.reader;
    }
};

/// Create a pipe returning two connection objects
pub fn Pipe(duplex: bool) !struct { Connection, Connection } {
    _ = duplex;

    const pipe1 = try std.posix.pipe();
    const pipe2 = try std.posix.pipe();

    const conn1 = Connection.init(pipe1[0], pipe2[1]);
    const conn2 = Connection.init(pipe2[0], pipe1[1]);

    return .{ conn1, conn2 };
}
