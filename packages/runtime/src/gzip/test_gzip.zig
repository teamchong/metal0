const std = @import("std");
const gzip = @import("gzip.zig");
const testing = std.testing;

test "gzip roundtrip - simple string" {
    const allocator = testing.allocator;
    const original = "Hello, World!";

    // Compress
    const compressed = try gzip.compress(allocator, original);
    defer allocator.free(compressed);

    // Verify gzip header
    try testing.expectEqual(@as(u8, 0x1f), compressed[0]);
    try testing.expectEqual(@as(u8, 0x8b), compressed[1]);
    try testing.expectEqual(@as(u8, 0x08), compressed[2]); // deflate method

    // Decompress
    const decompressed = try gzip.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    // Verify result
    try testing.expectEqualStrings(original, decompressed);
}

test "gzip roundtrip - empty string" {
    const allocator = testing.allocator;
    const original = "";

    const compressed = try gzip.compress(allocator, original);
    defer allocator.free(compressed);

    const decompressed = try gzip.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(original, decompressed);
}

test "gzip roundtrip - large text" {
    const allocator = testing.allocator;

    // Create large repeating text (compresses well)
    var original_list = std.ArrayList(u8){};
    defer original_list.deinit(allocator);

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        try original_list.appendSlice(allocator, "The quick brown fox jumps over the lazy dog. ");
    }
    const original = try original_list.toOwnedSlice(allocator);
    defer allocator.free(original);

    const compressed = try gzip.compress(allocator, original);
    defer allocator.free(compressed);

    // Verify compression actually reduced size
    try testing.expect(compressed.len < original.len);

    const decompressed = try gzip.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    try testing.expectEqualStrings(original, decompressed);
}

test "gzip roundtrip - binary data" {
    const allocator = testing.allocator;

    // Create binary data
    var original: [256]u8 = undefined;
    for (&original, 0..) |*byte, idx| {
        byte.* = @truncate(idx);
    }

    const compressed = try gzip.compress(allocator, &original);
    defer allocator.free(compressed);

    const decompressed = try gzip.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    try testing.expectEqualSlices(u8, &original, decompressed);
}

test "gzip decompress - invalid magic bytes" {
    const allocator = testing.allocator;

    const invalid_data = [_]u8{ 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff };

    const result = gzip.decompress(allocator, &invalid_data);
    try testing.expectError(error.BadGzipHeader, result);
}

test "gzip decompress - invalid compression method" {
    const allocator = testing.allocator;

    const invalid_data = [_]u8{ 0x1f, 0x8b, 0x99, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff };

    const result = gzip.decompress(allocator, &invalid_data);
    try testing.expectError(error.BadGzipHeader, result);
}

test "gzip decompress - too short data" {
    const allocator = testing.allocator;

    const invalid_data = [_]u8{ 0x1f, 0x8b };

    const result = gzip.decompress(allocator, &invalid_data);
    try testing.expectError(error.EndOfStream, result);
}

test "gzip header format" {
    const allocator = testing.allocator;
    const data = "test";

    const compressed = try gzip.compress(allocator, data);
    defer allocator.free(compressed);

    // Verify header structure
    try testing.expectEqual(@as(u8, 0x1f), compressed[0]); // ID1
    try testing.expectEqual(@as(u8, 0x8b), compressed[1]); // ID2
    try testing.expectEqual(@as(u8, 0x08), compressed[2]); // CM (deflate)
    try testing.expectEqual(@as(u8, 0x00), compressed[3]); // FLG (no flags)
    // bytes 4-7: MTIME (4 bytes)
    try testing.expectEqual(@as(u8, 0x00), compressed[8]); // XFL
    try testing.expectEqual(@as(u8, 0xff), compressed[9]); // OS (libdeflate uses 0xff = unknown)
}

test "gzip CRC32 verification" {
    const allocator = testing.allocator;
    const original = "CRC test data";

    const compressed = try gzip.compress(allocator, original);
    defer allocator.free(compressed);

    // Corrupt the CRC in the footer
    var corrupted = try allocator.dupe(u8, compressed);
    defer allocator.free(corrupted);

    const footer_start = corrupted.len - 8;
    corrupted[footer_start] ^= 0xFF; // Flip bits in CRC

    const result = gzip.decompress(allocator, corrupted);
    try testing.expectError(error.WrongGzipChecksum, result);
}

test "gzip size verification" {
    const allocator = testing.allocator;
    const original = "Size test data";

    const compressed = try gzip.compress(allocator, original);
    defer allocator.free(compressed);

    // Corrupt the size in the footer
    var corrupted = try allocator.dupe(u8, compressed);
    defer allocator.free(corrupted);

    const size_start = corrupted.len - 4;
    corrupted[size_start] ^= 0xFF; // Flip bits in size

    const result = gzip.decompress(allocator, corrupted);
    try testing.expectError(error.WrongGzipSize, result);
}
