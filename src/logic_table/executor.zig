// Logic Table Executor - Core execution engine for @logic_table
//
// This module provides the shared execution layer used by both SQL and DataFrame APIs.
//
// Workflow:
// 1. Parse Python file to extract Table() declarations and method names
// 2. Resolve Lance file paths relative to Python file location
// 3. Load required columns from Lance files
// 4. Bind columns to LogicTableContext
// 5. Dispatch method calls to compiled extern functions
//
// Usage:
//   var executor = try LogicTableExecutor.init(allocator, "fraud_detector.py");
//   defer executor.deinit();
//
//   // Bind columns (or auto-load from Table declarations)
//   try executor.loadTables();
//
//   // Execute method on all rows (batch)
//   const scores = try executor.callMethodBatch("risk_score");
//
//   // Execute method on filtered rows
//   const filtered_scores = try executor.callMethodFiltered("risk_score", filtered_indices);

const std = @import("std");
const logic_table = @import("logic_table.zig");
const Table = @import("lanceql.table").Table;

const LogicTableContext = logic_table.LogicTableContext;
const QueryContext = logic_table.QueryContext;
const LogicTableMeta = logic_table.LogicTableMeta;
const MethodMeta = logic_table.MethodMeta;
const LogicTableError = logic_table.LogicTableError;

/// Table declaration extracted from Python @logic_table class
pub const TableDecl = struct {
    /// Variable name in Python (e.g., "orders")
    name: []const u8,
    /// Lance file path (e.g., "orders.lance")
    path: []const u8,
};

/// Loaded table with column data
pub const LoadedTable = struct {
    decl: TableDecl,
    table: *Table,
    /// Columns loaded from this table
    columns: std.StringHashMap(ColumnData),

    pub const ColumnData = union(enum) {
        f32: []const f32,
        f64: []const f64,
        i64: []const i64,
        i32: []const i32,
        bool_: []const bool,
        string: []const []const u8,
    };
};

/// Method function pointer types (scalar - returns single value)
pub const MethodFnF64 = *const fn (a: [*]const f64, b: [*]const f64, len: usize) callconv(.c) f64;
pub const MethodFnF64Single = *const fn (a: [*]const f64, len: usize) callconv(.c) f64;

/// Batch method function pointer types (N inputs → N outputs)
/// Used for vectorized operations that process all rows at once
/// Returns i64 (dummy 0 value, results are in out array)
pub const BatchMethodFn = *const fn (
    matrix: [*]const f64, // Input: [num_rows × dim]
    vec: [*]const f64, // Query vector [dim]
    num_rows: i64,
    dim: i64,
    out: [*]f64, // Output: [num_rows]
) callconv(.c) i64;

/// Batch method with f32 matrix input (common for embeddings)
pub const BatchMethodFnF32 = *const fn (
    matrix: [*]const f32, // Input: [num_rows × dim] as f32
    vec: [*]const f64, // Query vector [dim] as f64
    num_rows: i64,
    dim: i64,
    out: [*]f64, // Output: [num_rows] as f64
) callconv(.c) i64;

/// Default batch size for cache-friendly processing
pub const DEFAULT_BATCH_SIZE: usize = 1024;

/// Auto-determine batch size based on data characteristics
pub fn getOptimalBatchSize(num_rows: usize, dim: usize) usize {
    // L2 cache typically ~256KB on modern CPUs
    const L2_CACHE_SIZE: usize = 256 * 1024;
    const element_size: usize = @sizeOf(f64);

    // Calculate rows that fit in L2 cache
    const bytes_per_row = dim * element_size;
    const rows_per_cache = if (bytes_per_row > 0) L2_CACHE_SIZE / bytes_per_row else DEFAULT_BATCH_SIZE;

    // Use smaller of: cache-optimal, all rows, or default
    return @min(rows_per_cache, @min(num_rows, DEFAULT_BATCH_SIZE));
}

/// Registered method with function pointer
pub const RegisteredMethod = struct {
    name: []const u8,
    class_name: []const u8,
    /// Function pointer (type depends on signature)
    fn_ptr: *const anyopaque,
    /// Number of array parameters
    num_array_params: u8,
    /// Optional batch processing function pointer
    batch_fn_ptr: ?*const anyopaque = null,
    /// Whether batch processing is supported
    supports_batch: bool = false,
    /// Whether batch function uses f32 input matrix
    batch_uses_f32: bool = false,
};

/// LogicTable Executor - manages @logic_table execution
pub const LogicTableExecutor = struct {
    allocator: std.mem.Allocator,

    /// Path to Python file
    python_file: []const u8,

    /// Directory containing Python file (for relative path resolution)
    base_dir: []const u8,

    /// Class name extracted from Python
    class_name: []const u8,

    /// Table declarations from Python
    table_decls: std.ArrayList(TableDecl),

    /// Loaded tables with data
    loaded_tables: std.StringHashMap(LoadedTable),

    /// Method metadata
    methods: std.ArrayList(MethodMeta),

    /// Registered method function pointers
    registered_methods: std.StringHashMap(RegisteredMethod),

    /// LogicTableContext for column binding
    ctx: LogicTableContext,

    /// QueryContext for pushdown
    query_ctx: ?*QueryContext,

    const Self = @This();

    /// Initialize executor from Python file path
    pub fn init(allocator: std.mem.Allocator, python_file: []const u8) !Self {
        // Extract base directory
        const base_dir = std.fs.path.dirname(python_file) orelse ".";

        return Self{
            .allocator = allocator,
            .python_file = try allocator.dupe(u8, python_file),
            .base_dir = try allocator.dupe(u8, base_dir),
            .class_name = "",
            .table_decls = .{},
            .loaded_tables = std.StringHashMap(LoadedTable).init(allocator),
            .methods = .{},
            .registered_methods = std.StringHashMap(RegisteredMethod).init(allocator),
            .ctx = LogicTableContext.init(allocator),
            .query_ctx = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.python_file);
        self.allocator.free(self.base_dir);

        // Free class name if parsed
        if (self.class_name.len > 0) {
            self.allocator.free(self.class_name);
        }

        // Free table declarations
        for (self.table_decls.items) |decl| {
            self.allocator.free(decl.name);
            self.allocator.free(decl.path);
        }
        self.table_decls.deinit(self.allocator);

        // Free loaded tables
        var iter = self.loaded_tables.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.table.deinit();
            entry.value_ptr.columns.deinit();
        }
        self.loaded_tables.deinit();

        // Free methods
        for (self.methods.items) |method| {
            self.allocator.free(method.name);
        }
        self.methods.deinit(self.allocator);

        self.registered_methods.deinit();
        self.ctx.deinit();
    }

    /// Set query context for pushdown optimization
    pub fn setQueryContext(self: *Self, query_ctx: *QueryContext) void {
        self.query_ctx = query_ctx;
        self.ctx.query_context = query_ctx;
    }

    /// Parse Python file to extract @logic_table metadata
    /// Extracts: class name, Table() declarations, method names
    pub fn parsePythonFile(self: *Self) !void {
        // Read the Python file
        const file = std.fs.cwd().openFile(self.python_file, .{}) catch |err| {
            std.debug.print("Failed to open Python file: {s} (error: {})\n", .{ self.python_file, err });
            return LogicTableError.InvalidLogicTable;
        };
        defer file.close();

        const content = file.readToEndAlloc(self.allocator, 1024 * 1024) catch |err| {
            std.debug.print("Failed to read Python file: {s} (error: {})\n", .{ self.python_file, err });
            return LogicTableError.InvalidLogicTable;
        };
        defer self.allocator.free(content);

        // Extract class name
        self.class_name = try self.extractClassName(content);

        // Extract Table() declarations
        try self.extractTableDecls(content);

        // Extract method names
        try self.extractMethods(content);
    }

    /// Extract class name from Python content
    /// Looks for: @logic_table\n... class ClassName:
    pub fn extractClassName(self: *Self, content: []const u8) ![]const u8 {
        // Find @logic_table decorator
        const logic_table_pos = std.mem.indexOf(u8, content, "@logic_table") orelse
            return LogicTableError.InvalidLogicTable;

        // Find "class " after the decorator
        const after_decorator = content[logic_table_pos..];
        const class_pos = std.mem.indexOf(u8, after_decorator, "class ") orelse
            return LogicTableError.InvalidLogicTable;

        const name_start = class_pos + 6; // "class " length
        const after_class = after_decorator[name_start..];

        // Find end of class name (: or ( for inheritance)
        var name_end: usize = 0;
        for (after_class, 0..) |c, i| {
            if (c == ':' or c == '(' or c == ' ' or c == '\n') {
                name_end = i;
                break;
            }
        }
        if (name_end == 0) return LogicTableError.InvalidLogicTable;

        const class_name = std.mem.trim(u8, after_class[0..name_end], " \t\n\r");
        return try self.allocator.dupe(u8, class_name);
    }

    /// Extract Table() declarations from Python content
    /// Looks for: variable_name = Table("path.lance")
    pub fn extractTableDecls(self: *Self, content: []const u8) !void {
        var pos: usize = 0;
        while (pos < content.len) {
            // Find "Table(" pattern
            const table_start = std.mem.indexOfPos(u8, content, pos, "Table(") orelse break;

            // Look backwards to find variable name
            var var_start = table_start;
            while (var_start > 0 and content[var_start - 1] != '\n') {
                var_start -= 1;
            }

            // Extract the line before Table(
            const line_before = content[var_start..table_start];

            // Look for pattern: "name = " or "name=" with optional spaces
            const eq_pos = std.mem.indexOf(u8, line_before, "=") orelse {
                pos = table_start + 6;
                continue;
            };

            const var_name = std.mem.trim(u8, line_before[0..eq_pos], " \t");

            // Skip if variable name is empty or has invalid chars
            if (var_name.len == 0 or !isValidPythonIdent(var_name)) {
                pos = table_start + 6;
                continue;
            }

            // Extract path from Table("...") or Table('...')
            const after_table = content[table_start + 6..];
            const quote = if (after_table.len > 0 and (after_table[0] == '"' or after_table[0] == '\''))
                after_table[0]
            else {
                pos = table_start + 6;
                continue;
            };

            const path_start: usize = 1;
            const path_end = std.mem.indexOfPos(u8, after_table, path_start, &[_]u8{quote}) orelse {
                pos = table_start + 6;
                continue;
            };

            const path = after_table[path_start..path_end];

            // Add table declaration
            try self.table_decls.append(self.allocator, .{
                .name = try self.allocator.dupe(u8, var_name),
                .path = try self.allocator.dupe(u8, path),
            });

            pos = table_start + 6 + path_end;
        }
    }

    /// Extract method names from Python content
    /// Looks for: def method_name(self, ...):
    pub fn extractMethods(self: *Self, content: []const u8) !void {
        var pos: usize = 0;
        while (pos < content.len) {
            // Find "def " pattern
            const def_start = std.mem.indexOfPos(u8, content, pos, "def ") orelse break;

            // Skip methods starting with underscore (private/magic)
            const name_start = def_start + 4;
            if (name_start >= content.len) break;

            // Find end of method name (
            const after_def = content[name_start..];
            const paren_pos = std.mem.indexOf(u8, after_def, "(") orelse {
                pos = name_start;
                continue;
            };

            const method_name = std.mem.trim(u8, after_def[0..paren_pos], " \t");

            // Skip private methods and __init__
            if (method_name.len == 0 or method_name[0] == '_') {
                pos = name_start + paren_pos;
                continue;
            }

            // Check if method has 'self' parameter (instance method)
            const params_start = name_start + paren_pos + 1;
            const after_paren = content[params_start..];
            const close_paren = std.mem.indexOf(u8, after_paren, ")") orelse {
                pos = params_start;
                continue;
            };

            const params = after_paren[0..close_paren];
            const has_self = std.mem.indexOf(u8, params, "self") != null;

            if (has_self) {
                try self.methods.append(self.allocator, .{
                    .name = try self.allocator.dupe(u8, method_name),
                    .deps = &.{}, // Dependencies extracted later
                });
            }

            pos = params_start + close_paren;
        }
    }

    /// Check if string is a valid Python identifier
    fn isValidPythonIdent(s: []const u8) bool {
        if (s.len == 0) return false;

        // First char must be letter or underscore
        const first = s[0];
        if (!std.ascii.isAlphabetic(first) and first != '_') return false;

        // Rest must be alphanumeric or underscore
        for (s[1..]) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '_') return false;
        }
        return true;
    }

    /// Add a table declaration manually (alternative to parsing Python)
    pub fn addTableDecl(self: *Self, name: []const u8, path: []const u8) !void {
        try self.table_decls.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .path = try self.allocator.dupe(u8, path),
        });
    }

    /// Add a method declaration manually
    pub fn addMethod(self: *Self, name: []const u8, deps: []const []const u8) !void {
        try self.methods.append(self.allocator, .{
            .name = try self.allocator.dupe(u8, name),
            .deps = deps,
        });
    }

    /// Register a compiled method function pointer
    pub fn registerMethod(
        self: *Self,
        class_name: []const u8,
        method_name: []const u8,
        fn_ptr: *const anyopaque,
        num_array_params: u8,
    ) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class_name, method_name });
        errdefer self.allocator.free(key);

        try self.registered_methods.put(key, .{
            .name = method_name,
            .class_name = class_name,
            .fn_ptr = fn_ptr,
            .num_array_params = num_array_params,
        });
    }

    /// Register a method with batch processing support
    pub fn registerMethodWithBatch(
        self: *Self,
        class_name: []const u8,
        method_name: []const u8,
        fn_ptr: *const anyopaque,
        num_array_params: u8,
        batch_fn_ptr: *const anyopaque,
        batch_uses_f32: bool,
    ) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class_name, method_name });
        errdefer self.allocator.free(key);

        try self.registered_methods.put(key, .{
            .name = method_name,
            .class_name = class_name,
            .fn_ptr = fn_ptr,
            .num_array_params = num_array_params,
            .batch_fn_ptr = batch_fn_ptr,
            .supports_batch = true,
            .batch_uses_f32 = batch_uses_f32,
        });
    }

    /// Call method returning batch output (N inputs → N outputs)
    /// Automatically uses batch function if available, otherwise falls back to per-row
    pub fn callMethodBatchOutput(
        self: *Self,
        class_name: []const u8,
        method_name: []const u8,
        input_data_f64: ?[]const f64, // Flattened [N × dim] as f64
        input_data_f32: ?[]const f32, // Flattened [N × dim] as f32
        query_vec: []const f64, // Query vector [dim]
        num_rows: usize,
        dim: usize,
    ) ![]f64 {
        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class_name, method_name });
        defer self.allocator.free(key);

        const method = self.registered_methods.get(key) orelse
            return LogicTableError.MethodNotFound;

        // Allocate output
        var results = try self.allocator.alloc(f64, num_rows);
        errdefer self.allocator.free(results);

        // Use batch function if available
        if (method.batch_fn_ptr) |batch_fn| {
            if (method.batch_uses_f32) {
                // Batch with f32 input matrix
                const fn_ptr: BatchMethodFnF32 = @ptrCast(@alignCast(batch_fn));
                const input = input_data_f32 orelse return LogicTableError.TypeMismatch;
                _ = fn_ptr(input.ptr, query_vec.ptr, @intCast(num_rows), @intCast(dim), results.ptr);
            } else {
                // Batch with f64 input matrix
                const fn_ptr: BatchMethodFn = @ptrCast(@alignCast(batch_fn));
                const input = input_data_f64 orelse return LogicTableError.TypeMismatch;
                _ = fn_ptr(input.ptr, query_vec.ptr, @intCast(num_rows), @intCast(dim), results.ptr);
            }
        } else {
            // Fallback: call scalar method per-row (slow but compatible)
            const input = input_data_f64 orelse return LogicTableError.TypeMismatch;
            const scalar_fn: MethodFnF64 = @ptrCast(@alignCast(method.fn_ptr));
            for (0..num_rows) |i| {
                const row_start = i * dim;
                const row_end = row_start + dim;
                results[i] = scalar_fn(
                    input[row_start..row_end].ptr,
                    query_vec.ptr,
                    dim,
                );
            }
        }

        return results;
    }

    /// Check if a method supports batch processing
    pub fn methodSupportsBatch(self: *Self, class_name: []const u8, method_name: []const u8) bool {
        const key = std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class_name, method_name }) catch return false;
        defer self.allocator.free(key);

        const method = self.registered_methods.get(key) orelse return false;
        return method.supports_batch;
    }

    /// Load all declared tables from Lance files
    pub fn loadTables(self: *Self) !void {
        for (self.table_decls.items) |decl| {
            try self.loadTable(decl);
        }
    }

    /// Get the primary (first) loaded table for SQL execution
    /// Returns null if no tables are loaded
    pub fn getPrimaryTable(self: *Self) ?*Table {
        // Return the first loaded table
        var iter = self.loaded_tables.valueIterator();
        if (iter.next()) |loaded| {
            return loaded.table;
        }
        return null;
    }

    /// Load a single table
    fn loadTable(self: *Self, decl: TableDecl) !void {
        // Resolve path relative to Python file
        const full_path = try std.fs.path.join(self.allocator, &.{ self.base_dir, decl.path });
        defer self.allocator.free(full_path);

        // Read file
        const file = std.fs.cwd().openFile(full_path, .{}) catch |err| {
            std.debug.print("Failed to open Lance file: {s} (error: {})\n", .{ full_path, err });
            return LogicTableError.TableNotFound;
        };
        defer file.close();

        const file_size = try file.getEndPos();
        const data = try self.allocator.alloc(u8, file_size);
        _ = try file.readAll(data);

        // Initialize Table
        const table = try self.allocator.create(Table);
        table.* = Table.init(self.allocator, data) catch |err| {
            std.debug.print("Failed to parse Lance file: {s} (error: {})\n", .{ full_path, err });
            return LogicTableError.InvalidLogicTable;
        };

        try self.loaded_tables.put(decl.name, .{
            .decl = decl,
            .table = table,
            .columns = std.StringHashMap(LoadedTable.ColumnData).init(self.allocator),
        });
    }

    /// Load a specific column from a table and bind to context
    pub fn loadColumn(self: *Self, table_name: []const u8, column_name: []const u8) !void {
        const loaded = self.loaded_tables.getPtr(table_name) orelse
            return LogicTableError.TableNotFound;

        const table = loaded.table;

        // Find column index by name
        const col_idx_usize = table.columnIndex(column_name) orelse
            return LogicTableError.ColumnNotFound;
        const col_idx: u32 = @intCast(col_idx_usize);

        // Get field to determine type
        const field = table.getField(col_idx_usize) orelse
            return LogicTableError.ColumnNotFound;

        // Determine column type from logical_type string
        if (std.mem.eql(u8, field.logical_type, "float") or
            std.mem.eql(u8, field.logical_type, "float32"))
        {
            const data = table.readFloat32Column(col_idx) catch
                return LogicTableError.ColumnNotFound;
            try loaded.columns.put(column_name, .{ .f32 = data });
            try self.ctx.bindF32(table_name, column_name, data);
        } else if (std.mem.eql(u8, field.logical_type, "double") or
            std.mem.eql(u8, field.logical_type, "float64"))
        {
            const data = table.readFloat64Column(col_idx) catch
                return LogicTableError.ColumnNotFound;
            try loaded.columns.put(column_name, .{ .f64 = data });
            // Note: LogicTableContext currently only has f32 and i64
        } else if (std.mem.eql(u8, field.logical_type, "int64") or
            std.mem.eql(u8, field.logical_type, "long"))
        {
            const data = table.readInt64Column(col_idx) catch
                return LogicTableError.ColumnNotFound;
            try loaded.columns.put(column_name, .{ .i64 = data });
            try self.ctx.bindI64(table_name, column_name, data);
        } else if (std.mem.eql(u8, field.logical_type, "int32") or
            std.mem.eql(u8, field.logical_type, "int"))
        {
            const data = table.readInt32Column(col_idx) catch
                return LogicTableError.ColumnNotFound;
            try loaded.columns.put(column_name, .{ .i32 = data });
        } else {
            return LogicTableError.TypeMismatch;
        }
    }

    /// Call a registered method in batch mode (all rows)
    pub fn callMethodBatch(
        self: *Self,
        class_name: []const u8,
        method_name: []const u8,
        args: anytype,
    ) !f64 {
        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class_name, method_name });
        defer self.allocator.free(key);

        const method = self.registered_methods.get(key) orelse
            return LogicTableError.MethodNotFound;

        // Call based on number of array parameters
        switch (method.num_array_params) {
            2 => {
                // Two array params (e.g., dot_product(a, b))
                const fn_ptr: MethodFnF64 = @ptrCast(@alignCast(method.fn_ptr));
                const a = args[0];
                const b = args[1];
                const len = args[2];
                return fn_ptr(a, b, len);
            },
            1 => {
                // Single array param (e.g., sum_squares(a))
                const fn_ptr: MethodFnF64Single = @ptrCast(@alignCast(method.fn_ptr));
                const a = args[0];
                const len = args[1];
                return fn_ptr(a, len);
            },
            else => return LogicTableError.MethodNotFound,
        }
    }

    /// Get column data from context
    pub fn getColumnF32(self: *const Self, table_name: []const u8, column_name: []const u8) ![]const f32 {
        return self.ctx.getF32(table_name, column_name);
    }

    pub fn getColumnI64(self: *const Self, table_name: []const u8, column_name: []const u8) ![]const i64 {
        return self.ctx.getI64(table_name, column_name);
    }

    /// Get row count from first loaded table
    pub fn getRowCount(self: *const Self) usize {
        var iter = self.loaded_tables.iterator();
        if (iter.next()) |entry| {
            // Use first column to get row count
            return entry.value_ptr.table.rowCount(0) catch 0;
        }
        return 0;
    }

    /// Get LogicTableContext for direct access
    pub fn getContext(self: *Self) *LogicTableContext {
        return &self.ctx;
    }

    /// Get metadata about this logic_table
    pub fn getMeta(self: *const Self) LogicTableMeta {
        return .{
            .name = self.class_name,
            .methods = self.methods.items,
        };
    }
};

// =============================================================================
// Extern declarations for compiled @logic_table methods
// These come from lib/vector_ops.a (linked at build time)
// =============================================================================

// VectorOps class methods (scalar - single result)
pub extern fn VectorOps_dot_product(a: [*]const f64, b: [*]const f64, len: usize) callconv(.c) f64;
pub extern fn VectorOps_sum_squares(a: [*]const f64, len: usize) callconv(.c) f64;

// VectorOps batch methods (N inputs → N outputs)
// Returns i64 (dummy 0 value, results are in out array)
pub extern fn VectorOps_batch_dot_product(
    matrix: [*]const f64,
    vec: [*]const f64,
    num_rows: i64,
    dim: i64,
    out: [*]f64,
) callconv(.c) i64;

pub extern fn VectorOps_batch_dot_product_f32(
    matrix: [*]const f32,
    vec: [*]const f64,
    num_rows: i64,
    dim: i64,
    out: [*]f64,
) callconv(.c) i64;

// =============================================================================
// Convenience functions for common patterns
// =============================================================================

/// Create executor with VectorOps methods pre-registered
pub fn createVectorOpsExecutor(allocator: std.mem.Allocator) !LogicTableExecutor {
    var exec = try LogicTableExecutor.init(allocator, "vector_ops.py");

    // Register scalar methods
    try exec.registerMethod("VectorOps", "dot_product", @ptrCast(&VectorOps_dot_product), 2);
    try exec.registerMethod("VectorOps", "sum_squares", @ptrCast(&VectorOps_sum_squares), 1);

    // Register batch methods with batch function pointers
    try exec.registerMethodWithBatch(
        "VectorOps",
        "batch_dot_product",
        @ptrCast(&VectorOps_dot_product), // fallback scalar
        2,
        @ptrCast(&VectorOps_batch_dot_product), // batch function
        false, // uses f64
    );
    try exec.registerMethodWithBatch(
        "VectorOps",
        "batch_dot_product_f32",
        @ptrCast(&VectorOps_dot_product), // fallback scalar
        2,
        @ptrCast(&VectorOps_batch_dot_product_f32), // batch function (f32 input)
        true, // uses f32
    );

    try exec.addMethod("dot_product", &.{ "a", "b" });
    try exec.addMethod("sum_squares", &.{"a"});
    try exec.addMethod("batch_dot_product", &.{ "matrix", "vec", "num_rows", "dim", "out" });
    try exec.addMethod("batch_dot_product_f32", &.{ "matrix", "vec", "num_rows", "dim", "out" });

    return exec;
}

// =============================================================================
// Tests
// =============================================================================

test "LogicTableExecutor basic" {
    const allocator = std.testing.allocator;

    var executor = try LogicTableExecutor.init(allocator, "test.py");
    defer executor.deinit();

    // Add table declaration
    try executor.addTableDecl("orders", "orders.lance");

    try std.testing.expectEqual(@as(usize, 1), executor.table_decls.items.len);
    try std.testing.expectEqualStrings("orders", executor.table_decls.items[0].name);
}

test "LogicTableExecutor path resolution" {
    const allocator = std.testing.allocator;

    // Test with subdirectory
    var executor = try LogicTableExecutor.init(allocator, "examples/fraud_detector.py");
    defer executor.deinit();

    try std.testing.expectEqualStrings("examples", executor.base_dir);
}

test "Python parsing - extractClassName" {
    const allocator = std.testing.allocator;

    var executor = try LogicTableExecutor.init(allocator, "test.py");
    defer executor.deinit();

    // Test extractClassName with valid content
    const content =
        \\from lanceql import logic_table, Table
        \\
        \\@logic_table
        \\class FraudDetector:
        \\    orders = Table("orders.lance")
    ;

    const class_name = try executor.extractClassName(content);
    defer allocator.free(class_name);

    try std.testing.expectEqualStrings("FraudDetector", class_name);
}

test "Python parsing - extractTableDecls" {
    const allocator = std.testing.allocator;

    var executor = try LogicTableExecutor.init(allocator, "test.py");
    defer executor.deinit();

    const content =
        \\@logic_table
        \\class FraudDetector:
        \\    orders = Table("orders.lance")
        \\    customers = Table('customers.lance')
        \\
        \\    def risk_score(self):
        \\        return 0.5
    ;

    try executor.extractTableDecls(content);

    try std.testing.expectEqual(@as(usize, 2), executor.table_decls.items.len);
    try std.testing.expectEqualStrings("orders", executor.table_decls.items[0].name);
    try std.testing.expectEqualStrings("orders.lance", executor.table_decls.items[0].path);
    try std.testing.expectEqualStrings("customers", executor.table_decls.items[1].name);
    try std.testing.expectEqualStrings("customers.lance", executor.table_decls.items[1].path);
}

test "Python parsing - extractMethods" {
    const allocator = std.testing.allocator;

    var executor = try LogicTableExecutor.init(allocator, "test.py");
    defer executor.deinit();

    const content =
        \\@logic_table
        \\class FraudDetector:
        \\    def __init__(self):
        \\        pass
        \\
        \\    def risk_score(self):
        \\        return 0.5
        \\
        \\    def _private_method(self):
        \\        pass
        \\
        \\    def calculate_velocity(self, window_days=30):
        \\        return 0.1
    ;

    try executor.extractMethods(content);

    // Should only extract risk_score and calculate_velocity (not __init__ or _private_method)
    try std.testing.expectEqual(@as(usize, 2), executor.methods.items.len);
    try std.testing.expectEqualStrings("risk_score", executor.methods.items[0].name);
    try std.testing.expectEqualStrings("calculate_velocity", executor.methods.items[1].name);
}

test "isValidPythonIdent" {
    try std.testing.expect(LogicTableExecutor.isValidPythonIdent("valid_name"));
    try std.testing.expect(LogicTableExecutor.isValidPythonIdent("_private"));
    try std.testing.expect(LogicTableExecutor.isValidPythonIdent("CamelCase"));
    try std.testing.expect(LogicTableExecutor.isValidPythonIdent("name123"));
    try std.testing.expect(!LogicTableExecutor.isValidPythonIdent(""));
    try std.testing.expect(!LogicTableExecutor.isValidPythonIdent("123name"));
    try std.testing.expect(!LogicTableExecutor.isValidPythonIdent("name-with-dash"));
    try std.testing.expect(!LogicTableExecutor.isValidPythonIdent("name with space"));
}
