//! test.test_zoneinfo.test_part6 - Zone file parsing and validation
//!
//! This module provides TZif file format parsing:
//! - Binary file parsing for TZif versions 1, 2, 3
//! - Validation of header fields and data integrity
//! - Extraction of transitions, ttinfo, and abbreviations

const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

/// TZif file parser
pub const TZifParser = struct {
    allocator: Allocator,
    data: []const u8,
    position: usize,

    pub fn init(allocator: Allocator, data: []const u8) TZifParser {
        return .{
            .allocator = allocator,
            .data = data,
            .position = 0,
        };
    }

    /// Read a big-endian u32
    pub fn readU32(self: *TZifParser) !u32 {
        if (self.position + 4 > self.data.len) {
            return error.UnexpectedEOF;
        }
        const value = mem.readInt(u32, self.data[self.position..][0..4], .big);
        self.position += 4;
        return value;
    }

    /// Read a big-endian i32
    pub fn readI32(self: *TZifParser) !i32 {
        return @bitCast(try self.readU32());
    }

    /// Read a big-endian u64
    pub fn readU64(self: *TZifParser) !u64 {
        if (self.position + 8 > self.data.len) {
            return error.UnexpectedEOF;
        }
        const value = mem.readInt(u64, self.data[self.position..][0..8], .big);
        self.position += 8;
        return value;
    }

    /// Read a big-endian i64
    pub fn readI64(self: *TZifParser) !i64 {
        return @bitCast(try self.readU64());
    }

    /// Read a single byte
    pub fn readByte(self: *TZifParser) !u8 {
        if (self.position >= self.data.len) {
            return error.UnexpectedEOF;
        }
        const value = self.data[self.position];
        self.position += 1;
        return value;
    }

    /// Read N bytes
    pub fn readBytes(self: *TZifParser, n: usize) ![]const u8 {
        if (self.position + n > self.data.len) {
            return error.UnexpectedEOF;
        }
        const value = self.data[self.position .. self.position + n];
        self.position += n;
        return value;
    }

    /// Skip N bytes
    pub fn skip(self: *TZifParser, n: usize) !void {
        if (self.position + n > self.data.len) {
            return error.UnexpectedEOF;
        }
        self.position += n;
    }

    /// Check if at end of data
    pub fn isEOF(self: *const TZifParser) bool {
        return self.position >= self.data.len;
    }

    /// Remaining bytes
    pub fn remaining(self: *const TZifParser) usize {
        if (self.position >= self.data.len) return 0;
        return self.data.len - self.position;
    }
};

/// Parsed TZif header
pub const ParsedHeader = struct {
    magic: [4]u8,
    version: u8,
    isut_count: u32,
    isstd_count: u32,
    leap_count: u32,
    time_count: u32,
    type_count: u32,
    char_count: u32,

    pub fn parse(parser: *TZifParser) !ParsedHeader {
        const magic = try parser.readBytes(4);
        const version = try parser.readByte();
        try parser.skip(15); // reserved

        return .{
            .magic = magic[0..4].*,
            .version = version,
            .isut_count = try parser.readU32(),
            .isstd_count = try parser.readU32(),
            .leap_count = try parser.readU32(),
            .time_count = try parser.readU32(),
            .type_count = try parser.readU32(),
            .char_count = try parser.readU32(),
        };
    }

    pub fn isValid(self: ParsedHeader) bool {
        return mem.eql(u8, &self.magic, "TZif");
    }

    pub fn isV2orV3(self: ParsedHeader) bool {
        return self.version == '2' or self.version == '3';
    }

    /// Calculate size of v1 data block
    pub fn v1DataSize(self: ParsedHeader) usize {
        return self.time_count * 4 + // transition times
            self.time_count + // transition types
            self.type_count * 6 + // ttinfos
            self.char_count + // abbreviations
            self.leap_count * 8 + // leap seconds
            self.isstd_count +
            self.isut_count;
    }
};

/// Parsed ttinfo entry
pub const ParsedTTInfo = struct {
    ut_offset: i32,
    is_dst: bool,
    abbr_idx: u8,

    pub fn parse(parser: *TZifParser) !ParsedTTInfo {
        return .{
            .ut_offset = try parser.readI32(),
            .is_dst = (try parser.readByte()) != 0,
            .abbr_idx = try parser.readByte(),
        };
    }
};

/// Parsed transition entry
pub const ParsedTransition = struct {
    time: i64,
    type_idx: u8,
};

/// Complete parsed TZif file
pub const ParsedTZif = struct {
    header: ParsedHeader,
    transitions: []ParsedTransition,
    ttinfos: []ParsedTTInfo,
    abbreviations: []const u8,
    posix_tz: ?[]const u8,
    allocator: Allocator,

    pub fn deinit(self: *ParsedTZif) void {
        self.allocator.free(self.transitions);
        self.allocator.free(self.ttinfos);
        self.allocator.free(self.abbreviations);
        if (self.posix_tz) |tz| {
            self.allocator.free(tz);
        }
    }

    /// Get abbreviation for a ttinfo index
    pub fn getAbbrev(self: ParsedTZif, idx: u8) []const u8 {
        if (idx >= self.abbreviations.len) return "???";
        var end: usize = idx;
        while (end < self.abbreviations.len and self.abbreviations[end] != 0) {
            end += 1;
        }
        return self.abbreviations[idx..end];
    }
};

/// Validation result
pub const ValidationResult = struct {
    is_valid: bool,
    errors: std.ArrayList([]const u8),
    warnings: std.ArrayList([]const u8),

    pub fn init(allocator: Allocator) ValidationResult {
        return .{
            .is_valid = true,
            .errors = std.ArrayList([]const u8).init(allocator),
            .warnings = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *ValidationResult) void {
        self.errors.deinit();
        self.warnings.deinit();
    }

    pub fn addError(self: *ValidationResult, msg: []const u8) void {
        self.is_valid = false;
        self.errors.append(msg) catch {};
    }

    pub fn addWarning(self: *ValidationResult, msg: []const u8) void {
        self.warnings.append(msg) catch {};
    }
};

/// TZif file validator
pub const TZifValidator = struct {
    /// Validate a parsed TZif file
    pub fn validate(parsed: ParsedTZif, allocator: Allocator) ValidationResult {
        var result = ValidationResult.init(allocator);

        // Check magic
        if (!parsed.header.isValid()) {
            result.addError("Invalid magic number");
        }

        // Check version
        if (parsed.header.version != 0 and
            parsed.header.version != '2' and
            parsed.header.version != '3')
        {
            result.addError("Unknown version");
        }

        // Check type count > 0
        if (parsed.header.type_count == 0) {
            result.addError("No ttinfo entries");
        }

        // Check transitions are sorted
        var prev_time: i64 = std.math.minInt(i64);
        for (parsed.transitions) |trans| {
            if (trans.time < prev_time) {
                result.addError("Transitions not sorted");
                break;
            }
            prev_time = trans.time;
        }

        // Check type indices valid
        for (parsed.transitions) |trans| {
            if (trans.type_idx >= parsed.ttinfos.len) {
                result.addError("Invalid type index in transition");
                break;
            }
        }

        // Check abbreviation indices valid
        for (parsed.ttinfos) |tt| {
            if (tt.abbr_idx >= parsed.abbreviations.len) {
                result.addWarning("Abbreviation index out of bounds");
            }
        }

        return result;
    }
};

/// Zone data builder for testing
pub const ZoneDataBuilder = struct {
    transitions: std.ArrayList(ParsedTransition),
    ttinfos: std.ArrayList(ParsedTTInfo),
    abbrevs: std.ArrayList(u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator) ZoneDataBuilder {
        return .{
            .transitions = std.ArrayList(ParsedTransition).init(allocator),
            .ttinfos = std.ArrayList(ParsedTTInfo).init(allocator),
            .abbrevs = std.ArrayList(u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ZoneDataBuilder) void {
        self.transitions.deinit();
        self.ttinfos.deinit();
        self.abbrevs.deinit();
    }

    /// Add a ttinfo entry and return its index
    pub fn addTTInfo(self: *ZoneDataBuilder, offset: i32, is_dst: bool, abbr: []const u8) !u8 {
        const abbr_idx: u8 = @intCast(self.abbrevs.items.len);
        try self.abbrevs.appendSlice(abbr);
        try self.abbrevs.append(0); // null terminator

        const idx: u8 = @intCast(self.ttinfos.items.len);
        try self.ttinfos.append(.{
            .ut_offset = offset,
            .is_dst = is_dst,
            .abbr_idx = abbr_idx,
        });
        return idx;
    }

    /// Add a transition
    pub fn addTransition(self: *ZoneDataBuilder, time: i64, type_idx: u8) !void {
        try self.transitions.append(.{
            .time = time,
            .type_idx = type_idx,
        });
    }

    /// Build the parsed result
    pub fn build(self: *ZoneDataBuilder) !ParsedTZif {
        return .{
            .header = .{
                .magic = "TZif".*,
                .version = '2',
                .isut_count = 0,
                .isstd_count = 0,
                .leap_count = 0,
                .time_count = @intCast(self.transitions.items.len),
                .type_count = @intCast(self.ttinfos.items.len),
                .char_count = @intCast(self.abbrevs.items.len),
            },
            .transitions = try self.transitions.toOwnedSlice(),
            .ttinfos = try self.ttinfos.toOwnedSlice(),
            .abbreviations = try self.abbrevs.toOwnedSlice(),
            .posix_tz = null,
            .allocator = self.allocator,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "tzif_parser_read_u32" {
    const data = [_]u8{ 0x00, 0x00, 0x01, 0x00 };
    var parser = TZifParser.init(testing.allocator, &data);
    const value = try parser.readU32();
    try testing.expectEqual(@as(u32, 256), value);
}

test "tzif_parser_read_i32_negative" {
    const data = [_]u8{ 0xFF, 0xFF, 0xB9, 0xB0 }; // -18000
    var parser = TZifParser.init(testing.allocator, &data);
    const value = try parser.readI32();
    try testing.expectEqual(@as(i32, -18000), value);
}

test "tzif_parser_read_u64" {
    const data = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x5F, 0x5E, 0x10, 0x00 };
    var parser = TZifParser.init(testing.allocator, &data);
    const value = try parser.readU64();
    try testing.expectEqual(@as(u64, 1600000000), value);
}

test "tzif_parser_read_byte" {
    const data = [_]u8{ 0x42 };
    var parser = TZifParser.init(testing.allocator, &data);
    const value = try parser.readByte();
    try testing.expectEqual(@as(u8, 0x42), value);
}

test "tzif_parser_read_bytes" {
    const data = [_]u8{ 'T', 'Z', 'i', 'f', '2' };
    var parser = TZifParser.init(testing.allocator, &data);
    const magic = try parser.readBytes(4);
    try testing.expectEqualStrings("TZif", magic);
}

test "tzif_parser_skip" {
    const data = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    var parser = TZifParser.init(testing.allocator, &data);
    try parser.skip(4);
    try testing.expectEqual(@as(usize, 4), parser.position);
    try testing.expectEqual(@as(usize, 4), parser.remaining());
}

test "tzif_parser_eof" {
    const data = [_]u8{ 1, 2 };
    var parser = TZifParser.init(testing.allocator, &data);
    try testing.expect(!parser.isEOF());
    try parser.skip(2);
    try testing.expect(parser.isEOF());
}

test "tzif_parser_unexpected_eof" {
    const data = [_]u8{ 1, 2 };
    var parser = TZifParser.init(testing.allocator, &data);
    try testing.expectError(error.UnexpectedEOF, parser.readU32());
}

test "parsed_header_is_valid" {
    const valid = ParsedHeader{
        .magic = "TZif".*,
        .version = '2',
        .isut_count = 0,
        .isstd_count = 0,
        .leap_count = 0,
        .time_count = 0,
        .type_count = 1,
        .char_count = 4,
    };
    try testing.expect(valid.isValid());

    const invalid = ParsedHeader{
        .magic = "XXXX".*,
        .version = '2',
        .isut_count = 0,
        .isstd_count = 0,
        .leap_count = 0,
        .time_count = 0,
        .type_count = 1,
        .char_count = 4,
    };
    try testing.expect(!invalid.isValid());
}

test "parsed_header_is_v2_or_v3" {
    const v1 = ParsedHeader{
        .magic = "TZif".*,
        .version = 0,
        .isut_count = 0,
        .isstd_count = 0,
        .leap_count = 0,
        .time_count = 0,
        .type_count = 1,
        .char_count = 4,
    };
    try testing.expect(!v1.isV2orV3());

    const v2 = ParsedHeader{
        .magic = "TZif".*,
        .version = '2',
        .isut_count = 0,
        .isstd_count = 0,
        .leap_count = 0,
        .time_count = 0,
        .type_count = 1,
        .char_count = 4,
    };
    try testing.expect(v2.isV2orV3());
}

test "parsed_header_v1_data_size" {
    const header = ParsedHeader{
        .magic = "TZif".*,
        .version = 0,
        .isut_count = 2,
        .isstd_count = 2,
        .leap_count = 1,
        .time_count = 5,
        .type_count = 2,
        .char_count = 8,
    };
    // 5*4 + 5 + 2*6 + 8 + 1*8 + 2 + 2 = 20 + 5 + 12 + 8 + 8 + 2 + 2 = 57
    try testing.expectEqual(@as(usize, 57), header.v1DataSize());
}

test "zone_data_builder_add_ttinfo" {
    var builder = ZoneDataBuilder.init(testing.allocator);
    defer builder.deinit();

    const idx1 = try builder.addTTInfo(-18000, false, "EST");
    const idx2 = try builder.addTTInfo(-14400, true, "EDT");

    try testing.expectEqual(@as(u8, 0), idx1);
    try testing.expectEqual(@as(u8, 1), idx2);
    try testing.expectEqual(@as(usize, 2), builder.ttinfos.items.len);
}

test "zone_data_builder_add_transition" {
    var builder = ZoneDataBuilder.init(testing.allocator);
    defer builder.deinit();

    _ = try builder.addTTInfo(0, false, "UTC");
    try builder.addTransition(1000, 0);
    try builder.addTransition(2000, 0);

    try testing.expectEqual(@as(usize, 2), builder.transitions.items.len);
}

test "zone_data_builder_build" {
    var builder = ZoneDataBuilder.init(testing.allocator);
    defer builder.deinit();

    _ = try builder.addTTInfo(-18000, false, "EST");
    _ = try builder.addTTInfo(-14400, true, "EDT");
    try builder.addTransition(1000, 1);
    try builder.addTransition(2000, 0);

    var parsed = try builder.build();
    defer parsed.deinit();

    try testing.expect(parsed.header.isValid());
    try testing.expectEqual(@as(u32, 2), parsed.header.time_count);
    try testing.expectEqual(@as(u32, 2), parsed.header.type_count);
}

test "parsed_tzif_get_abbrev" {
    var builder = ZoneDataBuilder.init(testing.allocator);
    defer builder.deinit();

    _ = try builder.addTTInfo(-18000, false, "EST");
    _ = try builder.addTTInfo(-14400, true, "EDT");

    var parsed = try builder.build();
    defer parsed.deinit();

    try testing.expectEqualStrings("EST", parsed.getAbbrev(0));
    try testing.expectEqualStrings("EDT", parsed.getAbbrev(4));
}

test "validation_result_add_error" {
    var result = ValidationResult.init(testing.allocator);
    defer result.deinit();

    try testing.expect(result.is_valid);
    result.addError("Test error");
    try testing.expect(!result.is_valid);
    try testing.expectEqual(@as(usize, 1), result.errors.items.len);
}

test "tzif_validator_valid_data" {
    var builder = ZoneDataBuilder.init(testing.allocator);
    defer builder.deinit();

    _ = try builder.addTTInfo(0, false, "UTC");
    try builder.addTransition(1000, 0);

    var parsed = try builder.build();
    defer parsed.deinit();

    var result = TZifValidator.validate(parsed, testing.allocator);
    defer result.deinit();

    try testing.expect(result.is_valid);
}

test "tzif_validator_invalid_magic" {
    var parsed = ParsedTZif{
        .header = .{
            .magic = "XXXX".*,
            .version = '2',
            .isut_count = 0,
            .isstd_count = 0,
            .leap_count = 0,
            .time_count = 0,
            .type_count = 1,
            .char_count = 4,
        },
        .transitions = &[_]ParsedTransition{},
        .ttinfos = &[_]ParsedTTInfo{},
        .abbreviations = "UTC\x00",
        .posix_tz = null,
        .allocator = testing.allocator,
    };

    var result = TZifValidator.validate(parsed, testing.allocator);
    defer result.deinit();

    try testing.expect(!result.is_valid);
}
