//! Query Executor - executes parsed SQL statements against Lance tables.
//!
//! Execution pipeline:
//! 1. Column projection - identify needed columns
//! 2. Scan - read column data
//! 3. Filter - apply WHERE clause
//! 4. Group - GROUP BY aggregation
//! 5. Having - filter groups
//! 6. Sort - ORDER BY
//! 7. Limit - truncate results

const std = @import("std");
const Value = @import("lanceql.value").Value;
const ast = @import("ast.zig");
const SelectStmt = ast.SelectStmt;
const SelectItem = ast.SelectItem;
const OrderBy = ast.OrderBy;
const AggregateType = ast.AggregateType;
const expr_mod = @import("expr.zig");
const Expr = expr_mod.Expr;
const agg_mod = @import("aggregates.zig");
const Aggregate = agg_mod.Aggregate;
const GroupKey = agg_mod.GroupKey;
const GroupKeyContext = agg_mod.GroupKeyContext;

/// Query result set.
pub const ResultSet = struct {
    /// Column names
    columns: [][]const u8,

    /// Row data (array of rows, each row is array of values)
    rows: [][]Value,

    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        for (self.rows) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(self.rows);
        self.allocator.free(self.columns);
    }

    /// Get row count.
    pub fn rowCount(self: Self) usize {
        return self.rows.len;
    }

    /// Get column count.
    pub fn columnCount(self: Self) usize {
        return self.columns.len;
    }

    /// Format as simple table string.
    pub fn format(
        self: Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        // Header
        for (self.columns, 0..) |col, i| {
            if (i > 0) try writer.writeAll(" | ");
            try writer.writeAll(col);
        }
        try writer.writeAll("\n");

        // Separator
        for (self.columns, 0..) |col, i| {
            if (i > 0) try writer.writeAll("-+-");
            for (0..col.len) |_| try writer.writeAll("-");
        }
        try writer.writeAll("\n");

        // Rows
        for (self.rows) |row| {
            for (row, 0..) |val, i| {
                if (i > 0) try writer.writeAll(" | ");
                try val.format("", .{}, writer);
            }
            try writer.writeAll("\n");
        }
    }
};

/// Query executor.
pub const Executor = struct {
    allocator: std.mem.Allocator,
    stmt: SelectStmt,

    /// Column data provider interface.
    /// Users implement this to provide column data from their source.
    pub const DataProvider = struct {
        ptr: *anyopaque,
        vtable: *const VTable,

        pub const VTable = struct {
            /// Get column names.
            getColumnNames: *const fn (ptr: *anyopaque) [][]const u8,

            /// Get row count.
            getRowCount: *const fn (ptr: *anyopaque) usize,

            /// Read column as int64 values.
            readInt64Column: *const fn (ptr: *anyopaque, col_idx: usize) ?[]i64,

            /// Read column as float64 values.
            readFloat64Column: *const fn (ptr: *anyopaque, col_idx: usize) ?[]f64,
        };

        pub fn getColumnNames(self: DataProvider) [][]const u8 {
            return self.vtable.getColumnNames(self.ptr);
        }

        pub fn getRowCount(self: DataProvider) usize {
            return self.vtable.getRowCount(self.ptr);
        }

        pub fn readInt64Column(self: DataProvider, col_idx: usize) ?[]i64 {
            return self.vtable.readInt64Column(self.ptr, col_idx);
        }

        pub fn readFloat64Column(self: DataProvider, col_idx: usize) ?[]f64 {
            return self.vtable.readFloat64Column(self.ptr, col_idx);
        }
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, stmt: SelectStmt) Self {
        return .{
            .allocator = allocator,
            .stmt = stmt,
        };
    }

    /// Execute the query against provided data.
    pub fn execute(self: *Self, provider: DataProvider) !ResultSet {
        const col_names = provider.getColumnNames();
        const row_count = provider.getRowCount();

        // Build column name -> index map
        var col_map = std.StringHashMap(usize).init(self.allocator);
        defer col_map.deinit();
        for (col_names, 0..) |name, i| {
            try col_map.put(name, i);
        }

        // Step 1: Determine which columns we need to read
        var needed_cols = std.AutoHashMap(usize, void).init(self.allocator);
        defer needed_cols.deinit();

        // Columns from SELECT
        for (self.stmt.columns) |item| {
            switch (item) {
                .star => {
                    // Need all columns
                    for (0..col_names.len) |i| {
                        try needed_cols.put(i, {});
                    }
                },
                .expr => |e| {
                    try self.collectNeededColumns(e.expression, &col_map, &needed_cols);
                },
            }
        }

        // Columns from WHERE
        if (self.stmt.where) |where| {
            try self.collectNeededColumns(where, &col_map, &needed_cols);
        }

        // Columns from GROUP BY
        for (self.stmt.group_by) |col| {
            if (col_map.get(col)) |idx| {
                try needed_cols.put(idx, {});
            }
        }

        // Step 2: Read column data into memory
        var columns_data: std.ArrayListUnmanaged([]Value) = .empty;
        defer {
            for (columns_data.items) |col_data| {
                self.allocator.free(col_data);
            }
            columns_data.deinit(self.allocator);
        }

        for (0..col_names.len) |col_idx| {
            if (needed_cols.contains(col_idx)) {
                const values = try self.readColumnValues(provider, col_idx, row_count);
                try columns_data.append(self.allocator, values);
            } else {
                // Empty placeholder
                try columns_data.append(self.allocator, &.{});
            }
        }

        // Step 3: Build rows and apply WHERE filter
        var filtered_rows: std.ArrayListUnmanaged([]Value) = .empty;
        defer filtered_rows.deinit(self.allocator);

        for (0..row_count) |row_idx| {
            // Build row
            var row = try self.allocator.alloc(Value, col_names.len);
            for (0..col_names.len) |col_idx| {
                if (columns_data.items[col_idx].len > 0) {
                    row[col_idx] = columns_data.items[col_idx][row_idx];
                } else {
                    row[col_idx] = Value.nil();
                }
            }

            // Apply WHERE filter
            var include = true;
            if (self.stmt.where) |where| {
                const result = where.eval(row, col_map) catch Value.nil();
                include = result.toBool() orelse false;
            }

            if (include) {
                try filtered_rows.append(self.allocator, row);
            } else {
                self.allocator.free(row);
            }
        }

        // Step 4: Handle GROUP BY or simple projection
        var result_rows: [][]Value = undefined;
        var result_cols: [][]const u8 = undefined;

        if (self.stmt.group_by.len > 0) {
            const grouped = try self.executeGroupBy(filtered_rows.items, &col_map);
            result_rows = grouped.rows;
            result_cols = grouped.cols;
        } else if (self.hasAggregates()) {
            // Aggregate without GROUP BY (whole table is one group)
            const agg_result = try self.executeAggregateAll(filtered_rows.items, &col_map);
            result_rows = agg_result.rows;
            result_cols = agg_result.cols;
        } else {
            // Simple projection
            const projected = try self.executeProjection(filtered_rows.items, &col_map, col_names);
            result_rows = projected.rows;
            result_cols = projected.cols;
        }

        // Free filtered rows if not used directly
        if (self.stmt.group_by.len > 0 or self.hasAggregates()) {
            for (filtered_rows.items) |row| {
                self.allocator.free(row);
            }
        }

        // Step 5: Apply HAVING (already done in executeGroupBy if needed)

        // Step 6: ORDER BY
        if (self.stmt.order_by.len > 0) {
            try self.applyOrderBy(&result_rows, result_cols);
        }

        // Step 7: OFFSET and LIMIT
        var final_rows = result_rows;
        if (self.stmt.offset) |offset| {
            if (offset < final_rows.len) {
                // Free skipped rows
                for (final_rows[0..offset]) |row| {
                    self.allocator.free(row);
                }
                final_rows = final_rows[offset..];
            } else {
                for (final_rows) |row| {
                    self.allocator.free(row);
                }
                final_rows = &.{};
            }
        }

        if (self.stmt.limit) |limit| {
            if (limit < final_rows.len) {
                // Free excess rows
                for (final_rows[limit..]) |row| {
                    self.allocator.free(row);
                }
                final_rows = final_rows[0..limit];
            }
        }

        // Reallocate to owned slice
        const owned_rows = try self.allocator.alloc([]Value, final_rows.len);
        @memcpy(owned_rows, final_rows);

        // Free the original result_rows array (not the row contents, just the outer array)
        // We need to free the original allocation, which might be different from final_rows
        // if OFFSET was applied
        self.allocator.free(result_rows);

        return ResultSet{
            .columns = result_cols,
            .rows = owned_rows,
            .allocator = self.allocator,
        };
    }

    fn collectNeededColumns(
        self: *Self,
        e: *Expr,
        col_map: *std.StringHashMap(usize),
        needed: *std.AutoHashMap(usize, void),
    ) !void {
        _ = self;
        switch (e.*) {
            .column => |name| {
                if (col_map.get(name)) |idx| {
                    try needed.put(idx, {});
                }
            },
            .binary => |b| {
                try @constCast(&Executor{ .allocator = needed.allocator, .stmt = undefined }).collectNeededColumns(b.left, col_map, needed);
                try @constCast(&Executor{ .allocator = needed.allocator, .stmt = undefined }).collectNeededColumns(b.right, col_map, needed);
            },
            .unary => |u| {
                try @constCast(&Executor{ .allocator = needed.allocator, .stmt = undefined }).collectNeededColumns(u.operand, col_map, needed);
            },
            .call => |c| {
                for (c.args) |*arg| {
                    try @constCast(&Executor{ .allocator = needed.allocator, .stmt = undefined }).collectNeededColumns(@constCast(arg), col_map, needed);
                }
            },
            .literal, .star => {},
        }
    }

    fn readColumnValues(self: *Self, provider: DataProvider, col_idx: usize, row_count: usize) ![]Value {
        var values = try self.allocator.alloc(Value, row_count);

        // Try int64 first
        if (provider.readInt64Column(col_idx)) |int_data| {
            for (int_data, 0..) |v, i| {
                values[i] = Value.int(v);
            }
            return values;
        }

        // Try float64
        if (provider.readFloat64Column(col_idx)) |float_data| {
            for (float_data, 0..) |v, i| {
                values[i] = Value.float(v);
            }
            return values;
        }

        // No data available
        for (0..row_count) |i| {
            values[i] = Value.nil();
        }
        return values;
    }

    fn hasAggregates(self: *Self) bool {
        for (self.stmt.columns) |item| {
            switch (item) {
                .expr => |e| {
                    if (e.expression.isAggregate()) return true;
                },
                .star => {},
            }
        }
        return false;
    }

    fn executeProjection(
        self: *Self,
        rows: [][]Value,
        col_map: *std.StringHashMap(usize),
        col_names: [][]const u8,
    ) !struct { rows: [][]Value, cols: [][]const u8 } {
        var result_cols: std.ArrayListUnmanaged([]const u8) = .empty;
        var result_rows: std.ArrayListUnmanaged([]Value) = .empty;

        // Determine output columns
        for (self.stmt.columns) |item| {
            switch (item) {
                .star => {
                    for (col_names) |name| {
                        try result_cols.append(self.allocator, name);
                    }
                },
                .expr => |e| {
                    const name = e.alias orelse switch (e.expression.*) {
                        .column => |n| n,
                        else => "?",
                    };
                    try result_cols.append(self.allocator, name);
                },
            }
        }

        // Project each row
        for (rows) |row| {
            var new_row = try self.allocator.alloc(Value, result_cols.items.len);
            var col_idx: usize = 0;

            for (self.stmt.columns) |item| {
                switch (item) {
                    .star => {
                        for (row) |val| {
                            new_row[col_idx] = val;
                            col_idx += 1;
                        }
                    },
                    .expr => |e| {
                        new_row[col_idx] = e.expression.eval(row, col_map.*) catch Value.nil();
                        col_idx += 1;
                    },
                }
            }

            try result_rows.append(self.allocator, new_row);
        }

        return .{
            .rows = try result_rows.toOwnedSlice(self.allocator),
            .cols = try result_cols.toOwnedSlice(self.allocator),
        };
    }

    fn executeAggregateAll(
        self: *Self,
        rows: [][]Value,
        col_map: *std.StringHashMap(usize),
    ) !struct { rows: [][]Value, cols: [][]const u8 } {
        var result_cols: std.ArrayListUnmanaged([]const u8) = .empty;
        var aggs: std.ArrayListUnmanaged(Aggregate) = .empty;
        defer aggs.deinit(self.allocator);

        // Initialize aggregates for each SELECT item
        for (self.stmt.columns) |item| {
            switch (item) {
                .star => {
                    // COUNT(*) as default
                    try result_cols.append(self.allocator, "count");
                    try aggs.append(self.allocator, Aggregate.init(.count, false));
                },
                .expr => |e| {
                    const name = e.alias orelse "?";
                    try result_cols.append(self.allocator, name);

                    switch (e.expression.*) {
                        .call => |c| {
                            const agg_type = AggregateType.fromStr(c.name) orelse .count;
                            try aggs.append(self.allocator, Aggregate.init(agg_type, c.distinct));
                        },
                        else => {
                            // Non-aggregate in aggregate query - use first value
                            try aggs.append(self.allocator, Aggregate.init(.min, false));
                        },
                    }
                },
            }
        }

        // Process all rows
        for (rows) |row| {
            for (self.stmt.columns, 0..) |item, i| {
                switch (item) {
                    .star => {
                        aggs.items[i].addRow();
                    },
                    .expr => |e| {
                        switch (e.expression.*) {
                            .call => |c| {
                                if (c.args.len > 0) {
                                    const arg = &c.args[0];
                                    if (arg.* == .star) {
                                        aggs.items[i].addRow();
                                    } else {
                                        const val = arg.eval(row, col_map.*) catch Value.nil();
                                        aggs.items[i].add(val);
                                    }
                                } else {
                                    aggs.items[i].addRow();
                                }
                            },
                            else => {
                                const val = e.expression.eval(row, col_map.*) catch Value.nil();
                                aggs.items[i].add(val);
                            },
                        }
                    },
                }
            }
        }

        // Build result row
        var result_row = try self.allocator.alloc(Value, aggs.items.len);
        for (aggs.items, 0..) |agg, i| {
            result_row[i] = agg.result();
        }

        var result_rows = try self.allocator.alloc([]Value, 1);
        result_rows[0] = result_row;

        return .{
            .rows = result_rows,
            .cols = try result_cols.toOwnedSlice(self.allocator),
        };
    }

    fn executeGroupBy(
        self: *Self,
        rows: [][]Value,
        col_map: *std.StringHashMap(usize),
    ) !struct { rows: [][]Value, cols: [][]const u8 } {
        if (rows.len == 0) {
            return .{
                .rows = try self.allocator.alloc([]Value, 0),
                .cols = try self.allocator.alloc([]const u8, 0),
            };
        }

        // Step 1: Get indices for GROUP BY columns
        var group_col_indices = try self.allocator.alloc(usize, self.stmt.group_by.len);
        defer self.allocator.free(group_col_indices);

        for (self.stmt.group_by, 0..) |col_name, i| {
            group_col_indices[i] = col_map.get(col_name) orelse return error.ColumnNotFound;
        }

        // Step 2: Determine output columns and aggregate info
        var result_cols: std.ArrayListUnmanaged([]const u8) = .empty;
        var agg_infos: std.ArrayListUnmanaged(AggInfo) = .empty;
        defer agg_infos.deinit(self.allocator);

        for (self.stmt.columns) |item| {
            switch (item) {
                .star => {
                    // For GROUP BY with *, just include group columns
                    for (self.stmt.group_by) |col_name| {
                        try result_cols.append(self.allocator, col_name);
                        try agg_infos.append(self.allocator, .{ .is_group_col = true, .group_col_name = col_name, .agg_type = null, .agg_arg = null, .distinct = false });
                    }
                },
                .expr => |e| {
                    const name = e.alias orelse switch (e.expression.*) {
                        .column => |n| n,
                        .call => |c| c.name,
                        else => "?",
                    };
                    try result_cols.append(self.allocator, name);

                    // Determine if this is a group column or aggregate
                    switch (e.expression.*) {
                        .column => |col_name| {
                            // Check if it's a GROUP BY column
                            var is_group = false;
                            for (self.stmt.group_by) |gb| {
                                if (std.mem.eql(u8, gb, col_name)) {
                                    is_group = true;
                                    break;
                                }
                            }
                            try agg_infos.append(self.allocator, .{
                                .is_group_col = is_group,
                                .group_col_name = if (is_group) col_name else null,
                                .agg_type = if (!is_group) AggregateType.min else null, // Use min for non-group columns
                                .agg_arg = if (!is_group) e.expression else null,
                                .distinct = false,
                            });
                        },
                        .call => |c| {
                            const agg_type = AggregateType.fromStr(c.name) orelse .count;
                            const arg: ?*Expr = if (c.args.len > 0) @constCast(&c.args[0]) else null;
                            try agg_infos.append(self.allocator, .{
                                .is_group_col = false,
                                .group_col_name = null,
                                .agg_type = agg_type,
                                .agg_arg = arg,
                                .distinct = c.distinct,
                            });
                        },
                        else => {
                            // Expression - evaluate and use first value
                            try agg_infos.append(self.allocator, .{
                                .is_group_col = false,
                                .group_col_name = null,
                                .agg_type = .min,
                                .agg_arg = e.expression,
                                .distinct = false,
                            });
                        },
                    }
                },
            }
        }

        // Step 3: Group rows using HashMap
        const GroupData = struct {
            key_values: []Value,
            aggregates: []Aggregate,
        };

        var groups = std.HashMap(GroupKey, GroupData, GroupKeyContext, 80).init(self.allocator);
        defer {
            var iter = groups.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.values);
                self.allocator.free(entry.value_ptr.aggregates);
            }
            groups.deinit();
        }

        // Process each row
        for (rows) |row| {
            // Build group key from GROUP BY column values
            var key_values = try self.allocator.alloc(Value, group_col_indices.len);
            for (group_col_indices, 0..) |col_idx, i| {
                key_values[i] = row[col_idx];
            }
            const key = GroupKey{ .values = key_values };

            // Get or create group
            const gop = try groups.getOrPut(key);
            if (!gop.found_existing) {
                // Initialize aggregates for this group
                var aggs = try self.allocator.alloc(Aggregate, agg_infos.items.len);
                for (agg_infos.items, 0..) |info, i| {
                    if (info.agg_type) |agg_type| {
                        aggs[i] = Aggregate.init(agg_type, info.distinct);
                    } else {
                        aggs[i] = Aggregate.init(.count, false); // Placeholder for group columns
                    }
                }
                gop.value_ptr.* = .{
                    .key_values = key_values,
                    .aggregates = aggs,
                };
            } else {
                // Key already exists, free the duplicate key values
                self.allocator.free(key_values);
            }

            // Update aggregates for this row
            for (agg_infos.items, 0..) |info, i| {
                if (info.is_group_col) continue; // Group columns don't need aggregation

                if (info.agg_arg) |arg| {
                    if (arg.* == .star) {
                        gop.value_ptr.aggregates[i].addRow();
                    } else {
                        const val = arg.eval(row, col_map.*) catch Value.nil();
                        gop.value_ptr.aggregates[i].add(val);
                    }
                } else {
                    gop.value_ptr.aggregates[i].addRow();
                }
            }
        }

        // Step 4: Build result rows from groups
        var result_rows: std.ArrayListUnmanaged([]Value) = .empty;
        defer result_rows.deinit(self.allocator);

        var group_iter = groups.iterator();
        while (group_iter.next()) |entry| {
            const group_data = entry.value_ptr.*;

            var result_row = try self.allocator.alloc(Value, agg_infos.items.len);
            for (agg_infos.items, 0..) |info, i| {
                if (info.is_group_col) {
                    // Find the value from group key
                    for (self.stmt.group_by, 0..) |gb, gi| {
                        if (info.group_col_name != null and std.mem.eql(u8, gb, info.group_col_name.?)) {
                            result_row[i] = group_data.key_values[gi];
                            break;
                        }
                    }
                } else {
                    result_row[i] = group_data.aggregates[i].result();
                }
            }

            // Apply HAVING filter if present
            if (self.stmt.having) |having_expr| {
                const having_result = try self.evaluateHavingExpr(having_expr, result_row, result_cols.items);
                if (!having_result) {
                    self.allocator.free(result_row);
                    continue;
                }
            }

            try result_rows.append(self.allocator, result_row);
        }

        return .{
            .rows = try result_rows.toOwnedSlice(self.allocator),
            .cols = try result_cols.toOwnedSlice(self.allocator),
        };
    }

    const AggInfo = struct {
        is_group_col: bool,
        group_col_name: ?[]const u8,
        agg_type: ?AggregateType,
        agg_arg: ?*Expr,
        distinct: bool,
    };

    fn evaluateHavingExpr(self: *Self, expr: *const Expr, row: []Value, col_names: [][]const u8) !bool {
        // Build a column map for the result columns
        var result_col_map = std.StringHashMap(usize).init(self.allocator);
        defer result_col_map.deinit();

        for (col_names, 0..) |name, i| {
            try result_col_map.put(name, i);
        }

        const result = expr.eval(row, result_col_map) catch return true;
        return result.toBool() orelse false;
    }

    fn applyOrderBy(self: *Self, rows: *[][]Value, col_names: [][]const u8) !void {
        if (self.stmt.order_by.len == 0) return;

        // Find column indices for ORDER BY
        var order_indices = try self.allocator.alloc(usize, self.stmt.order_by.len);
        defer self.allocator.free(order_indices);

        for (self.stmt.order_by, 0..) |ob, i| {
            for (col_names, 0..) |name, idx| {
                if (std.mem.eql(u8, name, ob.column)) {
                    order_indices[i] = idx;
                    break;
                }
            }
        }

        const order_by = self.stmt.order_by;

        // Sort rows
        const SortContext = struct {
            order_indices: []usize,
            order_by: []OrderBy,

            pub fn lessThan(ctx: @This(), a: []Value, b: []Value) bool {
                for (ctx.order_indices, ctx.order_by) |idx, ob| {
                    const cmp = Value.compare(a[idx], b[idx]) orelse continue;
                    if (cmp == .eq) continue;

                    if (ob.descending) {
                        return cmp == .gt;
                    } else {
                        return cmp == .lt;
                    }
                }
                return false;
            }
        };
        const sort_ctx = SortContext{ .order_indices = order_indices, .order_by = order_by };
        std.mem.sort([]Value, rows.*, sort_ctx, SortContext.lessThan);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ResultSet format" {
    var result = ResultSet{
        .columns = @constCast(&[_][]const u8{ "id", "name" }),
        .rows = @constCast(&[_][]Value{
            @constCast(&[_]Value{ Value.int(1), Value.str("Alice") }),
            @constCast(&[_]Value{ Value.int(2), Value.str("Bob") }),
        }),
        .allocator = std.testing.allocator,
    };

    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try result.format("", .{}, stream.writer());

    const output = stream.getWritten();
    try std.testing.expect(std.mem.indexOf(u8, output, "id") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Alice") != null);
}

// Mock data provider for testing
const MockProvider = struct {
    col_names: [][]const u8,
    int_data: [][]i64,
    row_count: usize,

    const Self = @This();

    fn getColumnNames(ptr: *anyopaque) [][]const u8 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.col_names;
    }

    fn getRowCount(ptr: *anyopaque) usize {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.row_count;
    }

    fn readInt64Column(ptr: *anyopaque, col_idx: usize) ?[]i64 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (col_idx < self.int_data.len) {
            return self.int_data[col_idx];
        }
        return null;
    }

    fn readFloat64Column(_: *anyopaque, _: usize) ?[]f64 {
        return null;
    }

    fn toProvider(self: *Self) Executor.DataProvider {
        return .{
            .ptr = self,
            .vtable = &.{
                .getColumnNames = getColumnNames,
                .getRowCount = getRowCount,
                .readInt64Column = readInt64Column,
                .readFloat64Column = readFloat64Column,
            },
        };
    }
};

test "GROUP BY basic" {
    const allocator = std.testing.allocator;

    // Test data: category (0=A, 1=B), value
    // A: 10, 20, A: 30 -> sum(A) = 60
    // B: 15, 25 -> sum(B) = 40
    var col_names = [_][]const u8{ "category", "value" };
    var cat_data = [_]i64{ 0, 0, 0, 1, 1 }; // A, A, A, B, B
    var val_data = [_]i64{ 10, 20, 30, 15, 25 };
    var int_data = [_][]i64{ &cat_data, &val_data };

    var mock = MockProvider{
        .col_names = &col_names,
        .int_data = &int_data,
        .row_count = 5,
    };

    // Create SELECT category, SUM(value) FROM t GROUP BY category
    const sum_arg = Expr{ .column = "value" };
    var sum_call = Expr{ .call = .{ .name = "SUM", .args = @constCast(&[_]Expr{sum_arg}), .distinct = false } };
    var cat_expr = Expr{ .column = "category" };

    const stmt = SelectStmt{
        .columns = @constCast(&[_]SelectItem{
            .{ .expr = .{ .expression = &cat_expr, .alias = "category" } },
            .{ .expr = .{ .expression = &sum_call, .alias = "total" } },
        }),
        .from = null,
        .where = null,
        .group_by = @constCast(&[_][]const u8{"category"}),
        .having = null,
        .order_by = &.{},
        .limit = null,
        .offset = null,
        .distinct = false,
    };

    var exec = Executor.init(allocator, stmt);
    var result = try exec.execute(mock.toProvider());
    defer result.deinit();

    // Should have 2 groups
    try std.testing.expectEqual(@as(usize, 2), result.rowCount());
    try std.testing.expectEqual(@as(usize, 2), result.columnCount());

    // Verify column names
    try std.testing.expectEqualStrings("category", result.columns[0]);
    try std.testing.expectEqualStrings("total", result.columns[1]);

    // Check that we have expected sums (order may vary due to HashMap)
    var found_cat_0 = false;
    var found_cat_1 = false;

    for (result.rows) |row| {
        const cat = row[0].int64;
        const total = row[1].int64;

        if (cat == 0) {
            try std.testing.expectEqual(@as(i64, 60), total); // 10 + 20 + 30
            found_cat_0 = true;
        } else if (cat == 1) {
            try std.testing.expectEqual(@as(i64, 40), total); // 15 + 25
            found_cat_1 = true;
        }
    }

    try std.testing.expect(found_cat_0);
    try std.testing.expect(found_cat_1);
}

test "GROUP BY with HAVING" {
    const allocator = std.testing.allocator;

    // Same test data as above
    var col_names = [_][]const u8{ "category", "value" };
    var cat_data = [_]i64{ 0, 0, 0, 1, 1 };
    var val_data = [_]i64{ 10, 20, 30, 15, 25 };
    var int_data = [_][]i64{ &cat_data, &val_data };

    var mock = MockProvider{
        .col_names = &col_names,
        .int_data = &int_data,
        .row_count = 5,
    };

    // SELECT category, SUM(value) AS total FROM t GROUP BY category HAVING total > 50
    const sum_arg = Expr{ .column = "value" };
    var sum_call = Expr{ .call = .{ .name = "SUM", .args = @constCast(&[_]Expr{sum_arg}), .distinct = false } };
    var cat_expr = Expr{ .column = "category" };

    // HAVING: total > 50
    var total_col = Expr{ .column = "total" };
    var fifty = Expr{ .literal = Value.int(50) };
    var having_expr = Expr{ .binary = .{
        .op = .gt,
        .left = &total_col,
        .right = &fifty,
    } };

    const stmt = SelectStmt{
        .columns = @constCast(&[_]SelectItem{
            .{ .expr = .{ .expression = &cat_expr, .alias = "category" } },
            .{ .expr = .{ .expression = &sum_call, .alias = "total" } },
        }),
        .from = null,
        .where = null,
        .group_by = @constCast(&[_][]const u8{"category"}),
        .having = &having_expr,
        .order_by = &.{},
        .limit = null,
        .offset = null,
        .distinct = false,
    };

    var exec = Executor.init(allocator, stmt);
    var result = try exec.execute(mock.toProvider());
    defer result.deinit();

    // Should have 1 group (only category 0 with sum 60 > 50)
    try std.testing.expectEqual(@as(usize, 1), result.rowCount());

    // Verify it's category 0 with sum 60
    try std.testing.expectEqual(@as(i64, 0), result.rows[0][0].int64);
    try std.testing.expectEqual(@as(i64, 60), result.rows[0][1].int64);
}

test "GROUP BY with COUNT" {
    const allocator = std.testing.allocator;

    // Test data: category, value
    // Category 0: 3 rows
    // Category 1: 2 rows
    var col_names = [_][]const u8{ "category", "value" };
    var cat_data = [_]i64{ 0, 0, 0, 1, 1 };
    var val_data = [_]i64{ 10, 20, 30, 15, 25 };
    var int_data = [_][]i64{ &cat_data, &val_data };

    var mock = MockProvider{
        .col_names = &col_names,
        .int_data = &int_data,
        .row_count = 5,
    };

    // SELECT category, COUNT(*) AS cnt FROM t GROUP BY category
    const star_arg = Expr{ .star = {} };
    var count_call = Expr{ .call = .{ .name = "COUNT", .args = @constCast(&[_]Expr{star_arg}), .distinct = false } };
    var cat_expr = Expr{ .column = "category" };

    const stmt = SelectStmt{
        .columns = @constCast(&[_]SelectItem{
            .{ .expr = .{ .expression = &cat_expr, .alias = "category" } },
            .{ .expr = .{ .expression = &count_call, .alias = "cnt" } },
        }),
        .from = null,
        .where = null,
        .group_by = @constCast(&[_][]const u8{"category"}),
        .having = null,
        .order_by = &.{},
        .limit = null,
        .offset = null,
        .distinct = false,
    };

    var exec = Executor.init(allocator, stmt);
    var result = try exec.execute(mock.toProvider());
    defer result.deinit();

    // Should have 2 groups
    try std.testing.expectEqual(@as(usize, 2), result.rowCount());

    // Check counts (order may vary)
    var found_cat_0 = false;
    var found_cat_1 = false;

    for (result.rows) |row| {
        const cat = row[0].int64;
        const cnt = row[1].int64;

        if (cat == 0) {
            try std.testing.expectEqual(@as(i64, 3), cnt); // 3 rows in category 0
            found_cat_0 = true;
        } else if (cat == 1) {
            try std.testing.expectEqual(@as(i64, 2), cnt); // 2 rows in category 1
            found_cat_1 = true;
        }
    }

    try std.testing.expect(found_cat_0);
    try std.testing.expect(found_cat_1);
}

test "GROUP BY with AVG" {
    const allocator = std.testing.allocator;

    // Test data: category, value
    // Category 0: values 10, 20, 30 -> avg = 20
    // Category 1: values 15, 25 -> avg = 20
    var col_names = [_][]const u8{ "category", "value" };
    var cat_data = [_]i64{ 0, 0, 0, 1, 1 };
    var val_data = [_]i64{ 10, 20, 30, 15, 25 };
    var int_data = [_][]i64{ &cat_data, &val_data };

    var mock = MockProvider{
        .col_names = &col_names,
        .int_data = &int_data,
        .row_count = 5,
    };

    // SELECT category, AVG(value) AS avg_val FROM t GROUP BY category
    const avg_arg = Expr{ .column = "value" };
    var avg_call = Expr{ .call = .{ .name = "AVG", .args = @constCast(&[_]Expr{avg_arg}), .distinct = false } };
    var cat_expr = Expr{ .column = "category" };

    const stmt = SelectStmt{
        .columns = @constCast(&[_]SelectItem{
            .{ .expr = .{ .expression = &cat_expr, .alias = "category" } },
            .{ .expr = .{ .expression = &avg_call, .alias = "avg_val" } },
        }),
        .from = null,
        .where = null,
        .group_by = @constCast(&[_][]const u8{"category"}),
        .having = null,
        .order_by = &.{},
        .limit = null,
        .offset = null,
        .distinct = false,
    };

    var exec = Executor.init(allocator, stmt);
    var result = try exec.execute(mock.toProvider());
    defer result.deinit();

    // Should have 2 groups
    try std.testing.expectEqual(@as(usize, 2), result.rowCount());

    // Check averages (order may vary)
    for (result.rows) |row| {
        const cat = row[0].int64;
        const avg_val = row[1].float64;

        if (cat == 0) {
            try std.testing.expectApproxEqAbs(@as(f64, 20.0), avg_val, 0.001); // (10+20+30)/3 = 20
        } else if (cat == 1) {
            try std.testing.expectApproxEqAbs(@as(f64, 20.0), avg_val, 0.001); // (15+25)/2 = 20
        }
    }
}
