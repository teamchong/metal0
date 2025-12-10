// WebSocket Client Implementation
// Maps to Python's websockets library

const std = @import("std");
const protocol = @import("protocol.zig");
const Opcode = protocol.Opcode;
const WebSocketHeader = protocol.WebSocketHeader;
const CloseCode = protocol.CloseCode;

// TLS support for wss://
const tls = @import("../../shared/http/h2/tls.zig");
const TlsConnection = tls.TlsConnection;

pub const WebSocketError = error{
    ConnectionFailed,
    HandshakeFailed,
    InvalidResponse,
    ConnectionClosed,
    InvalidFrame,
    MessageTooLarge,
    ProtocolError,
    Timeout,
    TlsError,
    TlsHandshakeFailed,
};

pub const State = enum {
    Connecting,
    Open,
    Closing,
    Closed,
};

pub const Message = struct {
    data: []const u8,
    is_binary: bool,

    pub fn text(data: []const u8) Message {
        return .{ .data = data, .is_binary = false };
    }

    pub fn binary(data: []const u8) Message {
        return .{ .data = data, .is_binary = true };
    }
};

pub const WebSocketClient = struct {
    allocator: std.mem.Allocator,
    stream: ?std.net.Stream = null,
    tls_conn: ?*TlsConnection = null, // TLS connection for wss://
    is_tls: bool = false, // Whether using TLS
    state: State = .Closed,
    uri: std.Uri,
    buffer: std.ArrayList(u8),
    max_message_size: usize = 16 * 1024 * 1024, // 16MB default

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, url: []const u8) !Self {
        const uri = try std.Uri.parse(url);
        const is_tls = std.mem.eql(u8, uri.scheme, "wss");
        return Self{
            .allocator = allocator,
            .uri = uri,
            .buffer = std.ArrayList(u8).init(allocator),
            .is_tls = is_tls,
        };
    }

    pub fn deinit(self: *Self) void {
        self.close() catch {};
        self.buffer.deinit();
        if (self.tls_conn) |tls_c| {
            tls_c.deinit();
            self.tls_conn = null;
        }
    }

    pub fn connect(self: *Self) !void {
        if (self.state != .Closed) return;

        self.state = .Connecting;
        errdefer self.state = .Closed;

        const host = self.uri.host orelse return WebSocketError.ConnectionFailed;
        const port: u16 = self.uri.port orelse if (self.is_tls) @as(u16, 443) else @as(u16, 80);

        const address = try std.net.Address.resolveIp(host, port);
        self.stream = try std.net.tcpConnectToAddress(address);

        // Perform TLS handshake if wss://
        if (self.is_tls) {
            const socket = self.stream.?.handle;
            self.tls_conn = TlsConnection.init(self.allocator, socket, null, null) catch {
                return WebSocketError.TlsError;
            };

            // Perform TLS 1.3 handshake (no ALPN for WebSocket)
            self.tls_conn.?.handshake(host, &[_][]const u8{}) catch {
                if (self.tls_conn) |tc| {
                    tc.deinit();
                    self.tls_conn = null;
                }
                return WebSocketError.TlsHandshakeFailed;
            };
        }

        try self.performHandshake();
        self.state = .Open;
    }

    fn performHandshake(self: *Self) !void {
        // Generate WebSocket key
        var key_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&key_bytes);
        var key_encoded: [24]u8 = undefined;
        _ = std.base64.standard.Encoder.encode(&key_encoded, &key_bytes);

        const host = self.uri.host orelse return WebSocketError.ConnectionFailed;
        const path = if (self.uri.path.len > 0) self.uri.path else "/";

        // Build HTTP upgrade request
        var request_buf: [2048]u8 = undefined;
        const request = std.fmt.bufPrint(&request_buf,
            "GET {s} HTTP/1.1\r\n" ++
            "Host: {s}\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: {s}\r\n" ++
            "Sec-WebSocket-Version: 13\r\n" ++
            "\r\n",
            .{path, host, key_encoded}
        ) catch return WebSocketError.ConnectionFailed;

        // Send through TLS or raw socket
        try self.writeAll(request);

        // Read response
        var response_buf: [4096]u8 = undefined;
        var total_read: usize = 0;

        while (total_read < response_buf.len) {
            const n = try self.readSome(response_buf[total_read..]);
            if (n == 0) return WebSocketError.ConnectionClosed;
            total_read += n;

            // Check for end of headers
            if (std.mem.indexOf(u8, response_buf[0..total_read], "\r\n\r\n")) |_| {
                break;
            }
        }

        const response = response_buf[0..total_read];

        // Verify 101 Switching Protocols
        if (!std.mem.startsWith(u8, response, "HTTP/1.1 101")) {
            return WebSocketError.HandshakeFailed;
        }

        // Verify Upgrade header
        if (std.mem.indexOf(u8, response, "Upgrade: websocket") == null and
            std.mem.indexOf(u8, response, "upgrade: websocket") == null)
        {
            return WebSocketError.HandshakeFailed;
        }
    }

    // Helper to write data through TLS or raw socket
    fn writeAll(self: *Self, data: []const u8) !void {
        if (self.tls_conn) |tls_c| {
            tls_c.send(data) catch return WebSocketError.TlsError;
        } else if (self.stream) |stream| {
            stream.writer().writeAll(data) catch return WebSocketError.ConnectionFailed;
        } else {
            return WebSocketError.ConnectionClosed;
        }
    }

    // Helper to read data through TLS or raw socket
    fn readSome(self: *Self, buffer: []u8) !usize {
        if (self.tls_conn) |tls_c| {
            return tls_c.recv(buffer) catch return WebSocketError.TlsError;
        } else if (self.stream) |stream| {
            return stream.reader().read(buffer) catch return WebSocketError.ConnectionFailed;
        } else {
            return WebSocketError.ConnectionClosed;
        }
    }

    // Helper to read all bytes
    fn readAll(self: *Self, buffer: []u8) !void {
        var total: usize = 0;
        while (total < buffer.len) {
            const n = try self.readSome(buffer[total..]);
            if (n == 0) return WebSocketError.ConnectionClosed;
            total += n;
        }
    }

    pub fn send(self: *Self, message: Message) !void {
        if (self.state != .Open) return WebSocketError.ConnectionClosed;

        const opcode: Opcode = if (message.is_binary) .Binary else .Text;
        const payload_len = message.data.len;

        // Client must mask all frames
        const header = WebSocketHeader{
            .final = true,
            .opcode = opcode,
            .mask = true,
            .len = WebSocketHeader.packLength(payload_len),
        };

        // Serialize header to buffer
        var header_buf: [14]u8 = undefined; // Max header size
        var header_len: usize = 2;

        header_buf[0] = (@as(u8, if (header.final) 0x80 else 0)) | @intFromEnum(header.opcode);
        header_buf[1] = (@as(u8, if (header.mask) 0x80 else 0)) | @as(u7, @truncate(header.len));

        if (header.len == 126) {
            const len16: u16 = @intCast(payload_len);
            header_buf[2] = @truncate(len16 >> 8);
            header_buf[3] = @truncate(len16);
            header_len = 4;
        } else if (header.len == 127) {
            const len64: u64 = @intCast(payload_len);
            header_buf[2] = @truncate(len64 >> 56);
            header_buf[3] = @truncate(len64 >> 48);
            header_buf[4] = @truncate(len64 >> 40);
            header_buf[5] = @truncate(len64 >> 32);
            header_buf[6] = @truncate(len64 >> 24);
            header_buf[7] = @truncate(len64 >> 16);
            header_buf[8] = @truncate(len64 >> 8);
            header_buf[9] = @truncate(len64);
            header_len = 10;
        }

        try self.writeAll(header_buf[0..header_len]);

        // Write mask
        const mask = protocol.generateMask();
        try self.writeAll(&mask);

        // Write masked payload
        const masked_data = try self.allocator.alloc(u8, payload_len);
        defer self.allocator.free(masked_data);
        @memcpy(masked_data, message.data);
        protocol.applyMask(masked_data, mask);
        try self.writeAll(masked_data);
    }

    pub fn sendText(self: *Self, data: []const u8) !void {
        try self.send(Message.text(data));
    }

    pub fn sendBinary(self: *Self, data: []const u8) !void {
        try self.send(Message.binary(data));
    }

    pub fn recv(self: *Self) !Message {
        if (self.state != .Open) return WebSocketError.ConnectionClosed;

        // Read header
        var header_bytes: [2]u8 = undefined;
        try self.readAll(&header_bytes);
        const header = WebSocketHeader.fromSlice(header_bytes);

        // Read extended length
        var payload_len: usize = header.len;
        if (header.len == 126) {
            var len_bytes: [2]u8 = undefined;
            try self.readAll(&len_bytes);
            payload_len = (@as(usize, len_bytes[0]) << 8) | len_bytes[1];
        } else if (header.len == 127) {
            var len_bytes: [8]u8 = undefined;
            try self.readAll(&len_bytes);
            payload_len = (@as(usize, len_bytes[0]) << 56) |
                (@as(usize, len_bytes[1]) << 48) |
                (@as(usize, len_bytes[2]) << 40) |
                (@as(usize, len_bytes[3]) << 32) |
                (@as(usize, len_bytes[4]) << 24) |
                (@as(usize, len_bytes[5]) << 16) |
                (@as(usize, len_bytes[6]) << 8) |
                len_bytes[7];
        }

        if (payload_len > self.max_message_size) {
            return WebSocketError.MessageTooLarge;
        }

        // Read mask if present (server shouldn't mask, but handle it)
        var mask: ?[4]u8 = null;
        if (header.mask) {
            var mask_bytes: [4]u8 = undefined;
            try self.readAll(&mask_bytes);
            mask = mask_bytes;
        }

        // Read payload
        const payload = try self.allocator.alloc(u8, payload_len);
        try self.readAll(payload);

        if (mask) |m| {
            protocol.applyMask(payload, m);
        }

        // Handle control frames
        if (header.opcode.isControl()) {
            defer self.allocator.free(payload);

            switch (header.opcode) {
                .Ping => {
                    try self.sendPong(payload);
                    return self.recv(); // Continue to next message
                },
                .Pong => {
                    return self.recv(); // Ignore pong, get next message
                },
                .Close => {
                    self.state = .Closed;
                    return WebSocketError.ConnectionClosed;
                },
                else => return WebSocketError.ProtocolError,
            }
        }

        return Message{
            .data = payload,
            .is_binary = header.opcode == .Binary,
        };
    }

    fn sendPong(self: *Self, data: []const u8) !void {
        try self.sendControlFrame(.Pong, data);
    }

    pub fn ping(self: *Self, data: []const u8) !void {
        if (self.state != .Open) return WebSocketError.ConnectionClosed;
        try self.sendControlFrame(.Ping, data);
    }

    fn sendControlFrame(self: *Self, opcode: Opcode, data: []const u8) !void {
        var header_buf: [6]u8 = undefined;
        header_buf[0] = 0x80 | @intFromEnum(opcode); // FIN + opcode
        header_buf[1] = 0x80 | @as(u8, @truncate(data.len)); // MASK + len

        try self.writeAll(header_buf[0..2]);

        const mask = protocol.generateMask();
        try self.writeAll(&mask);

        if (data.len > 0) {
            const masked = try self.allocator.alloc(u8, data.len);
            defer self.allocator.free(masked);
            @memcpy(masked, data);
            protocol.applyMask(masked, mask);
            try self.writeAll(masked);
        }
    }

    pub fn close(self: *Self) !void {
        if (self.state == .Closed) return;

        if (self.state == .Open) {
            // Send close frame with code 1000 (normal closure)
            var close_payload = [_]u8{ 0x03, 0xe8 }; // 1000 in big endian
            self.sendControlFrame(.Close, &close_payload) catch {};
        }

        // Clean up TLS connection
        if (self.tls_conn) |tls_c| {
            tls_c.deinit();
            self.tls_conn = null;
        }

        // Close raw socket
        if (self.stream) |stream| {
            stream.close();
            self.stream = null;
        }

        self.state = .Closed;
    }
};

// Convenience function matching Python's websockets.connect()
pub fn connect(allocator: std.mem.Allocator, url: []const u8) !*WebSocketClient {
    const client = try allocator.create(WebSocketClient);
    client.* = try WebSocketClient.init(allocator, url);
    try client.connect();
    return client;
}
