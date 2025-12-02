/// NumPy function code generation
/// Generates calls to c_interop/numpy.zig for direct BLAS integration
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("main.zig").NativeCodegen;
const CodegenError = @import("main.zig").CodegenError;

/// Handler function type
const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;

// Comptime generator for simple 1-arg numpy functions: numpy.func(arr, allocator)
fn gen1Arg(comptime func_name: []const u8) ModuleHandler {
    return struct {
        fn handler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            if (args.len == 0) return;
            try self.emit("try numpy." ++ func_name ++ "(");
            try self.genExpr(args[0]);
            try self.emit(", allocator)");
        }
    }.handler;
}

// Comptime generator for simple 2-arg numpy functions: numpy.func(a, b, allocator)
fn gen2Arg(comptime func_name: []const u8) ModuleHandler {
    return struct {
        fn handler(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
            if (args.len < 2) return;
            try self.emit("try numpy." ++ func_name ++ "(");
            try self.genExpr(args[0]);
            try self.emit(", ");
            try self.genExpr(args[1]);
            try self.emit(", allocator)");
        }
    }.handler;
}

/// Module function map - exported for dispatch
pub const Funcs = std.StaticStringMap(ModuleHandler).initComptime(.{
    // Array creation (complex - keep custom handlers)
    .{ "array", genArray },
    .{ "zeros", genZeros },
    .{ "ones", genOnes },
    .{ "empty", genEmpty },
    .{ "full", genFull },
    .{ "eye", genEye },
    .{ "identity", genEye },
    .{ "arange", genArange },
    .{ "linspace", genLinspace },
    .{ "logspace", genLogspace },
    // Array manipulation (complex)
    .{ "reshape", genReshape },
    .{ "ravel", gen1Arg("ravel") },
    .{ "flatten", gen1Arg("ravel") },
    .{ "transpose", genTranspose },
    .{ "squeeze", gen1Arg("squeeze") },
    .{ "expand_dims", gen2Arg("expandDims") },
    // Element-wise math (simple 1-arg or 2-arg)
    .{ "add", gen2Arg("add") },
    .{ "subtract", gen2Arg("subtract") },
    .{ "multiply", gen2Arg("multiply") },
    .{ "divide", gen2Arg("divide") },
    .{ "power", gen2Arg("power") },
    .{ "sqrt", gen1Arg("sqrt") },
    .{ "exp", gen1Arg("exp") },
    .{ "log", gen1Arg("npLog") },
    .{ "sin", gen1Arg("sin") },
    .{ "cos", gen1Arg("cos") },
    .{ "abs", gen1Arg("npAbs") },
    // Reductions (simple 1-arg)
    .{ "sum", gen1Arg("sum") },
    .{ "mean", gen1Arg("mean") },
    .{ "std", gen1Arg("npStd") },
    .{ "var", gen1Arg("npVar") },
    .{ "min", gen1Arg("npMin") },
    .{ "max", gen1Arg("npMax") },
    .{ "argmin", gen1Arg("argmin") },
    .{ "argmax", gen1Arg("argmax") },
    .{ "prod", gen1Arg("prod") },
    // Linear algebra
    .{ "dot", gen2Arg("dot") },
    .{ "matmul", genMatmul },
    .{ "inner", gen2Arg("inner") },
    .{ "outer", gen2Arg("outer") },
    .{ "vdot", gen2Arg("vdot") },
    .{ "trace", gen1Arg("trace") },
    // Statistics
    .{ "median", gen1Arg("median") },
    .{ "percentile", gen2Arg("percentile") },
    // Array manipulation
    .{ "concatenate", genConcatenate },
    .{ "vstack", gen1Arg("vstack") },
    .{ "hstack", gen1Arg("hstack") },
    .{ "stack", gen2Arg("stack") },
    .{ "split", gen2Arg("split") },
    // Conditional and rounding
    .{ "where", genWhere },
    .{ "clip", genClip },
    .{ "floor", gen1Arg("floor") },
    .{ "ceil", gen1Arg("ceil") },
    .{ "round", gen1Arg("round") },
    .{ "rint", gen1Arg("round") },
    // Sorting and searching
    .{ "sort", gen1Arg("sort") },
    .{ "argsort", gen1Arg("argsort") },
    .{ "unique", gen1Arg("unique") },
    .{ "searchsorted", gen2Arg("searchsorted") },
    // Array copying
    .{ "copy", gen1Arg("copy") },
    .{ "asarray", gen1Arg("asarray") },
    // Repeating and flipping
    .{ "tile", gen2Arg("tile") },
    .{ "repeat", gen2Arg("repeat") },
    .{ "flip", gen1Arg("flip") },
    .{ "flipud", gen1Arg("flipud") },
    .{ "fliplr", gen1Arg("fliplr") },
    // Cumulative operations
    .{ "cumsum", gen1Arg("cumsum") },
    .{ "cumprod", gen1Arg("cumprod") },
    .{ "diff", gen1Arg("diff") },
    // Comparison
    .{ "allclose", gen2Arg("allclose") },
    .{ "array_equal", gen2Arg("arrayEqual") },
    // Matrix construction
    .{ "diag", gen1Arg("diag") },
    .{ "triu", gen1Arg("triu") },
    .{ "tril", gen1Arg("tril") },
    // Additional math (simple 1-arg)
    .{ "tan", gen1Arg("tan") },
    .{ "arcsin", gen1Arg("arcsin") },
    .{ "arccos", gen1Arg("arccos") },
    .{ "arctan", gen1Arg("arctan") },
    .{ "sinh", gen1Arg("sinh") },
    .{ "cosh", gen1Arg("cosh") },
    .{ "tanh", gen1Arg("tanh") },
    .{ "log10", gen1Arg("log10") },
    .{ "log2", gen1Arg("log2") },
    .{ "exp2", gen1Arg("exp2") },
    .{ "expm1", gen1Arg("expm1") },
    .{ "log1p", gen1Arg("log1p") },
    .{ "sign", gen1Arg("sign") },
    .{ "negative", gen1Arg("negative") },
    .{ "reciprocal", gen1Arg("reciprocal") },
    .{ "square", gen1Arg("square") },
    .{ "cbrt", gen1Arg("cbrt") },
    .{ "maximum", gen2Arg("maximum") },
    .{ "minimum", gen2Arg("minimum") },
    .{ "mod", genMod },
    .{ "remainder", genMod },
    // Array manipulation (roll, rot90, pad, take, put, cross)
    .{ "roll", genRoll },
    .{ "rot90", genRot90 },
    .{ "pad", genPad },
    .{ "take", genTake },
    .{ "put", genPut },
    .{ "cross", genCross },
    // Logical functions
    .{ "any", genAny },
    .{ "all", genAll },
    .{ "logical_and", genLogicalAnd },
    .{ "logical_or", genLogicalOr },
    .{ "logical_not", genLogicalNot },
    .{ "logical_xor", genLogicalXor },
    // Set functions
    .{ "setdiff1d", genSetdiff1d },
    .{ "union1d", genUnion1d },
    .{ "intersect1d", genIntersect1d },
    .{ "isin", genIsin },
    // Numerical functions
    .{ "gradient", genGradient },
    .{ "trapz", genTrapz },
    .{ "interp", genInterp },
    .{ "convolve", genConvolve },
    .{ "correlate", genCorrelate },
    // Utility functions
    .{ "nonzero", genNonzero },
    .{ "count_nonzero", genCountNonzero },
    .{ "flatnonzero", genFlatnonzero },
    .{ "meshgrid", genMeshgrid },
    .{ "histogram", genHistogram },
    .{ "bincount", genBincount },
    .{ "digitize", genDigitize },
    .{ "nan_to_num", genNanToNum },
    .{ "isnan", genIsnan },
    .{ "isinf", genIsinf },
    .{ "isfinite", genIsfinite },
    .{ "absolute", genAbsolute },
    .{ "fabs", genAbsolute },
});

/// NumPy linalg module functions
pub const LinalgFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "norm", gen1Arg("norm") },
    .{ "det", gen1Arg("det") },
    .{ "inv", gen1Arg("inv") },
    .{ "solve", gen2Arg("solve") },
    .{ "qr", gen1Arg("qr") },
    .{ "cholesky", gen1Arg("cholesky") },
    .{ "eig", gen1Arg("eig") },
    .{ "svd", gen1Arg("svd") },
    .{ "lstsq", gen2Arg("lstsq") },
});

/// NumPy random module functions
pub const RandomFuncs = std.StaticStringMap(ModuleHandler).initComptime(.{
    .{ "seed", genRandomSeed },
    .{ "rand", genRandomRand },
    .{ "randn", genRandomRandn },
    .{ "randint", genRandomRandint },
    .{ "uniform", genRandomUniform },
    .{ "choice", genRandomChoice },
    .{ "shuffle", genRandomShuffle },
    .{ "permutation", genRandomPermutation },
});

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

// Logical functions use gen1Arg/gen2Arg via comptime generators
fn genAny(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try numpy.npAny(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

fn genAll(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try numpy.npAll(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

fn genLogicalAnd(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("try numpy.logical_and(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

fn genLogicalOr(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("try numpy.logical_or(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

fn genLogicalNot(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try numpy.logical_not(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

fn genLogicalXor(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("try numpy.logical_xor(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

fn genSetdiff1d(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("try numpy.setdiff1d(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

fn genUnion1d(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("try numpy.union1d(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

fn genIntersect1d(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("try numpy.intersect1d(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

fn genIsin(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("try numpy.isin(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

fn genGradient(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try numpy.gradient(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

fn genTrapz(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try numpy.trapz(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    if (args.len > 1) {
        try self.genExpr(args[1]);
    } else {
        try self.emit("1.0");
    }
    try self.emit(", allocator)");
}

fn genInterp(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 3) return;
    try self.emit("try numpy.interp(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", ");
    try self.genExpr(args[2]);
    try self.emit(", allocator)");
}

fn genConvolve(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("try numpy.convolve(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

fn genCorrelate(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("try numpy.correlate(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

fn genNonzero(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try numpy.nonzero(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

fn genCountNonzero(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try numpy.count_nonzero(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

fn genFlatnonzero(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try numpy.flatnonzero(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

fn genMeshgrid(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("try numpy.meshgrid(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

fn genHistogram(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try numpy.histogram(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    if (args.len > 1) {
        try self.emit("@intCast(");
        try self.genExpr(args[1]);
        try self.emit(")");
    } else {
        try self.emit("10");
    }
    try self.emit(", allocator)");
}

fn genBincount(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try numpy.bincount(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

fn genDigitize(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len < 2) return;
    try self.emit("try numpy.digitize(");
    try self.genExpr(args[0]);
    try self.emit(", ");
    try self.genExpr(args[1]);
    try self.emit(", allocator)");
}

fn genNanToNum(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try numpy.nan_to_num(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

fn genIsnan(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try numpy.isnan(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

fn genIsinf(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try numpy.isinf(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

fn genIsfinite(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try numpy.isfinite(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}

fn genAbsolute(self: *NativeCodegen, args: []ast.Node) CodegenError!void {
    if (args.len == 0) return;
    try self.emit("try numpy.absolute(");
    try self.genExpr(args[0]);
    try self.emit(", allocator)");
}
