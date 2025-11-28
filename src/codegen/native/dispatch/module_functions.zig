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
});

/// NumPy linalg module functions
const NumpyLinalgFuncs = FuncMap.initComptime(.{
    .{ "norm", numpy_mod.genNorm },
    .{ "det", numpy_mod.genDet },
    .{ "inv", numpy_mod.genInv },
    .{ "solve", numpy_mod.genSolve },
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
