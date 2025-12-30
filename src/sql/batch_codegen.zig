//! Batch Function Code Generator for @logic_table
//!
//! Generates optimized batch processing functions that:
//! 1. Extract required columns from Lance tables
//! 2. Dispatch to GPU (Metal) or CPU (SIMD) based on workload size
//! 3. Process entire column batches in parallel
//!
//! Example: Given a Python @logic_table method:
//! ```python
//! @logic_table
//! class FraudDetector:
//!     def score(self, transactions):
//!         return cosine_sim(transactions.embedding, self.fraud_pattern)
//! ```
//!
//! Generates Zig batch function:
//! ```zig
//! fn score_batch(embeddings: []const f32, pattern: []const f32, dim: usize, out: []f32) void {
//!     metal.gpuCosineSimilarityBatch(pattern, embeddings, dim, out);
//! }
//! ```

const std = @import("std");
const ast = @import("ast.zig");
const column_deps = @import("column_deps.zig");

/// Operation types that can be batched
pub const BatchOp = enum {
    // Vector similarity
    cosine_sim,
    l2_distance,
    dot_product,

    // Elementwise arithmetic
    add,
    sub,
    mul,
    div,

    // Aggregations
    sum,
    mean,
    min,
    max,

    // Normalization
    normalize,
};

/// A batch operation with its operands
pub const BatchOperation = struct {
    op: BatchOp,
    /// Column references used by this operation
    inputs: []const column_deps.ColumnRef,
    /// Output column name (for intermediate results)
    output: ?[]const u8,
};

/// Batch function signature
pub const BatchFuncSig = struct {
    name: []const u8,
    /// Input columns and their types
    inputs: []const InputParam,
    /// Output type
    output_type: OutputType,

    pub const InputParam = struct {
        name: []const u8,
        col_type: ColumnType,
    };

    pub const ColumnType = enum {
        f32_array,
        f64_array,
        i64_array,
        string_array,
        embedding, // Fixed-size f32 vector
    };

    pub const OutputType = enum {
        f32_array,
        f64_array,
        i64_array,
        scalar_f32,
        scalar_f64,
        scalar_i64,
    };
};

/// Code generator for batch functions
pub const BatchCodeGen = struct {
    allocator: std.mem.Allocator,
    /// Generated code buffer
    output: std.ArrayListUnmanaged(u8),
    /// Column dependencies
    deps: *const column_deps.ColumnDeps,
    /// Detected operations
    operations: std.ArrayListUnmanaged(BatchOperation),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, deps: *const column_deps.ColumnDeps) Self {
        return .{
            .allocator = allocator,
            .output = .{},
            .deps = deps,
            .operations = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.output.deinit(self.allocator);
        self.operations.deinit(self.allocator);
    }

    /// Analyze expression and detect batch operations
    pub fn analyzeExpr(self: *Self, expr: *const ast.Expr) !void {
        switch (expr.*) {
            .call => |call| {
                // Detect known batch-able functions
                const op = detectBatchOp(call.name) orelse return;

                // Collect input column refs
                var inputs = std.ArrayListUnmanaged(column_deps.ColumnRef){};
                defer inputs.deinit(self.allocator);

                for (call.args) |*arg| {
                    try self.collectColumnRefs(arg, &inputs);
                }

                try self.operations.append(self.allocator, .{
                    .op = op,
                    .inputs = try self.allocator.dupe(column_deps.ColumnRef, inputs.items),
                    .output = null,
                });
            },
            .binary => |bin| {
                // Detect arithmetic operations on columns
                const op: ?BatchOp = switch (bin.op) {
                    .add => .add,
                    .subtract => .sub,
                    .multiply => .mul,
                    .divide => .div,
                    else => null,
                };

                if (op) |batch_op| {
                    var inputs = std.ArrayListUnmanaged(column_deps.ColumnRef){};
                    defer inputs.deinit(self.allocator);

                    try self.collectColumnRefs(bin.left, &inputs);
                    try self.collectColumnRefs(bin.right, &inputs);

                    if (inputs.items.len > 0) {
                        try self.operations.append(self.allocator, .{
                            .op = batch_op,
                            .inputs = try self.allocator.dupe(column_deps.ColumnRef, inputs.items),
                            .output = null,
                        });
                    }
                }

                // Recurse
                try self.analyzeExpr(bin.left);
                try self.analyzeExpr(bin.right);
            },
            .unary => |un| {
                try self.analyzeExpr(un.operand);
            },
            else => {},
        }
    }

    fn collectColumnRefs(self: *Self, expr: *const ast.Expr, refs: *std.ArrayListUnmanaged(column_deps.ColumnRef)) !void {
        switch (expr.*) {
            .column => |col| {
                try refs.append(self.allocator, .{
                    .table = col.table,
                    .column = col.name,
                });
            },
            .binary => |bin| {
                try self.collectColumnRefs(bin.left, refs);
                try self.collectColumnRefs(bin.right, refs);
            },
            .unary => |un| {
                try self.collectColumnRefs(un.operand, refs);
            },
            .call => |call| {
                for (call.args) |*arg| {
                    try self.collectColumnRefs(arg, refs);
                }
            },
            else => {},
        }
    }

    /// Generate Zig batch function code
    pub fn generateBatchFunction(self: *Self, func_name: []const u8) ![]const u8 {
        try self.output.appendSlice(self.allocator, "/// Auto-generated batch function for @logic_table\n");
        try self.output.appendSlice(self.allocator, "/// GPU dispatch on Apple Silicon, SIMD fallback elsewhere\n");

        // Function signature
        try self.output.appendSlice(self.allocator, "pub fn ");
        try self.output.appendSlice(self.allocator, func_name);
        try self.output.appendSlice(self.allocator, "_batch(\n");

        // Generate parameters based on column deps
        for (self.deps.getRefs()) |ref| {
            try self.output.appendSlice(self.allocator, "    ");
            if (ref.table) |t| {
                try self.output.appendSlice(self.allocator, t);
                try self.output.appendSlice(self.allocator, "_");
            }
            try self.output.appendSlice(self.allocator, ref.column);
            try self.output.appendSlice(self.allocator, ": []const f32,\n");
        }

        try self.output.appendSlice(self.allocator, "    dim: usize,\n");
        try self.output.appendSlice(self.allocator, "    out: []f32,\n");
        try self.output.appendSlice(self.allocator, ") void {\n");

        // Generate body based on detected operations
        if (self.operations.items.len > 0) {
            const op = self.operations.items[0];
            try self.generateOpDispatch(op);
        } else {
            try self.output.appendSlice(self.allocator, "    // No batch operations detected\n");
            try self.output.appendSlice(self.allocator, "    _ = dim;\n");
            try self.output.appendSlice(self.allocator, "    _ = out;\n");
        }

        try self.output.appendSlice(self.allocator, "}\n");

        return self.output.items;
    }

    fn generateOpDispatch(self: *Self, op: BatchOperation) !void {
        switch (op.op) {
            .cosine_sim => {
                try self.output.appendSlice(self.allocator,
                    \\    const metal = @import("lanceql.metal");
                    \\    // GPU dispatch on Apple Silicon, SIMD fallback
                    \\    if (comptime metal.is_apple_silicon) {
                    \\        metal.gpuCosineSimilarityBatch(
                    \\
                );
                // First input is query, second is vectors
                if (op.inputs.len >= 1) {
                    try self.generateColumnAccess(op.inputs[0]);
                    try self.output.appendSlice(self.allocator, ",\n");
                }
                if (op.inputs.len >= 2) {
                    try self.output.appendSlice(self.allocator, "            ");
                    try self.generateColumnAccess(op.inputs[1]);
                    try self.output.appendSlice(self.allocator, ",\n");
                }
                try self.output.appendSlice(self.allocator,
                    \\            dim,
                    \\            out,
                    \\        );
                    \\    } else {
                    \\        metal.batchCosineSimilarity(
                    \\
                );
                if (op.inputs.len >= 1) {
                    try self.generateColumnAccess(op.inputs[0]);
                    try self.output.appendSlice(self.allocator, ",\n");
                }
                if (op.inputs.len >= 2) {
                    try self.output.appendSlice(self.allocator, "            ");
                    try self.generateColumnAccess(op.inputs[1]);
                    try self.output.appendSlice(self.allocator, ",\n");
                }
                try self.output.appendSlice(self.allocator,
                    \\            dim,
                    \\            out,
                    \\        );
                    \\    }
                    \\
                );
            },
            .l2_distance => {
                try self.output.appendSlice(self.allocator,
                    \\    const metal = @import("lanceql.metal");
                    \\    const num_vectors = out.len;
                    \\    for (0..num_vectors) |i| {
                    \\        const vec =
                );
                if (op.inputs.len >= 2) {
                    try self.generateColumnAccess(op.inputs[1]);
                }
                try self.output.appendSlice(self.allocator,
                    \\[i * dim ..][0..dim];
                    \\        out[i] = metal.l2DistanceSquared(
                );
                if (op.inputs.len >= 1) {
                    try self.generateColumnAccess(op.inputs[0]);
                }
                try self.output.appendSlice(self.allocator,
                    \\, vec);
                    \\    }
                    \\
                );
            },
            .dot_product => {
                try self.output.appendSlice(self.allocator,
                    \\    const metal = @import("lanceql.metal");
                    \\    metal.gpuDotProductBatch(
                );
                if (op.inputs.len >= 1) {
                    try self.generateColumnAccess(op.inputs[0]);
                    try self.output.appendSlice(self.allocator, ", ");
                }
                if (op.inputs.len >= 2) {
                    try self.generateColumnAccess(op.inputs[1]);
                    try self.output.appendSlice(self.allocator, ", ");
                }
                try self.output.appendSlice(self.allocator, "dim, out);\n");
            },
            .add => {
                try self.output.appendSlice(self.allocator,
                    \\    const metal = @import("lanceql.metal");
                    \\    metal.gpuBatchAddArrays(
                );
                try self.generateBinaryOpArgs(op);
                try self.output.appendSlice(self.allocator, ", out);\n");
            },
            .sub => {
                try self.output.appendSlice(self.allocator,
                    \\    const metal = @import("lanceql.metal");
                    \\    metal.gpuBatchSubArrays(
                );
                try self.generateBinaryOpArgs(op);
                try self.output.appendSlice(self.allocator, ", out);\n");
            },
            .mul => {
                try self.output.appendSlice(self.allocator,
                    \\    const metal = @import("lanceql.metal");
                    \\    metal.gpuBatchMulArrays(
                );
                try self.generateBinaryOpArgs(op);
                try self.output.appendSlice(self.allocator, ", out);\n");
            },
            .div => {
                try self.output.appendSlice(self.allocator,
                    \\    const metal = @import("lanceql.metal");
                    \\    metal.gpuBatchDivArrays(
                );
                try self.generateBinaryOpArgs(op);
                try self.output.appendSlice(self.allocator, ", out);\n");
            },
            .sum, .mean, .min, .max => {
                try self.output.appendSlice(self.allocator, "    // Aggregation: ");
                try self.output.appendSlice(self.allocator, @tagName(op.op));
                try self.output.appendSlice(self.allocator, "\n");
                try self.output.appendSlice(self.allocator, "    _ = dim;\n");
            },
            .normalize => {
                try self.output.appendSlice(self.allocator,
                    \\    // L2 normalize each vector
                    \\    const num_vectors = out.len / dim;
                    \\    for (0..num_vectors) |i| {
                    \\        var sum: f32 = 0;
                    \\        for (0..dim) |j| {
                    \\            const idx = i * dim + j;
                    \\            sum +=
                );
                if (op.inputs.len >= 1) {
                    try self.generateColumnAccess(op.inputs[0]);
                }
                try self.output.appendSlice(self.allocator,
                    \\[idx] *
                );
                if (op.inputs.len >= 1) {
                    try self.generateColumnAccess(op.inputs[0]);
                }
                try self.output.appendSlice(self.allocator,
                    \\[idx];
                    \\        }
                    \\        const norm = @sqrt(sum);
                    \\        if (norm > 0) {
                    \\            for (0..dim) |j| {
                    \\                out[i * dim + j] =
                );
                if (op.inputs.len >= 1) {
                    try self.generateColumnAccess(op.inputs[0]);
                }
                try self.output.appendSlice(self.allocator,
                    \\[i * dim + j] / norm;
                    \\            }
                    \\        }
                    \\    }
                    \\
                );
            },
        }
    }

    fn generateBinaryOpArgs(self: *Self, op: BatchOperation) !void {
        if (op.inputs.len >= 1) {
            try self.generateColumnAccess(op.inputs[0]);
            try self.output.appendSlice(self.allocator, ", ");
        }
        if (op.inputs.len >= 2) {
            try self.generateColumnAccess(op.inputs[1]);
        }
    }

    fn generateColumnAccess(self: *Self, ref: column_deps.ColumnRef) !void {
        if (ref.table) |t| {
            try self.output.appendSlice(self.allocator, t);
            try self.output.appendSlice(self.allocator, "_");
        }
        try self.output.appendSlice(self.allocator, ref.column);
    }
};

/// Detect if a function name is a known batch operation
fn detectBatchOp(name: []const u8) ?BatchOp {
    const ops = std.StaticStringMap(BatchOp).initComptime(.{
        .{ "cosine_sim", .cosine_sim },
        .{ "cosine_similarity", .cosine_sim },
        .{ "l2_distance", .l2_distance },
        .{ "euclidean_distance", .l2_distance },
        .{ "dot", .dot_product },
        .{ "dot_product", .dot_product },
        .{ "sum", .sum },
        .{ "mean", .mean },
        .{ "avg", .mean },
        .{ "min", .min },
        .{ "max", .max },
        .{ "normalize", .normalize },
        .{ "l2_normalize", .normalize },
    });
    return ops.get(name);
}

// =============================================================================
// Tests
// =============================================================================

test "detect batch operations" {
    try std.testing.expect(detectBatchOp("cosine_sim") == .cosine_sim);
    try std.testing.expect(detectBatchOp("l2_distance") == .l2_distance);
    try std.testing.expect(detectBatchOp("dot") == .dot_product);
    try std.testing.expect(detectBatchOp("unknown") == null);
}

test "generate batch function" {
    const allocator = std.testing.allocator;

    // Create column deps
    var deps = column_deps.ColumnDeps.init(allocator);
    defer deps.deinit();

    try deps.addRef("transactions", "embedding");
    try deps.addRef(null, "fraud_pattern");

    // Create codegen
    var codegen = BatchCodeGen.init(allocator, &deps);
    defer codegen.deinit();

    // Add a cosine_sim operation manually
    const refs = [_]column_deps.ColumnRef{
        .{ .table = null, .column = "fraud_pattern" },
        .{ .table = "transactions", .column = "embedding" },
    };
    try codegen.operations.append(allocator, .{
        .op = .cosine_sim,
        .inputs = &refs,
        .output = null,
    });

    // Generate
    const code = try codegen.generateBatchFunction("score");

    // Verify output contains key elements
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn score_batch") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "gpuCosineSimilarityBatch") != null);
}
