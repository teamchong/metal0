//! test.test_concurrent_futures.test_map - Executor map tests
//!
//! Tests for executor.map() functionality including parallel mapping of iterables,
//! chunksize handling, and ordered result retrieval.

const std = @import("std");
const testing = std.testing;

/// Error types for map operations
pub const MapError = error{
    ExecutorShutdown,
    ChunksizeInvalid,
    EmptyIterable,
    MapFailed,
    TimeoutError,
    IteratorExhausted,
};

/// Configuration for map operations
pub const MapConfig = struct {
    chunksize: usize = 1,
    timeout_ms: ?u64 = null,
    preserve_order: bool = true,
    fail_fast: bool = true,
    prefetch_count: usize = 1,

    pub fn init() MapConfig {
        return .{};
    }

    pub fn withChunksize(chunksize: usize) MapConfig {
        return .{ .chunksize = chunksize };
    }

    pub fn unordered() MapConfig {
        return .{ .preserve_order = false };
    }

    pub fn withTimeout(timeout_ms: u64) MapConfig {
        return .{ .timeout_ms = timeout_ms };
    }

    pub fn validate(self: MapConfig) MapError!void {
        if (self.chunksize == 0) {
            return MapError.ChunksizeInvalid;
        }
    }
};

/// Represents a chunk of work to be processed
pub fn Chunk(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []const T,
        start_index: usize,
        chunk_id: usize,

        pub fn init(items: []const T, start_index: usize, chunk_id: usize) Self {
            return .{
                .items = items,
                .start_index = start_index,
                .chunk_id = chunk_id,
            };
        }

        pub fn len(self: Self) usize {
            return self.items.len;
        }

        pub fn isEmpty(self: Self) bool {
            return self.items.len == 0;
        }

        pub fn getEndIndex(self: Self) usize {
            return self.start_index + self.items.len;
        }
    };
}

/// Chunk result containing processed outputs
pub fn ChunkResult(comptime T: type, comptime R: type) type {
    return struct {
        const Self = @This();

        chunk: Chunk(T),
        results: std.ArrayList(R),
        errors: std.ArrayList(MapItemError),
        processing_time_ns: u64 = 0,

        pub const MapItemError = struct {
            index: usize,
            err: anyerror,
        };

        pub fn init(allocator: std.mem.Allocator, chunk: Chunk(T)) Self {
            return .{
                .chunk = chunk,
                .results = std.ArrayList(R).init(allocator),
                .errors = std.ArrayList(MapItemError).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.results.deinit();
            self.errors.deinit();
        }

        pub fn addResult(self: *Self, result: R) !void {
            try self.results.append(result);
        }

        pub fn addError(self: *Self, index: usize, err: anyerror) !void {
            try self.errors.append(.{ .index = index, .err = err });
        }

        pub fn hasErrors(self: Self) bool {
            return self.errors.items.len > 0;
        }

        pub fn successCount(self: Self) usize {
            return self.results.items.len;
        }

        pub fn errorCount(self: Self) usize {
            return self.errors.items.len;
        }
    };
}

/// Iterator for chunking input data
pub fn ChunkIterator(comptime T: type) type {
    return struct {
        const Self = @This();

        data: []const T,
        chunksize: usize,
        current_index: usize = 0,
        chunk_id: usize = 0,

        pub fn init(data: []const T, chunksize: usize) Self {
            return .{
                .data = data,
                .chunksize = if (chunksize == 0) 1 else chunksize,
            };
        }

        pub fn next(self: *Self) ?Chunk(T) {
            if (self.current_index >= self.data.len) {
                return null;
            }

            const end = @min(self.current_index + self.chunksize, self.data.len);
            const chunk = Chunk(T).init(
                self.data[self.current_index..end],
                self.current_index,
                self.chunk_id,
            );

            self.current_index = end;
            self.chunk_id += 1;
            return chunk;
        }

        pub fn reset(self: *Self) void {
            self.current_index = 0;
            self.chunk_id = 0;
        }

        pub fn remaining(self: Self) usize {
            if (self.current_index >= self.data.len) return 0;
            return self.data.len - self.current_index;
        }

        pub fn totalChunks(self: Self) usize {
            if (self.data.len == 0) return 0;
            return (self.data.len + self.chunksize - 1) / self.chunksize;
        }
    };
}

/// Map result collector for gathering results in order
pub fn MapResultCollector(comptime R: type) type {
    return struct {
        const Self = @This();

        results: std.ArrayList(?R),
        allocator: std.mem.Allocator,
        total_items: usize,
        collected_count: usize = 0,
        error_count: usize = 0,

        pub fn init(allocator: std.mem.Allocator, total_items: usize) !Self {
            var results = std.ArrayList(?R).init(allocator);
            try results.resize(total_items);
            for (results.items) |*item| {
                item.* = null;
            }
            return .{
                .results = results,
                .allocator = allocator,
                .total_items = total_items,
            };
        }

        pub fn deinit(self: *Self) void {
            self.results.deinit();
        }

        pub fn setResult(self: *Self, index: usize, result: R) void {
            if (index < self.results.items.len) {
                if (self.results.items[index] == null) {
                    self.collected_count += 1;
                }
                self.results.items[index] = result;
            }
        }

        pub fn markError(self: *Self, index: usize) void {
            _ = index;
            self.error_count += 1;
        }

        pub fn isComplete(self: Self) bool {
            return self.collected_count + self.error_count >= self.total_items;
        }

        pub fn getCompletedResults(self: Self) []const ?R {
            return self.results.items;
        }

        pub fn successRate(self: Self) f64 {
            if (self.total_items == 0) return 1.0;
            return @as(f64, @floatFromInt(self.collected_count)) / @as(f64, @floatFromInt(self.total_items));
        }
    };
}

/// Mapper function wrapper
pub fn Mapper(comptime Input: type, comptime Output: type) type {
    return struct {
        const Self = @This();

        func: *const fn (Input) Output,
        name: ?[]const u8 = null,

        pub fn init(func: *const fn (Input) Output) Self {
            return .{ .func = func };
        }

        pub fn withName(func: *const fn (Input) Output, name: []const u8) Self {
            return .{ .func = func, .name = name };
        }

        pub fn apply(self: Self, input: Input) Output {
            return self.func(input);
        }

        pub fn mapSlice(self: Self, allocator: std.mem.Allocator, inputs: []const Input) ![]Output {
            var outputs = try allocator.alloc(Output, inputs.len);
            for (inputs, 0..) |input, i| {
                outputs[i] = self.apply(input);
            }
            return outputs;
        }
    };
}

/// Parallel map executor
pub fn ParallelMapper(comptime Input: type, comptime Output: type) type {
    return struct {
        const Self = @This();

        mapper: Mapper(Input, Output),
        config: MapConfig,
        allocator: std.mem.Allocator,
        stats: MapStats = .{},

        pub const MapStats = struct {
            items_processed: usize = 0,
            chunks_processed: usize = 0,
            total_time_ns: u64 = 0,
            errors: usize = 0,

            pub fn averageItemTimeNs(self: MapStats) u64 {
                if (self.items_processed == 0) return 0;
                return self.total_time_ns / self.items_processed;
            }
        };

        pub fn init(allocator: std.mem.Allocator, mapper: Mapper(Input, Output), config: MapConfig) MapError!Self {
            try config.validate();
            return .{
                .allocator = allocator,
                .mapper = mapper,
                .config = config,
            };
        }

        pub fn map(self: *Self, inputs: []const Input) ![]Output {
            if (inputs.len == 0) {
                return &[_]Output{};
            }

            const start_time = std.time.nanoTimestamp();
            var outputs = try self.allocator.alloc(Output, inputs.len);

            var chunk_iter = ChunkIterator(Input).init(inputs, self.config.chunksize);
            while (chunk_iter.next()) |chunk| {
                for (chunk.items, 0..) |item, i| {
                    const global_idx = chunk.start_index + i;
                    outputs[global_idx] = self.mapper.apply(item);
                    self.stats.items_processed += 1;
                }
                self.stats.chunks_processed += 1;
            }

            const end_time = std.time.nanoTimestamp();
            self.stats.total_time_ns = @intCast(end_time - start_time);

            return outputs;
        }

        pub fn getStats(self: Self) MapStats {
            return self.stats;
        }

        pub fn resetStats(self: *Self) void {
            self.stats = .{};
        }
    };
}

/// Calculate optimal chunksize based on input size and worker count
pub fn calculateOptimalChunksize(input_size: usize, worker_count: usize) usize {
    if (input_size == 0 or worker_count == 0) return 1;

    // Aim for at least 4 chunks per worker for good load balancing
    const target_chunks = worker_count * 4;
    const chunksize = (input_size + target_chunks - 1) / target_chunks;

    // Ensure reasonable bounds
    return @max(1, @min(chunksize, 1000));
}

// ============================================================================
// Test helper functions
// ============================================================================

fn double(x: i32) i32 {
    return x * 2;
}

fn square(x: i32) i32 {
    return x * x;
}

fn addTen(x: i32) i32 {
    return x + 10;
}

fn identity(x: i32) i32 {
    return x;
}

// ============================================================================
// Tests
// ============================================================================

test "map_config_default" {
    const config = MapConfig.init();
    try testing.expectEqual(@as(usize, 1), config.chunksize);
    try testing.expect(config.preserve_order);
    try testing.expect(config.fail_fast);
    try config.validate();
}

test "map_config_with_chunksize" {
    const config = MapConfig.withChunksize(10);
    try testing.expectEqual(@as(usize, 10), config.chunksize);
    try config.validate();
}

test "map_config_validation" {
    const invalid = MapConfig{ .chunksize = 0 };
    try testing.expectError(MapError.ChunksizeInvalid, invalid.validate());
}

test "chunk_basic" {
    const data = [_]i32{ 1, 2, 3, 4, 5 };
    const chunk = Chunk(i32).init(&data, 0, 0);

    try testing.expectEqual(@as(usize, 5), chunk.len());
    try testing.expect(!chunk.isEmpty());
    try testing.expectEqual(@as(usize, 0), chunk.start_index);
    try testing.expectEqual(@as(usize, 5), chunk.getEndIndex());
}

test "chunk_iterator" {
    const data = [_]i32{ 1, 2, 3, 4, 5, 6, 7 };
    var iter = ChunkIterator(i32).init(&data, 3);

    try testing.expectEqual(@as(usize, 3), iter.totalChunks());

    const chunk1 = iter.next().?;
    try testing.expectEqual(@as(usize, 3), chunk1.len());
    try testing.expectEqual(@as(usize, 0), chunk1.start_index);

    const chunk2 = iter.next().?;
    try testing.expectEqual(@as(usize, 3), chunk2.len());
    try testing.expectEqual(@as(usize, 3), chunk2.start_index);

    const chunk3 = iter.next().?;
    try testing.expectEqual(@as(usize, 1), chunk3.len());
    try testing.expectEqual(@as(usize, 6), chunk3.start_index);

    try testing.expect(iter.next() == null);
}

test "chunk_iterator_reset" {
    const data = [_]i32{ 1, 2, 3 };
    var iter = ChunkIterator(i32).init(&data, 2);

    _ = iter.next();
    _ = iter.next();
    try testing.expect(iter.next() == null);

    iter.reset();
    try testing.expect(iter.next() != null);
}

test "chunk_result" {
    const data = [_]i32{ 1, 2, 3 };
    const chunk = Chunk(i32).init(&data, 0, 0);

    var result = ChunkResult(i32, i32).init(testing.allocator, chunk);
    defer result.deinit();

    try result.addResult(2);
    try result.addResult(4);
    try result.addResult(6);

    try testing.expectEqual(@as(usize, 3), result.successCount());
    try testing.expect(!result.hasErrors());
}

test "chunk_result_with_errors" {
    const data = [_]i32{ 1, 2, 3 };
    const chunk = Chunk(i32).init(&data, 0, 0);

    var result = ChunkResult(i32, i32).init(testing.allocator, chunk);
    defer result.deinit();

    try result.addResult(2);
    try result.addError(1, error.SomeError);
    try result.addResult(6);

    try testing.expectEqual(@as(usize, 2), result.successCount());
    try testing.expectEqual(@as(usize, 1), result.errorCount());
    try testing.expect(result.hasErrors());
}

test "map_result_collector" {
    var collector = try MapResultCollector(i32).init(testing.allocator, 5);
    defer collector.deinit();

    try testing.expect(!collector.isComplete());

    collector.setResult(0, 10);
    collector.setResult(2, 30);
    collector.setResult(4, 50);
    collector.markError(1);
    collector.markError(3);

    try testing.expect(collector.isComplete());
    try testing.expectApproxEqAbs(@as(f64, 0.6), collector.successRate(), 0.01);
}

test "mapper_basic" {
    const mapper = Mapper(i32, i32).init(double);

    try testing.expectEqual(@as(i32, 10), mapper.apply(5));
    try testing.expectEqual(@as(i32, -8), mapper.apply(-4));
}

test "mapper_with_name" {
    const mapper = Mapper(i32, i32).withName(square, "square_func");

    try testing.expectEqualStrings("square_func", mapper.name.?);
    try testing.expectEqual(@as(i32, 16), mapper.apply(4));
}

test "mapper_map_slice" {
    const mapper = Mapper(i32, i32).init(double);
    const inputs = [_]i32{ 1, 2, 3, 4, 5 };

    const outputs = try mapper.mapSlice(testing.allocator, &inputs);
    defer testing.allocator.free(outputs);

    try testing.expectEqual(@as(usize, 5), outputs.len);
    try testing.expectEqual(@as(i32, 2), outputs[0]);
    try testing.expectEqual(@as(i32, 4), outputs[1]);
    try testing.expectEqual(@as(i32, 6), outputs[2]);
    try testing.expectEqual(@as(i32, 8), outputs[3]);
    try testing.expectEqual(@as(i32, 10), outputs[4]);
}

test "parallel_mapper" {
    const mapper = Mapper(i32, i32).init(addTen);
    const config = MapConfig.withChunksize(2);

    var pm = try ParallelMapper(i32, i32).init(testing.allocator, mapper, config);
    const inputs = [_]i32{ 1, 2, 3, 4, 5 };

    const outputs = try pm.map(&inputs);
    defer testing.allocator.free(outputs);

    try testing.expectEqual(@as(i32, 11), outputs[0]);
    try testing.expectEqual(@as(i32, 12), outputs[1]);
    try testing.expectEqual(@as(i32, 13), outputs[2]);
    try testing.expectEqual(@as(i32, 14), outputs[3]);
    try testing.expectEqual(@as(i32, 15), outputs[4]);

    const stats = pm.getStats();
    try testing.expectEqual(@as(usize, 5), stats.items_processed);
    try testing.expectEqual(@as(usize, 3), stats.chunks_processed); // 2+2+1
}

test "calculate_optimal_chunksize" {
    try testing.expectEqual(@as(usize, 1), calculateOptimalChunksize(0, 4));
    try testing.expectEqual(@as(usize, 1), calculateOptimalChunksize(10, 0));
    try testing.expectEqual(@as(usize, 1), calculateOptimalChunksize(4, 4));
    try testing.expectEqual(@as(usize, 7), calculateOptimalChunksize(100, 4));
    try testing.expectEqual(@as(usize, 63), calculateOptimalChunksize(1000, 4));
}

test "empty_map" {
    const mapper = Mapper(i32, i32).init(identity);
    const config = MapConfig.init();

    var pm = try ParallelMapper(i32, i32).init(testing.allocator, mapper, config);
    const empty = [_]i32{};

    const outputs = try pm.map(&empty);
    try testing.expectEqual(@as(usize, 0), outputs.len);
}
