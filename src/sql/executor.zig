//! SQL Executor - Execute parsed SQL queries against Lance files
//!
//! Takes a parsed AST and executes it against Lance columnar files,
//! returning results in columnar format compatible with better-sqlite3.

const std = @import("std");
const ast = @import("ast");
const Table = @import("lanceql.table").Table;
pub const logic_table_dispatch = @import("logic_table_dispatch.zig");

const Expr = ast.Expr;
const SelectStmt = ast.SelectStmt;
const Value = ast.Value;
const BinaryOp = ast.BinaryOp;

/// Aggregate function types
pub const AggregateType = enum {
    count,
    count_star,
    sum,
    avg,
    min,
    max,
    // Statistical aggregates
    stddev, // Sample standard deviation
    variance, // Sample variance
    stddev_pop, // Population standard deviation
    var_pop, // Population variance
    // Percentile-based aggregates (require storing all values)
    median, // 50th percentile
    percentile, // Arbitrary percentile (0-1)
};

/// Accumulator for aggregate computations
pub const Accumulator = struct {
    agg_type: AggregateType,
    count: i64,
    sum: f64,
    sum_sq: f64, // Sum of squares for variance/stddev
    min_int: ?i64,
    max_int: ?i64,
    min_float: ?f64,
    max_float: ?f64,

    pub fn init(agg_type: AggregateType) Accumulator {
        return Accumulator{
            .agg_type = agg_type,
            .count = 0,
            .sum = 0,
            .sum_sq = 0,
            .min_int = null,
            .max_int = null,
            .min_float = null,
            .max_float = null,
        };
    }

    pub fn addInt(self: *Accumulator, value: i64) void {
        const fval = @as(f64, @floatFromInt(value));
        self.count += 1;
        self.sum += fval;
        self.sum_sq += fval * fval;
        if (self.min_int == null or value < self.min_int.?) {
            self.min_int = value;
        }
        if (self.max_int == null or value > self.max_int.?) {
            self.max_int = value;
        }
    }

    pub fn addFloat(self: *Accumulator, value: f64) void {
        self.count += 1;
        self.sum += value;
        self.sum_sq += value * value;
        if (self.min_float == null or value < self.min_float.?) {
            self.min_float = value;
        }
        if (self.max_float == null or value > self.max_float.?) {
            self.max_float = value;
        }
    }

    pub fn addCount(self: *Accumulator) void {
        self.count += 1;
    }

    /// Compute variance using the formula: (sum_sq - sum²/n) / divisor
    /// where divisor is (n-1) for sample variance, n for population variance
    fn computeVariance(self: Accumulator, population: bool) f64 {
        if (self.count == 0) return 0;
        if (!population and self.count == 1) return 0; // Sample variance undefined for n=1
        const n = @as(f64, @floatFromInt(self.count));
        const mean = self.sum / n;
        // Variance = E[X²] - E[X]² = sum_sq/n - mean²
        const variance_pop = self.sum_sq / n - mean * mean;
        if (population) {
            return variance_pop;
        } else {
            // Sample variance: multiply by n/(n-1) to get unbiased estimate
            return variance_pop * n / (n - 1);
        }
    }

    pub fn getResult(self: Accumulator) f64 {
        return switch (self.agg_type) {
            .count, .count_star => @as(f64, @floatFromInt(self.count)),
            .sum => self.sum,
            .avg => if (self.count > 0) self.sum / @as(f64, @floatFromInt(self.count)) else 0,
            .min => self.min_float orelse @as(f64, @floatFromInt(self.min_int orelse 0)),
            .max => self.max_float orelse @as(f64, @floatFromInt(self.max_int orelse 0)),
            .variance => self.computeVariance(false),
            .var_pop => self.computeVariance(true),
            .stddev => @sqrt(self.computeVariance(false)),
            .stddev_pop => @sqrt(self.computeVariance(true)),
            // Percentile-based aggregates use PercentileAccumulator, not this one
            .median, .percentile => unreachable,
        };
    }

    pub fn getIntResult(self: Accumulator) i64 {
        return switch (self.agg_type) {
            .count, .count_star => self.count,
            .sum => @as(i64, @intFromFloat(self.sum)),
            .avg => if (self.count > 0) @as(i64, @intFromFloat(self.sum / @as(f64, @floatFromInt(self.count)))) else 0,
            .min => self.min_int orelse 0,
            .max => self.max_int orelse 0,
            .variance, .var_pop, .stddev, .stddev_pop => @as(i64, @intFromFloat(self.getResult())),
            // Percentile-based aggregates use PercentileAccumulator, not this one
            .median, .percentile => unreachable,
        };
    }
};

/// Accumulator for percentile-based aggregates (MEDIAN, PERCENTILE)
/// These require storing all values to compute the result
pub const PercentileAccumulator = struct {
    allocator: std.mem.Allocator,
    values: std.ArrayList(f64),
    percentile: f64, // 0.5 for median, configurable for percentile

    pub fn init(allocator: std.mem.Allocator, percentile: f64) PercentileAccumulator {
        return PercentileAccumulator{
            .allocator = allocator,
            .values = std.ArrayList(f64){},
            .percentile = percentile,
        };
    }

    pub fn deinit(self: *PercentileAccumulator) void {
        self.values.deinit(self.allocator);
    }

    pub fn addValue(self: *PercentileAccumulator, value: f64) !void {
        try self.values.append(self.allocator, value);
    }

    pub fn addInt(self: *PercentileAccumulator, value: i64) !void {
        try self.addValue(@as(f64, @floatFromInt(value)));
    }

    pub fn addFloat(self: *PercentileAccumulator, value: f64) !void {
        try self.addValue(value);
    }

    /// Compute the percentile using linear interpolation
    pub fn getResult(self: *PercentileAccumulator) f64 {
        if (self.values.items.len == 0) return 0;

        // Sort values
        std.mem.sort(f64, self.values.items, {}, std.sort.asc(f64));

        const n = self.values.items.len;
        if (n == 1) return self.values.items[0];

        // Calculate position using linear interpolation
        const pos = self.percentile * @as(f64, @floatFromInt(n - 1));
        const lower_idx = @as(usize, @intFromFloat(@floor(pos)));
        const upper_idx = @min(lower_idx + 1, n - 1);
        const fraction = pos - @floor(pos);

        // Linear interpolation between lower and upper values
        const lower_val = self.values.items[lower_idx];
        const upper_val = self.values.items[upper_idx];
        return lower_val + fraction * (upper_val - lower_val);
    }
};

/// Query result in columnar format
pub const Result = struct {
    columns: []Column,
    row_count: usize,
    allocator: std.mem.Allocator,

    pub const Column = struct {
        name: []const u8,
        data: ColumnData,
    };

    pub const ColumnData = union(enum) {
        int64: []i64,
        int32: []i32,
        float64: []f64,
        float32: []f32,
        bool_: []bool,
        string: [][]const u8,
        // Timestamp types (all stored as integers, semantic meaning differs)
        timestamp_s: []i64, // seconds since epoch
        timestamp_ms: []i64, // milliseconds since epoch
        timestamp_us: []i64, // microseconds since epoch
        timestamp_ns: []i64, // nanoseconds since epoch
        date32: []i32, // days since epoch
        date64: []i64, // milliseconds since epoch

        /// Get the length of the column data
        pub fn len(self: ColumnData) usize {
            return switch (self) {
                inline else => |data| data.len,
            };
        }

        /// Free the column data using the provided allocator
        pub fn free(self: ColumnData, allocator: std.mem.Allocator) void {
            switch (self) {
                .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |data| allocator.free(data),
                .int32, .date32 => |data| allocator.free(data),
                .float64 => |data| allocator.free(data),
                .float32 => |data| allocator.free(data),
                .bool_ => |data| allocator.free(data),
                .string => |data| {
                    for (data) |str| {
                        allocator.free(str);
                    }
                    allocator.free(data);
                },
            }
        }
    };

    pub fn deinit(self: *Result) void {
        for (self.columns) |col| {
            col.data.free(self.allocator);
        }
        self.allocator.free(self.columns);
    }
};

/// Cached column data
pub const CachedColumn = union(enum) {
    int64: []i64,
    int32: []i32,
    float64: []f64,
    float32: []f32,
    bool_: []bool,
    string: [][]const u8,
    // Timestamp types
    timestamp_s: []i64,
    timestamp_ms: []i64,
    timestamp_us: []i64,
    timestamp_ns: []i64,
    date32: []i32,
    date64: []i64,

    /// Get the length of the column data
    pub fn len(self: CachedColumn) usize {
        return switch (self) {
            inline else => |data| data.len,
        };
    }

    /// Free the column data using the provided allocator
    pub fn free(self: CachedColumn, allocator: std.mem.Allocator) void {
        switch (self) {
            .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |data| allocator.free(data),
            .int32, .date32 => |data| allocator.free(data),
            .float64 => |data| allocator.free(data),
            .float32 => |data| allocator.free(data),
            .bool_ => |data| allocator.free(data),
            .string => |data| {
                for (data) |str| {
                    allocator.free(str);
                }
                allocator.free(data);
            },
        }
    }
};

/// Materialized data from a JOIN operation
pub const JoinedData = struct {
    /// Column data by name (qualified with table alias if present)
    columns: std.StringHashMap(CachedColumn),
    /// Column names in order
    column_names: [][]const u8,
    /// Number of rows in the joined result
    row_count: usize,
    /// Allocator for cleanup
    allocator: std.mem.Allocator,
    /// Left table pointer (for schema access)
    left_table: *Table,

    pub fn deinit(self: *JoinedData) void {
        // Free column data
        var iter = self.columns.valueIterator();
        while (iter.next()) |col| {
            col.free(self.allocator);
        }
        self.columns.deinit();
        // Free column names
        for (self.column_names) |name| {
            self.allocator.free(name);
        }
        self.allocator.free(self.column_names);
    }
};

/// Active table source for query execution
/// Tracks whether we're using a direct table or a logic_table
pub const TableSource = union(enum) {
    /// Direct table (existing behavior - table injected at init)
    direct: *Table,
    /// Logic table with loaded data from Python file
    logic_table: struct {
        executor: *logic_table_dispatch.LogicTableExecutor,
        primary_table: *Table,
        alias: ?[]const u8,
    },
    /// Joined table with materialized data
    joined: *JoinedData,

    pub fn getTable(self: TableSource) *Table {
        return switch (self) {
            .direct => |t| t,
            .logic_table => |lt| lt.primary_table,
            .joined => |jd| jd.left_table,
        };
    }
};

/// SQL Query Executor
pub const Executor = struct {
    /// Default table (used when FROM is a simple table name or not specified)
    table: ?*Table,
    allocator: std.mem.Allocator,
    column_cache: std.StringHashMap(CachedColumn),
    /// Optional dispatcher for @logic_table method calls
    dispatcher: ?*logic_table_dispatch.Dispatcher = null,
    /// Maps table alias to class name for @logic_table instances
    logic_table_aliases: std.StringHashMap([]const u8),
    /// Currently active table source (set during execute)
    active_source: ?TableSource = null,
    /// Registered tables by name (for JOINs and multi-table queries)
    tables: std.StringHashMap(*Table),

    const Self = @This();

    pub fn init(table: ?*Table, allocator: std.mem.Allocator) Self {
        return .{
            .table = table,
            .allocator = allocator,
            .column_cache = std.StringHashMap(CachedColumn).init(allocator),
            .dispatcher = null,
            .logic_table_aliases = std.StringHashMap([]const u8).init(allocator),
            .active_source = null,
            .tables = std.StringHashMap(*Table).init(allocator),
        };
    }

    /// Register a table by name for use in JOINs and multi-table queries
    pub fn registerTable(self: *Self, name: []const u8, table: *Table) !void {
        try self.tables.put(name, table);
    }

    /// Get a registered table by name
    pub fn getRegisteredTable(self: *Self, name: []const u8) ?*Table {
        return self.tables.get(name);
    }

    /// Initialize with a table (convenience for existing code)
    pub fn initWithTable(table: *Table, allocator: std.mem.Allocator) Self {
        return init(table, allocator);
    }

    /// Get the table (must be set before calling this)
    /// This is used by internal methods that expect a table to be configured.
    inline fn tbl(self: *Self) *Table {
        return self.table orelse unreachable;
    }

    /// Set the dispatcher for @logic_table method calls
    pub fn setDispatcher(self: *Self, dispatcher: *logic_table_dispatch.Dispatcher) void {
        self.dispatcher = dispatcher;
    }

    /// Register a @logic_table alias with its class name
    /// Returns error.DuplicateAlias if alias already registered
    pub fn registerLogicTableAlias(self: *Self, alias: []const u8, class_name: []const u8) !void {
        // Check for existing alias first - we don't support overwriting
        if (self.logic_table_aliases.contains(alias)) {
            return error.DuplicateAlias;
        }

        const alias_copy = try self.allocator.dupe(u8, alias);
        errdefer self.allocator.free(alias_copy);
        const class_copy = try self.allocator.dupe(u8, class_name);
        errdefer self.allocator.free(class_copy);
        try self.logic_table_aliases.put(alias_copy, class_copy);
    }

    pub fn deinit(self: *Self) void {
        // Free cached columns
        var iter = self.column_cache.valueIterator();
        while (iter.next()) |col| {
            col.free(self.allocator);
        }
        self.column_cache.deinit();

        // Free logic_table alias keys and values
        var alias_iter = self.logic_table_aliases.iterator();
        while (alias_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.logic_table_aliases.deinit();

        // Clean up registered tables map (tables are owned by caller, just deinit the map)
        self.tables.deinit();
    }

    // ========================================================================
    // Column Preloading (for WHERE clause optimization)
    // ========================================================================

    /// Extract all column names referenced in an expression
    fn extractColumnNames(self: *Self, expr: *const Expr, list: *std.ArrayList([]const u8)) anyerror!void {
        switch (expr.*) {
            .column => |col| {
                try list.append(self.allocator, col.name);
            },
            .binary => |bin| {
                try self.extractColumnNames(bin.left, list);
                try self.extractColumnNames(bin.right, list);
            },
            .unary => |un| {
                try self.extractColumnNames(un.operand, list);
            },
            .in_list => |in| {
                try self.extractColumnNames(in.expr, list);
                for (in.values) |*val| {
                    try self.extractColumnNames(val, list);
                }
            },
            .in_subquery => |in| {
                try self.extractColumnNames(in.expr, list);
                // Don't extract from subquery - it has its own scope
            },
            .call => |call| {
                for (call.args) |*arg| {
                    try self.extractColumnNames(arg, list);
                }
            },
            else => {},
        }
    }

    /// Preload columns into cache
    fn preloadColumns(self: *Self, col_names: []const []const u8) !void {
        for (col_names) |name| {
            // Skip if already cached
            if (self.column_cache.contains(name)) continue;

            // Use physical column ID (not array index) for column metadata access
            const physical_col_id = self.tbl().physicalColumnId(name) orelse return error.ColumnNotFound;
            const field = self.tbl().getFieldById(physical_col_id) orelse return error.InvalidColumn;

            // Read and cache column based on type
            // Precise type detection (order matters - check specific before general)
            const logical_type = field.logical_type;

            // Timestamp types (check before generic "int" matches)
            if (std.mem.indexOf(u8, logical_type, "timestamp[ns") != null) {
                const data = try self.tbl().readInt64Column(physical_col_id);
                try self.column_cache.put(name, CachedColumn{ .timestamp_ns = data });
            } else if (std.mem.indexOf(u8, logical_type, "timestamp[us") != null) {
                const data = try self.tbl().readInt64Column(physical_col_id);
                try self.column_cache.put(name, CachedColumn{ .timestamp_us = data });
            } else if (std.mem.indexOf(u8, logical_type, "timestamp[ms") != null) {
                const data = try self.tbl().readInt64Column(physical_col_id);
                try self.column_cache.put(name, CachedColumn{ .timestamp_ms = data });
            } else if (std.mem.indexOf(u8, logical_type, "timestamp[s") != null) {
                const data = try self.tbl().readInt64Column(physical_col_id);
                try self.column_cache.put(name, CachedColumn{ .timestamp_s = data });
            } else if (std.mem.indexOf(u8, logical_type, "date32") != null) {
                const data = try self.tbl().readInt32Column(physical_col_id);
                try self.column_cache.put(name, CachedColumn{ .date32 = data });
            } else if (std.mem.indexOf(u8, logical_type, "date64") != null) {
                const data = try self.tbl().readInt64Column(physical_col_id);
                try self.column_cache.put(name, CachedColumn{ .date64 = data });
            } else if (std.mem.eql(u8, logical_type, "int32")) {
                // Explicit int32 type
                const data = try self.tbl().readInt32Column(physical_col_id);
                try self.column_cache.put(name, CachedColumn{ .int32 = data });
            } else if (std.mem.eql(u8, logical_type, "float") or
                std.mem.indexOf(u8, logical_type, "float32") != null)
            {
                // float or float32 → f32
                const data = try self.tbl().readFloat32Column(physical_col_id);
                try self.column_cache.put(name, CachedColumn{ .float32 = data });
            } else if (std.mem.eql(u8, logical_type, "bool") or
                std.mem.indexOf(u8, logical_type, "boolean") != null)
            {
                // bool or boolean → bool
                const data = try self.tbl().readBoolColumn(physical_col_id);
                try self.column_cache.put(name, CachedColumn{ .bool_ = data });
            } else if (std.mem.indexOf(u8, logical_type, "int") != null) {
                // Default integers (int, int64, integer) to int64
                const data = try self.tbl().readInt64Column(physical_col_id);
                try self.column_cache.put(name, CachedColumn{ .int64 = data });
            } else if (std.mem.indexOf(u8, logical_type, "double") != null) {
                // double → float64
                const data = try self.tbl().readFloat64Column(physical_col_id);
                try self.column_cache.put(name, CachedColumn{ .float64 = data });
            } else if (std.mem.indexOf(u8, logical_type, "utf8") != null or
                std.mem.indexOf(u8, logical_type, "string") != null)
            {
                const data = try self.tbl().readStringColumn(physical_col_id);
                try self.column_cache.put(name, CachedColumn{ .string = data });
            } else {
                return error.UnsupportedColumnType;
            }
        }
    }

    /// Get the currently active table for query execution
    fn getActiveTable(self: *Self) !*Table {
        if (self.active_source) |source| {
            return source.getTable();
        }
        return self.table orelse error.NoTableConfigured;
    }

    /// Resolve FROM clause to get the table source
    fn resolveTableSource(self: *Self, from: *const ast.TableRef) anyerror!TableSource {
        switch (from.*) {
            .simple => |simple| {
                // First check if table is registered by name
                if (self.tables.get(simple.name)) |registered_table| {
                    return .{ .direct = registered_table };
                }
                // Otherwise use the default table
                const direct_table = self.table orelse return error.NoTableConfigured;
                return .{ .direct = direct_table };
            },
            .function => |func| {
                // Table-valued function (e.g., logic_table('fraud.py'))
                if (std.mem.eql(u8, func.func.name, "logic_table")) {
                    // Extract file path from first argument
                    if (func.func.args.len == 0) {
                        return error.LogicTableRequiresPath;
                    }

                    const path_arg = func.func.args[0];
                    const path = switch (path_arg) {
                        .value => |val| switch (val) {
                            .string => |s| s,
                            else => return error.LogicTablePathMustBeString,
                        },
                        else => return error.LogicTablePathMustBeString,
                    };

                    // Create LogicTableExecutor from file path (heap allocated)
                    const executor = try self.allocator.create(logic_table_dispatch.LogicTableExecutor);
                    errdefer self.allocator.destroy(executor);
                    executor.* = try logic_table_dispatch.LogicTableExecutor.init(self.allocator, path);
                    errdefer executor.deinit();

                    // Load tables referenced in the Python file
                    try executor.loadTables();

                    // Get primary table (first loaded table)
                    const primary_table = executor.getPrimaryTable() orelse {
                        executor.deinit();
                        self.allocator.destroy(executor);
                        return error.NoTablesInLogicTable;
                    };

                    // Register alias for method dispatch
                    if (func.alias) |alias| {
                        try self.registerLogicTableAlias(alias, executor.class_name);
                    }

                    return .{ .logic_table = .{
                        .executor = executor,
                        .primary_table = primary_table,
                        .alias = func.alias,
                    } };
                }
                return error.UnsupportedTableFunction;
            },
            .join => |join| {
                // Execute JOIN by resolving both sides and performing hash join
                return try self.executeJoin(join.left, &join.join_clause);
            },
        }
    }

    /// Execute a JOIN operation using hash join algorithm
    fn executeJoin(self: *Self, left_ref: *const ast.TableRef, join_clause: *const ast.JoinClause) !TableSource {
        // 1. Resolve left table
        var left_source = try self.resolveTableSource(left_ref);
        errdefer self.releaseTableSource(&left_source);
        const left_table = left_source.getTable();

        // 2. Resolve right table
        var right_source = try self.resolveTableSource(join_clause.table);
        defer self.releaseTableSource(&right_source);
        const right_table = right_source.getTable();

        // 3. Extract join key column names from ON condition
        const join_keys = try self.extractJoinKeys(join_clause.on_condition orelse return error.JoinRequiresOnCondition);

        // 4. Get join key columns from both tables
        const left_key_col_idx = left_table.physicalColumnId(join_keys.left_col) orelse return error.JoinColumnNotFound;
        const right_key_col_idx = right_table.physicalColumnId(join_keys.right_col) orelse return error.JoinColumnNotFound;

        // 5. Read join key data
        const left_key_data = try self.readJoinKeyColumn(left_table, left_key_col_idx);
        defer self.freeJoinKeyData(left_key_data);

        const right_key_data = try self.readJoinKeyColumn(right_table, right_key_col_idx);
        defer self.freeJoinKeyData(right_key_data);

        // 6. Build hash table from right table (build phase)
        var hash_table = std.StringHashMap(std.ArrayListUnmanaged(usize)).init(self.allocator);
        defer {
            var iter = hash_table.iterator();
            while (iter.next()) |entry| {
                // Free the key (we allocated it during insertion)
                self.allocator.free(entry.key_ptr.*);
                // Deinit the ArrayList value
                entry.value_ptr.deinit(self.allocator);
            }
            hash_table.deinit();
        }

        for (0..right_key_data.len()) |idx| {
            const key = try self.joinKeyToString(right_key_data, idx);
            defer self.allocator.free(key);

            const result = try hash_table.getOrPut(key);
            if (!result.found_existing) {
                const key_copy = try self.allocator.dupe(u8, key);
                result.key_ptr.* = key_copy;
                result.value_ptr.* = .{};
            }
            try result.value_ptr.append(self.allocator, idx);
        }

        // 7. Probe phase - find matching rows
        var left_indices = std.ArrayListUnmanaged(usize){};
        defer left_indices.deinit(self.allocator);
        var right_indices = std.ArrayListUnmanaged(usize){};
        defer right_indices.deinit(self.allocator);

        // Track matched rows for outer joins
        var matched_right = std.AutoHashMap(usize, void).init(self.allocator);
        defer matched_right.deinit();

        for (0..left_key_data.len()) |left_idx| {
            const key = try self.joinKeyToString(left_key_data, left_idx);
            defer self.allocator.free(key);

            if (hash_table.get(key)) |right_list| {
                for (right_list.items) |right_idx| {
                    try left_indices.append(self.allocator, left_idx);
                    try right_indices.append(self.allocator, right_idx);
                    try matched_right.put(right_idx, {});
                }
            } else if (join_clause.join_type == .left or join_clause.join_type == .full) {
                // LEFT/FULL JOIN: include left row with NULL for right
                try left_indices.append(self.allocator, left_idx);
                try right_indices.append(self.allocator, std.math.maxInt(usize)); // Sentinel for NULL
            }
        }

        // For RIGHT/FULL JOIN: add unmatched right rows
        if (join_clause.join_type == .right or join_clause.join_type == .full) {
            for (0..right_key_data.len()) |right_idx| {
                if (!matched_right.contains(right_idx)) {
                    try left_indices.append(self.allocator, std.math.maxInt(usize)); // Sentinel for NULL
                    try right_indices.append(self.allocator, right_idx);
                }
            }
        }

        // 8. Build joined result with all columns from both tables
        const joined_data = try self.allocator.create(JoinedData);
        errdefer self.allocator.destroy(joined_data);

        joined_data.* = JoinedData{
            .columns = std.StringHashMap(CachedColumn).init(self.allocator),
            .column_names = &[_][]const u8{},
            .row_count = left_indices.items.len,
            .allocator = self.allocator,
            .left_table = left_table,
        };
        errdefer joined_data.deinit();

        // Build column names list and copy data
        var col_names = std.ArrayListUnmanaged([]const u8){};
        errdefer {
            for (col_names.items) |name| {
                self.allocator.free(name);
            }
            col_names.deinit(self.allocator);
        }

        // Add left table columns (with table alias prefix if available)
        const left_alias = switch (left_ref.*) {
            .simple => |s| s.alias orelse s.name,
            else => "left",
        };

        try self.addJoinedColumns(
            left_table,
            left_alias,
            left_indices.items,
            joined_data,
            &col_names,
            false, // isRightSide
        );

        // Add right table columns
        const right_alias = switch (join_clause.table.*) {
            .simple => |s| s.alias orelse s.name,
            else => "right",
        };

        try self.addJoinedColumns(
            right_table,
            right_alias,
            right_indices.items,
            joined_data,
            &col_names,
            true, // isRightSide
        );

        joined_data.column_names = try col_names.toOwnedSlice(self.allocator);

        // Release left_source ownership since it's now managed by joined_data
        // (we keep left_table pointer in joined_data.left_table)
        switch (left_source) {
            .direct => {}, // Nothing to release
            .logic_table => |*lt| {
                lt.executor.deinit();
                self.allocator.destroy(lt.executor);
            },
            .joined => |jd| {
                jd.deinit();
                self.allocator.destroy(jd);
            },
        }

        return .{ .joined = joined_data };
    }

    /// Extract left and right column names from JOIN ON condition
    fn extractJoinKeys(self: *Self, condition: ast.Expr) !struct { left_col: []const u8, right_col: []const u8 } {
        _ = self;
        // ON condition should be: left.col = right.col
        switch (condition) {
            .binary => |bin| {
                if (bin.op != .eq) return error.JoinConditionMustBeEquality;

                const left_col = switch (bin.left.*) {
                    .column => |col| col.name, // column.table is optional qualifier
                    else => return error.JoinConditionMustBeColumn,
                };

                const right_col = switch (bin.right.*) {
                    .column => |col| col.name,
                    else => return error.JoinConditionMustBeColumn,
                };

                return .{ .left_col = left_col, .right_col = right_col };
            },
            else => return error.JoinConditionMustBeBinary,
        }
    }

    /// Join key data union for different column types
    const JoinKeyData = union(enum) {
        int64: []i64,
        int32: []i32,
        float64: []f64,
        string: [][]const u8,

        fn len(self: JoinKeyData) usize {
            return switch (self) {
                .int64 => |d| d.len,
                .int32 => |d| d.len,
                .float64 => |d| d.len,
                .string => |d| d.len,
            };
        }
    };

    /// Read join key column data
    fn readJoinKeyColumn(self: *Self, table: *Table, col_idx: u32) !JoinKeyData {
        _ = self;
        const field = table.getFieldById(col_idx) orelse return error.InvalidColumn;
        const logical_type = field.logical_type;

        if (std.mem.indexOf(u8, logical_type, "int64") != null or
            std.mem.indexOf(u8, logical_type, "int") != null)
        {
            const data = try table.readInt64Column(col_idx);
            return .{ .int64 = data };
        } else if (std.mem.indexOf(u8, logical_type, "int32") != null) {
            const data = try table.readInt32Column(col_idx);
            return .{ .int32 = data };
        } else if (std.mem.indexOf(u8, logical_type, "float") != null or
            std.mem.indexOf(u8, logical_type, "double") != null)
        {
            const data = try table.readFloat64Column(col_idx);
            return .{ .float64 = data };
        } else if (std.mem.indexOf(u8, logical_type, "string") != null or
            std.mem.indexOf(u8, logical_type, "utf8") != null)
        {
            const data = try table.readStringColumn(col_idx);
            return .{ .string = data };
        }
        return error.UnsupportedJoinKeyType;
    }

    /// Free join key data
    fn freeJoinKeyData(self: *Self, data: JoinKeyData) void {
        switch (data) {
            .int64 => |d| self.allocator.free(d),
            .int32 => |d| self.allocator.free(d),
            .float64 => |d| self.allocator.free(d),
            .string => |d| {
                for (d) |s| self.allocator.free(s);
                self.allocator.free(d);
            },
        }
    }

    /// Convert join key value at index to string for hashing
    fn joinKeyToString(self: *Self, data: JoinKeyData, idx: usize) ![]u8 {
        var buf: [64]u8 = undefined;
        const result = switch (data) {
            .int64 => |d| std.fmt.bufPrint(&buf, "{d}", .{d[idx]}),
            .int32 => |d| std.fmt.bufPrint(&buf, "{d}", .{d[idx]}),
            .float64 => |d| std.fmt.bufPrint(&buf, "{d:.10}", .{d[idx]}),
            .string => |d| return try self.allocator.dupe(u8, d[idx]),
        };
        return try self.allocator.dupe(u8, result catch return error.FormatError);
    }

    /// Add columns from a table to the joined result
    fn addJoinedColumns(
        self: *Self,
        table: *Table,
        alias: []const u8,
        row_indices: []const usize,
        joined_data: *JoinedData,
        col_names: *std.ArrayListUnmanaged([]const u8),
        is_right_side: bool,
    ) !void {
        const schema = table.getSchema() orelse return error.NoSchema;

        for (schema.fields) |field| {
            if (field.id < 0) continue;
            const col_idx: u32 = @intCast(field.id);

            // Create qualified column name: "alias.column"
            const qualified_name = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ alias, field.name });
            errdefer self.allocator.free(qualified_name);

            // Read and filter column data based on row indices
            const col_data = try self.readJoinedColumnData(table, col_idx, row_indices, is_right_side);

            try joined_data.columns.put(qualified_name, col_data);
            try col_names.append(self.allocator, qualified_name);
        }
    }

    /// Read column data for joined rows (handles NULL for outer joins)
    fn readJoinedColumnData(
        self: *Self,
        table: *Table,
        col_idx: u32,
        row_indices: []const usize,
        is_right_side: bool,
    ) !CachedColumn {
        _ = is_right_side;
        const field = table.getFieldById(col_idx) orelse return error.InvalidColumn;
        const logical_type = field.logical_type;

        // Determine column type and read full data
        if (std.mem.indexOf(u8, logical_type, "int64") != null or
            std.mem.indexOf(u8, logical_type, "int") != null)
        {
            const all_data = try table.readInt64Column(col_idx);
            defer self.allocator.free(all_data);

            const result = try self.allocator.alloc(i64, row_indices.len);
            for (row_indices, 0..) |idx, i| {
                if (idx == std.math.maxInt(usize)) {
                    result[i] = 0; // NULL represented as 0 for now
                } else {
                    result[i] = all_data[idx];
                }
            }
            return .{ .int64 = result };
        } else if (std.mem.indexOf(u8, logical_type, "float") != null or
            std.mem.indexOf(u8, logical_type, "double") != null)
        {
            const all_data = try table.readFloat64Column(col_idx);
            defer self.allocator.free(all_data);

            const result = try self.allocator.alloc(f64, row_indices.len);
            for (row_indices, 0..) |idx, i| {
                if (idx == std.math.maxInt(usize)) {
                    result[i] = std.math.nan(f64); // NULL as NaN
                } else {
                    result[i] = all_data[idx];
                }
            }
            return .{ .float64 = result };
        } else if (std.mem.indexOf(u8, logical_type, "string") != null or
            std.mem.indexOf(u8, logical_type, "utf8") != null)
        {
            const all_data = try table.readStringColumn(col_idx);
            defer {
                for (all_data) |s| self.allocator.free(s);
                self.allocator.free(all_data);
            }

            const result = try self.allocator.alloc([]const u8, row_indices.len);
            for (row_indices, 0..) |idx, i| {
                if (idx == std.math.maxInt(usize)) {
                    result[i] = try self.allocator.dupe(u8, ""); // NULL as empty string
                } else {
                    result[i] = try self.allocator.dupe(u8, all_data[idx]);
                }
            }
            return .{ .string = result };
        }

        return error.UnsupportedColumnType;
    }

    /// Release resources associated with a table source
    fn releaseTableSource(self: *Self, source: *TableSource) void {
        switch (source.*) {
            .direct => {
                // Nothing to release - table is managed externally
            },
            .logic_table => |*lt| {
                // Clean up executor and free heap allocation
                lt.executor.deinit();
                self.allocator.destroy(lt.executor);
            },
            .joined => |jd| {
                // Clean up joined data
                jd.deinit();
                self.allocator.destroy(jd);
            },
        }
    }

    /// Execute a SELECT statement
    pub fn execute(self: *Self, stmt: *const SelectStmt, params: []const Value) !Result {
        // 0. Resolve FROM clause to get table source
        var source = try self.resolveTableSource(&stmt.from);
        defer self.releaseTableSource(&source);

        // Set active source and temporarily swap table pointer for internal methods
        self.active_source = source;
        const original_table = self.table;
        self.table = source.getTable();
        defer {
            self.active_source = null;
            self.table = original_table;
        }

        // 1. Bind parameters to WHERE clause (replace ? with actual values)
        if (stmt.where) |where_expr| {
            _ = where_expr; // TODO: Implement parameter binding
        }

        // 1.5. Extract and preload columns referenced in WHERE clause
        if (stmt.where) |where_expr| {
            var col_names = std.ArrayList([]const u8){};
            defer col_names.deinit(self.allocator);

            try self.extractColumnNames(&where_expr, &col_names);
            try self.preloadColumns(col_names.items);
        }

        // 2. Apply WHERE clause to get filtered row indices
        const indices = if (stmt.where) |where_expr|
            try self.evaluateWhere(&where_expr, params)
        else
            try self.getAllIndices();

        defer self.allocator.free(indices);

        // 3. Check if we need GROUP BY processing
        const has_group_by = stmt.group_by != null;
        const has_aggregates = self.hasAggregates(stmt.columns);

        if (has_group_by or has_aggregates) {
            // Execute with GROUP BY / aggregation
            return self.executeWithGroupBy(stmt, indices);
        }

        // 4. Read columns based on SELECT list (non-aggregate path)
        // Window function columns are handled separately
        var columns_list = std.ArrayList(Result.Column){};
        errdefer {
            for (columns_list.items) |*col| {
                self.freeColumnData(&col.data);
            }
            columns_list.deinit(self.allocator);
        }

        const base_columns = try self.readColumns(stmt.columns, indices);
        defer self.allocator.free(base_columns);
        try columns_list.appendSlice(self.allocator, base_columns);

        // 4.5. Evaluate window functions if present
        if (self.hasWindowFunctions(stmt.columns)) {
            try self.evaluateWindowFunctions(&columns_list, stmt.columns, indices);
        }

        var columns = try columns_list.toOwnedSlice(self.allocator);
        var row_count = indices.len;

        // 5. Apply DISTINCT if specified
        if (stmt.distinct) {
            const distinct_result = try self.applyDistinct(columns);
            columns = distinct_result.columns;
            row_count = distinct_result.row_count;
        }

        // 6. Apply ORDER BY (in-memory sorting)
        if (stmt.order_by) |order_by| {
            try self.applyOrderBy(columns, order_by);
        }

        // 7. Apply LIMIT and OFFSET
        const final_row_count = self.applyLimitOffset(columns, stmt.limit, stmt.offset);

        var result = Result{
            .columns = columns,
            .row_count = final_row_count,
            .allocator = self.allocator,
        };

        // 8. Apply set operation (UNION/INTERSECT/EXCEPT) if present
        if (stmt.set_operation) |set_op| {
            result = try self.executeSetOperation(result, set_op, params);
        }

        return result;
    }

    // ========================================================================
    // Set Operation Execution (UNION/INTERSECT/EXCEPT)
    // ========================================================================

    /// Execute a set operation (UNION, INTERSECT, EXCEPT) between two result sets
    /// Note: Takes ownership of left result and frees it after use
    fn executeSetOperation(self: *Self, left_in: Result, set_op: ast.SetOperation, params: []const Value) anyerror!Result {
        var left = left_in;
        defer left.deinit();

        // Execute the right-hand SELECT
        var right = try self.execute(set_op.right, params);
        defer right.deinit();

        // Verify column count matches
        if (left.columns.len != right.columns.len) {
            return error.SetOperationColumnMismatch;
        }

        return switch (set_op.op_type) {
            .union_all => try self.executeUnionAll(left, right),
            .union_distinct => try self.executeUnionDistinct(left, right),
            .intersect => try self.executeIntersect(left, right),
            .except => try self.executeExcept(left, right),
        };
    }

    /// UNION ALL: Concatenate both result sets (keeping duplicates)
    fn executeUnionAll(self: *Self, left: Result, right: Result) !Result {
        const col_count = left.columns.len;
        const total_rows = left.row_count + right.row_count;

        var new_columns = try self.allocator.alloc(Result.Column, col_count);
        errdefer self.allocator.free(new_columns);

        for (0..col_count) |i| {
            const left_col = left.columns[i];
            const right_col = right.columns[i];

            new_columns[i] = Result.Column{
                .name = left_col.name,
                .data = try self.concatenateColumnData(left_col.data, right_col.data, left.row_count, right.row_count),
            };
        }

        // Free old left result columns (but not the data, which is now owned by new_columns)
        // Actually, we need to be careful - left's data is NOT reused, we copied it
        // So we should let the caller free left

        return Result{
            .columns = new_columns,
            .row_count = total_rows,
            .allocator = self.allocator,
        };
    }

    /// UNION: Concatenate and remove duplicates
    fn executeUnionDistinct(self: *Self, left: Result, right: Result) !Result {
        // First do UNION ALL, then apply DISTINCT
        var union_all = try self.executeUnionAll(left, right);
        errdefer union_all.deinit();

        const distinct_result = try self.applyDistinct(union_all.columns);
        union_all.columns = distinct_result.columns;
        union_all.row_count = distinct_result.row_count;

        return union_all;
    }

    /// INTERSECT: Keep only rows that appear in both result sets
    fn executeIntersect(self: *Self, left: Result, right: Result) !Result {
        // Build a hash set of rows from right result
        var right_rows = std.StringHashMap(void).init(self.allocator);
        defer right_rows.deinit();

        for (0..right.row_count) |i| {
            const key = try self.buildRowKey(right.columns, i);
            defer self.allocator.free(key);
            try right_rows.put(try self.allocator.dupe(u8, key), {});
        }
        defer {
            var iter = right_rows.keyIterator();
            while (iter.next()) |key| {
                self.allocator.free(key.*);
            }
        }

        // Find matching rows in left result
        var matching_indices = std.ArrayList(usize){};
        defer matching_indices.deinit(self.allocator);

        var seen = std.StringHashMap(void).init(self.allocator);
        defer {
            var iter = seen.keyIterator();
            while (iter.next()) |key| {
                self.allocator.free(key.*);
            }
            seen.deinit();
        }

        for (0..left.row_count) |i| {
            const key = try self.buildRowKey(left.columns, i);
            defer self.allocator.free(key);

            // Only include if in right AND not already included (for distinct)
            if (right_rows.contains(key) and !seen.contains(key)) {
                try matching_indices.append(self.allocator, i);
                try seen.put(try self.allocator.dupe(u8, key), {});
            }
        }

        return try self.projectRows(left.columns, matching_indices.items);
    }

    /// EXCEPT: Keep rows from left that don't appear in right
    fn executeExcept(self: *Self, left: Result, right: Result) !Result {
        // Build a hash set of rows from right result
        var right_rows = std.StringHashMap(void).init(self.allocator);
        defer right_rows.deinit();

        for (0..right.row_count) |i| {
            const key = try self.buildRowKey(right.columns, i);
            defer self.allocator.free(key);
            try right_rows.put(try self.allocator.dupe(u8, key), {});
        }
        defer {
            var iter = right_rows.keyIterator();
            while (iter.next()) |key| {
                self.allocator.free(key.*);
            }
        }

        // Find rows in left that are NOT in right
        var non_matching_indices = std.ArrayList(usize){};
        defer non_matching_indices.deinit(self.allocator);

        var seen = std.StringHashMap(void).init(self.allocator);
        defer {
            var iter = seen.keyIterator();
            while (iter.next()) |key| {
                self.allocator.free(key.*);
            }
            seen.deinit();
        }

        for (0..left.row_count) |i| {
            const key = try self.buildRowKey(left.columns, i);
            defer self.allocator.free(key);

            // Include if NOT in right AND not already included (for distinct)
            if (!right_rows.contains(key) and !seen.contains(key)) {
                try non_matching_indices.append(self.allocator, i);
                try seen.put(try self.allocator.dupe(u8, key), {});
            }
        }

        return try self.projectRows(left.columns, non_matching_indices.items);
    }

    /// Build a string key representing a row for hashing
    fn buildRowKey(self: *Self, columns: []const Result.Column, row_idx: usize) ![]u8 {
        var key_parts = std.ArrayList(u8){};
        errdefer key_parts.deinit(self.allocator);

        for (columns, 0..) |col, col_idx| {
            if (col_idx > 0) {
                try key_parts.append(self.allocator, '|');
            }

            switch (col.data) {
                .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |data| {
                    var buf: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, "{d}", .{data[row_idx]}) catch unreachable;
                    try key_parts.appendSlice(self.allocator, s);
                },
                .int32, .date32 => |data| {
                    var buf: [16]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, "{d}", .{data[row_idx]}) catch unreachable;
                    try key_parts.appendSlice(self.allocator, s);
                },
                .float64 => |data| {
                    var buf: [64]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, "{d}", .{data[row_idx]}) catch unreachable;
                    try key_parts.appendSlice(self.allocator, s);
                },
                .float32 => |data| {
                    var buf: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, "{d}", .{data[row_idx]}) catch unreachable;
                    try key_parts.appendSlice(self.allocator, s);
                },
                .bool_ => |data| {
                    try key_parts.appendSlice(self.allocator, if (data[row_idx]) "T" else "F");
                },
                .string => |data| {
                    try key_parts.appendSlice(self.allocator, data[row_idx]);
                },
            }
        }

        return try key_parts.toOwnedSlice(self.allocator);
    }

    /// Concatenate two column data arrays
    fn concatenateColumnData(self: *Self, left_data: Result.ColumnData, right_data: Result.ColumnData, left_len: usize, right_len: usize) !Result.ColumnData {
        const total_len = left_len + right_len;

        return switch (left_data) {
            .int64 => |left| {
                const right = right_data.int64;
                const new_data = try self.allocator.alloc(i64, total_len);
                @memcpy(new_data[0..left_len], left[0..left_len]);
                @memcpy(new_data[left_len..], right[0..right_len]);
                return Result.ColumnData{ .int64 = new_data };
            },
            .int32 => |left| {
                const right = right_data.int32;
                const new_data = try self.allocator.alloc(i32, total_len);
                @memcpy(new_data[0..left_len], left[0..left_len]);
                @memcpy(new_data[left_len..], right[0..right_len]);
                return Result.ColumnData{ .int32 = new_data };
            },
            .float64 => |left| {
                const right = right_data.float64;
                const new_data = try self.allocator.alloc(f64, total_len);
                @memcpy(new_data[0..left_len], left[0..left_len]);
                @memcpy(new_data[left_len..], right[0..right_len]);
                return Result.ColumnData{ .float64 = new_data };
            },
            .float32 => |left| {
                const right = right_data.float32;
                const new_data = try self.allocator.alloc(f32, total_len);
                @memcpy(new_data[0..left_len], left[0..left_len]);
                @memcpy(new_data[left_len..], right[0..right_len]);
                return Result.ColumnData{ .float32 = new_data };
            },
            .bool_ => |left| {
                const right = right_data.bool_;
                const new_data = try self.allocator.alloc(bool, total_len);
                @memcpy(new_data[0..left_len], left[0..left_len]);
                @memcpy(new_data[left_len..], right[0..right_len]);
                return Result.ColumnData{ .bool_ = new_data };
            },
            .string => |left| {
                const right = right_data.string;
                const new_data = try self.allocator.alloc([]const u8, total_len);
                errdefer self.allocator.free(new_data);

                // Copy strings (need to duplicate)
                for (0..left_len) |i| {
                    new_data[i] = try self.allocator.dupe(u8, left[i]);
                }
                for (0..right_len) |i| {
                    new_data[left_len + i] = try self.allocator.dupe(u8, right[i]);
                }
                return Result.ColumnData{ .string = new_data };
            },
            .timestamp_s => |left| {
                const right = right_data.timestamp_s;
                const new_data = try self.allocator.alloc(i64, total_len);
                @memcpy(new_data[0..left_len], left[0..left_len]);
                @memcpy(new_data[left_len..], right[0..right_len]);
                return Result.ColumnData{ .timestamp_s = new_data };
            },
            .timestamp_ms => |left| {
                const right = right_data.timestamp_ms;
                const new_data = try self.allocator.alloc(i64, total_len);
                @memcpy(new_data[0..left_len], left[0..left_len]);
                @memcpy(new_data[left_len..], right[0..right_len]);
                return Result.ColumnData{ .timestamp_ms = new_data };
            },
            .timestamp_us => |left| {
                const right = right_data.timestamp_us;
                const new_data = try self.allocator.alloc(i64, total_len);
                @memcpy(new_data[0..left_len], left[0..left_len]);
                @memcpy(new_data[left_len..], right[0..right_len]);
                return Result.ColumnData{ .timestamp_us = new_data };
            },
            .timestamp_ns => |left| {
                const right = right_data.timestamp_ns;
                const new_data = try self.allocator.alloc(i64, total_len);
                @memcpy(new_data[0..left_len], left[0..left_len]);
                @memcpy(new_data[left_len..], right[0..right_len]);
                return Result.ColumnData{ .timestamp_ns = new_data };
            },
            .date32 => |left| {
                const right = right_data.date32;
                const new_data = try self.allocator.alloc(i32, total_len);
                @memcpy(new_data[0..left_len], left[0..left_len]);
                @memcpy(new_data[left_len..], right[0..right_len]);
                return Result.ColumnData{ .date32 = new_data };
            },
            .date64 => |left| {
                const right = right_data.date64;
                const new_data = try self.allocator.alloc(i64, total_len);
                @memcpy(new_data[0..left_len], left[0..left_len]);
                @memcpy(new_data[left_len..], right[0..right_len]);
                return Result.ColumnData{ .date64 = new_data };
            },
        };
    }

    /// Project specific rows from a result set
    fn projectRows(self: *Self, columns: []const Result.Column, indices: []const usize) !Result {
        const new_row_count = indices.len;
        const col_count = columns.len;

        var new_columns = try self.allocator.alloc(Result.Column, col_count);
        errdefer self.allocator.free(new_columns);

        for (0..col_count) |col_idx| {
            const col = columns[col_idx];

            new_columns[col_idx] = Result.Column{
                .name = col.name,
                .data = try self.projectColumnData(col.data, indices),
            };
        }

        return Result{
            .columns = new_columns,
            .row_count = new_row_count,
            .allocator = self.allocator,
        };
    }

    /// Project specific rows from column data
    fn projectColumnData(self: *Self, data: Result.ColumnData, indices: []const usize) !Result.ColumnData {
        const len = indices.len;

        return switch (data) {
            .int64 => |d| {
                const new_data = try self.allocator.alloc(i64, len);
                for (indices, 0..) |src_idx, dst_idx| {
                    new_data[dst_idx] = d[src_idx];
                }
                return Result.ColumnData{ .int64 = new_data };
            },
            .int32 => |d| {
                const new_data = try self.allocator.alloc(i32, len);
                for (indices, 0..) |src_idx, dst_idx| {
                    new_data[dst_idx] = d[src_idx];
                }
                return Result.ColumnData{ .int32 = new_data };
            },
            .float64 => |d| {
                const new_data = try self.allocator.alloc(f64, len);
                for (indices, 0..) |src_idx, dst_idx| {
                    new_data[dst_idx] = d[src_idx];
                }
                return Result.ColumnData{ .float64 = new_data };
            },
            .float32 => |d| {
                const new_data = try self.allocator.alloc(f32, len);
                for (indices, 0..) |src_idx, dst_idx| {
                    new_data[dst_idx] = d[src_idx];
                }
                return Result.ColumnData{ .float32 = new_data };
            },
            .bool_ => |d| {
                const new_data = try self.allocator.alloc(bool, len);
                for (indices, 0..) |src_idx, dst_idx| {
                    new_data[dst_idx] = d[src_idx];
                }
                return Result.ColumnData{ .bool_ = new_data };
            },
            .string => |d| {
                const new_data = try self.allocator.alloc([]const u8, len);
                errdefer self.allocator.free(new_data);
                for (indices, 0..) |src_idx, dst_idx| {
                    new_data[dst_idx] = try self.allocator.dupe(u8, d[src_idx]);
                }
                return Result.ColumnData{ .string = new_data };
            },
            .timestamp_s => |d| {
                const new_data = try self.allocator.alloc(i64, len);
                for (indices, 0..) |src_idx, dst_idx| {
                    new_data[dst_idx] = d[src_idx];
                }
                return Result.ColumnData{ .timestamp_s = new_data };
            },
            .timestamp_ms => |d| {
                const new_data = try self.allocator.alloc(i64, len);
                for (indices, 0..) |src_idx, dst_idx| {
                    new_data[dst_idx] = d[src_idx];
                }
                return Result.ColumnData{ .timestamp_ms = new_data };
            },
            .timestamp_us => |d| {
                const new_data = try self.allocator.alloc(i64, len);
                for (indices, 0..) |src_idx, dst_idx| {
                    new_data[dst_idx] = d[src_idx];
                }
                return Result.ColumnData{ .timestamp_us = new_data };
            },
            .timestamp_ns => |d| {
                const new_data = try self.allocator.alloc(i64, len);
                for (indices, 0..) |src_idx, dst_idx| {
                    new_data[dst_idx] = d[src_idx];
                }
                return Result.ColumnData{ .timestamp_ns = new_data };
            },
            .date32 => |d| {
                const new_data = try self.allocator.alloc(i32, len);
                for (indices, 0..) |src_idx, dst_idx| {
                    new_data[dst_idx] = d[src_idx];
                }
                return Result.ColumnData{ .date32 = new_data };
            },
            .date64 => |d| {
                const new_data = try self.allocator.alloc(i64, len);
                for (indices, 0..) |src_idx, dst_idx| {
                    new_data[dst_idx] = d[src_idx];
                }
                return Result.ColumnData{ .date64 = new_data };
            },
        };
    }

    // ========================================================================
    // GROUP BY / Aggregate Execution
    // ========================================================================

    /// Check if SELECT list contains any aggregate functions
    fn hasAggregates(self: *Self, select_list: []const ast.SelectItem) bool {
        _ = self;
        for (select_list) |item| {
            if (containsAggregate(&item.expr)) {
                return true;
            }
        }
        return false;
    }

    /// Recursively check if expression contains an aggregate function
    fn containsAggregate(expr: *const Expr) bool {
        return switch (expr.*) {
            .call => |call| blk: {
                // Check if this is an aggregate function
                const is_agg = isAggregateFunction(call.name);
                if (is_agg) break :blk true;

                // Check arguments recursively
                for (call.args) |*arg| {
                    if (containsAggregate(arg)) break :blk true;
                }
                break :blk false;
            },
            .binary => |bin| containsAggregate(bin.left) or containsAggregate(bin.right),
            .unary => |un| containsAggregate(un.operand),
            else => false,
        };
    }

    /// Check if function name is an aggregate function
    fn isAggregateFunction(name: []const u8) bool {
        // Case-insensitive comparison
        if (name.len < 3 or name.len > 15) return false;

        var upper_buf: [16]u8 = undefined;
        const len = @min(name.len, upper_buf.len);
        const upper_name = std.ascii.upperString(upper_buf[0..len], name[0..len]);

        return std.mem.eql(u8, upper_name, "COUNT") or
            std.mem.eql(u8, upper_name, "SUM") or
            std.mem.eql(u8, upper_name, "AVG") or
            std.mem.eql(u8, upper_name, "MIN") or
            std.mem.eql(u8, upper_name, "MAX") or
            std.mem.eql(u8, upper_name, "STDDEV") or
            std.mem.eql(u8, upper_name, "STDDEV_SAMP") or
            std.mem.eql(u8, upper_name, "STDDEV_POP") or
            std.mem.eql(u8, upper_name, "VARIANCE") or
            std.mem.eql(u8, upper_name, "VAR_SAMP") or
            std.mem.eql(u8, upper_name, "VAR_POP") or
            std.mem.eql(u8, upper_name, "MEDIAN") or
            std.mem.eql(u8, upper_name, "PERCENTILE") or
            std.mem.eql(u8, upper_name, "PERCENTILE_CONT") or
            std.mem.eql(u8, upper_name, "QUANTILE");
    }

    // ========================================================================
    // Window Function Support
    // ========================================================================

    /// Window function types
    const WindowFunctionType = enum {
        row_number,
        rank,
        dense_rank,
        lag,
        lead,
    };

    /// Check if expression is a window function (has OVER clause)
    fn isWindowFunction(expr: *const Expr) bool {
        return switch (expr.*) {
            .call => |call| call.window != null,
            else => false,
        };
    }

    /// Check if SELECT list contains any window functions
    fn hasWindowFunctions(self: *Self, select_list: []const ast.SelectItem) bool {
        _ = self;
        for (select_list) |item| {
            if (isWindowFunction(&item.expr)) {
                return true;
            }
        }
        return false;
    }

    /// Parse window function name
    fn parseWindowFunctionType(name: []const u8) ?WindowFunctionType {
        var upper_buf: [16]u8 = undefined;
        const upper_name = std.ascii.upperString(&upper_buf, name);

        if (std.mem.eql(u8, upper_name, "ROW_NUMBER")) return .row_number;
        if (std.mem.eql(u8, upper_name, "RANK")) return .rank;
        if (std.mem.eql(u8, upper_name, "DENSE_RANK")) return .dense_rank;
        if (std.mem.eql(u8, upper_name, "LAG")) return .lag;
        if (std.mem.eql(u8, upper_name, "LEAD")) return .lead;
        return null;
    }

    /// Evaluate window functions and add result columns
    /// Window functions are evaluated after all base columns are computed
    fn evaluateWindowFunctions(
        self: *Self,
        columns: *std.ArrayList(Result.Column),
        select_list: []const ast.SelectItem,
        indices: []const u32,
    ) !void {
        for (select_list) |item| {
            if (!isWindowFunction(&item.expr)) continue;

            const call = item.expr.call;
            const window_spec = call.window.?;
            const func_type = parseWindowFunctionType(call.name) orelse continue;

            // Build partition groups
            var partitions = try self.buildWindowPartitions(window_spec, indices);
            defer {
                var iter = partitions.valueIterator();
                while (iter.next()) |list| {
                    list.deinit(self.allocator);
                }
                partitions.deinit();
            }

            // Allocate result array
            const results = try self.allocator.alloc(i64, indices.len);
            errdefer self.allocator.free(results);

            // Process each partition
            var partition_iter = partitions.iterator();
            while (partition_iter.next()) |entry| {
                var partition_indices = entry.value_ptr.*;

                // Sort partition by ORDER BY if specified
                if (window_spec.order_by) |order_by| {
                    try self.sortWindowPartition(&partition_indices, order_by);
                }

                // Compute window function for this partition
                switch (func_type) {
                    .row_number => {
                        // ROW_NUMBER: sequential number within partition
                        for (partition_indices.items, 0..) |original_idx, rank| {
                            // Find position in indices array
                            const result_idx = self.findIndexPosition(indices, original_idx);
                            if (result_idx) |idx| {
                                results[idx] = @intCast(rank + 1);
                            }
                        }
                    },
                    .rank => {
                        // RANK: same rank for ties, skip ranks after ties
                        try self.computeRank(results, partition_indices.items, indices, window_spec.order_by, false);
                    },
                    .dense_rank => {
                        // DENSE_RANK: same rank for ties, no gaps
                        try self.computeRank(results, partition_indices.items, indices, window_spec.order_by, true);
                    },
                    .lag => {
                        // LAG: value from N rows before
                        const offset: usize = if (call.args.len > 1) blk: {
                            const arg = call.args[1];
                            if (arg == .value and arg.value == .integer) {
                                break :blk @intCast(arg.value.integer);
                            }
                            break :blk 1;
                        } else 1;

                        const default_val: i64 = if (call.args.len > 2) blk: {
                            const arg = call.args[2];
                            if (arg == .value and arg.value == .integer) {
                                break :blk arg.value.integer;
                            }
                            break :blk 0;
                        } else 0;

                        try self.computeLagLead(results, partition_indices.items, indices, call.args, offset, default_val, true);
                    },
                    .lead => {
                        // LEAD: value from N rows after
                        const offset: usize = if (call.args.len > 1) blk: {
                            const arg = call.args[1];
                            if (arg == .value and arg.value == .integer) {
                                break :blk @intCast(arg.value.integer);
                            }
                            break :blk 1;
                        } else 1;

                        const default_val: i64 = if (call.args.len > 2) blk: {
                            const arg = call.args[2];
                            if (arg == .value and arg.value == .integer) {
                                break :blk arg.value.integer;
                            }
                            break :blk 0;
                        } else 0;

                        try self.computeLagLead(results, partition_indices.items, indices, call.args, offset, default_val, false);
                    },
                }
            }

            // Add result column
            const col_name = item.alias orelse call.name;
            try columns.append(self.allocator, Result.Column{
                .name = col_name,
                .data = Result.ColumnData{ .int64 = results },
            });
        }
    }

    /// Build partition groups based on PARTITION BY columns
    fn buildWindowPartitions(
        self: *Self,
        window_spec: *const ast.WindowSpec,
        indices: []const u32,
    ) !std.StringHashMap(std.ArrayListUnmanaged(u32)) {
        var partitions = std.StringHashMap(std.ArrayListUnmanaged(u32)).init(self.allocator);
        errdefer {
            var iter = partitions.valueIterator();
            while (iter.next()) |list| {
                list.deinit(self.allocator);
            }
            partitions.deinit();
        }

        if (window_spec.partition_by) |partition_cols| {
            // Preload partition columns
            try self.preloadColumns(partition_cols);

            // Group rows by partition key
            for (indices) |row_idx| {
                const key = try self.buildPartitionKey(partition_cols, row_idx);
                const result = try partitions.getOrPut(key);
                if (!result.found_existing) {
                    result.value_ptr.* = .{};
                }
                try result.value_ptr.append(self.allocator, row_idx);
            }
        } else {
            // No PARTITION BY - all rows in one partition
            var single_partition: std.ArrayListUnmanaged(u32) = .{};
            for (indices) |row_idx| {
                try single_partition.append(self.allocator, row_idx);
            }
            try partitions.put("", single_partition);
        }

        return partitions;
    }

    /// Build partition key from row values
    fn buildPartitionKey(self: *Self, partition_cols: [][]const u8, row_idx: u32) ![]const u8 {
        var key_parts = std.ArrayList(u8){};
        errdefer key_parts.deinit(self.allocator);

        for (partition_cols, 0..) |col_name, i| {
            if (i > 0) try key_parts.append(self.allocator, '|');

            const col = self.column_cache.get(col_name) orelse return error.ColumnNotFound;
            const value_str = try self.columnValueToString(col, row_idx);
            try key_parts.appendSlice(self.allocator, value_str);
        }

        return key_parts.toOwnedSlice(self.allocator);
    }

    /// Convert column value at index to string for key building
    fn columnValueToString(self: *Self, col: CachedColumn, row_idx: u32) ![]const u8 {
        return switch (col) {
            .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |data| blk: {
                const val = data[row_idx];
                const buf = try self.allocator.alloc(u8, 32);
                const written = std.fmt.bufPrint(buf, "{d}", .{val}) catch "";
                break :blk written;
            },
            .int32, .date32 => |data| blk: {
                const val = data[row_idx];
                const buf = try self.allocator.alloc(u8, 16);
                const written = std.fmt.bufPrint(buf, "{d}", .{val}) catch "";
                break :blk written;
            },
            .float64 => |data| blk: {
                const val = data[row_idx];
                const buf = try self.allocator.alloc(u8, 32);
                const written = std.fmt.bufPrint(buf, "{d}", .{val}) catch "";
                break :blk written;
            },
            .float32 => |data| blk: {
                const val = data[row_idx];
                const buf = try self.allocator.alloc(u8, 32);
                const written = std.fmt.bufPrint(buf, "{d}", .{val}) catch "";
                break :blk written;
            },
            .bool_ => |data| if (data[row_idx]) "true" else "false",
            .string => |data| data[row_idx],
        };
    }

    /// Sort partition indices by ORDER BY columns
    fn sortWindowPartition(
        self: *Self,
        partition: *std.ArrayListUnmanaged(u32),
        order_by: []const ast.OrderBy,
    ) !void {
        // Preload ORDER BY columns
        var col_names = std.ArrayList([]const u8){};
        defer col_names.deinit(self.allocator);
        for (order_by) |ob| {
            try col_names.append(self.allocator, ob.column);
        }
        try self.preloadColumns(col_names.items);

        // Sort using first ORDER BY column (simplified - full impl would use all)
        if (order_by.len == 0) return;

        const first_ob = order_by[0];
        const col_name = first_ob.column;

        const cached_col = self.column_cache.get(col_name) orelse return;
        const ascending = first_ob.direction == .asc;

        // Sort partition indices based on column values
        const WindowSortCtx = struct {
            col: CachedColumn,
            asc: bool,

            fn lessThan(c: @This(), a: u32, b: u32) bool {
                const result = switch (c.col) {
                    .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |data| data[a] < data[b],
                    .int32, .date32 => |data| data[a] < data[b],
                    .float64 => |data| data[a] < data[b],
                    .float32 => |data| data[a] < data[b],
                    .string => |data| std.mem.lessThan(u8, data[a], data[b]),
                    .bool_ => |data| @intFromBool(data[a]) < @intFromBool(data[b]),
                };
                return if (c.asc) result else !result;
            }
        };

        const sort_ctx = WindowSortCtx{ .col = cached_col, .asc = ascending };
        std.mem.sort(u32, partition.items, sort_ctx, WindowSortCtx.lessThan);
    }

    /// Find position of original row index in indices array
    fn findIndexPosition(self: *Self, indices: []const u32, original_idx: u32) ?usize {
        _ = self;
        for (indices, 0..) |idx, pos| {
            if (idx == original_idx) return pos;
        }
        return null;
    }

    /// Compute RANK or DENSE_RANK for partition
    fn computeRank(
        self: *Self,
        results: []i64,
        partition: []const u32,
        indices: []const u32,
        order_by: ?[]const ast.OrderBy,
        dense: bool,
    ) !void {
        if (partition.len == 0) return;

        var current_rank: i64 = 1;
        var prev_value: ?i64 = null;
        var rows_at_rank: i64 = 0;

        // Get ORDER BY column for comparison
        const order_col: ?CachedColumn = if (order_by) |ob| blk: {
            if (ob.len == 0) break :blk null;
            const col_name = ob[0].column;
            break :blk self.column_cache.get(col_name);
        } else null;

        for (partition, 0..) |original_idx, i| {
            const result_idx = self.findIndexPosition(indices, original_idx) orelse continue;

            if (order_col) |col| {
                const current_value: i64 = switch (col) {
                    .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |data| data[original_idx],
                    .int32, .date32 => |data| data[original_idx],
                    .float64 => |data| @intFromFloat(data[original_idx]),
                    .float32 => |data| @intFromFloat(data[original_idx]),
                    .string => |data| @intCast(std.hash.Wyhash.hash(0, data[original_idx])),
                    .bool_ => |data| if (data[original_idx]) 1 else 0,
                };

                if (prev_value) |pv| {
                    if (current_value != pv) {
                        // Value changed - update rank
                        if (dense) {
                            current_rank += 1;
                        } else {
                            current_rank += rows_at_rank;
                        }
                        rows_at_rank = 1;
                    } else {
                        rows_at_rank += 1;
                    }
                } else {
                    rows_at_rank = 1;
                }
                prev_value = current_value;
            } else {
                // No ORDER BY - all get rank 1
                _ = i;
            }

            results[result_idx] = current_rank;
        }
    }

    /// Compute LAG or LEAD for partition
    fn computeLagLead(
        self: *Self,
        results: []i64,
        partition: []const u32,
        indices: []const u32,
        args: []const Expr,
        offset: usize,
        default_val: i64,
        is_lag: bool,
    ) !void {
        if (args.len == 0) return;

        // Get the column to look up
        const col_name = switch (args[0]) {
            .column => |col| col.name,
            else => return,
        };

        const cached_col = self.column_cache.get(col_name) orelse return;

        for (partition, 0..) |original_idx, i| {
            const result_idx = self.findIndexPosition(indices, original_idx) orelse continue;

            // Calculate source index
            const source_partition_idx: ?usize = if (is_lag) blk: {
                if (i < offset) break :blk null;
                break :blk i - offset;
            } else blk: {
                if (i + offset >= partition.len) break :blk null;
                break :blk i + offset;
            };

            if (source_partition_idx) |src_idx| {
                const src_original_idx = partition[src_idx];
                results[result_idx] = switch (cached_col) {
                    .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |data| data[src_original_idx],
                    .int32, .date32 => |data| data[src_original_idx],
                    .float64 => |data| @intFromFloat(data[src_original_idx]),
                    .float32 => |data| @intFromFloat(data[src_original_idx]),
                    .string => 0, // LAG/LEAD on strings returns 0 for now
                    .bool_ => |data| if (data[src_original_idx]) 1 else 0,
                };
            } else {
                results[result_idx] = default_val;
            }
        }
    }

    /// Parse aggregate function name to AggregateType
    fn parseAggregateType(name: []const u8, args: []const Expr) AggregateType {
        var upper_buf: [16]u8 = undefined;
        const len = @min(name.len, upper_buf.len);
        const upper_name = std.ascii.upperString(upper_buf[0..len], name[0..len]);

        if (std.mem.eql(u8, upper_name, "COUNT")) {
            // COUNT(*) vs COUNT(col)
            if (args.len == 1 and args[0] == .column and
                std.mem.eql(u8, args[0].column.name, "*"))
            {
                return .count_star;
            }
            return .count;
        } else if (std.mem.eql(u8, upper_name, "SUM")) {
            return .sum;
        } else if (std.mem.eql(u8, upper_name, "AVG")) {
            return .avg;
        } else if (std.mem.eql(u8, upper_name, "MIN")) {
            return .min;
        } else if (std.mem.eql(u8, upper_name, "MAX")) {
            return .max;
        } else if (std.mem.eql(u8, upper_name, "STDDEV") or std.mem.eql(u8, upper_name, "STDDEV_SAMP")) {
            return .stddev;
        } else if (std.mem.eql(u8, upper_name, "STDDEV_POP")) {
            return .stddev_pop;
        } else if (std.mem.eql(u8, upper_name, "VARIANCE") or std.mem.eql(u8, upper_name, "VAR_SAMP")) {
            return .variance;
        } else if (std.mem.eql(u8, upper_name, "VAR_POP")) {
            return .var_pop;
        } else if (std.mem.eql(u8, upper_name, "MEDIAN")) {
            return .median;
        } else if (std.mem.eql(u8, upper_name, "PERCENTILE") or
            std.mem.eql(u8, upper_name, "PERCENTILE_CONT") or
            std.mem.eql(u8, upper_name, "QUANTILE"))
        {
            return .percentile;
        }
        return .count; // Default fallback
    }

    /// Execute SELECT with GROUP BY and/or aggregates
    fn executeWithGroupBy(self: *Self, stmt: *const SelectStmt, filtered_indices: []const u32) !Result {
        // Preload all columns we'll need for grouping and aggregates
        try self.preloadGroupByColumns(stmt);

        // Get group by column names (empty if no GROUP BY but has aggregates)
        const group_cols = if (stmt.group_by) |gb| gb.columns else &[_][]const u8{};

        // Build groups: maps group key to list of row indices
        var groups = std.StringHashMap(std.ArrayListUnmanaged(u32)).init(self.allocator);
        defer {
            var iter = groups.valueIterator();
            while (iter.next()) |list| {
                list.deinit(self.allocator);
            }
            groups.deinit();
        }

        // Also need to track key strings for proper cleanup
        var key_strings = std.ArrayListUnmanaged([]const u8){};
        defer {
            for (key_strings.items) |key| {
                self.allocator.free(key);
            }
            key_strings.deinit(self.allocator);
        }

        // Group rows by their group key
        for (filtered_indices) |row_idx| {
            const key = try self.buildGroupKey(group_cols, row_idx);

            if (groups.getPtr(key)) |list| {
                // Existing group - add row index and free the duplicate key
                try list.append(self.allocator, row_idx);
                self.allocator.free(key);
            } else {
                // New group
                var list = std.ArrayListUnmanaged(u32){};
                try list.append(self.allocator, row_idx);
                try groups.put(key, list);
                try key_strings.append(self.allocator, key);
            }
        }

        // If no GROUP BY and no matching rows, return single row with 0/null for aggregates
        const num_groups = if (groups.count() == 0 and group_cols.len == 0)
            @as(usize, 1) // Single aggregate result
        else
            groups.count();

        // Build result columns
        var result_columns = std.ArrayListUnmanaged(Result.Column){};
        errdefer {
            for (result_columns.items) |col| {
                col.data.free(self.allocator);
            }
            result_columns.deinit(self.allocator);
        }

        // Process each SELECT item
        for (stmt.columns) |item| {
            const col = try self.evaluateSelectItemForGroups(item, &groups, group_cols, num_groups);
            try result_columns.append(self.allocator, col);
        }

        var result = Result{
            .columns = try result_columns.toOwnedSlice(self.allocator),
            .row_count = num_groups,
            .allocator = self.allocator,
        };

        // Apply HAVING clause
        if (stmt.group_by) |gb| {
            if (gb.having) |having_expr| {
                try self.applyHaving(&result, &having_expr, stmt.columns);
            }
        }

        // Apply ORDER BY
        if (stmt.order_by) |order_by| {
            try self.applyOrderBy(result.columns, order_by);
        }

        // Apply LIMIT/OFFSET
        result.row_count = self.applyLimitOffset(result.columns, stmt.limit, stmt.offset);

        return result;
    }

    /// Preload columns needed for GROUP BY and aggregates
    fn preloadGroupByColumns(self: *Self, stmt: *const SelectStmt) !void {
        var col_names = std.ArrayList([]const u8){};
        defer col_names.deinit(self.allocator);

        // Add GROUP BY columns
        if (stmt.group_by) |gb| {
            for (gb.columns) |col| {
                try col_names.append(self.allocator, col);
            }
        }

        // Add columns referenced in SELECT expressions
        for (stmt.columns) |item| {
            try self.extractExprColumnNames(&item.expr, &col_names);
        }

        try self.preloadColumns(col_names.items);
    }

    /// Extract column names from any expression
    fn extractExprColumnNames(self: *Self, expr: *const Expr, list: *std.ArrayList([]const u8)) anyerror!void {
        switch (expr.*) {
            .column => |col| {
                if (!std.mem.eql(u8, col.name, "*")) {
                    try list.append(self.allocator, col.name);
                }
            },
            .binary => |bin| {
                try self.extractExprColumnNames(bin.left, list);
                try self.extractExprColumnNames(bin.right, list);
            },
            .unary => |un| {
                try self.extractExprColumnNames(un.operand, list);
            },
            .call => |call| {
                for (call.args) |*arg| {
                    try self.extractExprColumnNames(arg, list);
                }
            },
            else => {},
        }
    }

    /// Build a group key string from GROUP BY column values for a row
    fn buildGroupKey(self: *Self, group_cols: []const []const u8, row_idx: u32) ![]const u8 {
        if (group_cols.len == 0) {
            // No GROUP BY - all rows in one group
            return try self.allocator.dupe(u8, "__all__");
        }

        var key = std.ArrayList(u8){};
        errdefer key.deinit(self.allocator);

        for (group_cols, 0..) |col_name, i| {
            if (i > 0) try key.append(self.allocator, '|');

            const cached = self.column_cache.get(col_name) orelse return error.ColumnNotCached;

            switch (cached) {
                .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |data| {
                    var buf: [64]u8 = undefined;
                    const str = std.fmt.bufPrint(&buf, "{d}", .{data[row_idx]}) catch |err| return err;
                    try key.appendSlice(self.allocator, str);
                },
                .int32, .date32 => |data| {
                    var buf: [32]u8 = undefined;
                    const str = std.fmt.bufPrint(&buf, "{d}", .{data[row_idx]}) catch |err| return err;
                    try key.appendSlice(self.allocator, str);
                },
                .float64 => |data| {
                    var buf: [64]u8 = undefined;
                    const str = std.fmt.bufPrint(&buf, "{d}", .{data[row_idx]}) catch |err| return err;
                    try key.appendSlice(self.allocator, str);
                },
                .float32 => |data| {
                    var buf: [32]u8 = undefined;
                    const str = std.fmt.bufPrint(&buf, "{d}", .{data[row_idx]}) catch |err| return err;
                    try key.appendSlice(self.allocator, str);
                },
                .bool_ => |data| {
                    const str = if (data[row_idx]) "true" else "false";
                    try key.appendSlice(self.allocator, str);
                },
                .string => |data| {
                    try key.appendSlice(self.allocator, data[row_idx]);
                },
            }
        }

        return key.toOwnedSlice(self.allocator);
    }

    /// Evaluate a SELECT item for all groups
    fn evaluateSelectItemForGroups(
        self: *Self,
        item: ast.SelectItem,
        groups: *std.StringHashMap(std.ArrayList(u32)),
        group_cols: []const []const u8,
        num_groups: usize,
    ) !Result.Column {
        const expr = &item.expr;

        // Handle aggregate function
        if (expr.* == .call and isAggregateFunction(expr.call.name)) {
            return self.evaluateAggregateForGroups(item, groups, num_groups);
        }

        // Handle regular column (must be in GROUP BY)
        if (expr.* == .column) {
            const col_name = expr.column.name;

            // Verify column is in GROUP BY
            var in_group_by = false;
            for (group_cols) |gb_col| {
                if (std.mem.eql(u8, gb_col, col_name)) {
                    in_group_by = true;
                    break;
                }
            }
            if (!in_group_by and group_cols.len > 0) {
                return error.ColumnNotInGroupBy;
            }

            return self.evaluateGroupByColumnForGroups(item, groups, num_groups);
        }

        return error.UnsupportedExpression;
    }

    /// Evaluate an aggregate function for all groups
    fn evaluateAggregateForGroups(
        self: *Self,
        item: ast.SelectItem,
        groups: *std.StringHashMap(std.ArrayList(u32)),
        num_groups: usize,
    ) !Result.Column {
        const call = item.expr.call;
        const agg_type = parseAggregateType(call.name, call.args);

        // Determine column name for the aggregate (if not COUNT(*))
        const agg_col_name: ?[]const u8 = if (agg_type != .count_star and call.args.len > 0)
            if (call.args[0] == .column) call.args[0].column.name else null
        else
            null;

        // Check if this is a percentile-based aggregate (requires storing all values)
        const is_percentile_agg = agg_type == .median or agg_type == .percentile;

        // Check if this is a float-returning aggregate (stddev, variance)
        const is_float_agg = agg_type == .stddev or agg_type == .stddev_pop or
            agg_type == .variance or agg_type == .var_pop or agg_type == .avg;

        if (is_percentile_agg) {
            // Percentile-based aggregates need to store all values
            const results = try self.allocator.alloc(f64, num_groups);
            errdefer self.allocator.free(results);

            // Handle case of no groups
            if (groups.count() == 0) {
                results[0] = 0;
                return Result.Column{
                    .name = item.alias orelse call.name,
                    .data = Result.ColumnData{ .float64 = results },
                };
            }

            // Get percentile value (0.5 for median, from second arg for percentile)
            const percentile_val: f64 = if (agg_type == .median)
                0.5
            else if (call.args.len >= 2 and call.args[1] == .value)
                switch (call.args[1].value) {
                    .float => |f| f,
                    .integer => |i| @as(f64, @floatFromInt(i)),
                    else => 0.5,
                }
            else
                0.5;

            // Compute percentile for each group
            var group_idx: usize = 0;
            var iter = groups.iterator();
            while (iter.next()) |entry| {
                const row_indices = entry.value_ptr.items;

                var acc = PercentileAccumulator.init(self.allocator, percentile_val);
                defer acc.deinit();

                for (row_indices) |row_idx| {
                    if (agg_col_name) |col_name| {
                        const cached = self.column_cache.get(col_name) orelse return error.ColumnNotCached;

                        switch (cached) {
                            .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |data| try acc.addInt(data[row_idx]),
                            .int32, .date32 => |data| try acc.addInt(data[row_idx]),
                            .float64 => |data| try acc.addFloat(data[row_idx]),
                            .float32 => |data| try acc.addFloat(data[row_idx]),
                            .bool_ => |data| try acc.addInt(if (data[row_idx]) 1 else 0),
                            .string => {}, // Skip strings for percentile
                        }
                    }
                }

                results[group_idx] = acc.getResult();
                group_idx += 1;
            }

            return Result.Column{
                .name = item.alias orelse call.name,
                .data = Result.ColumnData{ .float64 = results },
            };
        } else if (is_float_agg) {
            // Allocate float64 result array
            const results = try self.allocator.alloc(f64, num_groups);
            errdefer self.allocator.free(results);

            // Handle case of no groups
            if (groups.count() == 0) {
                results[0] = 0;
                return Result.Column{
                    .name = item.alias orelse call.name,
                    .data = Result.ColumnData{ .float64 = results },
                };
            }

            // Compute aggregate for each group
            var group_idx: usize = 0;
            var iter = groups.iterator();
            while (iter.next()) |entry| {
                const row_indices = entry.value_ptr.items;

                var acc = Accumulator.init(agg_type);

                for (row_indices) |row_idx| {
                    if (agg_col_name) |col_name| {
                        const cached = self.column_cache.get(col_name) orelse return error.ColumnNotCached;

                        switch (cached) {
                            .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |data| acc.addInt(data[row_idx]),
                            .int32, .date32 => |data| acc.addInt(data[row_idx]),
                            .float64 => |data| acc.addFloat(data[row_idx]),
                            .float32 => |data| acc.addFloat(data[row_idx]),
                            .bool_ => acc.addCount(),
                            .string => acc.addCount(),
                        }
                    } else {
                        acc.addCount();
                    }
                }

                results[group_idx] = acc.getResult();
                group_idx += 1;
            }

            return Result.Column{
                .name = item.alias orelse call.name,
                .data = Result.ColumnData{ .float64 = results },
            };
        } else {
            // Allocate int64 result array for count, sum, min, max
            const results = try self.allocator.alloc(i64, num_groups);
            errdefer self.allocator.free(results);

            // Handle case of no groups (aggregate over empty set or no GROUP BY with data)
            if (groups.count() == 0) {
                // Return 0 for COUNT, null would be better for others but use 0
                results[0] = 0;
                return Result.Column{
                    .name = item.alias orelse call.name,
                    .data = Result.ColumnData{ .int64 = results },
                };
            }

            // Compute aggregate for each group
            var group_idx: usize = 0;
            var iter = groups.iterator();
            while (iter.next()) |entry| {
                const row_indices = entry.value_ptr.items;

                var acc = Accumulator.init(agg_type);

                for (row_indices) |row_idx| {
                    if (agg_type == .count_star) {
                        acc.addCount();
                    } else if (agg_col_name) |col_name| {
                        const cached = self.column_cache.get(col_name) orelse return error.ColumnNotCached;

                        switch (cached) {
                            .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |data| acc.addInt(data[row_idx]),
                            .int32, .date32 => |data| acc.addInt(data[row_idx]),
                            .float64 => |data| acc.addFloat(data[row_idx]),
                            .float32 => |data| acc.addFloat(data[row_idx]),
                            .bool_ => acc.addCount(), // COUNT for bools
                            .string => acc.addCount(), // COUNT for strings
                        }
                    } else {
                        acc.addCount();
                    }
                }

                results[group_idx] = acc.getIntResult();
                group_idx += 1;
            }

            return Result.Column{
                .name = item.alias orelse call.name,
                .data = Result.ColumnData{ .int64 = results },
            };
        }
    }

    /// Evaluate a GROUP BY column for all groups (return first value from each group)
    fn evaluateGroupByColumnForGroups(
        self: *Self,
        item: ast.SelectItem,
        groups: *std.StringHashMap(std.ArrayList(u32)),
        num_groups: usize,
    ) !Result.Column {
        const col_name = item.expr.column.name;
        const cached = self.column_cache.get(col_name) orelse return error.ColumnNotCached;

        // Allocate based on column type
        switch (cached) {
            .int64 => |source_data| {
                const results = try self.allocator.alloc(i64, num_groups);
                errdefer self.allocator.free(results);

                var group_idx: usize = 0;
                var iter = groups.iterator();
                while (iter.next()) |entry| {
                    const row_indices = entry.value_ptr.items;
                    if (row_indices.len > 0) {
                        results[group_idx] = source_data[row_indices[0]];
                    }
                    group_idx += 1;
                }

                return Result.Column{
                    .name = item.alias orelse col_name,
                    .data = Result.ColumnData{ .int64 = results },
                };
            },
            .timestamp_s => |source_data| {
                const results = try self.allocator.alloc(i64, num_groups);
                errdefer self.allocator.free(results);

                var group_idx: usize = 0;
                var iter = groups.iterator();
                while (iter.next()) |entry| {
                    const row_indices = entry.value_ptr.items;
                    if (row_indices.len > 0) {
                        results[group_idx] = source_data[row_indices[0]];
                    }
                    group_idx += 1;
                }

                return Result.Column{
                    .name = item.alias orelse col_name,
                    .data = Result.ColumnData{ .timestamp_s = results },
                };
            },
            .timestamp_ms => |source_data| {
                const results = try self.allocator.alloc(i64, num_groups);
                errdefer self.allocator.free(results);

                var group_idx: usize = 0;
                var iter = groups.iterator();
                while (iter.next()) |entry| {
                    const row_indices = entry.value_ptr.items;
                    if (row_indices.len > 0) {
                        results[group_idx] = source_data[row_indices[0]];
                    }
                    group_idx += 1;
                }

                return Result.Column{
                    .name = item.alias orelse col_name,
                    .data = Result.ColumnData{ .timestamp_ms = results },
                };
            },
            .timestamp_us => |source_data| {
                const results = try self.allocator.alloc(i64, num_groups);
                errdefer self.allocator.free(results);

                var group_idx: usize = 0;
                var iter = groups.iterator();
                while (iter.next()) |entry| {
                    const row_indices = entry.value_ptr.items;
                    if (row_indices.len > 0) {
                        results[group_idx] = source_data[row_indices[0]];
                    }
                    group_idx += 1;
                }

                return Result.Column{
                    .name = item.alias orelse col_name,
                    .data = Result.ColumnData{ .timestamp_us = results },
                };
            },
            .timestamp_ns => |source_data| {
                const results = try self.allocator.alloc(i64, num_groups);
                errdefer self.allocator.free(results);

                var group_idx: usize = 0;
                var iter = groups.iterator();
                while (iter.next()) |entry| {
                    const row_indices = entry.value_ptr.items;
                    if (row_indices.len > 0) {
                        results[group_idx] = source_data[row_indices[0]];
                    }
                    group_idx += 1;
                }

                return Result.Column{
                    .name = item.alias orelse col_name,
                    .data = Result.ColumnData{ .timestamp_ns = results },
                };
            },
            .date64 => |source_data| {
                const results = try self.allocator.alloc(i64, num_groups);
                errdefer self.allocator.free(results);

                var group_idx: usize = 0;
                var iter = groups.iterator();
                while (iter.next()) |entry| {
                    const row_indices = entry.value_ptr.items;
                    if (row_indices.len > 0) {
                        results[group_idx] = source_data[row_indices[0]];
                    }
                    group_idx += 1;
                }

                return Result.Column{
                    .name = item.alias orelse col_name,
                    .data = Result.ColumnData{ .date64 = results },
                };
            },
            .int32 => |source_data| {
                const results = try self.allocator.alloc(i32, num_groups);
                errdefer self.allocator.free(results);

                var group_idx: usize = 0;
                var iter = groups.iterator();
                while (iter.next()) |entry| {
                    const row_indices = entry.value_ptr.items;
                    if (row_indices.len > 0) {
                        results[group_idx] = source_data[row_indices[0]];
                    }
                    group_idx += 1;
                }

                return Result.Column{
                    .name = item.alias orelse col_name,
                    .data = Result.ColumnData{ .int32 = results },
                };
            },
            .date32 => |source_data| {
                const results = try self.allocator.alloc(i32, num_groups);
                errdefer self.allocator.free(results);

                var group_idx: usize = 0;
                var iter = groups.iterator();
                while (iter.next()) |entry| {
                    const row_indices = entry.value_ptr.items;
                    if (row_indices.len > 0) {
                        results[group_idx] = source_data[row_indices[0]];
                    }
                    group_idx += 1;
                }

                return Result.Column{
                    .name = item.alias orelse col_name,
                    .data = Result.ColumnData{ .date32 = results },
                };
            },
            .float64 => |source_data| {
                const results = try self.allocator.alloc(f64, num_groups);
                errdefer self.allocator.free(results);

                var group_idx: usize = 0;
                var iter = groups.iterator();
                while (iter.next()) |entry| {
                    const row_indices = entry.value_ptr.items;
                    if (row_indices.len > 0) {
                        results[group_idx] = source_data[row_indices[0]];
                    }
                    group_idx += 1;
                }

                return Result.Column{
                    .name = item.alias orelse col_name,
                    .data = Result.ColumnData{ .float64 = results },
                };
            },
            .float32 => |source_data| {
                const results = try self.allocator.alloc(f32, num_groups);
                errdefer self.allocator.free(results);

                var group_idx: usize = 0;
                var iter = groups.iterator();
                while (iter.next()) |entry| {
                    const row_indices = entry.value_ptr.items;
                    if (row_indices.len > 0) {
                        results[group_idx] = source_data[row_indices[0]];
                    }
                    group_idx += 1;
                }

                return Result.Column{
                    .name = item.alias orelse col_name,
                    .data = Result.ColumnData{ .float32 = results },
                };
            },
            .bool_ => |source_data| {
                const results = try self.allocator.alloc(bool, num_groups);
                errdefer self.allocator.free(results);

                var group_idx: usize = 0;
                var iter = groups.iterator();
                while (iter.next()) |entry| {
                    const row_indices = entry.value_ptr.items;
                    if (row_indices.len > 0) {
                        results[group_idx] = source_data[row_indices[0]];
                    }
                    group_idx += 1;
                }

                return Result.Column{
                    .name = item.alias orelse col_name,
                    .data = Result.ColumnData{ .bool_ = results },
                };
            },
            .string => |source_data| {
                const results = try self.allocator.alloc([]const u8, num_groups);
                errdefer self.allocator.free(results);

                var group_idx: usize = 0;
                var iter = groups.iterator();
                while (iter.next()) |entry| {
                    const row_indices = entry.value_ptr.items;
                    if (row_indices.len > 0) {
                        results[group_idx] = try self.allocator.dupe(u8, source_data[row_indices[0]]);
                    }
                    group_idx += 1;
                }

                return Result.Column{
                    .name = item.alias orelse col_name,
                    .data = Result.ColumnData{ .string = results },
                };
            },
        }
    }

    // ========================================================================
    // WHERE Clause Evaluation
    // ========================================================================

    /// Evaluate WHERE clause and return matching row indices
    fn evaluateWhere(self: *Self, where_expr: *const Expr, params: []const Value) ![]u32 {
        // Bind parameters first
        var bound_expr = try self.bindParameters(where_expr, params);
        defer self.freeExpr(&bound_expr);

        // Get total row count
        const row_count = try self.tbl().rowCount(0);

        // Evaluate expression for each row
        var matching_indices = std.ArrayList(u32){};
        errdefer matching_indices.deinit(self.allocator);

        var row_idx: u32 = 0;
        while (row_idx < row_count) : (row_idx += 1) {
            const matches = try self.evaluateExprForRow(&bound_expr, row_idx);
            if (matches) {
                try matching_indices.append(self.allocator, row_idx);
            }
        }

        return matching_indices.toOwnedSlice(self.allocator);
    }

    /// Bind parameters (replace ? placeholders with actual values)
    fn bindParameters(self: *Self, expr: *const Expr, params: []const Value) !Expr {
        return switch (expr.*) {
            .value => |val| blk: {
                if (val == .parameter) {
                    const param_idx = val.parameter;
                    if (param_idx >= params.len) return error.ParameterOutOfBounds;
                    break :blk Expr{ .value = params[param_idx] };
                }
                break :blk expr.*;
            },
            .column => expr.*,
            .binary => |bin| blk: {
                const left_ptr = try self.allocator.create(Expr);
                errdefer self.allocator.destroy(left_ptr);
                left_ptr.* = try self.bindParameters(bin.left, params);
                errdefer self.freeExpr(left_ptr);

                const right_ptr = try self.allocator.create(Expr);
                errdefer self.allocator.destroy(right_ptr);
                right_ptr.* = try self.bindParameters(bin.right, params);

                break :blk Expr{
                    .binary = .{
                        .op = bin.op,
                        .left = left_ptr,
                        .right = right_ptr,
                    },
                };
            },
            .unary => |un| blk: {
                const operand_ptr = try self.allocator.create(Expr);
                errdefer self.allocator.destroy(operand_ptr);
                operand_ptr.* = try self.bindParameters(un.operand, params);

                break :blk Expr{
                    .unary = .{
                        .op = un.op,
                        .operand = operand_ptr,
                    },
                };
            },
            .call => |call| blk: {
                // Bind parameters in function arguments
                const new_args = try self.allocator.alloc(Expr, call.args.len);
                errdefer self.allocator.free(new_args);

                for (call.args, 0..) |*arg, i| {
                    new_args[i] = try self.bindParameters(arg, params);
                }

                break :blk Expr{
                    .call = .{
                        .name = call.name,
                        .args = new_args,
                        .distinct = call.distinct,
                        .window = call.window,
                    },
                };
            },
            .in_list => |in| blk: {
                // Bind parameters in IN list
                const new_expr = try self.allocator.create(Expr);
                errdefer self.allocator.destroy(new_expr);
                new_expr.* = try self.bindParameters(in.expr, params);
                errdefer self.freeExpr(new_expr);

                const new_values = try self.allocator.alloc(Expr, in.values.len);
                errdefer self.allocator.free(new_values);

                for (in.values, 0..) |*val, i| {
                    new_values[i] = try self.bindParameters(val, params);
                }

                break :blk Expr{
                    .in_list = .{
                        .expr = new_expr,
                        .values = new_values,
                        .negated = in.negated,
                    },
                };
            },
            .between => |bet| blk: {
                const new_expr = try self.allocator.create(Expr);
                errdefer self.allocator.destroy(new_expr);
                new_expr.* = try self.bindParameters(bet.expr, params);
                errdefer self.freeExpr(new_expr);

                const new_low = try self.allocator.create(Expr);
                errdefer self.allocator.destroy(new_low);
                new_low.* = try self.bindParameters(bet.low, params);
                errdefer self.freeExpr(new_low);

                const new_high = try self.allocator.create(Expr);
                errdefer self.allocator.destroy(new_high);
                new_high.* = try self.bindParameters(bet.high, params);

                break :blk Expr{
                    .between = .{
                        .expr = new_expr,
                        .low = new_low,
                        .high = new_high,
                    },
                };
            },
            // New expression types - pass through for now (execution support TODO)
            .case_expr => expr.*,
            .exists => expr.*,
            .in_subquery => |in| blk: {
                // Bind parameters in IN subquery expression
                const new_expr = try self.allocator.create(Expr);
                errdefer self.allocator.destroy(new_expr);
                new_expr.* = try self.bindParameters(in.expr, params);

                // Subquery uses its own execution context, no need to bind here
                break :blk Expr{
                    .in_subquery = .{
                        .expr = new_expr,
                        .subquery = in.subquery,
                        .negated = in.negated,
                    },
                };
            },
            .cast => expr.*,
            .method_call => |mc| blk: {
                // Bind parameters in method call arguments
                const new_args = try self.allocator.alloc(Expr, mc.args.len);
                errdefer self.allocator.free(new_args);

                for (mc.args, 0..) |*arg, i| {
                    new_args[i] = try self.bindParameters(arg, params);
                }

                break :blk Expr{
                    .method_call = .{
                        .object = mc.object,
                        .method = mc.method,
                        .args = new_args,
                        .over = mc.over, // Window spec passes through (no parameter placeholders)
                    },
                };
            },
        };
    }

    /// Free allocated expression tree
    fn freeExpr(self: *Self, expr: *Expr) void {
        switch (expr.*) {
            .binary => |bin| {
                self.freeExpr(bin.left);
                self.allocator.destroy(bin.left);
                self.freeExpr(bin.right);
                self.allocator.destroy(bin.right);
            },
            .unary => |un| {
                self.freeExpr(un.operand);
                self.allocator.destroy(un.operand);
            },
            .call => |call| {
                for (call.args) |*arg| {
                    self.freeExpr(arg);
                }
                self.allocator.free(call.args);
            },
            .in_list => |in| {
                self.freeExpr(in.expr);
                self.allocator.destroy(in.expr);
                for (in.values) |*val| {
                    self.freeExpr(val);
                }
                self.allocator.free(in.values);
            },
            .in_subquery => |in| {
                self.freeExpr(in.expr);
                self.allocator.destroy(in.expr);
                // Don't free subquery - it's owned by the AST
            },
            .between => |bet| {
                self.freeExpr(bet.expr);
                self.allocator.destroy(bet.expr);
                self.freeExpr(bet.low);
                self.allocator.destroy(bet.low);
                self.freeExpr(bet.high);
                self.allocator.destroy(bet.high);
            },
            else => {},
        }
    }

    /// Evaluate expression for a specific row
    fn evaluateExprForRow(self: *Self, expr: *const Expr, row_idx: u32) anyerror!bool {
        return switch (expr.*) {
            .value => |val| blk: {
                // Literal value - interpret as boolean
                break :blk switch (val) {
                    .integer => |i| i != 0,
                    .float => |f| f != 0.0,
                    .null => false,
                    else => true,
                };
            },
            .column => error.ColumnRequiresComparison,
            .binary => |bin| try self.evaluateBinaryOp(bin.op, bin.left, bin.right, row_idx),
            .unary => |un| try self.evaluateUnaryOp(un.op, un.operand, row_idx),
            .exists => |ex| try self.evaluateExists(ex.subquery, ex.negated),
            .in_list => |in| blk: {
                const result = try self.evaluateInList(in.expr, in.values, row_idx);
                break :blk if (in.negated) !result else result;
            },
            .in_subquery => |in| try self.evaluateInSubquery(in.expr, in.subquery, in.negated, row_idx),
            else => error.UnsupportedExpression,
        };
    }

    /// Evaluate EXISTS subquery
    fn evaluateExists(self: *Self, subquery: *ast.SelectStmt, negated: bool) anyerror!bool {
        // Execute the subquery
        var result = try self.execute(subquery, &[_]Value{});
        defer result.deinit();

        // EXISTS is true if the subquery returns at least one row
        const exists = result.row_count > 0;

        // Apply negation if NOT EXISTS
        return if (negated) !exists else exists;
    }

    /// Evaluate IN list expression
    fn evaluateInList(self: *Self, expr: *const Expr, values: []const Expr, row_idx: u32) anyerror!bool {
        // Get the value of the left expression
        const left_val = try self.evaluateToValue(expr, row_idx);

        // Check if the value is in the list
        for (values) |*val_expr| {
            const list_val = try self.evaluateToValue(val_expr, row_idx);

            // Compare based on type
            const matches = switch (left_val) {
                .integer => |left_int| switch (list_val) {
                    .integer => |right_int| left_int == right_int,
                    .float => |right_float| @as(f64, @floatFromInt(left_int)) == right_float,
                    else => false,
                },
                .float => |left_float| switch (list_val) {
                    .integer => |right_int| left_float == @as(f64, @floatFromInt(right_int)),
                    .float => |right_float| left_float == right_float,
                    else => false,
                },
                .string => |left_str| switch (list_val) {
                    .string => |right_str| std.mem.eql(u8, left_str, right_str),
                    else => false,
                },
                .null => false, // NULL is not equal to anything including itself in IN
                else => false,
            };

            if (matches) return true;
        }

        return false;
    }

    /// Evaluate IN subquery expression
    fn evaluateInSubquery(self: *Self, expr: *const Expr, subquery: *ast.SelectStmt, negated: bool, row_idx: u32) anyerror!bool {
        // Get the value of the left expression
        const left_val = try self.evaluateToValue(expr, row_idx);

        // Execute the subquery
        var result = try self.execute(subquery, &[_]Value{});
        defer result.deinit();

        // Subquery must return exactly one column
        if (result.columns.len != 1) {
            return error.SubqueryMustReturnOneColumn;
        }

        // Check if the value is in the subquery results
        const col = result.columns[0];
        for (0..result.row_count) |i| {
            const subquery_val: Value = switch (col.data) {
                .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |data| .{ .integer = data[i] },
                .int32, .date32 => |data| .{ .integer = data[i] },
                .float64 => |data| .{ .float = data[i] },
                .float32 => |data| .{ .float = data[i] },
                .bool_ => |data| .{ .integer = if (data[i]) 1 else 0 },
                .string => |data| .{ .string = data[i] },
            };

            // Compare based on type
            const matches = switch (left_val) {
                .integer => |left_int| switch (subquery_val) {
                    .integer => |right_int| left_int == right_int,
                    .float => |right_float| @as(f64, @floatFromInt(left_int)) == right_float,
                    else => false,
                },
                .float => |left_float| switch (subquery_val) {
                    .integer => |right_int| left_float == @as(f64, @floatFromInt(right_int)),
                    .float => |right_float| left_float == right_float,
                    else => false,
                },
                .string => |left_str| switch (subquery_val) {
                    .string => |right_str| std.mem.eql(u8, left_str, right_str),
                    else => false,
                },
                .null => false,
                else => false,
            };

            if (matches) {
                return if (negated) false else true;
            }
        }

        return if (negated) true else false;
    }

    /// Evaluate binary operation
    fn evaluateBinaryOp(
        self: *Self,
        op: BinaryOp,
        left: *const Expr,
        right: *const Expr,
        row_idx: u32,
    ) anyerror!bool {
        return switch (op) {
            .@"and" => (try self.evaluateExprForRow(left, row_idx)) and
                       (try self.evaluateExprForRow(right, row_idx)),
            .@"or" => (try self.evaluateExprForRow(left, row_idx)) or
                      (try self.evaluateExprForRow(right, row_idx)),
            .eq, .ne, .lt, .le, .gt, .ge => try self.evaluateComparison(op, left, right, row_idx),
            else => error.UnsupportedOperator,
        };
    }

    /// Evaluate comparison operation
    fn evaluateComparison(
        self: *Self,
        op: BinaryOp,
        left: *const Expr,
        right: *const Expr,
        row_idx: u32,
    ) !bool {
        const left_val = try self.evaluateToValue(left, row_idx);
        const right_val = try self.evaluateToValue(right, row_idx);

        // Type coercion: compare integers and floats
        return switch (left_val) {
            .integer => |left_int| blk: {
                const right_num = switch (right_val) {
                    .integer => |i| @as(f64, @floatFromInt(i)),
                    .float => |f| f,
                    else => return error.TypeMismatch,
                };
                const left_num = @as(f64, @floatFromInt(left_int));
                break :blk self.compareNumbers(op, left_num, right_num);
            },
            .float => |left_float| blk: {
                const right_num = switch (right_val) {
                    .integer => |i| @as(f64, @floatFromInt(i)),
                    .float => |f| f,
                    else => return error.TypeMismatch,
                };
                break :blk self.compareNumbers(op, left_float, right_num);
            },
            .string => |left_str| blk: {
                const right_str = switch (right_val) {
                    .string => |s| s,
                    else => return error.TypeMismatch,
                };
                break :blk self.compareStrings(op, left_str, right_str);
            },
            .null => op == .ne, // NULL != anything is true, NULL == anything is false
            else => error.UnsupportedType,
        };
    }

    /// Compare two numbers
    fn compareNumbers(self: *Self, op: BinaryOp, left: f64, right: f64) bool {
        _ = self;
        return switch (op) {
            .eq => left == right,
            .ne => left != right,
            .lt => left < right,
            .le => left <= right,
            .gt => left > right,
            .ge => left >= right,
            else => unreachable,
        };
    }

    /// Compare two strings
    fn compareStrings(self: *Self, op: BinaryOp, left: []const u8, right: []const u8) bool {
        _ = self;
        const cmp = std.mem.order(u8, left, right);
        return switch (op) {
            .eq => cmp == .eq,
            .ne => cmp != .eq,
            .lt => cmp == .lt,
            .le => cmp == .lt or cmp == .eq,
            .gt => cmp == .gt,
            .ge => cmp == .gt or cmp == .eq,
            else => unreachable,
        };
    }

    /// Evaluate unary operation
    fn evaluateUnaryOp(
        self: *Self,
        op: ast.UnaryOp,
        operand: *const Expr,
        row_idx: u32,
    ) !bool {
        return switch (op) {
            .not => !(try self.evaluateExprForRow(operand, row_idx)),
            .is_null => blk: {
                const val = try self.evaluateToValue(operand, row_idx);
                break :blk val == .null;
            },
            .is_not_null => blk: {
                const val = try self.evaluateToValue(operand, row_idx);
                break :blk val != .null;
            },
            else => error.UnsupportedOperator,
        };
    }

    /// Evaluate expression to a concrete value (for WHERE clause comparisons)
    fn evaluateToValue(self: *Self, expr: *const Expr, row_idx: u32) !Value {
        return switch (expr.*) {
            .value => expr.value,
            .column => |col| blk: {
                // Lookup in cache instead of reading from table
                const cached = self.column_cache.get(col.name) orelse return error.ColumnNotCached;

                break :blk switch (cached) {
                    .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |data| Value{ .integer = data[row_idx] },
                    .int32, .date32 => |data| Value{ .integer = data[row_idx] },
                    .float64 => |data| Value{ .float = data[row_idx] },
                    .float32 => |data| Value{ .float = data[row_idx] },
                    .bool_ => |data| Value{ .integer = if (data[row_idx]) 1 else 0 },
                    .string => |data| Value{ .string = data[row_idx] },
                };
            },
            .method_call => |mc| try self.evaluateMethodCall(mc, row_idx),
            .call => |call| try self.evaluateScalarFunction(call, row_idx),
            else => error.UnsupportedExpression,
        };
    }

    // ========================================================================
    // Expression Evaluation (for SELECT clause)
    // ========================================================================

    /// Evaluate any expression to a concrete Value for a given row
    /// This handles arithmetic, function calls, and nested expressions
    fn evaluateExprToValue(self: *Self, expr: *const Expr, row_idx: u32) !Value {
        return switch (expr.*) {
            .value => expr.value,
            .column => |col| blk: {
                const cached = self.column_cache.get(col.name) orelse return error.ColumnNotCached;
                break :blk switch (cached) {
                    .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |data| Value{ .integer = data[row_idx] },
                    .int32, .date32 => |data| Value{ .integer = data[row_idx] },
                    .float64 => |data| Value{ .float = data[row_idx] },
                    .float32 => |data| Value{ .float = data[row_idx] },
                    .bool_ => |data| Value{ .integer = if (data[row_idx]) 1 else 0 },
                    .string => |data| Value{ .string = data[row_idx] },
                };
            },
            .binary => |bin| try self.evaluateBinaryToValue(bin, row_idx),
            .unary => |un| try self.evaluateUnaryToValue(un, row_idx),
            .call => |call| try self.evaluateScalarFunction(call, row_idx),
            .method_call => |mc| try self.evaluateMethodCall(mc, row_idx),
            else => error.UnsupportedExpression,
        };
    }

    /// Evaluate a @logic_table method call (e.g., t.risk_score())
    fn evaluateMethodCall(self: *Self, mc: anytype, row_idx: u32) !Value {
        _ = row_idx; // TODO: Support row-wise method calls

        // Get class name from alias
        const class_name = self.logic_table_aliases.get(mc.object) orelse
            return error.TableAliasNotFound;

        // Get dispatcher
        const dispatcher = self.dispatcher orelse
            return error.NoDispatcherConfigured;

        // For now, we only support methods with no runtime arguments
        // The compiled method operates on batch data loaded in the LogicTableContext
        if (mc.args.len > 0) {
            return error.MethodArgsNotSupported;
        }

        // Call the method via dispatcher (0-arg methods for now)
        // TODO: This is placeholder - real impl needs LogicTableContext data binding
        const result = dispatcher.callMethod0(class_name, mc.method) catch |err| {
            return switch (err) {
                error.MethodNotFound => error.MethodNotFound,
                error.ArgumentCountMismatch => error.ArgumentCountMismatch,
                else => error.ExecutionFailed,
            };
        };

        return Value{ .float = result };
    }

    /// Evaluate binary expression to a Value (arithmetic operations)
    fn evaluateBinaryToValue(self: *Self, bin: anytype, row_idx: u32) anyerror!Value {
        const left = try self.evaluateExprToValue(bin.left, row_idx);
        const right = try self.evaluateExprToValue(bin.right, row_idx);

        return switch (bin.op) {
            .add => self.addValues(left, right),
            .subtract => self.subtractValues(left, right),
            .multiply => self.multiplyValues(left, right),
            .divide => self.divideValues(left, right),
            .concat => try self.concatStrings(left, right),
            else => error.UnsupportedOperator,
        };
    }

    /// Evaluate unary expression to a Value
    fn evaluateUnaryToValue(self: *Self, un: anytype, row_idx: u32) anyerror!Value {
        const operand = try self.evaluateExprToValue(un.operand, row_idx);

        return switch (un.op) {
            .minus => self.negateValue(operand),
            .not => blk: {
                // Boolean negation
                const bool_val = switch (operand) {
                    .integer => |i| i != 0,
                    .float => |f| f != 0.0,
                    .null => false,
                    else => true,
                };
                break :blk Value{ .integer = if (bool_val) 0 else 1 };
            },
            else => error.UnsupportedOperator,
        };
    }

    /// Negate a numeric value
    fn negateValue(self: *Self, val: Value) Value {
        _ = self;
        return switch (val) {
            .integer => |i| Value{ .integer = -i },
            .float => |f| Value{ .float = -f },
            else => Value{ .null = {} },
        };
    }

    /// Add two values (int + int = int, int + float = float, float + float = float)
    fn addValues(self: *Self, left: Value, right: Value) Value {
        _ = self;
        return switch (left) {
            .integer => |l| switch (right) {
                .integer => |r| Value{ .integer = l + r },
                .float => |r| Value{ .float = @as(f64, @floatFromInt(l)) + r },
                else => Value{ .null = {} },
            },
            .float => |l| switch (right) {
                .integer => |r| Value{ .float = l + @as(f64, @floatFromInt(r)) },
                .float => |r| Value{ .float = l + r },
                else => Value{ .null = {} },
            },
            else => Value{ .null = {} },
        };
    }

    /// Subtract two values
    fn subtractValues(self: *Self, left: Value, right: Value) Value {
        _ = self;
        return switch (left) {
            .integer => |l| switch (right) {
                .integer => |r| Value{ .integer = l - r },
                .float => |r| Value{ .float = @as(f64, @floatFromInt(l)) - r },
                else => Value{ .null = {} },
            },
            .float => |l| switch (right) {
                .integer => |r| Value{ .float = l - @as(f64, @floatFromInt(r)) },
                .float => |r| Value{ .float = l - r },
                else => Value{ .null = {} },
            },
            else => Value{ .null = {} },
        };
    }

    /// Multiply two values
    fn multiplyValues(self: *Self, left: Value, right: Value) Value {
        _ = self;
        return switch (left) {
            .integer => |l| switch (right) {
                .integer => |r| Value{ .integer = l * r },
                .float => |r| Value{ .float = @as(f64, @floatFromInt(l)) * r },
                else => Value{ .null = {} },
            },
            .float => |l| switch (right) {
                .integer => |r| Value{ .float = l * @as(f64, @floatFromInt(r)) },
                .float => |r| Value{ .float = l * r },
                else => Value{ .null = {} },
            },
            else => Value{ .null = {} },
        };
    }

    /// Divide two values (always returns float for precision)
    fn divideValues(self: *Self, left: Value, right: Value) Value {
        _ = self;
        const left_f = switch (left) {
            .integer => |i| @as(f64, @floatFromInt(i)),
            .float => |f| f,
            else => return Value{ .null = {} },
        };
        const right_f = switch (right) {
            .integer => |i| @as(f64, @floatFromInt(i)),
            .float => |f| f,
            else => return Value{ .null = {} },
        };

        if (right_f == 0) return Value{ .null = {} }; // Division by zero
        return Value{ .float = left_f / right_f };
    }

    /// Concatenate two strings (|| operator)
    fn concatStrings(self: *Self, left: Value, right: Value) !Value {
        const left_str = switch (left) {
            .string => |s| s,
            .integer => |i| blk: {
                var buf: [32]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.FormatError;
                break :blk str;
            },
            .float => |f| blk: {
                var buf: [32]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return error.FormatError;
                break :blk str;
            },
            else => return Value{ .null = {} },
        };

        const right_str = switch (right) {
            .string => |s| s,
            .integer => |i| blk: {
                var buf: [32]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "{d}", .{i}) catch return error.FormatError;
                break :blk str;
            },
            .float => |f| blk: {
                var buf: [32]u8 = undefined;
                const str = std.fmt.bufPrint(&buf, "{d}", .{f}) catch return error.FormatError;
                break :blk str;
            },
            else => return Value{ .null = {} },
        };

        // Allocate new concatenated string
        const result = try self.allocator.alloc(u8, left_str.len + right_str.len);
        @memcpy(result[0..left_str.len], left_str);
        @memcpy(result[left_str.len..], right_str);

        return Value{ .string = result };
    }

    /// Evaluate scalar function call
    fn evaluateScalarFunction(self: *Self, call: anytype, row_idx: u32) anyerror!Value {
        // Skip aggregates - handled elsewhere
        if (isAggregateFunction(call.name)) {
            return error.AggregateInScalarContext;
        }

        // Evaluate all arguments
        var args: [8]Value = undefined;
        const arg_count = @min(call.args.len, 8);
        for (call.args[0..arg_count], 0..) |*arg, i| {
            args[i] = try self.evaluateExprToValue(arg, row_idx);
        }

        // Dispatch by function name (case-insensitive)
        var upper_buf: [32]u8 = undefined;
        const upper_name = std.ascii.upperString(&upper_buf, call.name);

        // String functions
        if (std.mem.eql(u8, upper_name, "UPPER")) {
            return self.funcUpper(args[0]);
        }
        if (std.mem.eql(u8, upper_name, "LOWER")) {
            return self.funcLower(args[0]);
        }
        if (std.mem.eql(u8, upper_name, "LENGTH")) {
            return self.funcLength(args[0]);
        }
        if (std.mem.eql(u8, upper_name, "TRIM")) {
            return self.funcTrim(args[0]);
        }

        // Math functions
        if (std.mem.eql(u8, upper_name, "ABS")) {
            return self.funcAbs(args[0]);
        }
        if (std.mem.eql(u8, upper_name, "ROUND")) {
            const precision: i32 = if (arg_count > 1) switch (args[1]) {
                .integer => |i| @intCast(i),
                else => 0,
            } else 0;
            return self.funcRound(args[0], precision);
        }
        if (std.mem.eql(u8, upper_name, "FLOOR")) {
            return self.funcFloor(args[0]);
        }
        if (std.mem.eql(u8, upper_name, "CEIL") or std.mem.eql(u8, upper_name, "CEILING")) {
            return self.funcCeil(args[0]);
        }

        // Type functions
        if (std.mem.eql(u8, upper_name, "COALESCE")) {
            // Return first non-null value
            for (args[0..arg_count]) |arg| {
                if (arg != .null) return arg;
            }
            return Value{ .null = {} };
        }

        // Date/Time functions
        // EXTRACT(part, timestamp) or DATE_PART(part, timestamp)
        if (std.mem.eql(u8, upper_name, "EXTRACT") or std.mem.eql(u8, upper_name, "DATE_PART")) {
            if (arg_count < 2) return Value{ .null = {} };
            return self.funcExtract(args[0], args[1]);
        }

        // Shorthand date part extractors: YEAR(ts), MONTH(ts), DAY(ts), etc.
        if (std.mem.eql(u8, upper_name, "YEAR")) {
            return self.funcExtractPart(.year, args[0]);
        }
        if (std.mem.eql(u8, upper_name, "MONTH")) {
            return self.funcExtractPart(.month, args[0]);
        }
        if (std.mem.eql(u8, upper_name, "DAY")) {
            return self.funcExtractPart(.day, args[0]);
        }
        if (std.mem.eql(u8, upper_name, "HOUR")) {
            return self.funcExtractPart(.hour, args[0]);
        }
        if (std.mem.eql(u8, upper_name, "MINUTE")) {
            return self.funcExtractPart(.minute, args[0]);
        }
        if (std.mem.eql(u8, upper_name, "SECOND")) {
            return self.funcExtractPart(.second, args[0]);
        }
        if (std.mem.eql(u8, upper_name, "DAYOFWEEK") or std.mem.eql(u8, upper_name, "DOW")) {
            return self.funcExtractPart(.dayofweek, args[0]);
        }
        if (std.mem.eql(u8, upper_name, "DAYOFYEAR") or std.mem.eql(u8, upper_name, "DOY")) {
            return self.funcExtractPart(.dayofyear, args[0]);
        }
        if (std.mem.eql(u8, upper_name, "WEEK")) {
            return self.funcExtractPart(.week, args[0]);
        }
        if (std.mem.eql(u8, upper_name, "QUARTER")) {
            return self.funcExtractPart(.quarter, args[0]);
        }

        // DATE_TRUNC(part, timestamp)
        if (std.mem.eql(u8, upper_name, "DATE_TRUNC")) {
            if (arg_count < 2) return Value{ .null = {} };
            return self.funcDateTrunc(args[0], args[1]);
        }

        // DATE_ADD(timestamp, interval, part) - Add interval to timestamp
        if (std.mem.eql(u8, upper_name, "DATE_ADD") or std.mem.eql(u8, upper_name, "DATEADD")) {
            if (arg_count < 3) return Value{ .null = {} };
            return self.funcDateAdd(args[0], args[1], args[2]);
        }

        // DATE_DIFF(timestamp1, timestamp2, part) - Difference between timestamps
        if (std.mem.eql(u8, upper_name, "DATE_DIFF") or std.mem.eql(u8, upper_name, "DATEDIFF")) {
            if (arg_count < 3) return Value{ .null = {} };
            return self.funcDateDiff(args[0], args[1], args[2]);
        }

        // EPOCH(timestamp) - Convert to Unix epoch seconds
        if (std.mem.eql(u8, upper_name, "EPOCH") or std.mem.eql(u8, upper_name, "UNIX_TIMESTAMP")) {
            return self.funcEpoch(args[0]);
        }

        // FROM_UNIXTIME(epoch_seconds) - Convert Unix epoch to timestamp
        if (std.mem.eql(u8, upper_name, "FROM_UNIXTIME") or std.mem.eql(u8, upper_name, "TO_TIMESTAMP")) {
            return args[0]; // Already an integer, just return as-is
        }

        return error.UnknownFunction;
    }

    // ========================================================================
    // Date/Time Functions
    // ========================================================================

    const DatePart = enum {
        year,
        month,
        day,
        hour,
        minute,
        second,
        millisecond,
        dayofweek,
        dayofyear,
        week,
        quarter,
    };

    /// Parse date part from string
    fn parseDatePart(val: Value) ?DatePart {
        const part_str = switch (val) {
            .string => |s| s,
            else => return null,
        };

        var upper_buf: [16]u8 = undefined;
        const len = @min(part_str.len, upper_buf.len);
        const upper = std.ascii.upperString(upper_buf[0..len], part_str[0..len]);

        if (std.mem.eql(u8, upper, "YEAR") or std.mem.eql(u8, upper, "Y")) return .year;
        if (std.mem.eql(u8, upper, "MONTH") or std.mem.eql(u8, upper, "M")) return .month;
        if (std.mem.eql(u8, upper, "DAY") or std.mem.eql(u8, upper, "D")) return .day;
        if (std.mem.eql(u8, upper, "HOUR") or std.mem.eql(u8, upper, "H")) return .hour;
        if (std.mem.eql(u8, upper, "MINUTE") or std.mem.eql(u8, upper, "MI")) return .minute;
        if (std.mem.eql(u8, upper, "SECOND") or std.mem.eql(u8, upper, "S")) return .second;
        if (std.mem.eql(u8, upper, "MILLISECOND") or std.mem.eql(u8, upper, "MS")) return .millisecond;
        if (std.mem.eql(u8, upper, "DAYOFWEEK") or std.mem.eql(u8, upper, "DOW")) return .dayofweek;
        if (std.mem.eql(u8, upper, "DAYOFYEAR") or std.mem.eql(u8, upper, "DOY")) return .dayofyear;
        if (std.mem.eql(u8, upper, "WEEK") or std.mem.eql(u8, upper, "W")) return .week;
        if (std.mem.eql(u8, upper, "QUARTER") or std.mem.eql(u8, upper, "Q")) return .quarter;

        return null;
    }

    /// Convert timestamp to seconds since epoch
    fn toEpochSeconds(val: Value) ?i64 {
        return switch (val) {
            .integer => |i| i, // Assume already in seconds
            .float => |f| @intFromFloat(f),
            else => null,
        };
    }

    /// EXTRACT(part, timestamp) - Extract date/time component
    fn funcExtract(self: *Self, part_val: Value, ts_val: Value) Value {
        const part = parseDatePart(part_val) orelse return Value{ .null = {} };
        return self.funcExtractPart(part, ts_val);
    }

    /// Extract a specific date part from timestamp
    fn funcExtractPart(self: *Self, part: DatePart, ts_val: Value) Value {
        _ = self;
        const epoch_secs = toEpochSeconds(ts_val) orelse return Value{ .null = {} };

        // Convert epoch seconds to date components
        // Using a simplified algorithm (doesn't handle all edge cases perfectly)
        const secs_per_day: i64 = 86400;
        const secs_per_hour: i64 = 3600;
        const secs_per_min: i64 = 60;

        // Days since epoch (Jan 1, 1970)
        var days = @divFloor(epoch_secs, secs_per_day);
        var remaining = @mod(epoch_secs, secs_per_day);
        if (remaining < 0) {
            remaining += secs_per_day;
            days -= 1;
        }

        const hour = @divFloor(remaining, secs_per_hour);
        remaining = @mod(remaining, secs_per_hour);
        const minute = @divFloor(remaining, secs_per_min);
        const second = @mod(remaining, secs_per_min);

        // Calculate year, month, day from days since epoch
        const date = daysToDate(days);

        return switch (part) {
            .year => Value{ .integer = date.year },
            .month => Value{ .integer = date.month },
            .day => Value{ .integer = date.day },
            .hour => Value{ .integer = hour },
            .minute => Value{ .integer = minute },
            .second => Value{ .integer = second },
            .millisecond => Value{ .integer = 0 }, // Would need ms precision input
            .dayofweek => Value{ .integer = @mod(days + 4, 7) }, // Jan 1, 1970 was Thursday (4)
            .dayofyear => Value{ .integer = date.dayOfYear },
            .week => Value{ .integer = @divFloor(date.dayOfYear - 1, 7) + 1 },
            .quarter => Value{ .integer = @divFloor(date.month - 1, 3) + 1 },
        };
    }

    const DateComponents = struct {
        year: i64,
        month: i64,
        day: i64,
        dayOfYear: i64,
    };

    /// Convert days since epoch to year/month/day
    fn daysToDate(days_since_epoch: i64) DateComponents {
        // Algorithm based on Howard Hinnant's date algorithms
        const z = days_since_epoch + 719468; // Days since Mar 1, 0000
        const era: i64 = if (z >= 0) @divFloor(z, 146097) else @divFloor(z - 146096, 146097);
        const doe: i64 = z - era * 146097; // Day of era [0, 146096]
        const yoe: i64 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
        const y: i64 = yoe + era * 400;
        const doy: i64 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100)); // Day of year [0, 365]
        const mp: i64 = @divFloor(5 * doy + 2, 153);
        const d: i64 = doy - @divFloor(153 * mp + 2, 5) + 1;
        const m: i64 = if (mp < 10) mp + 3 else mp - 9;
        const year = if (m <= 2) y + 1 else y;

        // Calculate day of year for the actual year
        const jan1_days = dateToDays(year, 1, 1);
        const day_of_year = days_since_epoch - jan1_days + 1;

        return .{
            .year = year,
            .month = m,
            .day = d,
            .dayOfYear = day_of_year,
        };
    }

    /// Convert year/month/day to days since epoch
    fn dateToDays(year: i64, month: i64, day: i64) i64 {
        const y = if (month <= 2) year - 1 else year;
        const era: i64 = if (y >= 0) @divFloor(y, 400) else @divFloor(y - 399, 400);
        const yoe: i64 = y - era * 400;
        const m = if (month <= 2) month + 9 else month - 3;
        const doy: i64 = @divFloor(153 * m + 2, 5) + day - 1;
        const doe: i64 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
        return era * 146097 + doe - 719468;
    }

    /// DATE_TRUNC(part, timestamp) - Truncate timestamp to precision
    fn funcDateTrunc(self: *Self, part_val: Value, ts_val: Value) Value {
        _ = self;
        const part = parseDatePart(part_val) orelse return Value{ .null = {} };
        const epoch_secs = toEpochSeconds(ts_val) orelse return Value{ .null = {} };

        const secs_per_day: i64 = 86400;
        const secs_per_hour: i64 = 3600;
        const secs_per_min: i64 = 60;

        const days = @divFloor(epoch_secs, secs_per_day);
        const date = daysToDate(days);

        return switch (part) {
            .year => Value{ .integer = dateToDays(date.year, 1, 1) * secs_per_day },
            .month => Value{ .integer = dateToDays(date.year, date.month, 1) * secs_per_day },
            .day => Value{ .integer = days * secs_per_day },
            .hour => Value{ .integer = @divFloor(epoch_secs, secs_per_hour) * secs_per_hour },
            .minute => Value{ .integer = @divFloor(epoch_secs, secs_per_min) * secs_per_min },
            .second => Value{ .integer = epoch_secs },
            else => Value{ .null = {} },
        };
    }

    /// DATE_ADD(timestamp, interval, part) - Add interval to timestamp
    fn funcDateAdd(self: *Self, ts_val: Value, interval_val: Value, part_val: Value) Value {
        _ = self;
        const part = parseDatePart(part_val) orelse return Value{ .null = {} };
        const epoch_secs = toEpochSeconds(ts_val) orelse return Value{ .null = {} };
        const interval = switch (interval_val) {
            .integer => |i| i,
            .float => |f| @as(i64, @intFromFloat(f)),
            else => return Value{ .null = {} },
        };

        const secs_per_day: i64 = 86400;
        const secs_per_hour: i64 = 3600;
        const secs_per_min: i64 = 60;

        return switch (part) {
            .year => blk: {
                const days = @divFloor(epoch_secs, secs_per_day);
                const time_of_day = @mod(epoch_secs, secs_per_day);
                const date = daysToDate(days);
                const new_days = dateToDays(date.year + interval, date.month, date.day);
                break :blk Value{ .integer = new_days * secs_per_day + time_of_day };
            },
            .month => blk: {
                const days = @divFloor(epoch_secs, secs_per_day);
                const time_of_day = @mod(epoch_secs, secs_per_day);
                const date = daysToDate(days);
                var new_month = date.month + interval;
                var new_year = date.year;
                while (new_month > 12) {
                    new_month -= 12;
                    new_year += 1;
                }
                while (new_month < 1) {
                    new_month += 12;
                    new_year -= 1;
                }
                const new_days = dateToDays(new_year, new_month, date.day);
                break :blk Value{ .integer = new_days * secs_per_day + time_of_day };
            },
            .day => Value{ .integer = epoch_secs + interval * secs_per_day },
            .hour => Value{ .integer = epoch_secs + interval * secs_per_hour },
            .minute => Value{ .integer = epoch_secs + interval * secs_per_min },
            .second => Value{ .integer = epoch_secs + interval },
            else => Value{ .null = {} },
        };
    }

    /// DATE_DIFF(timestamp1, timestamp2, part) - Difference in specified units
    fn funcDateDiff(self: *Self, ts1_val: Value, ts2_val: Value, part_val: Value) Value {
        _ = self;
        const part = parseDatePart(part_val) orelse return Value{ .null = {} };
        const epoch1 = toEpochSeconds(ts1_val) orelse return Value{ .null = {} };
        const epoch2 = toEpochSeconds(ts2_val) orelse return Value{ .null = {} };

        const diff = epoch1 - epoch2;
        const secs_per_day: i64 = 86400;
        const secs_per_hour: i64 = 3600;
        const secs_per_min: i64 = 60;

        return switch (part) {
            .year => blk: {
                const date1 = daysToDate(@divFloor(epoch1, secs_per_day));
                const date2 = daysToDate(@divFloor(epoch2, secs_per_day));
                break :blk Value{ .integer = date1.year - date2.year };
            },
            .month => blk: {
                const date1 = daysToDate(@divFloor(epoch1, secs_per_day));
                const date2 = daysToDate(@divFloor(epoch2, secs_per_day));
                break :blk Value{ .integer = (date1.year - date2.year) * 12 + (date1.month - date2.month) };
            },
            .day => Value{ .integer = @divFloor(diff, secs_per_day) },
            .hour => Value{ .integer = @divFloor(diff, secs_per_hour) },
            .minute => Value{ .integer = @divFloor(diff, secs_per_min) },
            .second => Value{ .integer = diff },
            else => Value{ .null = {} },
        };
    }

    /// EPOCH(timestamp) - Return epoch seconds
    fn funcEpoch(self: *Self, val: Value) Value {
        _ = self;
        return switch (val) {
            .integer => val,
            .float => |f| Value{ .integer = @intFromFloat(f) },
            else => Value{ .null = {} },
        };
    }

    /// UPPER(string) - Convert string to uppercase
    fn funcUpper(self: *Self, val: Value) Value {
        const str = switch (val) {
            .string => |s| s,
            else => return Value{ .null = {} },
        };

        const result = self.allocator.alloc(u8, str.len) catch return Value{ .null = {} };
        for (str, 0..) |c, i| {
            result[i] = std.ascii.toUpper(c);
        }

        return Value{ .string = result };
    }

    /// LOWER(string) - Convert string to lowercase
    fn funcLower(self: *Self, val: Value) Value {
        const str = switch (val) {
            .string => |s| s,
            else => return Value{ .null = {} },
        };

        const result = self.allocator.alloc(u8, str.len) catch return Value{ .null = {} };
        for (str, 0..) |c, i| {
            result[i] = std.ascii.toLower(c);
        }

        return Value{ .string = result };
    }

    /// LENGTH(string) - Return string length
    fn funcLength(self: *Self, val: Value) Value {
        _ = self;
        return switch (val) {
            .string => |s| Value{ .integer = @intCast(s.len) },
            else => Value{ .null = {} },
        };
    }

    /// TRIM(string) - Remove leading/trailing whitespace
    fn funcTrim(self: *Self, val: Value) Value {
        const str = switch (val) {
            .string => |s| s,
            else => return Value{ .null = {} },
        };

        const trimmed = std.mem.trim(u8, str, " \t\n\r");
        const result = self.allocator.dupe(u8, trimmed) catch return Value{ .null = {} };

        return Value{ .string = result };
    }

    /// ABS(number) - Absolute value
    fn funcAbs(self: *Self, val: Value) Value {
        _ = self;
        return switch (val) {
            .integer => |i| Value{ .integer = if (i < 0) -i else i },
            .float => |f| Value{ .float = @abs(f) },
            else => Value{ .null = {} },
        };
    }

    /// ROUND(number, precision) - Round to precision decimal places
    fn funcRound(self: *Self, val: Value, precision: i32) Value {
        _ = self;
        const f = switch (val) {
            .integer => |i| @as(f64, @floatFromInt(i)),
            .float => |f| f,
            else => return Value{ .null = {} },
        };

        const multiplier = std.math.pow(f64, 10.0, @floatFromInt(precision));
        return Value{ .float = @round(f * multiplier) / multiplier };
    }

    /// FLOOR(number) - Round down
    fn funcFloor(self: *Self, val: Value) Value {
        _ = self;
        return switch (val) {
            .integer => val,
            .float => |f| Value{ .float = @floor(f) },
            else => Value{ .null = {} },
        };
    }

    /// CEIL(number) - Round up
    fn funcCeil(self: *Self, val: Value) Value {
        _ = self;
        return switch (val) {
            .integer => val,
            .float => |f| Value{ .float = @ceil(f) },
            else => Value{ .null = {} },
        };
    }

    // ========================================================================
    // Type Inference for Expressions
    // ========================================================================

    /// Result type enum for expression type inference
    const ResultType = enum {
        int64,
        float64,
        string,
    };

    /// Infer the result type of an expression
    fn inferExpressionType(self: *Self, expr: *const Expr) !ResultType {
        return switch (expr.*) {
            .value => |v| switch (v) {
                .integer => .int64,
                .float => .float64,
                .string => .string,
                else => .string,
            },
            .column => |col| blk: {
                const cached = self.column_cache.get(col.name) orelse {
                    // Not cached yet, look up from table
                    const physical_col_id = self.tbl().physicalColumnId(col.name) orelse return error.ColumnNotFound;
                    const field = self.tbl().getFieldById(physical_col_id) orelse return error.InvalidColumn;

                    if (std.mem.indexOf(u8, field.logical_type, "int") != null) {
                        break :blk .int64;
                    } else if (std.mem.indexOf(u8, field.logical_type, "float") != null or
                              std.mem.indexOf(u8, field.logical_type, "double") != null) {
                        break :blk .float64;
                    } else {
                        break :blk .string;
                    }
                };

                break :blk switch (cached) {
                    .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => .int64,
                    .int32, .date32 => .int64, // int32/date32 promoted to int64 for expressions
                    .float64 => .float64,
                    .float32 => .float64, // float32 promoted to float64 for expressions
                    .bool_ => .int64, // bool treated as integer
                    .string => .string,
                };
            },
            .binary => |bin| try self.inferBinaryType(bin),
            .unary => |un| try self.inferExpressionType(un.operand),
            .call => |call| self.inferFunctionReturnType(call.name),
            else => .string,
        };
    }

    /// Infer type of binary expression
    fn inferBinaryType(self: *Self, bin: anytype) anyerror!ResultType {
        // Concat always returns string
        if (bin.op == .concat) return .string;

        const left_type = try self.inferExpressionType(bin.left);
        const right_type = try self.inferExpressionType(bin.right);

        // Division always returns float
        if (bin.op == .divide) return .float64;

        // If either operand is float, result is float
        if (left_type == .float64 or right_type == .float64) return .float64;

        // Both integers -> integer
        if (left_type == .int64 and right_type == .int64) return .int64;

        // Default to float for mixed/unknown types
        return .float64;
    }

    /// Infer return type of a scalar function
    fn inferFunctionReturnType(self: *Self, name: []const u8) ResultType {
        _ = self;
        var upper_buf: [32]u8 = undefined;
        const upper_name = std.ascii.upperString(&upper_buf, name);

        // String functions return string
        if (std.mem.eql(u8, upper_name, "UPPER") or
            std.mem.eql(u8, upper_name, "LOWER") or
            std.mem.eql(u8, upper_name, "TRIM"))
        {
            return .string;
        }

        // LENGTH returns int
        if (std.mem.eql(u8, upper_name, "LENGTH")) {
            return .int64;
        }

        // Date/Time functions return int64
        if (std.mem.eql(u8, upper_name, "YEAR") or
            std.mem.eql(u8, upper_name, "MONTH") or
            std.mem.eql(u8, upper_name, "DAY") or
            std.mem.eql(u8, upper_name, "HOUR") or
            std.mem.eql(u8, upper_name, "MINUTE") or
            std.mem.eql(u8, upper_name, "SECOND") or
            std.mem.eql(u8, upper_name, "DAYOFWEEK") or
            std.mem.eql(u8, upper_name, "DOW") or
            std.mem.eql(u8, upper_name, "DAYOFYEAR") or
            std.mem.eql(u8, upper_name, "DOY") or
            std.mem.eql(u8, upper_name, "WEEK") or
            std.mem.eql(u8, upper_name, "QUARTER") or
            std.mem.eql(u8, upper_name, "EXTRACT") or
            std.mem.eql(u8, upper_name, "DATE_PART") or
            std.mem.eql(u8, upper_name, "DATE_TRUNC") or
            std.mem.eql(u8, upper_name, "DATE_ADD") or
            std.mem.eql(u8, upper_name, "DATEADD") or
            std.mem.eql(u8, upper_name, "DATE_DIFF") or
            std.mem.eql(u8, upper_name, "DATEDIFF") or
            std.mem.eql(u8, upper_name, "EPOCH") or
            std.mem.eql(u8, upper_name, "UNIX_TIMESTAMP") or
            std.mem.eql(u8, upper_name, "FROM_UNIXTIME") or
            std.mem.eql(u8, upper_name, "TO_TIMESTAMP"))
        {
            return .int64;
        }

        // Math functions typically return float (except ABS which preserves type)
        // For simplicity, return float64 for all math functions
        return .float64;
    }

    /// Evaluate an expression column for all filtered indices
    fn evaluateExpressionColumn(
        self: *Self,
        item: ast.SelectItem,
        indices: []const u32,
    ) !Result.Column {
        // First, preload any columns referenced in the expression
        var col_names = std.ArrayList([]const u8){};
        defer col_names.deinit(self.allocator);
        try self.extractExprColumnNames(&item.expr, &col_names);
        try self.preloadColumns(col_names.items);

        // Infer result type
        const result_type = try self.inferExpressionType(&item.expr);

        // Generate column name from expression if no alias
        const col_name = item.alias orelse "expr";

        // Evaluate expression for each row and store results
        switch (result_type) {
            .int64 => {
                const results = try self.allocator.alloc(i64, indices.len);
                errdefer self.allocator.free(results);

                for (indices, 0..) |row_idx, i| {
                    const val = try self.evaluateExprToValue(&item.expr, row_idx);
                    results[i] = switch (val) {
                        .integer => |v| v,
                        .float => |f| @intFromFloat(f),
                        else => 0,
                    };
                }

                return Result.Column{
                    .name = col_name,
                    .data = Result.ColumnData{ .int64 = results },
                };
            },
            .float64 => {
                const results = try self.allocator.alloc(f64, indices.len);
                errdefer self.allocator.free(results);

                for (indices, 0..) |row_idx, i| {
                    const val = try self.evaluateExprToValue(&item.expr, row_idx);
                    results[i] = switch (val) {
                        .integer => |v| @floatFromInt(v),
                        .float => |f| f,
                        else => 0.0,
                    };
                }

                return Result.Column{
                    .name = col_name,
                    .data = Result.ColumnData{ .float64 = results },
                };
            },
            .string => {
                const results = try self.allocator.alloc([]const u8, indices.len);
                errdefer self.allocator.free(results);

                // Check if expression produces owned strings (e.g., concat, UPPER)
                // by checking if it's a binary concat or a function call
                const expr_produces_owned = switch (item.expr) {
                    .binary => |bin| bin.op == .concat,
                    .call => true, // String functions allocate their results
                    else => false,
                };

                for (indices, 0..) |row_idx, i| {
                    const val = try self.evaluateExprToValue(&item.expr, row_idx);
                    results[i] = switch (val) {
                        .string => |s| blk: {
                            if (expr_produces_owned) {
                                // String was already allocated by concat/UPPER/etc.
                                // Use it directly without duping
                                break :blk s;
                            } else {
                                // String is borrowed from cache, must dupe
                                break :blk try self.allocator.dupe(u8, s);
                            }
                        },
                        .integer => |v| blk: {
                            var buf: [32]u8 = undefined;
                            const str = std.fmt.bufPrint(&buf, "{d}", .{v}) catch "";
                            break :blk try self.allocator.dupe(u8, str);
                        },
                        .float => |f| blk: {
                            var buf: [32]u8 = undefined;
                            const str = std.fmt.bufPrint(&buf, "{d}", .{f}) catch "";
                            break :blk try self.allocator.dupe(u8, str);
                        },
                        else => try self.allocator.dupe(u8, ""),
                    };
                }

                return Result.Column{
                    .name = col_name,
                    .data = Result.ColumnData{ .string = results },
                };
            },
        }
    }

    /// Get all row indices (0, 1, 2, ..., n-1)
    fn getAllIndices(self: *Self) ![]u32 {
        // Get row count from first column
        const row_count = try self.tbl().rowCount(0);
        const indices = try self.allocator.alloc(u32, @intCast(row_count));

        for (indices, 0..) |*idx, i| {
            idx.* = @intCast(i);
        }

        return indices;
    }

    // ========================================================================
    // Column Reading
    // ========================================================================

    /// Read columns based on SELECT list and filtered indices
    fn readColumns(
        self: *Self,
        select_list: []const ast.SelectItem,
        indices: []const u32,
    ) ![]Result.Column {
        var columns = std.ArrayList(Result.Column){};
        errdefer {
            for (columns.items) |col| {
                col.data.free(self.allocator);
            }
            columns.deinit(self.allocator);
        }

        for (select_list) |item| {
            // Skip window function expressions - they're handled separately
            if (isWindowFunction(&item.expr)) continue;

            // Handle SELECT *
            if (item.expr == .column and std.mem.eql(u8, item.expr.column.name, "*")) {
                const col_names = try self.tbl().columnNames();
                defer self.allocator.free(col_names);

                for (col_names) |col_name| {
                    // Look up the physical column ID from the name
                    // The physical column ID maps to the column metadata index
                    const physical_col_id = self.tbl().physicalColumnId(col_name) orelse return error.ColumnNotFound;
                    const data = try self.readColumnAtIndices(physical_col_id, indices);

                    try columns.append(self.allocator, Result.Column{
                        .name = col_name,
                        .data = data,
                    });
                }
                break; // SELECT * means we're done
            }

            // Handle regular column
            if (item.expr == .column) {
                const col_name = item.expr.column.name;
                const col_idx = self.tbl().physicalColumnId(col_name) orelse return error.ColumnNotFound;
                const data = try self.readColumnAtIndices(col_idx, indices);

                try columns.append(self.allocator, Result.Column{
                    .name = item.alias orelse col_name,
                    .data = data,
                });
            } else {
                // Handle expressions (arithmetic, functions, etc.)
                const expr_col = try self.evaluateExpressionColumn(item, indices);
                try columns.append(self.allocator, expr_col);
            }
        }

        return columns.toOwnedSlice(self.allocator);
    }

    /// Read column data at specific row indices
    fn readColumnAtIndices(
        self: *Self,
        col_idx: u32,
        indices: []const u32,
    ) !Result.ColumnData {
        const field = self.tbl().getFieldById(col_idx) orelse return error.InvalidColumn;

        // Phase 2: Table API now has readAtIndices() methods
        // Current implementation still uses inline filtering for type-specific handling
        // Future: refactor to use Table.readInt64AtIndices() etc. for cleaner code

        const logical_type = field.logical_type;

        // Precise type detection (order matters - check specific before general)
        // Timestamp types (check before generic "int" matches)
        if (std.mem.indexOf(u8, logical_type, "timestamp[ns") != null) {
            const all_data = try self.tbl().readInt64Column(col_idx);
            defer self.allocator.free(all_data);

            const filtered = try self.allocator.alloc(i64, indices.len);
            for (indices, 0..) |idx, i| {
                filtered[i] = all_data[idx];
            }
            return Result.ColumnData{ .timestamp_ns = filtered };
        } else if (std.mem.indexOf(u8, logical_type, "timestamp[us") != null) {
            const all_data = try self.tbl().readInt64Column(col_idx);
            defer self.allocator.free(all_data);

            const filtered = try self.allocator.alloc(i64, indices.len);
            for (indices, 0..) |idx, i| {
                filtered[i] = all_data[idx];
            }
            return Result.ColumnData{ .timestamp_us = filtered };
        } else if (std.mem.indexOf(u8, logical_type, "timestamp[ms") != null) {
            const all_data = try self.tbl().readInt64Column(col_idx);
            defer self.allocator.free(all_data);

            const filtered = try self.allocator.alloc(i64, indices.len);
            for (indices, 0..) |idx, i| {
                filtered[i] = all_data[idx];
            }
            return Result.ColumnData{ .timestamp_ms = filtered };
        } else if (std.mem.indexOf(u8, logical_type, "timestamp[s") != null) {
            const all_data = try self.tbl().readInt64Column(col_idx);
            defer self.allocator.free(all_data);

            const filtered = try self.allocator.alloc(i64, indices.len);
            for (indices, 0..) |idx, i| {
                filtered[i] = all_data[idx];
            }
            return Result.ColumnData{ .timestamp_s = filtered };
        } else if (std.mem.indexOf(u8, logical_type, "date32") != null) {
            const all_data = try self.tbl().readInt32Column(col_idx);
            defer self.allocator.free(all_data);

            const filtered = try self.allocator.alloc(i32, indices.len);
            for (indices, 0..) |idx, i| {
                filtered[i] = all_data[idx];
            }
            return Result.ColumnData{ .date32 = filtered };
        } else if (std.mem.indexOf(u8, logical_type, "date64") != null) {
            const all_data = try self.tbl().readInt64Column(col_idx);
            defer self.allocator.free(all_data);

            const filtered = try self.allocator.alloc(i64, indices.len);
            for (indices, 0..) |idx, i| {
                filtered[i] = all_data[idx];
            }
            return Result.ColumnData{ .date64 = filtered };
        } else if (std.mem.eql(u8, logical_type, "int32")) {
            const all_data = try self.tbl().readInt32Column(col_idx);
            defer self.allocator.free(all_data);

            const filtered = try self.allocator.alloc(i32, indices.len);
            for (indices, 0..) |idx, i| {
                filtered[i] = all_data[idx];
            }
            return Result.ColumnData{ .int32 = filtered };
        } else if (std.mem.eql(u8, logical_type, "float") or
            std.mem.indexOf(u8, logical_type, "float32") != null) {
            const all_data = try self.tbl().readFloat32Column(col_idx);
            defer self.allocator.free(all_data);

            const filtered = try self.allocator.alloc(f32, indices.len);
            for (indices, 0..) |idx, i| {
                filtered[i] = all_data[idx];
            }
            return Result.ColumnData{ .float32 = filtered };
        } else if (std.mem.eql(u8, logical_type, "bool") or
            std.mem.indexOf(u8, logical_type, "boolean") != null) {
            const all_data = try self.tbl().readBoolColumn(col_idx);
            defer self.allocator.free(all_data);

            const filtered = try self.allocator.alloc(bool, indices.len);
            for (indices, 0..) |idx, i| {
                filtered[i] = all_data[idx];
            }
            return Result.ColumnData{ .bool_ = filtered };
        } else if (std.mem.indexOf(u8, logical_type, "int") != null) {
            // Default integers to int64
            const all_data = try self.tbl().readInt64Column(col_idx);
            defer self.allocator.free(all_data);

            const filtered = try self.allocator.alloc(i64, indices.len);
            for (indices, 0..) |idx, i| {
                filtered[i] = all_data[idx];
            }
            return Result.ColumnData{ .int64 = filtered };
        } else if (std.mem.indexOf(u8, logical_type, "double") != null) {
            const all_data = try self.tbl().readFloat64Column(col_idx);
            defer self.allocator.free(all_data);

            const filtered = try self.allocator.alloc(f64, indices.len);
            for (indices, 0..) |idx, i| {
                filtered[i] = all_data[idx];
            }
            return Result.ColumnData{ .float64 = filtered };
        } else if (std.mem.indexOf(u8, logical_type, "utf8") != null or
            std.mem.indexOf(u8, logical_type, "string") != null) {
            const all_data = try self.tbl().readStringColumn(col_idx);
            // all_data contains owned strings - must free both array and individual strings
            defer {
                for (all_data) |str| {
                    self.allocator.free(str);
                }
                self.allocator.free(all_data);
            }

            const filtered = try self.allocator.alloc([]const u8, indices.len);
            for (indices, 0..) |idx, i| {
                // Duplicate string for the filtered result
                filtered[i] = try self.allocator.dupe(u8, all_data[idx]);
            }
            return Result.ColumnData{ .string = filtered };
        } else {
            return error.UnsupportedColumnType;
        }
    }

    // ========================================================================
    // DISTINCT Implementation
    // ========================================================================

    /// Apply DISTINCT - remove duplicate rows from result columns
    fn applyDistinct(self: *Self, columns: []Result.Column) !struct {
        columns: []Result.Column,
        row_count: usize,
    } {
        if (columns.len == 0) {
            return .{ .columns = columns, .row_count = 0 };
        }

        const total_rows = columns[0].data.len();
        if (total_rows == 0) {
            return .{ .columns = columns, .row_count = 0 };
        }

        // Track unique row keys using StringHashMap
        var seen = std.StringHashMap(void).init(self.allocator);
        defer {
            // Free all keys stored in the map
            var key_iter = seen.keyIterator();
            while (key_iter.next()) |key| {
                self.allocator.free(key.*);
            }
            seen.deinit();
        }

        // Track which row indices to keep
        var keep_indices = std.ArrayList(usize){};
        defer keep_indices.deinit(self.allocator);

        // Build row keys and identify unique rows
        for (0..total_rows) |row_idx| {
            const row_key = try self.buildDistinctRowKey(columns, row_idx);

            if (!seen.contains(row_key)) {
                // Store owned copy of key in map
                try seen.put(row_key, {});
                try keep_indices.append(self.allocator, row_idx);
            } else {
                // Key already exists, free the duplicate
                self.allocator.free(row_key);
            }
        }

        // If all rows are unique, return original columns
        if (keep_indices.items.len == total_rows) {
            return .{ .columns = columns, .row_count = total_rows };
        }

        // Build new columns with only unique rows
        const unique_count = keep_indices.items.len;
        const new_columns = try self.allocator.alloc(Result.Column, columns.len);
        errdefer self.allocator.free(new_columns);

        for (columns, 0..) |col, col_idx| {
            new_columns[col_idx] = try self.filterColumnByIndices(col, keep_indices.items);
        }

        // Free original column data
        for (columns) |col| {
            col.data.free(self.allocator);
        }
        self.allocator.free(columns);

        return .{ .columns = new_columns, .row_count = unique_count };
    }

    /// Build a unique key string for a row across all columns (for DISTINCT)
    fn buildDistinctRowKey(self: *Self, columns: []const Result.Column, row_idx: usize) ![]u8 {
        var key = std.ArrayList(u8){};
        errdefer key.deinit(self.allocator);

        for (columns) |col| {
            try key.append(self.allocator, '|'); // Column separator
            switch (col.data) {
                .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |vals| {
                    var buf: [64]u8 = undefined;
                    const str = std.fmt.bufPrint(&buf, "{d}", .{vals[row_idx]}) catch |err| return err;
                    try key.appendSlice(self.allocator, str);
                },
                .int32, .date32 => |vals| {
                    var buf: [32]u8 = undefined;
                    const str = std.fmt.bufPrint(&buf, "{d}", .{vals[row_idx]}) catch |err| return err;
                    try key.appendSlice(self.allocator, str);
                },
                .float64 => |vals| {
                    var buf: [64]u8 = undefined;
                    const str = std.fmt.bufPrint(&buf, "{d}", .{vals[row_idx]}) catch |err| return err;
                    try key.appendSlice(self.allocator, str);
                },
                .float32 => |vals| {
                    var buf: [32]u8 = undefined;
                    const str = std.fmt.bufPrint(&buf, "{d}", .{vals[row_idx]}) catch |err| return err;
                    try key.appendSlice(self.allocator, str);
                },
                .bool_ => |vals| {
                    try key.appendSlice(self.allocator, if (vals[row_idx]) "true" else "false");
                },
                .string => |vals| {
                    try key.appendSlice(self.allocator, vals[row_idx]);
                },
            }
        }

        return key.toOwnedSlice(self.allocator);
    }

    /// Filter a column to keep only specified row indices
    fn filterColumnByIndices(self: *Self, col: Result.Column, indices: []const usize) !Result.Column {
        const count = indices.len;

        return Result.Column{
            .name = col.name,
            .data = switch (col.data) {
                .string => |vals| blk: {
                    const new_vals = try self.allocator.alloc([]const u8, count);
                    for (indices, 0..) |idx, i| {
                        new_vals[i] = try self.allocator.dupe(u8, vals[idx]);
                    }
                    break :blk Result.ColumnData{ .string = new_vals };
                },
                inline else => |vals, tag| blk: {
                    const new_vals = try self.allocator.alloc(@TypeOf(vals[0]), count);
                    for (indices, 0..) |idx, i| {
                        new_vals[i] = vals[idx];
                    }
                    break :blk @unionInit(Result.ColumnData, @tagName(tag), new_vals);
                },
            },
        };
    }

    // ========================================================================
    // ORDER BY Implementation
    // ========================================================================

    fn applyOrderBy(
        self: *Self,
        columns: []Result.Column,
        order_by: []const ast.OrderBy,
    ) !void {
        if (columns.len == 0) return;

        const row_count = columns[0].data.len();
        if (row_count == 0) return;

        // Create array of indices [0, 1, 2, ..., n-1]
        const indices = try self.allocator.alloc(usize, row_count);
        defer self.allocator.free(indices);

        for (indices, 0..) |*idx, i| {
            idx.* = i;
        }

        // Sort indices based on order_by columns
        for (order_by) |order| {
            const sort_col_idx = self.findColumnIndex(columns, order.column) orelse continue;
            const sort_col = &columns[sort_col_idx];

            // Sort using comparison function
            const context = SortContext{
                .column = sort_col,
                .direction = order.direction,
            };

            std.mem.sort(usize, indices, context, sortCompare);
        }

        // Reorder all columns based on sorted indices
        for (columns) |*col| {
            try self.reorderColumn(col, indices);
        }
    }

    const SortContext = struct {
        column: *const Result.Column,
        direction: ast.OrderDirection,
    };

    fn sortCompare(context: SortContext, a_idx: usize, b_idx: usize) bool {
        const ascending = context.direction == .asc;

        const cmp = switch (context.column.data) {
            .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |data| blk: {
                const a = data[a_idx];
                const b = data[b_idx];
                if (a < b) break :blk std.math.Order.lt;
                if (a > b) break :blk std.math.Order.gt;
                break :blk std.math.Order.eq;
            },
            .int32, .date32 => |data| blk: {
                const a = data[a_idx];
                const b = data[b_idx];
                if (a < b) break :blk std.math.Order.lt;
                if (a > b) break :blk std.math.Order.gt;
                break :blk std.math.Order.eq;
            },
            .float64 => |data| blk: {
                const a = data[a_idx];
                const b = data[b_idx];
                if (a < b) break :blk std.math.Order.lt;
                if (a > b) break :blk std.math.Order.gt;
                break :blk std.math.Order.eq;
            },
            .float32 => |data| blk: {
                const a = data[a_idx];
                const b = data[b_idx];
                if (a < b) break :blk std.math.Order.lt;
                if (a > b) break :blk std.math.Order.gt;
                break :blk std.math.Order.eq;
            },
            .bool_ => |data| blk: {
                const a: u8 = if (data[a_idx]) 1 else 0;
                const b: u8 = if (data[b_idx]) 1 else 0;
                if (a < b) break :blk std.math.Order.lt;
                if (a > b) break :blk std.math.Order.gt;
                break :blk std.math.Order.eq;
            },
            .string => |data| std.mem.order(u8, data[a_idx], data[b_idx]),
        };

        return if (ascending)
            cmp == .lt
        else
            cmp == .gt;
    }

    fn findColumnIndex(self: *Self, columns: []const Result.Column, name: []const u8) ?usize {
        _ = self;
        for (columns, 0..) |col, i| {
            if (std.mem.eql(u8, col.name, name)) {
                return i;
            }
        }
        return null;
    }

    fn reorderColumn(self: *Self, col: *Result.Column, indices: []const usize) !void {
        switch (col.data) {
            .string => |data| {
                const reordered = try self.allocator.alloc([]const u8, data.len);
                for (indices, 0..) |idx, i| {
                    reordered[i] = try self.allocator.dupe(u8, data[idx]);
                }
                // Free old strings and array
                for (data) |str| {
                    self.allocator.free(str);
                }
                self.allocator.free(data);
                col.data = Result.ColumnData{ .string = reordered };
            },
            inline else => |data, tag| {
                const reordered = try self.allocator.alloc(@TypeOf(data[0]), data.len);
                for (indices, 0..) |idx, i| {
                    reordered[i] = data[idx];
                }
                self.allocator.free(data);
                col.data = @unionInit(Result.ColumnData, @tagName(tag), reordered);
            },
        }
    }

    // ========================================================================
    // LIMIT/OFFSET Implementation
    // ========================================================================

    fn applyLimitOffset(
        self: *Self,
        columns: []Result.Column,
        limit: ?u32,
        offset: ?u32,
    ) usize {
        if (columns.len == 0) return 0;

        const row_count = columns[0].data.len();
        const start = offset orelse 0;
        if (start >= row_count) {
            // Free all data and return 0
            for (columns) |*col| {
                self.freeColumnData(&col.data);
                col.data = switch (col.data) {
                    .int64 => Result.ColumnData{ .int64 = &[_]i64{} },
                    .timestamp_s => Result.ColumnData{ .timestamp_s = &[_]i64{} },
                    .timestamp_ms => Result.ColumnData{ .timestamp_ms = &[_]i64{} },
                    .timestamp_us => Result.ColumnData{ .timestamp_us = &[_]i64{} },
                    .timestamp_ns => Result.ColumnData{ .timestamp_ns = &[_]i64{} },
                    .date64 => Result.ColumnData{ .date64 = &[_]i64{} },
                    .int32 => Result.ColumnData{ .int32 = &[_]i32{} },
                    .date32 => Result.ColumnData{ .date32 = &[_]i32{} },
                    .float64 => Result.ColumnData{ .float64 = &[_]f64{} },
                    .float32 => Result.ColumnData{ .float32 = &[_]f32{} },
                    .bool_ => Result.ColumnData{ .bool_ = &[_]bool{} },
                    .string => Result.ColumnData{ .string = &[_][]const u8{} },
                };
            }
            return 0;
        }

        const end = if (limit) |l|
            @min(start + l, row_count)
        else
            row_count;

        // Slice each column
        for (columns) |*col| {
            self.sliceColumn(col, start, end) catch {};
        }

        return end - start;
    }

    fn sliceColumn(self: *Self, col: *Result.Column, start: usize, end: usize) !void {
        const new_len = end - start;

        switch (col.data) {
            .string => |data| {
                const sliced = try self.allocator.alloc([]const u8, new_len);
                for (data[start..end], 0..) |str, i| {
                    sliced[i] = try self.allocator.dupe(u8, str);
                }
                // Free old strings
                for (data) |str| {
                    self.allocator.free(str);
                }
                self.allocator.free(data);
                col.data = Result.ColumnData{ .string = sliced };
            },
            inline else => |data, tag| {
                const sliced = try self.allocator.alloc(@TypeOf(data[0]), new_len);
                @memcpy(sliced, data[start..end]);
                self.allocator.free(data);
                col.data = @unionInit(Result.ColumnData, @tagName(tag), sliced);
            },
        }
    }

    fn freeColumnData(self: *Self, data: *Result.ColumnData) void {
        data.free(self.allocator);
    }

    // ========================================================================
    // HAVING Clause Implementation
    // ========================================================================

    /// Apply HAVING filter to result, returning filtered result
    fn applyHaving(
        self: *Self,
        result: *Result,
        having_expr: *const Expr,
        select_items: []const ast.SelectItem,
    ) !void {
        if (result.row_count == 0) return;

        // Collect indices of rows that pass the HAVING filter
        var passing_indices = std.ArrayList(usize){};
        defer passing_indices.deinit(self.allocator);

        for (0..result.row_count) |row_idx| {
            const passes = try self.evaluateHavingExpr(result.columns, select_items, having_expr, row_idx);
            if (passes) {
                try passing_indices.append(self.allocator, row_idx);
            }
        }

        // If all rows pass, nothing to do
        if (passing_indices.items.len == result.row_count) return;

        // Build filtered result columns
        const indices = passing_indices.items;
        var new_columns = try self.allocator.alloc(Result.Column, result.columns.len);
        errdefer self.allocator.free(new_columns);

        for (result.columns, 0..) |col, i| {
            new_columns[i] = try self.filterColumnByIndices(col, indices);
        }

        // Free old column data
        for (result.columns) |col| {
            var data = col.data;
            self.freeColumnData(&data);
        }
        self.allocator.free(result.columns);

        result.columns = new_columns;
        result.row_count = indices.len;
    }

    /// Evaluate HAVING expression for a single result row
    fn evaluateHavingExpr(
        self: *Self,
        columns: []const Result.Column,
        select_items: []const ast.SelectItem,
        expr: *const Expr,
        row_idx: usize,
    ) anyerror!bool {
        return switch (expr.*) {
            .value => |val| switch (val) {
                .integer => |i| i != 0,
                .float => |f| f != 0.0,
                .null => false,
                else => true,
            },
            .binary => |bin| try self.evaluateHavingBinaryOp(columns, select_items, bin.op, bin.left, bin.right, row_idx),
            .unary => |un| switch (un.op) {
                .not => !(try self.evaluateHavingExpr(columns, select_items, un.operand, row_idx)),
                else => error.UnsupportedOperator,
            },
            else => error.UnsupportedExpression,
        };
    }

    /// Evaluate binary operation in HAVING context
    fn evaluateHavingBinaryOp(
        self: *Self,
        columns: []const Result.Column,
        select_items: []const ast.SelectItem,
        op: BinaryOp,
        left: *const Expr,
        right: *const Expr,
        row_idx: usize,
    ) anyerror!bool {
        return switch (op) {
            .@"and" => (try self.evaluateHavingExpr(columns, select_items, left, row_idx)) and
                (try self.evaluateHavingExpr(columns, select_items, right, row_idx)),
            .@"or" => (try self.evaluateHavingExpr(columns, select_items, left, row_idx)) or
                (try self.evaluateHavingExpr(columns, select_items, right, row_idx)),
            .eq, .ne, .lt, .le, .gt, .ge => try self.evaluateHavingComparison(columns, select_items, op, left, right, row_idx),
            else => error.UnsupportedOperator,
        };
    }

    /// Evaluate comparison in HAVING context
    fn evaluateHavingComparison(
        self: *Self,
        columns: []const Result.Column,
        select_items: []const ast.SelectItem,
        op: BinaryOp,
        left: *const Expr,
        right: *const Expr,
        row_idx: usize,
    ) !bool {
        const left_val = try self.getHavingValue(columns, select_items, left, row_idx);
        const right_val = try self.getHavingValue(columns, select_items, right, row_idx);

        // Compare as floats for numeric comparison
        return switch (left_val) {
            .integer => |left_int| blk: {
                const right_num = switch (right_val) {
                    .integer => |i| @as(f64, @floatFromInt(i)),
                    .float => |f| f,
                    else => return error.TypeMismatch,
                };
                const left_num = @as(f64, @floatFromInt(left_int));
                break :blk self.compareNumbers(op, left_num, right_num);
            },
            .float => |left_float| blk: {
                const right_num = switch (right_val) {
                    .integer => |i| @as(f64, @floatFromInt(i)),
                    .float => |f| f,
                    else => return error.TypeMismatch,
                };
                break :blk self.compareNumbers(op, left_float, right_num);
            },
            .string => |left_str| blk: {
                const right_str = switch (right_val) {
                    .string => |s| s,
                    else => return error.TypeMismatch,
                };
                break :blk self.compareStrings(op, left_str, right_str);
            },
            .null => op == .ne,
            else => error.UnsupportedType,
        };
    }

    /// Get value of expression in HAVING context (from result columns)
    fn getHavingValue(
        self: *Self,
        columns: []const Result.Column,
        select_items: []const ast.SelectItem,
        expr: *const Expr,
        row_idx: usize,
    ) !Value {
        return switch (expr.*) {
            .value => expr.value,
            .column => |col| blk: {
                // Look up column by name in result columns
                const col_idx = self.findColumnIndex(columns, col.name) orelse
                    return error.ColumnNotFound;
                break :blk self.getResultColumnValue(columns[col_idx], row_idx);
            },
            .call => |call| blk: {
                // For aggregate functions, find matching SELECT item
                if (isAggregateFunction(call.name)) {
                    const col_idx = try self.findAggregateColumnIndex(columns, select_items, call.name, call.args);
                    break :blk self.getResultColumnValue(columns[col_idx], row_idx);
                }
                return error.UnsupportedExpression;
            },
            .binary => |bin| try self.evaluateHavingBinaryToValue(columns, select_items, bin, row_idx),
            else => error.UnsupportedExpression,
        };
    }

    /// Evaluate binary expression to value in HAVING context
    fn evaluateHavingBinaryToValue(
        self: *Self,
        columns: []const Result.Column,
        select_items: []const ast.SelectItem,
        bin: anytype,
        row_idx: usize,
    ) anyerror!Value {
        const left = try self.getHavingValue(columns, select_items, bin.left, row_idx);
        const right = try self.getHavingValue(columns, select_items, bin.right, row_idx);

        return switch (bin.op) {
            .add => self.addValues(left, right),
            .subtract => self.subtractValues(left, right),
            .multiply => self.multiplyValues(left, right),
            .divide => self.divideValues(left, right),
            else => error.UnsupportedOperator,
        };
    }

    /// Get value from a result column at a given row index
    fn getResultColumnValue(self: *Self, col: Result.Column, row_idx: usize) Value {
        _ = self;
        return switch (col.data) {
            .int64, .timestamp_s, .timestamp_ms, .timestamp_us, .timestamp_ns, .date64 => |data| Value{ .integer = data[row_idx] },
            .int32, .date32 => |data| Value{ .integer = data[row_idx] },
            .float64 => |data| Value{ .float = data[row_idx] },
            .float32 => |data| Value{ .float = data[row_idx] },
            .bool_ => |data| Value{ .integer = if (data[row_idx]) 1 else 0 },
            .string => |data| Value{ .string = data[row_idx] },
        };
    }

    /// Find the result column index that matches an aggregate function call
    fn findAggregateColumnIndex(
        self: *Self,
        columns: []const Result.Column,
        select_items: []const ast.SelectItem,
        call_name: []const u8,
        call_args: []const Expr,
    ) !usize {
        _ = self;
        // First, try to find by alias matching the function name
        for (columns, 0..) |col, i| {
            if (std.ascii.eqlIgnoreCase(col.name, call_name)) {
                return i;
            }
        }

        // Match by comparing SELECT item expressions
        for (select_items, 0..) |item, i| {
            if (item.expr == .call) {
                const item_call = item.expr.call;
                // Match function name (case insensitive)
                if (std.ascii.eqlIgnoreCase(item_call.name, call_name)) {
                    // Match arguments
                    if (aggregateArgsMatch(item_call.args, call_args)) {
                        return i;
                    }
                }
            }
        }

        return error.ColumnNotFound;
    }
};

/// Check if two aggregate argument lists match
fn aggregateArgsMatch(a: []const Expr, b: []const Expr) bool {
    if (a.len != b.len) return false;

    for (a, b) |arg_a, arg_b| {
        if (!exprEquals(&arg_a, &arg_b)) return false;
    }

    return true;
}

/// Check if two expressions are equal (for aggregate matching)
fn exprEquals(a: *const Expr, b: *const Expr) bool {
    if (std.meta.activeTag(a.*) != std.meta.activeTag(b.*)) return false;

    return switch (a.*) {
        .column => |col_a| blk: {
            const col_b = b.column;
            break :blk std.mem.eql(u8, col_a.name, col_b.name);
        },
        .value => |val_a| blk: {
            const val_b = b.value;
            if (std.meta.activeTag(val_a) != std.meta.activeTag(val_b)) break :blk false;
            break :blk switch (val_a) {
                .integer => |i| i == val_b.integer,
                .float => |f| f == val_b.float,
                .string => |s| std.mem.eql(u8, s, val_b.string),
                .null => true,
                else => false,
            };
        },
        else => false,
    };
}

// Tests are in tests/test_sql_executor.zig
