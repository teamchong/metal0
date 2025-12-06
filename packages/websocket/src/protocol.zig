// WebSocket Protocol Implementation (RFC 6455)
// Based on Bun's websocket.zig (https://github.com/oven-sh/bun)

const std = @import("std");

pub const Opcode = enum(u4) {
    Continue = 0x0,
    Text = 0x1,
    Binary = 0x2,
    Res3 = 0x3,
    Res4 = 0x4,
    Res5 = 0x5,
    Res6 = 0x6,
    Res7 = 0x7,
    Close = 0x8,
    Ping = 0x9,
    Pong = 0xA,
    ResB = 0xB,
    ResC = 0xC,
    ResD = 0xD,
    ResE = 0xE,
    ResF = 0xF,

    pub fn isControl(opcode: Opcode) bool {
        return @intFromEnum(opcode) & 0x8 != 0;
    }
};

pub const WebSocketHeader = packed struct(u16) {
    len: u7,
    mask: bool,
    opcode: Opcode,
    rsv: u2 = 0,
    compressed: bool = false,
    final: bool = true,

    pub const mask_length = 4;
    pub const header_length = 2;

    pub fn packLength(length: usize) u7 {
        return switch (length) {
            0...125 => @as(u7, @truncate(length)),
            126...0xFFFF => 126,
            else => 127,
        };
    }

    pub fn lengthByteCount(byte_length: usize) usize {
        return switch (byte_length) {
            0...125 => 0,
            126...0xFFFF => @sizeOf(u16),
            else => @sizeOf(u64),
        };
    }

    pub fn frameSize(byte_length: usize) usize {
        return header_length + byte_length + lengthByteCount(byte_length);
    }

    pub fn frameSizeIncludingMask(byte_length: usize) usize {
        return frameSize(byte_length) + mask_length;
    }

    pub fn slice(self: WebSocketHeader) [2]u8 {
        return @as([2]u8, @bitCast(@byteSwap(@as(u16, @bitCast(self)))));
    }

    pub fn fromSlice(bytes: [2]u8) WebSocketHeader {
        return @as(WebSocketHeader, @bitCast(@byteSwap(@as(u16, @bitCast(bytes)))));
    }

    pub fn write(self: WebSocketHeader, writer: anytype, payload_len: usize) !void {
        try writer.writeInt(u16, @as(u16, @bitCast(self)), .big);

        // Write extended length if needed
        if (self.len == 126) {
            try writer.writeInt(u16, @as(u16, @truncate(payload_len)), .big);
        } else if (self.len == 127) {
            try writer.writeInt(u64, payload_len, .big);
        }
    }
};

/// Close status codes (RFC 6455 Section 7.4.1)
pub const CloseCode = enum(u16) {
    Normal = 1000,
    GoingAway = 1001,
    ProtocolError = 1002,
    UnsupportedData = 1003,
    NoStatus = 1005,
    Abnormal = 1006,
    InvalidPayload = 1007,
    PolicyViolation = 1008,
    MessageTooBig = 1009,
    MandatoryExtension = 1010,
    InternalError = 1011,
    ServiceRestart = 1012,
    TryAgainLater = 1013,
    BadGateway = 1014,
    TlsHandshake = 1015,
    _,
};

/// Apply/remove XOR mask to payload data
pub fn applyMask(data: []u8, mask: [4]u8) void {
    for (data, 0..) |*byte, i| {
        byte.* ^= mask[i % 4];
    }
}

/// Generate random masking key
pub fn generateMask() [4]u8 {
    var mask: [4]u8 = undefined;
    std.crypto.random.bytes(&mask);
    return mask;
}

test "WebSocketHeader pack/unpack" {
    const header = WebSocketHeader{
        .final = true,
        .opcode = .Text,
        .mask = false,
        .len = 5,
    };
    const bytes = header.slice();
    const unpacked = WebSocketHeader.fromSlice(bytes);
    try std.testing.expectEqual(header.final, unpacked.final);
    try std.testing.expectEqual(header.opcode, unpacked.opcode);
    try std.testing.expectEqual(header.mask, unpacked.mask);
    try std.testing.expectEqual(header.len, unpacked.len);
}
