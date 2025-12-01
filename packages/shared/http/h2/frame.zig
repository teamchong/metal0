//! HTTP/2 Frame Protocol (RFC 7540)
//!
//! HTTP/2 uses a binary framing layer with 9-byte headers:
//! +-----------------------------------------------+
//! |                 Length (24)                   |
//! +---------------+---------------+---------------+
//! |   Type (8)    |   Flags (8)   |
//! +-+-------------+---------------+-------------------------------+
//! |R|                 Stream Identifier (31)                      |
//! +=+=============================================================+
//! |                   Frame Payload (0...)                      ...
//! +---------------------------------------------------------------+

const std = @import("std");

/// Frame types (RFC 7540 Section 6)
pub const FrameType = enum(u8) {
    DATA = 0x0,
    HEADERS = 0x1,
    PRIORITY = 0x2,
    RST_STREAM = 0x3,
    SETTINGS = 0x4,
    PUSH_PROMISE = 0x5,
    PING = 0x6,
    GOAWAY = 0x7,
    WINDOW_UPDATE = 0x8,
    CONTINUATION = 0x9,
    _,
};

/// Frame flags
pub const FrameFlags = struct {
    // DATA flags
    pub const END_STREAM: u8 = 0x1;
    pub const PADDED: u8 = 0x8;

    // HEADERS flags
    pub const END_HEADERS: u8 = 0x4;
    pub const PRIORITY: u8 = 0x20;

    // SETTINGS flags
    pub const ACK: u8 = 0x1;

    // PING flags (uses ACK)
};

/// Settings parameters (RFC 7540 Section 6.5.2)
pub const SettingsParam = enum(u16) {
    HEADER_TABLE_SIZE = 0x1,
    ENABLE_PUSH = 0x2,
    MAX_CONCURRENT_STREAMS = 0x3,
    INITIAL_WINDOW_SIZE = 0x4,
    MAX_FRAME_SIZE = 0x5,
    MAX_HEADER_LIST_SIZE = 0x6,
    _,
};

/// Default settings values
pub const DefaultSettings = struct {
    pub const HEADER_TABLE_SIZE: u32 = 4096;
    pub const ENABLE_PUSH: u32 = 1;
    pub const MAX_CONCURRENT_STREAMS: u32 = 100;
    pub const INITIAL_WINDOW_SIZE: u32 = 65535;
    pub const MAX_FRAME_SIZE: u32 = 16384;
    pub const MAX_HEADER_LIST_SIZE: u32 = 8192;
};

/// HTTP/2 connection preface (client sends first)
pub const CONNECTION_PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";

/// Frame header (9 bytes)
pub const FrameHeader = struct {
    length: u24,
    frame_type: FrameType,
    flags: u8,
    stream_id: u31,

    pub const SIZE = 9;

    /// Parse frame header from bytes
    pub fn parse(data: []const u8) !FrameHeader {
        if (data.len < SIZE) return error.InsufficientData;

        const length: u24 = (@as(u24, data[0]) << 16) |
            (@as(u24, data[1]) << 8) |
            @as(u24, data[2]);

        const frame_type: FrameType = @enumFromInt(data[3]);
        const flags = data[4];

        // Stream ID is 31 bits (MSB reserved)
        const stream_id: u31 = @truncate(
            (@as(u32, data[5] & 0x7F) << 24) |
                (@as(u32, data[6]) << 16) |
                (@as(u32, data[7]) << 8) |
                @as(u32, data[8]),
        );

        return .{
            .length = length,
            .frame_type = frame_type,
            .flags = flags,
            .stream_id = stream_id,
        };
    }

    /// Serialize frame header to bytes
    pub fn serialize(self: FrameHeader, out: *[SIZE]u8) void {
        // Length (24 bits)
        out[0] = @truncate(self.length >> 16);
        out[1] = @truncate(self.length >> 8);
        out[2] = @truncate(self.length);

        // Type (8 bits)
        out[3] = @intFromEnum(self.frame_type);

        // Flags (8 bits)
        out[4] = self.flags;

        // Stream ID (31 bits, MSB reserved = 0)
        const sid: u32 = self.stream_id;
        out[5] = @truncate(sid >> 24);
        out[6] = @truncate(sid >> 16);
        out[7] = @truncate(sid >> 8);
        out[8] = @truncate(sid);
    }

    /// Check if END_STREAM flag is set
    pub fn isEndStream(self: FrameHeader) bool {
        return (self.flags & FrameFlags.END_STREAM) != 0;
    }

    /// Check if END_HEADERS flag is set
    pub fn isEndHeaders(self: FrameHeader) bool {
        return (self.flags & FrameFlags.END_HEADERS) != 0;
    }

    /// Check if ACK flag is set
    pub fn isAck(self: FrameHeader) bool {
        return (self.flags & FrameFlags.ACK) != 0;
    }
};

/// Complete frame (header + payload)
pub const Frame = struct {
    header: FrameHeader,
    payload: []const u8,

    /// Create a SETTINGS frame
    pub fn settings(allocator: std.mem.Allocator, params: []const struct { id: SettingsParam, value: u32 }) !Frame {
        const payload = try allocator.alloc(u8, params.len * 6);
        errdefer allocator.free(payload);

        for (params, 0..) |param, i| {
            const offset = i * 6;
            // Parameter ID (16 bits)
            payload[offset] = @truncate(@intFromEnum(param.id) >> 8);
            payload[offset + 1] = @truncate(@intFromEnum(param.id));
            // Value (32 bits)
            payload[offset + 2] = @truncate(param.value >> 24);
            payload[offset + 3] = @truncate(param.value >> 16);
            payload[offset + 4] = @truncate(param.value >> 8);
            payload[offset + 5] = @truncate(param.value);
        }

        return .{
            .header = .{
                .length = @intCast(payload.len),
                .frame_type = .SETTINGS,
                .flags = 0,
                .stream_id = 0,
            },
            .payload = payload,
        };
    }

    /// Create a SETTINGS ACK frame
    pub fn settingsAck() Frame {
        return .{
            .header = .{
                .length = 0,
                .frame_type = .SETTINGS,
                .flags = FrameFlags.ACK,
                .stream_id = 0,
            },
            .payload = &[_]u8{},
        };
    }

    /// Create a HEADERS frame
    pub fn headers(stream_id: u31, header_block: []const u8, end_stream: bool, end_headers: bool) Frame {
        var flags: u8 = 0;
        if (end_stream) flags |= FrameFlags.END_STREAM;
        if (end_headers) flags |= FrameFlags.END_HEADERS;

        return .{
            .header = .{
                .length = @intCast(header_block.len),
                .frame_type = .HEADERS,
                .flags = flags,
                .stream_id = stream_id,
            },
            .payload = header_block,
        };
    }

    /// Create a DATA frame
    pub fn data(stream_id: u31, payload_data: []const u8, end_stream: bool) Frame {
        return .{
            .header = .{
                .length = @intCast(payload_data.len),
                .frame_type = .DATA,
                .flags = if (end_stream) FrameFlags.END_STREAM else 0,
                .stream_id = stream_id,
            },
            .payload = payload_data,
        };
    }

    /// Create a WINDOW_UPDATE frame header (caller must provide payload buffer)
    pub fn windowUpdate(stream_id: u31, increment: u31) struct { header: FrameHeader, increment: u32 } {
        return .{
            .header = .{
                .length = 4,
                .frame_type = .WINDOW_UPDATE,
                .flags = 0,
                .stream_id = stream_id,
            },
            .increment = @as(u32, increment),
        };
    }

    /// Create a GOAWAY frame
    pub fn goaway(last_stream_id: u31, error_code: u32) Frame {
        var payload: [8]u8 = undefined;
        const sid: u32 = last_stream_id;
        payload[0] = @truncate(sid >> 24);
        payload[1] = @truncate(sid >> 16);
        payload[2] = @truncate(sid >> 8);
        payload[3] = @truncate(sid);
        payload[4] = @truncate(error_code >> 24);
        payload[5] = @truncate(error_code >> 16);
        payload[6] = @truncate(error_code >> 8);
        payload[7] = @truncate(error_code);

        return .{
            .header = .{
                .length = 8,
                .frame_type = .GOAWAY,
                .flags = 0,
                .stream_id = 0,
            },
            .payload = &payload,
        };
    }

    /// Serialize complete frame to writer
    pub fn write(self: Frame, writer: anytype) !void {
        var header_buf: [FrameHeader.SIZE]u8 = undefined;
        self.header.serialize(&header_buf);
        try writer.writeAll(&header_buf);
        if (self.payload.len > 0) {
            try writer.writeAll(self.payload);
        }
    }

    /// Total frame size
    pub fn totalSize(self: Frame) usize {
        return FrameHeader.SIZE + self.header.length;
    }
};

/// Error codes (RFC 7540 Section 7)
pub const ErrorCode = enum(u32) {
    NO_ERROR = 0x0,
    PROTOCOL_ERROR = 0x1,
    INTERNAL_ERROR = 0x2,
    FLOW_CONTROL_ERROR = 0x3,
    SETTINGS_TIMEOUT = 0x4,
    STREAM_CLOSED = 0x5,
    FRAME_SIZE_ERROR = 0x6,
    REFUSED_STREAM = 0x7,
    CANCEL = 0x8,
    COMPRESSION_ERROR = 0x9,
    CONNECT_ERROR = 0xa,
    ENHANCE_YOUR_CALM = 0xb,
    INADEQUATE_SECURITY = 0xc,
    HTTP_1_1_REQUIRED = 0xd,
    _,
};

// ============================================================================
// Tests
// ============================================================================

test "FrameHeader parse and serialize roundtrip" {
    const original = FrameHeader{
        .length = 16384,
        .frame_type = .HEADERS,
        .flags = FrameFlags.END_HEADERS | FrameFlags.END_STREAM,
        .stream_id = 1,
    };

    var buf: [FrameHeader.SIZE]u8 = undefined;
    original.serialize(&buf);

    const parsed = try FrameHeader.parse(&buf);
    try std.testing.expectEqual(original.length, parsed.length);
    try std.testing.expectEqual(original.frame_type, parsed.frame_type);
    try std.testing.expectEqual(original.flags, parsed.flags);
    try std.testing.expectEqual(original.stream_id, parsed.stream_id);
}

test "SETTINGS frame creation" {
    const allocator = std.testing.allocator;

    const frame = try Frame.settings(allocator, &.{
        .{ .id = .MAX_CONCURRENT_STREAMS, .value = 100 },
        .{ .id = .INITIAL_WINDOW_SIZE, .value = 65535 },
    });
    defer allocator.free(frame.payload);

    try std.testing.expectEqual(FrameType.SETTINGS, frame.header.frame_type);
    try std.testing.expectEqual(@as(u24, 12), frame.header.length);
    try std.testing.expectEqual(@as(u31, 0), frame.header.stream_id);
}

test "SETTINGS ACK frame" {
    const frame = Frame.settingsAck();
    try std.testing.expectEqual(FrameType.SETTINGS, frame.header.frame_type);
    try std.testing.expectEqual(@as(u24, 0), frame.header.length);
    try std.testing.expect(frame.header.isAck());
}
