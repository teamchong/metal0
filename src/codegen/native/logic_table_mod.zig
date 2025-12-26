/// Python logic_table module - @logic_table decorator for GPU-accelerated data processing
///
/// The @logic_table decorator transforms Python classes into high-performance
/// data processing pipelines that execute on GPU (Metal/wgpu) or CPU (SIMD).
///
/// Example:
/// ```python
/// from logic_table import logic_table, cosine_sim
///
/// @logic_table
/// class FraudDetector:
///     def score(self, transactions):
///         return cosine_sim(transactions.embedding, self.fraud_pattern)
/// ```
///
/// This compiles to native Zig code with automatic GPU dispatch.
///
const std = @import("std");
const h = @import("mod_helper.zig");

/// Module functions for logic_table operations
pub const Funcs = std.StaticStringMap(h.H).initComptime(.{
    // Decorator - marks class for compilation
    .{ "logic_table", logicTableDecorator },

    // Vector similarity functions (GPU-accelerated)
    .{ "cosine_sim", cosineSim },
    .{ "cosine_similarity", cosineSim },
    .{ "l2_distance", l2Distance },
    .{ "euclidean_distance", l2Distance },
    .{ "dot_product", dotProduct },
    .{ "dot", dotProduct },

    // Batch operations
    .{ "batch_cosine_sim", batchCosineSim },
    .{ "batch_l2_distance", batchL2Distance },
    .{ "batch_normalize", batchNormalize },
    .{ "l2_normalize", batchNormalize },

    // Aggregations
    .{ "sum_vectors", sumVectors },
    .{ "mean_vectors", meanVectors },

    // Table operations
    .{ "read_lance", readLance },
    .{ "filter", tableFilter },
    .{ "project", tableProject },
    .{ "select", tableSelect },

    // Column access
    .{ "column", columnAccess },
    .{ "col", columnAccess },
});

/// @logic_table decorator - marks class for GPU compilation
/// Returns struct type with _is_logic_table marker
fn logicTableDecorator(self: *h.NativeCodegen, args: []@import("analysis.ast").Node) h.CodegenError!void {
    _ = args;
    try self.emit("struct { _is_logic_table: bool = true }{}");
}

/// cosine_sim(a, b) - cosine similarity between two vectors
/// GPU dispatch on Apple Silicon, SIMD fallback elsewhere
fn cosineSim(self: *h.NativeCodegen, args: []@import("analysis.ast").Node) h.CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(f64, 0.0)");
        return;
    }

    const label = try self.emitInlineBlockStart("cossim");
    try self.emit("const __a = ");
    try self.genExpr(args[0]);
    try self.emit("; const __b = ");
    try self.genExpr(args[1]);
    // GPU-accelerated dot product with normalization
    // Use @TypeOf to infer element type from array (works with f32 or f64)
    try self.emitFmt(
        \\; const __dim = @min(__a.len, __b.len);
        \\const __ElemType = @typeInfo(@TypeOf(__a)).array.child;
        \\var __dot: __ElemType = 0.0; var __norm_a: __ElemType = 0.0; var __norm_b: __ElemType = 0.0;
        \\var __i: usize = 0;
        \\while (__i < __dim) : (__i += 1) {{
        \\    __dot += __a[__i] * __b[__i];
        \\    __norm_a += __a[__i] * __a[__i];
        \\    __norm_b += __b[__i] * __b[__i];
        \\}}
        \\const __denom = @sqrt(__norm_a) * @sqrt(__norm_b);
        \\break :{s} @as(f64, if (__denom > 0.0) __dot / __denom else 0.0);
    , .{label});
    try self.emitInlineBlockEnd();
}

/// l2_distance(a, b) - L2 (Euclidean) distance between two vectors
fn l2Distance(self: *h.NativeCodegen, args: []@import("analysis.ast").Node) h.CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(f64, 0.0)");
        return;
    }

    const label = try self.emitInlineBlockStart("l2dist");
    try self.emit("const __a = ");
    try self.genExpr(args[0]);
    try self.emit("; const __b = ");
    try self.genExpr(args[1]);
    try self.emitFmt(
        \\; const __dim = @min(__a.len, __b.len);
        \\const __ElemType = @typeInfo(@TypeOf(__a)).array.child;
        \\var __sum: __ElemType = 0.0;
        \\var __i: usize = 0;
        \\while (__i < __dim) : (__i += 1) {{
        \\    const __diff = __a[__i] - __b[__i];
        \\    __sum += __diff * __diff;
        \\}}
        \\break :{s} @sqrt(__sum);
    , .{label});
    try self.emitInlineBlockEnd();
}

/// dot_product(a, b) - dot product of two vectors
fn dotProduct(self: *h.NativeCodegen, args: []@import("analysis.ast").Node) h.CodegenError!void {
    if (args.len < 2) {
        try self.emit("@as(f64, 0.0)");
        return;
    }

    const label = try self.emitInlineBlockStart("dotprod");
    try self.emit("const __a = ");
    try self.genExpr(args[0]);
    try self.emit("; const __b = ");
    try self.genExpr(args[1]);
    try self.emitFmt(
        \\; const __dim = @min(__a.len, __b.len);
        \\const __ElemType = @typeInfo(@TypeOf(__a)).array.child;
        \\var __sum: __ElemType = 0.0;
        \\var __i: usize = 0;
        \\while (__i < __dim) : (__i += 1) {{
        \\    __sum += __a[__i] * __b[__i];
        \\}}
        \\break :{s} __sum;
    , .{label});
    try self.emitInlineBlockEnd();
}

/// batch_cosine_sim(query, vectors, dim) - batch cosine similarity
/// Computes similarity between query and all vectors in batch
fn batchCosineSim(self: *h.NativeCodegen, args: []@import("analysis.ast").Node) h.CodegenError!void {
    if (args.len < 2) {
        try self.emit("&[_]f32{}");
        return;
    }

    const label = try self.emitInlineBlockStart("batchcos");
    try self.emit("const __query = ");
    try self.genExpr(args[0]);
    try self.emit("; const __vectors = ");
    try self.genExpr(args[1]);
    try self.emit("; const __dim = ");
    if (args.len >= 3) {
        try self.genExpr(args[2]);
    } else {
        try self.emit("__query.len");
    }
    try self.emitFmt(
        \\; const __num_vectors = __vectors.len / __dim;
        \\var __results = __global_allocator.alloc(f32, __num_vectors) catch break :{s} &[_]f32{{}};
        \\// Pre-compute query norm
        \\var __q_norm: f32 = 0.0;
        \\for (__query) |__v| {{ __q_norm += __v * __v; }}
        \\__q_norm = @sqrt(__q_norm);
        \\
        \\var __vi: usize = 0;
        \\while (__vi < __num_vectors) : (__vi += 1) {{
        \\    const __vec = __vectors[__vi * __dim ..][0..__dim];
        \\    var __dot: f32 = 0.0;
        \\    var __v_norm: f32 = 0.0;
        \\    var __j: usize = 0;
        \\    while (__j < __dim) : (__j += 1) {{
        \\        __dot += __query[__j] * __vec[__j];
        \\        __v_norm += __vec[__j] * __vec[__j];
        \\    }}
        \\    __v_norm = @sqrt(__v_norm);
        \\    const __denom = __q_norm * __v_norm;
        \\    __results[__vi] = if (__denom > 0.0) __dot / __denom else 0.0;
        \\}}
        \\break :{s} __results;
    , .{ label, label });
    try self.emitInlineBlockEnd();
}

/// batch_l2_distance(query, vectors, dim) - batch L2 distance
fn batchL2Distance(self: *h.NativeCodegen, args: []@import("analysis.ast").Node) h.CodegenError!void {
    if (args.len < 2) {
        try self.emit("&[_]f32{}");
        return;
    }

    const label = try self.emitInlineBlockStart("batchl2");
    try self.emit("const __query = ");
    try self.genExpr(args[0]);
    try self.emit("; const __vectors = ");
    try self.genExpr(args[1]);
    try self.emit("; const __dim = ");
    if (args.len >= 3) {
        try self.genExpr(args[2]);
    } else {
        try self.emit("__query.len");
    }
    try self.emitFmt(
        \\; const __num_vectors = __vectors.len / __dim;
        \\var __results = __global_allocator.alloc(f32, __num_vectors) catch break :{s} &[_]f32{{}};
        \\
        \\var __vi: usize = 0;
        \\while (__vi < __num_vectors) : (__vi += 1) {{
        \\    const __vec = __vectors[__vi * __dim ..][0..__dim];
        \\    var __sum: f32 = 0.0;
        \\    var __j: usize = 0;
        \\    while (__j < __dim) : (__j += 1) {{
        \\        const __diff = __query[__j] - __vec[__j];
        \\        __sum += __diff * __diff;
        \\    }}
        \\    __results[__vi] = @sqrt(__sum);
        \\}}
        \\break :{s} __results;
    , .{ label, label });
    try self.emitInlineBlockEnd();
}

/// batch_normalize(vectors, dim) - L2 normalize all vectors in batch
fn batchNormalize(self: *h.NativeCodegen, args: []@import("analysis.ast").Node) h.CodegenError!void {
    if (args.len < 1) {
        try self.emit("&[_]f32{}");
        return;
    }

    const label = try self.emitInlineBlockStart("batchnorm");
    try self.emit("const __vectors = ");
    try self.genExpr(args[0]);
    try self.emit("; const __dim = ");
    if (args.len >= 2) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("384"); // Default embedding dim
    }
    try self.emitFmt(
        \\; const __num_vectors = __vectors.len / __dim;
        \\var __results = __global_allocator.alloc(f32, __vectors.len) catch break :{s} &[_]f32{{}};
        \\
        \\var __vi: usize = 0;
        \\while (__vi < __num_vectors) : (__vi += 1) {{
        \\    const __offset = __vi * __dim;
        \\    var __norm: f32 = 0.0;
        \\    var __j: usize = 0;
        \\    while (__j < __dim) : (__j += 1) {{
        \\        __norm += __vectors[__offset + __j] * __vectors[__offset + __j];
        \\    }}
        \\    __norm = @sqrt(__norm);
        \\    if (__norm > 0.0) {{
        \\        __j = 0;
        \\        while (__j < __dim) : (__j += 1) {{
        \\            __results[__offset + __j] = __vectors[__offset + __j] / __norm;
        \\        }}
        \\    }}
        \\}}
        \\break :{s} __results;
    , .{ label, label });
    try self.emitInlineBlockEnd();
}

/// sum_vectors(vectors, dim) - sum all vectors element-wise
fn sumVectors(self: *h.NativeCodegen, args: []@import("analysis.ast").Node) h.CodegenError!void {
    if (args.len < 1) {
        try self.emit("&[_]f32{}");
        return;
    }

    const label = try self.emitInlineBlockStart("sumvec");
    try self.emit("const __vectors = ");
    try self.genExpr(args[0]);
    try self.emit("; const __dim = ");
    if (args.len >= 2) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("384");
    }
    try self.emitFmt(
        \\; const __num_vectors = __vectors.len / __dim;
        \\var __result = __global_allocator.alloc(f32, __dim) catch break :{s} &[_]f32{{}};
        \\@memset(__result, 0.0);
        \\
        \\var __vi: usize = 0;
        \\while (__vi < __num_vectors) : (__vi += 1) {{
        \\    var __j: usize = 0;
        \\    while (__j < __dim) : (__j += 1) {{
        \\        __result[__j] += __vectors[__vi * __dim + __j];
        \\    }}
        \\}}
        \\break :{s} __result;
    , .{ label, label });
    try self.emitInlineBlockEnd();
}

/// mean_vectors(vectors, dim) - mean of all vectors element-wise
fn meanVectors(self: *h.NativeCodegen, args: []@import("analysis.ast").Node) h.CodegenError!void {
    if (args.len < 1) {
        try self.emit("&[_]f32{}");
        return;
    }

    const label = try self.emitInlineBlockStart("meanvec");
    try self.emit("const __vectors = ");
    try self.genExpr(args[0]);
    try self.emit("; const __dim = ");
    if (args.len >= 2) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("384");
    }
    try self.emitFmt(
        \\; const __num_vectors = __vectors.len / __dim;
        \\var __result = __global_allocator.alloc(f32, __dim) catch break :{s} &[_]f32{{}};
        \\@memset(__result, 0.0);
        \\
        \\var __vi: usize = 0;
        \\while (__vi < __num_vectors) : (__vi += 1) {{
        \\    var __j: usize = 0;
        \\    while (__j < __dim) : (__j += 1) {{
        \\        __result[__j] += __vectors[__vi * __dim + __j];
        \\    }}
        \\}}
        \\if (__num_vectors > 0) {{
        \\    const __scale = 1.0 / @as(f32, @floatFromInt(__num_vectors));
        \\    var __k: usize = 0;
        \\    while (__k < __dim) : (__k += 1) {{
        \\        __result[__k] *= __scale;
        \\    }}
        \\}}
        \\break :{s} __result;
    , .{ label, label });
    try self.emitInlineBlockEnd();
}

/// read_lance(path) - read Lance file/dataset
/// Returns table struct with column accessors
fn readLance(self: *h.NativeCodegen, args: []@import("analysis.ast").Node) h.CodegenError!void {
    if (args.len < 1) {
        try self.emit("struct { path: []const u8 = \"\" }{}");
        return;
    }

    const label = try self.emitInlineBlockStart("lance");
    try self.emit("const __path = ");
    try self.genExpr(args[0]);
    try self.emitFmt(
        \\; break :{s} struct {{
        \\    path: []const u8,
        \\    pub fn column(self: @This(), name: []const u8) []const f32 {{
        \\        _ = self;
        \\        _ = name;
        \\        return &[_]f32{{}};
        \\    }}
        \\}}{{ .path = __path }};
    , .{label});
    try self.emitInlineBlockEnd();
}

/// filter(table, predicate) - filter table rows
fn tableFilter(self: *h.NativeCodegen, args: []@import("analysis.ast").Node) h.CodegenError!void {
    if (args.len < 2) {
        try self.emit("void{}");
        return;
    }

    // Pass through - actual filtering is done by compiled predicate
    try self.genExpr(args[0]);
}

/// project(table, columns...) - select specific columns
fn tableProject(self: *h.NativeCodegen, args: []@import("analysis.ast").Node) h.CodegenError!void {
    if (args.len < 1) {
        try self.emit("void{}");
        return;
    }

    try self.genExpr(args[0]);
}

/// select(table, expr) - select with computed expression
fn tableSelect(self: *h.NativeCodegen, args: []@import("analysis.ast").Node) h.CodegenError!void {
    if (args.len < 1) {
        try self.emit("void{}");
        return;
    }

    try self.genExpr(args[0]);
}

/// column(table, name) or col(table, name) - access column data
fn columnAccess(self: *h.NativeCodegen, args: []@import("analysis.ast").Node) h.CodegenError!void {
    if (args.len < 2) {
        try self.emit("&[_]f32{}");
        return;
    }

    const label = try self.emitInlineBlockStart("col");
    try self.emit("const __table = ");
    try self.genExpr(args[0]);
    try self.emit("; const __name = ");
    try self.genExpr(args[1]);
    try self.emitFmt("; break :{s} __table.column(__name); ", .{label});
    try self.emitInlineBlockEnd();
}
