/// NumPy function code generation
/// Generates calls to c_interop/numpy.zig for direct BLAS integration
const std = @import("std");
const ast = @import("../../ast.zig");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

/// Generate numpy.array() call
/// Converts Python list to NumPy array (f64 slice)
pub fn genArray(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return; // Silently ignore invalid calls

    // Check if argument is a list literal
    const arg = args[0];
    if (arg == .list) {
        const elements = arg.list.elts;

        // Determine element type from first element
        const elem_type = if (elements.len > 0)
            try self.type_inferrer.inferExpr(elements[0])
        else
            .int;

        // Generate inline array literal
        if (elem_type == .float) {
            // Float array - pass directly to arrayFloat
            try self.emit("try numpy.arrayFloat(&[_]f64{");
            for (elements, 0..) |elem, i| {
                if (i > 0) try self.emit(", ");
                try self.genExpr(elem);
            }
            try self.emit("}, allocator)");
        } else {
            // Integer array - convert via array()
            try self.emit("try numpy.array(&[_]i64{");
            for (elements, 0..) |elem, i| {
                if (i > 0) try self.emit(", ");
                try self.genExpr(elem);
            }
            try self.emit("}, allocator)");
        }
    } else {
        // Variable reference - need to convert
        try self.emit("try numpy.array(");
        try self.genExpr(arg);
        try self.emit(", allocator)");
    }
}

/// Generate numpy.dot() call
/// Vector dot product using BLAS
pub fn genDot(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return; // Silently ignore invalid calls

    try self.emit("numpy.dot(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(")");
}

/// Generate numpy.sum() call
/// Sum all array elements
pub fn genSum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("numpy.sum(");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate numpy.mean() call
/// Calculate mean of array elements
pub fn genMean(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("numpy.mean(");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate numpy.transpose() call
/// Transpose matrix
pub fn genTranspose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) return; // Need matrix, rows, cols

    // numpy.transpose(matrix, rows, cols)
    try self.emit("try numpy.transpose(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", ");
    try self.genExpr(args[2]);
    try self.emit(", allocator)");
}

/// Generate numpy.matmul() call
/// Matrix multiplication using BLAS
pub fn genMatmul(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 5) return; // Need a, b, m, n, k

    // numpy.matmul(a, b, m, n, k) where:
    // a: m x k matrix
    // b: k x n matrix
    // result: m x n matrix
    try self.emit("try numpy.matmul(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", ");
    try self.genExpr(args[2]);
    try self.emit(", ");
    try self.genExpr(args[3]);
    try self.emit(", ");
    try self.genExpr(args[4]);
    try self.emit(", allocator)");
}

/// Generate numpy.zeros() call
/// Create array of zeros
pub fn genZeros(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("blk: {\n");
    try self.emit("    const size = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emit("    const arr = try allocator.alloc(f64, size);\n");
    try self.emit("    @memset(arr, 0.0);\n");
    try self.emit("    break :blk arr;\n");
    try self.emit("}");
}

/// Generate numpy.ones() call
/// Create array of ones
pub fn genOnes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("blk: {\n");
    try self.emit("    const size = ");
    try self.genExpr(args[0]);
    try self.emit(";\n");
    try self.emit("    const arr = try allocator.alloc(f64, size);\n");
    try self.emit("    @memset(arr, 1.0);\n");
    try self.emit("    break :blk arr;\n");
    try self.emit("}");
}
