# Logic Table Implementation Plan

## Current State

The logic_table feature is partially implemented with these gaps:

### Critical Issues

1. **SQL executor ignores FROM clause** (`src/sql/executor.zig:320`)
   - `execute()` always uses `self.table` (injected at init)
   - `stmt.from` is never processed
   - Cannot use `FROM logic_table('file.py')` or JOINs

2. **Method calls are stubbed** (`src/sql/executor.zig:1367`)
   - `evaluateMethodCall()` ignores `row_idx`
   - Args are rejected (`mc.args.len > 0` returns error)
   - Only 0-arg scalar calls work via `dispatcher.callMethod0()`

### High Priority

3. **LogicTableExecutor.init doesn't parse Python** (`src/logic_table/executor.zig:107`)
   - `class_name` stays empty
   - `table_decls` not populated
   - `methods` not extracted

4. **Window specs only accept identifiers** (`src/sql/ast.zig:173`)
   - Cannot do `t.risk_score() OVER (PARTITION BY customer_id)`
   - Parser doesn't support expressions in PARTITION BY/ORDER BY

## Target Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          SQL Query                               │
│  SELECT t.risk_score(), o.amount                                │
│  FROM logic_table('fraud_detector.py') AS t                     │
│  WHERE t.risk_score() > 0.7                                     │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                      SQL Executor                                │
│  1. Parse FROM clause → detect logic_table() call               │
│  2. Create LogicTableExecutor from Python file                  │
│  3. Load referenced Lance tables                                 │
│  4. Bind columns to LogicTableContext                           │
│  5. Execute query with batch method dispatch                    │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                  LogicTableExecutor                              │
│  ┌──────────────────┐  ┌──────────────────┐                     │
│  │  Python Parser   │  │  Table Loader    │                     │
│  │  - class_name    │  │  - orders.lance  │                     │
│  │  - table_decls   │  │  - customers...  │                     │
│  │  - methods       │  │                  │                     │
│  └────────┬─────────┘  └────────┬─────────┘                     │
│           │                     │                                │
│           ▼                     ▼                                │
│  ┌──────────────────────────────────────────┐                   │
│  │           LogicTableContext              │                   │
│  │  - column_bindings: { "amount" → []f64 } │                   │
│  │  - row_count: 100_000                    │                   │
│  └────────────────────┬─────────────────────┘                   │
└───────────────────────┼─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Batch Method Dispatch                         │
│                                                                  │
│  fn risk_score(                                                 │
│      inputs: []const ColumnBinding,   // amount, velocity, etc  │
│      selection: ?[]const u32,         // filtered row indices   │
│      output: *ColumnBuffer,           // pre-allocated output   │
│      ctx: *QueryContext,              // window state, etc      │
│  ) !void                                                        │
└─────────────────────────────────────────────────────────────────┘
```

## Implementation Steps

### Phase 1: Wire FROM clause (Critical)

**File: `src/sql/executor.zig`**

1. Add `TableSource` union to track active data source:
```zig
const TableSource = union(enum) {
    /// Direct table (existing behavior)
    direct: *Table,
    /// Logic table with loaded data
    logic_table: struct {
        executor: *LogicTableExecutor,
        primary_table: *Table,  // First table from declarations
    },
};
```

2. Modify `execute()` to process FROM before query:
```zig
pub fn execute(self: *Self, stmt: *const SelectStmt, params: []const Value) !Result {
    // NEW: Process FROM clause to get table source
    const source = try self.resolveTableSource(&stmt.from);
    defer self.releaseTableSource(source);

    // Use source.getTable() instead of self.table
    ...
}
```

3. Add `resolveTableSource()` helper:
```zig
fn resolveTableSource(self: *Self, from: *const ast.TableRef) !TableSource {
    switch (from.*) {
        .simple => return .{ .direct = self.table },
        .function => |func| {
            if (std.mem.eql(u8, func.func.name, "logic_table")) {
                // Extract file path from first arg
                const path = try self.extractStringArg(func.func.args[0]);

                // Create LogicTableExecutor
                var executor = try LogicTableExecutor.init(self.allocator, path);
                try executor.loadTables();

                // Register alias for method dispatch
                if (func.alias) |alias| {
                    try self.registerLogicTableAlias(alias, executor.class_name);
                }

                return .{ .logic_table = .{
                    .executor = executor,
                    .primary_table = executor.getPrimaryTable(),
                }};
            }
            return error.UnsupportedTableFunction;
        },
        .join => return error.JoinsNotYetSupported,
    }
}
```

### Phase 2: Batch Method Dispatch ABI

**File: `src/sql/logic_table_dispatch.zig`**

1. Define batch ABI types:
```zig
/// Column binding for batch method input
pub const ColumnBinding = struct {
    name: []const u8,
    data: ColumnData,

    pub const ColumnData = union(enum) {
        f64: []const f64,
        i64: []const i64,
        bool_: []const bool,
        string: []const []const u8,
    };
};

/// Output buffer for batch method results
pub const ColumnBuffer = struct {
    f64: ?[]f64,
    i64: ?[]i64,
    bool_: ?[]bool,

    pub fn initFloat(allocator: Allocator, len: usize) !ColumnBuffer {
        return .{ .f64 = try allocator.alloc(f64, len), .i64 = null, .bool_ = null };
    }
};

/// Batch method function signature
pub const BatchMethodFn = *const fn (
    inputs: []const ColumnBinding,
    selection: ?[]const u32,
    output: *ColumnBuffer,
    ctx: *QueryContext,
) callconv(.c) void;
```

2. Update dispatcher to use batch ABI:
```zig
pub fn callMethodBatch(
    self: *Self,
    class_name: []const u8,
    method_name: []const u8,
    inputs: []const ColumnBinding,
    selection: ?[]const u32,
    output: *ColumnBuffer,
    ctx: *QueryContext,
) !void {
    const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{class_name, method_name});
    defer self.allocator.free(key);

    const method = self.methods.get(key) orelse return error.MethodNotFound;
    const batch_fn: BatchMethodFn = @ptrCast(method.fn_ptr);
    batch_fn(inputs, selection, output, ctx);
}
```

3. Update `evaluateMethodCall` in executor to use batch dispatch:
```zig
fn evaluateMethodCall(self: *Self, mc: anytype, indices: []const u32) ![]f64 {
    const class_name = self.logic_table_aliases.get(mc.object) orelse
        return error.TableAliasNotFound;

    const dispatcher = self.dispatcher orelse
        return error.NoDispatcherConfigured;

    // Get input columns from context
    const inputs = try self.getMethodInputBindings(class_name, mc.method);

    // Allocate output buffer
    var output = try ColumnBuffer.initFloat(self.allocator, indices.len);

    // Call batch method
    try dispatcher.callMethodBatch(
        class_name,
        mc.method,
        inputs,
        indices,
        &output,
        self.query_ctx,
    );

    return output.f64.?;
}
```

### Phase 3: Python Parsing

**File: `src/logic_table/executor.zig`**

1. Add simple Python parser (regex-based for MVP):
```zig
pub fn parsePythonFile(self: *Self) !void {
    const content = try std.fs.cwd().readFileAlloc(
        self.allocator, self.python_file, 1024 * 1024
    );
    defer self.allocator.free(content);

    // Extract class name: @logic_table\nclass ClassName:
    self.class_name = try self.extractClassName(content);

    // Extract Table() declarations: name = Table("path.lance")
    try self.extractTableDecls(content);

    // Extract method names: def method_name(self, ...):
    try self.extractMethods(content);
}

fn extractClassName(self: *Self, content: []const u8) ![]const u8 {
    // Find "class " after "@logic_table"
    const logic_table_pos = std.mem.indexOf(u8, content, "@logic_table") orelse
        return error.NoLogicTableDecorator;
    const after = content[logic_table_pos..];
    const class_pos = std.mem.indexOf(u8, after, "class ") orelse
        return error.NoClassFound;
    const name_start = class_pos + 6;
    const name_end = std.mem.indexOfAny(u8, after[name_start..], ":(") orelse
        return error.InvalidClassName;
    return try self.allocator.dupe(u8, std.mem.trim(u8, after[name_start..name_start + name_end], " "));
}
```

### Phase 4: Window Expression Support

**File: `src/sql/ast.zig`**

1. Extend WindowSpec to accept expressions:
```zig
pub const WindowSpec = struct {
    /// PARTITION BY expressions (not just column names)
    partition_by: ?[]Expr,

    /// ORDER BY expressions with direction
    order_by: ?[]struct {
        expr: Expr,
        direction: OrderDirection,
    },

    /// Window frame (ROWS/RANGE BETWEEN)
    frame: ?WindowFrame,
};
```

2. Add OVER clause to method calls in parser (`src/sql/parser.zig`):
```zig
fn parseMethodCall(self: *Self) !Expr {
    const object = try self.parseIdentifier();
    _ = try self.expect(.dot);
    const method = try self.parseIdentifier();
    _ = try self.expect(.left_paren);
    const args = try self.parseExprList();
    _ = try self.expect(.right_paren);

    // NEW: Check for OVER clause
    const window_spec = if (self.match(.keyword_over))
        try self.parseWindowSpec()
    else
        null;

    return .{ .method_call = .{
        .object = object,
        .method = method,
        .args = args,
        .over = window_spec,
    }};
}
```

## Testing Strategy

### Unit Tests

1. **FROM clause resolution** (`tests/test_sql_executor.zig`):
```zig
test "execute with logic_table FROM clause" {
    const stmt = try parser.parse(
        "SELECT t.risk_score() FROM logic_table('fraud.py') AS t"
    );

    // Create mock LogicTableExecutor
    var executor = try Executor.init(null, allocator);
    executor.setDispatcher(&mock_dispatcher);

    const result = try executor.execute(&stmt.select, &.{});
    try testing.expect(result.row_count > 0);
}
```

2. **Batch method dispatch** (`tests/test_logic_table_dispatch.zig`):
```zig
test "batch method dispatch with selection" {
    var dispatcher = Dispatcher.init(allocator);
    try dispatcher.registerBatchMethod("FraudDetector", "risk_score", &mock_risk_score);

    const inputs = &[_]ColumnBinding{
        .{ .name = "amount", .data = .{ .f64 = amounts } },
    };
    const selection = &[_]u32{ 0, 2, 5 };  // Only process rows 0, 2, 5
    var output = try ColumnBuffer.initFloat(allocator, 3);

    try dispatcher.callMethodBatch("FraudDetector", "risk_score", inputs, selection, &output, null);

    try testing.expect(output.f64.?[0] == expected_scores[0]);
}
```

### End-to-End Test

```zig
test "e2e: logic_table SQL execution" {
    // Setup: Create test Lance files
    const orders = try createTestLanceFile("test_orders.lance", ...);
    defer std.fs.cwd().deleteFile("test_orders.lance");

    // Setup: Create test Python file
    try std.fs.cwd().writeFile("test_fraud.py",
        \\@logic_table
        \\class FraudDetector:
        \\    orders = Table("test_orders.lance")
        \\
        \\    def risk_score(self):
        \\        return self.orders.amount * 0.01
    );
    defer std.fs.cwd().deleteFile("test_fraud.py");

    // Execute
    const result = try sql.execute(
        "SELECT t.risk_score(), orders.amount " ++
        "FROM logic_table('test_fraud.py') AS t " ++
        "WHERE t.risk_score() > 0.5"
    );

    // Verify
    try testing.expect(result.row_count == expected_high_risk_count);
}
```

## Migration Path

1. **Phase 1**: Wire FROM clause (enables `FROM logic_table(...)` syntax)
2. **Phase 2**: Batch dispatch (enables efficient method execution)
3. **Phase 3**: Python parsing (enables auto-loading tables)
4. **Phase 4**: Window expressions (enables `t.method() OVER (...)`)

Each phase is independently testable and deployable.
