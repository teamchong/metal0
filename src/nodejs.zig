//! Node.js C API for LanceQL
//!
//! This module provides C-compatible exports for Node.js N-API bindings.
//! It follows the same patterns as python.zig but adds SQL execution capabilities.

const std = @import("std");
const Table = @import("lanceql.table").Table;
const ast = @import("lanceql.sql.ast");
const parser = @import("lanceql.sql.parser");
const executor = @import("lanceql.sql.executor");

// ============================================================================
// Opaque Handle Types
// ============================================================================

pub const Handle = opaque {}; // Table handle
pub const SQLHandle = opaque {}; // Parsed SQL statement
pub const ResultHandle = opaque {}; // Query result

/// Global allocator for all Node.js API operations
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// ============================================================================
// Global State for Handle Management
// ============================================================================

var tables_lock = std.Thread.Mutex{};
var tables = std.AutoHashMap(*Handle, *Table).init(allocator);

var statements_lock = std.Thread.Mutex{};
var statements = std.AutoHashMap(*SQLHandle, *Statement).init(allocator);

var results_lock = std.Thread.Mutex{};
var results = std.AutoHashMap(*ResultHandle, *executor.Result).init(allocator);

const Statement = struct {
    stmt: ast.SelectStmt,
    table_handle: *Handle,
    allocator: std.mem.Allocator,
    sql_copy: []const u8, // Owned copy of SQL string to keep AST slices valid
};

// ============================================================================
// Handle Conversion Functions
// ============================================================================

fn tableToHandle(table: *Table) *Handle {
    return @ptrCast(table);
}

fn handleToTable(handle: *Handle) *Table {
    return @ptrCast(@alignCast(handle));
}

fn stmtToHandle(stmt: *Statement) *SQLHandle {
    return @ptrCast(stmt);
}

fn handleToStmt(handle: *SQLHandle) *Statement {
    return @ptrCast(@alignCast(handle));
}

fn resultToHandle(result: *executor.Result) *ResultHandle {
    return @ptrCast(result);
}

fn handleToResult(handle: *ResultHandle) *executor.Result {
    return @ptrCast(@alignCast(handle));
}

// ============================================================================
// File & Table Management
// ============================================================================

/// Open a Lance file from a file path.
/// Supports both:
/// - Direct .lance data file paths (e.g., path/to/file.lance)
/// - Lance dataset directories (e.g., path/to/dataset.lance/) which contain _versions/, _transactions/, and data/
export fn lance_open(path_ptr: [*]const u8, path_len: usize) ?*Handle {
    const path = path_ptr[0..path_len];

    // Check if path is a directory by trying to stat it
    const stat = std.fs.cwd().statFile(path) catch {
        // Path doesn't exist or can't be accessed
        return null;
    };

    if (stat.kind == .directory) {
        // It's a directory, try to open as Lance dataset
        return openLanceDataset(path);
    }

    // It's a file, open it directly
    var file = std.fs.cwd().openFile(path, .{}) catch return null;
    defer file.close();

    const data = file.readToEndAlloc(allocator, 100 * 1024 * 1024) catch return null; // Max 100MB

    // Create Table
    const table_ptr = allocator.create(Table) catch return null;
    table_ptr.* = Table.init(allocator, data) catch {
        allocator.free(data);
        allocator.destroy(table_ptr);
        return null;
    };

    const handle = tableToHandle(table_ptr);

    // Store in global map
    tables_lock.lock();
    defer tables_lock.unlock();
    tables.put(handle, table_ptr) catch {
        table_ptr.deinit();
        allocator.free(data);
        allocator.destroy(table_ptr);
        return null;
    };

    return handle;
}

/// Open a Lance dataset directory by finding the latest data file via manifest
fn openLanceDataset(base_path: []const u8) ?*Handle {
    // Lance datasets have structure:
    // dataset.lance/
    //   _versions/
    //     1.manifest (or higher numbered)
    //   _transactions/
    //   data/
    //     {hash}.lance (actual data file)

    // First, try to directly scan the data directory for .lance files
    // This is a simpler approach that works without parsing the manifest
    var data_path_buf: [4096]u8 = undefined;

    // bufPrint returns a slice that needs null termination for C interop
    const data_path_len = std.fmt.bufPrint(&data_path_buf, "{s}/data", .{base_path}) catch return null;
    data_path_buf[data_path_len.len] = 0; // null terminate

    var data_dir = std.fs.cwd().openDir(data_path_len, .{ .iterate = true }) catch return null;
    defer data_dir.close();

    // Find first .lance file in data directory
    var data_iter = data_dir.iterate();
    while (data_iter.next() catch null) |entry| {
        if (entry.kind != .file) continue;

        if (std.mem.endsWith(u8, entry.name, ".lance")) {
            // Found a data file - use dir.openFile directly instead of building path
            var file = data_dir.openFile(entry.name, .{}) catch continue;
            defer file.close();

            const data = file.readToEndAlloc(allocator, 100 * 1024 * 1024) catch continue;

            // Create Table
            const table_ptr = allocator.create(Table) catch {
                allocator.free(data);
                return null;
            };

            table_ptr.* = Table.init(allocator, data) catch {
                allocator.free(data);
                allocator.destroy(table_ptr);
                return null;
            };

            const handle = tableToHandle(table_ptr);

            // Store in global map
            tables_lock.lock();
            defer tables_lock.unlock();
            tables.put(handle, table_ptr) catch {
                table_ptr.deinit();
                allocator.free(data);
                allocator.destroy(table_ptr);
                return null;
            };

            return handle;
        }
    }

    return null;
}

/// Open a Lance file from a memory buffer
export fn lance_open_memory(data: [*]const u8, len: usize) ?*Handle {
    const buffer = data[0..len];

    // Copy buffer data (Node.js Buffer might be temporary)
    const owned_data = allocator.alloc(u8, len) catch return null;
    @memcpy(owned_data, buffer);

    // Create Table
    const table_ptr = allocator.create(Table) catch {
        allocator.free(owned_data);
        return null;
    };

    table_ptr.* = Table.init(allocator, owned_data) catch {
        allocator.free(owned_data);
        allocator.destroy(table_ptr);
        return null;
    };

    const handle = tableToHandle(table_ptr);

    // Store in global map
    tables_lock.lock();
    defer tables_lock.unlock();
    tables.put(handle, table_ptr) catch {
        table_ptr.deinit();
        allocator.free(owned_data);
        allocator.destroy(table_ptr);
        return null;
    };

    return handle;
}

/// Close a Lance file and free resources
export fn lance_close(handle: *Handle) void {
    tables_lock.lock();
    defer tables_lock.unlock();

    if (tables.fetchRemove(handle)) |entry| {
        const table_ptr = entry.value;
        table_ptr.deinit();
        allocator.destroy(table_ptr);
    }
}

// ============================================================================
// Table Metadata
// ============================================================================

/// Get the number of columns in the table
export fn lance_column_count(handle: *Handle) u32 {
    const table = handleToTable(handle);
    return table.numColumns();
}

/// Get the number of rows for a specific column
export fn lance_row_count(handle: *Handle, col_idx: u32) u64 {
    const table = handleToTable(handle);
    return table.rowCount(@intCast(col_idx)) catch 0;
}

/// Get a column name (returns length of name written to buffer)
export fn lance_column_name(handle: *Handle, col_idx: u32, buf: [*]u8, buf_len: usize) usize {
    const table = handleToTable(handle);
    const names = table.columnNames() catch return 0;
    defer allocator.free(names);

    if (col_idx >= names.len) return 0;

    const name = names[col_idx];
    const len = @min(name.len, buf_len);
    const out_buf = buf[0..buf_len];
    @memcpy(out_buf[0..len], name[0..len]);

    return len;
}

/// Get a column type (returns length of type string written to buffer)
export fn lance_column_type(handle: *Handle, col_idx: u32, buf: [*]u8, buf_len: usize) usize {
    const table = handleToTable(handle);
    const field = table.getField(@intCast(col_idx)) orelse return 0;

    const type_str = field.logical_type;
    const len = @min(type_str.len, buf_len);
    const out_buf = buf[0..buf_len];
    @memcpy(out_buf[0..len], type_str[0..len]);

    return len;
}

// ============================================================================
// SQL Query API
// ============================================================================

/// Parse SQL and return a statement handle
export fn lance_sql_parse(sql_ptr: [*]const u8, sql_len: usize, handle: *Handle) ?*SQLHandle {
    // Copy the SQL string so AST slices remain valid after JS releases the string
    const sql_copy = allocator.alloc(u8, sql_len) catch return null;
    @memcpy(sql_copy, sql_ptr[0..sql_len]);

    // Parse SQL using our owned copy
    const stmt = parser.parseSQL(sql_copy, allocator) catch {
        allocator.free(sql_copy);
        return null;
    };

    // Only SELECT is supported for now
    if (stmt != .select) {
        allocator.free(sql_copy);
        return null;
    }

    // Create Statement wrapper
    const stmt_ptr = allocator.create(Statement) catch {
        allocator.free(sql_copy);
        return null;
    };
    stmt_ptr.* = Statement{
        .stmt = stmt.select,
        .table_handle = handle,
        .allocator = allocator,
        .sql_copy = sql_copy,
    };

    const sql_handle = stmtToHandle(stmt_ptr);

    // Store in global map
    statements_lock.lock();
    defer statements_lock.unlock();
    statements.put(sql_handle, stmt_ptr) catch {
        allocator.destroy(stmt_ptr);
        return null;
    };

    return sql_handle;
}

/// Execute a parsed SQL statement
export fn lance_sql_execute(sql_handle: *SQLHandle, handle: *Handle) ?*ResultHandle {
    _ = handle; // Table handle is stored in Statement

    statements_lock.lock();
    const stmt_ptr = statements.get(sql_handle);
    statements_lock.unlock();

    if (stmt_ptr == null) return null;
    const stmt = stmt_ptr.?;

    // Get table from handle
    tables_lock.lock();
    const table_ptr = tables.get(stmt.table_handle);
    tables_lock.unlock();

    if (table_ptr == null) return null;

    // Execute query
    var exec = executor.Executor.init(table_ptr.?, allocator);
    defer exec.deinit();

    const result_ptr = allocator.create(executor.Result) catch return null;
    result_ptr.* = exec.execute(&stmt.stmt, &[_]ast.Value{}) catch {
        allocator.destroy(result_ptr);
        return null;
    };

    const result_handle = resultToHandle(result_ptr);

    // Store in global map
    results_lock.lock();
    defer results_lock.unlock();
    results.put(result_handle, result_ptr) catch {
        result_ptr.deinit();
        allocator.destroy(result_ptr);
        return null;
    };

    return result_handle;
}

/// Execute a parsed SQL statement with parameters
/// param_types: array of type codes: 'i' = int64, 'f' = float64, 's' = string, 'n' = null
/// param_count: number of parameters
/// int_params: array of int64 values (indexed by position in param_types where type='i')
/// float_params: array of float64 values (indexed by position in param_types where type='f')
/// string_ptrs: array of string pointers (indexed by position in param_types where type='s')
/// string_lens: array of string lengths (indexed by position in param_types where type='s')
export fn lance_sql_execute_params(
    sql_handle: *SQLHandle,
    handle: *Handle,
    param_types: [*]const u8,
    param_count: u32,
    int_params: [*]const i64,
    float_params: [*]const f64,
    string_ptrs: [*]const [*]const u8,
    string_lens: [*]const usize,
) ?*ResultHandle {
    _ = handle; // Table handle is stored in Statement

    statements_lock.lock();
    const stmt_ptr = statements.get(sql_handle);
    statements_lock.unlock();

    if (stmt_ptr == null) return null;
    const stmt = stmt_ptr.?;

    // Get table from handle
    tables_lock.lock();
    const table_ptr = tables.get(stmt.table_handle);
    tables_lock.unlock();

    if (table_ptr == null) return null;

    // Build Value array from parameters
    const params = allocator.alloc(ast.Value, param_count) catch return null;
    defer allocator.free(params);

    var int_idx: usize = 0;
    var float_idx: usize = 0;
    var str_idx: usize = 0;

    for (0..param_count) |i| {
        params[i] = switch (param_types[i]) {
            'i' => blk: {
                const v = int_params[int_idx];
                int_idx += 1;
                break :blk ast.Value{ .integer = v };
            },
            'f' => blk: {
                const v = float_params[float_idx];
                float_idx += 1;
                break :blk ast.Value{ .float = v };
            },
            's' => blk: {
                const ptr = string_ptrs[str_idx];
                const len = string_lens[str_idx];
                str_idx += 1;
                break :blk ast.Value{ .string = ptr[0..len] };
            },
            'n' => ast.Value{ .null = {} },
            else => return null,
        };
    }

    // Execute query with parameters
    var exec = executor.Executor.init(table_ptr.?, allocator);
    defer exec.deinit();

    const result_ptr = allocator.create(executor.Result) catch return null;
    result_ptr.* = exec.execute(&stmt.stmt, params) catch {
        allocator.destroy(result_ptr);
        return null;
    };

    const result_handle = resultToHandle(result_ptr);

    // Store in global map
    results_lock.lock();
    defer results_lock.unlock();
    results.put(result_handle, result_ptr) catch {
        result_ptr.deinit();
        allocator.destroy(result_ptr);
        return null;
    };

    return result_handle;
}

/// Close a SQL statement and free resources
export fn lance_sql_close(sql_handle: *SQLHandle) void {
    statements_lock.lock();
    defer statements_lock.unlock();

    if (statements.fetchRemove(sql_handle)) |entry| {
        const stmt_ptr = entry.value;
        // Free all AST allocations (columns, where, group_by, order_by)
        ast.deinitSelectStmt(&stmt_ptr.stmt, stmt_ptr.allocator);
        // Free the SQL string copy
        allocator.free(stmt_ptr.sql_copy);
        allocator.destroy(stmt_ptr);
    }
}

// ============================================================================
// Result Access
// ============================================================================

/// Get the number of rows in the result
export fn lance_result_row_count(result: *ResultHandle) usize {
    results_lock.lock();
    defer results_lock.unlock();

    const result_ptr = results.get(result) orelse return 0;
    return result_ptr.row_count;
}

/// Get the number of columns in the result
export fn lance_result_column_count(result: *ResultHandle) usize {
    results_lock.lock();
    defer results_lock.unlock();

    const result_ptr = results.get(result) orelse return 0;
    return result_ptr.columns.len;
}

/// Get a column name from the result
export fn lance_result_column_name(result: *ResultHandle, col_idx: u32, buf: [*]u8, buf_len: usize) usize {
    results_lock.lock();
    defer results_lock.unlock();

    const result_ptr = results.get(result) orelse return 0;
    if (col_idx >= result_ptr.columns.len) return 0;

    const name = result_ptr.columns[col_idx].name;
    const len = @min(name.len, buf_len);
    const out_buf = buf[0..buf_len];
    @memcpy(out_buf[0..len], name[0..len]);

    return len;
}

/// Get a column type from the result (0=int64, 1=float64, 2=string, 3=int32, 4=float32, 5=bool)
export fn lance_result_column_type(result: *ResultHandle, col_idx: u32) u32 {
    results_lock.lock();
    defer results_lock.unlock();

    const result_ptr = results.get(result) orelse return 999; // Invalid
    if (col_idx >= result_ptr.columns.len) return 999;

    const col = result_ptr.columns[col_idx];
    // Type codes: 0=int64, 1=float64, 2=string, 3=int32, 4=float32, 5=bool,
    //             6=timestamp_s, 7=timestamp_ms, 8=timestamp_us, 9=timestamp_ns,
    //             10=date32, 11=date64
    return switch (col.data) {
        .int64 => 0,
        .float64 => 1,
        .string => 2,
        .int32 => 3,
        .float32 => 4,
        .bool_ => 5,
        .timestamp_s => 6,
        .timestamp_ms => 7,
        .timestamp_us => 8,
        .timestamp_ns => 9,
        .date32 => 10,
        .date64 => 11,
    };
}

// ============================================================================
// Data Extraction
// ============================================================================

/// Read int64 column data
export fn lance_result_read_int64(result: *ResultHandle, col_idx: u32, out: [*]i64, max_count: usize) usize {
    results_lock.lock();
    defer results_lock.unlock();

    const result_ptr = results.get(result) orelse return 0;
    if (col_idx >= result_ptr.columns.len) return 0;

    const col = result_ptr.columns[col_idx];
    if (col.data != .int64) return 0;

    const data = col.data.int64;
    const count = @min(data.len, max_count);
    const out_buf = out[0..count];
    @memcpy(out_buf, data[0..count]);

    return count;
}

/// Read float64 column data
export fn lance_result_read_float64(result: *ResultHandle, col_idx: u32, out: [*]f64, max_count: usize) usize {
    results_lock.lock();
    defer results_lock.unlock();

    const result_ptr = results.get(result) orelse return 0;
    if (col_idx >= result_ptr.columns.len) return 0;

    const col = result_ptr.columns[col_idx];
    if (col.data != .float64) return 0;

    const data = col.data.float64;
    const count = @min(data.len, max_count);
    const out_buf = out[0..count];
    @memcpy(out_buf, data[0..count]);

    return count;
}

/// Read string column data (parallel arrays of pointers and lengths)
export fn lance_result_read_string(
    result: *ResultHandle,
    col_idx: u32,
    out_strings: [*][*]const u8,
    out_lengths: [*]usize,
    max_count: usize,
) usize {
    results_lock.lock();
    defer results_lock.unlock();

    const result_ptr = results.get(result) orelse return 0;
    if (col_idx >= result_ptr.columns.len) return 0;

    const col = result_ptr.columns[col_idx];
    if (col.data != .string) return 0;

    const data = col.data.string;
    const count = @min(data.len, max_count);

    for (0..count) |i| {
        out_strings[i] = data[i].ptr;
        out_lengths[i] = data[i].len;
    }

    return count;
}

/// Read int32 column data
export fn lance_result_read_int32(result: *ResultHandle, col_idx: u32, out: [*]i32, max_count: usize) usize {
    results_lock.lock();
    defer results_lock.unlock();

    const result_ptr = results.get(result) orelse return 0;
    if (col_idx >= result_ptr.columns.len) return 0;

    const col = result_ptr.columns[col_idx];
    if (col.data != .int32) return 0;

    const data = col.data.int32;
    const count = @min(data.len, max_count);
    const out_buf = out[0..count];
    @memcpy(out_buf, data[0..count]);

    return count;
}

/// Read float32 column data
export fn lance_result_read_float32(result: *ResultHandle, col_idx: u32, out: [*]f32, max_count: usize) usize {
    results_lock.lock();
    defer results_lock.unlock();

    const result_ptr = results.get(result) orelse return 0;
    if (col_idx >= result_ptr.columns.len) return 0;

    const col = result_ptr.columns[col_idx];
    if (col.data != .float32) return 0;

    const data = col.data.float32;
    const count = @min(data.len, max_count);
    const out_buf = out[0..count];
    @memcpy(out_buf, data[0..count]);

    return count;
}

/// Read bool column data (as u8: 0=false, 1=true)
export fn lance_result_read_bool(result: *ResultHandle, col_idx: u32, out: [*]u8, max_count: usize) usize {
    results_lock.lock();
    defer results_lock.unlock();

    const result_ptr = results.get(result) orelse return 0;
    if (col_idx >= result_ptr.columns.len) return 0;

    const col = result_ptr.columns[col_idx];
    if (col.data != .bool_) return 0;

    const data = col.data.bool_;
    const count = @min(data.len, max_count);
    const out_buf = out[0..count];
    for (data[0..count], 0..) |b, i| {
        out_buf[i] = if (b) 1 else 0;
    }

    return count;
}

/// Close a result and free resources
export fn lance_result_close(result: *ResultHandle) void {
    results_lock.lock();
    defer results_lock.unlock();

    if (results.fetchRemove(result)) |entry| {
        const result_ptr = entry.value;
        result_ptr.deinit();
        allocator.destroy(result_ptr);
    }
}

// ============================================================================
// Additional APIs (better-sqlite3 compatibility)
// ============================================================================

/// Get version string
export fn lance_version(buf: [*]u8, buf_len: usize) usize {
    const version = "0.1.0-lanceql";
    const len = @min(version.len, buf_len);
    const out_buf = buf[0..buf_len];
    @memcpy(out_buf[0..len], version[0..len]);
    return len;
}

/// Execute SQL (stub for better-sqlite3 compatibility - ignores writes)
export fn lance_exec(handle: *Handle, sql_ptr: [*]const u8, sql_len: usize) bool {
    _ = handle;
    _ = sql_ptr;
    _ = sql_len;
    // For v0.1.0, just return true (no-op for CREATE/INSERT/UPDATE)
    return true;
}

/// Get table info as JSON (PRAGMA table_info equivalent)
export fn lance_pragma_table_info(handle: *Handle, buf: [*]u8, buf_len: usize) usize {
    const table = handleToTable(handle);
    const names = table.columnNames() catch return 0;
    defer allocator.free(names);

    // Build simple JSON array: [{"name": "col1", "type": "int64"}, ...]
    var json = std.ArrayList(u8){};
    defer json.deinit(allocator);

    json.appendSlice(allocator, "[") catch return 0;

    for (names, 0..) |name, i| {
        const field = table.getField(@intCast(i)) orelse continue;

        if (i > 0) json.appendSlice(allocator, ",") catch return 0;

        json.appendSlice(allocator, "{\"name\":\"") catch return 0;
        json.appendSlice(allocator, name) catch return 0;
        json.appendSlice(allocator, "\",\"type\":\"") catch return 0;
        json.appendSlice(allocator, field.logical_type) catch return 0;
        json.appendSlice(allocator, "\"}") catch return 0;
    }

    json.appendSlice(allocator, "]") catch return 0;

    const len = @min(json.items.len, buf_len);
    const out_buf = buf[0..buf_len];
    @memcpy(out_buf[0..len], json.items[0..len]);

    return len;
}

/// Transaction stubs (no-op for read-only Lance files)
export fn lance_transaction_begin(handle: *Handle) bool {
    _ = handle;
    return true; // No-op
}

export fn lance_transaction_commit(handle: *Handle) bool {
    _ = handle;
    return true; // No-op
}

export fn lance_transaction_rollback(handle: *Handle) bool {
    _ = handle;
    return true; // No-op
}

// ============================================================================
// Module Lifecycle
// ============================================================================

/// Cleanup all resources when the module is unloaded.
/// Call this from Node.js module unload handler.
export fn lance_cleanup() void {
    // Close all open tables
    tables_lock.lock();
    defer tables_lock.unlock();
    var table_iter = tables.iterator();
    while (table_iter.next()) |entry| {
        const table_ptr = entry.value_ptr.*;
        table_ptr.deinit();
        allocator.destroy(table_ptr);
    }
    tables.clearAndFree();

    // Close all statements
    statements_lock.lock();
    defer statements_lock.unlock();
    var stmt_iter = statements.iterator();
    while (stmt_iter.next()) |entry| {
        const stmt_ptr = entry.value_ptr.*;
        // Free all AST allocations (columns, where, group_by, order_by)
        ast.deinitSelectStmt(&stmt_ptr.stmt, stmt_ptr.allocator);
        // Free the SQL string copy
        allocator.free(stmt_ptr.sql_copy);
        allocator.destroy(stmt_ptr);
    }
    statements.clearAndFree();

    // Close all results
    results_lock.lock();
    defer results_lock.unlock();
    var result_iter = results.iterator();
    while (result_iter.next()) |entry| {
        const result_ptr = entry.value_ptr.*;
        result_ptr.deinit();
        allocator.destroy(result_ptr);
    }
    results.clearAndFree();
}
