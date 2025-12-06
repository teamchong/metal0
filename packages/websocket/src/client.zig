// WebSocket Client Implementation
// Maps to Python's websockets library

const std = @import("std");
const protocol = @import("protocol.zig");
const Opcode = protocol.Opcode;
const WebSocketHeader = protocol.WebSocketHeader;
const CloseCode = protocol.CloseCode;

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
    state: State = .Closed,
    uri: std.Uri,
    buffer: std.ArrayList(u8),
    max_message_size: usize = 16 * 1024 * 1024, // 16MB default

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, url: []const u8) !Self {
        const uri = try std.Uri.parse(url);
        return Self{
            .allocator = allocator,
            .uri = uri,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.close() catch {};
        self.buffer.deinit();
    }

    pub fn connect(self: *Self) !void {
        if (self.state != .Closed) return;

        self.state = .Connecting;
        errdefer self.state = .Closed;

        const host = self.uri.host orelse return WebSocketError.ConnectionFailed;
        const port: u16 = self.uri.port orelse if (std.mem.eql(u8, self.uri.scheme, "wss")) @as(u16, 443) else @as(u16, 80);

        // For now, only support non-TLS (ws://)
        // TLS support requires integration with existing TLS code
        if (std.mem.eql(u8, self.uri.scheme, "wss")) {
            return WebSocketError.TlsError; // TODO: Implement TLS
        }

        const address = try std.net.Address.resolveIp(host, port);
        self.stream = try std.net.tcpConnectToAddress(address);

        try self.performHandshake();
        self.state = .Open;
    }

    fn performHandshake(self: *Self) !void {
        const stream = self.stream orelse return WebSocketError.ConnectionFailed;
        const writer = stream.writer();

        // Generate WebSocket key
        var key_bytes: [16]u8 = undefined;
        std.crypto.random.bytes(&key_bytes);
        const ws_key = std.base64.standard.Encoder.encode(&[_]u8{0} ** 24, &key_bytes);

        const host = self.uri.host orelse return WebSocketError.ConnectionFailed;
        const path = if (self.uri.path.len > 0) self.uri.path else "/";

        // Send HTTP upgrade request
        try writer.print("GET {s} HTTP/1.1\r\n", .{path});
        try writer.print("Host: {s}\r\n", .{host});
        try writer.writeAll("Upgrade: websocket\r\n");
        try writer.writeAll("Connection: Upgrade\r\n");
        try writer.print("Sec-WebSocket-Key: {s}\r\n", .{ws_key});
        try writer.writeAll("Sec-WebSocket-Version: 13\r\n");
        try writer.writeAll("\r\n");

        // Read response
        var response_buf: [4096]u8 = undefined;
        const reader = stream.reader();
        var total_read: usize = 0;

        while (total_read < response_buf.len) {
            const n = try reader.read(response_buf[total_read..]);
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

    pub fn send(self: *Self, message: Message) !void {
        if (self.state != .Open) return WebSocketError.ConnectionClosed;

        const stream = self.stream orelse return WebSocketError.ConnectionClosed;
        const writer = stream.writer();

        const opcode: Opcode = if (message.is_binary) .Binary else .Text;
        const payload_len = message.data.len;

        // Client must mask all frames
        const header = WebSocketHeader{
            .final = true,
            .opcode = opcode,
            .mask = true,
            .len = WebSocketHeader.packLength(payload_len),
        };

        try header.write(writer, payload_len);

        // Write mask
        const mask = protocol.generateMask();
        try writer.writeAll(&mask);

        // Write masked payload
        var masked_data = try self.allocator.alloc(u8, payload_len);
        defer self.allocator.free(masked_data);
        @memcpy(masked_data, message.data);
        protocol.applyMask(masked_data, mask);
        try writer.writeAll(masked_data);
    }

    pub fn sendText(self: *Self, data: []const u8) !void {
        try self.send(Message.text(data));
    }

    pub fn sendBinary(self: *Self, data: []const u8) !void {
        try self.send(Message.binary(data));
    }

    pub fn recv(self: *Self) !Message {
        if (self.state != .Open) return WebSocketError.ConnectionClosed;

        const stream = self.stream orelse return WebSocketError.ConnectionClosed;
        const reader = stream.reader();

        // Read header
        var header_bytes: [2]u8 = undefined;
        _ = try reader.readAll(&header_bytes);
        const header = WebSocketHeader.fromSlice(header_bytes);

        // Read extended length
        var payload_len: usize = header.len;
        if (header.len == 126) {
            payload_len = try reader.readInt(u16, .big);
        } else if (header.len == 127) {
            payload_len = try reader.readInt(u64, .big);
        }

        if (payload_len > self.max_message_size) {
            return WebSocketError.MessageTooLarge;
        }

        // Read mask if present (server shouldn't mask, but handle it)
        var mask: ?[4]u8 = null;
        if (header.mask) {
            var mask_bytes: [4]u8 = undefined;
            _ = try reader.readAll(&mask_bytes);
            mask = mask_bytes;
        }

        // Read payload
        const payload = try self.allocator.alloc(u8, payload_len);
        _ = try reader.readAll(payload);

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
        const stream = self.stream orelse return;
        const writer = stream.writer();

        const header = WebSocketHeader{
            .final = true,
            .opcode = .Pong,
            .mask = true,
            .len = WebSocketHeader.packLength(data.len),
        };

        try header.write(writer, data.len);

        const mask = protocol.generateMask();
        try writer.writeAll(&mask);

        var masked = try self.allocator.alloc(u8, data.len);
        defer self.allocator.free(masked);
        @memcpy(masked, data);
        protocol.applyMask(masked, mask);
        try writer.writeAll(masked);
    }

    pub fn ping(self: *Self, data: []const u8) !void {
        if (self.state != .Open) return WebSocketError.ConnectionClosed;

        const stream = self.stream orelse return WebSocketError.ConnectionClosed;
        const writer = stream.writer();

        const header = WebSocketHeader{
            .final = true,
            .opcode = .Ping,
            .mask = true,
            .len = WebSocketHeader.packLength(data.len),
        };

        try header.write(writer, data.len);

        const mask = protocol.generateMask();
        try writer.writeAll(&mask);

        if (data.len > 0) {
            var masked = try self.allocator.alloc(u8, data.len);
            defer self.allocator.free(masked);
            @memcpy(masked, data);
            protocol.applyMask(masked, mask);
            try writer.writeAll(masked);
        }
    }

    pub fn close(self: *Self) !void {
        if (self.state == .Closed) return;

        if (self.stream) |stream| {
            if (self.state == .Open) {
                // Send close frame
                const writer = stream.writer();
                const header = WebSocketHeader{
                    .final = true,
                    .opcode = .Close,
                    .mask = true,
                    .len = 2,
                };

                try header.write(writer, 2);

                const mask = protocol.generateMask();
                try writer.writeAll(&mask);

                // Close code 1000 (normal)
                var close_data = [_]u8{ 0x03, 0xe8 }; // 1000 in big endian
                protocol.applyMask(&close_data, mask);
                try writer.writeAll(&close_data);
            }

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
