//! test.test_zipfile.test_testzip - ZIP archive validation tests
//!
//! Tests for validating ZIP archive integrity including CRC checks,
//! structure validation, and error detection.

const std = @import("std");
const testing = std.testing;
const mem = std.mem;

// ============================================================================
// Validation Constants
// ============================================================================

/// ZIP signature bytes
const ZIP_LOCAL_MAGIC: [4]u8 = .{ 0x50, 0x4b, 0x03, 0x04 };
const ZIP_CENTRAL_MAGIC: [4]u8 = .{ 0x50, 0x4b, 0x01, 0x02 };
const ZIP_END_MAGIC: [4]u8 = .{ 0x50, 0x4b, 0x05, 0x06 };
const ZIP64_END_MAGIC: [4]u8 = .{ 0x50, 0x4b, 0x06, 0x06 };
const ZIP64_LOCATOR_MAGIC: [4]u8 = .{ 0x50, 0x4b, 0x06, 0x07 };

// ============================================================================
// Validation Result
// ============================================================================

pub const ValidationResult = struct {
    valid: bool = true,
    errors: std.ArrayList(ValidationError),
    warnings: std.ArrayList(ValidationWarning),

    pub const ValidationError = struct {
        code: ErrorCode,
        filename: ?[]const u8 = null,
        offset: ?u64 = null,
        message: []const u8,

        pub const ErrorCode = enum {
            bad_magic,
            bad_crc,
            truncated_file,
            missing_central_dir,
            corrupted_central_dir,
            file_size_mismatch,
            encryption_error,
            unsupported_compression,
            invalid_filename,
            invalid_extra_field,
            bad_data_descriptor,
        };
    };

    pub const ValidationWarning = struct {
        code: WarningCode,
        message: []const u8,

        pub const WarningCode = enum {
            duplicate_filename,
            empty_archive,
            suspicious_size,
            old_version,
            non_standard_extension,
        };
    };

    pub fn init(allocator: mem.Allocator) ValidationResult {
        return .{
            .errors = std.ArrayList(ValidationError).init(allocator),
            .warnings = std.ArrayList(ValidationWarning).init(allocator),
        };
    }

    pub fn deinit(self: *ValidationResult) void {
        self.errors.deinit();
        self.warnings.deinit();
    }

    pub fn addError(self: *ValidationResult, err: ValidationError) !void {
        self.valid = false;
        try self.errors.append(err);
    }

    pub fn addWarning(self: *ValidationResult, warn: ValidationWarning) !void {
        try self.warnings.append(warn);
    }

    pub fn isValid(self: ValidationResult) bool {
        return self.valid;
    }

    pub fn hasWarnings(self: ValidationResult) bool {
        return self.warnings.items.len > 0;
    }

    pub fn errorCount(self: ValidationResult) usize {
        return self.errors.items.len;
    }

    pub fn warningCount(self: ValidationResult) usize {
        return self.warnings.items.len;
    }
};

// ============================================================================
// ZIP Validator
// ============================================================================

pub const ZipValidator = struct {
    const Self = @This();

    allocator: mem.Allocator,
    strict_mode: bool = true,
    check_crc: bool = true,
    check_sizes: bool = true,
    max_file_count: u32 = 65535,
    max_comment_length: u16 = 65535,

    pub fn init(allocator: mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    /// Validate ZIP data
    pub fn validate(self: *Self, data: []const u8) !ValidationResult {
        var result = ValidationResult.init(self.allocator);
        errdefer result.deinit();

        // Check minimum size
        if (data.len < 22) {
            try result.addError(.{
                .code = .truncated_file,
                .message = "File too small to be a valid ZIP",
            });
            return result;
        }

        // Check for ZIP signature at start
        if (!self.hasValidMagic(data)) {
            try result.addError(.{
                .code = .bad_magic,
                .message = "Invalid ZIP signature",
            });
            return result;
        }

        // Find and validate end of central directory
        const eocd = self.findEndOfCentralDirectory(data);
        if (eocd == null) {
            try result.addError(.{
                .code = .missing_central_dir,
                .message = "End of central directory not found",
            });
            return result;
        }

        // Validate central directory structure
        try self.validateCentralDirectory(data, eocd.?, &result);

        // Check for empty archive
        if (self.getFileCount(data, eocd.?) == 0) {
            try result.addWarning(.{
                .code = .empty_archive,
                .message = "Archive contains no files",
            });
        }

        return result;
    }

    /// Check if data starts with valid ZIP magic
    fn hasValidMagic(self: *Self, data: []const u8) bool {
        _ = self;
        if (data.len < 4) return false;
        return mem.eql(u8, data[0..4], &ZIP_LOCAL_MAGIC);
    }

    /// Find end of central directory record
    fn findEndOfCentralDirectory(self: *Self, data: []const u8) ?usize {
        _ = self;
        // Search backwards from end
        const search_start = if (data.len > 65557) data.len - 65557 else 0;

        var i: usize = data.len - 22;
        while (i >= search_start) : (i -= 1) {
            if (mem.eql(u8, data[i..][0..4], &ZIP_END_MAGIC)) {
                return i;
            }
            if (i == 0) break;
        }
        return null;
    }

    /// Get file count from end of central directory
    fn getFileCount(self: *Self, data: []const u8, eocd_offset: usize) u16 {
        _ = self;
        if (eocd_offset + 12 > data.len) return 0;
        return mem.readInt(u16, data[eocd_offset + 10 ..][0..2], .little);
    }

    /// Validate central directory structure
    fn validateCentralDirectory(self: *Self, data: []const u8, eocd_offset: usize, result: *ValidationResult) !void {
        if (eocd_offset + 22 > data.len) {
            try result.addError(.{
                .code = .corrupted_central_dir,
                .message = "End of central directory truncated",
            });
            return;
        }

        const num_entries = mem.readInt(u16, data[eocd_offset + 10 ..][0..2], .little);
        const cd_size = mem.readInt(u32, data[eocd_offset + 12 ..][0..4], .little);
        const cd_offset = mem.readInt(u32, data[eocd_offset + 16 ..][0..4], .little);

        // Validate central directory location
        if (cd_offset + cd_size > eocd_offset) {
            try result.addError(.{
                .code = .corrupted_central_dir,
                .message = "Central directory size mismatch",
            });
            return;
        }

        // Validate each entry if strict mode
        if (self.strict_mode) {
            try self.validateEntries(data, cd_offset, num_entries, result);
        }
    }

    /// Validate individual entries
    fn validateEntries(self: *Self, data: []const u8, cd_offset: u32, num_entries: u16, result: *ValidationResult) !void {
        _ = self;
        var offset: usize = cd_offset;

        for (0..num_entries) |_| {
            if (offset + 46 > data.len) {
                try result.addError(.{
                    .code = .corrupted_central_dir,
                    .offset = offset,
                    .message = "Central directory entry truncated",
                });
                return;
            }

            // Check signature
            if (!mem.eql(u8, data[offset..][0..4], &ZIP_CENTRAL_MAGIC)) {
                try result.addError(.{
                    .code = .bad_magic,
                    .offset = offset,
                    .message = "Invalid central directory entry signature",
                });
                return;
            }

            const name_len = mem.readInt(u16, data[offset + 28 ..][0..2], .little);
            const extra_len = mem.readInt(u16, data[offset + 30 ..][0..2], .little);
            const comment_len = mem.readInt(u16, data[offset + 32 ..][0..2], .little);

            offset += 46 + name_len + extra_len + comment_len;
        }
    }
};

// ============================================================================
// CRC Verification
// ============================================================================

pub const CrcVerifier = struct {
    const Self = @This();

    /// Calculate CRC32 of data
    pub fn calculate(data: []const u8) u32 {
        return std.hash.crc.Crc32.hash(data);
    }

    /// Verify CRC matches expected value
    pub fn verify(data: []const u8, expected: u32) bool {
        return calculate(data) == expected;
    }

    /// Create streaming CRC calculator
    pub fn init() std.hash.crc.Crc32 {
        return std.hash.crc.Crc32.init();
    }
};

// ============================================================================
// Test ZIP Builder (for creating test fixtures)
// ============================================================================

pub const TestZipBuilder = struct {
    const Self = @This();

    allocator: mem.Allocator,
    buffer: std.ArrayList(u8),

    pub fn init(allocator: mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
    }

    /// Create minimal valid ZIP
    pub fn createMinimalZip(self: *Self) ![]const u8 {
        // Local file header
        try self.buffer.appendSlice(&ZIP_LOCAL_MAGIC);
        try self.buffer.appendSlice(&[_]u8{0} ** 26); // Header fields
        // No filename, no data

        const cd_offset = self.buffer.items.len;

        // Central directory entry (minimal)
        try self.buffer.appendSlice(&ZIP_CENTRAL_MAGIC);
        try self.buffer.appendSlice(&[_]u8{0} ** 42); // Header fields

        const cd_size = self.buffer.items.len - cd_offset;

        // End of central directory
        try self.buffer.appendSlice(&ZIP_END_MAGIC);
        try self.buffer.appendSlice(&[_]u8{ 0, 0, 0, 0 }); // Disk numbers
        try self.buffer.appendSlice(&[_]u8{ 1, 0, 1, 0 }); // Entry counts
        try self.buffer.writer().writeInt(u32, @intCast(cd_size), .little);
        try self.buffer.writer().writeInt(u32, @intCast(cd_offset), .little);
        try self.buffer.appendSlice(&[_]u8{ 0, 0 }); // Comment length

        return self.buffer.items;
    }

    /// Create empty (but valid) ZIP
    pub fn createEmptyZip(self: *Self) ![]const u8 {
        // Just end of central directory
        try self.buffer.appendSlice(&ZIP_END_MAGIC);
        try self.buffer.appendSlice(&[_]u8{ 0, 0, 0, 0 }); // Disk numbers
        try self.buffer.appendSlice(&[_]u8{ 0, 0, 0, 0 }); // Entry counts (0)
        try self.buffer.appendSlice(&[_]u8{ 0, 0, 0, 0 }); // CD size (0)
        try self.buffer.appendSlice(&[_]u8{ 0, 0, 0, 0 }); // CD offset (0)
        try self.buffer.appendSlice(&[_]u8{ 0, 0 }); // Comment length

        return self.buffer.items;
    }

    /// Create corrupted ZIP
    pub fn createCorruptedZip(self: *Self) ![]const u8 {
        try self.buffer.appendSlice(&ZIP_LOCAL_MAGIC);
        try self.buffer.appendSlice("CORRUPTED DATA");
        return self.buffer.items;
    }
};

// ============================================================================
// Quick Validation Functions
// ============================================================================

/// Quick check if data appears to be a ZIP file
pub fn isZipFile(data: []const u8) bool {
    if (data.len < 4) return false;
    return mem.eql(u8, data[0..4], &ZIP_LOCAL_MAGIC);
}

/// Check if ZIP appears to be valid (basic check)
pub fn isValidZip(data: []const u8) bool {
    if (!isZipFile(data)) return false;
    if (data.len < 22) return false;

    // Look for end of central directory
    var i: usize = data.len - 22;
    const search_limit = if (data.len > 65557) data.len - 65557 else 0;

    while (i >= search_limit) : (i -= 1) {
        if (mem.eql(u8, data[i..][0..4], &ZIP_END_MAGIC)) {
            return true;
        }
        if (i == 0) break;
    }
    return false;
}

/// Get archive comment if present
pub fn getArchiveComment(data: []const u8) ?[]const u8 {
    if (data.len < 22) return null;

    // Find EOCD
    var i: usize = data.len - 22;
    const search_limit = if (data.len > 65557) data.len - 65557 else 0;

    while (i >= search_limit) : (i -= 1) {
        if (mem.eql(u8, data[i..][0..4], &ZIP_END_MAGIC)) {
            const comment_len = mem.readInt(u16, data[i + 20 ..][0..2], .little);
            if (comment_len > 0 and i + 22 + comment_len <= data.len) {
                return data[i + 22 ..][0..comment_len];
            }
            return null;
        }
        if (i == 0) break;
    }
    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "ValidationResult init" {
    var result = ValidationResult.init(testing.allocator);
    defer result.deinit();

    try testing.expect(result.isValid());
    try testing.expect(!result.hasWarnings());
    try testing.expectEqual(@as(usize, 0), result.errorCount());
}

test "ValidationResult addError" {
    var result = ValidationResult.init(testing.allocator);
    defer result.deinit();

    try result.addError(.{
        .code = .bad_magic,
        .message = "Test error",
    });

    try testing.expect(!result.isValid());
    try testing.expectEqual(@as(usize, 1), result.errorCount());
}

test "ValidationResult addWarning" {
    var result = ValidationResult.init(testing.allocator);
    defer result.deinit();

    try result.addWarning(.{
        .code = .empty_archive,
        .message = "Test warning",
    });

    try testing.expect(result.isValid());
    try testing.expect(result.hasWarnings());
    try testing.expectEqual(@as(usize, 1), result.warningCount());
}

test "ZipValidator init" {
    const validator = ZipValidator.init(testing.allocator);
    try testing.expect(validator.strict_mode);
    try testing.expect(validator.check_crc);
}

test "ZipValidator validate too small" {
    var validator = ZipValidator.init(testing.allocator);
    const small_data = "too small";

    var result = try validator.validate(small_data);
    defer result.deinit();

    try testing.expect(!result.isValid());
    try testing.expect(result.errorCount() > 0);
}

test "ZipValidator validate bad magic" {
    var validator = ZipValidator.init(testing.allocator);
    const bad_data = [_]u8{0} ** 100;

    var result = try validator.validate(&bad_data);
    defer result.deinit();

    try testing.expect(!result.isValid());
    try testing.expectEqual(ValidationResult.ValidationError.ErrorCode.bad_magic, result.errors.items[0].code);
}

test "CrcVerifier calculate" {
    const data = "Hello, World!";
    const crc = CrcVerifier.calculate(data);
    try testing.expect(crc != 0);
}

test "CrcVerifier verify correct" {
    const data = "Test data";
    const expected = CrcVerifier.calculate(data);
    try testing.expect(CrcVerifier.verify(data, expected));
}

test "CrcVerifier verify incorrect" {
    const data = "Test data";
    try testing.expect(!CrcVerifier.verify(data, 0x12345678));
}

test "TestZipBuilder createEmptyZip" {
    var builder = TestZipBuilder.init(testing.allocator);
    defer builder.deinit();

    const zip = try builder.createEmptyZip();
    try testing.expect(zip.len >= 22);
    try testing.expect(mem.eql(u8, zip[0..4], &ZIP_END_MAGIC));
}

test "isZipFile valid" {
    const valid = [_]u8{ 0x50, 0x4b, 0x03, 0x04, 0, 0, 0, 0 };
    try testing.expect(isZipFile(&valid));
}

test "isZipFile invalid" {
    const invalid = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 };
    try testing.expect(!isZipFile(&invalid));
}

test "isZipFile too short" {
    const short = [_]u8{ 0x50, 0x4b };
    try testing.expect(!isZipFile(&short));
}

test "isValidZip empty" {
    var builder = TestZipBuilder.init(testing.allocator);
    defer builder.deinit();

    const zip = try builder.createEmptyZip();
    try testing.expect(isValidZip(zip));
}

test "isValidZip corrupted" {
    var builder = TestZipBuilder.init(testing.allocator);
    defer builder.deinit();

    const zip = try builder.createCorruptedZip();
    try testing.expect(!isValidZip(zip));
}

test "getArchiveComment no comment" {
    var builder = TestZipBuilder.init(testing.allocator);
    defer builder.deinit();

    const zip = try builder.createEmptyZip();
    try testing.expect(getArchiveComment(zip) == null);
}

test "ValidationError codes" {
    const err = ValidationResult.ValidationError{
        .code = .bad_crc,
        .message = "CRC mismatch",
    };
    try testing.expectEqual(ValidationResult.ValidationError.ErrorCode.bad_crc, err.code);
}

test "ValidationWarning codes" {
    const warn = ValidationResult.ValidationWarning{
        .code = .duplicate_filename,
        .message = "Duplicate found",
    };
    try testing.expectEqual(ValidationResult.ValidationWarning.WarningCode.duplicate_filename, warn.code);
}

test "CrcVerifier streaming" {
    var hasher = CrcVerifier.init();
    hasher.update("Hello, ");
    hasher.update("World!");
    const crc = hasher.final();

    const expected = CrcVerifier.calculate("Hello, World!");
    try testing.expectEqual(expected, crc);
}

test "ZIP magic constants" {
    try testing.expectEqual(@as(u8, 0x50), ZIP_LOCAL_MAGIC[0]);
    try testing.expectEqual(@as(u8, 0x4b), ZIP_LOCAL_MAGIC[1]);
    try testing.expectEqual(@as(u8, 0x03), ZIP_LOCAL_MAGIC[2]);
    try testing.expectEqual(@as(u8, 0x04), ZIP_LOCAL_MAGIC[3]);
}
