//! CPython source: Lib/uuid.py
//!
//! Generate and work with UUIDs according to RFC 4122.
//!
//! Mirrors: CPython Lib/uuid.py

const std = @import("std");

// ============================================================================
// UUID Type
// ============================================================================

/// UUID object representing a universally unique identifier
pub const UUID = struct {
    /// The 128-bit UUID value
    bytes: [16]u8,

    /// Create a UUID from 16 bytes
    pub fn init(bytes: [16]u8) UUID {
        return .{ .bytes = bytes };
    }

    /// Create a UUID from a hex string (with or without dashes)
    pub fn fromString(s: []const u8) !UUID {
        var bytes: [16]u8 = undefined;
        var byte_idx: usize = 0;
        var i: usize = 0;

        while (i < s.len and byte_idx < 16) {
            if (s[i] == '-') {
                i += 1;
                continue;
            }

            if (i + 1 >= s.len) return error.InvalidUUID;

            const high = hexDigitToInt(s[i]) orelse return error.InvalidUUID;
            const low = hexDigitToInt(s[i + 1]) orelse return error.InvalidUUID;
            bytes[byte_idx] = (high << 4) | low;
            byte_idx += 1;
            i += 2;
        }

        if (byte_idx != 16) return error.InvalidUUID;
        return UUID.init(bytes);
    }

    /// Create a UUID from an integer
    pub fn fromInt(int_val: u128) UUID {
        var bytes: [16]u8 = undefined;
        var val = int_val;
        var i: usize = 16;
        while (i > 0) {
            i -= 1;
            bytes[i] = @truncate(val);
            val >>= 8;
        }
        return UUID.init(bytes);
    }

    /// Convert UUID to integer
    pub fn toInt(self: UUID) u128 {
        var result: u128 = 0;
        for (self.bytes) |b| {
            result = (result << 8) | b;
        }
        return result;
    }

    /// Format UUID as hex string with dashes
    pub fn toString(self: UUID, buf: *[36]u8) []const u8 {
        const hex = "0123456789abcdef";
        var pos: usize = 0;

        // Time-low (4 bytes)
        for (0..4) |i| {
            buf[pos] = hex[self.bytes[i] >> 4];
            buf[pos + 1] = hex[self.bytes[i] & 0x0f];
            pos += 2;
        }
        buf[pos] = '-';
        pos += 1;

        // Time-mid (2 bytes)
        for (4..6) |i| {
            buf[pos] = hex[self.bytes[i] >> 4];
            buf[pos + 1] = hex[self.bytes[i] & 0x0f];
            pos += 2;
        }
        buf[pos] = '-';
        pos += 1;

        // Time-high-and-version (2 bytes)
        for (6..8) |i| {
            buf[pos] = hex[self.bytes[i] >> 4];
            buf[pos + 1] = hex[self.bytes[i] & 0x0f];
            pos += 2;
        }
        buf[pos] = '-';
        pos += 1;

        // Clock-seq-and-reserved + clock-seq-low (2 bytes)
        for (8..10) |i| {
            buf[pos] = hex[self.bytes[i] >> 4];
            buf[pos + 1] = hex[self.bytes[i] & 0x0f];
            pos += 2;
        }
        buf[pos] = '-';
        pos += 1;

        // Node (6 bytes)
        for (10..16) |i| {
            buf[pos] = hex[self.bytes[i] >> 4];
            buf[pos + 1] = hex[self.bytes[i] & 0x0f];
            pos += 2;
        }

        return buf[0..36];
    }

    /// Get the hex string without dashes
    pub fn toHex(self: UUID, buf: *[32]u8) []const u8 {
        const hex = "0123456789abcdef";
        for (self.bytes, 0..) |b, i| {
            buf[i * 2] = hex[b >> 4];
            buf[i * 2 + 1] = hex[b & 0x0f];
        }
        return buf[0..32];
    }

    /// Get the version (4 bits from byte 6)
    pub fn version(self: UUID) u4 {
        return @truncate(self.bytes[6] >> 4);
    }

    /// Get the variant (2-3 bits from byte 8)
    pub fn variant(self: UUID) Variant {
        const b = self.bytes[8];
        if ((b & 0x80) == 0) return .NCS;
        if ((b & 0x40) == 0) return .RFC_4122;
        if ((b & 0x20) == 0) return .MICROSOFT;
        return .FUTURE;
    }

    /// Get the time_low field (first 4 bytes)
    pub fn time_low(self: UUID) u32 {
        return std.mem.readInt(u32, self.bytes[0..4], .big);
    }

    /// Get the time_mid field (bytes 4-5)
    pub fn time_mid(self: UUID) u16 {
        return std.mem.readInt(u16, self.bytes[4..6], .big);
    }

    /// Get the time_hi_version field (bytes 6-7)
    pub fn time_hi_version(self: UUID) u16 {
        return std.mem.readInt(u16, self.bytes[6..8], .big);
    }

    /// Get the clock_seq_hi_variant field (byte 8)
    pub fn clock_seq_hi_variant(self: UUID) u8 {
        return self.bytes[8];
    }

    /// Get the clock_seq_low field (byte 9)
    pub fn clock_seq_low(self: UUID) u8 {
        return self.bytes[9];
    }

    /// Get the node field (bytes 10-15, as u48)
    pub fn node(self: UUID) u48 {
        var result: u48 = 0;
        for (self.bytes[10..16]) |b| {
            result = (result << 8) | b;
        }
        return result;
    }

    /// Get the URN representation
    pub fn urn(self: UUID, buf: *[45]u8) []const u8 {
        @memcpy(buf[0..9], "urn:uuid:");
        var uuid_buf: [36]u8 = undefined;
        const uuid_str = self.toString(&uuid_buf);
        @memcpy(buf[9..45], uuid_str);
        return buf[0..45];
    }

    /// Check equality
    pub fn eql(self: UUID, other: UUID) bool {
        return std.mem.eql(u8, &self.bytes, &other.bytes);
    }

    /// Compare UUIDs
    pub fn compare(self: UUID, other: UUID) std.math.Order {
        return std.mem.order(u8, &self.bytes, &other.bytes);
    }
};

/// UUID variant types
pub const Variant = enum {
    NCS, // Reserved for NCS compatibility
    RFC_4122, // The variant specified in RFC 4122
    MICROSOFT, // Reserved for Microsoft compatibility
    FUTURE, // Reserved for future definition
};

// ============================================================================
// UUID Generation
// ============================================================================

/// Generate a random UUID (version 4)
pub fn uuid4() UUID {
    var bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&bytes);

    // Set version to 4
    bytes[6] = (bytes[6] & 0x0f) | 0x40;

    // Set variant to RFC 4122
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    return UUID.init(bytes);
}

/// Generate a UUID based on MD5 hash of namespace and name (version 3)
pub fn uuid3(namespace: UUID, name: []const u8) UUID {
    var hasher = std.crypto.hash.Md5.init(.{});
    hasher.update(&namespace.bytes);
    hasher.update(name);
    var bytes = hasher.finalResult();

    // Set version to 3
    bytes[6] = (bytes[6] & 0x0f) | 0x30;

    // Set variant to RFC 4122
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    return UUID.init(bytes);
}

/// Generate a UUID based on SHA-1 hash of namespace and name (version 5)
pub fn uuid5(namespace: UUID, name: []const u8) UUID {
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(&namespace.bytes);
    hasher.update(name);
    const hash = hasher.finalResult();
    var bytes: [16]u8 = undefined;
    @memcpy(&bytes, hash[0..16]);

    // Set version to 5
    bytes[6] = (bytes[6] & 0x0f) | 0x50;

    // Set variant to RFC 4122
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    return UUID.init(bytes);
}

/// Generate a UUID based on host ID and current time (version 1)
pub fn uuid1() UUID {
    // Get current timestamp (100-nanosecond intervals since Oct 15, 1582)
    const now = std.time.nanoTimestamp();
    // Convert from Unix epoch to UUID epoch (difference is 122192928000000000)
    const uuid_time: u64 = @intCast(@as(i128, now) / 100 + 122192928000000000);

    var bytes: [16]u8 = undefined;

    // Time-low (bytes 0-3)
    const time_low: u32 = @truncate(uuid_time);
    std.mem.writeInt(u32, bytes[0..4], time_low, .big);

    // Time-mid (bytes 4-5)
    const time_mid: u16 = @truncate(uuid_time >> 32);
    std.mem.writeInt(u16, bytes[4..6], time_mid, .big);

    // Time-high-and-version (bytes 6-7)
    const time_hi: u16 = @truncate(uuid_time >> 48);
    std.mem.writeInt(u16, bytes[6..8], (time_hi & 0x0fff) | 0x1000, .big);

    // Clock sequence (bytes 8-9) - random
    std.crypto.random.bytes(bytes[8..10]);
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // Set variant

    // Node (bytes 10-15) - random (since we can't get MAC address portably)
    std.crypto.random.bytes(bytes[10..16]);

    return UUID.init(bytes);
}

// ============================================================================
// Predefined Namespace UUIDs
// ============================================================================

/// Namespace for DNS names
pub const NAMESPACE_DNS = UUID.init(.{
    0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
});

/// Namespace for URLs
pub const NAMESPACE_URL = UUID.init(.{
    0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
});

/// Namespace for ISO OIDs
pub const NAMESPACE_OID = UUID.init(.{
    0x6b, 0xa7, 0xb8, 0x12, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
});

/// Namespace for X.500 DNs
pub const NAMESPACE_X500 = UUID.init(.{
    0x6b, 0xa7, 0xb8, 0x14, 0x9d, 0xad, 0x11, 0xd1,
    0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
});

// ============================================================================
// Helper functions
// ============================================================================

fn hexDigitToInt(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @truncate(c - '0'),
        'a'...'f' => @truncate(c - 'a' + 10),
        'A'...'F' => @truncate(c - 'A' + 10),
        else => null,
    };
}

/// Get a random UUID (alias for uuid4)
pub fn getRandomUUID() UUID {
    return uuid4();
}

// ============================================================================
// Tests
// ============================================================================

test "uuid4" {
    const u = uuid4();
    try std.testing.expectEqual(@as(u4, 4), u.version());
    try std.testing.expectEqual(Variant.RFC_4122, u.variant());
}

test "uuid3" {
    const uuid_val = uuid3(NAMESPACE_DNS, "python.org");
    try std.testing.expectEqual(@as(u4, 3), uuid_val.version());
    try std.testing.expectEqual(Variant.RFC_4122, uuid_val.variant());

    // Same input should produce same UUID
    const uuid_val2 = uuid3(NAMESPACE_DNS, "python.org");
    try std.testing.expect(uuid_val.eql(uuid_val2));
}

test "uuid5" {
    const uuid_val = uuid5(NAMESPACE_DNS, "python.org");
    try std.testing.expectEqual(@as(u4, 5), uuid_val.version());
    try std.testing.expectEqual(Variant.RFC_4122, uuid_val.variant());

    // Same input should produce same UUID
    const uuid_val2 = uuid5(NAMESPACE_DNS, "python.org");
    try std.testing.expect(uuid_val.eql(uuid_val2));
}

test "uuid1" {
    const u = uuid1();
    try std.testing.expectEqual(@as(u4, 1), u.version());
    try std.testing.expectEqual(Variant.RFC_4122, u.variant());
}

test "UUID.fromString" {
    const u = try UUID.fromString("12345678-1234-5678-1234-567812345678");
    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);
    try std.testing.expectEqualStrings("12345678-1234-5678-1234-567812345678", s);
}

test "UUID.fromString without dashes" {
    const u = try UUID.fromString("12345678123456781234567812345678");
    var buf: [36]u8 = undefined;
    const s = u.toString(&buf);
    try std.testing.expectEqualStrings("12345678-1234-5678-1234-567812345678", s);
}

test "UUID.toInt and fromInt" {
    const original = uuid4();
    const int_val = original.toInt();
    const restored = UUID.fromInt(int_val);
    try std.testing.expect(original.eql(restored));
}

test "UUID.toHex" {
    const u = try UUID.fromString("12345678-1234-5678-1234-567812345678");
    var buf: [32]u8 = undefined;
    const hex = u.toHex(&buf);
    try std.testing.expectEqualStrings("12345678123456781234567812345678", hex);
}

test "UUID.urn" {
    const u = try UUID.fromString("12345678-1234-5678-1234-567812345678");
    var buf: [45]u8 = undefined;
    const urn_str = u.urn(&buf);
    try std.testing.expectEqualStrings("urn:uuid:12345678-1234-5678-1234-567812345678", urn_str);
}

test "UUID.compare" {
    const uuid_a = try UUID.fromString("00000000-0000-0000-0000-000000000001");
    const uuid_b = try UUID.fromString("00000000-0000-0000-0000-000000000002");
    try std.testing.expectEqual(std.math.Order.lt, uuid_a.compare(uuid_b));
    try std.testing.expectEqual(std.math.Order.gt, uuid_b.compare(uuid_a));
    try std.testing.expectEqual(std.math.Order.eq, uuid_a.compare(uuid_a));
}
