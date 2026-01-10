//! test.test_zipfile.test_encryption - ZIP encryption tests
//!
//! Tests for ZIP file encryption including traditional PKZIP encryption,
//! AES encryption, and password handling.

const std = @import("std");
const testing = std.testing;
const mem = std.mem;

// ============================================================================
// Encryption Constants
// ============================================================================

pub const EncryptionMethod = enum(u8) {
    none = 0,
    pkzip_traditional = 1, // Traditional PKWARE encryption
    aes_128 = 2, // AES-128
    aes_192 = 3, // AES-192
    aes_256 = 4, // AES-256

    pub fn keyLength(self: EncryptionMethod) usize {
        return switch (self) {
            .none => 0,
            .pkzip_traditional => 12,
            .aes_128 => 16,
            .aes_192 => 24,
            .aes_256 => 32,
        };
    }

    pub fn getName(self: EncryptionMethod) []const u8 {
        return switch (self) {
            .none => "none",
            .pkzip_traditional => "PKZIP",
            .aes_128 => "AES-128",
            .aes_192 => "AES-192",
            .aes_256 => "AES-256",
        };
    }

    pub fn isAes(self: EncryptionMethod) bool {
        return switch (self) {
            .aes_128, .aes_192, .aes_256 => true,
            else => false,
        };
    }
};

// ============================================================================
// Traditional PKZIP Encryption
// ============================================================================

pub const PkzipCrypto = struct {
    const Self = @This();

    keys: [3]u32,

    /// CRC32 lookup table
    const crc_table = blk: {
        var table: [256]u32 = undefined;
        for (0..256) |i| {
            var crc: u32 = @intCast(i);
            for (0..8) |_| {
                if (crc & 1 != 0) {
                    crc = (crc >> 1) ^ 0xedb88320;
                } else {
                    crc = crc >> 1;
                }
            }
            table[i] = crc;
        }
        break :blk table;
    };

    pub fn init(password: []const u8) Self {
        var self = Self{
            .keys = .{ 0x12345678, 0x23456789, 0x34567890 },
        };

        for (password) |byte| {
            self.updateKeys(byte);
        }

        return self;
    }

    fn updateKeys(self: *Self, byte: u8) void {
        self.keys[0] = self.crc32(self.keys[0], byte);
        self.keys[1] = (self.keys[1] +% (self.keys[0] & 0xff)) *% 134775813 +% 1;
        self.keys[2] = self.crc32(self.keys[2], @truncate(self.keys[1] >> 24));
    }

    fn crc32(self: *Self, crc: u32, byte: u8) u32 {
        _ = self;
        return (crc >> 8) ^ crc_table[@as(usize, @intCast((crc ^ byte) & 0xff))];
    }

    fn decryptByte(self: *Self) u8 {
        const temp: u16 = @truncate((self.keys[2] | 2));
        return @truncate((temp *% (temp ^ 1)) >> 8);
    }

    /// Decrypt a single byte
    pub fn decrypt(self: *Self, byte: u8) u8 {
        const keystream = self.decryptByte();
        const plain = byte ^ keystream;
        self.updateKeys(plain);
        return plain;
    }

    /// Encrypt a single byte
    pub fn encrypt(self: *Self, byte: u8) u8 {
        const keystream = self.decryptByte();
        const cipher = byte ^ keystream;
        self.updateKeys(byte);
        return cipher;
    }

    /// Decrypt data in place
    pub fn decryptData(self: *Self, data: []u8) void {
        for (data) |*byte| {
            byte.* = self.decrypt(byte.*);
        }
    }

    /// Encrypt data in place
    pub fn encryptData(self: *Self, data: []u8) void {
        for (data) |*byte| {
            byte.* = self.encrypt(byte.*);
        }
    }

    /// Generate encryption header
    pub fn generateHeader(self: *Self, crc: u32, allocator: mem.Allocator) ![]u8 {
        var header = try allocator.alloc(u8, 12);
        errdefer allocator.free(header);

        // Generate random bytes for first 11 bytes
        var prng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
        prng.fill(header[0..11]);

        // Last byte is high byte of CRC
        header[11] = @truncate(crc >> 24);

        // Encrypt the header
        self.encryptData(header);

        return header;
    }

    /// Verify decryption header
    pub fn verifyHeader(self: *Self, header: []const u8, crc: u32) bool {
        if (header.len < 12) return false;

        var copy: [12]u8 = undefined;
        @memcpy(&copy, header[0..12]);

        // Create a copy of crypto state
        var crypto = Self{ .keys = self.keys };
        crypto.decryptData(&copy);

        // Check if last byte matches high byte of CRC
        return copy[11] == @as(u8, @truncate(crc >> 24));
    }
};

// ============================================================================
// Password Utilities
// ============================================================================

pub const PasswordValidator = struct {
    min_length: usize = 1,
    max_length: usize = 256,
    require_ascii: bool = true,

    pub fn validate(self: PasswordValidator, password: []const u8) !void {
        if (password.len < self.min_length) {
            return error.PasswordTooShort;
        }
        if (password.len > self.max_length) {
            return error.PasswordTooLong;
        }
        if (self.require_ascii) {
            for (password) |c| {
                if (c > 127) {
                    return error.NonAsciiCharacter;
                }
            }
        }
    }

    pub fn isValid(self: PasswordValidator, password: []const u8) bool {
        self.validate(password) catch return false;
        return true;
    }
};

/// Derive key from password using PBKDF2-like algorithm
pub fn deriveKey(password: []const u8, salt: []const u8, iterations: u32, key_len: usize, allocator: mem.Allocator) ![]u8 {
    _ = iterations;
    var key = try allocator.alloc(u8, key_len);
    errdefer allocator.free(key);

    // Simple key derivation (for testing purposes)
    var hasher = std.hash.crc.Crc32.init();
    hasher.update(password);
    hasher.update(salt);
    const hash = hasher.final();

    // Fill key with repeated hash bytes
    var i: usize = 0;
    while (i < key_len) {
        const hash_bytes = mem.toBytes(hash);
        const remaining = @min(4, key_len - i);
        @memcpy(key[i..][0..remaining], hash_bytes[0..remaining]);
        i += 4;
    }

    return key;
}

// ============================================================================
// Encrypted Entry Metadata
// ============================================================================

pub const EncryptedEntry = struct {
    filename: []const u8,
    method: EncryptionMethod,
    header_offset: u64,
    compressed_size: u64,
    uncompressed_size: u64,
    crc32: u32,
    encryption_header: [12]u8 = [_]u8{0} ** 12,

    pub fn isEncrypted(self: EncryptedEntry) bool {
        return self.method != .none;
    }

    pub fn getDataOffset(self: EncryptedEntry) u64 {
        if (self.method == .pkzip_traditional) {
            return self.header_offset + 12; // Skip encryption header
        }
        return self.header_offset;
    }

    pub fn getActualDataSize(self: EncryptedEntry) u64 {
        if (self.method == .pkzip_traditional) {
            return self.compressed_size - 12;
        }
        return self.compressed_size;
    }
};

// ============================================================================
// Encryption Context
// ============================================================================

pub const EncryptionContext = struct {
    const Self = @This();

    allocator: mem.Allocator,
    method: EncryptionMethod,
    password: ?[]const u8 = null,
    salt: [16]u8 = [_]u8{0} ** 16,

    pub fn init(allocator: mem.Allocator, method: EncryptionMethod) Self {
        return .{
            .allocator = allocator,
            .method = method,
        };
    }

    pub fn setPassword(self: *Self, password: []const u8) !void {
        if (self.password) |p| {
            self.allocator.free(p);
        }
        self.password = try self.allocator.dupe(u8, password);
    }

    pub fn deinit(self: *Self) void {
        if (self.password) |p| {
            self.allocator.free(p);
        }
    }

    pub fn isReady(self: Self) bool {
        return self.password != null or self.method == .none;
    }

    pub fn createDecryptor(self: Self) !PkzipCrypto {
        const pw = self.password orelse return error.NoPasswordSet;
        return PkzipCrypto.init(pw);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "EncryptionMethod keyLength" {
    try testing.expectEqual(@as(usize, 0), EncryptionMethod.none.keyLength());
    try testing.expectEqual(@as(usize, 12), EncryptionMethod.pkzip_traditional.keyLength());
    try testing.expectEqual(@as(usize, 16), EncryptionMethod.aes_128.keyLength());
    try testing.expectEqual(@as(usize, 24), EncryptionMethod.aes_192.keyLength());
    try testing.expectEqual(@as(usize, 32), EncryptionMethod.aes_256.keyLength());
}

test "EncryptionMethod getName" {
    try testing.expectEqualStrings("none", EncryptionMethod.none.getName());
    try testing.expectEqualStrings("PKZIP", EncryptionMethod.pkzip_traditional.getName());
    try testing.expectEqualStrings("AES-256", EncryptionMethod.aes_256.getName());
}

test "EncryptionMethod isAes" {
    try testing.expect(!EncryptionMethod.none.isAes());
    try testing.expect(!EncryptionMethod.pkzip_traditional.isAes());
    try testing.expect(EncryptionMethod.aes_128.isAes());
    try testing.expect(EncryptionMethod.aes_192.isAes());
    try testing.expect(EncryptionMethod.aes_256.isAes());
}

test "PkzipCrypto init" {
    const crypto = PkzipCrypto.init("password");
    // Keys should be modified from initial values
    try testing.expect(crypto.keys[0] != 0x12345678);
    try testing.expect(crypto.keys[1] != 0x23456789);
    try testing.expect(crypto.keys[2] != 0x34567890);
}

test "PkzipCrypto encrypt decrypt roundtrip" {
    var encryptor = PkzipCrypto.init("secret");

    var data = [_]u8{ 'H', 'e', 'l', 'l', 'o' };
    const original = [_]u8{ 'H', 'e', 'l', 'l', 'o' };

    // Encrypt
    encryptor.encryptData(&data);
    try testing.expect(!mem.eql(u8, &data, &original));

    // Decrypt with fresh crypto
    var decryptor = PkzipCrypto.init("secret");
    decryptor.decryptData(&data);
    try testing.expectEqualSlices(u8, &original, &data);
}

test "PkzipCrypto different passwords" {
    var crypto1 = PkzipCrypto.init("password1");
    var crypto2 = PkzipCrypto.init("password2");

    var data1 = [_]u8{'A'};
    var data2 = [_]u8{'A'};

    crypto1.encryptData(&data1);
    crypto2.encryptData(&data2);

    // Same plaintext with different passwords should produce different ciphertext
    try testing.expect(!mem.eql(u8, &data1, &data2));
}

test "PasswordValidator valid password" {
    const validator = PasswordValidator{};
    try validator.validate("password123");
}

test "PasswordValidator too short" {
    const validator = PasswordValidator{ .min_length = 8 };
    try testing.expectError(error.PasswordTooShort, validator.validate("short"));
}

test "PasswordValidator too long" {
    const validator = PasswordValidator{ .max_length = 10 };
    const long_password = "this_password_is_way_too_long";
    try testing.expectError(error.PasswordTooLong, validator.validate(long_password));
}

test "PasswordValidator non-ascii" {
    const validator = PasswordValidator{ .require_ascii = true };
    try testing.expectError(error.NonAsciiCharacter, validator.validate("pass\xc0word"));
}

test "PasswordValidator isValid" {
    const validator = PasswordValidator{ .min_length = 4 };
    try testing.expect(validator.isValid("password"));
    try testing.expect(!validator.isValid("abc"));
}

test "deriveKey basic" {
    const key = try deriveKey("password", "salt", 1000, 16, testing.allocator);
    defer testing.allocator.free(key);

    try testing.expectEqual(@as(usize, 16), key.len);
}

test "deriveKey different lengths" {
    const key8 = try deriveKey("password", "salt", 1000, 8, testing.allocator);
    defer testing.allocator.free(key8);

    const key32 = try deriveKey("password", "salt", 1000, 32, testing.allocator);
    defer testing.allocator.free(key32);

    try testing.expectEqual(@as(usize, 8), key8.len);
    try testing.expectEqual(@as(usize, 32), key32.len);
}

test "EncryptedEntry isEncrypted" {
    const encrypted = EncryptedEntry{
        .filename = "secret.txt",
        .method = .pkzip_traditional,
        .header_offset = 0,
        .compressed_size = 100,
        .uncompressed_size = 100,
        .crc32 = 0,
    };

    const unencrypted = EncryptedEntry{
        .filename = "public.txt",
        .method = .none,
        .header_offset = 0,
        .compressed_size = 100,
        .uncompressed_size = 100,
        .crc32 = 0,
    };

    try testing.expect(encrypted.isEncrypted());
    try testing.expect(!unencrypted.isEncrypted());
}

test "EncryptedEntry getDataOffset" {
    const pkzip = EncryptedEntry{
        .filename = "test.txt",
        .method = .pkzip_traditional,
        .header_offset = 100,
        .compressed_size = 50,
        .uncompressed_size = 50,
        .crc32 = 0,
    };

    const none = EncryptedEntry{
        .filename = "test.txt",
        .method = .none,
        .header_offset = 100,
        .compressed_size = 50,
        .uncompressed_size = 50,
        .crc32 = 0,
    };

    try testing.expectEqual(@as(u64, 112), pkzip.getDataOffset());
    try testing.expectEqual(@as(u64, 100), none.getDataOffset());
}

test "EncryptedEntry getActualDataSize" {
    const pkzip = EncryptedEntry{
        .filename = "test.txt",
        .method = .pkzip_traditional,
        .header_offset = 0,
        .compressed_size = 100,
        .uncompressed_size = 100,
        .crc32 = 0,
    };

    try testing.expectEqual(@as(u64, 88), pkzip.getActualDataSize());
}

test "EncryptionContext init" {
    var ctx = EncryptionContext.init(testing.allocator, .aes_256);
    defer ctx.deinit();

    try testing.expectEqual(EncryptionMethod.aes_256, ctx.method);
    try testing.expect(!ctx.isReady());
}

test "EncryptionContext setPassword" {
    var ctx = EncryptionContext.init(testing.allocator, .pkzip_traditional);
    defer ctx.deinit();

    try ctx.setPassword("secret");
    try testing.expect(ctx.isReady());
    try testing.expectEqualStrings("secret", ctx.password.?);
}

test "EncryptionContext createDecryptor" {
    var ctx = EncryptionContext.init(testing.allocator, .pkzip_traditional);
    defer ctx.deinit();

    // Should fail without password
    try testing.expectError(error.NoPasswordSet, ctx.createDecryptor());

    // Should succeed with password
    try ctx.setPassword("password");
    const decryptor = try ctx.createDecryptor();
    _ = decryptor;
}

test "EncryptionContext none method always ready" {
    var ctx = EncryptionContext.init(testing.allocator, .none);
    defer ctx.deinit();

    try testing.expect(ctx.isReady());
}

test "PkzipCrypto crc table" {
    // Verify CRC table is computed correctly
    try testing.expectEqual(@as(u32, 0x00000000), PkzipCrypto.crc_table[0]);
    // Known CRC values
    try testing.expect(PkzipCrypto.crc_table[255] != 0);
}
