//! LogicTable Dispatch - Links SQL executor to compiled @logic_table methods
//!
//! This module provides the bridge between SQL execution and compiled Python
//! @logic_table methods. It handles:
//! - Registration of compiled extern functions
//! - Dynamic dispatch based on class/method names
//! - Method call execution with proper argument passing
//!
//! Example:
//! ```sql
//! SELECT t.risk_score(), orders.amount
//! FROM logic_table('fraud_detector.py') AS t
//! WHERE t.risk_score() > 0.7
//! ```

const std = @import("std");
const ast = @import("ast");
pub const logic_table = @import("lanceql.logic_table");

pub const LogicTableContext = logic_table.LogicTableContext;
pub const LogicTableExecutor = logic_table.LogicTableExecutor;

/// Error type for logic_table dispatch
pub const DispatchError = error{
    ClassNotFound,
    MethodNotFound,
    ArgumentCountMismatch,
    InvalidArgumentType,
    ExecutionFailed,
    OutputBufferNotInitialized,
    OutOfMemory,
};

// =============================================================================
// Batch-Vectorized Method Dispatch ABI
// =============================================================================

/// Column binding for batch method input
/// Provides named access to column data with type information
pub const ColumnBinding = struct {
    /// Column name (e.g., "amount", "customer_id")
    name: []const u8,
    /// Table alias (e.g., "orders", "t")
    table_alias: ?[]const u8,
    /// Actual column data
    data: ColumnData,

    pub const ColumnData = union(enum) {
        f64: []const f64,
        f32: []const f32,
        i64: []const i64,
        i32: []const i32,
        bool_: []const bool,
        string: []const []const u8,
    };

    /// Get row count from data
    pub fn len(self: ColumnBinding) usize {
        return switch (self.data) {
            .f64 => |d| d.len,
            .f32 => |d| d.len,
            .i64 => |d| d.len,
            .i32 => |d| d.len,
            .bool_ => |d| d.len,
            .string => |d| d.len,
        };
    }
};

/// Output buffer for batch method results
/// Pre-allocated by caller, filled by method
pub const ColumnBuffer = struct {
    f64: ?[]f64 = null,
    f32: ?[]f32 = null,
    i64: ?[]i64 = null,
    i32: ?[]i32 = null,
    bool_: ?[]bool = null,

    /// Initialize for f64 output
    pub fn initFloat64(allocator: std.mem.Allocator, len_val: usize) !ColumnBuffer {
        return .{ .f64 = try allocator.alloc(f64, len_val) };
    }

    /// Initialize for f32 output
    pub fn initFloat32(allocator: std.mem.Allocator, len_val: usize) !ColumnBuffer {
        return .{ .f32 = try allocator.alloc(f32, len_val) };
    }

    /// Initialize for i64 output
    pub fn initInt64(allocator: std.mem.Allocator, len_val: usize) !ColumnBuffer {
        return .{ .i64 = try allocator.alloc(i64, len_val) };
    }

    /// Initialize for bool output
    pub fn initBool(allocator: std.mem.Allocator, len_val: usize) !ColumnBuffer {
        return .{ .bool_ = try allocator.alloc(bool, len_val) };
    }

    /// Free allocated memory
    pub fn deinit(self: *ColumnBuffer, allocator: std.mem.Allocator) void {
        if (self.f64) |buf| allocator.free(buf);
        if (self.f32) |buf| allocator.free(buf);
        if (self.i64) |buf| allocator.free(buf);
        if (self.i32) |buf| allocator.free(buf);
        if (self.bool_) |buf| allocator.free(buf);
        self.* = .{};
    }

    /// Get output length
    pub fn len(self: ColumnBuffer) usize {
        if (self.f64) |buf| return buf.len;
        if (self.f32) |buf| return buf.len;
        if (self.i64) |buf| return buf.len;
        if (self.i32) |buf| return buf.len;
        if (self.bool_) |buf| return buf.len;
        return 0;
    }
};

/// Batch method function signature (C ABI)
/// This is the standard signature for all batch @logic_table methods
pub const BatchMethodFn = *const fn (
    /// Input column bindings
    inputs: [*]const ColumnBinding,
    num_inputs: usize,
    /// Row selection (null = all rows)
    selection: ?[*]const u32,
    selection_len: usize,
    /// Output buffer (pre-allocated)
    output: *ColumnBuffer,
    /// Query context for pushdown optimization
    ctx: ?*logic_table.QueryContext,
) callconv(.c) void;

/// Method function pointer types for C ABI
pub const MethodFnF64_2Args = *const fn ([*]const f64, [*]const f64, usize) callconv(.c) f64;
pub const MethodFnF64_1Arg = *const fn ([*]const f64, usize) callconv(.c) f64;
pub const MethodFnF64_NoArg = *const fn () callconv(.c) f64;

/// Registered method information
pub const RegisteredMethod = struct {
    class_name: []const u8,
    method_name: []const u8,
    fn_ptr: *const anyopaque,
    arg_count: u8,
    return_type: ReturnType,
    /// Method dispatch mode
    dispatch_mode: DispatchMode = .scalar,
    /// Input column names for batch methods
    input_columns: []const []const u8 = &.{},

    pub const ReturnType = enum {
        f64,
        f32,
        i64,
        bool_,
        void_, // For methods that write directly to output buffer
    };

    pub const DispatchMode = enum {
        /// Legacy scalar dispatch (callMethod0/1/2)
        scalar,
        /// Batch-vectorized dispatch (callMethodBatch)
        batch,
    };
};

/// LogicTable Dispatch Registry
/// Manages registered @logic_table classes and their methods
pub const Dispatcher = struct {
    allocator: std.mem.Allocator,
    /// Registered methods: "ClassName.method_name" -> RegisteredMethod
    methods: std.StringHashMap(RegisteredMethod),
    /// Logic table executors by alias
    executors: std.StringHashMap(*LogicTableExecutor),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .methods = std.StringHashMap(RegisteredMethod).init(allocator),
            .executors = std.StringHashMap(*LogicTableExecutor).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Free method keys
        var iter = self.methods.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.methods.deinit();

        // Free executor keys
        var exec_iter = self.executors.iterator();
        while (exec_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.executors.deinit();
    }

    /// Register a compiled method function pointer (scalar dispatch)
    pub fn registerMethod(
        self: *Self,
        class_name: []const u8,
        method_name: []const u8,
        fn_ptr: *const anyopaque,
        arg_count: u8,
    ) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class_name, method_name });
        errdefer self.allocator.free(key);

        try self.methods.put(key, .{
            .class_name = class_name,
            .method_name = method_name,
            .fn_ptr = fn_ptr,
            .arg_count = arg_count,
            .return_type = .f64,
        });
    }

    /// Register a batch-vectorized method function pointer
    pub fn registerBatchMethod(
        self: *Self,
        class_name: []const u8,
        method_name: []const u8,
        fn_ptr: BatchMethodFn,
        input_columns: []const []const u8,
        return_type: RegisteredMethod.ReturnType,
    ) !void {
        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ class_name, method_name });
        errdefer self.allocator.free(key);

        try self.methods.put(key, .{
            .class_name = class_name,
            .method_name = method_name,
            .fn_ptr = @ptrCast(fn_ptr),
            .arg_count = @intCast(input_columns.len),
            .return_type = return_type,
            .dispatch_mode = .batch,
            .input_columns = input_columns,
        });
    }

    /// Resolve a logic_table() table function
    /// Creates and registers a LogicTableExecutor for the given Python file
    pub fn resolveLogicTable(
        self: *Self,
        python_file: []const u8,
        alias: []const u8,
    ) !*LogicTableExecutor {
        // Check if already resolved
        if (self.executors.get(alias)) |exec| {
            return exec;
        }

        // Create new executor
        const exec = try self.allocator.create(LogicTableExecutor);
        exec.* = try LogicTableExecutor.init(self.allocator, python_file);

        // Store with alias
        const alias_copy = try self.allocator.dupe(u8, alias);
        errdefer self.allocator.free(alias_copy);
        try self.executors.put(alias_copy, exec);

        return exec;
    }

    /// Get executor by alias
    pub fn getExecutor(self: *Self, alias: []const u8) ?*LogicTableExecutor {
        return self.executors.get(alias);
    }

    /// Call a 0-argument method
    pub fn callMethod0(
        self: *Self,
        class_name: []const u8,
        method_name: []const u8,
    ) DispatchError!f64 {
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ class_name, method_name }) catch
            return DispatchError.MethodNotFound;

        const method = self.methods.get(key) orelse return DispatchError.MethodNotFound;

        if (method.arg_count != 0) return DispatchError.ArgumentCountMismatch;

        const fn_ptr: MethodFnF64_NoArg = @ptrCast(@alignCast(method.fn_ptr));
        return fn_ptr();
    }

    /// Call a 1-argument method (vector + len)
    pub fn callMethod1(
        self: *Self,
        class_name: []const u8,
        method_name: []const u8,
        a: [*]const f64,
        len: usize,
    ) DispatchError!f64 {
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ class_name, method_name }) catch
            return DispatchError.MethodNotFound;

        const method = self.methods.get(key) orelse return DispatchError.MethodNotFound;

        if (method.arg_count != 1) return DispatchError.ArgumentCountMismatch;

        const fn_ptr: MethodFnF64_1Arg = @ptrCast(@alignCast(method.fn_ptr));
        return fn_ptr(a, len);
    }

    /// Call a 2-argument method (two vectors + len)
    pub fn callMethod2(
        self: *Self,
        class_name: []const u8,
        method_name: []const u8,
        a: [*]const f64,
        b: [*]const f64,
        len: usize,
    ) DispatchError!f64 {
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ class_name, method_name }) catch
            return DispatchError.MethodNotFound;

        const method = self.methods.get(key) orelse return DispatchError.MethodNotFound;

        if (method.arg_count != 2) return DispatchError.ArgumentCountMismatch;

        const fn_ptr: MethodFnF64_2Args = @ptrCast(@alignCast(method.fn_ptr));
        return fn_ptr(a, b, len);
    }

    /// Call a batch-vectorized method
    /// This is the primary dispatch method for @logic_table batch execution
    pub fn callMethodBatch(
        self: *Self,
        class_name: []const u8,
        method_name: []const u8,
        inputs: []const ColumnBinding,
        selection: ?[]const u32,
        output: *ColumnBuffer,
        ctx: ?*logic_table.QueryContext,
    ) DispatchError!void {
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ class_name, method_name }) catch
            return DispatchError.MethodNotFound;

        const method = self.methods.get(key) orelse return DispatchError.MethodNotFound;

        // Verify this is a batch method
        if (method.dispatch_mode != .batch) {
            return DispatchError.ArgumentCountMismatch;
        }

        // Call the batch function
        const batch_fn: BatchMethodFn = @ptrCast(@alignCast(method.fn_ptr));
        const selection_ptr = if (selection) |s| s.ptr else null;
        const selection_len = if (selection) |s| s.len else 0;
        batch_fn(inputs.ptr, inputs.len, selection_ptr, selection_len, output, ctx);
    }

    /// Check if a method is registered as batch mode
    pub fn isBatchMethod(self: *Self, class_name: []const u8, method_name: []const u8) bool {
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ class_name, method_name }) catch return false;
        const method = self.methods.get(key) orelse return false;
        return method.dispatch_mode == .batch;
    }

    /// Get registered method info (for argument count checking)
    pub fn getMethodInfo(self: *Self, class_name: []const u8, method_name: []const u8) ?RegisteredMethod {
        var key_buf: [256]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "{s}.{s}", .{ class_name, method_name }) catch return null;
        return self.methods.get(key);
    }
};

/// Table source for SQL executor
/// Represents either a Lance file or a @logic_table instance
pub const TableSource = union(enum) {
    /// Regular Lance file
    lance: *anyopaque, // *Table pointer

    /// @logic_table virtual table
    logic_table: struct {
        /// Path to Python file
        python_file: []const u8,
        /// Executor instance
        executor: *LogicTableExecutor,
        /// Class name extracted from Python
        class_name: []const u8,
    },
};

// =============================================================================
// Extern declarations for compiled @logic_table methods
// These are populated when lib/logic_table.a is linked
// =============================================================================

// VectorOps class (from benchmarks/vector_ops.py)
pub extern fn VectorOps_dot_product(a: [*]const f64, b: [*]const f64, len: usize) callconv(.c) f64;
pub extern fn VectorOps_sum_squares(a: [*]const f64, len: usize) callconv(.c) f64;

/// Create a dispatcher with VectorOps methods pre-registered
pub fn createVectorOpsDispatcher(allocator: std.mem.Allocator) !Dispatcher {
    var dispatcher = Dispatcher.init(allocator);
    errdefer dispatcher.deinit();

    try dispatcher.registerMethod("VectorOps", "dot_product", @ptrCast(&VectorOps_dot_product), 2);
    try dispatcher.registerMethod("VectorOps", "sum_squares", @ptrCast(&VectorOps_sum_squares), 1);

    return dispatcher;
}

// =============================================================================
// Tests
// =============================================================================

test "Dispatcher basic" {
    const allocator = std.testing.allocator;

    var dispatcher = Dispatcher.init(allocator);
    defer dispatcher.deinit();

    // Create a test function
    const TestFn = struct {
        fn testAdd(a: [*]const f64, b: [*]const f64, len: usize) callconv(.c) f64 {
            var sum: f64 = 0;
            for (0..len) |i| {
                sum += a[i] + b[i];
            }
            return sum;
        }
    };

    try dispatcher.registerMethod("TestClass", "add", @ptrCast(&TestFn.testAdd), 2);

    // Call the method
    const a = [_]f64{ 1.0, 2.0, 3.0 };
    const b = [_]f64{ 4.0, 5.0, 6.0 };
    const result = try dispatcher.callMethod2("TestClass", "add", &a, &b, 3);

    try std.testing.expectEqual(@as(f64, 21.0), result);
}

test "Dispatcher method not found" {
    const allocator = std.testing.allocator;

    var dispatcher = Dispatcher.init(allocator);
    defer dispatcher.deinit();

    const result = dispatcher.callMethod0("Unknown", "method");
    try std.testing.expectError(DispatchError.MethodNotFound, result);
}

test "Dispatcher batch method" {
    const allocator = std.testing.allocator;

    var dispatcher = Dispatcher.init(allocator);
    defer dispatcher.deinit();

    // Create a batch test function that multiplies each value by 2
    const TestBatchFn = struct {
        fn batchDoubleValues(
            inputs: [*]const ColumnBinding,
            num_inputs: usize,
            selection: ?[*]const u32,
            selection_len: usize,
            output: *ColumnBuffer,
            ctx: ?*logic_table.QueryContext,
        ) callconv(.c) void {
            _ = ctx;

            // Get the first input column (should be f64)
            if (num_inputs == 0) return;
            const input_data = switch (inputs[0].data) {
                .f64 => |d| d,
                else => return,
            };

            const out_buf = output.f64 orelse return;

            // Process with or without selection
            if (selection) |sel| {
                for (0..selection_len) |i| {
                    const idx = sel[i];
                    out_buf[i] = input_data[idx] * 2.0;
                }
            } else {
                for (input_data, 0..) |val, i| {
                    out_buf[i] = val * 2.0;
                }
            }
        }
    };

    const input_cols = [_][]const u8{"value"};
    try dispatcher.registerBatchMethod(
        "TestBatch",
        "doubleValues",
        &TestBatchFn.batchDoubleValues,
        &input_cols,
        .f64,
    );

    // Create input data
    const values = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };
    const inputs = [_]ColumnBinding{
        .{
            .name = "value",
            .table_alias = null,
            .data = .{ .f64 = &values },
        },
    };

    // Test without selection (all rows)
    {
        var output = try ColumnBuffer.initFloat64(allocator, 5);
        defer output.deinit(allocator);

        try dispatcher.callMethodBatch("TestBatch", "doubleValues", &inputs, null, &output, null);

        const out_buf = output.f64.?;
        try std.testing.expectEqual(@as(f64, 2.0), out_buf[0]);
        try std.testing.expectEqual(@as(f64, 4.0), out_buf[1]);
        try std.testing.expectEqual(@as(f64, 10.0), out_buf[4]);
    }

    // Test with selection (only rows 1, 3)
    {
        const selection = [_]u32{ 1, 3 };
        var output = try ColumnBuffer.initFloat64(allocator, 2);
        defer output.deinit(allocator);

        try dispatcher.callMethodBatch("TestBatch", "doubleValues", &inputs, &selection, &output, null);

        const out_buf = output.f64.?;
        try std.testing.expectEqual(@as(f64, 4.0), out_buf[0]); // 2.0 * 2
        try std.testing.expectEqual(@as(f64, 8.0), out_buf[1]); // 4.0 * 2
    }
}

test "ColumnBuffer initialization" {
    const allocator = std.testing.allocator;

    // Test f64 buffer
    {
        var buf = try ColumnBuffer.initFloat64(allocator, 10);
        defer buf.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 10), buf.len());
    }

    // Test f32 buffer
    {
        var buf = try ColumnBuffer.initFloat32(allocator, 5);
        defer buf.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 5), buf.len());
    }

    // Test i64 buffer
    {
        var buf = try ColumnBuffer.initInt64(allocator, 3);
        defer buf.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 3), buf.len());
    }
}
