//! test.test_zoneinfo.test_part7 - Zone data serialization and roundtrip
//!
//! This module handles serialization of timezone data:
//! - Serialization to binary TZif format
//! - Roundtrip testing (parse -> serialize -> parse)
//! - Zone data comparison and equality

const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

/// TZif data serializer
pub const TZifSerializer = struct {
    buffer: std.ArrayList(u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) TZifSerializer {
        return .{
            .buffer = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TZifSerializer) void {
        self.buffer.deinit();
    }

    /// Write a big-endian u32
    pub fn writeU32(self: *TZifSerializer, value: u32) !void {
        var bytes: [4]u8 = undefined;
        mem.writeInt(u32, &bytes, value, .big);
        try self.buffer.appendSlice(&bytes);
    }

    /// Write a big-endian i32
    pub fn writeI32(self: *TZifSerializer, value: i32) !void {
        try self.writeU32(@bitCast(value));
    }

    /// Write a big-endian u64
    pub fn writeU64(self: *TZifSerializer, value: u64) !void {
        var bytes: [8]u8 = undefined;
        mem.writeInt(u64, &bytes, value, .big);
        try self.buffer.appendSlice(&bytes);
    }

    /// Write a big-endian i64
    pub fn writeI64(self: *TZifSerializer, value: i64) !void {
        try self.writeU64(@bitCast(value));
    }

    /// Write a single byte
    pub fn writeByte(self: *TZifSerializer, value: u8) !void {
        try self.buffer.append(value);
    }

    /// Write multiple bytes
    pub fn writeBytes(self: *TZifSerializer, bytes: []const u8) !void {
        try self.buffer.appendSlice(bytes);
    }

    /// Write zeros (padding)
    pub fn writeZeros(self: *TZifSerializer, count: usize) !void {
        try self.buffer.appendNTimes(0, count);
    }

    /// Get the serialized data
    pub fn getData(self: *const TZifSerializer) []const u8 {
        return self.buffer.items;
    }

    /// Get owned copy of data
    pub fn toOwnedSlice(self: *TZifSerializer) ![]u8 {
        return try self.buffer.toOwnedSlice();
    }
};

/// Serializable timezone info
pub const SerializableTTInfo = struct {
    ut_offset: i32,
    is_dst: bool,
    abbr_index: u8,

    pub fn serialize(self: SerializableTTInfo, serializer: *TZifSerializer) !void {
        try serializer.writeI32(self.ut_offset);
        try serializer.writeByte(if (self.is_dst) 1 else 0);
        try serializer.writeByte(self.abbr_index);
    }
};

/// Serializable transition
pub const SerializableTransition = struct {
    time: i64,
    type_index: u8,

    pub fn serializeV1(self: SerializableTransition, serializer: *TZifSerializer) !void {
        try serializer.writeI32(@intCast(@min(@max(self.time, -2147483648), 2147483647)));
    }

    pub fn serializeV2(self: SerializableTransition, serializer: *TZifSerializer) !void {
        try serializer.writeI64(self.time);
    }
};

/// Complete serializable zone
pub const SerializableZone = struct {
    transitions: []const SerializableTransition,
    ttinfos: []const SerializableTTInfo,
    abbreviations: []const u8,
    posix_tz: ?[]const u8 = null,

    /// Serialize to V2 TZif format
    pub fn serialize(self: SerializableZone, allocator: Allocator) ![]u8 {
        var serializer = TZifSerializer.init(allocator);
        defer serializer.deinit();

        // Write V1 header and data first (for compatibility)
        try self.writeV1Section(&serializer);

        // Write V2 header and data
        try self.writeV2Section(&serializer);

        // Write POSIX TZ string if present
        if (self.posix_tz) |tz| {
            try serializer.writeByte('\n');
            try serializer.writeBytes(tz);
            try serializer.writeByte('\n');
        }

        return try serializer.toOwnedSlice();
    }

    fn writeV1Section(self: SerializableZone, serializer: *TZifSerializer) !void {
        // Magic
        try serializer.writeBytes("TZif");
        // Version (v2)
        try serializer.writeByte('2');
        // Reserved (15 bytes)
        try serializer.writeZeros(15);

        // Counts
        try serializer.writeU32(@intCast(self.ttinfos.len)); // isut_count
        try serializer.writeU32(@intCast(self.ttinfos.len)); // isstd_count
        try serializer.writeU32(0); // leap_count
        try serializer.writeU32(@intCast(self.transitions.len)); // time_count
        try serializer.writeU32(@intCast(self.ttinfos.len)); // type_count
        try serializer.writeU32(@intCast(self.abbreviations.len)); // char_count

        // Transition times (32-bit)
        for (self.transitions) |trans| {
            try trans.serializeV1(serializer);
        }

        // Transition types
        for (self.transitions) |trans| {
            try serializer.writeByte(trans.type_index);
        }

        // TTInfos
        for (self.ttinfos) |tt| {
            try tt.serialize(serializer);
        }

        // Abbreviations
        try serializer.writeBytes(self.abbreviations);

        // Standard/wall indicators
        for (self.ttinfos) |_| {
            try serializer.writeByte(0);
        }

        // UT/local indicators
        for (self.ttinfos) |_| {
            try serializer.writeByte(0);
        }
    }

    fn writeV2Section(self: SerializableZone, serializer: *TZifSerializer) !void {
        // Magic
        try serializer.writeBytes("TZif");
        // Version (v2)
        try serializer.writeByte('2');
        // Reserved (15 bytes)
        try serializer.writeZeros(15);

        // Counts
        try serializer.writeU32(@intCast(self.ttinfos.len));
        try serializer.writeU32(@intCast(self.ttinfos.len));
        try serializer.writeU32(0);
        try serializer.writeU32(@intCast(self.transitions.len));
        try serializer.writeU32(@intCast(self.ttinfos.len));
        try serializer.writeU32(@intCast(self.abbreviations.len));

        // Transition times (64-bit)
        for (self.transitions) |trans| {
            try trans.serializeV2(serializer);
        }

        // Transition types
        for (self.transitions) |trans| {
            try serializer.writeByte(trans.type_index);
        }

        // TTInfos
        for (self.ttinfos) |tt| {
            try tt.serialize(serializer);
        }

        // Abbreviations
        try serializer.writeBytes(self.abbreviations);

        // Standard/wall indicators
        for (self.ttinfos) |_| {
            try serializer.writeByte(0);
        }

        // UT/local indicators
        for (self.ttinfos) |_| {
            try serializer.writeByte(0);
        }
    }
};

/// Zone data comparison
pub const ZoneComparator = struct {
    /// Compare two ttinfo entries
    pub fn compareTTInfo(a: SerializableTTInfo, b: SerializableTTInfo) bool {
        return a.ut_offset == b.ut_offset and
            a.is_dst == b.is_dst and
            a.abbr_index == b.abbr_index;
    }

    /// Compare two transitions
    pub fn compareTransition(a: SerializableTransition, b: SerializableTransition) bool {
        return a.time == b.time and a.type_index == b.type_index;
    }

    /// Compare entire zones
    pub fn compareZones(a: SerializableZone, b: SerializableZone) bool {
        if (a.transitions.len != b.transitions.len) return false;
        if (a.ttinfos.len != b.ttinfos.len) return false;
        if (!mem.eql(u8, a.abbreviations, b.abbreviations)) return false;

        for (a.transitions, b.transitions) |ta, tb| {
            if (!compareTransition(ta, tb)) return false;
        }

        for (a.ttinfos, b.ttinfos) |ia, ib| {
            if (!compareTTInfo(ia, ib)) return false;
        }

        return true;
    }
};

/// Zone hash calculator
pub const ZoneHasher = struct {
    /// Calculate a hash of zone data for quick comparison
    pub fn hash(zone: SerializableZone) u64 {
        var h = std.hash.Wyhash.init(0);

        for (zone.transitions) |trans| {
            h.update(mem.asBytes(&trans.time));
            h.update(&[_]u8{trans.type_index});
        }

        for (zone.ttinfos) |tt| {
            h.update(mem.asBytes(&tt.ut_offset));
            h.update(&[_]u8{ if (tt.is_dst) 1 else 0, tt.abbr_index });
        }

        h.update(zone.abbreviations);

        return h.final();
    }
};

/// Mock zones for testing
pub const MockZones = struct {
    pub fn utc() SerializableZone {
        const ttinfos = [_]SerializableTTInfo{
            .{ .ut_offset = 0, .is_dst = false, .abbr_index = 0 },
        };
        return .{
            .transitions = &[_]SerializableTransition{},
            .ttinfos = &ttinfos,
            .abbreviations = "UTC\x00",
        };
    }

    pub fn est() SerializableZone {
        const ttinfos = [_]SerializableTTInfo{
            .{ .ut_offset = -18000, .is_dst = false, .abbr_index = 0 },
        };
        return .{
            .transitions = &[_]SerializableTransition{},
            .ttinfos = &ttinfos,
            .abbreviations = "EST\x00",
        };
    }

    pub fn eastern() SerializableZone {
        const ttinfos = [_]SerializableTTInfo{
            .{ .ut_offset = -18000, .is_dst = false, .abbr_index = 0 },
            .{ .ut_offset = -14400, .is_dst = true, .abbr_index = 4 },
        };
        const transitions = [_]SerializableTransition{
            .{ .time = 1678608000, .type_index = 1 }, // Spring forward 2023
            .{ .time = 1699164000, .type_index = 0 }, // Fall back 2023
        };
        return .{
            .transitions = &transitions,
            .ttinfos = &ttinfos,
            .abbreviations = "EST\x00EDT\x00",
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "serializer_write_u32" {
    var s = TZifSerializer.init(testing.allocator);
    defer s.deinit();

    try s.writeU32(0x12345678);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x12, 0x34, 0x56, 0x78 }, s.getData());
}

test "serializer_write_i32_negative" {
    var s = TZifSerializer.init(testing.allocator);
    defer s.deinit();

    try s.writeI32(-18000);
    try testing.expectEqualSlices(u8, &[_]u8{ 0xFF, 0xFF, 0xB9, 0xB0 }, s.getData());
}

test "serializer_write_u64" {
    var s = TZifSerializer.init(testing.allocator);
    defer s.deinit();

    try s.writeU64(0x123456789ABCDEF0);
    try testing.expectEqualSlices(u8, &[_]u8{
        0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0,
    }, s.getData());
}

test "serializer_write_byte" {
    var s = TZifSerializer.init(testing.allocator);
    defer s.deinit();

    try s.writeByte(0x42);
    try testing.expectEqualSlices(u8, &[_]u8{0x42}, s.getData());
}

test "serializer_write_bytes" {
    var s = TZifSerializer.init(testing.allocator);
    defer s.deinit();

    try s.writeBytes("TZif");
    try testing.expectEqualSlices(u8, "TZif", s.getData());
}

test "serializer_write_zeros" {
    var s = TZifSerializer.init(testing.allocator);
    defer s.deinit();

    try s.writeZeros(5);
    try testing.expectEqualSlices(u8, &[_]u8{ 0, 0, 0, 0, 0 }, s.getData());
}

test "serializable_ttinfo_serialize" {
    var s = TZifSerializer.init(testing.allocator);
    defer s.deinit();

    const tt = SerializableTTInfo{
        .ut_offset = -18000,
        .is_dst = false,
        .abbr_index = 0,
    };
    try tt.serialize(&s);

    try testing.expectEqual(@as(usize, 6), s.getData().len);
}

test "serializable_transition_serialize_v1" {
    var s = TZifSerializer.init(testing.allocator);
    defer s.deinit();

    const trans = SerializableTransition{
        .time = 1000,
        .type_index = 0,
    };
    try trans.serializeV1(&s);

    try testing.expectEqual(@as(usize, 4), s.getData().len);
}

test "serializable_transition_serialize_v2" {
    var s = TZifSerializer.init(testing.allocator);
    defer s.deinit();

    const trans = SerializableTransition{
        .time = 1000,
        .type_index = 0,
    };
    try trans.serializeV2(&s);

    try testing.expectEqual(@as(usize, 8), s.getData().len);
}

test "serializable_zone_serialize_utc" {
    const zone = MockZones.utc();
    const data = try zone.serialize(testing.allocator);
    defer testing.allocator.free(data);

    // Check magic at start
    try testing.expectEqualStrings("TZif", data[0..4]);
    // Check version
    try testing.expectEqual(@as(u8, '2'), data[4]);
}

test "zone_comparator_compare_ttinfo" {
    const a = SerializableTTInfo{ .ut_offset = -18000, .is_dst = false, .abbr_index = 0 };
    const b = SerializableTTInfo{ .ut_offset = -18000, .is_dst = false, .abbr_index = 0 };
    const c = SerializableTTInfo{ .ut_offset = -14400, .is_dst = true, .abbr_index = 4 };

    try testing.expect(ZoneComparator.compareTTInfo(a, b));
    try testing.expect(!ZoneComparator.compareTTInfo(a, c));
}

test "zone_comparator_compare_transition" {
    const a = SerializableTransition{ .time = 1000, .type_index = 0 };
    const b = SerializableTransition{ .time = 1000, .type_index = 0 };
    const c = SerializableTransition{ .time = 2000, .type_index = 1 };

    try testing.expect(ZoneComparator.compareTransition(a, b));
    try testing.expect(!ZoneComparator.compareTransition(a, c));
}

test "zone_comparator_compare_zones" {
    const utc1 = MockZones.utc();
    const utc2 = MockZones.utc();
    const est = MockZones.est();

    try testing.expect(ZoneComparator.compareZones(utc1, utc2));
    try testing.expect(!ZoneComparator.compareZones(utc1, est));
}

test "zone_hasher_same_zones_same_hash" {
    const utc1 = MockZones.utc();
    const utc2 = MockZones.utc();

    try testing.expectEqual(ZoneHasher.hash(utc1), ZoneHasher.hash(utc2));
}

test "zone_hasher_different_zones_different_hash" {
    const utc = MockZones.utc();
    const est = MockZones.est();

    try testing.expect(ZoneHasher.hash(utc) != ZoneHasher.hash(est));
}

test "mock_zones_utc" {
    const zone = MockZones.utc();
    try testing.expectEqual(@as(usize, 0), zone.transitions.len);
    try testing.expectEqual(@as(usize, 1), zone.ttinfos.len);
    try testing.expectEqual(@as(i32, 0), zone.ttinfos[0].ut_offset);
}

test "mock_zones_est" {
    const zone = MockZones.est();
    try testing.expectEqual(@as(i32, -18000), zone.ttinfos[0].ut_offset);
    try testing.expect(!zone.ttinfos[0].is_dst);
}

test "mock_zones_eastern" {
    const zone = MockZones.eastern();
    try testing.expectEqual(@as(usize, 2), zone.transitions.len);
    try testing.expectEqual(@as(usize, 2), zone.ttinfos.len);
    try testing.expect(zone.ttinfos[1].is_dst);
}
