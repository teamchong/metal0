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
const copy_mod = @import("../copy_mod.zig");
const typing_mod = @import("../typing_mod.zig");
const contextlib_mod = @import("../contextlib_mod.zig");
const hashlib_mod = @import("../hashlib_mod.zig");
const struct_mod = @import("../struct_mod.zig");
const base64_mod = @import("../base64_mod.zig");
const random_mod = @import("../random_mod.zig");
const string_mod = @import("../string_mod.zig");
const time_mod = @import("../time_mod.zig");
const sys_mod = @import("../sys_mod.zig");
const uuid_mod = @import("../uuid_mod.zig");
const subprocess_mod = @import("../subprocess_mod.zig");
const tempfile_mod = @import("../tempfile_mod.zig");
const textwrap_mod = @import("../textwrap_mod.zig");
const shutil_mod = @import("../shutil_mod.zig");

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

/// copy module functions
const CopyFuncs = FuncMap.initComptime(.{
    .{ "copy", copy_mod.genCopy },
    .{ "deepcopy", copy_mod.genDeepcopy },
});

/// typing module functions (type hints - mostly no-ops)
const TypingFuncs = FuncMap.initComptime(.{
    .{ "Optional", typing_mod.genOptional },
    .{ "List", typing_mod.genList },
    .{ "Dict", typing_mod.genDict },
    .{ "Set", typing_mod.genSet },
    .{ "Tuple", typing_mod.genTuple },
    .{ "Union", typing_mod.genUnion },
    .{ "Any", typing_mod.genAny },
    .{ "Callable", typing_mod.genCallable },
    .{ "TypeVar", typing_mod.genTypeVar },
    .{ "Generic", typing_mod.genGeneric },
    .{ "cast", typing_mod.genCast },
    .{ "get_type_hints", typing_mod.genGetTypeHints },
});

/// contextlib module functions
const ContextlibFuncs = FuncMap.initComptime(.{
    .{ "contextmanager", contextlib_mod.genContextmanager },
    .{ "suppress", contextlib_mod.genSuppress },
    .{ "redirect_stdout", contextlib_mod.genRedirectStdout },
    .{ "redirect_stderr", contextlib_mod.genRedirectStderr },
    .{ "closing", contextlib_mod.genClosing },
    .{ "nullcontext", contextlib_mod.genNullcontext },
    .{ "ExitStack", contextlib_mod.genExitStack },
});

/// hashlib module functions
const HashlibFuncs = FuncMap.initComptime(.{
    .{ "md5", hashlib_mod.genMd5 },
    .{ "sha1", hashlib_mod.genSha1 },
    .{ "sha224", hashlib_mod.genSha224 },
    .{ "sha256", hashlib_mod.genSha256 },
    .{ "sha384", hashlib_mod.genSha384 },
    .{ "sha512", hashlib_mod.genSha512 },
    .{ "new", hashlib_mod.genNew },
});

/// struct module functions
const StructFuncs = FuncMap.initComptime(.{
    .{ "pack", struct_mod.genPack },
    .{ "unpack", struct_mod.genUnpack },
    .{ "calcsize", struct_mod.genCalcsize },
    .{ "pack_into", struct_mod.genPackInto },
    .{ "unpack_from", struct_mod.genUnpackFrom },
    .{ "iter_unpack", struct_mod.genIterUnpack },
});

/// base64 module functions
const Base64Funcs = FuncMap.initComptime(.{
    .{ "b64encode", base64_mod.genB64encode },
    .{ "b64decode", base64_mod.genB64decode },
    .{ "urlsafe_b64encode", base64_mod.genUrlsafeB64encode },
    .{ "urlsafe_b64decode", base64_mod.genUrlsafeB64decode },
    .{ "standard_b64encode", base64_mod.genStandardB64encode },
    .{ "standard_b64decode", base64_mod.genStandardB64decode },
    .{ "encodebytes", base64_mod.genEncodebytes },
    .{ "decodebytes", base64_mod.genDecodebytes },
    .{ "b32encode", base64_mod.genB32encode },
    .{ "b32decode", base64_mod.genB32decode },
    .{ "b16encode", base64_mod.genB16encode },
    .{ "b16decode", base64_mod.genB16decode },
    .{ "a85encode", base64_mod.genA85encode },
    .{ "a85decode", base64_mod.genA85decode },
});

/// random module functions
const RandomFuncs = FuncMap.initComptime(.{
    .{ "random", random_mod.genRandom },
    .{ "randint", random_mod.genRandint },
    .{ "randrange", random_mod.genRandrange },
    .{ "choice", random_mod.genChoice },
    .{ "choices", random_mod.genChoices },
    .{ "shuffle", random_mod.genShuffle },
    .{ "sample", random_mod.genSample },
    .{ "uniform", random_mod.genUniform },
    .{ "gauss", random_mod.genGauss },
    .{ "seed", random_mod.genSeed },
    .{ "getstate", random_mod.genGetstate },
    .{ "setstate", random_mod.genSetstate },
    .{ "getrandbits", random_mod.genGetrandbits },
});

/// string module functions (constants and utilities)
const StringFuncs = FuncMap.initComptime(.{
    .{ "ascii_lowercase", string_mod.genAsciiLowercase },
    .{ "ascii_uppercase", string_mod.genAsciiUppercase },
    .{ "ascii_letters", string_mod.genAsciiLetters },
    .{ "digits", string_mod.genDigits },
    .{ "hexdigits", string_mod.genHexdigits },
    .{ "octdigits", string_mod.genOctdigits },
    .{ "punctuation", string_mod.genPunctuation },
    .{ "whitespace", string_mod.genWhitespace },
    .{ "printable", string_mod.genPrintable },
    .{ "capwords", string_mod.genCapwords },
    .{ "Formatter", string_mod.genFormatter },
    .{ "Template", string_mod.genTemplate },
});

/// time module functions
const TimeFuncs = FuncMap.initComptime(.{
    .{ "time", time_mod.genTime },
    .{ "time_ns", time_mod.genTimeNs },
    .{ "sleep", time_mod.genSleep },
    .{ "perf_counter", time_mod.genPerfCounter },
    .{ "perf_counter_ns", time_mod.genPerfCounterNs },
    .{ "monotonic", time_mod.genMonotonic },
    .{ "monotonic_ns", time_mod.genMonotonicNs },
    .{ "process_time", time_mod.genProcessTime },
    .{ "process_time_ns", time_mod.genProcessTimeNs },
    .{ "ctime", time_mod.genCtime },
    .{ "gmtime", time_mod.genGmtime },
    .{ "localtime", time_mod.genLocaltime },
    .{ "mktime", time_mod.genMktime },
    .{ "strftime", time_mod.genStrftime },
    .{ "strptime", time_mod.genStrptime },
    .{ "get_clock_info", time_mod.genGetClockInfo },
});

/// sys module functions
const SysFuncs = FuncMap.initComptime(.{
    .{ "argv", sys_mod.genArgv },
    .{ "exit", sys_mod.genExit },
    .{ "path", sys_mod.genPath },
    .{ "platform", sys_mod.genPlatform },
    .{ "version", sys_mod.genVersion },
    .{ "version_info", sys_mod.genVersionInfo },
    .{ "executable", sys_mod.genExecutable },
    .{ "stdin", sys_mod.genStdin },
    .{ "stdout", sys_mod.genStdout },
    .{ "stderr", sys_mod.genStderr },
    .{ "maxsize", sys_mod.genMaxsize },
    .{ "byteorder", sys_mod.genByteorder },
    .{ "getsizeof", sys_mod.genGetsizeof },
    .{ "getrecursionlimit", sys_mod.genGetrecursionlimit },
    .{ "setrecursionlimit", sys_mod.genSetrecursionlimit },
    .{ "getdefaultencoding", sys_mod.genGetdefaultencoding },
    .{ "getfilesystemencoding", sys_mod.genGetfilesystemencoding },
    .{ "intern", sys_mod.genIntern },
    .{ "modules", sys_mod.genModules },
});

/// uuid module functions
const UuidFuncs = FuncMap.initComptime(.{
    .{ "uuid4", uuid_mod.genUuid4 },
    .{ "uuid1", uuid_mod.genUuid1 },
    .{ "uuid3", uuid_mod.genUuid3 },
    .{ "uuid5", uuid_mod.genUuid5 },
    .{ "UUID", uuid_mod.genUUID },
    .{ "NAMESPACE_DNS", uuid_mod.genNamespaceDns },
    .{ "NAMESPACE_URL", uuid_mod.genNamespaceUrl },
    .{ "NAMESPACE_OID", uuid_mod.genNamespaceOid },
    .{ "NAMESPACE_X500", uuid_mod.genNamespaceX500 },
    .{ "getnode", uuid_mod.genGetnode },
});

/// subprocess module functions
const SubprocessFuncs = FuncMap.initComptime(.{
    .{ "run", subprocess_mod.genRun },
    .{ "call", subprocess_mod.genCall },
    .{ "check_call", subprocess_mod.genCheckCall },
    .{ "check_output", subprocess_mod.genCheckOutput },
    .{ "Popen", subprocess_mod.genPopen },
    .{ "getoutput", subprocess_mod.genGetoutput },
    .{ "getstatusoutput", subprocess_mod.genGetstatusoutput },
    .{ "PIPE", subprocess_mod.genPIPE },
    .{ "STDOUT", subprocess_mod.genSTDOUT },
    .{ "DEVNULL", subprocess_mod.genDEVNULL },
});

/// tempfile module functions
const TempfileFuncs = FuncMap.initComptime(.{
    .{ "mktemp", tempfile_mod.genMktemp },
    .{ "mkdtemp", tempfile_mod.genMkdtemp },
    .{ "mkstemp", tempfile_mod.genMkstemp },
    .{ "gettempdir", tempfile_mod.genGettempdir },
    .{ "gettempprefix", tempfile_mod.genGettempprefix },
    .{ "NamedTemporaryFile", tempfile_mod.genNamedTemporaryFile },
    .{ "TemporaryFile", tempfile_mod.genTemporaryFile },
    .{ "SpooledTemporaryFile", tempfile_mod.genSpooledTemporaryFile },
    .{ "TemporaryDirectory", tempfile_mod.genTemporaryDirectory },
});

/// textwrap module functions
const TextwrapFuncs = FuncMap.initComptime(.{
    .{ "wrap", textwrap_mod.genWrap },
    .{ "fill", textwrap_mod.genFill },
    .{ "dedent", textwrap_mod.genDedent },
    .{ "indent", textwrap_mod.genIndent },
    .{ "shorten", textwrap_mod.genShorten },
    .{ "TextWrapper", textwrap_mod.genTextWrapper },
});

/// shutil module functions
const ShutilFuncs = FuncMap.initComptime(.{
    .{ "copy", shutil_mod.genCopy },
    .{ "copy2", shutil_mod.genCopy2 },
    .{ "copyfile", shutil_mod.genCopyfile },
    .{ "copystat", shutil_mod.genCopystat },
    .{ "copymode", shutil_mod.genCopymode },
    .{ "move", shutil_mod.genMove },
    .{ "rmtree", shutil_mod.genRmtree },
    .{ "copytree", shutil_mod.genCopytree },
    .{ "disk_usage", shutil_mod.genDiskUsage },
    .{ "which", shutil_mod.genWhich },
    .{ "get_terminal_size", shutil_mod.genGetTerminalSize },
    .{ "make_archive", shutil_mod.genMakeArchive },
    .{ "unpack_archive", shutil_mod.genUnpackArchive },
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
    .{ "copy", CopyFuncs },
    .{ "typing", TypingFuncs },
    .{ "contextlib", ContextlibFuncs },
    .{ "hashlib", HashlibFuncs },
    .{ "struct", StructFuncs },
    .{ "base64", Base64Funcs },
    .{ "random", RandomFuncs },
    .{ "string", StringFuncs },
    .{ "time", TimeFuncs },
    .{ "sys", SysFuncs },
    .{ "uuid", UuidFuncs },
    .{ "subprocess", SubprocessFuncs },
    .{ "tempfile", TempfileFuncs },
    .{ "textwrap", TextwrapFuncs },
    .{ "shutil", ShutilFuncs },
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
