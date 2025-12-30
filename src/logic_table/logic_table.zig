// Logic Table Integration for LanceQL
// This module provides the interface for @logic_table functions compiled by metal0
//
// Workflow:
// 1. Python code with @logic_table decorator is compiled by metal0
// 2. metal0 --emit-logic-table compiles to .a static library
// 3. LanceQL links the .a file (placed in lib/logic_table.a)
// 4. Compiled @logic_table structs are accessed via extern declarations
//
// The .a file contains:
// - Compiled @logic_table Python classes as Zig structs
// - metal0 runtime (bundled)
// - c_interop modules for numpy/external libs (bundled)
//
// Key Design: UDF Context Access
// ==============================
// Unlike traditional UDFs which are "black boxes", @logic_table functions can:
// 1. Access query context (filtered indices, total/matched row counts)
// 2. See pushdown predicates to optimize execution
// 3. Use shared column cache to avoid redundant data loading
// 4. Memoize results for repeated calls with same inputs
//
// This enables @logic_table functions to:
// - Skip rows already filtered by WHERE clause
// - Batch process only matching rows
// - Share data with the query engine efficiently

const std = @import("std");

// Re-export executor module
pub const executor = @import("executor.zig");
pub const LogicTableExecutor = executor.LogicTableExecutor;

// Re-export DataFrame module
pub const dataframe = @import("dataframe.zig");
pub const LogicTableDataFrame = dataframe.LogicTableDataFrame;
pub const QueryResult = dataframe.QueryResult;
pub const FilterOp = dataframe.FilterOp;

/// LogicTable struct metadata - describes a compiled @logic_table class
pub const LogicTableMeta = struct {
    name: []const u8,
    methods: []const MethodMeta,
};

/// Method metadata - describes a method on a @logic_table class
pub const MethodMeta = struct {
    name: []const u8,
    /// Column dependencies in "table.column" format
    deps: []const []const u8,
};

/// Errors from LogicTable execution
pub const LogicTableError = error{
    ColumnNotBound,
    ColumnNotFound,
    MethodNotFound,
    TypeMismatch,
    DimensionMismatch,
    OutOfMemory,
    GPUError,
    InvalidLogicTable,
    TableNotFound,
    CacheMiss,
    PredicateNotSupported,
};

// =============================================================================
// Query Context - Exposes pushdown data to @logic_table functions
// =============================================================================

/// Predicate operation types that can be pushed down
pub const PredicateOp = enum {
    eq, // =
    ne, // !=
    lt, // <
    le, // <=
    gt, // >
    ge, // >=
    like, // LIKE
    in_list, // IN (...)
    between, // BETWEEN
    is_null, // IS NULL
    is_not_null, // IS NOT NULL
};

/// A single filter predicate extracted from WHERE clause
/// @logic_table functions can use this to optimize execution
pub const FilterPredicate = struct {
    /// Column name this predicate applies to
    column: []const u8,
    /// Table alias (if any)
    table_alias: ?[]const u8,
    /// Operation type
    op: PredicateOp,
    /// Comparison value(s) - stored as f64 for numeric, string ptr for text
    value_f64: ?f64,
    value_i64: ?i64,
    value_str: ?[]const u8,
    /// For IN/BETWEEN: additional values
    values_f64: ?[]const f64,
    values_i64: ?[]const i64,
};

/// Query execution context passed to @logic_table functions
/// This breaks the "black box" UDF model by exposing query state
pub const QueryContext = struct {
    allocator: std.mem.Allocator,

    // Row filtering info
    /// Total rows in source table(s) before filtering
    total_rows: usize,
    /// Number of rows after WHERE clause filtering
    matched_rows: usize,
    /// Indices of rows that passed WHERE clause (null = all rows)
    filtered_indices: ?[]const u32,

    // Pushdown predicates from WHERE clause
    /// Predicates that @logic_table can use to optimize
    predicates: []const FilterPredicate,

    // Result cache for memoization
    /// Cache key -> cached result (for repeated calls, query-scoped)
    result_cache: std.StringHashMap(CachedResult),

    // External cache provider (optional, cross-query)
    /// Pluggable cache for Redis, file-based, or other persistent caches
    external_cache: ?CacheProvider,

    // Query metadata
    /// Current query depth (for nested subqueries)
    query_depth: u32,
    /// Whether this is a GROUP BY aggregation context
    is_aggregation: bool,
    /// Current group key (if in GROUP BY context)
    group_key: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .total_rows = 0,
            .matched_rows = 0,
            .filtered_indices = null,
            .predicates = &.{},
            .result_cache = std.StringHashMap(CachedResult).init(allocator),
            .external_cache = null,
            .query_depth = 0,
            .is_aggregation = false,
            .group_key = null,
        };
    }

    /// Initialize with external cache provider
    pub fn initWithCache(allocator: std.mem.Allocator, cache: CacheProvider) Self {
        return .{
            .allocator = allocator,
            .total_rows = 0,
            .matched_rows = 0,
            .filtered_indices = null,
            .predicates = &.{},
            .result_cache = std.StringHashMap(CachedResult).init(allocator),
            .external_cache = cache,
            .query_depth = 0,
            .is_aggregation = false,
            .group_key = null,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free cached results
        var iter = self.result_cache.valueIterator();
        while (iter.next()) |cached| {
            cached.deinit(self.allocator);
        }
        self.result_cache.deinit();
        // Note: external_cache cleanup is caller's responsibility
    }

    /// Check if a column has a predicate pushed down
    pub fn getPredicateForColumn(self: *const Self, column: []const u8) ?FilterPredicate {
        for (self.predicates) |pred| {
            if (std.mem.eql(u8, pred.column, column)) {
                return pred;
            }
        }
        return null;
    }

    /// Check if we should process a row (based on filtered_indices)
    pub fn shouldProcessRow(self: *const Self, row_idx: u32) bool {
        if (self.filtered_indices) |indices| {
            // Binary search for efficiency
            return std.sort.binarySearch(u32, indices, row_idx, {}, struct {
                fn cmp(_: void, a: u32, b: u32) std.math.Order {
                    return std.math.order(a, b);
                }
            }.cmp) != null;
        }
        // No filter = process all rows
        return true;
    }

    /// Get cached result (checks in-memory first, then external cache)
    pub fn getCached(self: *Self, key: []const u8) ?CachedResult {
        // Check in-memory cache first (fast path)
        if (self.result_cache.get(key)) |result| {
            return result;
        }
        // Fall back to external cache if available
        if (self.external_cache) |ext| {
            if (ext.get(key)) |result| {
                // Promote to in-memory for this query
                self.result_cache.put(
                    self.allocator.dupe(u8, key) catch return null,
                    result,
                ) catch {};
                return result;
            }
        }
        return null;
    }

    /// Store result in cache (both in-memory and external if available)
    pub fn putCached(self: *Self, key: []const u8, result: CachedResult) LogicTableError!void {
        const key_copy = self.allocator.dupe(u8, key) catch return LogicTableError.OutOfMemory;
        self.result_cache.put(key_copy, result) catch {
            self.allocator.free(key_copy);
            return LogicTableError.OutOfMemory;
        };
        // Also store in external cache if available
        if (self.external_cache) |ext| {
            ext.set(key, result);
        }
    }

    /// Invalidate cache entries matching pattern
    pub fn invalidateCache(self: *Self, pattern: []const u8) void {
        // For in-memory cache, we'd need to iterate and match
        // For simplicity, external cache handles pattern matching
        if (self.external_cache) |ext| {
            ext.invalidate(pattern);
        }
    }

    /// Get selectivity ratio (matched_rows / total_rows)
    pub fn getSelectivity(self: *const Self) f64 {
        if (self.total_rows == 0) return 1.0;
        return @as(f64, @floatFromInt(self.matched_rows)) / @as(f64, @floatFromInt(self.total_rows));
    }

    /// Check if this is a highly selective query (< 10% rows)
    pub fn isHighlySelective(self: *const Self) bool {
        return self.getSelectivity() < 0.1;
    }
};

/// Cached result from @logic_table function call
pub const CachedResult = union(enum) {
    f64_scalar: f64,
    i64_scalar: i64,
    f64_array: []f64,
    i64_array: []i64,
    f32_array: []f32,
    bool_scalar: bool,

    pub fn deinit(self: *CachedResult, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .f64_array => |arr| allocator.free(arr),
            .i64_array => |arr| allocator.free(arr),
            .f32_array => |arr| allocator.free(arr),
            else => {},
        }
    }
};

// =============================================================================
// External Cache Provider - for cross-query and persistent caching
// =============================================================================

/// External cache provider interface (vtable pattern)
/// Allows plugging in Redis, file-based, or other persistent caches
pub const CacheProvider = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Get cached value by key, returns null on miss
        get: *const fn (ptr: *anyopaque, key: []const u8) ?CachedResult,
        /// Set cached value with key
        set: *const fn (ptr: *anyopaque, key: []const u8, value: CachedResult) void,
        /// Invalidate cache entries matching pattern (e.g., "fraud_*")
        invalidate: *const fn (ptr: *anyopaque, pattern: []const u8) void,
        /// Close/cleanup the cache provider
        deinit: *const fn (ptr: *anyopaque) void,
    };

    pub fn get(self: CacheProvider, key: []const u8) ?CachedResult {
        return self.vtable.get(self.ptr, key);
    }

    pub fn set(self: CacheProvider, key: []const u8, value: CachedResult) void {
        self.vtable.set(self.ptr, key, value);
    }

    pub fn invalidate(self: CacheProvider, pattern: []const u8) void {
        self.vtable.invalidate(self.ptr, pattern);
    }

    pub fn deinit(self: CacheProvider) void {
        self.vtable.deinit(self.ptr);
    }
};

/// No-op cache provider (does nothing, for testing or when caching disabled)
pub const NoOpCacheProvider = struct {
    pub fn provider(self: *NoOpCacheProvider) CacheProvider {
        return .{
            .ptr = self,
            .vtable = &.{
                .get = get,
                .set = set,
                .invalidate = invalidate,
                .deinit = deinitFn,
            },
        };
    }

    fn get(_: *anyopaque, _: []const u8) ?CachedResult {
        return null;
    }

    fn set(_: *anyopaque, _: []const u8, _: CachedResult) void {}

    fn invalidate(_: *anyopaque, _: []const u8) void {}

    fn deinitFn(_: *anyopaque) void {}
};

/// Runtime context for executing LogicTable methods
/// Stores pre-loaded column data for batch operations
/// Also provides access to query context for pushdown optimization
pub const LogicTableContext = struct {
    allocator: std.mem.Allocator,

    /// Cached column data: "table.column" → slice
    column_cache_f32: std.StringHashMap([]const f32),
    column_cache_i64: std.StringHashMap([]const i64),

    /// Owned keys that need to be freed
    owned_keys: std.ArrayListUnmanaged([]const u8),

    /// Query context for pushdown access (null if not in query)
    query_context: ?*QueryContext,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .column_cache_f32 = std.StringHashMap([]const f32).init(allocator),
            .column_cache_i64 = std.StringHashMap([]const i64).init(allocator),
            .owned_keys = .{},
            .query_context = null,
        };
    }

    /// Create context with query context attached
    pub fn initWithQuery(allocator: std.mem.Allocator, query_ctx: *QueryContext) Self {
        return .{
            .allocator = allocator,
            .column_cache_f32 = std.StringHashMap([]const f32).init(allocator),
            .column_cache_i64 = std.StringHashMap([]const i64).init(allocator),
            .owned_keys = .{},
            .query_context = query_ctx,
        };
    }

    pub fn deinit(self: *Self) void {
        // Free owned keys
        for (self.owned_keys.items) |key| {
            self.allocator.free(key);
        }
        self.owned_keys.deinit(self.allocator);
        self.column_cache_f32.deinit();
        self.column_cache_i64.deinit();
    }

    /// Bind f32 column data with a key like "table.column"
    pub fn bindColumnF32(self: *Self, key: []const u8, data: []const f32) LogicTableError!void {
        const key_copy = self.allocator.dupe(u8, key) catch return LogicTableError.OutOfMemory;
        errdefer self.allocator.free(key_copy);

        self.column_cache_f32.put(key_copy, data) catch return LogicTableError.OutOfMemory;
        self.owned_keys.append(self.allocator, key_copy) catch return LogicTableError.OutOfMemory;
    }

    /// Bind i64 column data with a key like "table.column"
    pub fn bindColumnI64(self: *Self, key: []const u8, data: []const i64) LogicTableError!void {
        const key_copy = self.allocator.dupe(u8, key) catch return LogicTableError.OutOfMemory;
        errdefer self.allocator.free(key_copy);

        self.column_cache_i64.put(key_copy, data) catch return LogicTableError.OutOfMemory;
        self.owned_keys.append(self.allocator, key_copy) catch return LogicTableError.OutOfMemory;
    }

    /// Bind f32 column data with table alias and column name
    pub fn bindF32(self: *Self, table_alias: []const u8, column_name: []const u8, data: []const f32) LogicTableError!void {
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ table_alias, column_name }) catch
            return LogicTableError.OutOfMemory;
        return self.bindColumnF32(key, data);
    }

    /// Bind i64 column data with table alias and column name
    pub fn bindI64(self: *Self, table_alias: []const u8, column_name: []const u8, data: []const i64) LogicTableError!void {
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ table_alias, column_name }) catch
            return LogicTableError.OutOfMemory;
        return self.bindColumnI64(key, data);
    }

    /// Get bound f32 column data
    pub fn getColumnF32(self: *const Self, key: []const u8) ?[]const f32 {
        return self.column_cache_f32.get(key);
    }

    /// Get bound i64 column data
    pub fn getColumnI64(self: *const Self, key: []const u8) ?[]const i64 {
        return self.column_cache_i64.get(key);
    }

    /// Get f32 column data by table alias and column name
    pub fn getF32(self: *const Self, table_alias: []const u8, column_name: []const u8) LogicTableError![]const f32 {
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ table_alias, column_name }) catch
            return LogicTableError.OutOfMemory;

        return self.column_cache_f32.get(key) orelse LogicTableError.ColumnNotBound;
    }

    /// Get i64 column data by table alias and column name
    pub fn getI64(self: *const Self, table_alias: []const u8, column_name: []const u8) LogicTableError![]const i64 {
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ table_alias, column_name }) catch
            return LogicTableError.OutOfMemory;

        return self.column_cache_i64.get(key) orelse LogicTableError.ColumnNotBound;
    }

    // =========================================================================
    // Query Context Access - breaks the UDF "black box" model
    // =========================================================================

    /// Get the query context (if in query execution)
    pub fn getQueryContext(self: *const Self) ?*QueryContext {
        return self.query_context;
    }

    /// Get filtered row indices from WHERE clause
    /// Returns null if no filter applied (all rows)
    pub fn getFilteredIndices(self: *const Self) ?[]const u32 {
        if (self.query_context) |ctx| {
            return ctx.filtered_indices;
        }
        return null;
    }

    /// Get total row count before filtering
    pub fn getTotalRows(self: *const Self) usize {
        if (self.query_context) |ctx| {
            return ctx.total_rows;
        }
        return 0;
    }

    /// Get matched row count after filtering
    pub fn getMatchedRows(self: *const Self) usize {
        if (self.query_context) |ctx| {
            return ctx.matched_rows;
        }
        return 0;
    }

    /// Get selectivity ratio (useful for choosing algorithms)
    pub fn getSelectivity(self: *const Self) f64 {
        if (self.query_context) |ctx| {
            return ctx.getSelectivity();
        }
        return 1.0; // No context = assume all rows
    }

    /// Check if query is highly selective (< 10% rows)
    pub fn isHighlySelective(self: *const Self) bool {
        if (self.query_context) |ctx| {
            return ctx.isHighlySelective();
        }
        return false;
    }

    /// Get pushdown predicate for a column
    pub fn getPredicateForColumn(self: *const Self, column: []const u8) ?FilterPredicate {
        if (self.query_context) |ctx| {
            return ctx.getPredicateForColumn(column);
        }
        return null;
    }

    /// Check if should process a specific row
    pub fn shouldProcessRow(self: *const Self, row_idx: u32) bool {
        if (self.query_context) |ctx| {
            return ctx.shouldProcessRow(row_idx);
        }
        return true; // No context = process all
    }

    /// Check if in aggregation context (GROUP BY)
    pub fn isAggregation(self: *const Self) bool {
        if (self.query_context) |ctx| {
            return ctx.is_aggregation;
        }
        return false;
    }

    /// Get current group key (if in GROUP BY)
    pub fn getGroupKey(self: *const Self) ?[]const u8 {
        if (self.query_context) |ctx| {
            return ctx.group_key;
        }
        return null;
    }

    /// Cache a result for memoization
    pub fn cacheResult(self: *Self, key: []const u8, result: CachedResult) LogicTableError!void {
        if (self.query_context) |ctx| {
            return ctx.putCached(key, result);
        }
        // No context = can't cache
    }

    /// Get cached result
    pub fn getCachedResult(self: *Self, key: []const u8) ?CachedResult {
        if (self.query_context) |ctx| {
            return ctx.getCached(key);
        }
        return null;
    }
};

/// Registry of all available logic_table structs
/// The actual structs are linked from the .a static library
pub const LogicTableRegistry = struct {
    allocator: std.mem.Allocator,

    /// Registered tables (populated at runtime or via extern symbols)
    tables: std.StringHashMap(LogicTableMeta),

    pub fn init(allocator: std.mem.Allocator) LogicTableRegistry {
        return .{
            .allocator = allocator,
            .tables = std.StringHashMap(LogicTableMeta).init(allocator),
        };
    }

    pub fn deinit(self: *LogicTableRegistry) void {
        self.tables.deinit();
    }

    /// Register a logic_table struct
    pub fn register(self: *LogicTableRegistry, meta: LogicTableMeta) LogicTableError!void {
        self.tables.put(meta.name, meta) catch return LogicTableError.OutOfMemory;
    }

    /// Get metadata about a logic_table struct by name
    pub fn getTable(self: *const LogicTableRegistry, name: []const u8) ?LogicTableMeta {
        return self.tables.get(name);
    }

    /// List all registered table names
    pub fn listTables(self: *const LogicTableRegistry, allocator: std.mem.Allocator) LogicTableError![]const []const u8 {
        var names = std.ArrayListUnmanaged([]const u8){};
        errdefer names.deinit(allocator);

        var iter = self.tables.keyIterator();
        while (iter.next()) |key| {
            names.append(allocator, key.*) catch return LogicTableError.OutOfMemory;
        }

        return names.toOwnedSlice(allocator) catch LogicTableError.OutOfMemory;
    }
};

// =============================================================================
// Extern declarations for functions from the linked .a static library
// These are populated when lib/logic_table.a is linked
// =============================================================================

// Example: if your Python @logic_table class has a method like:
//   @logic_table
//   class VectorOps:
//       def cosine_similarity(self, query_embedding, doc_embedding) -> float:
//           ...
//
// metal0 will emit an extern function like:
//   export fn VectorOps_cosine_similarity(query: [*]const f32, query_len: usize,
//                                          doc: [*]const f32, doc_len: usize) f32;
//
// You can declare and use it here:
//   extern fn VectorOps_cosine_similarity(query: [*]const f32, query_len: usize,
//                                          doc: [*]const f32, doc_len: usize) f32;

// =============================================================================
// Tests
// =============================================================================

test "LogicTableContext basic" {
    const allocator = std.testing.allocator;
    var ctx = LogicTableContext.init(allocator);
    defer ctx.deinit();

    const f32_data = [_]f32{ 1.0, 2.0, 3.0 };
    const i64_data = [_]i64{ 10, 20, 30 };

    try ctx.bindF32("docs", "embedding", &f32_data);
    try ctx.bindI64("docs", "id", &i64_data);

    const retrieved_f32 = try ctx.getF32("docs", "embedding");
    try std.testing.expectEqual(@as(usize, 3), retrieved_f32.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), retrieved_f32[0], 0.001);

    const retrieved_i64 = try ctx.getI64("docs", "id");
    try std.testing.expectEqual(@as(usize, 3), retrieved_i64.len);
    try std.testing.expectEqual(@as(i64, 10), retrieved_i64[0]);
}

test "LogicTableRegistry basic" {
    const allocator = std.testing.allocator;
    var registry = LogicTableRegistry.init(allocator);
    defer registry.deinit();

    const methods = [_]MethodMeta{
        .{ .name = "cosine_similarity", .deps = &[_][]const u8{ "docs.embedding", "query.embedding" } },
    };

    try registry.register(.{
        .name = "VectorOps",
        .methods = &methods,
    });

    const meta = registry.getTable("VectorOps");
    try std.testing.expect(meta != null);
    try std.testing.expectEqualStrings("VectorOps", meta.?.name);
    try std.testing.expectEqual(@as(usize, 1), meta.?.methods.len);
}

test "QueryContext basic" {
    const allocator = std.testing.allocator;
    var query_ctx = QueryContext.init(allocator);
    defer query_ctx.deinit();

    // Set up query context
    query_ctx.total_rows = 1000;
    query_ctx.matched_rows = 100;

    // Test selectivity
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), query_ctx.getSelectivity(), 0.001);
    try std.testing.expect(query_ctx.isHighlySelective());
}

test "QueryContext with filtered indices" {
    const allocator = std.testing.allocator;
    var query_ctx = QueryContext.init(allocator);
    defer query_ctx.deinit();

    const indices = [_]u32{ 5, 10, 15, 20, 25 };
    query_ctx.filtered_indices = &indices;
    query_ctx.total_rows = 100;
    query_ctx.matched_rows = 5;

    // Test shouldProcessRow
    try std.testing.expect(query_ctx.shouldProcessRow(10));
    try std.testing.expect(!query_ctx.shouldProcessRow(11));
    try std.testing.expect(query_ctx.shouldProcessRow(25));
    try std.testing.expect(!query_ctx.shouldProcessRow(0));
}

test "QueryContext predicates" {
    const allocator = std.testing.allocator;
    var query_ctx = QueryContext.init(allocator);
    defer query_ctx.deinit();

    const predicates = [_]FilterPredicate{
        .{
            .column = "price",
            .table_alias = null,
            .op = .lt,
            .value_f64 = 100.0,
            .value_i64 = null,
            .value_str = null,
            .values_f64 = null,
            .values_i64 = null,
        },
    };
    query_ctx.predicates = &predicates;

    // Test getPredicateForColumn
    const pred = query_ctx.getPredicateForColumn("price");
    try std.testing.expect(pred != null);
    try std.testing.expectEqual(PredicateOp.lt, pred.?.op);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), pred.?.value_f64.?, 0.001);

    // Non-existent column
    try std.testing.expect(query_ctx.getPredicateForColumn("quantity") == null);
}

test "LogicTableContext with QueryContext" {
    const allocator = std.testing.allocator;

    var query_ctx = QueryContext.init(allocator);
    defer query_ctx.deinit();
    query_ctx.total_rows = 1000;
    query_ctx.matched_rows = 50;

    var ctx = LogicTableContext.initWithQuery(allocator, &query_ctx);
    defer ctx.deinit();

    // Test query context access through LogicTableContext
    try std.testing.expectEqual(@as(usize, 1000), ctx.getTotalRows());
    try std.testing.expectEqual(@as(usize, 50), ctx.getMatchedRows());
    try std.testing.expectApproxEqAbs(@as(f64, 0.05), ctx.getSelectivity(), 0.001);
    try std.testing.expect(ctx.isHighlySelective());
}

test "QueryContext caching" {
    const allocator = std.testing.allocator;
    var query_ctx = QueryContext.init(allocator);
    defer query_ctx.deinit();

    // Cache a result
    try query_ctx.putCached("test_key", .{ .f64_scalar = 42.0 });

    // Retrieve it
    const cached = query_ctx.getCached("test_key");
    try std.testing.expect(cached != null);
    try std.testing.expectApproxEqAbs(@as(f64, 42.0), cached.?.f64_scalar, 0.001);

    // Non-existent key
    try std.testing.expect(query_ctx.getCached("missing") == null);
}
