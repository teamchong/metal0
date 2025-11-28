/// Module function dispatchers (json, http, asyncio, numpy, pandas, os)
const std = @import("std");
const ast = @import("ast");
const NativeCodegen = @import("../main.zig").NativeCodegen;
const CodegenError = @import("../main.zig").CodegenError;

// Import specialized handlers
const json = @import("../json.zig");
const http = @import("../http.zig");
const async_mod = @import("../async.zig");
const numpy_mod = @import("../numpy.zig");
const pandas_mod = @import("../pandas.zig");
const unittest_mod = @import("../unittest/mod.zig");
const re_mod = @import("../re.zig");
const os_mod = @import("../os.zig");
const pathlib_mod = @import("../pathlib.zig");
const datetime_mod = @import("../datetime.zig");
const io_mod = @import("../io.zig");
const collections_mod = @import("../collections_mod.zig");
const functools_mod = @import("../functools_mod.zig");
const itertools_mod = @import("../itertools_mod.zig");

/// Handler function type for module dispatchers
const ModuleHandler = *const fn (*NativeCodegen, []ast.Node) CodegenError!void;
const FuncMap = std.StaticStringMap(ModuleHandler);

/// JSON module functions (O(1) lookup)
const JsonFuncs = FuncMap.initComptime(.{
    .{ "loads", json.genJsonLoads },
    .{ "dumps", json.genJsonDumps },
});

/// HTTP module functions
const HttpFuncs = FuncMap.initComptime(.{
    .{ "get", http.genHttpGet },
    .{ "post", http.genHttpPost },
});

/// Asyncio module functions
const AsyncioFuncs = FuncMap.initComptime(.{
    .{ "run", async_mod.genAsyncioRun },
    .{ "gather", async_mod.genAsyncioGather },
    .{ "create_task", async_mod.genAsyncioCreateTask },
    .{ "sleep", async_mod.genAsyncioSleep },
    .{ "Queue", async_mod.genAsyncioQueue },
});

/// NumPy module functions
const NumpyFuncs = FuncMap.initComptime(.{
    // Array creation
    .{ "array", numpy_mod.genArray },
    .{ "zeros", numpy_mod.genZeros },
    .{ "ones", numpy_mod.genOnes },
    .{ "empty", numpy_mod.genEmpty },
    .{ "full", numpy_mod.genFull },
    .{ "eye", numpy_mod.genEye },
    .{ "identity", numpy_mod.genEye },
    .{ "arange", numpy_mod.genArange },
    .{ "linspace", numpy_mod.genLinspace },
    .{ "logspace", numpy_mod.genLogspace },
    // Array manipulation
    .{ "reshape", numpy_mod.genReshape },
    .{ "ravel", numpy_mod.genRavel },
    .{ "flatten", numpy_mod.genRavel },
    .{ "transpose", numpy_mod.genTranspose },
    .{ "squeeze", numpy_mod.genSqueeze },
    .{ "expand_dims", numpy_mod.genExpandDims },
    // Element-wise math
    .{ "add", numpy_mod.genAdd },
    .{ "subtract", numpy_mod.genSubtract },
    .{ "multiply", numpy_mod.genMultiply },
    .{ "divide", numpy_mod.genDivide },
    .{ "power", numpy_mod.genPower },
    .{ "sqrt", numpy_mod.genSqrt },
    .{ "exp", numpy_mod.genExp },
    .{ "log", numpy_mod.genLog },
    .{ "sin", numpy_mod.genSin },
    .{ "cos", numpy_mod.genCos },
    .{ "abs", numpy_mod.genAbs },
    // Reductions
    .{ "sum", numpy_mod.genSum },
    .{ "mean", numpy_mod.genMean },
    .{ "std", numpy_mod.genStd },
    .{ "var", numpy_mod.genVar },
    .{ "min", numpy_mod.genMin },
    .{ "max", numpy_mod.genMax },
    .{ "argmin", numpy_mod.genArgmin },
    .{ "argmax", numpy_mod.genArgmax },
    .{ "prod", numpy_mod.genProd },
    // Linear algebra
    .{ "dot", numpy_mod.genDot },
    .{ "matmul", numpy_mod.genMatmul },
    .{ "inner", numpy_mod.genInner },
    .{ "outer", numpy_mod.genOuter },
    .{ "vdot", numpy_mod.genVdot },
    .{ "trace", numpy_mod.genTrace },
    // Statistics
    .{ "median", numpy_mod.genMedian },
    .{ "percentile", numpy_mod.genPercentile },
    // Array manipulation
    .{ "concatenate", numpy_mod.genConcatenate },
    .{ "vstack", numpy_mod.genVstack },
    .{ "hstack", numpy_mod.genHstack },
    .{ "stack", numpy_mod.genStack },
    .{ "split", numpy_mod.genSplit },
    // Conditional and rounding
    .{ "where", numpy_mod.genWhere },
    .{ "clip", numpy_mod.genClip },
    .{ "floor", numpy_mod.genFloor },
    .{ "ceil", numpy_mod.genCeil },
    .{ "round", numpy_mod.genRound },
    .{ "rint", numpy_mod.genRound },
    // Sorting and searching
    .{ "sort", numpy_mod.genSort },
    .{ "argsort", numpy_mod.genArgsort },
    .{ "unique", numpy_mod.genUnique },
    .{ "searchsorted", numpy_mod.genSearchsorted },
    // Array copying
    .{ "copy", numpy_mod.genCopy },
    .{ "asarray", numpy_mod.genAsarray },
    // Repeating and flipping
    .{ "tile", numpy_mod.genTile },
    .{ "repeat", numpy_mod.genRepeat },
    .{ "flip", numpy_mod.genFlip },
    .{ "flipud", numpy_mod.genFlipud },
    .{ "fliplr", numpy_mod.genFliplr },
    // Cumulative operations
    .{ "cumsum", numpy_mod.genCumsum },
    .{ "cumprod", numpy_mod.genCumprod },
    .{ "diff", numpy_mod.genDiff },
    // Comparison
    .{ "allclose", numpy_mod.genAllclose },
    .{ "array_equal", numpy_mod.genArrayEqual },
    // Matrix construction
    .{ "diag", numpy_mod.genDiag },
    .{ "triu", numpy_mod.genTriu },
    .{ "tril", numpy_mod.genTril },
    // Additional math
    .{ "tan", numpy_mod.genTan },
    .{ "arcsin", numpy_mod.genArcsin },
    .{ "arccos", numpy_mod.genArccos },
    .{ "arctan", numpy_mod.genArctan },
    .{ "sinh", numpy_mod.genSinh },
    .{ "cosh", numpy_mod.genCosh },
    .{ "tanh", numpy_mod.genTanh },
    .{ "log10", numpy_mod.genLog10 },
    .{ "log2", numpy_mod.genLog2 },
    .{ "exp2", numpy_mod.genExp2 },
    .{ "expm1", numpy_mod.genExpm1 },
    .{ "log1p", numpy_mod.genLog1p },
    .{ "sign", numpy_mod.genSign },
    .{ "negative", numpy_mod.genNegative },
    .{ "reciprocal", numpy_mod.genReciprocal },
    .{ "square", numpy_mod.genSquare },
    .{ "cbrt", numpy_mod.genCbrt },
    .{ "maximum", numpy_mod.genMaximum },
    .{ "minimum", numpy_mod.genMinimum },
    .{ "mod", numpy_mod.genMod },
    .{ "remainder", numpy_mod.genMod },
    // Array manipulation (roll, rot90, pad, take, put, cross)
    .{ "roll", numpy_mod.genRoll },
    .{ "rot90", numpy_mod.genRot90 },
    .{ "pad", numpy_mod.genPad },
    .{ "take", numpy_mod.genTake },
    .{ "put", numpy_mod.genPut },
    .{ "cross", numpy_mod.genCross },
    // Logical functions
    .{ "any", numpy_mod.genAny },
    .{ "all", numpy_mod.genAll },
    .{ "logical_and", numpy_mod.genLogicalAnd },
    .{ "logical_or", numpy_mod.genLogicalOr },
    .{ "logical_not", numpy_mod.genLogicalNot },
    .{ "logical_xor", numpy_mod.genLogicalXor },
    // Set functions
    .{ "setdiff1d", numpy_mod.genSetdiff1d },
    .{ "union1d", numpy_mod.genUnion1d },
    .{ "intersect1d", numpy_mod.genIntersect1d },
    .{ "isin", numpy_mod.genIsin },
    // Numerical functions
    .{ "gradient", numpy_mod.genGradient },
    .{ "trapz", numpy_mod.genTrapz },
    .{ "interp", numpy_mod.genInterp },
    .{ "convolve", numpy_mod.genConvolve },
    .{ "correlate", numpy_mod.genCorrelate },
    // Utility functions
    .{ "nonzero", numpy_mod.genNonzero },
    .{ "count_nonzero", numpy_mod.genCountNonzero },
    .{ "flatnonzero", numpy_mod.genFlatnonzero },
    .{ "meshgrid", numpy_mod.genMeshgrid },
    .{ "histogram", numpy_mod.genHistogram },
    .{ "bincount", numpy_mod.genBincount },
    .{ "digitize", numpy_mod.genDigitize },
    .{ "nan_to_num", numpy_mod.genNanToNum },
    .{ "isnan", numpy_mod.genIsnan },
    .{ "isinf", numpy_mod.genIsinf },
    .{ "isfinite", numpy_mod.genIsfinite },
    .{ "absolute", numpy_mod.genAbsolute },
    .{ "fabs", numpy_mod.genAbsolute },
});

/// NumPy linalg module functions
const NumpyLinalgFuncs = FuncMap.initComptime(.{
    .{ "norm", numpy_mod.genNorm },
    .{ "det", numpy_mod.genDet },
    .{ "inv", numpy_mod.genInv },
    .{ "solve", numpy_mod.genSolve },
    .{ "qr", numpy_mod.genQr },
    .{ "cholesky", numpy_mod.genCholesky },
    .{ "eig", numpy_mod.genEig },
    .{ "svd", numpy_mod.genSvd },
    .{ "lstsq", numpy_mod.genLstsq },
});

/// NumPy random module functions
const NumpyRandomFuncs = FuncMap.initComptime(.{
    .{ "seed", numpy_mod.genRandomSeed },
    .{ "rand", numpy_mod.genRandomRand },
    .{ "randn", numpy_mod.genRandomRandn },
    .{ "randint", numpy_mod.genRandomRandint },
    .{ "uniform", numpy_mod.genRandomUniform },
    .{ "choice", numpy_mod.genRandomChoice },
    .{ "shuffle", numpy_mod.genRandomShuffle },
    .{ "permutation", numpy_mod.genRandomPermutation },
});

/// Pandas module functions
const PandasFuncs = FuncMap.initComptime(.{
    .{ "DataFrame", pandas_mod.genDataFrame },
});

/// unittest module functions
const UnittestFuncs = FuncMap.initComptime(.{
    .{ "main", unittest_mod.genUnittestMain },
});

/// RE module functions
const ReFuncs = FuncMap.initComptime(.{
    .{ "search", re_mod.genReSearch },
    .{ "match", re_mod.genReMatch },
    .{ "sub", re_mod.genReSub },
    .{ "findall", re_mod.genReFindall },
    .{ "compile", re_mod.genReCompile },
});

/// OS module functions
const OsFuncs = FuncMap.initComptime(.{
    .{ "getcwd", os_mod.genGetcwd },
    .{ "chdir", os_mod.genChdir },
    .{ "listdir", os_mod.genListdir },
});

/// OS.path module functions
const OsPathFuncs = FuncMap.initComptime(.{
    .{ "exists", os_mod.genPathExists },
    .{ "join", os_mod.genPathJoin },
    .{ "dirname", os_mod.genPathDirname },
    .{ "basename", os_mod.genPathBasename },
});

/// Pathlib module functions
const PathlibFuncs = FuncMap.initComptime(.{
    .{ "Path", pathlib_mod.genPath },
});

/// datetime.datetime module functions (for datetime.datetime.now())
const DatetimeDatetimeFuncs = FuncMap.initComptime(.{
    .{ "now", datetime_mod.genDatetimeNow },
});

/// datetime.date module functions (for datetime.date.today())
const DatetimeDateFuncs = FuncMap.initComptime(.{
    .{ "today", datetime_mod.genDateToday },
});

/// datetime module functions (for datetime.timedelta())
const DatetimeFuncs = FuncMap.initComptime(.{
    .{ "timedelta", datetime_mod.genTimedelta },
});

/// IO module functions
const IoFuncs = FuncMap.initComptime(.{
    .{ "StringIO", io_mod.genStringIO },
    .{ "BytesIO", io_mod.genBytesIO },
    .{ "open", io_mod.genOpen },
});

/// collections module functions
const CollectionsFuncs = FuncMap.initComptime(.{
    .{ "Counter", collections_mod.genCounter },
    .{ "defaultdict", collections_mod.genDefaultdict },
    .{ "deque", collections_mod.genDeque },
    .{ "OrderedDict", collections_mod.genOrderedDict },
    .{ "namedtuple", collections_mod.genNamedtuple },
});

/// functools module functions
const FunctoolsFuncs = FuncMap.initComptime(.{
    .{ "partial", functools_mod.genPartial },
    .{ "reduce", functools_mod.genReduce },
    .{ "lru_cache", functools_mod.genLruCache },
    .{ "cache", functools_mod.genCache },
    .{ "wraps", functools_mod.genWraps },
    .{ "cmp_to_key", functools_mod.genCmpToKey },
    .{ "total_ordering", functools_mod.genTotalOrdering },
});

/// itertools module functions
const ItertoolsFuncs = FuncMap.initComptime(.{
    .{ "chain", itertools_mod.genChain },
    .{ "repeat", itertools_mod.genRepeat },
    .{ "count", itertools_mod.genCount },
    .{ "cycle", itertools_mod.genCycle },
    .{ "islice", itertools_mod.genIslice },
    .{ "zip_longest", itertools_mod.genZipLongest },
    .{ "product", itertools_mod.genProduct },
    .{ "permutations", itertools_mod.genPermutations },
    .{ "combinations", itertools_mod.genCombinations },
    .{ "groupby", itertools_mod.genGroupby },
});

/// Module to function map lookup
const ModuleMap = std.StaticStringMap(FuncMap).initComptime(.{
    .{ "json", JsonFuncs },
    .{ "http", HttpFuncs },
    .{ "asyncio", AsyncioFuncs },
    .{ "numpy", NumpyFuncs },
    .{ "np", NumpyFuncs },
    .{ "numpy.linalg", NumpyLinalgFuncs },
    .{ "np.linalg", NumpyLinalgFuncs },
    .{ "linalg", NumpyLinalgFuncs },
    .{ "numpy.random", NumpyRandomFuncs },
    .{ "np.random", NumpyRandomFuncs },
    .{ "pandas", PandasFuncs },
    .{ "pd", PandasFuncs },
    .{ "unittest", UnittestFuncs },
    .{ "re", ReFuncs },
    .{ "os", OsFuncs },
    .{ "os.path", OsPathFuncs },
    .{ "path", OsPathFuncs }, // for "from os import path" then path.exists()
    .{ "pathlib", PathlibFuncs },
    .{ "datetime", DatetimeFuncs },
    .{ "datetime.datetime", DatetimeDatetimeFuncs },
    .{ "datetime.date", DatetimeDateFuncs },
    .{ "io", IoFuncs },
    .{ "collections", CollectionsFuncs },
    .{ "functools", FunctoolsFuncs },
    .{ "itertools", ItertoolsFuncs },
});

/// Try to dispatch module function call (e.g., json.loads, numpy.array)
/// Returns true if dispatched successfully
pub fn tryDispatch(self: *NativeCodegen, module_name: []const u8, func_name: []const u8, call: ast.Node.Call) CodegenError!bool {
    // Check for importlib.import_module() (defensive - import already blocked)
    if (std.mem.eql(u8, module_name, "importlib") and
        std.mem.eql(u8, func_name, "import_module"))
    {
        std.debug.print("\nError: importlib.import_module() not supported in AOT compilation\n", .{});
        std.debug.print("   |\n", .{});
        std.debug.print("   = PyAOT resolves all imports at compile time\n", .{});
        std.debug.print("   = Dynamic runtime module loading not supported\n", .{});
        std.debug.print("   = Suggestion: Use static imports (import json) instead\n", .{});
        return error.OutOfMemory;
    }

    // O(1) module lookup, then O(1) function lookup
    if (ModuleMap.get(module_name)) |func_map| {
        if (func_map.get(func_name)) |handler| {
            try handler(self, call.args);
            return true;
        }
    }

    return false;
}
