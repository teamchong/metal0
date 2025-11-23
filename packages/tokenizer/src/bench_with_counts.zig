const std = @import("std");
const Tokenizer = @import("tokenizer.zig").Tokenizer;

// Global counters for allocation tracking
var alloc_count: usize = 0;
var total_bytes: usize = 0;

const CountingAllocator = struct {
    parent: std.mem.Allocator,

    pub fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
                .remap = std.mem.Allocator.noRemap,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        alloc_count += 1;
        total_bytes += len;
        return self.parent.rawAlloc(len, ptr_align, ret_addr);
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        if (new_len > buf.len) {
            alloc_count += 1;
            total_bytes += new_len;
        }
        return self.parent.rawResize(buf, buf_align, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.parent.rawFree(buf, buf_align, ret_addr);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var counting = CountingAllocator{ .parent = gpa.allocator() };
    const allocator = counting.allocator();

    // Load tokenizer
    std.debug.print("Loading tokenizer...\n", .{});
    var tokenizer = try Tokenizer.init("dist/cl100k_base_full.json", allocator);
    defer tokenizer.deinit();

    const init_allocs = alloc_count;
    const init_bytes = total_bytes;

    std.debug.print("Tokenizer loaded: {} allocs, {} bytes\n\n", .{init_allocs, init_bytes});

    // Test single encode
    alloc_count = 0;
    total_bytes = 0;

    const text = "The quick brown fox jumps over the lazy dog.";
    const tokens = try tokenizer.encode(text);
    defer allocator.free(tokens);

    std.debug.print("Single encode:\n", .{});
    std.debug.print("  Allocations: {}\n", .{alloc_count});
    std.debug.print("  Total bytes: {}\n", .{total_bytes});
    std.debug.print("  Tokens: {any}\n\n", .{tokens});

    // Test 10 encodes to see pattern
    alloc_count = 0;
    total_bytes = 0;

    for (0..10) |_| {
        const t = try tokenizer.encode(text);
        allocator.free(t);
    }

    std.debug.print("10 encodes:\n", .{});
    std.debug.print("  Total allocations: {}\n", .{alloc_count});
    std.debug.print("  Total bytes: {}\n", .{total_bytes});
    std.debug.print("  Per-encode allocs: {d:.1}\n", .{@as(f64, @floatFromInt(alloc_count)) / 10.0});
    std.debug.print("  Per-encode bytes: {d:.0}\n\n", .{@as(f64, @floatFromInt(total_bytes)) / 10.0});

    // Load benchmark data
    std.debug.print("Loading benchmark data...\n", .{});
    const file = try std.fs.cwd().openFile("benchmark_data.json", .{});
    defer file.close();

    const file_size = (try file.stat()).size;
    const json_data = try allocator.alloc(u8, file_size);
    defer allocator.free(json_data);
    _ = try file.readAll(json_data);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
    defer parsed.deinit();

    const texts_json = parsed.value.object.get("texts").?.array;
    var texts = std.ArrayList([]const u8){};
    defer {
        for (texts.items) |t| allocator.free(t);
        texts.deinit(allocator);
    }

    for (texts_json.items) |text_value| {
        const t = text_value.string;
        const owned_text = try allocator.dupe(u8, t);
        try texts.append(allocator, owned_text);
    }

    std.debug.print("Loaded {} texts\n\n", .{texts.items.len});

    // Benchmark with allocation counting
    alloc_count = 0;
    total_bytes = 0;

    const iterations: usize = 10;
    const start = std.time.nanoTimestamp();

    for (0..iterations) |_| {
        for (texts.items) |t| {
            const t_tokens = try tokenizer.encode(t);
            allocator.free(t_tokens);
        }
    }

    const end = std.time.nanoTimestamp();
    const elapsed_ms = @divFloor(end - start, 1_000_000);

    std.debug.print("Benchmark (583 texts × {} iterations):\n", .{iterations});
    std.debug.print("  Time: {}ms\n", .{elapsed_ms});
    std.debug.print("  Total allocations: {}\n", .{alloc_count});
    std.debug.print("  Total bytes allocated: {}\n", .{total_bytes});
    std.debug.print("  Allocs per text: {d:.1}\n", .{
        @as(f64, @floatFromInt(alloc_count)) / @as(f64, @floatFromInt(texts.items.len * iterations))
    });
    std.debug.print("  Bytes per text: {d:.0}\n", .{
        @as(f64, @floatFromInt(total_bytes)) / @as(f64, @floatFromInt(texts.items.len * iterations))
    });
}
