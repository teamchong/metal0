//! LogicTable DataFrame API
//!
//! Provides a fluent interface for querying @logic_table virtual tables:
//!
//! ```python
//! # Python definition
//! @logic_table
//! class FraudDetector:
//!     orders = Table('orders.lance')
//!
//!     def risk_score(self) -> float:
//!         return self.amount_score() * 0.5 + self.velocity_score() * 0.5
//! ```
//!
//! ```zig
//! // Zig usage
//! const df = LogicTableDataFrame.init(allocator, "fraud_detector.py");
//! const results = df
//!     .filter(.{ .method = "risk_score", .op = .gt, .value = 0.7 })
//!     .select(&.{ "order_id", "risk_score" })
//!     .limit(100)
//!     .collect();
//! ```

const std = @import("std");
const logic_table = @import("logic_table.zig");

const LogicTableContext = logic_table.LogicTableContext;
const LogicTableExecutor = @import("executor.zig").LogicTableExecutor;

/// Method result cache - stores per-row method results computed in batch
pub const MethodResultCache = struct {
    allocator: std.mem.Allocator,
    results: std.StringHashMap([]f64),

    pub fn init(allocator: std.mem.Allocator) MethodResultCache {
        return .{
            .allocator = allocator,
            .results = std.StringHashMap([]f64).init(allocator),
        };
    }

    pub fn deinit(self: *MethodResultCache) void {
        var iter = self.results.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.results.deinit();
    }

    pub fn get(self: *const MethodResultCache, method: []const u8) ?[]const f64 {
        return self.results.get(method);
    }

    pub fn put(self: *MethodResultCache, method: []const u8, results: []f64) !void {
        try self.results.put(method, results);
    }
};

/// Filter operation for method results
pub const FilterOp = enum {
    eq, // ==
    ne, // !=
    lt, // <
    le, // <=
    gt, // >
    ge, // >=
};

/// Filter specification for method results
pub const MethodFilter = struct {
    /// Method name (e.g., "risk_score")
    method: []const u8,
    /// Comparison operator
    op: FilterOp,
    /// Threshold value
    value: f64,
};

/// Order specification
pub const OrderSpec = struct {
    /// Column or method name
    column: []const u8,
    /// Whether to sort descending
    descending: bool,
};

/// LogicTable DataFrame - fluent API for @logic_table queries
pub const LogicTableDataFrame = struct {
    allocator: std.mem.Allocator,
    executor: *LogicTableExecutor,

    // Query state
    select_columns: ?[]const []const u8 = null,
    method_filters: std.ArrayList(MethodFilter),
    column_filters: std.ArrayList(ColumnFilter),
    order_specs: ?[]const OrderSpec = null,
    limit_value: ?u64 = null,
    offset_value: ?u64 = null,

    // Method result cache - populated during collect()
    method_cache: MethodResultCache,

    // Optional: mock method results for testing (when real dispatch not available)
    mock_method_fn: ?*const fn (method: []const u8, row_count: usize, allocator: std.mem.Allocator) anyerror![]f64 = null,

    const Self = @This();

    /// Column filter for WHERE clause on data columns
    pub const ColumnFilter = struct {
        table: []const u8,
        column: []const u8,
        op: FilterOp,
        value: FilterValue,
    };

    pub const FilterValue = union(enum) {
        int: i64,
        float: f64,
        string: []const u8,
    };

    /// Initialize DataFrame from Python file path
    pub fn init(allocator: std.mem.Allocator, python_file: []const u8) !Self {
        const executor = try allocator.create(LogicTableExecutor);
        executor.* = try LogicTableExecutor.init(allocator, python_file);

        return Self{
            .allocator = allocator,
            .executor = executor,
            .method_filters = std.ArrayList(MethodFilter).init(allocator),
            .column_filters = std.ArrayList(ColumnFilter).init(allocator),
            .method_cache = MethodResultCache.init(allocator),
        };
    }

    /// Initialize from existing executor
    pub fn fromExecutor(allocator: std.mem.Allocator, executor: *LogicTableExecutor) Self {
        return Self{
            .allocator = allocator,
            .executor = executor,
            .method_filters = std.ArrayList(MethodFilter).init(allocator),
            .column_filters = std.ArrayList(ColumnFilter).init(allocator),
            .method_cache = MethodResultCache.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.method_filters.deinit();
        self.column_filters.deinit();
        self.method_cache.deinit();
        self.executor.deinit();
        self.allocator.destroy(self.executor);
    }

    /// Select specific columns/methods
    pub fn select(self: Self, columns: []const []const u8) Self {
        var new = self;
        new.select_columns = columns;
        return new;
    }

    /// Filter by method result
    /// Example: .filterMethod("risk_score", .gt, 0.7)
    pub fn filterMethod(self: Self, method: []const u8, op: FilterOp, value: f64) !Self {
        var new = self;
        try new.method_filters.append(.{
            .method = method,
            .op = op,
            .value = value,
        });
        return new;
    }

    /// Filter by column value
    /// Example: .filterColumn("orders", "amount", .gt, .{ .float = 100.0 })
    pub fn filterColumn(self: Self, table: []const u8, column: []const u8, op: FilterOp, value: FilterValue) !Self {
        var new = self;
        try new.column_filters.append(.{
            .table = table,
            .column = column,
            .op = op,
            .value = value,
        });
        return new;
    }

    /// Order by column/method
    pub fn orderBy(self: Self, column: []const u8, descending: bool) Self {
        var new = self;
        const specs = self.allocator.alloc(OrderSpec, 1) catch return new;
        specs[0] = .{ .column = column, .descending = descending };
        new.order_specs = specs;
        return new;
    }

    /// Limit results
    pub fn limit(self: Self, n: u64) Self {
        var new = self;
        new.limit_value = n;
        return new;
    }

    /// Offset results
    pub fn offset(self: Self, n: u64) Self {
        var new = self;
        new.offset_value = n;
        return new;
    }

    /// Execute the query and return results
    pub fn collect(self: *Self) !QueryResult {
        // Load tables if not already loaded
        try self.executor.loadTables();

        const row_count = self.executor.getRowCount();
        if (row_count == 0) {
            return QueryResult{
                .allocator = self.allocator,
                .columns = &.{},
                .row_count = 0,
            };
        }

        // Pre-compute all required method results in batch
        // This is much more efficient than row-by-row evaluation
        try self.computeMethodResults(row_count);

        // Build filtered indices based on column filters
        var filtered_indices = try self.allocator.alloc(u32, row_count);
        defer self.allocator.free(filtered_indices);

        var filtered_count: usize = 0;
        for (0..row_count) |i| {
            if (try self.evaluateColumnFilters(@intCast(i))) {
                filtered_indices[filtered_count] = @intCast(i);
                filtered_count += 1;
            }
        }

        // Apply method filters to narrow down results
        var final_indices = try self.allocator.alloc(u32, filtered_count);
        var final_count: usize = 0;

        for (filtered_indices[0..filtered_count]) |idx| {
            if (self.evaluateMethodFilters(idx)) {
                final_indices[final_count] = idx;
                final_count += 1;
            }
        }

        // Apply limit/offset
        var start: usize = 0;
        var end: usize = final_count;

        if (self.offset_value) |off| {
            start = @min(off, final_count);
        }
        if (self.limit_value) |lim| {
            end = @min(start + lim, final_count);
        }

        const result_count = end - start;

        return QueryResult{
            .allocator = self.allocator,
            .columns = self.select_columns orelse &.{},
            .row_count = result_count,
            .indices = try self.allocator.dupe(u32, final_indices[start..end]),
        };
    }

    /// Compute method results for all rows in batch mode
    /// Results are cached for use in filtering
    fn computeMethodResults(self: *Self, row_count: usize) !void {
        for (self.method_filters.items) |filter| {
            // Skip if already computed
            if (self.method_cache.get(filter.method) != null) continue;

            // Compute method results
            var results: []f64 = undefined;

            if (self.mock_method_fn) |mock_fn| {
                // Use mock function for testing
                results = try mock_fn(filter.method, row_count, self.allocator);
            } else {
                // Use real batch dispatch from executor
                // Parse method name format: "ClassName.method_name" or just "method_name"
                var class_name: []const u8 = "VectorOps";
                var method_name: []const u8 = filter.method;

                if (std.mem.indexOf(u8, filter.method, ".")) |dot_idx| {
                    class_name = filter.method[0..dot_idx];
                    method_name = filter.method[dot_idx + 1 ..];
                }

                // Check if method supports batch processing
                if (self.executor.methodSupportsBatch(class_name, method_name)) {
                    // Get input data from context based on method requirements
                    // This requires knowing what columns the method expects
                    // For now, fallback to placeholder until method metadata is available
                    results = try self.allocator.alloc(f64, row_count);
                    @memset(results, 0.0);
                    // NOTE: Full batch integration requires method signature metadata
                    // to know which columns to pass. Future: use executor.callMethodBatchOutput()
                } else {
                    // Fallback: allocate zeros (method not found or no batch support)
                    results = try self.allocator.alloc(f64, row_count);
                    @memset(results, 0.0);
                }
            }

            try self.method_cache.put(filter.method, results);
        }
    }

    /// Evaluate column filters for a row
    fn evaluateColumnFilters(self: *Self, row_idx: u32) !bool {
        for (self.column_filters.items) |filter| {
            const matches = try self.evaluateColumnFilter(filter, row_idx);
            if (!matches) return false;
        }
        return true;
    }

    fn evaluateColumnFilter(self: *Self, filter: ColumnFilter, row_idx: u32) !bool {
        // Get column value from context
        const ctx = self.executor.getContext();

        // Try to get as f32 first
        if (ctx.getF32(filter.table, filter.column)) |data| {
            const value = data[row_idx];
            const threshold = switch (filter.value) {
                .float => |f| @as(f32, @floatCast(f)),
                .int => |i| @as(f32, @floatFromInt(i)),
                else => return false,
            };
            return self.compareValues(f32, value, threshold, filter.op);
        } else |_| {}

        // Try i64
        if (ctx.getI64(filter.table, filter.column)) |data| {
            const value = data[row_idx];
            const threshold = switch (filter.value) {
                .int => |i| i,
                .float => |f| @as(i64, @intFromFloat(f)),
                else => return false,
            };
            return self.compareValues(i64, value, threshold, filter.op);
        } else |_| {}

        return false;
    }

    /// Evaluate method filters for a row using cached batch results
    fn evaluateMethodFilters(self: *Self, row_idx: u32) bool {
        for (self.method_filters.items) |filter| {
            // Get cached results for this method
            const results = self.method_cache.get(filter.method) orelse {
                // No results cached - skip this filter (shouldn't happen)
                continue;
            };

            // Get the value for this row
            if (row_idx >= results.len) continue;
            const value = results[row_idx];

            // Compare against filter threshold
            const matches = self.compareValues(f64, value, filter.value, filter.op);
            if (!matches) return false;
        }
        return true;
    }

    fn compareValues(self: *Self, comptime T: type, a: T, b: T, op: FilterOp) bool {
        _ = self;
        return switch (op) {
            .eq => a == b,
            .ne => a != b,
            .lt => a < b,
            .le => a <= b,
            .gt => a > b,
            .ge => a >= b,
        };
    }

    /// Get the LogicTableContext for direct column access
    pub fn getContext(self: *Self) *LogicTableContext {
        return self.executor.getContext();
    }

    /// Get row count
    pub fn count(self: *Self) !u64 {
        const result = try self.collect();
        return result.row_count;
    }

    /// Set mock method function for testing
    /// The function should return per-row results for the given method
    pub fn setMockMethodFn(self: *Self, mock_fn: *const fn ([]const u8, usize, std.mem.Allocator) anyerror![]f64) void {
        self.mock_method_fn = mock_fn;
    }

    /// Get cached method results (for testing/debugging)
    pub fn getMethodResults(self: *const Self, method: []const u8) ?[]const f64 {
        return self.method_cache.get(method);
    }
};

/// Query result from LogicTableDataFrame.collect()
pub const QueryResult = struct {
    allocator: std.mem.Allocator,
    columns: []const []const u8,
    row_count: usize,
    indices: ?[]const u32 = null,

    pub fn deinit(self: *QueryResult) void {
        if (self.indices) |idx| {
            self.allocator.free(idx);
        }
    }
};

// =============================================================================
// Tests
// =============================================================================

test "LogicTableDataFrame basic" {
    const allocator = std.testing.allocator;

    // Create a simple executor
    var executor = try LogicTableExecutor.init(allocator, "test.py");
    defer executor.deinit();

    // Create DataFrame from executor
    var df = LogicTableDataFrame.fromExecutor(allocator, &executor);
    defer {
        df.method_filters.deinit();
        df.column_filters.deinit();
    }

    // Test method chaining
    const filtered = df.select(&.{ "id", "score" }).limit(10);
    try std.testing.expectEqual(@as(u64, 10), filtered.limit_value.?);
}

test "FilterOp comparison" {
    try std.testing.expect(FilterOp.gt != FilterOp.lt);
    try std.testing.expect(FilterOp.eq == FilterOp.eq);
}

test "method filter with mock results" {
    const allocator = std.testing.allocator;

    // Create a simple executor
    var executor = try LogicTableExecutor.init(allocator, "test.py");

    // Create DataFrame from executor
    var df = LogicTableDataFrame.fromExecutor(allocator, &executor);
    defer {
        df.method_filters.deinit();
        df.column_filters.deinit();
        df.method_cache.deinit();
        executor.deinit();
    }

    // Mock method function that returns risk scores [0.1, 0.5, 0.8, 0.3, 0.9]
    const mock_fn = struct {
        fn compute(_: []const u8, row_count: usize, alloc: std.mem.Allocator) ![]f64 {
            const results = try alloc.alloc(f64, row_count);
            const mock_scores = [_]f64{ 0.1, 0.5, 0.8, 0.3, 0.9 };
            for (0..row_count) |i| {
                results[i] = if (i < mock_scores.len) mock_scores[i] else 0.0;
            }
            return results;
        }
    }.compute;

    df.setMockMethodFn(mock_fn);

    // Add filter: risk_score > 0.5
    _ = try df.filterMethod("risk_score", .gt, 0.5);

    // Verify filter was added
    try std.testing.expectEqual(@as(usize, 1), df.method_filters.items.len);
    try std.testing.expectEqualStrings("risk_score", df.method_filters.items[0].method);
    try std.testing.expectEqual(FilterOp.gt, df.method_filters.items[0].op);
    try std.testing.expectEqual(@as(f64, 0.5), df.method_filters.items[0].value);
}

test "MethodResultCache" {
    const allocator = std.testing.allocator;

    var cache = MethodResultCache.init(allocator);
    defer cache.deinit();

    // Add some results
    var results = try allocator.alloc(f64, 5);
    results[0] = 0.1;
    results[1] = 0.2;
    results[2] = 0.3;
    results[3] = 0.4;
    results[4] = 0.5;

    try cache.put("risk_score", results);

    // Retrieve and verify
    const retrieved = cache.get("risk_score");
    try std.testing.expect(retrieved != null);
    try std.testing.expectEqual(@as(f64, 0.1), retrieved.?[0]);
    try std.testing.expectEqual(@as(f64, 0.5), retrieved.?[4]);

    // Non-existent method
    try std.testing.expect(cache.get("unknown") == null);
}
