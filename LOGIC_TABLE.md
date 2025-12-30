# @logic_table: Business Logic That Runs WITH Your Data

## Python User Quick Reference

### What's Available in Each SQL Clause

When your `@logic_table` method is called, it receives a `QueryContext` that tells you WHERE in the query you are and WHAT data you can access:

| SQL Clause | `ctx.phase` | `ctx.filtered_indices` | `ctx.window_spec` | `ctx.predicates` | Cache Scope |
|------------|-------------|------------------------|-------------------|------------------|-------------|
| **WHERE** | `filter` | ❌ None yet (you're filtering!) | ❌ | ✅ Pushdown hints | Query |
| **SELECT** | `projection` | ✅ Rows that passed WHERE | ❌ | ✅ | Query |
| **HAVING** | `group_filter` | ✅ Rows in current group | ❌ | ✅ | Query |
| **ORDER BY** | `ordering` | ✅ All projected rows | ❌ | ✅ | Query |
| **OVER()** | `window` | ✅ Rows in current partition | ✅ Full window spec | ✅ | Partition |

### Context Properties

```python
class QueryContext:
    # Which SQL clause is calling this method
    phase: str  # 'filter', 'projection', 'group_filter', 'ordering', 'window'

    # Row information
    total_rows: int              # Total rows in source table
    matched_rows: int            # Rows that passed WHERE (0 during filter phase)
    filtered_indices: list[int]  # Which row indices passed WHERE (None during filter phase)

    # Predicate pushdown (hints from WHERE clause)
    predicates: list[FilterPredicate]  # e.g., [{"column": "amount", "op": ">", "value": 1000}]

    # Window function context (only when phase == 'window')
    window_spec: WindowSpec      # partition_keys, order_keys, frame_bounds
    partition_id: int            # Current partition number
    partition_row_indices: list[int]  # Row indices in current partition

    # Caching
    result_cache: dict           # Auto-managed, keyed by (method, phase, window_spec, snapshot)
```

### Example: Phase-Aware Method

```python
@logic_table
class SmartProcessor:
    data = Table('orders.lance')

    def smart_score(self, ctx: QueryContext) -> float:
        if ctx.phase == 'filter':
            # Called during WHERE evaluation
            # Use quick estimate - ctx.filtered_indices is None here
            # Can use ctx.predicates for pushdown hints
            return self.quick_estimate()

        elif ctx.phase == 'projection':
            # Called during SELECT
            # ctx.filtered_indices contains rows that passed WHERE
            return self.full_calculation()

        elif ctx.phase == 'window':
            # Called during OVER(PARTITION BY ... ORDER BY ...)
            # ctx.window_spec has partition_keys, order_keys, frame_bounds
            # ctx.partition_row_indices has rows in this partition
            return self.partition_aggregate(
                ctx.window_spec.partition_keys,
                ctx.partition_row_indices
            )

        return 0.0
```

### Example: Using Predicate Pushdown

```python
@logic_table
class OptimizedProcessor:
    data = Table('orders.lance')

    def optimized_score(self, ctx: QueryContext) -> float:
        # Check if WHERE clause has amount filter
        for pred in ctx.predicates:
            if pred.column == 'amount' and pred.op == '>':
                # Early exit for rows we know won't pass
                if self.data.amount < pred.value:
                    return 0.0  # Skip expensive computation

        return self.expensive_calculation()
```

### Example: Window Function with Partition Context

```python
@logic_table
class WindowProcessor:
    data = Table('orders.lance')

    def running_avg(self, ctx: QueryContext) -> float:
        if ctx.phase != 'window':
            raise ValueError("running_avg must be used in OVER() clause")

        # Get rows in current partition
        partition_rows = ctx.partition_row_indices
        current_pos = partition_rows.index(ctx.current_row)

        # Compute running average up to current row
        values = [self.data.amount[i] for i in partition_rows[:current_pos + 1]]
        return sum(values) / len(values)
```

```sql
-- SQL usage
SELECT
    order_id,
    t.running_avg() OVER (PARTITION BY customer_id ORDER BY order_date)
FROM logic_table('processor.py') AS t
```

### State Sharing Between Methods

All methods in a `@logic_table` share the same context, enabling:

```python
@logic_table
class FraudDetector:
    orders = Table('orders.lance')

    # Shared state via result_cache (auto-managed)
    def amount_score(self) -> float:
        return min(1.0, self.orders.amount / 50000)

    def velocity_score(self) -> float:
        return self.orders.amount / self.orders.avg_amount

    def risk_score(self) -> float:
        # These calls are memoized - computed once, reused everywhere
        return self.amount_score() * 0.5 + self.velocity_score() * 0.5
```

---

## The Story

A decade ago, I spent years writing complex SQL stored procedures. Business logic lived inside the database. It was fast because the logic ran WHERE the data lived.

Then the industry told us this was bad practice:

- **"Don't put business logic in the database"** - Hard to debug, deploy, and secure
- **"Keep the database dumb"** - Just store and retrieve data
- **"Logic belongs in the application layer"** - Where you have proper languages and tooling

So we moved everything to Python. And it worked... until it didn't.

### What's the Next Step?

Separating storage from compute was the first step. Formats like Parquet and Lance let you query files directly on S3/R2/GCS without a database server. No connection pooling, no stored procedure security nightmares, no vendor lock-in.

But we're still stuck with "query then process" - fetch data to Python, then run business logic. What if we could also separate the *logic* from the runtime, and have it run where the data lives?

### The Problem with "Query Then Process"

Modern data workflows look like this:

```
[Database] --serialize--> [Network] --deserialize--> [Python] --process--> [Result]
```

For 1 million rows of fraud detection:
1. Query engine scans data and builds result set
2. Serialize to Arrow/Parquet/JSON
3. Transfer over network or IPC
4. Deserialize into Python objects
5. Python interprets business logic row-by-row
6. Filter results

Each step adds latency. The Python interpreter processes one row at a time. Even with NumPy vectorization, you're still crossing boundaries and making copies.

### What Changed

Machines are more powerful now. A laptop can process millions of rows per second. So I built [metal0](https://github.com/metal0-tech/metal0) - a compiler that transpiles Python to native code (Zig, WASM, GPU shaders). The logic stays in Python (testable, versionable, proper tooling) but EXECUTES like stored procedures (compiled, runs on data, hardware-accelerated).

### Zero Python at Runtime

**Critical distinction**: Python in `@logic_table` is **compile-time only**.

```
┌─────────────────────────────────────────────────────────────────┐
│  COMPILE TIME (development)                                     │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────────┐  │
│  │ Python      │ ───► │   metal0    │ ───► │ Zig/WASM/GPU    │  │
│  │ @logic_table│      │  compiler   │      │ native code     │  │
│  └─────────────┘      └─────────────┘      └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│  RUNTIME (production)                                           │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Native execution only                                  │    │
│  │  • No CPython interpreter (Python semantics compiled)   │    │
│  │  • No CPython/Python runtime dependencies               │    │
│  │  • GPU/SIMD acceleration                                │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

This is why `@logic_table` can be 100–1000× faster than Python UDF-style execution in practice: there is **zero CPython/Python runtime at runtime** (no interpreter). We still preserve Python semantics by compiling them into native code, including a Python-compatible object model implemented in Zig where needed.

## @logic_table: The Solution

A `@logic_table` is a **Python class that becomes a virtual table** in SQL. It's NOT a UDF (user-defined function) - it's a table source with computed columns.

```python
# fraud_detector.py
from lanceql import logic_table, Table

@logic_table
class FraudDetector:
    """Fraud detection logic combining order and customer data."""

    # Data sources - query engine loads these automatically
    orders = Table('orders.lance')
    customers = Table('customers.lance')

    # Constants
    HIGH_AMOUNT_THRESHOLD = 10000

    def amount_score(self) -> float:
        """Score based on order amount."""
        if self.orders.amount > self.HIGH_AMOUNT_THRESHOLD:
            return min(1.0, self.orders.amount / 50000)
        return 0.0

    def customer_score(self) -> float:
        """Score based on customer risk factors."""
        score = 0.0
        if self.customers.days_since_signup < 30:
            score += 0.3
        if self.customers.previous_fraud:
            score += 0.5
        return min(1.0, score)

    def risk_score(self) -> float:
        """Combined risk score (0-1)."""
        return self.amount_score() * 0.5 + self.customer_score() * 0.5

    def risk_category(self) -> str:
        """Categorize risk level."""
        score = self.risk_score()
        if score > 0.8: return 'critical'
        if score > 0.6: return 'high'
        if score > 0.3: return 'medium'
        return 'low'

    def should_block(self) -> bool:
        """Whether to block this transaction."""
        return self.risk_score() > 0.8
```

### SQL Usage

The `@logic_table` class is used in **FROM or JOIN**, not as a function call:

```sql
-- Basic usage: logic_table as table source
WITH DATA (
    orders = 'orders.lance',
    customers = 'customers.lance'
)
SELECT
    orders.order_id,
    orders.amount,
    t.risk_score(),
    t.risk_category()
FROM logic_table('fraud_detector.py') AS t
WHERE t.risk_score() > 0.7
ORDER BY t.risk_score() DESC
LIMIT 100
```

### Methods in Different SQL Clauses

Every method can be used in ANY SQL clause:

```sql
-- SELECT: computed columns
SELECT t.risk_score(), t.risk_category(), t.should_block()

-- WHERE: filter by method result
WHERE t.risk_score() > 0.5 AND NOT t.should_block()

-- ORDER BY: sort by method result
ORDER BY t.risk_score() DESC

-- GROUP BY: group by method result
GROUP BY t.risk_category()

-- HAVING: filter groups
HAVING AVG(t.risk_score()) > 0.6

-- PARTITION BY: window function partitioning
SUM(amount) OVER(PARTITION BY t.risk_category() ORDER BY t.risk_score())
```

### With Table Alias or Without

```sql
-- With alias
FROM logic_table('fraud_detector.py') AS fraud
WHERE fraud.risk_score() > 0.7

-- Without alias (methods called directly)
FROM logic_table('fraud_detector.py')
WHERE risk_score() > 0.7

-- Join with other tables
SELECT o.*, fraud.risk_score()
FROM orders o
JOIN logic_table('fraud_detector.py') AS fraud
  ON fraud.orders.id = o.id
WHERE fraud.should_block() = false
```

## Key Difference from UDFs

### Traditional UDF (Opaque, Limited Context)

```python
# UDF: opaque to optimizer, limited context
def fraud_udf(amount, customer_id):
    # No query phase awareness
    # No window/partition context
    # No selectivity information
    # No cross-method caching scope
    return calculate_score(amount, customer_id)
```

```sql
-- DuckDB/Polars: treats UDF as opaque
-- Limited pushdown/rewrite opportunities
SELECT fraud_udf(amount, customer_id) FROM orders
```

**Note**: UDFs in SELECT won't run for rows filtered by WHERE (that's SQL semantics).
The real limitation is: UDFs are **opaque** to the optimizer, have **weak pushdown**
opportunities, and lack **rich query context** (predicates, selectivity, window specs, cache scope).

### @logic_table (Query-Planned, Context-Aware)

```python
@logic_table
class FraudDetector:
    def risk_score(self):
        # Has access to QueryContext:
        # - clause/phase (WHERE, SELECT, HAVING, ORDER BY, WINDOW)
        # - window_spec (partition keys, order keys, frame bounds)
        # - filtered_indices or selection mask
        # - predicates for pushdown
        # - selectivity for algorithm selection
        # - result_cache with correct scope
        return self.amount_score() + self.customer_score()
```

```sql
-- LanceQL: query-planned, fused with scan
SELECT t.risk_score()
FROM logic_table('fraud_detector.py') t
WHERE amount > 1000
-- Optimizer can fuse filter + projection
-- Method runs batch-wise on surviving rows only
```

### The Real Differences

| Aspect | Traditional UDF | @logic_table |
|--------|-----------------|--------------|
| Optimizer visibility | Opaque black box | Query-planned, participates in optimization |
| Pushdown | Weak/none | Full predicate pushdown |
| Context | Row values only | Phase, window spec, selectivity, predicates |
| Execution | Often row-wise | Batch vectorized (vectors + selection mask) |
| Caching | None or manual | Automatic with correct scope (phase, window, snapshot) |
| Rewrite | Cannot reorder/fuse | Optimizer can reorder, fuse, eliminate |

## Query Context Access

Unlike UDFs, `@logic_table` methods have access to query execution context:

### FilterPredicate (Pushdown from WHERE)

```python
@logic_table
class SmartProcessor:
    def optimized_score(self, ctx: QueryContext):
        # See what's in WHERE clause
        if ctx.has_predicate("amount"):
            threshold = ctx.get_predicate_value("amount")
            # Skip rows below threshold early
            if self.orders.amount < threshold:
                return 0.0  # Early exit

        return self.expensive_calculation()
```

### Filtered Indices

```python
def batch_process(self, ctx: QueryContext):
    # Only process rows that passed WHERE clause
    indices = ctx.filtered_indices  # [5, 10, 15, ...] or None

    if indices is not None:
        # Process only matching rows
        for i in indices:
            yield self.compute(i)
    else:
        # No filter, process all
        for i in range(ctx.total_rows):
            yield self.compute(i)
```

### Selectivity-Based Algorithm Choice

```python
def smart_join(self, ctx: QueryContext):
    selectivity = ctx.get_selectivity()  # matched/total

    if selectivity < 0.01:
        # Very selective: use index lookup
        return self.index_lookup()
    elif selectivity < 0.1:
        # Somewhat selective: use hash join
        return self.hash_join()
    else:
        # Not selective: use merge join
        return self.merge_join()
```

## Phase-Aware Execution

Methods can be used in any SQL clause, but they must know which **phase** they're in for correctness.

### Execution Phases

| Phase | SQL Clause | When It Runs | Context Available |
|-------|------------|--------------|-------------------|
| `filter` | WHERE | Before aggregation | predicates, selectivity |
| `projection` | SELECT | After filter | filtered_indices |
| `group_filter` | HAVING | After aggregation | group keys, aggregates |
| `ordering` | ORDER BY | After projection | sort requirements |
| `window` | OVER(...) | Partition + frame | partition_keys, order_keys, frame_bounds |

### QueryContext with Phase

```zig
pub const ExecutionPhase = enum {
    filter,       // WHERE clause
    projection,   // SELECT clause
    group_filter, // HAVING clause
    ordering,     // ORDER BY clause
    window,       // OVER(PARTITION BY ... ORDER BY ... ROWS/RANGE ...)
};

pub const WindowSpec = struct {
    partition_keys: []const []const u8,  // PARTITION BY columns
    order_keys: []const OrderKey,        // ORDER BY columns + direction
    frame_start: FrameBound,             // ROWS/RANGE start
    frame_end: FrameBound,               // ROWS/RANGE end
};

pub const QueryContext = struct {
    // Existing fields
    total_rows: usize,
    matched_rows: usize,
    filtered_indices: ?[]const usize,
    predicates: []const FilterPredicate,

    // Phase-aware fields
    phase: ExecutionPhase,
    window_spec: ?WindowSpec,           // Only set when phase == .window
    partition_id: ?usize,               // Current partition (for window)
    partition_row_indices: ?[]const usize, // Rows in current partition
};
```

### Why Phase Matters

The same method can behave differently depending on phase:

```python
@logic_table
class Metrics:
    def score(self, ctx: QueryContext):
        if ctx.phase == 'filter':
            # Quick estimate for filtering
            return self.quick_estimate()
        elif ctx.phase == 'projection':
            # Full computation for output
            return self.full_calculation()
        elif ctx.phase == 'window':
            # Partition-aware computation
            return self.partition_aggregate(ctx.partition_id)
```

### Cache Keys Must Include Phase

```zig
fn generateCacheKey(method: []const u8, ctx: *QueryContext) []u8 {
    // Key must include phase to avoid incorrect reuse
    return fmt("{s}:phase:{s}:window:{x}:snap:{d}",
        method,
        @tagName(ctx.phase),
        hashWindowSpec(ctx.window_spec),
        ctx.dataset_snapshot,
    );
}
```

## Window Functions with @logic_table

Methods can be used in PARTITION BY for parallel processing:

```sql
-- Partition by a computed column
SELECT
    order_id,
    amount,
    SUM(amount) OVER(PARTITION BY t.risk_category() ORDER BY t.risk_score())
FROM logic_table('fraud_detector.py') t

-- Use method result to define partitions
SELECT
    ROW_NUMBER() OVER(PARTITION BY t.should_review() ORDER BY t.risk_score() DESC)
FROM logic_table('fraud_detector.py') t
```

### Time-Based Windows

```sql
-- Session windows based on method
SELECT
    t.session_id(),
    SUM(amount) OVER(PARTITION BY t.session_id())
FROM logic_table('session_tracker.py') t

-- Tumbling windows
SELECT
    t.time_bucket('1 hour'),
    AVG(t.metric())
FROM logic_table('metrics.py') t
GROUP BY t.time_bucket('1 hour')
```

## ORDER BY and Window Execution Details

### Top-Level ORDER BY

When a method is used in ORDER BY:

```sql
SELECT amount, t.risk_score()
FROM logic_table('fraud.py') t
WHERE amount > 1000
ORDER BY t.risk_score() DESC
LIMIT 100
```

**Execution requirements**:
1. Method output must be a **sortable vector** with defined type
2. **Null ordering** must be specified (NULLS FIRST/LAST)
3. **Stable tie behavior** must be deterministic
4. For LIMIT, consider **Top-K optimization** (heap instead of full sort)

```zig
pub const OrderKey = struct {
    column_or_method: []const u8,
    ascending: bool,
    nulls_first: bool,
};

/// ORDER BY execution
fn executeOrderBy(
    rows: []const usize,        // Filtered row indices
    order_keys: []const OrderKey,
    limit: ?usize,
) []usize {
    if (limit) |k| {
        // Top-K: use heap, O(n log k)
        return topK(rows, order_keys, k);
    } else {
        // Full sort: O(n log n)
        return fullSort(rows, order_keys);
    }
}
```

### Window Function Execution

Window functions require **partition + order + frame** context:

```sql
SELECT
    order_id,
    SUM(amount) OVER(
        PARTITION BY t.risk_category()
        ORDER BY t.risk_score() DESC
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    )
FROM logic_table('fraud.py') t
```

**Execution phases**:

1. **Compute partition keys**: `t.risk_category()` for all rows
2. **Group by partition**: Rows with same partition key
3. **Order within partition**: By `t.risk_score() DESC`
4. **Apply frame**: ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
5. **Compute aggregate**: SUM(amount) over frame

```zig
pub const FrameBound = union(enum) {
    unbounded_preceding,
    preceding: usize,    // N PRECEDING
    current_row,
    following: usize,    // N FOLLOWING
    unbounded_following,
};

pub const WindowFrame = struct {
    mode: enum { rows, range, groups },
    start: FrameBound,
    end: FrameBound,
};

/// Window execution context
pub const WindowContext = struct {
    partition_id: usize,
    partition_start: usize,          // Start index in sorted order
    partition_end: usize,            // End index in sorted order
    current_row: usize,              // Current row within partition
    frame: WindowFrame,

    /// Get rows in current frame
    pub fn getFrameRows(self: *const WindowContext) []const usize {
        const start = switch (self.frame.start) {
            .current_row => self.current_row,
            .preceding => |n| @max(self.partition_start, self.current_row -| n),
            .unbounded_preceding => self.partition_start,
            // ...
        };
        const end = switch (self.frame.end) {
            .current_row => self.current_row + 1,
            .following => |n| @min(self.partition_end, self.current_row + n + 1),
            .unbounded_following => self.partition_end,
            // ...
        };
        return self.sorted_indices[start..end];
    }
};
```

### Batch Execution for Windows

Methods in window context run **per-partition batches**, not per-row:

```zig
/// Execute window function with batch method
fn executeWindowFunction(
    partitions: []const Partition,
    method: BatchMethodFn,
    aggregate: AggregateFn,
    frame: WindowFrame,
    out: []f64,
) void {
    for (partitions) |partition| {
        // Compute method for entire partition (batch)
        const method_results = method(partition.rows, ...);

        // Apply frame and aggregate
        for (partition.rows, 0..) |_, row_idx| {
            const frame_rows = getFrameRows(partition, row_idx, frame);
            out[row_idx] = aggregate(method_results[frame_rows]);
        }
    }
}
```

**Key insight**: The method computes once per partition, then the aggregate slides over the frame. This is much faster than computing the method for each frame position.

## Life Cycle

### Instance Life Cycle

A `@logic_table` instance follows this life cycle:

```
┌─────────────────────────────────────────────────────────────────┐
│                        QUERY EXECUTION                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. COMPILE (once)                                              │
│     ├─ Parse Python @logic_table class                          │
│     ├─ Extract Table dependencies                               │
│     ├─ Compile methods to Zig IR → native code                  │
│     └─ Register in LogicTableRegistry                           │
│                                                                 │
│  2. INIT (per query)                                            │
│     ├─ Create QueryContext                                      │
│     │   ├─ total_rows, matched_rows                             │
│     │   ├─ filtered_indices (from WHERE)                        │
│     │   ├─ predicates (pushdown)                                │
│     │   └─ result_cache (memoization)                           │
│     │                                                           │
│     └─ Create LogicTableContext                                 │
│         ├─ Link to QueryContext                                 │
│         └─ Initialize column caches                             │
│                                                                 │
│  3. BIND (per table in FROM/JOIN)                               │
│     ├─ Load required columns from Lance files                   │
│     ├─ ctx.bindF32("orders", "amount", [...])                   │
│     └─ ctx.bindI64("customers", "days_since_signup", [...])     │
│                                                                 │
│  4. EXECUTE (per method call)                                   │
│     ├─ Check result_cache for memoized result                   │
│     ├─ If miss: compute using bound columns                     │
│     ├─ GPU dispatch for ≥10K rows                               │
│     ├─ SIMD for 16-10K rows                                     │
│     ├─ Scalar for <16 rows                                      │
│     └─ Cache result for repeated calls                          │
│                                                                 │
│  5. CLEANUP (query end)                                         │
│     ├─ Free result_cache entries                                │
│     ├─ Free QueryContext                                        │
│     └─ Free LogicTableContext                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Code Example

```zig
// Life cycle in executor
pub fn executeQuery(sql: []const u8) !Result {
    var allocator = std.heap.page_allocator;

    // 2. INIT
    var query_ctx = QueryContext.init(allocator);
    defer query_ctx.deinit();  // 5. CLEANUP

    var ctx = LogicTableContext.initWithQuery(allocator, &query_ctx);
    defer ctx.deinit();  // 5. CLEANUP

    // 3. BIND (after parsing SQL and loading tables)
    try ctx.bindF32("orders", "amount", orders_amount_data);
    try ctx.bindI64("customers", "days_since_signup", customer_data);

    // Set query context (after WHERE evaluation)
    query_ctx.total_rows = 100000;
    query_ctx.matched_rows = 1500;
    query_ctx.filtered_indices = filtered;

    // 4. EXECUTE methods on filtered rows
    for (query_ctx.filtered_indices) |idx| {
        const score = compute_risk_score(&ctx, idx);
        // ...
    }
}
```

## Context Sharing

### Shared State Between Methods

All methods in a `@logic_table` share the same `LogicTableContext`, enabling:

1. **Column Data Sharing**: Bound once, used by all methods
2. **Result Memoization**: Cache expensive computations
3. **Query Context**: All methods see same filtered indices

```python
@logic_table
class FraudDetector:
    orders = Table('orders.lance')

    def amount_score(self) -> float:
        # Accesses shared column data
        return min(1.0, self.orders.amount / 50000)

    def velocity_score(self) -> float:
        # Same column data, different computation
        return self.orders.amount / self.orders.avg_amount

    def risk_score(self) -> float:
        # Calls other methods - results may be memoized
        return self.amount_score() * 0.5 + self.velocity_score() * 0.5
```

### Context Hierarchy

```
┌─────────────────────────────────────────────────────────────────┐
│ QueryContext (per query)                                        │
│   ├─ total_rows: 100,000                                        │
│   ├─ matched_rows: 1,500                                        │
│   ├─ filtered_indices: [5, 12, 45, ...]                         │
│   ├─ predicates: [{column: "amount", op: ">", value: 1000}]     │
│   └─ result_cache: {"risk_score_row_5": 0.85, ...}              │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │ LogicTableContext (per logic_table in FROM/JOIN)        │   │
│   │   ├─ query_context: *QueryContext (shared reference)    │   │
│   │   ├─ column_cache_f32: {"orders.amount": [...]}         │   │
│   │   └─ column_cache_i64: {"customers.days_since": [...]}  │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │ LogicTableContext (another logic_table)                 │   │
│   │   └─ query_context: *QueryContext (SAME reference)      │   │
│   └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### Cross-Table Joins

When multiple `@logic_table` classes are joined, they share the same `QueryContext`:

```sql
SELECT
    f.risk_score(),
    p.priority_score()
FROM logic_table('fraud_detector.py') AS f
JOIN logic_table('priority_scorer.py') AS p
  ON f.orders.id = p.orders.id
WHERE f.risk_score() > 0.5
```

Both `f` and `p` see:
- Same `filtered_indices` (rows passing WHERE)
- Same `predicates` (pushdown from WHERE)
- Shared `result_cache` (cross-table memoization)

## External Cache Provider

### Why External Caching?

The default `result_cache` in `QueryContext` is in-memory and query-scoped. For:
- **Cross-query caching**: Reuse expensive computations across queries
- **Persistent caching**: Survive process restarts
- **Distributed caching**: Share across workers/nodes

You need an external cache provider.

### Cache Provider Interface

**Important**: Python code in `@logic_table` is **compile-time only**. metal0 transpiles Python to native Zig/WASM/GPU code. There is **no CPython interpreter at runtime**.

The cache provider is configured at the Zig level:

```python
# Python @logic_table (COMPILE-TIME ONLY)
# metal0 transpiles this to native Zig code

@logic_table
class ExpensiveProcessor:
    """This Python is compiled away - runs as native code."""
    data = Table('large_dataset.lance')

    def expensive_score(self) -> float:
        # At runtime, this is native Zig, not Python!
        return self.complex_calculation()
```

### Zig Interface (Runtime)

```zig
/// External cache provider interface
pub const CacheProvider = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        get: *const fn (ptr: *anyopaque, key: []const u8) ?CachedResult,
        set: *const fn (ptr: *anyopaque, key: []const u8, value: CachedResult) void,
        invalidate: *const fn (ptr: *anyopaque, pattern: []const u8) void,
    };

    pub fn get(self: CacheProvider, key: []const u8) ?CachedResult {
        return self.vtable.get(self.ptr, key);
    }

    pub fn set(self: CacheProvider, key: []const u8, value: CachedResult) void {
        self.vtable.set(self.ptr, key, value);
    }
};

/// QueryContext with external cache support
pub const QueryContext = struct {
    // ... existing fields ...

    /// In-memory cache (query-scoped)
    result_cache: std.StringHashMap(CachedResult),

    /// External cache provider (optional, cross-query)
    external_cache: ?CacheProvider,

    pub fn getCached(self: *Self, key: []const u8) ?CachedResult {
        // Check in-memory first
        if (self.result_cache.get(key)) |result| {
            return result;
        }
        // Fall back to external cache
        if (self.external_cache) |ext| {
            if (ext.get(key)) |result| {
                // Promote to in-memory for this query
                self.result_cache.put(key, result) catch {};
                return result;
            }
        }
        return null;
    }
};
```

### Built-in Cache Providers

| Provider | Scope | Use Case |
|----------|-------|----------|
| `InMemoryCache` | Query | Default, fast, no persistence |
| `IndexedDBCache` | Browser session | WASM, survives page refresh |
| `FileCache` | Process | CLI tools, local persistence |
| `RedisCache` | Cluster | Distributed, shared state |

### Browser (IndexedDB) Cache

For WASM deployments, we use IndexedDB:

```javascript
// Already implemented in src/core/cache.js
import { metadataCache } from './cache.js';

// Cache schema and metadata
await metadataCache.set(datasetUrl, {
    schema: schema,
    columnTypes: types,
    fragments: fragmentInfo
});

// Retrieve on next visit
const cached = await metadataCache.get(datasetUrl);
if (cached) {
    // Skip expensive schema parsing
}
```

### Cache Key Generation

Cache keys must include **all context that affects correctness**:

```zig
/// Generate cache key with full correctness scope
fn generateCacheKey(
    allocator: std.mem.Allocator,
    method_name: []const u8,
    ctx: *const QueryContext,
) ![]u8 {
    var hasher = std.hash.Wyhash.init(0);

    // 1. Method identity
    hasher.update(method_name);

    // 2. Execution phase (WHERE vs SELECT vs WINDOW behave differently)
    hasher.update(@tagName(ctx.phase));

    // 3. Selection identity (which rows)
    if (ctx.filtered_indices) |indices| {
        hasher.update(std.mem.sliceAsBytes(indices));
    }

    // 4. Window spec (for window phase)
    if (ctx.window_spec) |spec| {
        for (spec.partition_keys) |key| hasher.update(key);
        for (spec.order_keys) |key| {
            hasher.update(key.column);
            hasher.update(std.mem.asBytes(&key.ascending));
        }
        hasher.update(std.mem.asBytes(&spec.frame_start));
        hasher.update(std.mem.asBytes(&spec.frame_end));
    }

    // 5. Dataset snapshot/version (Lance version + delete state)
    hasher.update(std.mem.asBytes(&ctx.dataset_snapshot));
    hasher.update(std.mem.asBytes(&ctx.fragment_id));
    hasher.update(std.mem.asBytes(&ctx.delete_version));

    return std.fmt.allocPrint(allocator,
        "{s}:{x}",
        .{ method_name, hasher.final() },
    );
}
```

**Critical**: Without snapshot/version in the key, you get "fast and wrong" results after deletes/updates/compaction.

### The One Rule: Never Recompute

The same method used in multiple places (SELECT + ORDER BY) must not recompute:

```sql
SELECT t.risk_score(), amount
FROM logic_table('fraud.py') t
ORDER BY t.risk_score() DESC
```

The cache ensures `risk_score()` computes once, reused for both SELECT output and ORDER BY sorting.

## Batch Vectorized ABI

Methods compile to batch operations, not row-by-row calls. This is the key to performance.

### Method Input/Output Contract

```zig
/// Batch method signature - operates on vectors, not rows
pub const BatchMethodFn = fn (
    // Input columns (bound from Lance)
    columns: *const ColumnBindings,

    // Selection: which rows to process
    selection: Selection,

    // Output buffer (caller-allocated)
    out: OutputBuffer,

    // Query context for phase-aware behavior
    ctx: *const QueryContext,
) void;

/// Selection can be indices or mask
pub const Selection = union(enum) {
    /// Indices array: [5, 12, 45, ...] - process only these rows
    indices: []const usize,

    /// Boolean mask: [false, false, true, ...] - process where true
    mask: []const bool,

    /// All rows (no filter)
    all: usize, // total count
};

/// Output depends on clause
pub const OutputBuffer = union(enum) {
    /// For SELECT/ORDER BY: vector of computed values
    vector_f64: []f64,
    vector_i64: []i64,
    vector_bool: []bool,

    /// For WHERE/HAVING: boolean predicate result
    predicate: []bool,
};
```

### Why Both Indices and Mask?

| Selection Type | Best For | Memory | Access Pattern |
|----------------|----------|--------|----------------|
| `indices` | Sparse selection (<10%) | O(matched) | Gather |
| `mask` | Dense selection (>10%) | O(total) | Sequential scan |
| `all` | No filter | O(1) | Sequential |

The optimizer chooses based on selectivity:

```zig
fn chooseSelectionType(selectivity: f64) SelectionType {
    if (selectivity < 0.1) return .indices;  // Sparse: use gather
    if (selectivity < 0.9) return .mask;     // Medium: use mask
    return .all;                              // Dense: process all
}
```

### Generated Code Example

Python:
```python
@logic_table
class FraudDetector:
    orders = Table('orders.lance')

    def amount_score(self) -> float:
        return min(1.0, self.orders.amount / 50000)
```

Compiles to:
```zig
/// Batch vectorized implementation
pub fn amount_score_batch(
    columns: *const ColumnBindings,
    selection: Selection,
    out: []f64,
    ctx: *const QueryContext,
) void {
    const amount = columns.getF64("orders", "amount");

    switch (selection) {
        .indices => |indices| {
            // Gather pattern: only process selected rows
            for (indices, 0..) |row_idx, out_idx| {
                out[out_idx] = @min(1.0, amount[row_idx] / 50000.0);
            }
        },
        .mask => |mask| {
            // Scan pattern: skip false entries
            var out_idx: usize = 0;
            for (mask, 0..) |selected, row_idx| {
                if (selected) {
                    out[out_idx] = @min(1.0, amount[row_idx] / 50000.0);
                    out_idx += 1;
                }
            }
        },
        .all => |count| {
            // SIMD pattern: process all rows
            simd.vectorizedMinDiv(amount[0..count], 50000.0, 1.0, out);
        },
    }
}
```

### GPU Dispatch Threshold

```zig
fn dispatchMethod(selection: Selection, ...) void {
    const count = switch (selection) {
        .indices => |i| i.len,
        .mask => |m| countTrue(m),
        .all => |n| n,
    };

    if (count >= 10_000 and metal.isGPUReady()) {
        // GPU: large batches
        metal.gpuDispatch(...);
    } else if (count >= 16) {
        // SIMD: medium batches
        simd.vectorized(...);
    } else {
        // Scalar: small batches
        scalar.loop(...);
    }
}
```

## Architecture

### Compilation Flow

```
Python Code                    metal0 Compiler                  LanceQL Runtime
    |                               |                                |
@logic_table -----> Parse AST ----> Zig IR -----> Native Code ----> GPU Execution
class Fraud...      Extract         Generate       Compile to        Fused with
                    deps            functions      GPU kernels       data scan
```

### Runtime Execution

```
SQL Query                                     Result
    │                                            ▲
    ▼                                            │
┌─────────────────────────────────────────────────────┐
│ Parser: Identify logic_table() in FROM/JOIN         │
│         Extract method calls (t.risk_score(), etc)  │
└─────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────┐
│ Column Deps: Analyze which Table columns needed     │
│   FraudDetector.risk_score() needs:                 │
│   - orders.amount                                   │
│   - customers.days_since_signup                     │
│   - customers.previous_fraud                        │
└─────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────┐
│ Load Data: Only load required columns               │
│   ctx.bindF32("orders", "amount", [...])            │
│   ctx.bindI64("customers", "days_since_signup")     │
└─────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────┐
│ Execute WHERE: Get filtered indices                 │
│   Push predicates to QueryContext                   │
│   filtered_indices = [5, 12, 45, ...]               │
└─────────────────────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────────────────────┐
│ Execute Methods: Run compiled @logic_table code     │
│   - Only on filtered_indices (not all rows!)        │
│   - GPU for 10K+ rows                               │
│   - SIMD for smaller batches                        │
└─────────────────────────────────────────────────────┘
```

### GPU Dispatch Thresholds

| Threshold | Dispatch | Use Case |
|-----------|----------|----------|
| ≥10K rows | GPU | Large batch operations |
| ≥16 elements | SIMD | Vector operations |
| <16 elements | Scalar | Small data |

## Implementation Files

```
src/logic_table/
├── logic_table.zig      # LogicTableContext, QueryContext, FilterPredicate
│                        # CachedResult, LogicTableRegistry
└── vector_ops.zig       # metal0-compiled example (VectorOps, FeatureEngineering)

src/query/
└── logic_table.zig      # Batch vector operations with GPU/SIMD dispatch

src/sql/
├── ast.zig              # AST with WindowSpec for OVER clause
├── parser.zig           # Parse logic_table() in FROM, method calls
├── executor.zig         # Execute with QueryContext
├── column_deps.zig      # Extract column dependencies from methods
└── batch_codegen.zig    # Generate GPU/SIMD dispatch code

src/core/
└── cache.js             # IndexedDB MetadataCache for browser (WASM)

examples/python/
└── fraud_detector.py    # Complete @logic_table example
```

## Benchmarks (Apple M2 Pro)

### @logic_table vs UDF Performance (100K rows × 384 dims)

| Method | Total (ms) | Per Row (μs) | Notes |
|--------|------------|--------------|-------|
| LanceQL @logic_table | ~10 | 0.1 | Compiled, pushdown |
| DuckDB Python UDF | 10,102 | 101 | Row-by-row Python calls |
| DuckDB → Python Batch | 1,805 | 18 | Pull then process |
| Polars .map_elements() | 9,376 | 94 | Row-by-row Python calls |

**Key insight**: @logic_table can be 100–1000× faster than Python UDF-style execution in these benchmarks because:
1. Zero Python at runtime (compiled Zig/WASM/GPU code only)
2. Only processes filtered rows (pushdown)
3. GPU/SIMD acceleration
4. No serialization/deserialization

## Current Status

- [x] @logic_table class decorator
- [x] Table data source declarations
- [x] Method to SQL clause mapping (SELECT, WHERE, ORDER BY, GROUP BY)
- [x] QueryContext with pushdown predicates
- [x] FilteredIndices for row skipping
- [x] LogicTableRegistry for compiled classes
- [x] metal0 Python-to-Zig compiler
- [x] GPU dispatch (Metal/CUDA)
- [x] Window function syntax (OVER, PARTITION BY, ORDER BY)
- [x] WASM deployment

## License

Apache-2.0 (same as [Lance](https://github.com/lance-format/lance))
