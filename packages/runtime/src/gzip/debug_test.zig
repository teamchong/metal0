const std = @import("std");
const gzip = @import("gzip.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const original = "Hello, World!";

    std.debug.print("Compressing: {s}\n", .{original});

    const compressed = try gzip.compress(allocator, original);
    defer allocator.free(compressed);

    std.debug.print("Compressed size: {d}\n", .{compressed.len});
    std.debug.print("First 3 bytes: 0x{X:0>2} 0x{X:0>2} 0x{X:0>2}\n", .{compressed[0], compressed[1], compressed[2]});

    std.debug.print("Decompressing...\n", .{});

    const decompressed = try gzip.decompress(allocator, compressed);
    defer allocator.free(decompressed);

    std.debug.print("Decompressed: {s}\n", .{decompressed});
}
