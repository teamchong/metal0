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
const pickle_mod = @import("../pickle_mod.zig");
const hmac_mod = @import("../hmac_mod.zig");
const socket_mod = @import("../socket_mod.zig");
const random_mod = @import("../random_mod.zig");
const string_mod = @import("../string_mod.zig");
const time_mod = @import("../time_mod.zig");
const sys_mod = @import("../sys_mod.zig");
const uuid_mod = @import("../uuid_mod.zig");
const subprocess_mod = @import("../subprocess_mod.zig");
const tempfile_mod = @import("../tempfile_mod.zig");
const textwrap_mod = @import("../textwrap_mod.zig");
const shutil_mod = @import("../shutil_mod.zig");
const glob_mod = @import("../glob_mod.zig");
const fnmatch_mod = @import("../fnmatch_mod.zig");
const secrets_mod = @import("../secrets_mod.zig");
const csv_mod = @import("../csv_mod.zig");
const configparser_mod = @import("../configparser_mod.zig");
const argparse_mod = @import("../argparse_mod.zig");
const zipfile_mod = @import("../zipfile_mod.zig");
const gzip_mod = @import("../gzip_mod.zig");
const logging_mod = @import("../logging_mod.zig");
const threading_mod = @import("../threading_mod.zig");
const queue_mod = @import("../queue_mod.zig");
const html_mod = @import("../html_mod.zig");
const urllib_mod = @import("../urllib_mod.zig");
const xml_mod = @import("../xml_mod.zig");
const decimal_mod = @import("../decimal_mod.zig");
const fractions_mod = @import("../fractions_mod.zig");
const email_mod = @import("../email_mod.zig");
const sqlite3_mod = @import("../sqlite3_mod.zig");
const heapq_mod = @import("../heapq_mod.zig");
const weakref_mod = @import("../weakref_mod.zig");
const types_mod = @import("../types_mod.zig");
const bisect_mod = @import("../bisect_mod.zig");
const statistics_mod = @import("../statistics_mod.zig");
const abc_mod = @import("../abc_mod.zig");
const inspect_mod = @import("../inspect_mod.zig");
const dataclasses_mod = @import("../dataclasses_mod.zig");
const enum_mod = @import("../enum_mod.zig");
const operator_mod = @import("../operator_mod.zig");
const atexit_mod = @import("../atexit_mod.zig");
const warnings_mod = @import("../warnings_mod.zig");
const traceback_mod = @import("../traceback_mod.zig");
const linecache_mod = @import("../linecache_mod.zig");
const pprint_mod = @import("../pprint_mod.zig");
const getpass_mod = @import("../getpass_mod.zig");
const platform_mod = @import("../platform_mod.zig");
const locale_mod = @import("../locale_mod.zig");
const codecs_mod = @import("../codecs_mod.zig");
const shelve_mod = @import("../shelve_mod.zig");
const cmath_mod = @import("../cmath_mod.zig");
const array_mod = @import("../array_mod.zig");
const difflib_mod = @import("../difflib_mod.zig");
const filecmp_mod = @import("../filecmp_mod.zig");
const graphlib_mod = @import("../graphlib_mod.zig");
const numbers_mod = @import("../numbers_mod.zig");
const http_mod = @import("../http_mod.zig");

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

/// pickle module functions (JSON-backed serialization)
const PickleFuncs = FuncMap.initComptime(.{
    .{ "dumps", pickle_mod.genDumps },
    .{ "loads", pickle_mod.genLoads },
    .{ "dump", pickle_mod.genDump },
    .{ "load", pickle_mod.genLoad },
});

/// hmac module functions (HMAC-SHA256)
const HmacFuncs = FuncMap.initComptime(.{
    .{ "new", hmac_mod.genNew },
    .{ "digest", hmac_mod.genDigest },
    .{ "compare_digest", hmac_mod.genCompareDigest },
});

/// socket module functions (TCP/UDP networking)
const SocketFuncs = FuncMap.initComptime(.{
    .{ "socket", socket_mod.genSocket },
    .{ "create_connection", socket_mod.genCreateConnection },
    .{ "gethostname", socket_mod.genGethostname },
    .{ "getfqdn", socket_mod.genGetfqdn },
    .{ "inet_aton", socket_mod.genInetAton },
    .{ "inet_ntoa", socket_mod.genInetNtoa },
    .{ "htons", socket_mod.genHtons },
    .{ "htonl", socket_mod.genHtonl },
    .{ "ntohs", socket_mod.genNtohs },
    .{ "ntohl", socket_mod.genNtohl },
    .{ "setdefaulttimeout", socket_mod.genSetdefaulttimeout },
    .{ "getdefaulttimeout", socket_mod.genGetdefaulttimeout },
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

/// glob module functions
const GlobFuncs = FuncMap.initComptime(.{
    .{ "glob", glob_mod.genGlob },
    .{ "iglob", glob_mod.genIglob },
    .{ "escape", glob_mod.genEscape },
    .{ "has_magic", glob_mod.genHasMagic },
});

/// fnmatch module functions
const FnmatchFuncs = FuncMap.initComptime(.{
    .{ "fnmatch", fnmatch_mod.genFnmatch },
    .{ "fnmatchcase", fnmatch_mod.genFnmatchcase },
    .{ "filter", fnmatch_mod.genFilter },
    .{ "translate", fnmatch_mod.genTranslate },
});

/// secrets module functions (cryptographically secure random)
const SecretsFuncs = FuncMap.initComptime(.{
    .{ "token_bytes", secrets_mod.genTokenBytes },
    .{ "token_hex", secrets_mod.genTokenHex },
    .{ "token_urlsafe", secrets_mod.genTokenUrlsafe },
    .{ "randbelow", secrets_mod.genRandbelow },
    .{ "choice", secrets_mod.genChoice },
    .{ "randbits", secrets_mod.genRandbits },
    .{ "compare_digest", secrets_mod.genCompareDigest },
    .{ "SystemRandom", secrets_mod.genSystemRandom },
});

/// csv module functions
const CsvFuncs = FuncMap.initComptime(.{
    .{ "reader", csv_mod.genReader },
    .{ "writer", csv_mod.genWriter },
    .{ "DictReader", csv_mod.genDictReader },
    .{ "DictWriter", csv_mod.genDictWriter },
    .{ "field_size_limit", csv_mod.genFieldSizeLimit },
    .{ "QUOTE_ALL", csv_mod.genQuoteAll },
    .{ "QUOTE_MINIMAL", csv_mod.genQuoteMinimal },
    .{ "QUOTE_NONNUMERIC", csv_mod.genQuoteNonnumeric },
    .{ "QUOTE_NONE", csv_mod.genQuoteNone },
});

/// configparser module functions
const ConfigparserFuncs = FuncMap.initComptime(.{
    .{ "ConfigParser", configparser_mod.genConfigParser },
    .{ "RawConfigParser", configparser_mod.genRawConfigParser },
    .{ "SafeConfigParser", configparser_mod.genSafeConfigParser },
});

/// argparse module functions
const ArgparseFuncs = FuncMap.initComptime(.{
    .{ "ArgumentParser", argparse_mod.genArgumentParser },
    .{ "Namespace", argparse_mod.genNamespace },
    .{ "FileType", argparse_mod.genFileType },
    .{ "REMAINDER", argparse_mod.genREMAINDER },
    .{ "SUPPRESS", argparse_mod.genSUPPRESS },
    .{ "OPTIONAL", argparse_mod.genOPTIONAL },
    .{ "ZERO_OR_MORE", argparse_mod.genZERO_OR_MORE },
    .{ "ONE_OR_MORE", argparse_mod.genONE_OR_MORE },
});

/// zipfile module functions
const ZipfileFuncs = FuncMap.initComptime(.{
    .{ "ZipFile", zipfile_mod.genZipFile },
    .{ "is_zipfile", zipfile_mod.genIsZipfile },
    .{ "ZipInfo", zipfile_mod.genZipInfo },
    .{ "ZIP_STORED", zipfile_mod.genZIP_STORED },
    .{ "ZIP_DEFLATED", zipfile_mod.genZIP_DEFLATED },
    .{ "ZIP_BZIP2", zipfile_mod.genZIP_BZIP2 },
    .{ "ZIP_LZMA", zipfile_mod.genZIP_LZMA },
    .{ "BadZipFile", zipfile_mod.genBadZipFile },
    .{ "LargeZipFile", zipfile_mod.genLargeZipFile },
});

/// gzip module functions
const GzipFuncs = FuncMap.initComptime(.{
    .{ "compress", gzip_mod.genCompress },
    .{ "decompress", gzip_mod.genDecompress },
    .{ "open", gzip_mod.genOpen },
    .{ "GzipFile", gzip_mod.genGzipFile },
    .{ "BadGzipFile", gzip_mod.genBadGzipFile },
});

/// logging module functions
const LoggingFuncs = FuncMap.initComptime(.{
    .{ "debug", logging_mod.genDebug },
    .{ "info", logging_mod.genInfo },
    .{ "warning", logging_mod.genWarning },
    .{ "error", logging_mod.genError },
    .{ "critical", logging_mod.genCritical },
    .{ "exception", logging_mod.genException },
    .{ "log", logging_mod.genLog },
    .{ "basicConfig", logging_mod.genBasicConfig },
    .{ "getLogger", logging_mod.genGetLogger },
    .{ "Logger", logging_mod.genLogger },
    .{ "Handler", logging_mod.genHandler },
    .{ "StreamHandler", logging_mod.genStreamHandler },
    .{ "FileHandler", logging_mod.genFileHandler },
    .{ "Formatter", logging_mod.genFormatter },
    .{ "DEBUG", logging_mod.genDEBUG },
    .{ "INFO", logging_mod.genINFO },
    .{ "WARNING", logging_mod.genWARNING },
    .{ "ERROR", logging_mod.genERROR },
    .{ "CRITICAL", logging_mod.genCRITICAL },
    .{ "NOTSET", logging_mod.genNOTSET },
});

/// threading module functions
const ThreadingFuncs = FuncMap.initComptime(.{
    .{ "Thread", threading_mod.genThread },
    .{ "Lock", threading_mod.genLock },
    .{ "RLock", threading_mod.genRLock },
    .{ "Condition", threading_mod.genCondition },
    .{ "Semaphore", threading_mod.genSemaphore },
    .{ "BoundedSemaphore", threading_mod.genBoundedSemaphore },
    .{ "Event", threading_mod.genEvent },
    .{ "Barrier", threading_mod.genBarrier },
    .{ "Timer", threading_mod.genTimer },
    .{ "current_thread", threading_mod.genCurrentThread },
    .{ "main_thread", threading_mod.genMainThread },
    .{ "active_count", threading_mod.genActiveCount },
    .{ "enumerate", threading_mod.genEnumerate },
    .{ "local", threading_mod.genLocal },
});

/// queue module functions
const QueueFuncs = FuncMap.initComptime(.{
    .{ "Queue", queue_mod.genQueue },
    .{ "LifoQueue", queue_mod.genLifoQueue },
    .{ "PriorityQueue", queue_mod.genPriorityQueue },
    .{ "SimpleQueue", queue_mod.genSimpleQueue },
    .{ "Empty", queue_mod.genEmpty },
    .{ "Full", queue_mod.genFull },
});

/// html module functions
const HtmlFuncs = FuncMap.initComptime(.{
    .{ "escape", html_mod.genEscape },
    .{ "unescape", html_mod.genUnescape },
});

/// urllib.parse module functions
const UrllibParseFuncs = FuncMap.initComptime(.{
    .{ "urlparse", urllib_mod.genUrlparse },
    .{ "urlunparse", urllib_mod.genUrlunparse },
    .{ "urlencode", urllib_mod.genUrlencode },
    .{ "quote", urllib_mod.genQuote },
    .{ "quote_plus", urllib_mod.genQuotePlus },
    .{ "unquote", urllib_mod.genUnquote },
    .{ "unquote_plus", urllib_mod.genUnquotePlus },
    .{ "urljoin", urllib_mod.genUrljoin },
    .{ "parse_qs", urllib_mod.genParseQs },
    .{ "parse_qsl", urllib_mod.genParseQsl },
});

/// xml.etree.ElementTree module functions
const XmlEtreeFuncs = FuncMap.initComptime(.{
    .{ "parse", xml_mod.genParse },
    .{ "fromstring", xml_mod.genFromstring },
    .{ "tostring", xml_mod.genTostring },
    .{ "Element", xml_mod.genElement },
    .{ "SubElement", xml_mod.genSubElement },
    .{ "ElementTree", xml_mod.genElementTree },
    .{ "Comment", xml_mod.genComment },
    .{ "ProcessingInstruction", xml_mod.genProcessingInstruction },
    .{ "QName", xml_mod.genQName },
    .{ "indent", xml_mod.genIndent },
    .{ "dump", xml_mod.genDump },
    .{ "iselement", xml_mod.genIselement },
});

/// decimal module functions
const DecimalFuncs = FuncMap.initComptime(.{
    .{ "Decimal", decimal_mod.genDecimal },
    .{ "getcontext", decimal_mod.genGetcontext },
    .{ "setcontext", decimal_mod.genSetcontext },
    .{ "localcontext", decimal_mod.genLocalcontext },
    .{ "BasicContext", decimal_mod.genBasicContext },
    .{ "ExtendedContext", decimal_mod.genExtendedContext },
    .{ "DefaultContext", decimal_mod.genDefaultContext },
    .{ "ROUND_CEILING", decimal_mod.genROUND_CEILING },
    .{ "ROUND_DOWN", decimal_mod.genROUND_DOWN },
    .{ "ROUND_FLOOR", decimal_mod.genROUND_FLOOR },
    .{ "ROUND_HALF_DOWN", decimal_mod.genROUND_HALF_DOWN },
    .{ "ROUND_HALF_EVEN", decimal_mod.genROUND_HALF_EVEN },
    .{ "ROUND_HALF_UP", decimal_mod.genROUND_HALF_UP },
    .{ "ROUND_UP", decimal_mod.genROUND_UP },
    .{ "ROUND_05UP", decimal_mod.genROUND_05UP },
    .{ "DecimalException", decimal_mod.genDecimalException },
    .{ "InvalidOperation", decimal_mod.genInvalidOperation },
    .{ "DivisionByZero", decimal_mod.genDivisionByZero },
    .{ "Overflow", decimal_mod.genOverflow },
    .{ "Underflow", decimal_mod.genUnderflow },
    .{ "Inexact", decimal_mod.genInexact },
    .{ "Rounded", decimal_mod.genRounded },
    .{ "Subnormal", decimal_mod.genSubnormal },
    .{ "FloatOperation", decimal_mod.genFloatOperation },
    .{ "Clamped", decimal_mod.genClamped },
});

/// fractions module functions
const FractionsFuncs = FuncMap.initComptime(.{
    .{ "Fraction", fractions_mod.genFraction },
    .{ "gcd", fractions_mod.genGcd },
});

/// email module functions
const EmailMessageFuncs = FuncMap.initComptime(.{
    .{ "EmailMessage", email_mod.genEmailMessage },
    .{ "Message", email_mod.genMessage },
});

/// email.mime.text module functions
const EmailMimeTextFuncs = FuncMap.initComptime(.{
    .{ "MIMEText", email_mod.genMIMEText },
});

/// email.mime.multipart module functions
const EmailMimeMultipartFuncs = FuncMap.initComptime(.{
    .{ "MIMEMultipart", email_mod.genMIMEMultipart },
});

/// email.mime.base module functions
const EmailMimeBaseFuncs = FuncMap.initComptime(.{
    .{ "MIMEBase", email_mod.genMIMEBase },
    .{ "MIMEApplication", email_mod.genMIMEApplication },
    .{ "MIMEImage", email_mod.genMIMEImage },
    .{ "MIMEAudio", email_mod.genMIMEAudio },
});

/// email.utils module functions
const EmailUtilsFuncs = FuncMap.initComptime(.{
    .{ "formataddr", email_mod.genFormataddr },
    .{ "parseaddr", email_mod.genParseaddr },
    .{ "formatdate", email_mod.genFormatdate },
    .{ "make_msgid", email_mod.genMakeMsgid },
});

/// sqlite3 module functions
const Sqlite3Funcs = FuncMap.initComptime(.{
    .{ "connect", sqlite3_mod.genConnect },
    .{ "Connection", sqlite3_mod.genConnection },
    .{ "Cursor", sqlite3_mod.genCursor },
    .{ "Row", sqlite3_mod.genRow },
    .{ "Error", sqlite3_mod.genError },
    .{ "DatabaseError", sqlite3_mod.genDatabaseError },
    .{ "IntegrityError", sqlite3_mod.genIntegrityError },
    .{ "OperationalError", sqlite3_mod.genOperationalError },
    .{ "ProgrammingError", sqlite3_mod.genProgrammingError },
    .{ "PARSE_DECLTYPES", sqlite3_mod.genPARSE_DECLTYPES },
    .{ "PARSE_COLNAMES", sqlite3_mod.genPARSE_COLNAMES },
    .{ "SQLITE_OK", sqlite3_mod.genSQLITE_OK },
    .{ "SQLITE_DENY", sqlite3_mod.genSQLITE_DENY },
    .{ "SQLITE_IGNORE", sqlite3_mod.genSQLITE_IGNORE },
    .{ "version", sqlite3_mod.genVersion },
    .{ "sqlite_version", sqlite3_mod.genSqliteVersion },
    .{ "register_adapter", sqlite3_mod.genRegisterAdapter },
    .{ "register_converter", sqlite3_mod.genRegisterConverter },
});

/// heapq module functions
const HeapqFuncs = FuncMap.initComptime(.{
    .{ "heappush", heapq_mod.genHeappush },
    .{ "heappop", heapq_mod.genHeappop },
    .{ "heapify", heapq_mod.genHeapify },
    .{ "heapreplace", heapq_mod.genHeapreplace },
    .{ "heappushpop", heapq_mod.genHeappushpop },
    .{ "nlargest", heapq_mod.genNlargest },
    .{ "nsmallest", heapq_mod.genNsmallest },
    .{ "merge", heapq_mod.genMerge },
});

/// weakref module functions
const WeakrefFuncs = FuncMap.initComptime(.{
    .{ "ref", weakref_mod.genRef },
    .{ "proxy", weakref_mod.genProxy },
    .{ "getweakrefcount", weakref_mod.genGetweakrefcount },
    .{ "getweakrefs", weakref_mod.genGetweakrefs },
    .{ "WeakSet", weakref_mod.genWeakSet },
    .{ "WeakKeyDictionary", weakref_mod.genWeakKeyDictionary },
    .{ "WeakValueDictionary", weakref_mod.genWeakValueDictionary },
    .{ "WeakMethod", weakref_mod.genWeakMethod },
    .{ "finalize", weakref_mod.genFinalize },
    .{ "ReferenceType", weakref_mod.genReferenceType },
    .{ "ProxyType", weakref_mod.genProxyType },
    .{ "CallableProxyType", weakref_mod.genCallableProxyType },
});

/// types module functions
const TypesFuncs = FuncMap.initComptime(.{
    .{ "FunctionType", types_mod.genFunctionType },
    .{ "LambdaType", types_mod.genLambdaType },
    .{ "GeneratorType", types_mod.genGeneratorType },
    .{ "CoroutineType", types_mod.genCoroutineType },
    .{ "AsyncGeneratorType", types_mod.genAsyncGeneratorType },
    .{ "CodeType", types_mod.genCodeType },
    .{ "CellType", types_mod.genCellType },
    .{ "MethodType", types_mod.genMethodType },
    .{ "BuiltinFunctionType", types_mod.genBuiltinFunctionType },
    .{ "BuiltinMethodType", types_mod.genBuiltinMethodType },
    .{ "ModuleType", types_mod.genModuleType },
    .{ "TracebackType", types_mod.genTracebackType },
    .{ "FrameType", types_mod.genFrameType },
    .{ "GetSetDescriptorType", types_mod.genGetSetDescriptorType },
    .{ "MemberDescriptorType", types_mod.genMemberDescriptorType },
    .{ "MappingProxyType", types_mod.genMappingProxyType },
    .{ "SimpleNamespace", types_mod.genSimpleNamespace },
    .{ "DynamicClassAttribute", types_mod.genDynamicClassAttribute },
    .{ "NoneType", types_mod.genNoneType },
    .{ "NotImplementedType", types_mod.genNotImplementedType },
    .{ "EllipsisType", types_mod.genEllipsisType },
    .{ "UnionType", types_mod.genUnionType },
    .{ "GenericAlias", types_mod.genGenericAlias },
    .{ "new_class", types_mod.genNewClass },
    .{ "resolve_bases", types_mod.genResolveBases },
    .{ "prepare_class", types_mod.genPrepareClass },
    .{ "get_original_bases", types_mod.genGetOriginalBases },
    .{ "coroutine", types_mod.genCoroutine },
});

/// bisect module functions
const BisectFuncs = FuncMap.initComptime(.{
    .{ "bisect_left", bisect_mod.genBisectLeft },
    .{ "bisect_right", bisect_mod.genBisectRight },
    .{ "bisect", bisect_mod.genBisect },
    .{ "insort_left", bisect_mod.genInsortLeft },
    .{ "insort_right", bisect_mod.genInsortRight },
    .{ "insort", bisect_mod.genInsort },
});

/// statistics module functions
const StatisticsFuncs = FuncMap.initComptime(.{
    .{ "mean", statistics_mod.genMean },
    .{ "fmean", statistics_mod.genFmean },
    .{ "geometric_mean", statistics_mod.genGeometricMean },
    .{ "harmonic_mean", statistics_mod.genHarmonicMean },
    .{ "median", statistics_mod.genMedian },
    .{ "median_low", statistics_mod.genMedianLow },
    .{ "median_high", statistics_mod.genMedianHigh },
    .{ "median_grouped", statistics_mod.genMedianGrouped },
    .{ "mode", statistics_mod.genMode },
    .{ "multimode", statistics_mod.genMultimode },
    .{ "pstdev", statistics_mod.genPstdev },
    .{ "pvariance", statistics_mod.genPvariance },
    .{ "stdev", statistics_mod.genStdev },
    .{ "variance", statistics_mod.genVariance },
    .{ "quantiles", statistics_mod.genQuantiles },
    .{ "covariance", statistics_mod.genCovariance },
    .{ "correlation", statistics_mod.genCorrelation },
    .{ "linear_regression", statistics_mod.genLinearRegression },
    .{ "NormalDist", statistics_mod.genNormalDist },
    .{ "StatisticsError", statistics_mod.genStatisticsError },
});

/// abc module functions
const AbcFuncs = FuncMap.initComptime(.{
    .{ "ABC", abc_mod.genABC },
    .{ "ABCMeta", abc_mod.genABCMeta },
    .{ "abstractmethod", abc_mod.genAbstractmethod },
    .{ "abstractclassmethod", abc_mod.genAbstractclassmethod },
    .{ "abstractstaticmethod", abc_mod.genAbstractstaticmethod },
    .{ "abstractproperty", abc_mod.genAbstractproperty },
    .{ "get_cache_token", abc_mod.genGetCacheToken },
    .{ "update_abstractmethods", abc_mod.genUpdateAbstractmethods },
});

/// inspect module functions
const InspectFuncs = FuncMap.initComptime(.{
    .{ "isclass", inspect_mod.genIsclass },
    .{ "isfunction", inspect_mod.genIsfunction },
    .{ "ismethod", inspect_mod.genIsmethod },
    .{ "ismodule", inspect_mod.genIsmodule },
    .{ "isbuiltin", inspect_mod.genIsbuiltin },
    .{ "isroutine", inspect_mod.genIsroutine },
    .{ "isabstract", inspect_mod.genIsabstract },
    .{ "isgenerator", inspect_mod.genIsgenerator },
    .{ "iscoroutine", inspect_mod.genIscoroutine },
    .{ "isasyncgen", inspect_mod.genIsasyncgen },
    .{ "isdatadescriptor", inspect_mod.genIsdatadescriptor },
    .{ "getmembers", inspect_mod.genGetmembers },
    .{ "getmodule", inspect_mod.genGetmodule },
    .{ "getfile", inspect_mod.genGetfile },
    .{ "getsourcefile", inspect_mod.genGetsourcefile },
    .{ "getsourcelines", inspect_mod.genGetsourcelines },
    .{ "getsource", inspect_mod.genGetsource },
    .{ "getdoc", inspect_mod.genGetdoc },
    .{ "getcomments", inspect_mod.genGetcomments },
    .{ "signature", inspect_mod.genSignature },
    .{ "Parameter", inspect_mod.genParameter },
    .{ "currentframe", inspect_mod.genCurrentframe },
    .{ "stack", inspect_mod.genStack },
    .{ "getargspec", inspect_mod.genGetargspec },
    .{ "getfullargspec", inspect_mod.genGetfullargspec },
    .{ "iscoroutinefunction", inspect_mod.genIscoroutinefunction },
    .{ "isgeneratorfunction", inspect_mod.genIsgeneratorfunction },
    .{ "isasyncgenfunction", inspect_mod.genIsasyncgenfunction },
    .{ "getattr_static", inspect_mod.genGetattrStatic },
    .{ "unwrap", inspect_mod.genUnwrap },
});

/// dataclasses module functions
const DataclassesFuncs = FuncMap.initComptime(.{
    .{ "dataclass", dataclasses_mod.genDataclass },
    .{ "field", dataclasses_mod.genField },
    .{ "Field", dataclasses_mod.genFieldClass },
    .{ "fields", dataclasses_mod.genFields },
    .{ "asdict", dataclasses_mod.genAsdict },
    .{ "astuple", dataclasses_mod.genAstuple },
    .{ "make_dataclass", dataclasses_mod.genMakeDataclass },
    .{ "replace", dataclasses_mod.genReplace },
    .{ "is_dataclass", dataclasses_mod.genIsDataclass },
    .{ "MISSING", dataclasses_mod.genMISSING },
    .{ "KW_ONLY", dataclasses_mod.genKW_ONLY },
    .{ "FrozenInstanceError", dataclasses_mod.genFrozenInstanceError },
});

/// enum module functions
const EnumFuncs = FuncMap.initComptime(.{
    .{ "Enum", enum_mod.genEnum },
    .{ "IntEnum", enum_mod.genIntEnum },
    .{ "StrEnum", enum_mod.genStrEnum },
    .{ "Flag", enum_mod.genFlag },
    .{ "IntFlag", enum_mod.genIntFlag },
    .{ "auto", enum_mod.genAuto },
    .{ "unique", enum_mod.genUnique },
    .{ "verify", enum_mod.genVerify },
    .{ "member", enum_mod.genMember },
    .{ "nonmember", enum_mod.genNonmember },
    .{ "global_enum", enum_mod.genGlobalEnum },
    .{ "EJECT", enum_mod.genEJECT },
    .{ "KEEP", enum_mod.genKEEP },
    .{ "STRICT", enum_mod.genSTRICT },
    .{ "CONFORM", enum_mod.genCONFORM },
    .{ "CONTINUOUS", enum_mod.genCONTINUOUS },
    .{ "NAMED_FLAGS", enum_mod.genNAMED_FLAGS },
    .{ "EnumType", enum_mod.genEnumType },
    .{ "EnumCheck", enum_mod.genEnumCheck },
    .{ "FlagBoundary", enum_mod.genFlagBoundary },
    .{ "property", enum_mod.genProperty },
});

/// operator module functions
const OperatorFuncs = FuncMap.initComptime(.{
    .{ "add", operator_mod.genAdd },
    .{ "sub", operator_mod.genSub },
    .{ "mul", operator_mod.genMul },
    .{ "truediv", operator_mod.genTruediv },
    .{ "floordiv", operator_mod.genFloordiv },
    .{ "mod", operator_mod.genMod },
    .{ "pow", operator_mod.genPow },
    .{ "neg", operator_mod.genNeg },
    .{ "pos", operator_mod.genPos },
    .{ "abs", operator_mod.genAbs },
    .{ "invert", operator_mod.genInvert },
    .{ "lshift", operator_mod.genLshift },
    .{ "rshift", operator_mod.genRshift },
    .{ "and_", operator_mod.genAnd },
    .{ "or_", operator_mod.genOr },
    .{ "xor", operator_mod.genXor },
    .{ "not_", operator_mod.genNot },
    .{ "truth", operator_mod.genTruth },
    .{ "eq", operator_mod.genEq },
    .{ "ne", operator_mod.genNe },
    .{ "lt", operator_mod.genLt },
    .{ "le", operator_mod.genLe },
    .{ "gt", operator_mod.genGt },
    .{ "ge", operator_mod.genGe },
    .{ "is_", operator_mod.genIs },
    .{ "is_not", operator_mod.genIsNot },
    .{ "concat", operator_mod.genConcat },
    .{ "contains", operator_mod.genContains },
    .{ "countOf", operator_mod.genCountOf },
    .{ "indexOf", operator_mod.genIndexOf },
    .{ "getitem", operator_mod.genGetitem },
    .{ "setitem", operator_mod.genSetitem },
    .{ "delitem", operator_mod.genDelitem },
    .{ "length_hint", operator_mod.genLengthHint },
    .{ "attrgetter", operator_mod.genAttrgetter },
    .{ "itemgetter", operator_mod.genItemgetter },
    .{ "methodcaller", operator_mod.genMethodcaller },
    .{ "matmul", operator_mod.genMatmul },
    .{ "index", operator_mod.genIndex },
    .{ "iadd", operator_mod.genIadd },
    .{ "isub", operator_mod.genIsub },
    .{ "imul", operator_mod.genImul },
    .{ "itruediv", operator_mod.genItruediv },
    .{ "ifloordiv", operator_mod.genIfloordiv },
    .{ "imod", operator_mod.genImod },
    .{ "ipow", operator_mod.genIpow },
    .{ "ilshift", operator_mod.genIlshift },
    .{ "irshift", operator_mod.genIrshift },
    .{ "iand", operator_mod.genIand },
    .{ "ior", operator_mod.genIor },
    .{ "ixor", operator_mod.genIxor },
    .{ "iconcat", operator_mod.genIconcat },
    .{ "imatmul", operator_mod.genImatmul },
    .{ "__call__", operator_mod.genCall },
});

/// atexit module functions
const AtexitFuncs = FuncMap.initComptime(.{
    .{ "register", atexit_mod.genRegister },
    .{ "unregister", atexit_mod.genUnregister },
    .{ "_run_exitfuncs", atexit_mod.genRunExitfuncs },
    .{ "_clear", atexit_mod.genClear },
    .{ "_ncallbacks", atexit_mod.genNcallbacks },
});

/// warnings module functions
const WarningsFuncs = FuncMap.initComptime(.{
    .{ "warn", warnings_mod.genWarn },
    .{ "warn_explicit", warnings_mod.genWarnExplicit },
    .{ "showwarning", warnings_mod.genShowwarning },
    .{ "formatwarning", warnings_mod.genFormatwarning },
    .{ "filterwarnings", warnings_mod.genFilterwarnings },
    .{ "simplefilter", warnings_mod.genSimplefilter },
    .{ "resetwarnings", warnings_mod.genResetwarnings },
    .{ "catch_warnings", warnings_mod.genCatchWarnings },
    .{ "Warning", warnings_mod.genWarning },
    .{ "UserWarning", warnings_mod.genUserWarning },
    .{ "DeprecationWarning", warnings_mod.genDeprecationWarning },
    .{ "PendingDeprecationWarning", warnings_mod.genPendingDeprecationWarning },
    .{ "SyntaxWarning", warnings_mod.genSyntaxWarning },
    .{ "RuntimeWarning", warnings_mod.genRuntimeWarning },
    .{ "FutureWarning", warnings_mod.genFutureWarning },
    .{ "ImportWarning", warnings_mod.genImportWarning },
    .{ "UnicodeWarning", warnings_mod.genUnicodeWarning },
    .{ "BytesWarning", warnings_mod.genBytesWarning },
    .{ "ResourceWarning", warnings_mod.genResourceWarning },
    .{ "filters", warnings_mod.genFilters },
});

/// traceback module functions
const TracebackFuncs = FuncMap.initComptime(.{
    .{ "print_tb", traceback_mod.genPrintTb },
    .{ "print_exception", traceback_mod.genPrintException },
    .{ "print_exc", traceback_mod.genPrintExc },
    .{ "print_last", traceback_mod.genPrintLast },
    .{ "print_stack", traceback_mod.genPrintStack },
    .{ "extract_tb", traceback_mod.genExtractTb },
    .{ "extract_stack", traceback_mod.genExtractStack },
    .{ "format_list", traceback_mod.genFormatList },
    .{ "format_exception_only", traceback_mod.genFormatExceptionOnly },
    .{ "format_exception", traceback_mod.genFormatException },
    .{ "format_exc", traceback_mod.genFormatExc },
    .{ "format_tb", traceback_mod.genFormatTb },
    .{ "format_stack", traceback_mod.genFormatStack },
    .{ "clear_frames", traceback_mod.genClearFrames },
    .{ "walk_tb", traceback_mod.genWalkTb },
    .{ "walk_stack", traceback_mod.genWalkStack },
    .{ "TracebackException", traceback_mod.genTracebackException },
    .{ "StackSummary", traceback_mod.genStackSummary },
    .{ "FrameSummary", traceback_mod.genFrameSummary },
});

/// linecache module functions
const LinecacheFuncs = FuncMap.initComptime(.{
    .{ "getline", linecache_mod.genGetline },
    .{ "getlines", linecache_mod.genGetlines },
    .{ "clearcache", linecache_mod.genClearcache },
    .{ "checkcache", linecache_mod.genCheckcache },
    .{ "updatecache", linecache_mod.genUpdatecache },
    .{ "lazycache", linecache_mod.genLazycache },
    .{ "cache", linecache_mod.genCache },
});

/// pprint module functions
const PprintFuncs = FuncMap.initComptime(.{
    .{ "pprint", pprint_mod.genPprint },
    .{ "pformat", pprint_mod.genPformat },
    .{ "pp", pprint_mod.genPp },
    .{ "isreadable", pprint_mod.genIsreadable },
    .{ "isrecursive", pprint_mod.genIsrecursive },
    .{ "saferepr", pprint_mod.genSaferepr },
    .{ "PrettyPrinter", pprint_mod.genPrettyPrinter },
});

/// getpass module functions
const GetpassFuncs = FuncMap.initComptime(.{
    .{ "getpass", getpass_mod.genGetpass },
    .{ "getuser", getpass_mod.genGetuser },
    .{ "GetPassWarning", getpass_mod.genGetPassWarning },
});

/// platform module functions
const PlatformFuncs = FuncMap.initComptime(.{
    .{ "system", platform_mod.genSystem },
    .{ "machine", platform_mod.genMachine },
    .{ "node", platform_mod.genNode },
    .{ "release", platform_mod.genRelease },
    .{ "version", platform_mod.genVersion },
    .{ "platform", platform_mod.genPlatform },
    .{ "processor", platform_mod.genProcessor },
    .{ "python_implementation", platform_mod.genPythonImplementation },
    .{ "python_version", platform_mod.genPythonVersion },
    .{ "python_version_tuple", platform_mod.genPythonVersionTuple },
    .{ "python_branch", platform_mod.genPythonBranch },
    .{ "python_revision", platform_mod.genPythonRevision },
    .{ "python_build", platform_mod.genPythonBuild },
    .{ "python_compiler", platform_mod.genPythonCompiler },
    .{ "uname", platform_mod.genUname },
    .{ "architecture", platform_mod.genArchitecture },
    .{ "mac_ver", platform_mod.genMacVer },
    .{ "win32_ver", platform_mod.genWin32Ver },
    .{ "win32_edition", platform_mod.genWin32Edition },
    .{ "win32_is_iot", platform_mod.genWin32IsIot },
    .{ "libc_ver", platform_mod.genLibcVer },
    .{ "freedesktop_os_release", platform_mod.genFreedesktopOsRelease },
});

/// locale module functions
const LocaleFuncs = FuncMap.initComptime(.{
    .{ "setlocale", locale_mod.genSetlocale },
    .{ "getlocale", locale_mod.genGetlocale },
    .{ "getdefaultlocale", locale_mod.genGetdefaultlocale },
    .{ "getpreferredencoding", locale_mod.genGetpreferredencoding },
    .{ "getencoding", locale_mod.genGetencoding },
    .{ "normalize", locale_mod.genNormalize },
    .{ "resetlocale", locale_mod.genResetlocale },
    .{ "localeconv", locale_mod.genLocaleconv },
    .{ "strcoll", locale_mod.genStrcoll },
    .{ "strxfrm", locale_mod.genStrxfrm },
    .{ "format_string", locale_mod.genFormatString },
    .{ "currency", locale_mod.genCurrency },
    .{ "str", locale_mod.genStr },
    .{ "atof", locale_mod.genAtof },
    .{ "atoi", locale_mod.genAtoi },
    .{ "delocalize", locale_mod.genDelocalize },
    .{ "localize", locale_mod.genLocalize },
    .{ "nl_langinfo", locale_mod.genNlLanginfo },
    .{ "gettext", locale_mod.genGettext },
    .{ "LC_CTYPE", locale_mod.genLC_CTYPE },
    .{ "LC_COLLATE", locale_mod.genLC_COLLATE },
    .{ "LC_TIME", locale_mod.genLC_TIME },
    .{ "LC_MONETARY", locale_mod.genLC_MONETARY },
    .{ "LC_MESSAGES", locale_mod.genLC_MESSAGES },
    .{ "LC_NUMERIC", locale_mod.genLC_NUMERIC },
    .{ "LC_ALL", locale_mod.genLC_ALL },
    .{ "Error", locale_mod.genError },
});

/// codecs module functions
const CodecsFuncs = FuncMap.initComptime(.{
    .{ "encode", codecs_mod.genEncode },
    .{ "decode", codecs_mod.genDecode },
    .{ "lookup", codecs_mod.genLookup },
    .{ "getencoder", codecs_mod.genGetencoder },
    .{ "getdecoder", codecs_mod.genGetdecoder },
    .{ "getincrementalencoder", codecs_mod.genGetincrementalencoder },
    .{ "getincrementaldecoder", codecs_mod.genGetincrementaldecoder },
    .{ "getreader", codecs_mod.genGetreader },
    .{ "getwriter", codecs_mod.genGetwriter },
    .{ "register", codecs_mod.genRegister },
    .{ "unregister", codecs_mod.genUnregister },
    .{ "register_error", codecs_mod.genRegisterError },
    .{ "lookup_error", codecs_mod.genLookupError },
    .{ "strict_errors", codecs_mod.genStrictErrors },
    .{ "ignore_errors", codecs_mod.genIgnoreErrors },
    .{ "replace_errors", codecs_mod.genReplaceErrors },
    .{ "xmlcharrefreplace_errors", codecs_mod.genXmlcharrefreplaceErrors },
    .{ "backslashreplace_errors", codecs_mod.genBackslashreplaceErrors },
    .{ "namereplace_errors", codecs_mod.genNamereplaceErrors },
    .{ "open", codecs_mod.genOpen },
    .{ "EncodedFile", codecs_mod.genEncodedFile },
    .{ "iterencode", codecs_mod.genIterencode },
    .{ "iterdecode", codecs_mod.genIterdecode },
    .{ "BOM", codecs_mod.genBOM },
    .{ "BOM_UTF8", codecs_mod.genBOM_UTF8 },
    .{ "BOM_UTF16", codecs_mod.genBOM_UTF16 },
    .{ "BOM_UTF16_LE", codecs_mod.genBOM_UTF16_LE },
    .{ "BOM_UTF16_BE", codecs_mod.genBOM_UTF16_BE },
    .{ "BOM_UTF32", codecs_mod.genBOM_UTF32 },
    .{ "BOM_UTF32_LE", codecs_mod.genBOM_UTF32_LE },
    .{ "BOM_UTF32_BE", codecs_mod.genBOM_UTF32_BE },
    .{ "Codec", codecs_mod.genCodec },
    .{ "IncrementalEncoder", codecs_mod.genIncrementalEncoder },
    .{ "IncrementalDecoder", codecs_mod.genIncrementalDecoder },
    .{ "StreamWriter", codecs_mod.genStreamWriter },
    .{ "StreamReader", codecs_mod.genStreamReader },
    .{ "StreamReaderWriter", codecs_mod.genStreamReaderWriter },
});

/// shelve module functions
const ShelveFuncs = FuncMap.initComptime(.{
    .{ "open", shelve_mod.genOpen },
    .{ "Shelf", shelve_mod.genShelf },
    .{ "BsdDbShelf", shelve_mod.genBsdDbShelf },
    .{ "DbfilenameShelf", shelve_mod.genDbfilenameShelf },
});

/// cmath module functions (complex math)
const CmathFuncs = FuncMap.initComptime(.{
    .{ "sqrt", cmath_mod.genSqrt },
    .{ "exp", cmath_mod.genExp },
    .{ "log", cmath_mod.genLog },
    .{ "log10", cmath_mod.genLog10 },
    .{ "sin", cmath_mod.genSin },
    .{ "cos", cmath_mod.genCos },
    .{ "tan", cmath_mod.genTan },
    .{ "asin", cmath_mod.genAsin },
    .{ "acos", cmath_mod.genAcos },
    .{ "atan", cmath_mod.genAtan },
    .{ "sinh", cmath_mod.genSinh },
    .{ "cosh", cmath_mod.genCosh },
    .{ "tanh", cmath_mod.genTanh },
    .{ "asinh", cmath_mod.genAsinh },
    .{ "acosh", cmath_mod.genAcosh },
    .{ "atanh", cmath_mod.genAtanh },
    .{ "phase", cmath_mod.genPhase },
    .{ "polar", cmath_mod.genPolar },
    .{ "rect", cmath_mod.genRect },
    .{ "isfinite", cmath_mod.genIsfinite },
    .{ "isinf", cmath_mod.genIsinf },
    .{ "isnan", cmath_mod.genIsnan },
    .{ "isclose", cmath_mod.genIsclose },
    .{ "pi", cmath_mod.genPi },
    .{ "e", cmath_mod.genE },
    .{ "tau", cmath_mod.genTau },
    .{ "inf", cmath_mod.genInf },
    .{ "infj", cmath_mod.genInfj },
    .{ "nan", cmath_mod.genNan },
    .{ "nanj", cmath_mod.genNanj },
});

/// array module functions
const ArrayFuncs = FuncMap.initComptime(.{
    .{ "array", array_mod.genArray },
    .{ "typecodes", array_mod.genTypecodes },
    .{ "ArrayType", array_mod.genArrayType },
});

/// difflib module functions
const DifflibFuncs = FuncMap.initComptime(.{
    .{ "SequenceMatcher", difflib_mod.genSequenceMatcher },
    .{ "Differ", difflib_mod.genDiffer },
    .{ "HtmlDiff", difflib_mod.genHtmlDiff },
    .{ "get_close_matches", difflib_mod.genGetCloseMatches },
    .{ "unified_diff", difflib_mod.genUnifiedDiff },
    .{ "context_diff", difflib_mod.genContextDiff },
    .{ "ndiff", difflib_mod.genNdiff },
    .{ "restore", difflib_mod.genRestore },
    .{ "IS_LINE_JUNK", difflib_mod.genIsLineJunk },
    .{ "IS_CHARACTER_JUNK", difflib_mod.genIsCharacterJunk },
    .{ "diff_bytes", difflib_mod.genDiffBytes },
});

/// filecmp module functions
const FilecmpFuncs = FuncMap.initComptime(.{
    .{ "cmp", filecmp_mod.genCmp },
    .{ "cmpfiles", filecmp_mod.genCmpfiles },
    .{ "dircmp", filecmp_mod.genDircmp },
    .{ "clear_cache", filecmp_mod.genClearCache },
    .{ "DEFAULT_IGNORES", filecmp_mod.genDEFAULT_IGNORES },
});

/// graphlib module functions
const GraphlibFuncs = FuncMap.initComptime(.{
    .{ "TopologicalSorter", graphlib_mod.genTopologicalSorter },
    .{ "CycleError", graphlib_mod.genCycleError },
});

/// numbers module functions (numeric ABCs)
const NumbersFuncs = FuncMap.initComptime(.{
    .{ "Number", numbers_mod.genNumber },
    .{ "Complex", numbers_mod.genComplex },
    .{ "Real", numbers_mod.genReal },
    .{ "Rational", numbers_mod.genRational },
    .{ "Integral", numbers_mod.genIntegral },
});

/// http.client module functions
const HttpClientFuncs = FuncMap.initComptime(.{
    .{ "HTTPConnection", http_mod.genHTTPConnection },
    .{ "HTTPSConnection", http_mod.genHTTPSConnection },
    .{ "HTTPResponse", http_mod.genHTTPResponse },
});

/// http.server module functions
const HttpServerFuncs = FuncMap.initComptime(.{
    .{ "HTTPServer", http_mod.genHTTPServer },
    .{ "ThreadingHTTPServer", http_mod.genThreadingHTTPServer },
    .{ "BaseHTTPRequestHandler", http_mod.genBaseHTTPRequestHandler },
    .{ "SimpleHTTPRequestHandler", http_mod.genSimpleHTTPRequestHandler },
    .{ "CGIHTTPRequestHandler", http_mod.genCGIHTTPRequestHandler },
});

/// http.cookies module functions
const HttpCookiesFuncs = FuncMap.initComptime(.{
    .{ "SimpleCookie", http_mod.genSimpleCookie },
    .{ "BaseCookie", http_mod.genBaseCookie },
});

/// http module functions (HTTPStatus)
const HttpModuleFuncs = FuncMap.initComptime(.{
    .{ "HTTPStatus", http_mod.genHTTPStatus },
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
    .{ "pickle", PickleFuncs },
    .{ "hmac", HmacFuncs },
    .{ "socket", SocketFuncs },
    .{ "random", RandomFuncs },
    .{ "string", StringFuncs },
    .{ "time", TimeFuncs },
    .{ "sys", SysFuncs },
    .{ "uuid", UuidFuncs },
    .{ "subprocess", SubprocessFuncs },
    .{ "tempfile", TempfileFuncs },
    .{ "textwrap", TextwrapFuncs },
    .{ "shutil", ShutilFuncs },
    .{ "glob", GlobFuncs },
    .{ "fnmatch", FnmatchFuncs },
    .{ "secrets", SecretsFuncs },
    .{ "csv", CsvFuncs },
    .{ "configparser", ConfigparserFuncs },
    .{ "argparse", ArgparseFuncs },
    .{ "zipfile", ZipfileFuncs },
    .{ "gzip", GzipFuncs },
    .{ "logging", LoggingFuncs },
    .{ "threading", ThreadingFuncs },
    .{ "queue", QueueFuncs },
    .{ "html", HtmlFuncs },
    .{ "urllib.parse", UrllibParseFuncs },
    .{ "xml.etree.ElementTree", XmlEtreeFuncs },
    .{ "ET", XmlEtreeFuncs },
    .{ "decimal", DecimalFuncs },
    .{ "fractions", FractionsFuncs },
    .{ "email.message", EmailMessageFuncs },
    .{ "email.mime.text", EmailMimeTextFuncs },
    .{ "email.mime.multipart", EmailMimeMultipartFuncs },
    .{ "email.mime.base", EmailMimeBaseFuncs },
    .{ "email.mime.application", EmailMimeBaseFuncs },
    .{ "email.mime.image", EmailMimeBaseFuncs },
    .{ "email.mime.audio", EmailMimeBaseFuncs },
    .{ "email.utils", EmailUtilsFuncs },
    .{ "sqlite3", Sqlite3Funcs },
    .{ "heapq", HeapqFuncs },
    .{ "weakref", WeakrefFuncs },
    .{ "types", TypesFuncs },
    .{ "bisect", BisectFuncs },
    .{ "statistics", StatisticsFuncs },
    .{ "abc", AbcFuncs },
    .{ "inspect", InspectFuncs },
    .{ "dataclasses", DataclassesFuncs },
    .{ "enum", EnumFuncs },
    .{ "operator", OperatorFuncs },
    .{ "atexit", AtexitFuncs },
    .{ "warnings", WarningsFuncs },
    .{ "traceback", TracebackFuncs },
    .{ "linecache", LinecacheFuncs },
    .{ "pprint", PprintFuncs },
    .{ "getpass", GetpassFuncs },
    .{ "platform", PlatformFuncs },
    .{ "locale", LocaleFuncs },
    .{ "codecs", CodecsFuncs },
    .{ "shelve", ShelveFuncs },
    .{ "cmath", CmathFuncs },
    .{ "array", ArrayFuncs },
    .{ "difflib", DifflibFuncs },
    .{ "filecmp", FilecmpFuncs },
    .{ "graphlib", GraphlibFuncs },
    .{ "numbers", NumbersFuncs },
    .{ "http.client", HttpClientFuncs },
    .{ "http.server", HttpServerFuncs },
    .{ "http.cookies", HttpCookiesFuncs },
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
