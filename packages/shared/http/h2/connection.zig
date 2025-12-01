//! HTTP/2 Connection with Stream Multiplexing
//!
//! Implements HTTP/2 over TLS (h2) with:
//! - ALPN negotiation
//! - Stream multiplexing (multiple requests over one connection)
//! - Flow control
//! - Header compression (HPACK)

const std = @import("std");
const frame = @import("frame.zig");
const hpack = @import("hpack.zig");
const tls = @import("tls.zig");

const FrameHeader = frame.FrameHeader;
const FrameType = frame.FrameType;
const FrameFlags = frame.FrameFlags;
const Frame = frame.Frame;

pub const H2Error = error{
    ConnectionFailed,
    TlsError,
    ProtocolError,
    StreamClosed,
    FlowControlError,
    FrameSizeError,
    CompressionError,
    Timeout,
    OutOfMemory,
    InvalidResponse,
};

/// HTTP/2 Request (for batch operations)
pub const Request = struct {
    method: []const u8,
    path: []const u8,
    host: []const u8,
};

/// Stream state (RFC 7540 Section 5.1)
pub const StreamState = enum {
    idle,
    reserved_local,
    reserved_remote,
    open,
    half_closed_local,
    half_closed_remote,
    closed,
};

/// HTTP/2 Stream
pub const Stream = struct {
    id: u31,
    state: StreamState,
    window_size: i32,

    // Response data
    status: ?u16,
    headers: std.ArrayList(hpack.Header),
    body: std.ArrayList(u8),

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, id: u31) Stream {
        return .{
            .id = id,
            .state = .idle,
            .window_size = 65535,
            .status = null,
            .headers = std.ArrayList(hpack.Header){},
            .body = std.ArrayList(u8){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Stream) void {
        for (self.headers.items) |h| {
            self.allocator.free(h.name);
            self.allocator.free(h.value);
        }
        self.headers.deinit(self.allocator);
        self.body.deinit(self.allocator);
    }

    /// Add received headers
    pub fn addHeaders(self: *Stream, hdrs: []const hpack.Header) !void {
        for (hdrs) |h| {
            // Check for pseudo-headers
            if (std.mem.eql(u8, h.name, ":status")) {
                self.status = std.fmt.parseInt(u16, h.value, 10) catch null;
            }

            const name_copy = try self.allocator.dupe(u8, h.name);
            errdefer self.allocator.free(name_copy);
            const value_copy = try self.allocator.dupe(u8, h.value);

            try self.headers.append(self.allocator, .{ .name = name_copy, .value = value_copy });
        }
    }

    /// Append data to body
    pub fn appendData(self: *Stream, data: []const u8) !void {
        try self.body.appendSlice(self.allocator, data);
    }

    /// Get response body as slice
    pub fn getBody(self: *Stream) []const u8 {
        return self.body.items;
    }

    /// Get header value by name
    pub fn getHeader(self: *Stream, name: []const u8) ?[]const u8 {
        for (self.headers.items) |h| {
            if (std.ascii.eqlIgnoreCase(h.name, name)) {
                return h.value;
            }
        }
        return null;
    }
};

/// HTTP/2 Connection Settings
pub const Settings = struct {
    header_table_size: u32 = 4096,
    enable_push: bool = false,
    max_concurrent_streams: u32 = 100,
    initial_window_size: u32 = 65535,
    max_frame_size: u32 = 16384,
    max_header_list_size: u32 = 8192,
};

/// HTTP/2 Connection
pub const Connection = struct {
    allocator: std.mem.Allocator,
    tls_conn: *tls.TlsConnection,

    // Connection state
    settings: Settings,
    peer_settings: Settings,
    hpack_encoder: hpack.Context,
    hpack_decoder: hpack.Context,

    // Streams
    streams: std.AutoHashMap(u31, *Stream),
    next_stream_id: u31,

    // Flow control
    connection_window: i32,

    // Buffer for reading
    read_buffer: [65536]u8,
    read_pos: usize,
    read_len: usize,

    /// Create HTTP/2 connection over an existing TLS connection
    pub fn initWithTls(allocator: std.mem.Allocator, tls_conn: *tls.TlsConnection) !*Connection {
        const conn = try allocator.create(Connection);
        errdefer allocator.destroy(conn);

        conn.* = .{
            .allocator = allocator,
            .tls_conn = tls_conn,
            .settings = .{},
            .peer_settings = .{},
            .hpack_encoder = hpack.Context.init(allocator),
            .hpack_decoder = hpack.Context.init(allocator),
            .streams = std.AutoHashMap(u31, *Stream).init(allocator),
            .next_stream_id = 1, // Client uses odd stream IDs
            .connection_window = 65535,
            .read_buffer = undefined,
            .read_pos = 0,
            .read_len = 0,
        };

        // Send connection preface
        try conn.sendPreface();

        // Exchange settings
        try conn.exchangeSettings();

        return conn;
    }

    pub fn init(allocator: std.mem.Allocator, host: []const u8, port: u16) !*Connection {
        _ = host;
        _ = port;
        // Legacy init - not supported, use initWithTls
        return allocator.create(Connection);
    }

    pub fn deinit(self: *Connection) void {
        // Close all streams
        var it = self.streams.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.streams.deinit();

        self.hpack_encoder.deinit();
        self.hpack_decoder.deinit();

        // TLS connection is owned by caller, don't close it here

        self.allocator.destroy(self);
    }

    /// Send HTTP/2 connection preface
    fn sendPreface(self: *Connection) !void {
        // Send magic string over TLS
        self.tls_conn.send(frame.CONNECTION_PREFACE) catch return H2Error.ConnectionFailed;

        // Send initial SETTINGS frame
        const settings_frame = try Frame.settings(self.allocator, &.{
            .{ .id = .MAX_CONCURRENT_STREAMS, .value = self.settings.max_concurrent_streams },
            .{ .id = .INITIAL_WINDOW_SIZE, .value = self.settings.initial_window_size },
            .{ .id = .ENABLE_PUSH, .value = 0 }, // Disable server push
        });
        defer self.allocator.free(settings_frame.payload);

        try self.sendFrame(settings_frame);
    }

    /// Exchange settings with server
    fn exchangeSettings(self: *Connection) !void {
        // Read server's SETTINGS frame
        const server_frame = try self.readFrame();


        if (server_frame.header.frame_type != .SETTINGS) {
            return H2Error.ProtocolError;
        }

        // Parse server settings
        try self.parseSettings(server_frame.payload);

        // Send SETTINGS ACK

        const ack = Frame.settingsAck();
        try self.sendFrame(ack);

        // Wait for server's SETTINGS ACK

        var count: usize = 0;
        while (true) {
            const ack_frame = try self.readFrame();
    
            if (ack_frame.header.frame_type == .SETTINGS and ack_frame.header.isAck()) {
        
                break;
            }
            // Process other frames
            try self.processFrame(ack_frame);
            count += 1;
            if (count > 100) break; // Safety limit
        }

    }

    fn parseSettings(self: *Connection, payload: []const u8) !void {
        var i: usize = 0;
        while (i + 6 <= payload.len) {
            const id: u16 = (@as(u16, payload[i]) << 8) | payload[i + 1];
            const value: u32 = (@as(u32, payload[i + 2]) << 24) |
                (@as(u32, payload[i + 3]) << 16) |
                (@as(u32, payload[i + 4]) << 8) |
                payload[i + 5];

            switch (@as(frame.SettingsParam, @enumFromInt(id))) {
                .HEADER_TABLE_SIZE => self.peer_settings.header_table_size = value,
                .ENABLE_PUSH => self.peer_settings.enable_push = value != 0,
                .MAX_CONCURRENT_STREAMS => self.peer_settings.max_concurrent_streams = value,
                .INITIAL_WINDOW_SIZE => self.peer_settings.initial_window_size = value,
                .MAX_FRAME_SIZE => self.peer_settings.max_frame_size = value,
                .MAX_HEADER_LIST_SIZE => self.peer_settings.max_header_list_size = value,
                _ => {},
            }
            i += 6;
        }
    }

    /// Send WINDOW_UPDATE frame
    fn sendWindowUpdate(self: *Connection, stream_id: u31, increment: u31) !void {
        var buf: [9 + 4]u8 = undefined; // header + payload
        const sid: u32 = stream_id;

        // Frame header (9 bytes)
        buf[0] = 0;
        buf[1] = 0;
        buf[2] = 4; // length = 4
        buf[3] = 0x8; // WINDOW_UPDATE
        buf[4] = 0; // flags
        buf[5] = @truncate(sid >> 24);
        buf[6] = @truncate(sid >> 16);
        buf[7] = @truncate(sid >> 8);
        buf[8] = @truncate(sid);

        // WINDOW_UPDATE payload (increment, 31 bits)
        const inc: u32 = increment;
        buf[9] = @truncate(inc >> 24);
        buf[10] = @truncate(inc >> 16);
        buf[11] = @truncate(inc >> 8);
        buf[12] = @truncate(inc);

        self.tls_conn.send(&buf) catch return H2Error.ConnectionFailed;
    }

    /// Send a frame over TLS
    pub fn sendFrame(self: *Connection, f: Frame) !void {
        var header_buf: [FrameHeader.SIZE]u8 = undefined;
        f.header.serialize(&header_buf);

        // Send frame header and payload as single TLS record for efficiency
        if (f.payload.len > 0) {
            const total = try self.allocator.alloc(u8, FrameHeader.SIZE + f.payload.len);
            defer self.allocator.free(total);
            @memcpy(total[0..FrameHeader.SIZE], &header_buf);
            @memcpy(total[FrameHeader.SIZE..], f.payload);
            self.tls_conn.send(total) catch return H2Error.ConnectionFailed;
        } else {
            self.tls_conn.send(&header_buf) catch return H2Error.ConnectionFailed;
        }
    }

    /// Read a frame from connection
    fn readFrame(self: *Connection) !Frame {
        // Read frame header
        try self.ensureData(FrameHeader.SIZE);

        const header = try FrameHeader.parse(self.read_buffer[self.read_pos .. self.read_pos + FrameHeader.SIZE]);
        self.read_pos += FrameHeader.SIZE;

        // Read payload
        try self.ensureData(header.length);

        const payload = self.read_buffer[self.read_pos .. self.read_pos + header.length];
        self.read_pos += header.length;

        return .{
            .header = header,
            .payload = payload,
        };
    }

    /// Ensure we have at least `needed` bytes in buffer
    fn ensureData(self: *Connection, needed: usize) !void {
        while (self.read_len - self.read_pos < needed) {
            // Compact buffer if needed
            if (self.read_pos > 0) {
                const remaining = self.read_len - self.read_pos;
                std.mem.copyForwards(u8, self.read_buffer[0..remaining], self.read_buffer[self.read_pos..self.read_len]);
                self.read_len = remaining;
                self.read_pos = 0;
            }

            // Read more data from TLS
            const n = self.tls_conn.recv(self.read_buffer[self.read_len..]) catch return H2Error.ConnectionFailed;
            if (n == 0) return H2Error.ConnectionFailed;
            self.read_len += n;
        }
    }

    /// Process incoming frame
    fn processFrame(self: *Connection, f: Frame) !void {
        switch (f.header.frame_type) {
            .DATA => try self.handleData(f),
            .HEADERS => try self.handleHeaders(f),
            .SETTINGS => {
                if (!f.header.isAck()) {
                    try self.parseSettings(f.payload);
                    try self.sendFrame(Frame.settingsAck());
                }
            },
            .WINDOW_UPDATE => try self.handleWindowUpdate(f),
            .PING => try self.handlePing(f),
            .GOAWAY => {
                // Server closing connection
                return H2Error.ConnectionFailed;
            },
            .RST_STREAM => try self.handleRstStream(f),
            else => {},
        }
    }

    fn handleData(self: *Connection, f: Frame) !void {
        if (self.streams.get(f.header.stream_id)) |stream| {
            try stream.appendData(f.payload);

            if (f.header.isEndStream()) {
                stream.state = .half_closed_remote;
            }

            // Send WINDOW_UPDATE for both connection and stream
            if (f.payload.len > 0) {
                try self.sendWindowUpdate(0, @intCast(f.payload.len)); // Connection
                try self.sendWindowUpdate(f.header.stream_id, @intCast(f.payload.len)); // Stream
            }
        }
    }

    fn handleHeaders(self: *Connection, f: Frame) !void {
        if (self.streams.get(f.header.stream_id)) |stream| {
            var payload = f.payload;

            // Handle PADDED flag (0x8)
            if (f.header.flags & 0x8 != 0) {
                if (payload.len < 1) return H2Error.ProtocolError;
                const pad_len = payload[0];
                if (payload.len < 1 + pad_len) return H2Error.ProtocolError;
                payload = payload[1 .. payload.len - pad_len];
            }

            // Handle PRIORITY flag (0x20)
            if (f.header.flags & 0x20 != 0) {
                if (payload.len < 5) return H2Error.ProtocolError;
                payload = payload[5..]; // Skip priority info (E + stream dep + weight)
            }

            // Decode HPACK headers
            var decoder = hpack.Decoder.init(&self.hpack_decoder);
            const headers = decoder.decode(self.allocator, payload) catch {
                return H2Error.CompressionError;
            };
            defer {
                for (headers) |h| {
                    self.allocator.free(h.name);
                    self.allocator.free(h.value);
                }
                self.allocator.free(headers);
            }

            try stream.addHeaders(headers);

            if (f.header.isEndStream()) {
                stream.state = .half_closed_remote;
            }
        }
    }

    fn handleWindowUpdate(self: *Connection, f: Frame) !void {
        if (f.payload.len < 4) return;

        const increment: u31 = @truncate(
            (@as(u32, f.payload[0] & 0x7F) << 24) |
                (@as(u32, f.payload[1]) << 16) |
                (@as(u32, f.payload[2]) << 8) |
                f.payload[3],
        );

        if (f.header.stream_id == 0) {
            self.connection_window += increment;
        } else if (self.streams.get(f.header.stream_id)) |stream| {
            stream.window_size += increment;
        }
    }

    fn handlePing(self: *Connection, f: Frame) !void {
        if (!f.header.isAck()) {
            // Send PING ACK
            const ack = Frame{
                .header = .{
                    .length = 8,
                    .frame_type = .PING,
                    .flags = FrameFlags.ACK,
                    .stream_id = 0,
                },
                .payload = f.payload,
            };
            try self.sendFrame(ack);
        }
    }

    fn handleRstStream(self: *Connection, f: Frame) !void {
        var error_code: u32 = 0;
        if (f.payload.len >= 4) {
            error_code = (@as(u32, f.payload[0]) << 24) |
                (@as(u32, f.payload[1]) << 16) |
                (@as(u32, f.payload[2]) << 8) |
                f.payload[3];
        }

        if (self.streams.get(f.header.stream_id)) |stream| {
            stream.state = .closed;
        }
    }

    /// Create a new stream and send request
    pub fn request(self: *Connection, method: []const u8, path: []const u8, host: []const u8, headers: []const hpack.Header) !*Stream {
        // Allocate stream ID
        const stream_id = self.next_stream_id;
        self.next_stream_id += 2; // Client uses odd numbers

        // Create stream
        const stream = try self.allocator.create(Stream);
        errdefer self.allocator.destroy(stream);
        stream.* = Stream.init(self.allocator, stream_id);
        stream.state = .open;

        try self.streams.put(stream_id, stream);

        // Build request headers
        var all_headers = std.ArrayList(hpack.Header){};
        defer all_headers.deinit(self.allocator);

        try all_headers.append(self.allocator, .{ .name = ":method", .value = method });
        try all_headers.append(self.allocator, .{ .name = ":path", .value = path });
        try all_headers.append(self.allocator, .{ .name = ":scheme", .value = "https" });
        try all_headers.append(self.allocator, .{ .name = ":authority", .value = host });

        for (headers) |h| {
            try all_headers.append(self.allocator, h);
        }

        // Encode headers with HPACK
        var encoder = hpack.Encoder.init(&self.hpack_encoder);
        const header_block = try encoder.encode(self.allocator, all_headers.items);
        defer self.allocator.free(header_block);

        // Send HEADERS frame
        const headers_frame = Frame.headers(stream_id, header_block, true, true);
        try self.sendFrame(headers_frame);

        stream.state = .half_closed_local;

        return stream;
    }

    /// Wait for stream response
    pub fn waitForResponse(self: *Connection, stream: *Stream) !void {
        var count: usize = 0;
        while (stream.state != .half_closed_remote and stream.state != .closed) {
            const f = try self.readFrame();
    
            try self.processFrame(f);
            count += 1;
            if (count > 1000) {
        
                return H2Error.ProtocolError;
            }
        }

    }

    /// Send multiple requests and wait for all responses (multiplexed!)
    pub fn requestAll(
        self: *Connection,
        requests: []const Request,
    ) ![]*Stream {

        const streams = try self.allocator.alloc(*Stream, requests.len);
        errdefer self.allocator.free(streams);

        // Send all requests
        const default_headers = [_]hpack.Header{
            .{ .name = "user-agent", .value = "metal0/1.0" },
            .{ .name = "accept", .value = "application/json" },
            .{ .name = "accept-encoding", .value = "gzip" }, // 5-10x smaller responses!
        };
        for (requests, 0..) |req, i| {
            streams[i] = try self.request(req.method, req.path, req.host, &default_headers);
        }


        // Wait for all responses
        var pending: usize = requests.len;
        var frame_count: usize = 0;
        var total_bytes: usize = 0;
        var timer = std.time.Timer.start() catch unreachable;
        while (pending > 0) {
            const f = try self.readFrame();
            total_bytes += f.payload.len;
            try self.processFrame(f);
            frame_count += 1;

            // Check how many are done
            pending = 0;
            for (streams) |s| {
                if (s.state != .half_closed_remote and s.state != .closed) {
                    pending += 1;
                }
            }
        }
        const elapsed = timer.read() / 1_000_000;
        std.debug.print("[H2] received {d} frames, {d}KB in {d}ms ({d} KB/s)\n", .{ frame_count, total_bytes / 1024, elapsed, if (elapsed > 0) total_bytes / elapsed else 0 });


        return streams;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Stream creation" {
    const allocator = std.testing.allocator;

    var stream = Stream.init(allocator, 1);
    defer stream.deinit();

    try std.testing.expectEqual(@as(u31, 1), stream.id);
    try std.testing.expectEqual(StreamState.idle, stream.state);
}

test "FrameHeader roundtrip" {
    const header = FrameHeader{
        .length = 100,
        .frame_type = .HEADERS,
        .flags = FrameFlags.END_HEADERS,
        .stream_id = 5,
    };

    var buf: [9]u8 = undefined;
    header.serialize(&buf);

    const parsed = try FrameHeader.parse(&buf);
    try std.testing.expectEqual(header.length, parsed.length);
    try std.testing.expectEqual(header.frame_type, parsed.frame_type);
    try std.testing.expectEqual(header.flags, parsed.flags);
    try std.testing.expectEqual(header.stream_id, parsed.stream_id);
}
