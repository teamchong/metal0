/// NumPy function code generation
/// Generates calls to c_interop/numpy.zig for direct BLAS integration
const std = @import("std");
const ast = @import("ast");
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

    try self.emit("try numpy.dot(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.sum() call
/// Sum all array elements
pub fn genSum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.sum(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.mean() call
/// Calculate mean of array elements
pub fn genMean(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.mean(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
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
    try self.emit(", @intCast(");
    try self.genExpr(args[2]);
    try self.emit("), @intCast(");
    try self.genExpr(args[3]);
    try self.emit("), @intCast(");
    try self.genExpr(args[4]);
    try self.emit("), allocator)");
}

/// Generate numpy.zeros() call
/// Create array of zeros
pub fn genZeros(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    const arg = args[0];

    // Check if shape is a tuple (multi-dimensional)
    if (arg == .tuple) {
        try self.emit("try numpy.zeros(&[_]usize{");
        for (arg.tuple.elts, 0..) |dim, i| {
            if (i > 0) try self.emit(", ");
            try self.emit("@intCast(");
            try self.genExpr(dim);
            try self.emit(")");
        }
        try self.emit("}, allocator)");
    } else {
        // numpy.zeros(n) -> create 1D array of n zeros
        try self.emit("try numpy.zeros(&[_]usize{@intCast(");
        try self.genExpr(arg);
        try self.emit(")}, allocator)");
    }
}

/// Generate numpy.ones() call
/// Create array of ones
pub fn genOnes(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    const arg = args[0];

    // Check if shape is a tuple (multi-dimensional)
    if (arg == .tuple) {
        try self.emit("try numpy.ones(&[_]usize{");
        for (arg.tuple.elts, 0..) |dim, i| {
            if (i > 0) try self.emit(", ");
            try self.emit("@intCast(");
            try self.genExpr(dim);
            try self.emit(")");
        }
        try self.emit("}, allocator)");
    } else {
        // numpy.ones(n) -> create 1D array of n ones
        try self.emit("try numpy.ones(&[_]usize{@intCast(");
        try self.genExpr(arg);
        try self.emit(")}, allocator)");
    }
}

// ============================================================================
// Array Creation Functions
// ============================================================================

/// Generate numpy.empty() call
pub fn genEmpty(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.empty(&[_]usize{@intCast(");
    try self.genExpr(args[0]);
    try self.emit(")}, allocator)");
}

/// Generate numpy.full() call
pub fn genFull(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.full(&[_]usize{@intCast(");
    try self.genExpr(args[0]);
    try self.emit(")}, ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.eye() / numpy.identity() call
pub fn genEye(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.eye(@intCast(");
    try self.genExpr(args[0]);
    try self.emit("), allocator)");
}

/// Generate numpy.arange() call
pub fn genArange(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    if (args.len == 1) {
        // arange(stop)
        try self.emit("try numpy.arange(0, ");
        try self.genExpr(args[0]);
        try self.emit(", 1, allocator)");
    } else if (args.len == 2) {
        // arange(start, stop)
        try self.emit("try numpy.arange(");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(", 1, allocator)");
    } else {
        // arange(start, stop, step)
        try self.emit("try numpy.arange(");
        try self.genExpr(args[0]);
        try self.emit(", ");
        try self.genExpr(args[1]);
        try self.emit(", ");
        try self.genExpr(args[2]);
        try self.emit(", allocator)");
    }
}

/// Generate numpy.linspace() call
pub fn genLinspace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) return;

    try self.emit("try numpy.linspace(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", @intCast(");
    try self.genExpr(args[2]);
    try self.emit("), allocator)");
}

/// Generate numpy.logspace() call
pub fn genLogspace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) return;

    try self.emit("try numpy.logspace(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", @intCast(");
    try self.genExpr(args[2]);
    try self.emit("), allocator)");
}

// ============================================================================
// Array Manipulation Functions
// ============================================================================

/// Generate numpy.reshape() call
pub fn genReshape(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    const shape_arg = args[1];

    try self.emit("try numpy.reshape(");
    try self.genExpr(args[0]);
    try self.emit(", ");

    // Check if shape is a tuple (multi-dimensional)
    if (shape_arg == .tuple) {
        try self.emit("&[_]usize{");
        for (shape_arg.tuple.elts, 0..) |dim, i| {
            if (i > 0) try self.emit(", ");
            try self.emit("@intCast(");
            try self.genExpr(dim);
            try self.emit(")");
        }
        try self.emit("}");
    } else {
        try self.emit("&[_]usize{@intCast(");
        try self.genExpr(shape_arg);
        try self.emit(")}");
    }
    try self.emit(", allocator)");
}

/// Generate numpy.ravel() or numpy.flatten() call
pub fn genRavel(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.ravel(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.squeeze() call
pub fn genSqueeze(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.squeeze(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.expand_dims() call
pub fn genExpandDims(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.expand_dims(");
    try self.genExpr(args[0]);
    try self.emit(", @intCast(");
    try self.genExpr(args[1]);
    try self.emit("), allocator)");
}

// ============================================================================
// Element-wise Math Functions
// ============================================================================

/// Generate numpy.add() call
pub fn genAdd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.add(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.subtract() call
pub fn genSubtract(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.subtract(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.multiply() call
pub fn genMultiply(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.multiply(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.divide() call
pub fn genDivide(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.divide(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.power() call
pub fn genPower(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.power(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.sqrt() call
pub fn genSqrt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.sqrt(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.exp() call
pub fn genExp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.npExp(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.log() call
pub fn genLog(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.npLog(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.sin() call
pub fn genSin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.sin(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.cos() call
pub fn genCos(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.cos(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.abs() call
pub fn genAbs(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.npAbs(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

// ============================================================================
// Reduction Functions
// ============================================================================

/// Generate numpy.std() call
pub fn genStd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.npStd(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.var() call
pub fn genVar(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.npVar(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.min() call
pub fn genMin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.npMin(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.max() call
pub fn genMax(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.npMax(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.argmin() call
pub fn genArgmin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.argmin(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.argmax() call
pub fn genArgmax(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.argmax(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.prod() call
pub fn genProd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.prod(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

// ============================================================================
// Linear Algebra Functions
// ============================================================================

/// Generate numpy.inner() call
pub fn genInner(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.inner(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.outer() call
pub fn genOuter(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.outer(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.vdot() call
pub fn genVdot(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.vdot(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.linalg.norm() call
pub fn genNorm(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.norm(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.linalg.det() call
pub fn genDet(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.det(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.linalg.inv() call
pub fn genInv(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.inv(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.linalg.solve() call
pub fn genSolve(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.solve(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.trace() call
pub fn genTrace(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.trace(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

// ============================================================================
// Statistics Functions
// ============================================================================

/// Generate numpy.median() call
pub fn genMedian(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.median(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.percentile() call
pub fn genPercentile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.percentile(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

// ============================================================================
// Random Functions (numpy.random module)
// ============================================================================

/// Generate numpy.random.seed() call
pub fn genRandomSeed(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("numpy.randomSeed(");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate numpy.random.rand() call - uniform [0, 1)
pub fn genRandomRand(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        // rand() with no args = single value, return array of size 1
        try self.emit("try numpy.randomRand(1, allocator)");
        return;
    }

    try self.emit("try numpy.randomRand(@intCast(");
    try self.genExpr(args[0]);
    try self.emit("), allocator)");
}

/// Generate numpy.random.randn() call - standard normal
pub fn genRandomRandn(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) {
        try self.emit("try numpy.randomRandn(1, allocator)");
        return;
    }

    try self.emit("try numpy.randomRandn(@intCast(");
    try self.genExpr(args[0]);
    try self.emit("), allocator)");
}

/// Generate numpy.random.randint() call
pub fn genRandomRandint(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    // randint(low, high) or randint(low, high, size)
    try self.emit("try numpy.randomRandint(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", ");
    if (args.len >= 3) {
        try self.emit("@intCast(");
        try self.genExpr(args[2]);
        try self.emit(")");
    } else {
        try self.emit("1");
    }
    try self.emit(", allocator)");
}

/// Generate numpy.random.uniform() call
pub fn genRandomUniform(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.randomUniform(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", ");
    if (args.len >= 3) {
        try self.emit("@intCast(");
        try self.genExpr(args[2]);
        try self.emit(")");
    } else {
        try self.emit("1");
    }
    try self.emit(", allocator)");
}

/// Generate numpy.random.choice() call
pub fn genRandomChoice(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.randomChoice(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    if (args.len >= 2) {
        try self.emit("@intCast(");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("1");
    }
    try self.emit(", allocator)");
}

/// Generate numpy.random.shuffle() call
pub fn genRandomShuffle(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.randomShuffle(");
    try self.genExpr(args[0]);
    try self.emit(")");
}

/// Generate numpy.random.permutation() call
pub fn genRandomPermutation(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.randomPermutation(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}
