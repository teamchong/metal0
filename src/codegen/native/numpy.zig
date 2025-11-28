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
        if (elements.len == 0) {
            try self.emit("try numpy.arrayFloat(&[_]f64{}, allocator)");
            return;
        }

        // Check if first element is also a list (2D array)
        if (elements[0] == .list) {
            // 2D array - [[1, 2], [3, 4]]
            const rows = elements.len;
            const cols = elements[0].list.elts.len;

            // Flatten to 1D and call array2D
            try self.emit("try numpy.array2D(&[_]f64{");
            var first = true;
            for (elements) |row| {
                if (row == .list) {
                    for (row.list.elts) |elem| {
                        if (!first) try self.emit(", ");
                        first = false;
                        try self.emit("@as(f64, ");
                        try self.genExpr(elem);
                        try self.emit(")");
                    }
                }
            }
            try self.emitFmt("}}, {d}, {d}, allocator)", .{ rows, cols });
        } else {
            // 1D array - [1, 2, 3]
            // Determine element type from first element
            const elem_type = try self.type_inferrer.inferExpr(elements[0]);

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
// Array Manipulation Functions
// ============================================================================

/// Generate numpy.concatenate() call
pub fn genConcatenate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    // Expect first arg to be a list of arrays: np.concatenate([a, b, c])
    const arg = args[0];
    if (arg == .list) {
        const arrays = arg.list.elts;
        try self.emit("try numpy.concatenate(&[_]*runtime.PyObject{");
        for (arrays, 0..) |arr, i| {
            if (i > 0) try self.emit(", ");
            try self.genExpr(arr);
        }
        try self.emit("}, allocator)");
    } else {
        // Single array or variable - just pass through
        try self.emit("try numpy.concatenate(&[_]*runtime.PyObject{");
        try self.genExpr(arg);
        try self.emit("}, allocator)");
    }
}

/// Generate numpy.vstack() call - vertical stack (row-wise)
pub fn genVstack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    const arg = args[0];
    if (arg == .list) {
        const arrays = arg.list.elts;
        try self.emit("try numpy.vstack(&[_]*runtime.PyObject{");
        for (arrays, 0..) |arr, i| {
            if (i > 0) try self.emit(", ");
            try self.genExpr(arr);
        }
        try self.emit("}, allocator)");
    } else {
        try self.emit("try numpy.vstack(&[_]*runtime.PyObject{");
        try self.genExpr(arg);
        try self.emit("}, allocator)");
    }
}

/// Generate numpy.hstack() call - horizontal stack (column-wise)
pub fn genHstack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    const arg = args[0];
    if (arg == .list) {
        const arrays = arg.list.elts;
        try self.emit("try numpy.hstack(&[_]*runtime.PyObject{");
        for (arrays, 0..) |arr, i| {
            if (i > 0) try self.emit(", ");
            try self.genExpr(arr);
        }
        try self.emit("}, allocator)");
    } else {
        try self.emit("try numpy.hstack(&[_]*runtime.PyObject{");
        try self.genExpr(arg);
        try self.emit("}, allocator)");
    }
}

/// Generate numpy.stack() call - stack along new axis
pub fn genStack(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    const arg = args[0];
    if (arg == .list) {
        const arrays = arg.list.elts;
        try self.emit("try numpy.stack(&[_]*runtime.PyObject{");
        for (arrays, 0..) |arr, i| {
            if (i > 0) try self.emit(", ");
            try self.genExpr(arr);
        }
        try self.emit("}, allocator)");
    } else {
        try self.emit("try numpy.stack(&[_]*runtime.PyObject{");
        try self.genExpr(arg);
        try self.emit("}, allocator)");
    }
}

/// Generate numpy.split() call - split array into sub-arrays
pub fn genSplit(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.split(");
    try self.genExpr(args[0]); // array
    try self.emit(", @intCast(");
    try self.genExpr(args[1]); // num sections
    try self.emit("), allocator)");
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

// ============================================================================
// Conditional and Rounding Functions
// ============================================================================

/// Generate numpy.where() call - np.where(cond, x, y)
pub fn genWhere(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) return;

    try self.emit("try numpy.where(");
    try self.genExpr(args[0]); // condition
    try self.emit(", ");
    try self.genExpr(args[1]); // x
    try self.emit(", ");
    try self.genExpr(args[2]); // y
    try self.emit(", allocator)");
}

/// Generate numpy.clip() call - np.clip(arr, min, max)
pub fn genClip(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) return;

    try self.emit("try numpy.clip(");
    try self.genExpr(args[0]); // array
    try self.emit(", ");
    try self.genExpr(args[1]); // min
    try self.emit(", ");
    try self.genExpr(args[2]); // max
    try self.emit(", allocator)");
}

/// Generate numpy.floor() call
pub fn genFloor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.floor(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.ceil() call
pub fn genCeil(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.ceil(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.round() or numpy.rint() call
pub fn genRound(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.npRound(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

// ============================================================================
// Sorting and Searching Functions
// ============================================================================

/// Generate numpy.sort() call
pub fn genSort(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.sort(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.argsort() call
pub fn genArgsort(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.argsort(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.unique() call
pub fn genUnique(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.unique(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.searchsorted() call
pub fn genSearchsorted(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.searchsorted(");
    try self.genExpr(args[0]); // array
    try self.emit(", ");
    try self.genExpr(args[1]); // value
    try self.emit(", allocator)");
}

// ============================================================================
// Array Copying Functions
// ============================================================================

/// Generate numpy.copy() call
pub fn genCopy(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.copy(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.asarray() call
pub fn genAsarray(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.asarray(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

// ============================================================================
// Repeating and Flipping Functions
// ============================================================================

/// Generate numpy.tile() call - np.tile(arr, reps)
pub fn genTile(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.tile(");
    try self.genExpr(args[0]); // array
    try self.emit(", @intCast(");
    try self.genExpr(args[1]); // reps
    try self.emit("), allocator)");
}

/// Generate numpy.repeat() call - np.repeat(arr, reps)
pub fn genRepeat(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.repeat(");
    try self.genExpr(args[0]); // array
    try self.emit(", @intCast(");
    try self.genExpr(args[1]); // reps
    try self.emit("), allocator)");
}

/// Generate numpy.flip() call
pub fn genFlip(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.flip(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.flipud() call
pub fn genFlipud(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.flipud(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.fliplr() call
pub fn genFliplr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.fliplr(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

// ============================================================================
// Cumulative Operations
// ============================================================================

/// Generate numpy.cumsum() call
pub fn genCumsum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.cumsum(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.cumprod() call
pub fn genCumprod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.cumprod(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.diff() call
pub fn genDiff(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.diff(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

// ============================================================================
// Comparison Functions
// ============================================================================

/// Generate numpy.allclose() call - np.allclose(a, b, rtol, atol)
pub fn genAllclose(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.allclose(");
    try self.genExpr(args[0]); // a
    try self.emit(", ");
    try self.genExpr(args[1]); // b
    try self.emit(", ");
    // rtol (default 1e-5)
    if (args.len > 2) {
        try self.genExpr(args[2]);
    } else {
        try self.emit("1e-5");
    }
    try self.emit(", ");
    // atol (default 1e-8)
    if (args.len > 3) {
        try self.genExpr(args[3]);
    } else {
        try self.emit("1e-8");
    }
    try self.emit(", allocator)");
}

/// Generate numpy.array_equal() call
pub fn genArrayEqual(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.array_equal(");
    try self.genExpr(args[0]); // a
    try self.emit(", ");
    try self.genExpr(args[1]); // b
    try self.emit(", allocator)");
}

// ============================================================================
// Matrix Construction Functions
// ============================================================================

/// Generate numpy.diag() call
pub fn genDiag(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.diag(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.triu() call
pub fn genTriu(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.triu(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.tril() call
pub fn genTril(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.tril(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

// ============================================================================
// Additional Math Functions
// ============================================================================

/// Generate numpy.tan() call
pub fn genTan(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.tan(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.arcsin() call
pub fn genArcsin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.arcsin(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.arccos() call
pub fn genArccos(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.arccos(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.arctan() call
pub fn genArctan(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.arctan(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.sinh() call
pub fn genSinh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.sinh(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.cosh() call
pub fn genCosh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.cosh(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.tanh() call
pub fn genTanh(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.tanh(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.log10() call
pub fn genLog10(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.log10(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.log2() call
pub fn genLog2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.log2(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.exp2() call
pub fn genExp2(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.exp2(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.expm1() call
pub fn genExpm1(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.expm1(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.log1p() call
pub fn genLog1p(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.log1p(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.sign() call
pub fn genSign(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.sign(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.negative() call
pub fn genNegative(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.negative(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.reciprocal() call
pub fn genReciprocal(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.reciprocal(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.square() call
pub fn genSquare(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.square(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.cbrt() call
pub fn genCbrt(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.cbrt(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.maximum() call - np.maximum(a, b)
pub fn genMaximum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.maximum(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.minimum() call - np.minimum(a, b)
pub fn genMinimum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.minimum(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.mod() or numpy.remainder() call - np.mod(a, b)
pub fn genMod(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.mod(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

// ============================================================================
// Array Manipulation Functions (roll, rot90, pad, take, put, cross)
// ============================================================================

/// Generate numpy.roll() call - np.roll(arr, shift)
pub fn genRoll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.roll(");
    try self.genExpr(args[0]); // array
    try self.emit(", @intCast(");
    try self.genExpr(args[1]); // shift
    try self.emit("), allocator)");
}

/// Generate numpy.rot90() call - np.rot90(arr, k=1)
pub fn genRot90(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.rot90(");
    try self.genExpr(args[0]); // array
    try self.emit(", ");
    if (args.len > 1) {
        try self.emit("@intCast(");
        try self.genExpr(args[1]); // k
        try self.emit(")");
    } else {
        try self.emit("1");
    }
    try self.emit(", allocator)");
}

/// Generate numpy.pad() call - np.pad(arr, pad_width, mode='constant')
pub fn genPad(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.pad(");
    try self.genExpr(args[0]); // array
    try self.emit(", @intCast(");
    try self.genExpr(args[1]); // pad_width
    try self.emit("), allocator)");
}

/// Generate numpy.take() call - np.take(arr, indices)
pub fn genTake(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.take(");
    try self.genExpr(args[0]); // array
    try self.emit(", ");
    try self.genExpr(args[1]); // indices
    try self.emit(", allocator)");
}

/// Generate numpy.put() call - np.put(arr, indices, values)
pub fn genPut(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) return;

    try self.emit("try numpy.put(");
    try self.genExpr(args[0]); // array
    try self.emit(", ");
    try self.genExpr(args[1]); // indices
    try self.emit(", ");
    try self.genExpr(args[2]); // values
    try self.emit(", allocator)");
}

/// Generate numpy.cross() call - np.cross(a, b)
pub fn genCross(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.cross(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

// ============================================================================
// Logical Functions (any, all, logical_and/or/not/xor)
// ============================================================================

/// Generate numpy.any() call
pub fn genAny(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.npAny(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.all() call
pub fn genAll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.npAll(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.logical_and() call
pub fn genLogicalAnd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.logical_and(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.logical_or() call
pub fn genLogicalOr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.logical_or(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.logical_not() call
pub fn genLogicalNot(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.logical_not(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.logical_xor() call
pub fn genLogicalXor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.logical_xor(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

// ============================================================================
// Set Functions (setdiff1d, union1d, intersect1d, isin)
// ============================================================================

/// Generate numpy.setdiff1d() call
pub fn genSetdiff1d(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.setdiff1d(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.union1d() call
pub fn genUnion1d(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.union1d(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.intersect1d() call
pub fn genIntersect1d(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.intersect1d(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.isin() call
pub fn genIsin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.isin(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

// ============================================================================
// Numerical Functions (gradient, trapz, interp, convolve, correlate)
// ============================================================================

/// Generate numpy.gradient() call
pub fn genGradient(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.gradient(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.trapz() call - np.trapz(y, dx=1.0)
pub fn genTrapz(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.trapz(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    if (args.len > 1) {
        try self.genExpr(args[1]); // dx
    } else {
        try self.emit("1.0"); // default dx
    }
    try self.emit(", allocator)");
}

/// Generate numpy.interp() call - np.interp(x, xp, fp)
pub fn genInterp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) return;

    try self.emit("try numpy.interp(");
    try self.genExpr(args[0]); // x
    try self.emit(", ");
    try self.genExpr(args[1]); // xp
    try self.emit(", ");
    try self.genExpr(args[2]); // fp
    try self.emit(", allocator)");
}

/// Generate numpy.convolve() call - np.convolve(a, v, mode='full')
pub fn genConvolve(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.convolve(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.correlate() call - np.correlate(a, v, mode='valid')
pub fn genCorrelate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.correlate(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

// ============================================================================
// Utility Functions (nonzero, count_nonzero, meshgrid, histogram, etc.)
// ============================================================================

/// Generate numpy.nonzero() call
pub fn genNonzero(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.nonzero(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.count_nonzero() call
pub fn genCountNonzero(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.count_nonzero(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.flatnonzero() call
pub fn genFlatnonzero(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.flatnonzero(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.meshgrid() call - np.meshgrid(x, y)
pub fn genMeshgrid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.meshgrid(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.histogram() call
pub fn genHistogram(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.histogram(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    if (args.len > 1) {
        try self.emit("@intCast(");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("10"); // default bins
    }
    try self.emit(", allocator)");
}

/// Generate numpy.bincount() call
pub fn genBincount(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.bincount(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.digitize() call - np.digitize(x, bins)
pub fn genDigitize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.digitize(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

/// Generate numpy.nan_to_num() call
pub fn genNanToNum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.nan_to_num(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.isnan() call
pub fn genIsnan(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.isnan(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.isinf() call
pub fn genIsinf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.isinf(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.isfinite() call
pub fn genIsfinite(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.isfinite(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.absolute() or numpy.fabs() call
pub fn genAbsolute(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.absolute(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

// ============================================================================
// Advanced Linear Algebra Functions (linalg module)
// ============================================================================

/// Generate numpy.linalg.qr() call - QR decomposition
pub fn genQr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.qr(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.linalg.cholesky() call - Cholesky decomposition
pub fn genCholesky(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.cholesky(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.linalg.eig() call - Eigenvalue decomposition
pub fn genEig(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.eig(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.linalg.svd() call - Singular Value Decomposition
pub fn genSvd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;

    try self.emit("try numpy.svd(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

/// Generate numpy.linalg.lstsq() call - Least squares solution
pub fn genLstsq(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;

    try self.emit("try numpy.lstsq(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}
