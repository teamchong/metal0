const std = @import("std");
const compress = @import("src/compress.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Simple Python code
    const test_request =
        \\{"model":"claude-3","max_tokens":100,"messages":[{"role":"user","content":"def hello():\n    print('Hello World')\n    return True"}]}
    ;

    std.debug.print("Testing compression...\n", .{});
    
    var compressor = compress.TextCompressor.init(allocator, true);
    const compressed = try compressor.compressRequest(test_request);
    defer allocator.free(compressed);

    std.debug.print("\n=== RESULT ===\n", .{});
    std.debug.print("Original: {d} bytes\n", .{test_request.len});
    std.debug.print("Compressed: {d} bytes\n", .{compressed.len});
    
    // Check if it contains base64 GIF data
    if (std.mem.indexOf(u8, compressed, "image/gif")) |_| {
        std.debug.print("✅ Contains GIF image!\n", .{});
        
        // Extract and save first GIF for inspection
        if (std.mem.indexOf(u8, compressed, "\"data\":\"")) |start| {
            const data_start = start + 8;
            if (std.mem.indexOf(u8, compressed[data_start..], "\"")) |end| {
                const base64_data = compressed[data_start..][0..end];
                
                // Decode base64
                const decoder = std.base64.standard.Decoder;
                const gif_size = try decoder.calcSizeForSlice(base64_data);
                const gif_bytes = try allocator.alloc(u8, gif_size);
                defer allocator.free(gif_bytes);
                try decoder.decode(gif_bytes, base64_data);
                
                // Save to file
                const file = try std.fs.cwd().createFile("/tmp/extracted.gif", .{});
                defer file.close();
                try file.writeAll(gif_bytes);
                
                std.debug.print("✅ Saved to /tmp/extracted.gif ({d} bytes)\n", .{gif_bytes.len});
            }
        }
    } else {
        std.debug.print("❌ No GIF found - kept as text\n", .{});
    }
}
