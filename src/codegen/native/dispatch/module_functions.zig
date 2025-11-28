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
const multiprocessing_mod = @import("../multiprocessing_mod.zig");
const concurrent_futures_mod = @import("../concurrent_futures_mod.zig");
const ctypes_mod = @import("../ctypes_mod.zig");
const select_mod = @import("../select_mod.zig");
const signal_mod = @import("../signal_mod.zig");
const mmap_mod = @import("../mmap_mod.zig");
const fcntl_mod = @import("../fcntl_mod.zig");
const termios_mod = @import("../termios_mod.zig");
const pty_mod = @import("../pty_mod.zig");
const tty_mod = @import("../tty_mod.zig");
const errno_mod = @import("../errno_mod.zig");
const resource_mod = @import("../resource_mod.zig");
const grp_mod = @import("../grp_mod.zig");
const pwd_mod = @import("../pwd_mod.zig");
const syslog_mod = @import("../syslog_mod.zig");
const curses_mod = @import("../curses_mod.zig");
const bz2_mod = @import("../bz2_mod.zig");
const lzma_mod = @import("../lzma_mod.zig");
const tarfile_mod = @import("../tarfile_mod.zig");
const shlex_mod = @import("../shlex_mod.zig");
const gettext_mod = @import("../gettext_mod.zig");
const calendar_mod = @import("../calendar_mod.zig");
const cmd_mod = @import("../cmd_mod.zig");
const code_mod = @import("../code_mod.zig");
const codeop_mod = @import("../codeop_mod.zig");
const dis_mod = @import("../dis_mod.zig");
const gc_mod = @import("../gc_mod.zig");
const ast_module = @import("../ast_mod.zig");
const unittest_mock_mod = @import("../unittest_mock_mod.zig");
const doctest_mod = @import("../doctest_mod.zig");
const profile_mod = @import("../profile_mod.zig");
const pdb_mod = @import("../pdb_mod.zig");
const timeit_mod = @import("../timeit_mod.zig");
const trace_mod = @import("../trace_mod.zig");
const binascii_mod = @import("../binascii_mod.zig");
const smtplib_mod = @import("../smtplib_mod.zig");
const imaplib_mod = @import("../imaplib_mod.zig");
const ftplib_mod = @import("../ftplib_mod.zig");
const poplib_mod = @import("../poplib_mod.zig");
const nntplib_mod = @import("../nntplib_mod.zig");
const ssl_mod = @import("../ssl_mod.zig");
const selectors_mod = @import("../selectors_mod.zig");
const ipaddress_mod = @import("../ipaddress_mod.zig");
const telnetlib_mod = @import("../telnetlib_mod.zig");
const xmlrpc_mod = @import("../xmlrpc_mod.zig");
const http_cookiejar_mod = @import("../http_cookiejar_mod.zig");
const urllib_request_mod = @import("../urllib_request_mod.zig");
const urllib_error_mod = @import("../urllib_error_mod.zig");
const urllib_robotparser_mod = @import("../urllib_robotparser_mod.zig");
const cgi_mod = @import("../cgi_mod.zig");
const wsgiref_mod = @import("../wsgiref_mod.zig");
const audioop_mod = @import("../audioop_mod.zig");
const wave_mod = @import("../wave_mod.zig");
const aifc_mod = @import("../aifc_mod.zig");
const sunau_mod = @import("../sunau_mod.zig");
const sndhdr_mod = @import("../sndhdr_mod.zig");
const imghdr_mod = @import("../imghdr_mod.zig");
const colorsys_mod = @import("../colorsys_mod.zig");
const netrc_mod = @import("../netrc_mod.zig");
const xdrlib_mod = @import("../xdrlib_mod.zig");
const plistlib_mod = @import("../plistlib_mod.zig");
const rlcompleter_mod = @import("../rlcompleter_mod.zig");
const readline_mod = @import("../readline_mod.zig");
const sched_mod = @import("../sched_mod.zig");
const mailbox_mod = @import("../mailbox_mod.zig");
const mailcap_mod = @import("../mailcap_mod.zig");
const mimetypes_mod = @import("../mimetypes_mod.zig");
const quopri_mod = @import("../quopri_mod.zig");
const uu_mod = @import("../uu_mod.zig");
const html_parser_mod = @import("../html_parser_mod.zig");
const html_entities_mod = @import("../html_entities_mod.zig");
const xml_sax_mod = @import("../xml_sax_mod.zig");
const xml_dom_mod = @import("../xml_dom_mod.zig");
const builtins_mod = @import("../builtins_mod.zig");
const typing_extensions_mod = @import("../typing_extensions_mod.zig");
const importlib_mod = @import("../importlib_mod.zig");
const pkgutil_mod = @import("../pkgutil_mod.zig");
const runpy_mod = @import("../runpy_mod.zig");
const venv_mod = @import("../venv_mod.zig");
const zipimport_mod = @import("../zipimport_mod.zig");
const compileall_mod = @import("../compileall_mod.zig");
const py_compile_mod = @import("../py_compile_mod.zig");
const contextvars_mod = @import("../contextvars_mod.zig");
const site_mod = @import("../site_mod.zig");
const __future___mod = @import("../__future___mod.zig");
const copyreg_mod = @import("../copyreg_mod.zig");
const _thread_mod = @import("../_thread_mod.zig");
const posixpath_mod = @import("../posixpath_mod.zig");
const reprlib_mod = @import("../reprlib_mod.zig");
const _collections_abc_mod = @import("../_collections_abc_mod.zig");
const keyword_mod = @import("../keyword_mod.zig");
const token_mod = @import("../token_mod.zig");
const tokenize_mod = @import("../tokenize_mod.zig");
const dbm_mod = @import("../dbm_mod.zig");
const symtable_mod = @import("../symtable_mod.zig");
const crypt_mod = @import("../crypt_mod.zig");
const posix_mod = @import("../posix_mod.zig");
const _io_mod = @import("../_io_mod.zig");
const genericpath_mod = @import("../genericpath_mod.zig");
const ntpath_mod = @import("../ntpath_mod.zig");
const zlib_mod = @import("../zlib_mod.zig");
const zipapp_mod = @import("../zipapp_mod.zig");
const ensurepip_mod = @import("../ensurepip_mod.zig");
const _string_mod = @import("../_string_mod.zig");
const _weakref_mod = @import("../_weakref_mod.zig");
const _functools_mod = @import("../_functools_mod.zig");
const _operator_mod = @import("../_operator_mod.zig");
const _json_mod = @import("../_json_mod.zig");
const _codecs_mod = @import("../_codecs_mod.zig");
const _collections_mod = @import("../_collections_mod.zig");
const _stat_mod = @import("../_stat_mod.zig");
const stat_mod = @import("../stat_mod.zig");
const _heapq_mod = @import("../_heapq_mod.zig");
const _bisect_mod = @import("../_bisect_mod.zig");
const _random_mod = @import("../_random_mod.zig");
const _struct_mod = @import("../_struct_mod.zig");
const _pickle_mod = @import("../_pickle_mod.zig");
const _datetime_mod = @import("../_datetime_mod.zig");
const _csv_mod = @import("../_csv_mod.zig");
const _socket_mod = @import("../_socket_mod.zig");
const _hashlib_mod = @import("../_hashlib_mod.zig");
const _locale_mod = @import("../_locale_mod.zig");
const _signal_mod = @import("../_signal_mod.zig");
const math_mod = @import("../math_mod.zig");
const faulthandler_mod = @import("../faulthandler_mod.zig");
const tracemalloc_mod = @import("../tracemalloc_mod.zig");
const sysconfig_mod = @import("../sysconfig_mod.zig");
const fileinput_mod = @import("../fileinput_mod.zig");
const getopt_mod = @import("../getopt_mod.zig");
const chunk_mod = @import("../chunk_mod.zig");
const bdb_mod = @import("../bdb_mod.zig");
const pstats_mod = @import("../pstats_mod.zig");
const unicodedata_mod = @import("../unicodedata_mod.zig");
const zoneinfo_mod = @import("../zoneinfo_mod.zig");
const tomllib_mod = @import("../tomllib_mod.zig");
const webbrowser_mod = @import("../webbrowser_mod.zig");
const modulefinder_mod = @import("../modulefinder_mod.zig");
const pyclbr_mod = @import("../pyclbr_mod.zig");
const tabnanny_mod = @import("../tabnanny_mod.zig");
const stringprep_mod = @import("../stringprep_mod.zig");
const pickletools_mod = @import("../pickletools_mod.zig");
const pipes_mod = @import("../pipes_mod.zig");
const socketserver_mod = @import("../socketserver_mod.zig");
const cgitb_mod = @import("../cgitb_mod.zig");
const optparse_mod = @import("../optparse_mod.zig");
const sre_compile_mod = @import("../sre_compile_mod.zig");
const sre_constants_mod = @import("../sre_constants_mod.zig");
const sre_parse_mod = @import("../sre_parse_mod.zig");
const encodings_mod = @import("../encodings_mod.zig");
const marshal_mod = @import("../marshal_mod.zig");
const opcode_mod = @import("../opcode_mod.zig");

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
    .{ "getenv", os_mod.genGetenv },
    .{ "mkdir", os_mod.genMkdir },
    .{ "makedirs", os_mod.genMakedirs },
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

/// multiprocessing module functions
const MultiprocessingFuncs = FuncMap.initComptime(.{
    .{ "Process", multiprocessing_mod.genProcess },
    .{ "Pool", multiprocessing_mod.genPool },
    .{ "Queue", multiprocessing_mod.genQueue },
    .{ "Pipe", multiprocessing_mod.genPipe },
    .{ "Value", multiprocessing_mod.genValue },
    .{ "Array", multiprocessing_mod.genArray },
    .{ "Manager", multiprocessing_mod.genManager },
    .{ "Lock", multiprocessing_mod.genLock },
    .{ "RLock", multiprocessing_mod.genRLock },
    .{ "Semaphore", multiprocessing_mod.genSemaphore },
    .{ "Event", multiprocessing_mod.genEvent },
    .{ "Condition", multiprocessing_mod.genCondition },
    .{ "Barrier", multiprocessing_mod.genBarrier },
    .{ "cpu_count", multiprocessing_mod.genCpuCount },
    .{ "current_process", multiprocessing_mod.genCurrentProcess },
    .{ "parent_process", multiprocessing_mod.genParentProcess },
    .{ "active_children", multiprocessing_mod.genActiveChildren },
    .{ "set_start_method", multiprocessing_mod.genSetStartMethod },
    .{ "get_start_method", multiprocessing_mod.genGetStartMethod },
    .{ "get_all_start_methods", multiprocessing_mod.genGetAllStartMethods },
    .{ "get_context", multiprocessing_mod.genGetContext },
});

/// concurrent.futures module functions
const ConcurrentFuturesFuncs = FuncMap.initComptime(.{
    .{ "ThreadPoolExecutor", concurrent_futures_mod.genThreadPoolExecutor },
    .{ "ProcessPoolExecutor", concurrent_futures_mod.genProcessPoolExecutor },
    .{ "Future", concurrent_futures_mod.genFuture },
    .{ "wait", concurrent_futures_mod.genWait },
    .{ "as_completed", concurrent_futures_mod.genAsCompleted },
    .{ "ALL_COMPLETED", concurrent_futures_mod.genAllCompleted },
    .{ "FIRST_COMPLETED", concurrent_futures_mod.genFirstCompleted },
    .{ "FIRST_EXCEPTION", concurrent_futures_mod.genFirstException },
    .{ "CancelledError", concurrent_futures_mod.genCancelledError },
    .{ "TimeoutError", concurrent_futures_mod.genTimeoutError },
    .{ "BrokenExecutor", concurrent_futures_mod.genBrokenExecutor },
    .{ "InvalidStateError", concurrent_futures_mod.genInvalidStateError },
});

/// ctypes module functions
const CtypesFuncs = FuncMap.initComptime(.{
    .{ "CDLL", ctypes_mod.genCDLL },
    .{ "WinDLL", ctypes_mod.genWinDLL },
    .{ "OleDLL", ctypes_mod.genOleDLL },
    .{ "PyDLL", ctypes_mod.genPyDLL },
    .{ "c_bool", ctypes_mod.genCBool },
    .{ "c_char", ctypes_mod.genCChar },
    .{ "c_wchar", ctypes_mod.genCWchar },
    .{ "c_byte", ctypes_mod.genCByte },
    .{ "c_ubyte", ctypes_mod.genCUbyte },
    .{ "c_short", ctypes_mod.genCShort },
    .{ "c_ushort", ctypes_mod.genCUshort },
    .{ "c_int", ctypes_mod.genCInt },
    .{ "c_uint", ctypes_mod.genCUint },
    .{ "c_long", ctypes_mod.genCLong },
    .{ "c_ulong", ctypes_mod.genCUlong },
    .{ "c_longlong", ctypes_mod.genCLonglong },
    .{ "c_ulonglong", ctypes_mod.genCUlonglong },
    .{ "c_size_t", ctypes_mod.genCSizeT },
    .{ "c_ssize_t", ctypes_mod.genCSSizeT },
    .{ "c_float", ctypes_mod.genCFloat },
    .{ "c_double", ctypes_mod.genCDouble },
    .{ "c_longdouble", ctypes_mod.genCLongdouble },
    .{ "c_char_p", ctypes_mod.genCCharP },
    .{ "c_wchar_p", ctypes_mod.genCWcharP },
    .{ "c_void_p", ctypes_mod.genCVoidP },
    .{ "Structure", ctypes_mod.genStructure },
    .{ "Union", ctypes_mod.genUnion },
    .{ "BigEndianStructure", ctypes_mod.genBigEndianStructure },
    .{ "LittleEndianStructure", ctypes_mod.genLittleEndianStructure },
    .{ "Array", ctypes_mod.genArrayType },
    .{ "POINTER", ctypes_mod.genPOINTER },
    .{ "pointer", ctypes_mod.genPointer },
    .{ "sizeof", ctypes_mod.genSizeof },
    .{ "alignment", ctypes_mod.genAlignment },
    .{ "addressof", ctypes_mod.genAddressof },
    .{ "byref", ctypes_mod.genByref },
    .{ "cast", ctypes_mod.genCast },
    .{ "create_string_buffer", ctypes_mod.genCreateStringBuffer },
    .{ "create_unicode_buffer", ctypes_mod.genCreateUnicodeBuffer },
    .{ "get_errno", ctypes_mod.genGetErrno },
    .{ "set_errno", ctypes_mod.genSetErrno },
    .{ "get_last_error", ctypes_mod.genGetLastError },
    .{ "set_last_error", ctypes_mod.genSetLastError },
    .{ "memmove", ctypes_mod.genMemmove },
    .{ "memset", ctypes_mod.genMemset },
    .{ "string_at", ctypes_mod.genStringAt },
    .{ "wstring_at", ctypes_mod.genWstringAt },
    .{ "CFUNCTYPE", ctypes_mod.genCFUNCTYPE },
    .{ "WINFUNCTYPE", ctypes_mod.genWINFUNCTYPE },
    .{ "PYFUNCTYPE", ctypes_mod.genPYFUNCTYPE },
});

/// select module functions
const SelectFuncs = FuncMap.initComptime(.{
    .{ "select", select_mod.genSelect },
    .{ "poll", select_mod.genPoll },
    .{ "epoll", select_mod.genEpoll },
    .{ "devpoll", select_mod.genDevpoll },
    .{ "kqueue", select_mod.genKqueue },
    .{ "kevent", select_mod.genKevent },
    .{ "POLLIN", select_mod.genPOLLIN },
    .{ "POLLPRI", select_mod.genPOLLPRI },
    .{ "POLLOUT", select_mod.genPOLLOUT },
    .{ "POLLERR", select_mod.genPOLLERR },
    .{ "POLLHUP", select_mod.genPOLLHUP },
    .{ "POLLNVAL", select_mod.genPOLLNVAL },
    .{ "EPOLLIN", select_mod.genEPOLLIN },
    .{ "EPOLLOUT", select_mod.genEPOLLOUT },
    .{ "EPOLLPRI", select_mod.genEPOLLPRI },
    .{ "EPOLLERR", select_mod.genEPOLLERR },
    .{ "EPOLLHUP", select_mod.genEPOLLHUP },
    .{ "EPOLLET", select_mod.genEPOLLET },
    .{ "EPOLLONESHOT", select_mod.genEPOLLONESHOT },
    .{ "EPOLLEXCLUSIVE", select_mod.genEPOLLEXCLUSIVE },
    .{ "EPOLLRDHUP", select_mod.genEPOLLRDHUP },
    .{ "EPOLLRDNORM", select_mod.genEPOLLRDNORM },
    .{ "EPOLLRDBAND", select_mod.genEPOLLRDBAND },
    .{ "EPOLLWRNORM", select_mod.genEPOLLWRNORM },
    .{ "EPOLLWRBAND", select_mod.genEPOLLWRBAND },
    .{ "EPOLLMSG", select_mod.genEPOLLMSG },
    .{ "KQ_FILTER_READ", select_mod.genKQ_FILTER_READ },
    .{ "KQ_FILTER_WRITE", select_mod.genKQ_FILTER_WRITE },
    .{ "KQ_FILTER_AIO", select_mod.genKQ_FILTER_AIO },
    .{ "KQ_FILTER_VNODE", select_mod.genKQ_FILTER_VNODE },
    .{ "KQ_FILTER_PROC", select_mod.genKQ_FILTER_PROC },
    .{ "KQ_FILTER_SIGNAL", select_mod.genKQ_FILTER_SIGNAL },
    .{ "KQ_FILTER_TIMER", select_mod.genKQ_FILTER_TIMER },
    .{ "KQ_EV_ADD", select_mod.genKQ_EV_ADD },
    .{ "KQ_EV_DELETE", select_mod.genKQ_EV_DELETE },
    .{ "KQ_EV_ENABLE", select_mod.genKQ_EV_ENABLE },
    .{ "KQ_EV_DISABLE", select_mod.genKQ_EV_DISABLE },
    .{ "KQ_EV_ONESHOT", select_mod.genKQ_EV_ONESHOT },
    .{ "KQ_EV_CLEAR", select_mod.genKQ_EV_CLEAR },
    .{ "KQ_EV_EOF", select_mod.genKQ_EV_EOF },
    .{ "KQ_EV_ERROR", select_mod.genKQ_EV_ERROR },
});

/// signal module functions
const SignalFuncs = FuncMap.initComptime(.{
    .{ "signal", signal_mod.genSignal },
    .{ "getsignal", signal_mod.genGetsignal },
    .{ "strsignal", signal_mod.genStrsignal },
    .{ "valid_signals", signal_mod.genValidSignals },
    .{ "raise_signal", signal_mod.genRaiseSignal },
    .{ "alarm", signal_mod.genAlarm },
    .{ "pause", signal_mod.genPause },
    .{ "setitimer", signal_mod.genSetitimer },
    .{ "getitimer", signal_mod.genGetitimer },
    .{ "set_wakeup_fd", signal_mod.genSetWakeupFd },
    .{ "sigwait", signal_mod.genSigwait },
    .{ "sigwaitinfo", signal_mod.genSigwaitinfo },
    .{ "sigtimedwait", signal_mod.genSigtimedwait },
    .{ "pthread_sigmask", signal_mod.genPthreadSigmask },
    .{ "pthread_kill", signal_mod.genPthreadKill },
    .{ "sigpending", signal_mod.genSigpending },
    .{ "siginterrupt", signal_mod.genSiginterrupt },
    .{ "SIGHUP", signal_mod.genSIGHUP },
    .{ "SIGINT", signal_mod.genSIGINT },
    .{ "SIGQUIT", signal_mod.genSIGQUIT },
    .{ "SIGILL", signal_mod.genSIGILL },
    .{ "SIGTRAP", signal_mod.genSIGTRAP },
    .{ "SIGABRT", signal_mod.genSIGABRT },
    .{ "SIGBUS", signal_mod.genSIGBUS },
    .{ "SIGFPE", signal_mod.genSIGFPE },
    .{ "SIGKILL", signal_mod.genSIGKILL },
    .{ "SIGUSR1", signal_mod.genSIGUSR1 },
    .{ "SIGSEGV", signal_mod.genSIGSEGV },
    .{ "SIGUSR2", signal_mod.genSIGUSR2 },
    .{ "SIGPIPE", signal_mod.genSIGPIPE },
    .{ "SIGALRM", signal_mod.genSIGALRM },
    .{ "SIGTERM", signal_mod.genSIGTERM },
    .{ "SIGCHLD", signal_mod.genSIGCHLD },
    .{ "SIGCONT", signal_mod.genSIGCONT },
    .{ "SIGSTOP", signal_mod.genSIGSTOP },
    .{ "SIGTSTP", signal_mod.genSIGTSTP },
    .{ "SIGTTIN", signal_mod.genSIGTTIN },
    .{ "SIGTTOU", signal_mod.genSIGTTOU },
    .{ "SIGURG", signal_mod.genSIGURG },
    .{ "SIGXCPU", signal_mod.genSIGXCPU },
    .{ "SIGXFSZ", signal_mod.genSIGXFSZ },
    .{ "SIGVTALRM", signal_mod.genSIGVTALRM },
    .{ "SIGPROF", signal_mod.genSIGPROF },
    .{ "SIGWINCH", signal_mod.genSIGWINCH },
    .{ "SIGIO", signal_mod.genSIGIO },
    .{ "SIGSYS", signal_mod.genSIGSYS },
    .{ "SIG_DFL", signal_mod.genSIG_DFL },
    .{ "SIG_IGN", signal_mod.genSIG_IGN },
    .{ "SIG_BLOCK", signal_mod.genSIG_BLOCK },
    .{ "SIG_UNBLOCK", signal_mod.genSIG_UNBLOCK },
    .{ "SIG_SETMASK", signal_mod.genSIG_SETMASK },
    .{ "ITIMER_REAL", signal_mod.genITIMER_REAL },
    .{ "ITIMER_VIRTUAL", signal_mod.genITIMER_VIRTUAL },
    .{ "ITIMER_PROF", signal_mod.genITIMER_PROF },
    .{ "NSIG", signal_mod.genNSIG },
    .{ "Signals", signal_mod.genSignals },
    .{ "Handlers", signal_mod.genHandlers },
});

/// mmap module functions
const MmapFuncs = FuncMap.initComptime(.{
    .{ "mmap", mmap_mod.genMmap },
    .{ "ACCESS_READ", mmap_mod.genACCESS_READ },
    .{ "ACCESS_WRITE", mmap_mod.genACCESS_WRITE },
    .{ "ACCESS_COPY", mmap_mod.genACCESS_COPY },
    .{ "ACCESS_DEFAULT", mmap_mod.genACCESS_DEFAULT },
    .{ "MAP_SHARED", mmap_mod.genMAP_SHARED },
    .{ "MAP_PRIVATE", mmap_mod.genMAP_PRIVATE },
    .{ "MAP_ANONYMOUS", mmap_mod.genMAP_ANONYMOUS },
    .{ "PROT_READ", mmap_mod.genPROT_READ },
    .{ "PROT_WRITE", mmap_mod.genPROT_WRITE },
    .{ "PROT_EXEC", mmap_mod.genPROT_EXEC },
    .{ "PAGESIZE", mmap_mod.genPAGESIZE },
    .{ "ALLOCATIONGRANULARITY", mmap_mod.genALLOCATIONGRANULARITY },
    .{ "MADV_NORMAL", mmap_mod.genMADV_NORMAL },
    .{ "MADV_RANDOM", mmap_mod.genMADV_RANDOM },
    .{ "MADV_SEQUENTIAL", mmap_mod.genMADV_SEQUENTIAL },
    .{ "MADV_WILLNEED", mmap_mod.genMADV_WILLNEED },
    .{ "MADV_DONTNEED", mmap_mod.genMADV_DONTNEED },
});

/// fcntl module functions
const FcntlFuncs = FuncMap.initComptime(.{
    .{ "fcntl", fcntl_mod.genFcntl },
    .{ "ioctl", fcntl_mod.genIoctl },
    .{ "flock", fcntl_mod.genFlock },
    .{ "lockf", fcntl_mod.genLockf },
    .{ "F_DUPFD", fcntl_mod.genF_DUPFD },
    .{ "F_GETFD", fcntl_mod.genF_GETFD },
    .{ "F_SETFD", fcntl_mod.genF_SETFD },
    .{ "F_GETFL", fcntl_mod.genF_GETFL },
    .{ "F_SETFL", fcntl_mod.genF_SETFL },
    .{ "F_GETLK", fcntl_mod.genF_GETLK },
    .{ "F_SETLK", fcntl_mod.genF_SETLK },
    .{ "F_SETLKW", fcntl_mod.genF_SETLKW },
    .{ "F_RDLCK", fcntl_mod.genF_RDLCK },
    .{ "F_WRLCK", fcntl_mod.genF_WRLCK },
    .{ "F_UNLCK", fcntl_mod.genF_UNLCK },
    .{ "FD_CLOEXEC", fcntl_mod.genFD_CLOEXEC },
    .{ "F_GETOWN", fcntl_mod.genF_GETOWN },
    .{ "F_SETOWN", fcntl_mod.genF_SETOWN },
    .{ "F_GETSIG", fcntl_mod.genF_GETSIG },
    .{ "F_SETSIG", fcntl_mod.genF_SETSIG },
    .{ "LOCK_SH", fcntl_mod.genLOCK_SH },
    .{ "LOCK_EX", fcntl_mod.genLOCK_EX },
    .{ "LOCK_NB", fcntl_mod.genLOCK_NB },
    .{ "LOCK_UN", fcntl_mod.genLOCK_UN },
    .{ "F_LOCK", fcntl_mod.genF_LOCK },
    .{ "F_TLOCK", fcntl_mod.genF_TLOCK },
    .{ "F_ULOCK", fcntl_mod.genF_ULOCK },
    .{ "F_TEST", fcntl_mod.genF_TEST },
});

/// termios module functions
const TermiosFuncs = FuncMap.initComptime(.{
    .{ "tcgetattr", termios_mod.genTcgetattr },
    .{ "tcsetattr", termios_mod.genTcsetattr },
    .{ "tcsendbreak", termios_mod.genTcsendbreak },
    .{ "tcdrain", termios_mod.genTcdrain },
    .{ "tcflush", termios_mod.genTcflush },
    .{ "tcflow", termios_mod.genTcflow },
    .{ "tcgetwinsize", termios_mod.genTcgetwinsize },
    .{ "tcsetwinsize", termios_mod.genTcsetwinsize },
    .{ "TCSANOW", termios_mod.genTCSANOW },
    .{ "TCSADRAIN", termios_mod.genTCSADRAIN },
    .{ "TCSAFLUSH", termios_mod.genTCSAFLUSH },
    .{ "TCIFLUSH", termios_mod.genTCIFLUSH },
    .{ "TCOFLUSH", termios_mod.genTCOFLUSH },
    .{ "TCIOFLUSH", termios_mod.genTCIOFLUSH },
    .{ "TCOOFF", termios_mod.genTCOOFF },
    .{ "TCOON", termios_mod.genTCOON },
    .{ "TCIOFF", termios_mod.genTCIOFF },
    .{ "TCION", termios_mod.genTCION },
    .{ "ECHO", termios_mod.genECHO },
    .{ "ECHOE", termios_mod.genECHOE },
    .{ "ECHOK", termios_mod.genECHOK },
    .{ "ECHONL", termios_mod.genECHONL },
    .{ "ICANON", termios_mod.genICANON },
    .{ "ISIG", termios_mod.genISIG },
    .{ "IEXTEN", termios_mod.genIEXTEN },
    .{ "ICRNL", termios_mod.genICRNL },
    .{ "IXON", termios_mod.genIXON },
    .{ "IXOFF", termios_mod.genIXOFF },
    .{ "OPOST", termios_mod.genOPOST },
    .{ "ONLCR", termios_mod.genONLCR },
    .{ "CS8", termios_mod.genCS8 },
    .{ "CREAD", termios_mod.genCREAD },
    .{ "CLOCAL", termios_mod.genCLOCAL },
    .{ "B9600", termios_mod.genB9600 },
    .{ "B19200", termios_mod.genB19200 },
    .{ "B38400", termios_mod.genB38400 },
    .{ "B57600", termios_mod.genB57600 },
    .{ "B115200", termios_mod.genB115200 },
    .{ "VMIN", termios_mod.genVMIN },
    .{ "VTIME", termios_mod.genVTIME },
    .{ "NCCS", termios_mod.genNCCS },
});

/// pty module functions
const PtyFuncs = FuncMap.initComptime(.{
    .{ "fork", pty_mod.genFork },
    .{ "openpty", pty_mod.genOpenpty },
    .{ "spawn", pty_mod.genSpawn },
    .{ "STDIN_FILENO", pty_mod.genSTDIN_FILENO },
    .{ "STDOUT_FILENO", pty_mod.genSTDOUT_FILENO },
    .{ "STDERR_FILENO", pty_mod.genSTDERR_FILENO },
    .{ "CHILD", pty_mod.genCHILD },
});

/// tty module functions
const TtyFuncs = FuncMap.initComptime(.{
    .{ "setraw", tty_mod.genSetraw },
    .{ "setcbreak", tty_mod.genSetcbreak },
    .{ "isatty", tty_mod.genIsatty },
});

/// errno module functions
const ErrnoFuncs = FuncMap.initComptime(.{
    .{ "errorcode", errno_mod.genErrorcode },
    .{ "EPERM", errno_mod.genEPERM },
    .{ "ENOENT", errno_mod.genENOENT },
    .{ "ESRCH", errno_mod.genESRCH },
    .{ "EINTR", errno_mod.genEINTR },
    .{ "EIO", errno_mod.genEIO },
    .{ "ENXIO", errno_mod.genENXIO },
    .{ "E2BIG", errno_mod.genE2BIG },
    .{ "ENOEXEC", errno_mod.genENOEXEC },
    .{ "EBADF", errno_mod.genEBADF },
    .{ "ECHILD", errno_mod.genECHILD },
    .{ "EAGAIN", errno_mod.genEAGAIN },
    .{ "ENOMEM", errno_mod.genENOMEM },
    .{ "EACCES", errno_mod.genEACCES },
    .{ "EFAULT", errno_mod.genEFAULT },
    .{ "ENOTBLK", errno_mod.genENOTBLK },
    .{ "EBUSY", errno_mod.genEBUSY },
    .{ "EEXIST", errno_mod.genEEXIST },
    .{ "EXDEV", errno_mod.genEXDEV },
    .{ "ENODEV", errno_mod.genENODEV },
    .{ "ENOTDIR", errno_mod.genENOTDIR },
    .{ "EISDIR", errno_mod.genEISDIR },
    .{ "EINVAL", errno_mod.genEINVAL },
    .{ "ENFILE", errno_mod.genENFILE },
    .{ "EMFILE", errno_mod.genEMFILE },
    .{ "ENOTTY", errno_mod.genENOTTY },
    .{ "ETXTBSY", errno_mod.genETXTBSY },
    .{ "EFBIG", errno_mod.genEFBIG },
    .{ "ENOSPC", errno_mod.genENOSPC },
    .{ "ESPIPE", errno_mod.genESPIPE },
    .{ "EROFS", errno_mod.genEROFS },
    .{ "EMLINK", errno_mod.genEMLINK },
    .{ "EPIPE", errno_mod.genEPIPE },
    .{ "EDOM", errno_mod.genEDOM },
    .{ "ERANGE", errno_mod.genERANGE },
    .{ "EDEADLK", errno_mod.genEDEADLK },
    .{ "ENAMETOOLONG", errno_mod.genENAMETOOLONG },
    .{ "ENOLCK", errno_mod.genENOLCK },
    .{ "ENOSYS", errno_mod.genENOSYS },
    .{ "ENOTEMPTY", errno_mod.genENOTEMPTY },
    .{ "ELOOP", errno_mod.genELOOP },
    .{ "EWOULDBLOCK", errno_mod.genEWOULDBLOCK },
    .{ "ENOMSG", errno_mod.genENOMSG },
    .{ "EIDRM", errno_mod.genEIDRM },
    .{ "ECHRNG", errno_mod.genECHRNG },
    .{ "ENOSTR", errno_mod.genENOSTR },
    .{ "ENODATA", errno_mod.genENODATA },
    .{ "ETIME", errno_mod.genETIME },
    .{ "ENOSR", errno_mod.genENOSR },
    .{ "EOVERFLOW", errno_mod.genEOVERFLOW },
    .{ "ENOTSOCK", errno_mod.genENOTSOCK },
    .{ "EDESTADDRREQ", errno_mod.genEDESTADDRREQ },
    .{ "EMSGSIZE", errno_mod.genEMSGSIZE },
    .{ "EPROTOTYPE", errno_mod.genEPROTOTYPE },
    .{ "ENOPROTOOPT", errno_mod.genENOPROTOOPT },
    .{ "EPROTONOSUPPORT", errno_mod.genEPROTONOSUPPORT },
    .{ "ESOCKTNOSUPPORT", errno_mod.genESOCKTNOSUPPORT },
    .{ "EOPNOTSUPP", errno_mod.genEOPNOTSUPP },
    .{ "EPFNOSUPPORT", errno_mod.genEPFNOSUPPORT },
    .{ "EAFNOSUPPORT", errno_mod.genEAFNOSUPPORT },
    .{ "EADDRINUSE", errno_mod.genEADDRINUSE },
    .{ "EADDRNOTAVAIL", errno_mod.genEADDRNOTAVAIL },
    .{ "ENETDOWN", errno_mod.genENETDOWN },
    .{ "ENETUNREACH", errno_mod.genENETUNREACH },
    .{ "ENETRESET", errno_mod.genENETRESET },
    .{ "ECONNABORTED", errno_mod.genECONNABORTED },
    .{ "ECONNRESET", errno_mod.genECONNRESET },
    .{ "ENOBUFS", errno_mod.genENOBUFS },
    .{ "EISCONN", errno_mod.genEISCONN },
    .{ "ENOTCONN", errno_mod.genENOTCONN },
    .{ "ESHUTDOWN", errno_mod.genESHUTDOWN },
    .{ "ETOOMANYREFS", errno_mod.genETOOMANYREFS },
    .{ "ETIMEDOUT", errno_mod.genETIMEDOUT },
    .{ "ECONNREFUSED", errno_mod.genECONNREFUSED },
    .{ "EHOSTDOWN", errno_mod.genEHOSTDOWN },
    .{ "EHOSTUNREACH", errno_mod.genEHOSTUNREACH },
    .{ "EALREADY", errno_mod.genEALREADY },
    .{ "EINPROGRESS", errno_mod.genEINPROGRESS },
    .{ "ESTALE", errno_mod.genESTALE },
    .{ "ECANCELED", errno_mod.genECANCELED },
    .{ "ENOKEY", errno_mod.genENOKEY },
    .{ "EKEYEXPIRED", errno_mod.genEKEYEXPIRED },
    .{ "EKEYREVOKED", errno_mod.genEKEYREVOKED },
    .{ "EKEYREJECTED", errno_mod.genEKEYREJECTED },
});

/// resource module functions
const ResourceFuncs = FuncMap.initComptime(.{
    .{ "getrusage", resource_mod.genGetrusage },
    .{ "getrlimit", resource_mod.genGetrlimit },
    .{ "setrlimit", resource_mod.genSetrlimit },
    .{ "prlimit", resource_mod.genPrlimit },
    .{ "getpagesize", resource_mod.genGetpagesize },
    .{ "RUSAGE_SELF", resource_mod.genRUSAGE_SELF },
    .{ "RUSAGE_CHILDREN", resource_mod.genRUSAGE_CHILDREN },
    .{ "RUSAGE_BOTH", resource_mod.genRUSAGE_BOTH },
    .{ "RUSAGE_THREAD", resource_mod.genRUSAGE_THREAD },
    .{ "RLIMIT_CPU", resource_mod.genRLIMIT_CPU },
    .{ "RLIMIT_FSIZE", resource_mod.genRLIMIT_FSIZE },
    .{ "RLIMIT_DATA", resource_mod.genRLIMIT_DATA },
    .{ "RLIMIT_STACK", resource_mod.genRLIMIT_STACK },
    .{ "RLIMIT_CORE", resource_mod.genRLIMIT_CORE },
    .{ "RLIMIT_RSS", resource_mod.genRLIMIT_RSS },
    .{ "RLIMIT_NPROC", resource_mod.genRLIMIT_NPROC },
    .{ "RLIMIT_NOFILE", resource_mod.genRLIMIT_NOFILE },
    .{ "RLIMIT_MEMLOCK", resource_mod.genRLIMIT_MEMLOCK },
    .{ "RLIMIT_AS", resource_mod.genRLIMIT_AS },
    .{ "RLIMIT_LOCKS", resource_mod.genRLIMIT_LOCKS },
    .{ "RLIMIT_SIGPENDING", resource_mod.genRLIMIT_SIGPENDING },
    .{ "RLIMIT_MSGQUEUE", resource_mod.genRLIMIT_MSGQUEUE },
    .{ "RLIMIT_NICE", resource_mod.genRLIMIT_NICE },
    .{ "RLIMIT_RTPRIO", resource_mod.genRLIMIT_RTPRIO },
    .{ "RLIMIT_RTTIME", resource_mod.genRLIMIT_RTTIME },
    .{ "RLIM_INFINITY", resource_mod.genRLIM_INFINITY },
});

/// grp module functions
const GrpFuncs = FuncMap.initComptime(.{
    .{ "getgrnam", grp_mod.genGetgrnam },
    .{ "getgrgid", grp_mod.genGetgrgid },
    .{ "getgrall", grp_mod.genGetgrall },
    .{ "struct_group", grp_mod.genStruct_group },
});

/// pwd module functions
const PwdFuncs = FuncMap.initComptime(.{
    .{ "getpwnam", pwd_mod.genGetpwnam },
    .{ "getpwuid", pwd_mod.genGetpwuid },
    .{ "getpwall", pwd_mod.genGetpwall },
    .{ "struct_passwd", pwd_mod.genStruct_passwd },
});

/// syslog module functions
const SyslogFuncs = FuncMap.initComptime(.{
    .{ "openlog", syslog_mod.genOpenlog },
    .{ "syslog", syslog_mod.genSyslog },
    .{ "closelog", syslog_mod.genCloselog },
    .{ "setlogmask", syslog_mod.genSetlogmask },
    .{ "LOG_EMERG", syslog_mod.genLOG_EMERG },
    .{ "LOG_ALERT", syslog_mod.genLOG_ALERT },
    .{ "LOG_CRIT", syslog_mod.genLOG_CRIT },
    .{ "LOG_ERR", syslog_mod.genLOG_ERR },
    .{ "LOG_WARNING", syslog_mod.genLOG_WARNING },
    .{ "LOG_NOTICE", syslog_mod.genLOG_NOTICE },
    .{ "LOG_INFO", syslog_mod.genLOG_INFO },
    .{ "LOG_DEBUG", syslog_mod.genLOG_DEBUG },
    .{ "LOG_KERN", syslog_mod.genLOG_KERN },
    .{ "LOG_USER", syslog_mod.genLOG_USER },
    .{ "LOG_MAIL", syslog_mod.genLOG_MAIL },
    .{ "LOG_DAEMON", syslog_mod.genLOG_DAEMON },
    .{ "LOG_AUTH", syslog_mod.genLOG_AUTH },
    .{ "LOG_SYSLOG", syslog_mod.genLOG_SYSLOG },
    .{ "LOG_LPR", syslog_mod.genLOG_LPR },
    .{ "LOG_NEWS", syslog_mod.genLOG_NEWS },
    .{ "LOG_UUCP", syslog_mod.genLOG_UUCP },
    .{ "LOG_CRON", syslog_mod.genLOG_CRON },
    .{ "LOG_LOCAL0", syslog_mod.genLOG_LOCAL0 },
    .{ "LOG_LOCAL1", syslog_mod.genLOG_LOCAL1 },
    .{ "LOG_LOCAL2", syslog_mod.genLOG_LOCAL2 },
    .{ "LOG_LOCAL3", syslog_mod.genLOG_LOCAL3 },
    .{ "LOG_LOCAL4", syslog_mod.genLOG_LOCAL4 },
    .{ "LOG_LOCAL5", syslog_mod.genLOG_LOCAL5 },
    .{ "LOG_LOCAL6", syslog_mod.genLOG_LOCAL6 },
    .{ "LOG_LOCAL7", syslog_mod.genLOG_LOCAL7 },
    .{ "LOG_PID", syslog_mod.genLOG_PID },
    .{ "LOG_CONS", syslog_mod.genLOG_CONS },
    .{ "LOG_ODELAY", syslog_mod.genLOG_ODELAY },
    .{ "LOG_NDELAY", syslog_mod.genLOG_NDELAY },
    .{ "LOG_NOWAIT", syslog_mod.genLOG_NOWAIT },
    .{ "LOG_PERROR", syslog_mod.genLOG_PERROR },
    .{ "LOG_MASK", syslog_mod.genLOG_MASK },
    .{ "LOG_UPTO", syslog_mod.genLOG_UPTO },
});

/// curses module functions
const CursesFuncs = FuncMap.initComptime(.{
    .{ "initscr", curses_mod.genInitscr },
    .{ "endwin", curses_mod.genEndwin },
    .{ "newwin", curses_mod.genNewwin },
    .{ "newpad", curses_mod.genNewpad },
    .{ "cbreak", curses_mod.genCbreak },
    .{ "nocbreak", curses_mod.genNocbreak },
    .{ "echo", curses_mod.genEcho },
    .{ "noecho", curses_mod.genNoecho },
    .{ "raw", curses_mod.genRaw },
    .{ "noraw", curses_mod.genNoraw },
    .{ "start_color", curses_mod.genStart_color },
    .{ "has_colors", curses_mod.genHas_colors },
    .{ "can_change_color", curses_mod.genCan_change_color },
    .{ "init_pair", curses_mod.genInit_pair },
    .{ "init_color", curses_mod.genInit_color },
    .{ "color_pair", curses_mod.genColor_pair },
    .{ "pair_number", curses_mod.genPair_number },
    .{ "getch", curses_mod.genGetch },
    .{ "getkey", curses_mod.genGetkey },
    .{ "ungetch", curses_mod.genUngetch },
    .{ "getstr", curses_mod.genGetstr },
    .{ "addch", curses_mod.genAddch },
    .{ "addstr", curses_mod.genAddstr },
    .{ "addnstr", curses_mod.genAddnstr },
    .{ "mvaddch", curses_mod.genMvaddch },
    .{ "mvaddstr", curses_mod.genMvaddstr },
    .{ "move", curses_mod.genMove },
    .{ "refresh", curses_mod.genRefresh },
    .{ "clear", curses_mod.genClear },
    .{ "erase", curses_mod.genErase },
    .{ "clrtoeol", curses_mod.genClrtoeol },
    .{ "clrtobot", curses_mod.genClrtobot },
    .{ "curs_set", curses_mod.genCurs_set },
    .{ "getmaxyx", curses_mod.genGetmaxyx },
    .{ "getyx", curses_mod.genGetyx },
    .{ "LINES", curses_mod.genLINES },
    .{ "COLS", curses_mod.genCOLS },
    .{ "attron", curses_mod.genAttron },
    .{ "attroff", curses_mod.genAttroff },
    .{ "attrset", curses_mod.genAttrset },
    .{ "COLOR_BLACK", curses_mod.genCOLOR_BLACK },
    .{ "COLOR_RED", curses_mod.genCOLOR_RED },
    .{ "COLOR_GREEN", curses_mod.genCOLOR_GREEN },
    .{ "COLOR_YELLOW", curses_mod.genCOLOR_YELLOW },
    .{ "COLOR_BLUE", curses_mod.genCOLOR_BLUE },
    .{ "COLOR_MAGENTA", curses_mod.genCOLOR_MAGENTA },
    .{ "COLOR_CYAN", curses_mod.genCOLOR_CYAN },
    .{ "COLOR_WHITE", curses_mod.genCOLOR_WHITE },
    .{ "A_NORMAL", curses_mod.genA_NORMAL },
    .{ "A_STANDOUT", curses_mod.genA_STANDOUT },
    .{ "A_UNDERLINE", curses_mod.genA_UNDERLINE },
    .{ "A_REVERSE", curses_mod.genA_REVERSE },
    .{ "A_BLINK", curses_mod.genA_BLINK },
    .{ "A_DIM", curses_mod.genA_DIM },
    .{ "A_BOLD", curses_mod.genA_BOLD },
    .{ "A_PROTECT", curses_mod.genA_PROTECT },
    .{ "A_INVIS", curses_mod.genA_INVIS },
    .{ "A_ALTCHARSET", curses_mod.genA_ALTCHARSET },
    .{ "KEY_UP", curses_mod.genKEY_UP },
    .{ "KEY_DOWN", curses_mod.genKEY_DOWN },
    .{ "KEY_LEFT", curses_mod.genKEY_LEFT },
    .{ "KEY_RIGHT", curses_mod.genKEY_RIGHT },
    .{ "KEY_HOME", curses_mod.genKEY_HOME },
    .{ "KEY_END", curses_mod.genKEY_END },
    .{ "KEY_NPAGE", curses_mod.genKEY_NPAGE },
    .{ "KEY_PPAGE", curses_mod.genKEY_PPAGE },
    .{ "KEY_BACKSPACE", curses_mod.genKEY_BACKSPACE },
    .{ "KEY_DC", curses_mod.genKEY_DC },
    .{ "KEY_IC", curses_mod.genKEY_IC },
    .{ "KEY_ENTER", curses_mod.genKEY_ENTER },
    .{ "KEY_F1", curses_mod.genKEY_F1 },
    .{ "KEY_F2", curses_mod.genKEY_F2 },
    .{ "KEY_F3", curses_mod.genKEY_F3 },
    .{ "KEY_F4", curses_mod.genKEY_F4 },
    .{ "KEY_F5", curses_mod.genKEY_F5 },
    .{ "KEY_F6", curses_mod.genKEY_F6 },
    .{ "KEY_F7", curses_mod.genKEY_F7 },
    .{ "KEY_F8", curses_mod.genKEY_F8 },
    .{ "KEY_F9", curses_mod.genKEY_F9 },
    .{ "KEY_F10", curses_mod.genKEY_F10 },
    .{ "KEY_F11", curses_mod.genKEY_F11 },
    .{ "KEY_F12", curses_mod.genKEY_F12 },
    .{ "beep", curses_mod.genBeep },
    .{ "flash", curses_mod.genFlash },
    .{ "napms", curses_mod.genNapms },
    .{ "wrapper", curses_mod.genWrapper },
    .{ "use_default_colors", curses_mod.genUse_default_colors },
    .{ "keypad", curses_mod.genKeypad },
    .{ "nodelay", curses_mod.genNodelay },
    .{ "halfdelay", curses_mod.genHalfdelay },
    .{ "timeout", curses_mod.genTimeout },
});

/// bz2 module functions
const Bz2Funcs = FuncMap.initComptime(.{
    .{ "compress", bz2_mod.genCompress },
    .{ "decompress", bz2_mod.genDecompress },
    .{ "open", bz2_mod.genOpen },
    .{ "BZ2File", bz2_mod.genBZ2File },
    .{ "BZ2Compressor", bz2_mod.genBZ2Compressor },
    .{ "BZ2Decompressor", bz2_mod.genBZ2Decompressor },
});

/// lzma module functions
const LzmaFuncs = FuncMap.initComptime(.{
    .{ "compress", lzma_mod.genCompress },
    .{ "decompress", lzma_mod.genDecompress },
    .{ "open", lzma_mod.genOpen },
    .{ "LZMAFile", lzma_mod.genLZMAFile },
    .{ "LZMACompressor", lzma_mod.genLZMACompressor },
    .{ "LZMADecompressor", lzma_mod.genLZMADecompressor },
    .{ "is_check_supported", lzma_mod.genIs_check_supported },
    .{ "FORMAT_AUTO", lzma_mod.genFORMAT_AUTO },
    .{ "FORMAT_XZ", lzma_mod.genFORMAT_XZ },
    .{ "FORMAT_ALONE", lzma_mod.genFORMAT_ALONE },
    .{ "FORMAT_RAW", lzma_mod.genFORMAT_RAW },
    .{ "CHECK_NONE", lzma_mod.genCHECK_NONE },
    .{ "CHECK_CRC32", lzma_mod.genCHECK_CRC32 },
    .{ "CHECK_CRC64", lzma_mod.genCHECK_CRC64 },
    .{ "CHECK_SHA256", lzma_mod.genCHECK_SHA256 },
    .{ "CHECK_ID_MAX", lzma_mod.genCHECK_ID_MAX },
    .{ "CHECK_UNKNOWN", lzma_mod.genCHECK_UNKNOWN },
    .{ "PRESET_DEFAULT", lzma_mod.genPRESET_DEFAULT },
    .{ "PRESET_EXTREME", lzma_mod.genPRESET_EXTREME },
    .{ "FILTER_LZMA1", lzma_mod.genFILTER_LZMA1 },
    .{ "FILTER_LZMA2", lzma_mod.genFILTER_LZMA2 },
    .{ "FILTER_DELTA", lzma_mod.genFILTER_DELTA },
    .{ "FILTER_X86", lzma_mod.genFILTER_X86 },
    .{ "FILTER_ARM", lzma_mod.genFILTER_ARM },
    .{ "FILTER_ARMTHUMB", lzma_mod.genFILTER_ARMTHUMB },
    .{ "FILTER_SPARC", lzma_mod.genFILTER_SPARC },
});

/// tarfile module functions
const TarfileFuncs = FuncMap.initComptime(.{
    .{ "open", tarfile_mod.genOpen },
    .{ "is_tarfile", tarfile_mod.genIs_tarfile },
    .{ "TarFile", tarfile_mod.genTarFile },
    .{ "TarInfo", tarfile_mod.genTarInfo },
    .{ "REGTYPE", tarfile_mod.genREGTYPE },
    .{ "AREGTYPE", tarfile_mod.genAREGTYPE },
    .{ "LNKTYPE", tarfile_mod.genLNKTYPE },
    .{ "SYMTYPE", tarfile_mod.genSYMTYPE },
    .{ "CHRTYPE", tarfile_mod.genCHRTYPE },
    .{ "BLKTYPE", tarfile_mod.genBLKTYPE },
    .{ "DIRTYPE", tarfile_mod.genDIRTYPE },
    .{ "FIFOTYPE", tarfile_mod.genFIFOTYPE },
    .{ "CONTTYPE", tarfile_mod.genCONTTYPE },
    .{ "GNUTYPE_LONGNAME", tarfile_mod.genGNUTYPE_LONGNAME },
    .{ "GNUTYPE_LONGLINK", tarfile_mod.genGNUTYPE_LONGLINK },
    .{ "GNUTYPE_SPARSE", tarfile_mod.genGNUTYPE_SPARSE },
    .{ "USTAR_FORMAT", tarfile_mod.genUSTAR_FORMAT },
    .{ "GNU_FORMAT", tarfile_mod.genGNU_FORMAT },
    .{ "PAX_FORMAT", tarfile_mod.genPAX_FORMAT },
    .{ "DEFAULT_FORMAT", tarfile_mod.genDEFAULT_FORMAT },
    .{ "BLOCKSIZE", tarfile_mod.genBLOCKSIZE },
    .{ "RECORDSIZE", tarfile_mod.genRECORDSIZE },
    .{ "ENCODING", tarfile_mod.genENCODING },
});

/// shlex module functions
const ShlexFuncs = FuncMap.initComptime(.{
    .{ "split", shlex_mod.genSplit },
    .{ "join", shlex_mod.genJoin },
    .{ "quote", shlex_mod.genQuote },
    .{ "shlex", shlex_mod.genShlex },
});

/// gettext module functions
const GettextFuncs = FuncMap.initComptime(.{
    .{ "gettext", gettext_mod.genGettext },
    .{ "ngettext", gettext_mod.genNgettext },
    .{ "pgettext", gettext_mod.genPgettext },
    .{ "npgettext", gettext_mod.genNpgettext },
    .{ "dgettext", gettext_mod.genDgettext },
    .{ "dngettext", gettext_mod.genDngettext },
    .{ "bindtextdomain", gettext_mod.genBindtextdomain },
    .{ "textdomain", gettext_mod.genTextdomain },
    .{ "install", gettext_mod.genInstall },
    .{ "translation", gettext_mod.genTranslation },
    .{ "find", gettext_mod.genFind },
    .{ "GNUTranslations", gettext_mod.genGNUTranslations },
    .{ "NullTranslations", gettext_mod.genNullTranslations },
});

/// calendar module functions
const CalendarFuncs = FuncMap.initComptime(.{
    .{ "isleap", calendar_mod.genIsleap },
    .{ "leapdays", calendar_mod.genLeapdays },
    .{ "weekday", calendar_mod.genWeekday },
    .{ "monthrange", calendar_mod.genMonthrange },
    .{ "month", calendar_mod.genMonth },
    .{ "monthcalendar", calendar_mod.genMonthcalendar },
    .{ "prmonth", calendar_mod.genPrmonth },
    .{ "calendar", calendar_mod.genCalendar },
    .{ "prcal", calendar_mod.genPrcal },
    .{ "setfirstweekday", calendar_mod.genSetfirstweekday },
    .{ "firstweekday", calendar_mod.genFirstweekday },
    .{ "timegm", calendar_mod.genTimegm },
    .{ "Calendar", calendar_mod.genCalendarClass },
    .{ "TextCalendar", calendar_mod.genTextCalendar },
    .{ "HTMLCalendar", calendar_mod.genHTMLCalendar },
    .{ "LocaleTextCalendar", calendar_mod.genLocaleTextCalendar },
    .{ "LocaleHTMLCalendar", calendar_mod.genLocaleHTMLCalendar },
    .{ "MONDAY", calendar_mod.genMONDAY },
    .{ "TUESDAY", calendar_mod.genTUESDAY },
    .{ "WEDNESDAY", calendar_mod.genWEDNESDAY },
    .{ "THURSDAY", calendar_mod.genTHURSDAY },
    .{ "FRIDAY", calendar_mod.genFRIDAY },
    .{ "SATURDAY", calendar_mod.genSATURDAY },
    .{ "SUNDAY", calendar_mod.genSUNDAY },
    .{ "day_name", calendar_mod.genDay_name },
    .{ "day_abbr", calendar_mod.genDay_abbr },
    .{ "month_name", calendar_mod.genMonth_name },
    .{ "month_abbr", calendar_mod.genMonth_abbr },
    .{ "IllegalMonthError", calendar_mod.genIllegalMonthError },
    .{ "IllegalWeekdayError", calendar_mod.genIllegalWeekdayError },
});

/// cmd module functions
const CmdFuncs = FuncMap.initComptime(.{
    .{ "Cmd", cmd_mod.genCmd },
});

/// code module functions
const CodeFuncs = FuncMap.initComptime(.{
    .{ "InteractiveConsole", code_mod.genInteractiveConsole },
    .{ "InteractiveInterpreter", code_mod.genInteractiveInterpreter },
    .{ "compile_command", code_mod.genCompile_command },
    .{ "interact", code_mod.genInteract },
});

/// codeop module functions
const CodeopFuncs = FuncMap.initComptime(.{
    .{ "compile_command", codeop_mod.genCompile_command },
    .{ "Compile", codeop_mod.genCompile },
    .{ "CommandCompiler", codeop_mod.genCommandCompiler },
    .{ "PyCF_DONT_IMPLY_DEDENT", codeop_mod.genPyCF_DONT_IMPLY_DEDENT },
    .{ "PyCF_ALLOW_INCOMPLETE_INPUT", codeop_mod.genPyCF_ALLOW_INCOMPLETE_INPUT },
});

/// dis module functions
const DisFuncs = FuncMap.initComptime(.{
    .{ "dis", dis_mod.genDis },
    .{ "disassemble", dis_mod.genDisassemble },
    .{ "distb", dis_mod.genDistb },
    .{ "disco", dis_mod.genDisco },
    .{ "code_info", dis_mod.genCode_info },
    .{ "show_code", dis_mod.genShow_code },
    .{ "get_instructions", dis_mod.genGet_instructions },
    .{ "findlinestarts", dis_mod.genFindlinestarts },
    .{ "findlabels", dis_mod.genFindlabels },
    .{ "stack_effect", dis_mod.genStack_effect },
    .{ "Bytecode", dis_mod.genBytecode },
    .{ "Instruction", dis_mod.genInstruction },
    .{ "HAVE_ARGUMENT", dis_mod.genHAVE_ARGUMENT },
    .{ "EXTENDED_ARG", dis_mod.genEXTENDED_ARG },
});

/// gc module functions
const GcFuncs = FuncMap.initComptime(.{
    .{ "enable", gc_mod.genEnable },
    .{ "disable", gc_mod.genDisable },
    .{ "isenabled", gc_mod.genIsenabled },
    .{ "collect", gc_mod.genCollect },
    .{ "set_debug", gc_mod.genSet_debug },
    .{ "get_debug", gc_mod.genGet_debug },
    .{ "get_stats", gc_mod.genGet_stats },
    .{ "set_threshold", gc_mod.genSet_threshold },
    .{ "get_threshold", gc_mod.genGet_threshold },
    .{ "get_count", gc_mod.genGet_count },
    .{ "get_objects", gc_mod.genGet_objects },
    .{ "get_referrers", gc_mod.genGet_referrers },
    .{ "get_referents", gc_mod.genGet_referents },
    .{ "is_tracked", gc_mod.genIs_tracked },
    .{ "is_finalized", gc_mod.genIs_finalized },
    .{ "freeze", gc_mod.genFreeze },
    .{ "unfreeze", gc_mod.genUnfreeze },
    .{ "get_freeze_count", gc_mod.genGet_freeze_count },
    .{ "garbage", gc_mod.genGarbage },
    .{ "callbacks", gc_mod.genCallbacks },
    .{ "DEBUG_STATS", gc_mod.genDEBUG_STATS },
    .{ "DEBUG_COLLECTABLE", gc_mod.genDEBUG_COLLECTABLE },
    .{ "DEBUG_UNCOLLECTABLE", gc_mod.genDEBUG_UNCOLLECTABLE },
    .{ "DEBUG_SAVEALL", gc_mod.genDEBUG_SAVEALL },
    .{ "DEBUG_LEAK", gc_mod.genDEBUG_LEAK },
});

/// ast module functions
const AstFuncs = FuncMap.initComptime(.{
    .{ "parse", ast_module.genParse },
    .{ "literal_eval", ast_module.genLiteral_eval },
    .{ "dump", ast_module.genDump },
    .{ "unparse", ast_module.genUnparse },
    .{ "fix_missing_locations", ast_module.genFix_missing_locations },
    .{ "increment_lineno", ast_module.genIncrement_lineno },
    .{ "copy_location", ast_module.genCopy_location },
    .{ "iter_fields", ast_module.genIter_fields },
    .{ "iter_child_nodes", ast_module.genIter_child_nodes },
    .{ "walk", ast_module.genWalk },
    .{ "get_docstring", ast_module.genGet_docstring },
    .{ "get_source_segment", ast_module.genGet_source_segment },
    .{ "AST", ast_module.genAST },
    .{ "Module", ast_module.genModule },
    .{ "Expression", ast_module.genExpression },
    .{ "Interactive", ast_module.genInteractive },
    .{ "FunctionDef", ast_module.genFunctionDef },
    .{ "AsyncFunctionDef", ast_module.genAsyncFunctionDef },
    .{ "ClassDef", ast_module.genClassDef },
    .{ "Return", ast_module.genReturn },
    .{ "Name", ast_module.genName },
    .{ "Constant", ast_module.genConstant },
    .{ "NodeVisitor", ast_module.genNodeVisitor },
    .{ "NodeTransformer", ast_module.genNodeTransformer },
    .{ "PyCF_ONLY_AST", ast_module.genPyCF_ONLY_AST },
    .{ "PyCF_TYPE_COMMENTS", ast_module.genPyCF_TYPE_COMMENTS },
});

/// unittest.mock module functions
const UnittestMockFuncs = FuncMap.initComptime(.{
    .{ "Mock", unittest_mock_mod.genMock },
    .{ "MagicMock", unittest_mock_mod.genMagicMock },
    .{ "AsyncMock", unittest_mock_mod.genAsyncMock },
    .{ "NonCallableMock", unittest_mock_mod.genNonCallableMock },
    .{ "NonCallableMagicMock", unittest_mock_mod.genNonCallableMagicMock },
    .{ "patch", unittest_mock_mod.genPatch },
    .{ "patch.object", unittest_mock_mod.genPatch_object },
    .{ "patch.dict", unittest_mock_mod.genPatch_dict },
    .{ "patch.multiple", unittest_mock_mod.genPatch_multiple },
    .{ "create_autospec", unittest_mock_mod.genCreate_autospec },
    .{ "call", unittest_mock_mod.genCall },
    .{ "ANY", unittest_mock_mod.genANY },
    .{ "FILTER_DIR", unittest_mock_mod.genFILTER_DIR },
    .{ "sentinel", unittest_mock_mod.genSentinel },
    .{ "DEFAULT", unittest_mock_mod.genDEFAULT },
    .{ "seal", unittest_mock_mod.genSeal },
    .{ "PropertyMock", unittest_mock_mod.genPropertyMock },
});

/// doctest module functions
const DoctestFuncs = FuncMap.initComptime(.{
    .{ "testmod", doctest_mod.genTestmod },
    .{ "testfile", doctest_mod.genTestfile },
    .{ "run_docstring_examples", doctest_mod.genRun_docstring_examples },
    .{ "DocTestSuite", doctest_mod.genDocTestSuite },
    .{ "DocFileSuite", doctest_mod.genDocFileSuite },
    .{ "DocTestParser", doctest_mod.genDocTestParser },
    .{ "DocTestRunner", doctest_mod.genDocTestRunner },
    .{ "DocTestFinder", doctest_mod.genDocTestFinder },
    .{ "DocTest", doctest_mod.genDocTest },
    .{ "Example", doctest_mod.genExample },
    .{ "OutputChecker", doctest_mod.genOutputChecker },
    .{ "DebugRunner", doctest_mod.genDebugRunner },
    .{ "OPTIONFLAGS", doctest_mod.genOPTIONFLAGS },
    .{ "ELLIPSIS", doctest_mod.genELLIPSIS },
    .{ "NORMALIZE_WHITESPACE", doctest_mod.genNORMALIZE_WHITESPACE },
    .{ "DONT_ACCEPT_TRUE_FOR_1", doctest_mod.genDONT_ACCEPT_TRUE_FOR_1 },
    .{ "DONT_ACCEPT_BLANKLINE", doctest_mod.genDONT_ACCEPT_BLANKLINE },
    .{ "SKIP", doctest_mod.genSKIP },
    .{ "IGNORE_EXCEPTION_DETAIL", doctest_mod.genIGNORE_EXCEPTION_DETAIL },
    .{ "REPORT_UDIFF", doctest_mod.genREPORT_UDIFF },
    .{ "REPORT_CDIFF", doctest_mod.genREPORT_CDIFF },
    .{ "REPORT_NDIFF", doctest_mod.genREPORT_NDIFF },
    .{ "REPORT_ONLY_FIRST_FAILURE", doctest_mod.genREPORT_ONLY_FIRST_FAILURE },
    .{ "FAIL_FAST", doctest_mod.genFAIL_FAST },
});

/// profile module functions
const ProfileFuncs = FuncMap.initComptime(.{
    .{ "Profile", profile_mod.genProfile },
    .{ "run", profile_mod.genRun },
    .{ "runctx", profile_mod.genRunctx },
});

/// cProfile module functions (same as profile)
const CProfileFuncs = FuncMap.initComptime(.{
    .{ "Profile", profile_mod.genCProfile },
    .{ "run", profile_mod.genRun },
    .{ "runctx", profile_mod.genRunctx },
});

/// pdb module functions
const PdbFuncs = FuncMap.initComptime(.{
    .{ "Pdb", pdb_mod.genPdb },
    .{ "run", pdb_mod.genRun },
    .{ "runeval", pdb_mod.genRuneval },
    .{ "runcall", pdb_mod.genRuncall },
    .{ "set_trace", pdb_mod.genSet_trace },
    .{ "post_mortem", pdb_mod.genPost_mortem },
    .{ "pm", pdb_mod.genPm },
    .{ "help", pdb_mod.genHelp },
    .{ "Breakpoint", pdb_mod.genBreakpoint },
});

/// timeit module functions
const TimeitFuncs = FuncMap.initComptime(.{
    .{ "timeit", timeit_mod.genTimeit },
    .{ "repeat", timeit_mod.genRepeat },
    .{ "default_timer", timeit_mod.genDefault_timer },
    .{ "Timer", timeit_mod.genTimer },
});

/// trace module functions
const TraceFuncs = FuncMap.initComptime(.{
    .{ "Trace", trace_mod.genTrace },
    .{ "CoverageResults", trace_mod.genCoverageResults },
});

/// binascii module functions
const BinasciiFuncs = FuncMap.initComptime(.{
    .{ "hexlify", binascii_mod.genHexlify },
    .{ "unhexlify", binascii_mod.genUnhexlify },
    .{ "b2a_hex", binascii_mod.genB2a_hex },
    .{ "a2b_hex", binascii_mod.genA2b_hex },
    .{ "b2a_base64", binascii_mod.genB2a_base64 },
    .{ "a2b_base64", binascii_mod.genA2b_base64 },
    .{ "b2a_uu", binascii_mod.genB2a_uu },
    .{ "a2b_uu", binascii_mod.genA2b_uu },
    .{ "b2a_qp", binascii_mod.genB2a_qp },
    .{ "a2b_qp", binascii_mod.genA2b_qp },
    .{ "crc32", binascii_mod.genCrc32 },
    .{ "crc_hqx", binascii_mod.genCrc_hqx },
    .{ "Error", binascii_mod.genError },
    .{ "Incomplete", binascii_mod.genIncomplete },
});

/// smtplib module functions
const SmtplibFuncs = FuncMap.initComptime(.{
    .{ "SMTP", smtplib_mod.genSMTP },
    .{ "SMTP_SSL", smtplib_mod.genSMTP_SSL },
    .{ "LMTP", smtplib_mod.genLMTP },
    .{ "SMTP_PORT", smtplib_mod.genSMTP_PORT },
    .{ "SMTP_SSL_PORT", smtplib_mod.genSMTP_SSL_PORT },
    .{ "SMTPException", smtplib_mod.genSMTPException },
    .{ "SMTPServerDisconnected", smtplib_mod.genSMTPServerDisconnected },
    .{ "SMTPResponseException", smtplib_mod.genSMTPResponseException },
    .{ "SMTPSenderRefused", smtplib_mod.genSMTPSenderRefused },
    .{ "SMTPRecipientsRefused", smtplib_mod.genSMTPRecipientsRefused },
    .{ "SMTPDataError", smtplib_mod.genSMTPDataError },
    .{ "SMTPConnectError", smtplib_mod.genSMTPConnectError },
    .{ "SMTPHeloError", smtplib_mod.genSMTPHeloError },
    .{ "SMTPAuthenticationError", smtplib_mod.genSMTPAuthenticationError },
    .{ "SMTPNotSupportedError", smtplib_mod.genSMTPNotSupportedError },
});

/// imaplib module functions
const ImaplibFuncs = FuncMap.initComptime(.{
    .{ "IMAP4", imaplib_mod.genIMAP4 },
    .{ "IMAP4_SSL", imaplib_mod.genIMAP4_SSL },
    .{ "IMAP4_stream", imaplib_mod.genIMAP4_stream },
    .{ "IMAP4_PORT", imaplib_mod.genIMAP4_PORT },
    .{ "IMAP4_SSL_PORT", imaplib_mod.genIMAP4_SSL_PORT },
    .{ "Commands", imaplib_mod.genCommands },
    .{ "IMAP4.error", imaplib_mod.genIMAP4_error },
    .{ "IMAP4.abort", imaplib_mod.genIMAP4_abort },
    .{ "IMAP4.readonly", imaplib_mod.genIMAP4_readonly },
    .{ "Internaldate2tuple", imaplib_mod.genInternaldate2tuple },
    .{ "Int2AP", imaplib_mod.genInt2AP },
    .{ "ParseFlags", imaplib_mod.genParseFlags },
    .{ "Time2Internaldate", imaplib_mod.genTime2Internaldate },
});

/// ftplib module functions
const FtplibFuncs = FuncMap.initComptime(.{
    .{ "FTP", ftplib_mod.genFTP },
    .{ "FTP_TLS", ftplib_mod.genFTP_TLS },
    .{ "FTP_PORT", ftplib_mod.genFTP_PORT },
    .{ "error", ftplib_mod.genError },
    .{ "error_reply", ftplib_mod.genError_reply },
    .{ "error_temp", ftplib_mod.genError_temp },
    .{ "error_perm", ftplib_mod.genError_perm },
    .{ "error_proto", ftplib_mod.genError_proto },
    .{ "all_errors", ftplib_mod.genAll_errors },
});

/// poplib module functions
const PoplibFuncs = FuncMap.initComptime(.{
    .{ "POP3", poplib_mod.genPOP3 },
    .{ "POP3_SSL", poplib_mod.genPOP3_SSL },
    .{ "POP3_PORT", poplib_mod.genPOP3_PORT },
    .{ "POP3_SSL_PORT", poplib_mod.genPOP3_SSL_PORT },
    .{ "error_proto", poplib_mod.genError_proto },
});

/// nntplib module functions
const NntplibFuncs = FuncMap.initComptime(.{
    .{ "NNTP", nntplib_mod.genNNTP },
    .{ "NNTP_SSL", nntplib_mod.genNNTP_SSL },
    .{ "NNTP_PORT", nntplib_mod.genNNTP_PORT },
    .{ "NNTP_SSL_PORT", nntplib_mod.genNNTP_SSL_PORT },
    .{ "NNTPError", nntplib_mod.genNNTPError },
    .{ "NNTPReplyError", nntplib_mod.genNNTPReplyError },
    .{ "NNTPTemporaryError", nntplib_mod.genNNTPTemporaryError },
    .{ "NNTPPermanentError", nntplib_mod.genNNTPPermanentError },
    .{ "NNTPProtocolError", nntplib_mod.genNNTPProtocolError },
    .{ "NNTPDataError", nntplib_mod.genNNTPDataError },
    .{ "GroupInfo", nntplib_mod.genGroupInfo },
    .{ "ArticleInfo", nntplib_mod.genArticleInfo },
    .{ "decode_header", nntplib_mod.genDecode_header },
});

/// ssl module functions
const SslFuncs = FuncMap.initComptime(.{
    .{ "SSLContext", ssl_mod.genSSLContext },
    .{ "create_default_context", ssl_mod.genCreate_default_context },
    .{ "wrap_socket", ssl_mod.genWrap_socket },
    .{ "get_default_verify_paths", ssl_mod.genGet_default_verify_paths },
    .{ "cert_time_to_seconds", ssl_mod.genCert_time_to_seconds },
    .{ "get_server_certificate", ssl_mod.genGet_server_certificate },
    .{ "DER_cert_to_PEM_cert", ssl_mod.genDER_cert_to_PEM_cert },
    .{ "PEM_cert_to_DER_cert", ssl_mod.genPEM_cert_to_DER_cert },
    .{ "match_hostname", ssl_mod.genMatch_hostname },
    .{ "RAND_status", ssl_mod.genRAND_status },
    .{ "RAND_add", ssl_mod.genRAND_add },
    .{ "RAND_bytes", ssl_mod.genRAND_bytes },
    .{ "RAND_pseudo_bytes", ssl_mod.genRAND_pseudo_bytes },
    .{ "PROTOCOL_SSLv23", ssl_mod.genPROTOCOL_SSLv23 },
    .{ "PROTOCOL_TLS", ssl_mod.genPROTOCOL_TLS },
    .{ "PROTOCOL_TLS_CLIENT", ssl_mod.genPROTOCOL_TLS_CLIENT },
    .{ "PROTOCOL_TLS_SERVER", ssl_mod.genPROTOCOL_TLS_SERVER },
    .{ "CERT_NONE", ssl_mod.genCERT_NONE },
    .{ "CERT_OPTIONAL", ssl_mod.genCERT_OPTIONAL },
    .{ "CERT_REQUIRED", ssl_mod.genCERT_REQUIRED },
    .{ "OP_ALL", ssl_mod.genOP_ALL },
    .{ "OP_NO_SSLv2", ssl_mod.genOP_NO_SSLv2 },
    .{ "OP_NO_SSLv3", ssl_mod.genOP_NO_SSLv3 },
    .{ "OP_NO_TLSv1", ssl_mod.genOP_NO_TLSv1 },
    .{ "OP_NO_TLSv1_1", ssl_mod.genOP_NO_TLSv1_1 },
    .{ "OP_NO_TLSv1_2", ssl_mod.genOP_NO_TLSv1_2 },
    .{ "OP_NO_TLSv1_3", ssl_mod.genOP_NO_TLSv1_3 },
    .{ "SSLError", ssl_mod.genSSLError },
    .{ "SSLZeroReturnError", ssl_mod.genSSLZeroReturnError },
    .{ "SSLWantReadError", ssl_mod.genSSLWantReadError },
    .{ "SSLWantWriteError", ssl_mod.genSSLWantWriteError },
    .{ "SSLSyscallError", ssl_mod.genSSLSyscallError },
    .{ "SSLEOFError", ssl_mod.genSSLEOFError },
    .{ "SSLCertVerificationError", ssl_mod.genSSLCertVerificationError },
    .{ "Purpose.SERVER_AUTH", ssl_mod.genPurpose_SERVER_AUTH },
    .{ "Purpose.CLIENT_AUTH", ssl_mod.genPurpose_CLIENT_AUTH },
    .{ "OPENSSL_VERSION", ssl_mod.genOPENSSL_VERSION },
    .{ "OPENSSL_VERSION_INFO", ssl_mod.genOPENSSL_VERSION_INFO },
    .{ "OPENSSL_VERSION_NUMBER", ssl_mod.genOPENSSL_VERSION_NUMBER },
    .{ "HAS_SNI", ssl_mod.genHAS_SNI },
    .{ "HAS_ALPN", ssl_mod.genHAS_ALPN },
    .{ "HAS_ECDH", ssl_mod.genHAS_ECDH },
    .{ "HAS_TLSv1_3", ssl_mod.genHAS_TLSv1_3 },
});

/// selectors module functions
const SelectorsFuncs = FuncMap.initComptime(.{
    .{ "DefaultSelector", selectors_mod.genDefaultSelector },
    .{ "SelectSelector", selectors_mod.genSelectSelector },
    .{ "PollSelector", selectors_mod.genPollSelector },
    .{ "EpollSelector", selectors_mod.genEpollSelector },
    .{ "DevpollSelector", selectors_mod.genDevpollSelector },
    .{ "KqueueSelector", selectors_mod.genKqueueSelector },
    .{ "BaseSelector", selectors_mod.genBaseSelector },
    .{ "SelectorKey", selectors_mod.genSelectorKey },
    .{ "EVENT_READ", selectors_mod.genEVENT_READ },
    .{ "EVENT_WRITE", selectors_mod.genEVENT_WRITE },
});

/// ipaddress module functions
const IpaddressFuncs = FuncMap.initComptime(.{
    .{ "ip_address", ipaddress_mod.genIp_address },
    .{ "ip_network", ipaddress_mod.genIp_network },
    .{ "ip_interface", ipaddress_mod.genIp_interface },
    .{ "IPv4Address", ipaddress_mod.genIPv4Address },
    .{ "IPv4Network", ipaddress_mod.genIPv4Network },
    .{ "IPv4Interface", ipaddress_mod.genIPv4Interface },
    .{ "IPv6Address", ipaddress_mod.genIPv6Address },
    .{ "IPv6Network", ipaddress_mod.genIPv6Network },
    .{ "IPv6Interface", ipaddress_mod.genIPv6Interface },
    .{ "v4_int_to_packed", ipaddress_mod.genV4_int_to_packed },
    .{ "v6_int_to_packed", ipaddress_mod.genV6_int_to_packed },
    .{ "summarize_address_range", ipaddress_mod.genSummarize_address_range },
    .{ "collapse_addresses", ipaddress_mod.genCollapse_addresses },
    .{ "get_mixed_type_key", ipaddress_mod.genGet_mixed_type_key },
    .{ "AddressValueError", ipaddress_mod.genAddressValueError },
    .{ "NetmaskValueError", ipaddress_mod.genNetmaskValueError },
});

/// telnetlib module functions
const TelnetlibFuncs = FuncMap.initComptime(.{
    .{ "Telnet", telnetlib_mod.genTelnet },
    .{ "THEOPT", telnetlib_mod.genTHEOPT },
    .{ "SE", telnetlib_mod.genSE },
    .{ "NOP", telnetlib_mod.genNOP },
    .{ "DM", telnetlib_mod.genDM },
    .{ "BRK", telnetlib_mod.genBRK },
    .{ "IP", telnetlib_mod.genIP },
    .{ "AO", telnetlib_mod.genAO },
    .{ "AYT", telnetlib_mod.genAYT },
    .{ "EC", telnetlib_mod.genEC },
    .{ "EL", telnetlib_mod.genEL },
    .{ "GA", telnetlib_mod.genGA },
    .{ "SB", telnetlib_mod.genSB },
    .{ "WILL", telnetlib_mod.genWILL },
    .{ "WONT", telnetlib_mod.genWONT },
    .{ "DO", telnetlib_mod.genDO },
    .{ "DONT", telnetlib_mod.genDONT },
    .{ "IAC", telnetlib_mod.genIAC },
    .{ "ECHO", telnetlib_mod.genECHO },
    .{ "SGA", telnetlib_mod.genSGA },
    .{ "TTYPE", telnetlib_mod.genTTYPE },
    .{ "NAWS", telnetlib_mod.genNAWS },
    .{ "LINEMODE", telnetlib_mod.genLINEMODE },
    .{ "NEW_ENVIRON", telnetlib_mod.genNEW_ENVIRON },
    .{ "XDISPLOC", telnetlib_mod.genXDISPLOC },
    .{ "AUTHENTICATION", telnetlib_mod.genAUTHENTICATION },
    .{ "ENCRYPT", telnetlib_mod.genENCRYPT },
    .{ "TELNET_PORT", telnetlib_mod.genTELNET_PORT },
});

/// xmlrpc.client module functions
const XmlrpcClientFuncs = FuncMap.initComptime(.{
    .{ "ServerProxy", xmlrpc_mod.genServerProxy },
    .{ "Transport", xmlrpc_mod.genTransport },
    .{ "SafeTransport", xmlrpc_mod.genSafeTransport },
    .{ "dumps", xmlrpc_mod.genDumps },
    .{ "loads", xmlrpc_mod.genLoads },
    .{ "gzip_encode", xmlrpc_mod.genGzip_encode },
    .{ "gzip_decode", xmlrpc_mod.genGzip_decode },
    .{ "Fault", xmlrpc_mod.genFault },
    .{ "ProtocolError", xmlrpc_mod.genProtocolError },
    .{ "ResponseError", xmlrpc_mod.genResponseError },
    .{ "Boolean", xmlrpc_mod.genBoolean },
    .{ "DateTime", xmlrpc_mod.genDateTime },
    .{ "Binary", xmlrpc_mod.genBinary },
    .{ "MAXINT", xmlrpc_mod.genMAXINT },
    .{ "MININT", xmlrpc_mod.genMININT },
});

/// xmlrpc.server module functions
const XmlrpcServerFuncs = FuncMap.initComptime(.{
    .{ "SimpleXMLRPCServer", xmlrpc_mod.genSimpleXMLRPCServer },
    .{ "CGIXMLRPCRequestHandler", xmlrpc_mod.genCGIXMLRPCRequestHandler },
    .{ "SimpleXMLRPCRequestHandler", xmlrpc_mod.genSimpleXMLRPCRequestHandler },
    .{ "DocXMLRPCServer", xmlrpc_mod.genDocXMLRPCServer },
    .{ "DocCGIXMLRPCRequestHandler", xmlrpc_mod.genDocCGIXMLRPCRequestHandler },
});

/// http.cookiejar module functions
const HttpCookiejarFuncs = FuncMap.initComptime(.{
    .{ "CookieJar", http_cookiejar_mod.genCookieJar },
    .{ "FileCookieJar", http_cookiejar_mod.genFileCookieJar },
    .{ "MozillaCookieJar", http_cookiejar_mod.genMozillaCookieJar },
    .{ "LWPCookieJar", http_cookiejar_mod.genLWPCookieJar },
    .{ "Cookie", http_cookiejar_mod.genCookie },
    .{ "DefaultCookiePolicy", http_cookiejar_mod.genDefaultCookiePolicy },
    .{ "BlockingPolicy", http_cookiejar_mod.genBlockingPolicy },
    .{ "BlockAllCookies", http_cookiejar_mod.genBlockAllCookies },
    .{ "DomainStrictNoDots", http_cookiejar_mod.genDomainStrictNoDots },
    .{ "DomainStrictNonDomain", http_cookiejar_mod.genDomainStrictNonDomain },
    .{ "DomainRFC2965Match", http_cookiejar_mod.genDomainRFC2965Match },
    .{ "DomainLiberal", http_cookiejar_mod.genDomainLiberal },
    .{ "DomainStrict", http_cookiejar_mod.genDomainStrict },
    .{ "LoadError", http_cookiejar_mod.genLoadError },
    .{ "time2isoz", http_cookiejar_mod.genTime2isoz },
    .{ "time2netscape", http_cookiejar_mod.genTime2netscape },
});

/// urllib.request module functions
const UrllibRequestFuncs = FuncMap.initComptime(.{
    .{ "urlopen", urllib_request_mod.genUrlopen },
    .{ "install_opener", urllib_request_mod.genInstall_opener },
    .{ "build_opener", urllib_request_mod.genBuild_opener },
    .{ "pathname2url", urllib_request_mod.genPathname2url },
    .{ "url2pathname", urllib_request_mod.genUrl2pathname },
    .{ "getproxies", urllib_request_mod.genGetproxies },
    .{ "Request", urllib_request_mod.genRequest },
    .{ "OpenerDirector", urllib_request_mod.genOpenerDirector },
    .{ "BaseHandler", urllib_request_mod.genBaseHandler },
    .{ "HTTPDefaultErrorHandler", urllib_request_mod.genHTTPDefaultErrorHandler },
    .{ "HTTPRedirectHandler", urllib_request_mod.genHTTPRedirectHandler },
    .{ "HTTPCookieProcessor", urllib_request_mod.genHTTPCookieProcessor },
    .{ "ProxyHandler", urllib_request_mod.genProxyHandler },
    .{ "HTTPPasswordMgr", urllib_request_mod.genHTTPPasswordMgr },
    .{ "HTTPPasswordMgrWithDefaultRealm", urllib_request_mod.genHTTPPasswordMgrWithDefaultRealm },
    .{ "HTTPPasswordMgrWithPriorAuth", urllib_request_mod.genHTTPPasswordMgrWithPriorAuth },
    .{ "AbstractBasicAuthHandler", urllib_request_mod.genAbstractBasicAuthHandler },
    .{ "HTTPBasicAuthHandler", urllib_request_mod.genHTTPBasicAuthHandler },
    .{ "ProxyBasicAuthHandler", urllib_request_mod.genProxyBasicAuthHandler },
    .{ "AbstractDigestAuthHandler", urllib_request_mod.genAbstractDigestAuthHandler },
    .{ "HTTPDigestAuthHandler", urllib_request_mod.genHTTPDigestAuthHandler },
    .{ "ProxyDigestAuthHandler", urllib_request_mod.genProxyDigestAuthHandler },
    .{ "HTTPHandler", urllib_request_mod.genHTTPHandler },
    .{ "HTTPSHandler", urllib_request_mod.genHTTPSHandler },
    .{ "FileHandler", urllib_request_mod.genFileHandler },
    .{ "FTPHandler", urllib_request_mod.genFTPHandler },
    .{ "CacheFTPHandler", urllib_request_mod.genCacheFTPHandler },
    .{ "DataHandler", urllib_request_mod.genDataHandler },
    .{ "UnknownHandler", urllib_request_mod.genUnknownHandler },
    .{ "HTTPErrorProcessor", urllib_request_mod.genHTTPErrorProcessor },
    .{ "URLError", urllib_request_mod.genURLError },
    .{ "HTTPError", urllib_request_mod.genHTTPError },
    .{ "ContentTooShortError", urllib_request_mod.genContentTooShortError },
});

/// urllib.error module functions
const UrllibErrorFuncs = FuncMap.initComptime(.{
    .{ "URLError", urllib_error_mod.genURLError },
    .{ "HTTPError", urllib_error_mod.genHTTPError },
    .{ "ContentTooShortError", urllib_error_mod.genContentTooShortError },
});

/// urllib.robotparser module functions
const UrllibRobotparserFuncs = FuncMap.initComptime(.{
    .{ "RobotFileParser", urllib_robotparser_mod.genRobotFileParser },
});

/// cgi module functions
const CgiFuncs = FuncMap.initComptime(.{
    .{ "parse", cgi_mod.genParse },
    .{ "parse_qs", cgi_mod.genParse_qs },
    .{ "parse_qsl", cgi_mod.genParse_qsl },
    .{ "parse_multipart", cgi_mod.genParse_multipart },
    .{ "parse_header", cgi_mod.genParse_header },
    .{ "test", cgi_mod.genTest },
    .{ "print_environ", cgi_mod.genPrint_environ },
    .{ "print_form", cgi_mod.genPrint_form },
    .{ "print_directory", cgi_mod.genPrint_directory },
    .{ "print_environ_usage", cgi_mod.genPrint_environ_usage },
    .{ "escape", cgi_mod.genEscape },
    .{ "FieldStorage", cgi_mod.genFieldStorage },
    .{ "MiniFieldStorage", cgi_mod.genMiniFieldStorage },
    .{ "maxlen", cgi_mod.genMaxlen },
});

/// wsgiref.simple_server module functions
const WsgirefSimpleServerFuncs = FuncMap.initComptime(.{
    .{ "make_server", wsgiref_mod.genMake_server },
    .{ "WSGIServer", wsgiref_mod.genWSGIServer },
    .{ "WSGIRequestHandler", wsgiref_mod.genWSGIRequestHandler },
    .{ "demo_app", wsgiref_mod.genDemo_app },
});

/// wsgiref.util module functions
const WsgirefUtilFuncs = FuncMap.initComptime(.{
    .{ "setup_testing_defaults", wsgiref_mod.genSetup_testing_defaults },
    .{ "request_uri", wsgiref_mod.genRequest_uri },
    .{ "application_uri", wsgiref_mod.genApplication_uri },
    .{ "shift_path_info", wsgiref_mod.genShift_path_info },
    .{ "FileWrapper", wsgiref_mod.genFileWrapper },
});

/// wsgiref.headers module functions
const WsgirefHeadersFuncs = FuncMap.initComptime(.{
    .{ "Headers", wsgiref_mod.genHeaders },
});

/// wsgiref.handlers module functions
const WsgirefHandlersFuncs = FuncMap.initComptime(.{
    .{ "BaseHandler", wsgiref_mod.genBaseHandler },
    .{ "SimpleHandler", wsgiref_mod.genSimpleHandler },
    .{ "BaseCGIHandler", wsgiref_mod.genBaseCGIHandler },
    .{ "CGIHandler", wsgiref_mod.genCGIHandler },
    .{ "IISCGIHandler", wsgiref_mod.genIISCGIHandler },
});

/// wsgiref.validate module functions
const WsgirefValidateFuncs = FuncMap.initComptime(.{
    .{ "validator", wsgiref_mod.genValidator },
    .{ "assert_", wsgiref_mod.genAssert_ },
    .{ "check_status", wsgiref_mod.genCheck_status },
    .{ "check_headers", wsgiref_mod.genCheck_headers },
    .{ "check_content_type", wsgiref_mod.genCheck_content_type },
    .{ "check_exc_info", wsgiref_mod.genCheck_exc_info },
    .{ "check_environ", wsgiref_mod.genCheck_environ },
    .{ "WSGIWarning", wsgiref_mod.genWSGIWarning },
});

/// audioop module functions
const AudioopFuncs = FuncMap.initComptime(.{
    .{ "add", audioop_mod.genAdd },
    .{ "adpcm2lin", audioop_mod.genAdpcm2lin },
    .{ "alaw2lin", audioop_mod.genAlaw2lin },
    .{ "avg", audioop_mod.genAvg },
    .{ "avgpp", audioop_mod.genAvgpp },
    .{ "bias", audioop_mod.genBias },
    .{ "byteswap", audioop_mod.genByteswap },
    .{ "cross", audioop_mod.genCross },
    .{ "findfactor", audioop_mod.genFindfactor },
    .{ "findfit", audioop_mod.genFindfit },
    .{ "findmax", audioop_mod.genFindmax },
    .{ "getsample", audioop_mod.genGetsample },
    .{ "lin2adpcm", audioop_mod.genLin2adpcm },
    .{ "lin2alaw", audioop_mod.genLin2alaw },
    .{ "lin2lin", audioop_mod.genLin2lin },
    .{ "lin2ulaw", audioop_mod.genLin2ulaw },
    .{ "max", audioop_mod.genMax },
    .{ "maxpp", audioop_mod.genMaxpp },
    .{ "minmax", audioop_mod.genMinmax },
    .{ "mul", audioop_mod.genMul },
    .{ "ratecv", audioop_mod.genRatecv },
    .{ "reverse", audioop_mod.genReverse },
    .{ "rms", audioop_mod.genRms },
    .{ "tomono", audioop_mod.genTomono },
    .{ "tostereo", audioop_mod.genTostereo },
    .{ "ulaw2lin", audioop_mod.genUlaw2lin },
    .{ "error", audioop_mod.genError },
});

/// wave module functions
const WaveFuncs = FuncMap.initComptime(.{
    .{ "open", wave_mod.genOpen },
    .{ "Wave_read", wave_mod.genWave_read },
    .{ "Wave_write", wave_mod.genWave_write },
    .{ "Error", wave_mod.genError },
});

/// aifc module functions
const AifcFuncs = FuncMap.initComptime(.{
    .{ "open", aifc_mod.genOpen },
    .{ "Aifc_read", aifc_mod.genAifc_read },
    .{ "Aifc_write", aifc_mod.genAifc_write },
    .{ "Error", aifc_mod.genError },
});

/// sunau module functions
const SunauFuncs = FuncMap.initComptime(.{
    .{ "open", sunau_mod.genOpen },
    .{ "Au_read", sunau_mod.genAu_read },
    .{ "Au_write", sunau_mod.genAu_write },
    .{ "AUDIO_FILE_MAGIC", sunau_mod.genAUDIO_FILE_MAGIC },
    .{ "AUDIO_FILE_ENCODING_MULAW_8", sunau_mod.genAUDIO_FILE_ENCODING_MULAW_8 },
    .{ "AUDIO_FILE_ENCODING_LINEAR_8", sunau_mod.genAUDIO_FILE_ENCODING_LINEAR_8 },
    .{ "AUDIO_FILE_ENCODING_LINEAR_16", sunau_mod.genAUDIO_FILE_ENCODING_LINEAR_16 },
    .{ "AUDIO_FILE_ENCODING_LINEAR_24", sunau_mod.genAUDIO_FILE_ENCODING_LINEAR_24 },
    .{ "AUDIO_FILE_ENCODING_LINEAR_32", sunau_mod.genAUDIO_FILE_ENCODING_LINEAR_32 },
    .{ "AUDIO_FILE_ENCODING_FLOAT", sunau_mod.genAUDIO_FILE_ENCODING_FLOAT },
    .{ "AUDIO_FILE_ENCODING_DOUBLE", sunau_mod.genAUDIO_FILE_ENCODING_DOUBLE },
    .{ "AUDIO_FILE_ENCODING_ALAW_8", sunau_mod.genAUDIO_FILE_ENCODING_ALAW_8 },
    .{ "Error", sunau_mod.genError },
});

/// sndhdr module functions
const SndhdrFuncs = FuncMap.initComptime(.{
    .{ "what", sndhdr_mod.genWhat },
    .{ "whathdr", sndhdr_mod.genWhathdr },
    .{ "SndHeaders", sndhdr_mod.genSndHeaders },
    .{ "tests", sndhdr_mod.genTests },
});

/// imghdr module functions
const ImghdrFuncs = FuncMap.initComptime(.{
    .{ "what", imghdr_mod.genWhat },
    .{ "tests", imghdr_mod.genTests },
});

/// colorsys module functions
const ColorsysFuncs = FuncMap.initComptime(.{
    .{ "rgb_to_yiq", colorsys_mod.genRgb_to_yiq },
    .{ "yiq_to_rgb", colorsys_mod.genYiq_to_rgb },
    .{ "rgb_to_hls", colorsys_mod.genRgb_to_hls },
    .{ "hls_to_rgb", colorsys_mod.genHls_to_rgb },
    .{ "rgb_to_hsv", colorsys_mod.genRgb_to_hsv },
    .{ "hsv_to_rgb", colorsys_mod.genHsv_to_rgb },
});

/// netrc module functions
const NetrcFuncs = FuncMap.initComptime(.{
    .{ "netrc", netrc_mod.genNetrc },
    .{ "NetrcParseError", netrc_mod.genNetrcParseError },
});

/// xdrlib module functions
const XdrlibFuncs = FuncMap.initComptime(.{
    .{ "Packer", xdrlib_mod.genPacker },
    .{ "Unpacker", xdrlib_mod.genUnpacker },
    .{ "Error", xdrlib_mod.genError },
    .{ "ConversionError", xdrlib_mod.genConversionError },
});

/// plistlib module functions
const PlistlibFuncs = FuncMap.initComptime(.{
    .{ "load", plistlib_mod.genLoad },
    .{ "loads", plistlib_mod.genLoads },
    .{ "dump", plistlib_mod.genDump },
    .{ "dumps", plistlib_mod.genDumps },
    .{ "UID", plistlib_mod.genUID },
    .{ "FMT_XML", plistlib_mod.genFMT_XML },
    .{ "FMT_BINARY", plistlib_mod.genFMT_BINARY },
    .{ "Dict", plistlib_mod.genDict },
    .{ "Data", plistlib_mod.genData },
    .{ "InvalidFileException", plistlib_mod.genInvalidFileException },
    .{ "readPlist", plistlib_mod.genReadPlist },
    .{ "writePlist", plistlib_mod.genWritePlist },
    .{ "readPlistFromBytes", plistlib_mod.genReadPlistFromBytes },
    .{ "writePlistToBytes", plistlib_mod.genWritePlistToBytes },
});

/// rlcompleter module functions
const RlcompleterFuncs = FuncMap.initComptime(.{
    .{ "Completer", rlcompleter_mod.genCompleter },
});

/// readline module functions
const ReadlineFuncs = FuncMap.initComptime(.{
    .{ "parse_and_bind", readline_mod.genParse_and_bind },
    .{ "read_init_file", readline_mod.genRead_init_file },
    .{ "get_line_buffer", readline_mod.genGet_line_buffer },
    .{ "insert_text", readline_mod.genInsert_text },
    .{ "redisplay", readline_mod.genRedisplay },
    .{ "read_history_file", readline_mod.genRead_history_file },
    .{ "write_history_file", readline_mod.genWrite_history_file },
    .{ "append_history_file", readline_mod.genAppend_history_file },
    .{ "get_history_length", readline_mod.genGet_history_length },
    .{ "set_history_length", readline_mod.genSet_history_length },
    .{ "clear_history", readline_mod.genClear_history },
    .{ "get_current_history_length", readline_mod.genGet_current_history_length },
    .{ "get_history_item", readline_mod.genGet_history_item },
    .{ "remove_history_item", readline_mod.genRemove_history_item },
    .{ "replace_history_item", readline_mod.genReplace_history_item },
    .{ "add_history", readline_mod.genAdd_history },
    .{ "set_auto_history", readline_mod.genSet_auto_history },
    .{ "set_startup_hook", readline_mod.genSet_startup_hook },
    .{ "set_pre_input_hook", readline_mod.genSet_pre_input_hook },
    .{ "set_completer", readline_mod.genSet_completer },
    .{ "get_completer", readline_mod.genGet_completer },
    .{ "get_completion_type", readline_mod.genGet_completion_type },
    .{ "get_begidx", readline_mod.genGet_begidx },
    .{ "get_endidx", readline_mod.genGet_endidx },
    .{ "set_completer_delims", readline_mod.genSet_completer_delims },
    .{ "get_completer_delims", readline_mod.genGet_completer_delims },
    .{ "set_completion_display_matches_hook", readline_mod.genSet_completion_display_matches_hook },
});

/// sched module functions
const SchedFuncs = FuncMap.initComptime(.{
    .{ "scheduler", sched_mod.genScheduler },
    .{ "Event", sched_mod.genEvent },
});

/// mailbox module functions
const MailboxFuncs = FuncMap.initComptime(.{
    .{ "Mailbox", mailbox_mod.genMailbox },
    .{ "Maildir", mailbox_mod.genMaildir },
    .{ "mbox", mailbox_mod.genMbox },
    .{ "MH", mailbox_mod.genMH },
    .{ "Babyl", mailbox_mod.genBabyl },
    .{ "MMDF", mailbox_mod.genMMDF },
    .{ "Message", mailbox_mod.genMessage },
    .{ "MaildirMessage", mailbox_mod.genMaildirMessage },
    .{ "mboxMessage", mailbox_mod.genMboxMessage },
    .{ "MHMessage", mailbox_mod.genMHMessage },
    .{ "BabylMessage", mailbox_mod.genBabylMessage },
    .{ "MMDFMessage", mailbox_mod.genMMDFMessage },
    .{ "Error", mailbox_mod.genError },
    .{ "NoSuchMailboxError", mailbox_mod.genNoSuchMailboxError },
    .{ "NotEmptyError", mailbox_mod.genNotEmptyError },
    .{ "ExternalClashError", mailbox_mod.genExternalClashError },
    .{ "FormatError", mailbox_mod.genFormatError },
});

/// mailcap module functions
const MailcapFuncs = FuncMap.initComptime(.{
    .{ "findmatch", mailcap_mod.genFindmatch },
    .{ "getcaps", mailcap_mod.genGetcaps },
    .{ "listmailcapfiles", mailcap_mod.genListmailcapfiles },
    .{ "readmailcapfile", mailcap_mod.genReadmailcapfile },
    .{ "lookup", mailcap_mod.genLookup },
    .{ "subst", mailcap_mod.genSubst },
});

/// mimetypes module functions
const MimetypesFuncs = FuncMap.initComptime(.{
    .{ "guess_type", mimetypes_mod.genGuess_type },
    .{ "guess_all_extensions", mimetypes_mod.genGuess_all_extensions },
    .{ "guess_extension", mimetypes_mod.genGuess_extension },
    .{ "init", mimetypes_mod.genInit },
    .{ "read_mime_types", mimetypes_mod.genRead_mime_types },
    .{ "add_type", mimetypes_mod.genAdd_type },
    .{ "MimeTypes", mimetypes_mod.genMimeTypes },
    .{ "knownfiles", mimetypes_mod.genKnownfiles },
    .{ "inited", mimetypes_mod.genInited },
    .{ "suffix_map", mimetypes_mod.genSuffix_map },
    .{ "encodings_map", mimetypes_mod.genEncodings_map },
    .{ "types_map", mimetypes_mod.genTypes_map },
    .{ "common_types", mimetypes_mod.genCommon_types },
});

/// quopri module functions
const QuopriFuncs = FuncMap.initComptime(.{
    .{ "encode", quopri_mod.genEncode },
    .{ "decode", quopri_mod.genDecode },
    .{ "encodestring", quopri_mod.genEncodestring },
    .{ "decodestring", quopri_mod.genDecodestring },
});

/// uu module functions
const UuFuncs = FuncMap.initComptime(.{
    .{ "encode", uu_mod.genEncode },
    .{ "decode", uu_mod.genDecode },
    .{ "Error", uu_mod.genError },
});

/// html.parser module functions
const HtmlParserFuncs = FuncMap.initComptime(.{
    .{ "HTMLParser", html_parser_mod.genHTMLParser },
    .{ "HTMLParseError", html_parser_mod.genHTMLParseError },
});

/// html.entities module functions
const HtmlEntitiesFuncs = FuncMap.initComptime(.{
    .{ "html5", html_entities_mod.genHtml5 },
    .{ "name2codepoint", html_entities_mod.genName2codepoint },
    .{ "codepoint2name", html_entities_mod.genCodepoint2name },
    .{ "entitydefs", html_entities_mod.genEntitydefs },
});

/// xml.sax module functions
const XmlSaxFuncs = FuncMap.initComptime(.{
    .{ "make_parser", xml_sax_mod.genMake_parser },
    .{ "parse", xml_sax_mod.genParse },
    .{ "parseString", xml_sax_mod.genParseString },
    .{ "ContentHandler", xml_sax_mod.genContentHandler },
    .{ "DTDHandler", xml_sax_mod.genDTDHandler },
    .{ "EntityResolver", xml_sax_mod.genEntityResolver },
    .{ "ErrorHandler", xml_sax_mod.genErrorHandler },
    .{ "InputSource", xml_sax_mod.genInputSource },
    .{ "AttributesImpl", xml_sax_mod.genAttributesImpl },
    .{ "AttributesNSImpl", xml_sax_mod.genAttributesNSImpl },
    .{ "SAXException", xml_sax_mod.genSAXException },
    .{ "SAXNotRecognizedException", xml_sax_mod.genSAXNotRecognizedException },
    .{ "SAXNotSupportedException", xml_sax_mod.genSAXNotSupportedException },
    .{ "SAXParseException", xml_sax_mod.genSAXParseException },
});

/// xml.dom module functions
const XmlDomFuncs = FuncMap.initComptime(.{
    .{ "registerDOMImplementation", xml_dom_mod.genRegisterDOMImplementation },
    .{ "getDOMImplementation", xml_dom_mod.genGetDOMImplementation },
    .{ "ELEMENT_NODE", xml_dom_mod.genELEMENT_NODE },
    .{ "ATTRIBUTE_NODE", xml_dom_mod.genATTRIBUTE_NODE },
    .{ "TEXT_NODE", xml_dom_mod.genTEXT_NODE },
    .{ "CDATA_SECTION_NODE", xml_dom_mod.genCDATA_SECTION_NODE },
    .{ "ENTITY_REFERENCE_NODE", xml_dom_mod.genENTITY_REFERENCE_NODE },
    .{ "ENTITY_NODE", xml_dom_mod.genENTITY_NODE },
    .{ "PROCESSING_INSTRUCTION_NODE", xml_dom_mod.genPROCESSING_INSTRUCTION_NODE },
    .{ "COMMENT_NODE", xml_dom_mod.genCOMMENT_NODE },
    .{ "DOCUMENT_NODE", xml_dom_mod.genDOCUMENT_NODE },
    .{ "DOCUMENT_TYPE_NODE", xml_dom_mod.genDOCUMENT_TYPE_NODE },
    .{ "DOCUMENT_FRAGMENT_NODE", xml_dom_mod.genDOCUMENT_FRAGMENT_NODE },
    .{ "NOTATION_NODE", xml_dom_mod.genNOTATION_NODE },
    .{ "DomstringSizeErr", xml_dom_mod.genDomstringSizeErr },
    .{ "HierarchyRequestErr", xml_dom_mod.genHierarchyRequestErr },
    .{ "IndexSizeErr", xml_dom_mod.genIndexSizeErr },
    .{ "InuseAttributeErr", xml_dom_mod.genInuseAttributeErr },
    .{ "InvalidAccessErr", xml_dom_mod.genInvalidAccessErr },
    .{ "InvalidCharacterErr", xml_dom_mod.genInvalidCharacterErr },
    .{ "InvalidModificationErr", xml_dom_mod.genInvalidModificationErr },
    .{ "InvalidStateErr", xml_dom_mod.genInvalidStateErr },
    .{ "NamespaceErr", xml_dom_mod.genNamespaceErr },
    .{ "NoDataAllowedErr", xml_dom_mod.genNoDataAllowedErr },
    .{ "NoModificationAllowedErr", xml_dom_mod.genNoModificationAllowedErr },
    .{ "NotFoundErr", xml_dom_mod.genNotFoundErr },
    .{ "NotSupportedErr", xml_dom_mod.genNotSupportedErr },
    .{ "SyntaxErr", xml_dom_mod.genSyntaxErr },
    .{ "ValidationErr", xml_dom_mod.genValidationErr },
    .{ "WrongDocumentErr", xml_dom_mod.genWrongDocumentErr },
});

/// builtins module functions
const BuiltinsFuncs = FuncMap.initComptime(.{
    .{ "open", builtins_mod.genOpen },
    .{ "print", builtins_mod.genPrint },
    .{ "len", builtins_mod.genLen },
    .{ "range", builtins_mod.genRange },
    .{ "enumerate", builtins_mod.genEnumerate },
    .{ "zip", builtins_mod.genZip },
    .{ "map", builtins_mod.genMap },
    .{ "filter", builtins_mod.genFilter },
    .{ "sorted", builtins_mod.genSorted },
    .{ "reversed", builtins_mod.genReversed },
    .{ "sum", builtins_mod.genSum },
    .{ "min", builtins_mod.genMin },
    .{ "max", builtins_mod.genMax },
    .{ "abs", builtins_mod.genAbs },
    .{ "all", builtins_mod.genAll },
    .{ "any", builtins_mod.genAny },
    .{ "isinstance", builtins_mod.genIsinstance },
    .{ "issubclass", builtins_mod.genIssubclass },
    .{ "hasattr", builtins_mod.genHasattr },
    .{ "getattr", builtins_mod.genGetattr },
    .{ "setattr", builtins_mod.genSetattr },
    .{ "delattr", builtins_mod.genDelattr },
    .{ "callable", builtins_mod.genCallable },
    .{ "repr", builtins_mod.genRepr },
    .{ "ascii", builtins_mod.genAscii },
    .{ "chr", builtins_mod.genChr },
    .{ "ord", builtins_mod.genOrd },
    .{ "hex", builtins_mod.genHex },
    .{ "oct", builtins_mod.genOct },
    .{ "bin", builtins_mod.genBin },
    .{ "pow", builtins_mod.genPow },
    .{ "round", builtins_mod.genRound },
    .{ "divmod", builtins_mod.genDivmod },
    .{ "hash", builtins_mod.genHash },
    .{ "id", builtins_mod.genId },
    .{ "type", builtins_mod.genType },
    .{ "dir", builtins_mod.genDir },
    .{ "vars", builtins_mod.genVars },
    .{ "globals", builtins_mod.genGlobals },
    .{ "locals", builtins_mod.genLocals },
    .{ "eval", builtins_mod.genEval },
    .{ "exec", builtins_mod.genExec },
    .{ "compile", builtins_mod.genCompile },
    .{ "input", builtins_mod.genInput },
    .{ "format", builtins_mod.genFormat },
    .{ "iter", builtins_mod.genIter },
    .{ "next", builtins_mod.genNext },
    .{ "slice", builtins_mod.genSlice },
    .{ "staticmethod", builtins_mod.genStaticmethod },
    .{ "classmethod", builtins_mod.genClassmethod },
    .{ "property", builtins_mod.genProperty },
    .{ "super", builtins_mod.genSuper },
    .{ "object", builtins_mod.genObject },
    .{ "breakpoint", builtins_mod.genBreakpoint },
    .{ "__import__", builtins_mod.genImport },
    .{ "Exception", builtins_mod.genException },
    .{ "BaseException", builtins_mod.genBaseException },
    .{ "TypeError", builtins_mod.genTypeError },
    .{ "ValueError", builtins_mod.genValueError },
    .{ "KeyError", builtins_mod.genKeyError },
    .{ "IndexError", builtins_mod.genIndexError },
    .{ "AttributeError", builtins_mod.genAttributeError },
    .{ "NameError", builtins_mod.genNameError },
    .{ "RuntimeError", builtins_mod.genRuntimeError },
    .{ "StopIteration", builtins_mod.genStopIteration },
    .{ "GeneratorExit", builtins_mod.genGeneratorExit },
    .{ "ArithmeticError", builtins_mod.genArithmeticError },
    .{ "ZeroDivisionError", builtins_mod.genZeroDivisionError },
    .{ "OverflowError", builtins_mod.genOverflowError },
    .{ "FloatingPointError", builtins_mod.genFloatingPointError },
    .{ "LookupError", builtins_mod.genLookupError },
    .{ "AssertionError", builtins_mod.genAssertionError },
    .{ "ImportError", builtins_mod.genImportError },
    .{ "ModuleNotFoundError", builtins_mod.genModuleNotFoundError },
    .{ "OSError", builtins_mod.genOSError },
    .{ "FileNotFoundError", builtins_mod.genFileNotFoundError },
    .{ "FileExistsError", builtins_mod.genFileExistsError },
    .{ "PermissionError", builtins_mod.genPermissionError },
    .{ "IsADirectoryError", builtins_mod.genIsADirectoryError },
    .{ "NotADirectoryError", builtins_mod.genNotADirectoryError },
    .{ "TimeoutError", builtins_mod.genTimeoutError },
    .{ "ConnectionError", builtins_mod.genConnectionError },
    .{ "BrokenPipeError", builtins_mod.genBrokenPipeError },
    .{ "ConnectionAbortedError", builtins_mod.genConnectionAbortedError },
    .{ "ConnectionRefusedError", builtins_mod.genConnectionRefusedError },
    .{ "ConnectionResetError", builtins_mod.genConnectionResetError },
    .{ "EOFError", builtins_mod.genEOFError },
    .{ "MemoryError", builtins_mod.genMemoryError },
    .{ "RecursionError", builtins_mod.genRecursionError },
    .{ "SystemError", builtins_mod.genSystemError },
    .{ "SystemExit", builtins_mod.genSystemExit },
    .{ "KeyboardInterrupt", builtins_mod.genKeyboardInterrupt },
    .{ "NotImplementedError", builtins_mod.genNotImplementedError },
    .{ "IndentationError", builtins_mod.genIndentationError },
    .{ "TabError", builtins_mod.genTabError },
    .{ "SyntaxError", builtins_mod.genSyntaxError },
    .{ "UnicodeError", builtins_mod.genUnicodeError },
    .{ "UnicodeDecodeError", builtins_mod.genUnicodeDecodeError },
    .{ "UnicodeEncodeError", builtins_mod.genUnicodeEncodeError },
    .{ "UnicodeTranslateError", builtins_mod.genUnicodeTranslateError },
    .{ "BufferError", builtins_mod.genBufferError },
    .{ "Warning", builtins_mod.genWarning },
    .{ "UserWarning", builtins_mod.genUserWarning },
    .{ "DeprecationWarning", builtins_mod.genDeprecationWarning },
    .{ "PendingDeprecationWarning", builtins_mod.genPendingDeprecationWarning },
    .{ "SyntaxWarning", builtins_mod.genSyntaxWarning },
    .{ "RuntimeWarning", builtins_mod.genRuntimeWarning },
    .{ "FutureWarning", builtins_mod.genFutureWarning },
    .{ "ImportWarning", builtins_mod.genImportWarning },
    .{ "UnicodeWarning", builtins_mod.genUnicodeWarning },
    .{ "BytesWarning", builtins_mod.genBytesWarning },
    .{ "ResourceWarning", builtins_mod.genResourceWarning },
    .{ "True", builtins_mod.genTrue },
    .{ "False", builtins_mod.genFalse },
    .{ "None", builtins_mod.genNone },
    .{ "Ellipsis", builtins_mod.genEllipsis },
    .{ "NotImplemented", builtins_mod.genNotImplemented },
});

/// typing_extensions module functions
const TypingExtensionsFuncs = FuncMap.initComptime(.{
    .{ "Annotated", typing_extensions_mod.genAnnotated },
    .{ "ParamSpec", typing_extensions_mod.genParamSpec },
    .{ "ParamSpecArgs", typing_extensions_mod.genParamSpecArgs },
    .{ "ParamSpecKwargs", typing_extensions_mod.genParamSpecKwargs },
    .{ "Concatenate", typing_extensions_mod.genConcatenate },
    .{ "TypeAlias", typing_extensions_mod.genTypeAlias },
    .{ "TypeGuard", typing_extensions_mod.genTypeGuard },
    .{ "TypeIs", typing_extensions_mod.genTypeIs },
    .{ "Self", typing_extensions_mod.genSelf },
    .{ "Never", typing_extensions_mod.genNever },
    .{ "Required", typing_extensions_mod.genRequired },
    .{ "NotRequired", typing_extensions_mod.genNotRequired },
    .{ "LiteralString", typing_extensions_mod.genLiteralString },
    .{ "Unpack", typing_extensions_mod.genUnpack },
    .{ "TypeVarTuple", typing_extensions_mod.genTypeVarTuple },
    .{ "override", typing_extensions_mod.genOverride },
    .{ "final", typing_extensions_mod.genFinal },
    .{ "deprecated", typing_extensions_mod.genDeprecated },
    .{ "dataclass_transform", typing_extensions_mod.genDataclass_transform },
    .{ "runtime_checkable", typing_extensions_mod.genRuntime_checkable },
    .{ "Protocol", typing_extensions_mod.genProtocol },
    .{ "TypedDict", typing_extensions_mod.genTypedDict },
    .{ "NamedTuple", typing_extensions_mod.genNamedTuple },
    .{ "get_type_hints", typing_extensions_mod.genGet_type_hints },
    .{ "get_origin", typing_extensions_mod.genGet_origin },
    .{ "get_args", typing_extensions_mod.genGet_args },
    .{ "is_typeddict", typing_extensions_mod.genIs_typeddict },
    .{ "get_annotations", typing_extensions_mod.genGet_annotations },
    .{ "assert_type", typing_extensions_mod.genAssert_type },
    .{ "reveal_type", typing_extensions_mod.genReveal_type },
    .{ "assert_never", typing_extensions_mod.genAssert_never },
    .{ "clear_overloads", typing_extensions_mod.genClear_overloads },
    .{ "get_overloads", typing_extensions_mod.genGet_overloads },
    .{ "Doc", typing_extensions_mod.genDoc },
    .{ "ReadOnly", typing_extensions_mod.genReadOnly },
    .{ "Any", typing_extensions_mod.genAny },
    .{ "Union", typing_extensions_mod.genUnion },
    .{ "Optional", typing_extensions_mod.genOptional },
    .{ "List", typing_extensions_mod.genList },
    .{ "Dict", typing_extensions_mod.genDict },
    .{ "Set", typing_extensions_mod.genSet },
    .{ "Tuple", typing_extensions_mod.genTuple },
    .{ "Callable", typing_extensions_mod.genCallable },
    .{ "Type", typing_extensions_mod.genType },
    .{ "Literal", typing_extensions_mod.genLiteral },
    .{ "ClassVar", typing_extensions_mod.genClassVar },
    .{ "TypeVar", typing_extensions_mod.genTypeVar },
    .{ "Generic", typing_extensions_mod.genGeneric },
    .{ "NoReturn", typing_extensions_mod.genNoReturn },
    .{ "cast", typing_extensions_mod.genCast },
    .{ "overload", typing_extensions_mod.genOverload },
    .{ "no_type_check", typing_extensions_mod.genNo_type_check },
    .{ "TYPE_CHECKING", typing_extensions_mod.genTYPE_CHECKING },
});

/// importlib module functions
const ImportlibFuncs = FuncMap.initComptime(.{
    .{ "import_module", importlib_mod.genImport_module },
    .{ "reload", importlib_mod.genReload },
    .{ "invalidate_caches", importlib_mod.genInvalidate_caches },
});

/// importlib.abc module functions
const ImportlibAbcFuncs = FuncMap.initComptime(.{
    .{ "Loader", importlib_mod.genLoader },
    .{ "MetaPathFinder", importlib_mod.genMetaPathFinder },
    .{ "PathEntryFinder", importlib_mod.genPathEntryFinder },
    .{ "ResourceLoader", importlib_mod.genResourceLoader },
    .{ "InspectLoader", importlib_mod.genInspectLoader },
    .{ "ExecutionLoader", importlib_mod.genExecutionLoader },
    .{ "FileLoader", importlib_mod.genFileLoader },
    .{ "SourceLoader", importlib_mod.genSourceLoader },
    .{ "Traversable", importlib_mod.genTraversable },
    .{ "TraversableResources", importlib_mod.genTraversableResources },
});

/// importlib.resources module functions
const ImportlibResourcesFuncs = FuncMap.initComptime(.{
    .{ "files", importlib_mod.genFiles },
    .{ "as_file", importlib_mod.genAs_file },
    .{ "read_text", importlib_mod.genRead_text },
    .{ "read_binary", importlib_mod.genRead_binary },
    .{ "is_resource", importlib_mod.genIs_resource },
    .{ "contents", importlib_mod.genContents },
});

/// importlib.metadata module functions
const ImportlibMetadataFuncs = FuncMap.initComptime(.{
    .{ "version", importlib_mod.genVersion },
    .{ "metadata", importlib_mod.genMetadata },
    .{ "entry_points", importlib_mod.genEntry_points },
    .{ "files", importlib_mod.genMetadataFiles },
    .{ "requires", importlib_mod.genRequires },
    .{ "distributions", importlib_mod.genDistributions },
    .{ "packages_distributions", importlib_mod.genPackages_distributions },
    .{ "PackageNotFoundError", importlib_mod.genPackageNotFoundError },
});

/// importlib.util module functions
const ImportlibUtilFuncs = FuncMap.initComptime(.{
    .{ "find_spec", importlib_mod.genFind_spec },
    .{ "module_from_spec", importlib_mod.genModule_from_spec },
    .{ "spec_from_loader", importlib_mod.genSpec_from_loader },
    .{ "spec_from_file_location", importlib_mod.genSpec_from_file_location },
    .{ "source_hash", importlib_mod.genSource_hash },
    .{ "resolve_name", importlib_mod.genResolve_name },
    .{ "LazyLoader", importlib_mod.genLazyLoader },
    .{ "MAGIC_NUMBER", importlib_mod.genMAGIC_NUMBER },
    .{ "cache_from_source", importlib_mod.genCache_from_source },
    .{ "source_from_cache", importlib_mod.genSource_from_cache },
    .{ "decode_source", importlib_mod.genDecode_source },
});

/// importlib.machinery module functions
const ImportlibMachineryFuncs = FuncMap.initComptime(.{
    .{ "ModuleSpec", importlib_mod.genModuleSpec },
    .{ "BuiltinImporter", importlib_mod.genBuiltinImporter },
    .{ "FrozenImporter", importlib_mod.genFrozenImporter },
    .{ "PathFinder", importlib_mod.genPathFinder },
    .{ "FileFinder", importlib_mod.genFileFinder },
    .{ "SourceFileLoader", importlib_mod.genSourceFileLoader },
    .{ "SourcelessFileLoader", importlib_mod.genSourcelessFileLoader },
    .{ "ExtensionFileLoader", importlib_mod.genExtensionFileLoader },
    .{ "SOURCE_SUFFIXES", importlib_mod.genSOURCE_SUFFIXES },
    .{ "BYTECODE_SUFFIXES", importlib_mod.genBYTECODE_SUFFIXES },
    .{ "EXTENSION_SUFFIXES", importlib_mod.genEXTENSION_SUFFIXES },
    .{ "all_suffixes", importlib_mod.genAll_suffixes },
});

/// pkgutil module functions
const PkgutilFuncs = FuncMap.initComptime(.{
    .{ "extend_path", pkgutil_mod.genExtend_path },
    .{ "find_loader", pkgutil_mod.genFind_loader },
    .{ "get_importer", pkgutil_mod.genGet_importer },
    .{ "get_loader", pkgutil_mod.genGet_loader },
    .{ "iter_importers", pkgutil_mod.genIter_importers },
    .{ "iter_modules", pkgutil_mod.genIter_modules },
    .{ "walk_packages", pkgutil_mod.genWalk_packages },
    .{ "get_data", pkgutil_mod.genGet_data },
    .{ "resolve_name", pkgutil_mod.genResolve_name },
    .{ "ModuleInfo", pkgutil_mod.genModuleInfo },
    .{ "ImpImporter", pkgutil_mod.genImpImporter },
    .{ "ImpLoader", pkgutil_mod.genImpLoader },
});

/// runpy module functions
const RunpyFuncs = FuncMap.initComptime(.{
    .{ "run_module", runpy_mod.genRun_module },
    .{ "run_path", runpy_mod.genRun_path },
});

/// venv module functions
const VenvFuncs = FuncMap.initComptime(.{
    .{ "EnvBuilder", venv_mod.genEnvBuilder },
    .{ "create", venv_mod.genCreate },
    .{ "ENV_CFG", venv_mod.genENV_CFG },
    .{ "BIN_NAME", venv_mod.genBIN_NAME },
});

/// zipimport module functions
const ZipimportFuncs = FuncMap.initComptime(.{
    .{ "zipimporter", zipimport_mod.genZipimporter },
    .{ "ZipImportError", zipimport_mod.genZipImportError },
});

/// compileall module functions
const CompileallFuncs = FuncMap.initComptime(.{
    .{ "compile_dir", compileall_mod.genCompile_dir },
    .{ "compile_file", compileall_mod.genCompile_file },
    .{ "compile_path", compileall_mod.genCompile_path },
    .{ "PycInvalidationMode", compileall_mod.genPycInvalidationMode },
});

/// py_compile module functions
const PyCompileFuncs = FuncMap.initComptime(.{
    .{ "compile", py_compile_mod.genCompile },
    .{ "main", py_compile_mod.genMain },
    .{ "PyCompileError", py_compile_mod.genPyCompileError },
    .{ "PycInvalidationMode", py_compile_mod.genPycInvalidationMode },
});

/// contextvars module functions
const ContextvarsFuncs = FuncMap.initComptime(.{
    .{ "ContextVar", contextvars_mod.genContextVar },
    .{ "Token", contextvars_mod.genToken },
    .{ "Context", contextvars_mod.genContext },
    .{ "copy_context", contextvars_mod.genCopy_context },
});

/// site module functions
const SiteFuncs = FuncMap.initComptime(.{
    .{ "PREFIXES", site_mod.genPREFIXES },
    .{ "ENABLE_USER_SITE", site_mod.genENABLE_USER_SITE },
    .{ "USER_SITE", site_mod.genUSER_SITE },
    .{ "USER_BASE", site_mod.genUSER_BASE },
    .{ "main", site_mod.genMain },
    .{ "addsitedir", site_mod.genAddsitedir },
    .{ "getsitepackages", site_mod.genGetsitepackages },
    .{ "getuserbase", site_mod.genGetuserbase },
    .{ "getusersitepackages", site_mod.genGetusersitepackages },
    .{ "removeduppaths", site_mod.genRemoveduppaths },
});

/// __future__ module functions
const FutureFuncs = FuncMap.initComptime(.{
    .{ "annotations", __future___mod.genAnnotations },
    .{ "division", __future___mod.genDivision },
    .{ "absolute_import", __future___mod.genAbsolute_import },
    .{ "with_statement", __future___mod.genWith_statement },
    .{ "print_function", __future___mod.genPrint_function },
    .{ "unicode_literals", __future___mod.genUnicode_literals },
    .{ "generator_stop", __future___mod.genGenerator_stop },
    .{ "nested_scopes", __future___mod.genNested_scopes },
    .{ "generators", __future___mod.genGenerators },
});

/// copyreg module functions
const CopyregFuncs = FuncMap.initComptime(.{
    .{ "pickle", copyreg_mod.genPickle },
    .{ "constructor", copyreg_mod.genConstructor },
    .{ "dispatch_table", copyreg_mod.genDispatch_table },
    .{ "_extension_registry", copyreg_mod.gen_extension_registry },
    .{ "_inverted_registry", copyreg_mod.gen_inverted_registry },
    .{ "_extension_cache", copyreg_mod.gen_extension_cache },
    .{ "add_extension", copyreg_mod.genAdd_extension },
    .{ "remove_extension", copyreg_mod.genRemove_extension },
    .{ "clear_extension_cache", copyreg_mod.genClear_extension_cache },
    .{ "__newobj__", copyreg_mod.gen__newobj__ },
    .{ "__newobj_ex__", copyreg_mod.gen__newobj_ex__ },
});

/// _thread module functions
const ThreadFuncs = FuncMap.initComptime(.{
    .{ "start_new_thread", _thread_mod.genStart_new_thread },
    .{ "interrupt_main", _thread_mod.genInterrupt_main },
    .{ "exit", _thread_mod.genExit },
    .{ "allocate_lock", _thread_mod.genAllocate_lock },
    .{ "get_ident", _thread_mod.genGet_ident },
    .{ "get_native_id", _thread_mod.genGet_native_id },
    .{ "stack_size", _thread_mod.genStack_size },
    .{ "TIMEOUT_MAX", _thread_mod.genTIMEOUT_MAX },
    .{ "LockType", _thread_mod.genLockType },
    .{ "RLock", _thread_mod.genRLock },
    .{ "error", _thread_mod.genError },
});

/// posixpath module functions
const PosixpathFuncs = FuncMap.initComptime(.{
    .{ "abspath", posixpath_mod.genAbspath },
    .{ "basename", posixpath_mod.genBasename },
    .{ "commonpath", posixpath_mod.genCommonpath },
    .{ "commonprefix", posixpath_mod.genCommonprefix },
    .{ "dirname", posixpath_mod.genDirname },
    .{ "exists", posixpath_mod.genExists },
    .{ "expanduser", posixpath_mod.genExpanduser },
    .{ "expandvars", posixpath_mod.genExpandvars },
    .{ "getatime", posixpath_mod.genGetatime },
    .{ "getctime", posixpath_mod.genGetctime },
    .{ "getmtime", posixpath_mod.genGetmtime },
    .{ "getsize", posixpath_mod.genGetsize },
    .{ "isabs", posixpath_mod.genIsabs },
    .{ "isdir", posixpath_mod.genIsdir },
    .{ "isfile", posixpath_mod.genIsfile },
    .{ "islink", posixpath_mod.genIslink },
    .{ "ismount", posixpath_mod.genIsmount },
    .{ "join", posixpath_mod.genJoin },
    .{ "lexists", posixpath_mod.genLexists },
    .{ "normcase", posixpath_mod.genNormcase },
    .{ "normpath", posixpath_mod.genNormpath },
    .{ "realpath", posixpath_mod.genRealpath },
    .{ "relpath", posixpath_mod.genRelpath },
    .{ "samefile", posixpath_mod.genSamefile },
    .{ "sameopenfile", posixpath_mod.genSameopenfile },
    .{ "samestat", posixpath_mod.genSamestat },
    .{ "split", posixpath_mod.genSplit },
    .{ "splitdrive", posixpath_mod.genSplitdrive },
    .{ "splitext", posixpath_mod.genSplitext },
    .{ "sep", posixpath_mod.genSep },
    .{ "altsep", posixpath_mod.genAltsep },
    .{ "extsep", posixpath_mod.genExtsep },
    .{ "pathsep", posixpath_mod.genPathsep },
    .{ "defpath", posixpath_mod.genDefpath },
    .{ "devnull", posixpath_mod.genDevnull },
    .{ "curdir", posixpath_mod.genCurdir },
    .{ "pardir", posixpath_mod.genPardir },
});

/// reprlib module functions
const ReprlibFuncs = FuncMap.initComptime(.{
    .{ "Repr", reprlib_mod.genRepr },
    .{ "repr", reprlib_mod.genReprFunc },
    .{ "recursive_repr", reprlib_mod.genRecursive_repr },
});

/// _collections_abc module functions
const CollectionsAbcFuncs = FuncMap.initComptime(.{
    .{ "Awaitable", _collections_abc_mod.genAwaitable },
    .{ "Coroutine", _collections_abc_mod.genCoroutine },
    .{ "AsyncIterable", _collections_abc_mod.genAsyncIterable },
    .{ "AsyncIterator", _collections_abc_mod.genAsyncIterator },
    .{ "AsyncGenerator", _collections_abc_mod.genAsyncGenerator },
    .{ "Hashable", _collections_abc_mod.genHashable },
    .{ "Iterable", _collections_abc_mod.genIterable },
    .{ "Iterator", _collections_abc_mod.genIterator },
    .{ "Generator", _collections_abc_mod.genGenerator },
    .{ "Reversible", _collections_abc_mod.genReversible },
    .{ "Container", _collections_abc_mod.genContainer },
    .{ "Collection", _collections_abc_mod.genCollection },
    .{ "Callable", _collections_abc_mod.genCallable },
    .{ "Set", _collections_abc_mod.genSet },
    .{ "MutableSet", _collections_abc_mod.genMutableSet },
    .{ "Mapping", _collections_abc_mod.genMapping },
    .{ "MutableMapping", _collections_abc_mod.genMutableMapping },
    .{ "Sequence", _collections_abc_mod.genSequence },
    .{ "MutableSequence", _collections_abc_mod.genMutableSequence },
    .{ "ByteString", _collections_abc_mod.genByteString },
    .{ "MappingView", _collections_abc_mod.genMappingView },
    .{ "KeysView", _collections_abc_mod.genKeysView },
    .{ "ItemsView", _collections_abc_mod.genItemsView },
    .{ "ValuesView", _collections_abc_mod.genValuesView },
    .{ "Sized", _collections_abc_mod.genSized },
    .{ "Buffer", _collections_abc_mod.genBuffer },
});

/// keyword module functions
const KeywordFuncs = FuncMap.initComptime(.{
    .{ "iskeyword", keyword_mod.genIskeyword },
    .{ "kwlist", keyword_mod.genKwlist },
    .{ "softkwlist", keyword_mod.genSoftkwlist },
    .{ "issoftkeyword", keyword_mod.genIssoftkeyword },
});

/// token module functions
const TokenFuncs = FuncMap.initComptime(.{
    .{ "ENDMARKER", token_mod.genENDMARKER },
    .{ "NAME", token_mod.genNAME },
    .{ "NUMBER", token_mod.genNUMBER },
    .{ "STRING", token_mod.genSTRING },
    .{ "NEWLINE", token_mod.genNEWLINE },
    .{ "INDENT", token_mod.genINDENT },
    .{ "DEDENT", token_mod.genDEDENT },
    .{ "OP", token_mod.genOP },
    .{ "ERRORTOKEN", token_mod.genERRORTOKEN },
    .{ "COMMENT", token_mod.genCOMMENT },
    .{ "NL", token_mod.genNL },
    .{ "ENCODING", token_mod.genENCODING },
    .{ "N_TOKENS", token_mod.genN_TOKENS },
    .{ "NT_OFFSET", token_mod.genNT_OFFSET },
    .{ "tok_name", token_mod.genTok_name },
    .{ "EXACT_TOKEN_TYPES", token_mod.genEXACT_TOKEN_TYPES },
    .{ "ISTERMINAL", token_mod.genISTERMINAL },
    .{ "ISNONTERMINAL", token_mod.genISNONTERMINAL },
    .{ "ISEOF", token_mod.genISEOF },
});

/// tokenize module functions
const TokenizeFuncs = FuncMap.initComptime(.{
    .{ "tokenize", tokenize_mod.genTokenize },
    .{ "generate_tokens", tokenize_mod.genGenerate_tokens },
    .{ "detect_encoding", tokenize_mod.genDetect_encoding },
    .{ "open", tokenize_mod.genOpen },
    .{ "untokenize", tokenize_mod.genUntokenize },
    .{ "TokenInfo", tokenize_mod.genTokenInfo },
    .{ "TokenError", tokenize_mod.genTokenError },
    .{ "StopTokenizing", tokenize_mod.genStopTokenizing },
});

/// dbm module functions
const DbmFuncs = FuncMap.initComptime(.{
    .{ "open", dbm_mod.genOpen },
    .{ "whichdb", dbm_mod.genWhichdb },
    .{ "error", dbm_mod.genError },
});

/// dbm.dumb module functions
const DbmDumbFuncs = FuncMap.initComptime(.{
    .{ "open", dbm_mod.genDumb_open },
    .{ "error", dbm_mod.genDumb_error },
});

/// dbm.gnu module functions
const DbmGnuFuncs = FuncMap.initComptime(.{
    .{ "open", dbm_mod.genGnu_open },
    .{ "error", dbm_mod.genGnu_error },
});

/// dbm.ndbm module functions
const DbmNdbmFuncs = FuncMap.initComptime(.{
    .{ "open", dbm_mod.genNdbm_open },
    .{ "error", dbm_mod.genNdbm_error },
});

/// symtable module functions
const SymtableFuncs = FuncMap.initComptime(.{
    .{ "symtable", symtable_mod.genSymtable },
    .{ "SymbolTable", symtable_mod.genSymbolTable },
    .{ "Symbol", symtable_mod.genSymbol },
    .{ "Function", symtable_mod.genFunction },
    .{ "Class", symtable_mod.genClass },
});

/// crypt module functions
const CryptFuncs = FuncMap.initComptime(.{
    .{ "crypt", crypt_mod.genCrypt },
    .{ "mksalt", crypt_mod.genMksalt },
    .{ "METHOD_SHA512", crypt_mod.genMETHOD_SHA512 },
    .{ "METHOD_SHA256", crypt_mod.genMETHOD_SHA256 },
    .{ "METHOD_BLOWFISH", crypt_mod.genMETHOD_BLOWFISH },
    .{ "METHOD_MD5", crypt_mod.genMETHOD_MD5 },
    .{ "METHOD_CRYPT", crypt_mod.genMETHOD_CRYPT },
    .{ "methods", crypt_mod.genMethods },
});

/// posix module functions
const PosixFuncs = FuncMap.initComptime(.{
    .{ "getcwd", posix_mod.genGetcwd },
    .{ "chdir", posix_mod.genChdir },
    .{ "listdir", posix_mod.genListdir },
    .{ "mkdir", posix_mod.genMkdir },
    .{ "rmdir", posix_mod.genRmdir },
    .{ "unlink", posix_mod.genUnlink },
    .{ "rename", posix_mod.genRename },
    .{ "stat", posix_mod.genStat },
    .{ "lstat", posix_mod.genLstat },
    .{ "fstat", posix_mod.genFstat },
    .{ "getenv", posix_mod.genGetenv },
    .{ "getpid", posix_mod.genGetpid },
    .{ "getppid", posix_mod.genGetppid },
    .{ "getuid", posix_mod.genGetuid },
    .{ "getgid", posix_mod.genGetgid },
    .{ "geteuid", posix_mod.genGeteuid },
    .{ "getegid", posix_mod.genGetegid },
    .{ "fork", posix_mod.genFork },
    .{ "kill", posix_mod.genKill },
    .{ "open", posix_mod.genOpen },
    .{ "close", posix_mod.genClose },
    .{ "read", posix_mod.genRead },
    .{ "write", posix_mod.genWrite },
    .{ "pipe", posix_mod.genPipe },
    .{ "dup", posix_mod.genDup },
    .{ "dup2", posix_mod.genDup2 },
    .{ "access", posix_mod.genAccess },
    .{ "chmod", posix_mod.genChmod },
    .{ "chown", posix_mod.genChown },
    .{ "umask", posix_mod.genUmask },
    .{ "symlink", posix_mod.genSymlink },
    .{ "readlink", posix_mod.genReadlink },
    .{ "uname", posix_mod.genUname },
    .{ "urandom", posix_mod.genUrandom },
    .{ "error", posix_mod.genError },
});

/// _io module functions
const IoInternalFuncs = FuncMap.initComptime(.{
    .{ "FileIO", _io_mod.genFileIO },
    .{ "BytesIO", _io_mod.genBytesIO },
    .{ "StringIO", _io_mod.genStringIO },
    .{ "BufferedReader", _io_mod.genBufferedReader },
    .{ "BufferedWriter", _io_mod.genBufferedWriter },
    .{ "BufferedRandom", _io_mod.genBufferedRandom },
    .{ "BufferedRWPair", _io_mod.genBufferedRWPair },
    .{ "TextIOWrapper", _io_mod.genTextIOWrapper },
    .{ "IncrementalNewlineDecoder", _io_mod.genIncrementalNewlineDecoder },
    .{ "open", _io_mod.genOpen },
    .{ "open_code", _io_mod.genOpen_code },
    .{ "text_encoding", _io_mod.genText_encoding },
    .{ "IOBase", _io_mod.genIOBase },
    .{ "RawIOBase", _io_mod.genRawIOBase },
    .{ "BufferedIOBase", _io_mod.genBufferedIOBase },
    .{ "TextIOBase", _io_mod.genTextIOBase },
    .{ "DEFAULT_BUFFER_SIZE", _io_mod.genDEFAULT_BUFFER_SIZE },
    .{ "UnsupportedOperation", _io_mod.genUnsupportedOperation },
    .{ "BlockingIOError", _io_mod.genBlockingIOError },
});

/// genericpath module functions
const GenericpathFuncs = FuncMap.initComptime(.{
    .{ "exists", genericpath_mod.genExists },
    .{ "isfile", genericpath_mod.genIsfile },
    .{ "isdir", genericpath_mod.genIsdir },
    .{ "getsize", genericpath_mod.genGetsize },
    .{ "getatime", genericpath_mod.genGetatime },
    .{ "getmtime", genericpath_mod.genGetmtime },
    .{ "getctime", genericpath_mod.genGetctime },
    .{ "commonprefix", genericpath_mod.genCommonprefix },
    .{ "samestat", genericpath_mod.genSamestat },
    .{ "samefile", genericpath_mod.genSamefile },
    .{ "sameopenfile", genericpath_mod.genSameopenfile },
    .{ "islink", genericpath_mod.genIslink },
});

/// ntpath module functions
const NtpathFuncs = FuncMap.initComptime(.{
    .{ "abspath", ntpath_mod.genAbspath },
    .{ "basename", ntpath_mod.genBasename },
    .{ "commonpath", ntpath_mod.genCommonpath },
    .{ "commonprefix", ntpath_mod.genCommonprefix },
    .{ "dirname", ntpath_mod.genDirname },
    .{ "exists", ntpath_mod.genExists },
    .{ "expanduser", ntpath_mod.genExpanduser },
    .{ "expandvars", ntpath_mod.genExpandvars },
    .{ "getatime", ntpath_mod.genGetatime },
    .{ "getctime", ntpath_mod.genGetctime },
    .{ "getmtime", ntpath_mod.genGetmtime },
    .{ "getsize", ntpath_mod.genGetsize },
    .{ "isabs", ntpath_mod.genIsabs },
    .{ "isdir", ntpath_mod.genIsdir },
    .{ "isfile", ntpath_mod.genIsfile },
    .{ "islink", ntpath_mod.genIslink },
    .{ "ismount", ntpath_mod.genIsmount },
    .{ "join", ntpath_mod.genJoin },
    .{ "lexists", ntpath_mod.genLexists },
    .{ "normcase", ntpath_mod.genNormcase },
    .{ "normpath", ntpath_mod.genNormpath },
    .{ "realpath", ntpath_mod.genRealpath },
    .{ "relpath", ntpath_mod.genRelpath },
    .{ "samefile", ntpath_mod.genSamefile },
    .{ "sameopenfile", ntpath_mod.genSameopenfile },
    .{ "samestat", ntpath_mod.genSamestat },
    .{ "split", ntpath_mod.genSplit },
    .{ "splitdrive", ntpath_mod.genSplitdrive },
    .{ "splitext", ntpath_mod.genSplitext },
    .{ "sep", ntpath_mod.genSep },
    .{ "altsep", ntpath_mod.genAltsep },
    .{ "extsep", ntpath_mod.genExtsep },
    .{ "pathsep", ntpath_mod.genPathsep },
    .{ "defpath", ntpath_mod.genDefpath },
    .{ "devnull", ntpath_mod.genDevnull },
    .{ "curdir", ntpath_mod.genCurdir },
    .{ "pardir", ntpath_mod.genPardir },
});

/// zlib module functions
const ZlibFuncs = FuncMap.initComptime(.{
    .{ "compress", zlib_mod.genCompress },
    .{ "decompress", zlib_mod.genDecompress },
    .{ "compressobj", zlib_mod.genCompressobj },
    .{ "decompressobj", zlib_mod.genDecompressobj },
    .{ "crc32", zlib_mod.genCrc32 },
    .{ "adler32", zlib_mod.genAdler32 },
    .{ "MAX_WBITS", zlib_mod.genMAX_WBITS },
    .{ "DEFLATED", zlib_mod.genDEFLATED },
    .{ "DEF_BUF_SIZE", zlib_mod.genDEF_BUF_SIZE },
    .{ "DEF_MEM_LEVEL", zlib_mod.genDEF_MEM_LEVEL },
    .{ "Z_DEFAULT_STRATEGY", zlib_mod.genZ_DEFAULT_STRATEGY },
    .{ "Z_FILTERED", zlib_mod.genZ_FILTERED },
    .{ "Z_HUFFMAN_ONLY", zlib_mod.genZ_HUFFMAN_ONLY },
    .{ "Z_RLE", zlib_mod.genZ_RLE },
    .{ "Z_FIXED", zlib_mod.genZ_FIXED },
    .{ "Z_NO_COMPRESSION", zlib_mod.genZ_NO_COMPRESSION },
    .{ "Z_BEST_SPEED", zlib_mod.genZ_BEST_SPEED },
    .{ "Z_BEST_COMPRESSION", zlib_mod.genZ_BEST_COMPRESSION },
    .{ "Z_DEFAULT_COMPRESSION", zlib_mod.genZ_DEFAULT_COMPRESSION },
    .{ "error", zlib_mod.genError },
});

/// zipapp module functions
const ZipappFuncs = FuncMap.initComptime(.{
    .{ "create_archive", zipapp_mod.genCreateArchive },
    .{ "get_interpreter", zipapp_mod.genGetInterpreter },
});

/// ensurepip module functions
const EnsurepipFuncs = FuncMap.initComptime(.{
    .{ "version", ensurepip_mod.genVersion },
    .{ "bootstrap", ensurepip_mod.genBootstrap },
    .{ "_main", ensurepip_mod.genMain },
});

/// _string module functions
const StringInternalFuncs = FuncMap.initComptime(.{
    .{ "formatter_field_name_split", _string_mod.genFormatterFieldNameSplit },
    .{ "formatter_parser", _string_mod.genFormatterParser },
});

/// _weakref module functions
const WeakrefInternalFuncs = FuncMap.initComptime(.{
    .{ "ref", _weakref_mod.genRef },
    .{ "proxy", _weakref_mod.genProxy },
    .{ "getweakrefcount", _weakref_mod.genGetweakrefcount },
    .{ "getweakrefs", _weakref_mod.genGetweakrefs },
    .{ "CallableProxyType", _weakref_mod.genCallableProxyType },
    .{ "ProxyType", _weakref_mod.genProxyType },
    .{ "ReferenceType", _weakref_mod.genReferenceType },
});

/// _functools module functions
const FunctoolsInternalFuncs = FuncMap.initComptime(.{
    .{ "reduce", _functools_mod.genReduce },
    .{ "cmp_to_key", _functools_mod.genCmpToKey },
});

/// _operator module functions
const OperatorInternalFuncs = FuncMap.initComptime(.{
    .{ "itemgetter", _operator_mod.genItemgetter },
    .{ "attrgetter", _operator_mod.genAttrgetter },
    .{ "methodcaller", _operator_mod.genMethodcaller },
    .{ "lt", _operator_mod.genLt },
    .{ "le", _operator_mod.genLe },
    .{ "eq", _operator_mod.genEq },
    .{ "ne", _operator_mod.genNe },
    .{ "ge", _operator_mod.genGe },
    .{ "gt", _operator_mod.genGt },
    .{ "add", _operator_mod.genAdd },
    .{ "sub", _operator_mod.genSub },
    .{ "mul", _operator_mod.genMul },
    .{ "truediv", _operator_mod.genTruediv },
    .{ "floordiv", _operator_mod.genFloordiv },
    .{ "mod", _operator_mod.genMod },
    .{ "neg", _operator_mod.genNeg },
    .{ "pos", _operator_mod.genPos },
    .{ "abs", _operator_mod.genAbs },
    .{ "and_", _operator_mod.genAnd_ },
    .{ "or_", _operator_mod.genOr_ },
    .{ "xor", _operator_mod.genXor },
    .{ "invert", _operator_mod.genInvert },
    .{ "lshift", _operator_mod.genLshift },
    .{ "rshift", _operator_mod.genRshift },
    .{ "not_", _operator_mod.genNot_ },
    .{ "truth", _operator_mod.genTruth },
    .{ "concat", _operator_mod.genConcat },
    .{ "contains", _operator_mod.genContains },
    .{ "countOf", _operator_mod.genCountOf },
    .{ "indexOf", _operator_mod.genIndexOf },
    .{ "getitem", _operator_mod.genGetitem },
    .{ "length_hint", _operator_mod.genLength_hint },
    .{ "is_", _operator_mod.genIs_ },
    .{ "is_not", _operator_mod.genIs_not },
    .{ "index", _operator_mod.genIndex },
});

/// _json module functions
const JsonInternalFuncs = FuncMap.initComptime(.{
    .{ "encode_basestring", _json_mod.genEncodeBasestring },
    .{ "encode_basestring_ascii", _json_mod.genEncodeBasestringAscii },
    .{ "scanstring", _json_mod.genScanstring },
    .{ "make_encoder", _json_mod.genMakeEncoder },
    .{ "make_scanner", _json_mod.genMakeScanner },
});

/// _codecs module functions
const CodecsInternalFuncs = FuncMap.initComptime(.{
    .{ "encode", _codecs_mod.genEncode },
    .{ "decode", _codecs_mod.genDecode },
    .{ "register", _codecs_mod.genRegister },
    .{ "lookup", _codecs_mod.genLookup },
    .{ "register_error", _codecs_mod.genRegisterError },
    .{ "lookup_error", _codecs_mod.genLookupError },
    .{ "utf_8_encode", _codecs_mod.genUtf8Encode },
    .{ "utf_8_decode", _codecs_mod.genUtf8Decode },
    .{ "ascii_encode", _codecs_mod.genAsciiEncode },
    .{ "ascii_decode", _codecs_mod.genAsciiDecode },
    .{ "latin_1_encode", _codecs_mod.genLatin1Encode },
    .{ "latin_1_decode", _codecs_mod.genLatin1Decode },
    .{ "escape_encode", _codecs_mod.genEscapeEncode },
    .{ "escape_decode", _codecs_mod.genEscapeDecode },
    .{ "raw_unicode_escape_encode", _codecs_mod.genRawUnicodeEscapeEncode },
    .{ "raw_unicode_escape_decode", _codecs_mod.genRawUnicodeEscapeDecode },
    .{ "unicode_escape_encode", _codecs_mod.genUnicodeEscapeEncode },
    .{ "unicode_escape_decode", _codecs_mod.genUnicodeEscapeDecode },
    .{ "charmap_encode", _codecs_mod.genCharmapEncode },
    .{ "charmap_decode", _codecs_mod.genCharmapDecode },
    .{ "charmap_build", _codecs_mod.genCharmapBuild },
    .{ "mbcs_encode", _codecs_mod.genMbcsEncode },
    .{ "mbcs_decode", _codecs_mod.genMbcsDecode },
    .{ "readbuffer_encode", _codecs_mod.genReadbufferEncode },
});

/// _collections module functions
const CollectionsInternalFuncs = FuncMap.initComptime(.{
    .{ "deque", _collections_mod.genDeque },
    .{ "_deque_iterator", _collections_mod.genDequeIterator },
    .{ "_deque_reverse_iterator", _collections_mod.genDequeReverseIterator },
    .{ "_count_elements", _collections_mod.genCountElements },
});

/// _stat module functions
const StatInternalFuncs = FuncMap.initComptime(.{
    .{ "S_IFMT", _stat_mod.genS_IFMT },
    .{ "S_IFDIR", _stat_mod.genS_IFDIR },
    .{ "S_IFCHR", _stat_mod.genS_IFCHR },
    .{ "S_IFBLK", _stat_mod.genS_IFBLK },
    .{ "S_IFREG", _stat_mod.genS_IFREG },
    .{ "S_IFIFO", _stat_mod.genS_IFIFO },
    .{ "S_IFLNK", _stat_mod.genS_IFLNK },
    .{ "S_IFSOCK", _stat_mod.genS_IFSOCK },
    .{ "S_ISUID", _stat_mod.genS_ISUID },
    .{ "S_ISGID", _stat_mod.genS_ISGID },
    .{ "S_ISVTX", _stat_mod.genS_ISVTX },
    .{ "S_IRWXU", _stat_mod.genS_IRWXU },
    .{ "S_IRUSR", _stat_mod.genS_IRUSR },
    .{ "S_IWUSR", _stat_mod.genS_IWUSR },
    .{ "S_IXUSR", _stat_mod.genS_IXUSR },
    .{ "S_IRWXG", _stat_mod.genS_IRWXG },
    .{ "S_IRGRP", _stat_mod.genS_IRGRP },
    .{ "S_IWGRP", _stat_mod.genS_IWGRP },
    .{ "S_IXGRP", _stat_mod.genS_IXGRP },
    .{ "S_IRWXO", _stat_mod.genS_IRWXO },
    .{ "S_IROTH", _stat_mod.genS_IROTH },
    .{ "S_IWOTH", _stat_mod.genS_IWOTH },
    .{ "S_IXOTH", _stat_mod.genS_IXOTH },
    .{ "S_ISDIR", _stat_mod.genS_ISDIR },
    .{ "S_ISCHR", _stat_mod.genS_ISCHR },
    .{ "S_ISBLK", _stat_mod.genS_ISBLK },
    .{ "S_ISREG", _stat_mod.genS_ISREG },
    .{ "S_ISFIFO", _stat_mod.genS_ISFIFO },
    .{ "S_ISLNK", _stat_mod.genS_ISLNK },
    .{ "S_ISSOCK", _stat_mod.genS_ISSOCK },
    .{ "S_IMODE", _stat_mod.genS_IMODE },
    .{ "filemode", _stat_mod.genFilemode },
    .{ "ST_MODE", _stat_mod.genST_MODE },
    .{ "ST_INO", _stat_mod.genST_INO },
    .{ "ST_DEV", _stat_mod.genST_DEV },
    .{ "ST_NLINK", _stat_mod.genST_NLINK },
    .{ "ST_UID", _stat_mod.genST_UID },
    .{ "ST_GID", _stat_mod.genST_GID },
    .{ "ST_SIZE", _stat_mod.genST_SIZE },
    .{ "ST_ATIME", _stat_mod.genST_ATIME },
    .{ "ST_MTIME", _stat_mod.genST_MTIME },
    .{ "ST_CTIME", _stat_mod.genST_CTIME },
    .{ "FILE_ATTRIBUTE_ARCHIVE", _stat_mod.genFILE_ATTRIBUTE_ARCHIVE },
    .{ "FILE_ATTRIBUTE_COMPRESSED", _stat_mod.genFILE_ATTRIBUTE_COMPRESSED },
    .{ "FILE_ATTRIBUTE_DEVICE", _stat_mod.genFILE_ATTRIBUTE_DEVICE },
    .{ "FILE_ATTRIBUTE_DIRECTORY", _stat_mod.genFILE_ATTRIBUTE_DIRECTORY },
    .{ "FILE_ATTRIBUTE_ENCRYPTED", _stat_mod.genFILE_ATTRIBUTE_ENCRYPTED },
    .{ "FILE_ATTRIBUTE_HIDDEN", _stat_mod.genFILE_ATTRIBUTE_HIDDEN },
    .{ "FILE_ATTRIBUTE_NORMAL", _stat_mod.genFILE_ATTRIBUTE_NORMAL },
    .{ "FILE_ATTRIBUTE_NOT_CONTENT_INDEXED", _stat_mod.genFILE_ATTRIBUTE_NOT_CONTENT_INDEXED },
    .{ "FILE_ATTRIBUTE_OFFLINE", _stat_mod.genFILE_ATTRIBUTE_OFFLINE },
    .{ "FILE_ATTRIBUTE_READONLY", _stat_mod.genFILE_ATTRIBUTE_READONLY },
    .{ "FILE_ATTRIBUTE_REPARSE_POINT", _stat_mod.genFILE_ATTRIBUTE_REPARSE_POINT },
    .{ "FILE_ATTRIBUTE_SPARSE_FILE", _stat_mod.genFILE_ATTRIBUTE_SPARSE_FILE },
    .{ "FILE_ATTRIBUTE_SYSTEM", _stat_mod.genFILE_ATTRIBUTE_SYSTEM },
    .{ "FILE_ATTRIBUTE_TEMPORARY", _stat_mod.genFILE_ATTRIBUTE_TEMPORARY },
    .{ "FILE_ATTRIBUTE_VIRTUAL", _stat_mod.genFILE_ATTRIBUTE_VIRTUAL },
});

/// stat module functions (same as _stat)
const StatFuncs = StatInternalFuncs;

/// _heapq module functions
const HeapqInternalFuncs = FuncMap.initComptime(.{
    .{ "heappush", _heapq_mod.genHeappush },
    .{ "heappop", _heapq_mod.genHeappop },
    .{ "heapify", _heapq_mod.genHeapify },
    .{ "heapreplace", _heapq_mod.genHeapreplace },
    .{ "heappushpop", _heapq_mod.genHeappushpop },
    .{ "nlargest", _heapq_mod.genNlargest },
    .{ "nsmallest", _heapq_mod.genNsmallest },
});

/// _bisect module functions
const BisectInternalFuncs = FuncMap.initComptime(.{
    .{ "bisect_left", _bisect_mod.genBisectLeft },
    .{ "bisect_right", _bisect_mod.genBisectRight },
    .{ "bisect", _bisect_mod.genBisectRight },
    .{ "insort_left", _bisect_mod.genInsortLeft },
    .{ "insort_right", _bisect_mod.genInsortRight },
    .{ "insort", _bisect_mod.genInsortRight },
});

/// _random module functions
const RandomInternalFuncs = FuncMap.initComptime(.{
    .{ "Random", _random_mod.genRandom },
    .{ "random", _random_mod.genRandomRandom },
    .{ "seed", _random_mod.genSeed },
    .{ "getstate", _random_mod.genGetstate },
    .{ "setstate", _random_mod.genSetstate },
    .{ "getrandbits", _random_mod.genGetrandbits },
});

/// _struct module functions
const StructInternalFuncs = FuncMap.initComptime(.{
    .{ "pack", _struct_mod.genPack },
    .{ "pack_into", _struct_mod.genPackInto },
    .{ "unpack", _struct_mod.genUnpack },
    .{ "unpack_from", _struct_mod.genUnpackFrom },
    .{ "iter_unpack", _struct_mod.genIterUnpack },
    .{ "calcsize", _struct_mod.genCalcsize },
    .{ "Struct", _struct_mod.genStruct },
    .{ "error", _struct_mod.genError },
});

/// _pickle module functions
const PickleInternalFuncs = FuncMap.initComptime(.{
    .{ "dumps", _pickle_mod.genDumps },
    .{ "dump", _pickle_mod.genDump },
    .{ "loads", _pickle_mod.genLoads },
    .{ "load", _pickle_mod.genLoad },
    .{ "Pickler", _pickle_mod.genPickler },
    .{ "Unpickler", _pickle_mod.genUnpickler },
    .{ "HIGHEST_PROTOCOL", _pickle_mod.genHIGHEST_PROTOCOL },
    .{ "DEFAULT_PROTOCOL", _pickle_mod.genDEFAULT_PROTOCOL },
    .{ "PickleError", _pickle_mod.genPickleError },
    .{ "PicklingError", _pickle_mod.genPicklingError },
    .{ "UnpicklingError", _pickle_mod.genUnpicklingError },
});

/// _datetime module functions
const DatetimeInternalFuncs = FuncMap.initComptime(.{
    .{ "datetime", _datetime_mod.genDatetime },
    .{ "date", _datetime_mod.genDate },
    .{ "time", _datetime_mod.genTime },
    .{ "timedelta", _datetime_mod.genTimedelta },
    .{ "timezone", _datetime_mod.genTimezone },
    .{ "MINYEAR", _datetime_mod.genMINYEAR },
    .{ "MAXYEAR", _datetime_mod.genMAXYEAR },
    .{ "timezone_utc", _datetime_mod.genTimezoneUtc },
});

/// _csv module functions
const CsvInternalFuncs = FuncMap.initComptime(.{
    .{ "reader", _csv_mod.genReader },
    .{ "writer", _csv_mod.genWriter },
    .{ "register_dialect", _csv_mod.genRegisterDialect },
    .{ "unregister_dialect", _csv_mod.genUnregisterDialect },
    .{ "get_dialect", _csv_mod.genGetDialect },
    .{ "list_dialects", _csv_mod.genListDialects },
    .{ "field_size_limit", _csv_mod.genFieldSizeLimit },
    .{ "QUOTE_ALL", _csv_mod.genQUOTE_ALL },
    .{ "QUOTE_MINIMAL", _csv_mod.genQUOTE_MINIMAL },
    .{ "QUOTE_NONNUMERIC", _csv_mod.genQUOTE_NONNUMERIC },
    .{ "QUOTE_NONE", _csv_mod.genQUOTE_NONE },
    .{ "Error", _csv_mod.genError },
});

/// _socket module functions
const SocketInternalFuncs = FuncMap.initComptime(.{
    .{ "socket", _socket_mod.genSocket },
    .{ "getaddrinfo", _socket_mod.genGetaddrinfo },
    .{ "getnameinfo", _socket_mod.genGetnameinfo },
    .{ "gethostname", _socket_mod.genGethostname },
    .{ "gethostbyname", _socket_mod.genGethostbyname },
    .{ "gethostbyname_ex", _socket_mod.genGethostbynameEx },
    .{ "gethostbyaddr", _socket_mod.genGethostbyaddr },
    .{ "getfqdn", _socket_mod.genGetfqdn },
    .{ "getservbyname", _socket_mod.genGetservbyname },
    .{ "getservbyport", _socket_mod.genGetservbyport },
    .{ "getprotobyname", _socket_mod.genGetprotobyname },
    .{ "getdefaulttimeout", _socket_mod.genGetdefaulttimeout },
    .{ "setdefaulttimeout", _socket_mod.genSetdefaulttimeout },
    .{ "ntohs", _socket_mod.genNtohs },
    .{ "ntohl", _socket_mod.genNtohl },
    .{ "htons", _socket_mod.genHtons },
    .{ "htonl", _socket_mod.genHtonl },
    .{ "inet_aton", _socket_mod.genInetAton },
    .{ "inet_ntoa", _socket_mod.genInetNtoa },
    .{ "inet_pton", _socket_mod.genInetPton },
    .{ "inet_ntop", _socket_mod.genInetNtop },
    .{ "AF_INET", _socket_mod.genAF_INET },
    .{ "AF_INET6", _socket_mod.genAF_INET6 },
    .{ "AF_UNIX", _socket_mod.genAF_UNIX },
    .{ "SOCK_STREAM", _socket_mod.genSOCK_STREAM },
    .{ "SOCK_DGRAM", _socket_mod.genSOCK_DGRAM },
    .{ "SOCK_RAW", _socket_mod.genSOCK_RAW },
    .{ "SOL_SOCKET", _socket_mod.genSOL_SOCKET },
    .{ "SO_REUSEADDR", _socket_mod.genSO_REUSEADDR },
    .{ "SO_KEEPALIVE", _socket_mod.genSO_KEEPALIVE },
    .{ "IPPROTO_TCP", _socket_mod.genIPPROTO_TCP },
    .{ "IPPROTO_UDP", _socket_mod.genIPPROTO_UDP },
    .{ "error", _socket_mod.genSocketError },
    .{ "timeout", _socket_mod.genSocketTimeout },
    .{ "gaierror", _socket_mod.genSocketGaierror },
    .{ "herror", _socket_mod.genSocketHerror },
});

/// _hashlib module functions
const HashlibInternalFuncs = FuncMap.initComptime(.{
    .{ "new", _hashlib_mod.genNew },
    .{ "openssl_md5", _hashlib_mod.genOpensslMd5 },
    .{ "openssl_sha1", _hashlib_mod.genOpensslSha1 },
    .{ "openssl_sha224", _hashlib_mod.genOpensslSha224 },
    .{ "openssl_sha256", _hashlib_mod.genOpensslSha256 },
    .{ "openssl_sha384", _hashlib_mod.genOpensslSha384 },
    .{ "openssl_sha512", _hashlib_mod.genOpensslSha512 },
    .{ "openssl_sha3_224", _hashlib_mod.genOpensslSha3_224 },
    .{ "openssl_sha3_256", _hashlib_mod.genOpensslSha3_256 },
    .{ "openssl_sha3_384", _hashlib_mod.genOpensslSha3_384 },
    .{ "openssl_sha3_512", _hashlib_mod.genOpensslSha3_512 },
    .{ "openssl_shake_128", _hashlib_mod.genOpensslShake128 },
    .{ "openssl_shake_256", _hashlib_mod.genOpensslShake256 },
    .{ "pbkdf2_hmac", _hashlib_mod.genPbkdf2Hmac },
    .{ "scrypt", _hashlib_mod.genScrypt },
    .{ "hmac_digest", _hashlib_mod.genHmacDigest },
    .{ "compare_digest", _hashlib_mod.genCompareDigest },
    .{ "openssl_md_meth_names", _hashlib_mod.genOpensslMdMethNames },
});

/// _locale module functions
const LocaleInternalFuncs = FuncMap.initComptime(.{
    .{ "setlocale", _locale_mod.genSetlocale },
    .{ "localeconv", _locale_mod.genLocaleconv },
    .{ "getlocale", _locale_mod.genGetlocale },
    .{ "getdefaultlocale", _locale_mod.genGetdefaultlocale },
    .{ "getpreferredencoding", _locale_mod.genGetpreferredencoding },
    .{ "nl_langinfo", _locale_mod.genNlLanginfo },
    .{ "strcoll", _locale_mod.genStrcoll },
    .{ "strxfrm", _locale_mod.genStrxfrm },
    .{ "LC_CTYPE", _locale_mod.genLC_CTYPE },
    .{ "LC_COLLATE", _locale_mod.genLC_COLLATE },
    .{ "LC_TIME", _locale_mod.genLC_TIME },
    .{ "LC_NUMERIC", _locale_mod.genLC_NUMERIC },
    .{ "LC_MONETARY", _locale_mod.genLC_MONETARY },
    .{ "LC_MESSAGES", _locale_mod.genLC_MESSAGES },
    .{ "LC_ALL", _locale_mod.genLC_ALL },
    .{ "CODESET", _locale_mod.genCODESET },
    .{ "D_T_FMT", _locale_mod.genD_T_FMT },
    .{ "D_FMT", _locale_mod.genD_FMT },
    .{ "T_FMT", _locale_mod.genT_FMT },
    .{ "RADIXCHAR", _locale_mod.genRADIXCHAR },
    .{ "THOUSEP", _locale_mod.genTHOUSEP },
    .{ "YESEXPR", _locale_mod.genYESEXPR },
    .{ "NOEXPR", _locale_mod.genNOEXPR },
    .{ "CRNCYSTR", _locale_mod.genCRNCYSTR },
    .{ "ERA", _locale_mod.genERA },
    .{ "ERA_D_T_FMT", _locale_mod.genERA_D_T_FMT },
    .{ "ERA_D_FMT", _locale_mod.genERA_D_FMT },
    .{ "ERA_T_FMT", _locale_mod.genERA_T_FMT },
    .{ "ALT_DIGITS", _locale_mod.genALT_DIGITS },
});

/// _signal module functions
const SignalInternalFuncs = FuncMap.initComptime(.{
    .{ "signal", _signal_mod.genSignal },
    .{ "getsignal", _signal_mod.genGetsignal },
    .{ "raise_signal", _signal_mod.genRaiseSignal },
    .{ "alarm", _signal_mod.genAlarm },
    .{ "pause", _signal_mod.genPause },
    .{ "getitimer", _signal_mod.genGetitimer },
    .{ "setitimer", _signal_mod.genSetitimer },
    .{ "siginterrupt", _signal_mod.genSiginterrupt },
    .{ "set_wakeup_fd", _signal_mod.genSetWakeupFd },
    .{ "sigwait", _signal_mod.genSigwait },
    .{ "pthread_kill", _signal_mod.genPthreadKill },
    .{ "pthread_sigmask", _signal_mod.genPthreadSigmask },
    .{ "sigpending", _signal_mod.genSigpending },
    .{ "valid_signals", _signal_mod.genValidSignals },
    .{ "SIGHUP", _signal_mod.genSIGHUP },
    .{ "SIGINT", _signal_mod.genSIGINT },
    .{ "SIGQUIT", _signal_mod.genSIGQUIT },
    .{ "SIGILL", _signal_mod.genSIGILL },
    .{ "SIGTRAP", _signal_mod.genSIGTRAP },
    .{ "SIGABRT", _signal_mod.genSIGABRT },
    .{ "SIGFPE", _signal_mod.genSIGFPE },
    .{ "SIGKILL", _signal_mod.genSIGKILL },
    .{ "SIGBUS", _signal_mod.genSIGBUS },
    .{ "SIGSEGV", _signal_mod.genSIGSEGV },
    .{ "SIGSYS", _signal_mod.genSIGSYS },
    .{ "SIGPIPE", _signal_mod.genSIGPIPE },
    .{ "SIGALRM", _signal_mod.genSIGALRM },
    .{ "SIGTERM", _signal_mod.genSIGTERM },
    .{ "SIGURG", _signal_mod.genSIGURG },
    .{ "SIGSTOP", _signal_mod.genSIGSTOP },
    .{ "SIGTSTP", _signal_mod.genSIGTSTP },
    .{ "SIGCONT", _signal_mod.genSIGCONT },
    .{ "SIGCHLD", _signal_mod.genSIGCHLD },
    .{ "SIGTTIN", _signal_mod.genSIGTTIN },
    .{ "SIGTTOU", _signal_mod.genSIGTTOU },
    .{ "SIGIO", _signal_mod.genSIGIO },
    .{ "SIGXCPU", _signal_mod.genSIGXCPU },
    .{ "SIGXFSZ", _signal_mod.genSIGXFSZ },
    .{ "SIGVTALRM", _signal_mod.genSIGVTALRM },
    .{ "SIGPROF", _signal_mod.genSIGPROF },
    .{ "SIGWINCH", _signal_mod.genSIGWINCH },
    .{ "SIGINFO", _signal_mod.genSIGINFO },
    .{ "SIGUSR1", _signal_mod.genSIGUSR1 },
    .{ "SIGUSR2", _signal_mod.genSIGUSR2 },
    .{ "SIG_DFL", _signal_mod.genSIG_DFL },
    .{ "SIG_IGN", _signal_mod.genSIG_IGN },
    .{ "ITIMER_REAL", _signal_mod.genITIMER_REAL },
    .{ "ITIMER_VIRTUAL", _signal_mod.genITIMER_VIRTUAL },
    .{ "ITIMER_PROF", _signal_mod.genITIMER_PROF },
    .{ "SIG_BLOCK", _signal_mod.genSIG_BLOCK },
    .{ "SIG_UNBLOCK", _signal_mod.genSIG_UNBLOCK },
    .{ "SIG_SETMASK", _signal_mod.genSIG_SETMASK },
});

/// math module functions
const MathFuncs = FuncMap.initComptime(.{
    .{ "pi", math_mod.genPi },
    .{ "e", math_mod.genE },
    .{ "tau", math_mod.genTau },
    .{ "inf", math_mod.genInf },
    .{ "nan", math_mod.genNan },
    .{ "ceil", math_mod.genCeil },
    .{ "floor", math_mod.genFloor },
    .{ "trunc", math_mod.genTrunc },
    .{ "fabs", math_mod.genFabs },
    .{ "factorial", math_mod.genFactorial },
    .{ "gcd", math_mod.genGcd },
    .{ "lcm", math_mod.genLcm },
    .{ "comb", math_mod.genComb },
    .{ "perm", math_mod.genPerm },
    .{ "sqrt", math_mod.genSqrt },
    .{ "isqrt", math_mod.genIsqrt },
    .{ "exp", math_mod.genExp },
    .{ "exp2", math_mod.genExp2 },
    .{ "expm1", math_mod.genExpm1 },
    .{ "log", math_mod.genLog },
    .{ "log2", math_mod.genLog2 },
    .{ "log10", math_mod.genLog10 },
    .{ "log1p", math_mod.genLog1p },
    .{ "pow", math_mod.genPow },
    .{ "sin", math_mod.genSin },
    .{ "cos", math_mod.genCos },
    .{ "tan", math_mod.genTan },
    .{ "asin", math_mod.genAsin },
    .{ "acos", math_mod.genAcos },
    .{ "atan", math_mod.genAtan },
    .{ "atan2", math_mod.genAtan2 },
    .{ "sinh", math_mod.genSinh },
    .{ "cosh", math_mod.genCosh },
    .{ "tanh", math_mod.genTanh },
    .{ "asinh", math_mod.genAsinh },
    .{ "acosh", math_mod.genAcosh },
    .{ "atanh", math_mod.genAtanh },
    .{ "erf", math_mod.genErf },
    .{ "erfc", math_mod.genErfc },
    .{ "gamma", math_mod.genGamma },
    .{ "lgamma", math_mod.genLgamma },
    .{ "degrees", math_mod.genDegrees },
    .{ "radians", math_mod.genRadians },
    .{ "copysign", math_mod.genCopysign },
    .{ "fmod", math_mod.genFmod },
    .{ "frexp", math_mod.genFrexp },
    .{ "ldexp", math_mod.genLdexp },
    .{ "modf", math_mod.genModf },
    .{ "remainder", math_mod.genRemainder },
    .{ "isfinite", math_mod.genIsfinite },
    .{ "isinf", math_mod.genIsinf },
    .{ "isnan", math_mod.genIsnan },
    .{ "isclose", math_mod.genIsclose },
    .{ "hypot", math_mod.genHypot },
    .{ "dist", math_mod.genDist },
    .{ "fsum", math_mod.genFsum },
    .{ "prod", math_mod.genProd },
    .{ "nextafter", math_mod.genNextafter },
    .{ "ulp", math_mod.genUlp },
});

/// faulthandler module functions
const FaulthandlerFuncs = FuncMap.initComptime(.{
    .{ "enable", faulthandler_mod.genEnable },
    .{ "disable", faulthandler_mod.genDisable },
    .{ "is_enabled", faulthandler_mod.genIsEnabled },
    .{ "dump_traceback", faulthandler_mod.genDumpTraceback },
    .{ "dump_traceback_later", faulthandler_mod.genDumpTracebackLater },
    .{ "cancel_dump_traceback_later", faulthandler_mod.genCancelDumpTracebackLater },
    .{ "register", faulthandler_mod.genRegister },
    .{ "unregister", faulthandler_mod.genUnregister },
});

/// tracemalloc module functions
const TracemallocFuncs = FuncMap.initComptime(.{
    .{ "start", tracemalloc_mod.genStart },
    .{ "stop", tracemalloc_mod.genStop },
    .{ "is_tracing", tracemalloc_mod.genIsTracing },
    .{ "clear_traces", tracemalloc_mod.genClearTraces },
    .{ "get_object_traceback", tracemalloc_mod.genGetObjectTraceback },
    .{ "get_traceback_limit", tracemalloc_mod.genGetTracebackLimit },
    .{ "get_traced_memory", tracemalloc_mod.genGetTracedMemory },
    .{ "reset_peak", tracemalloc_mod.genResetPeak },
    .{ "get_tracemalloc_memory", tracemalloc_mod.genGetTracemallocMemory },
    .{ "take_snapshot", tracemalloc_mod.genTakeSnapshot },
    .{ "Snapshot", tracemalloc_mod.genSnapshot },
    .{ "Statistic", tracemalloc_mod.genStatistic },
    .{ "StatisticDiff", tracemalloc_mod.genStatisticDiff },
    .{ "Trace", tracemalloc_mod.genTrace },
    .{ "Traceback", tracemalloc_mod.genTraceback },
    .{ "Frame", tracemalloc_mod.genFrame },
    .{ "Filter", tracemalloc_mod.genFilter },
    .{ "DomainFilter", tracemalloc_mod.genDomainFilter },
});

/// sysconfig module functions
const SysconfigFuncs = FuncMap.initComptime(.{
    .{ "get_config_vars", sysconfig_mod.genGetConfigVars },
    .{ "get_config_var", sysconfig_mod.genGetConfigVar },
    .{ "get_scheme_names", sysconfig_mod.genGetSchemeNames },
    .{ "get_default_scheme", sysconfig_mod.genGetDefaultScheme },
    .{ "get_preferred_scheme", sysconfig_mod.genGetPreferredScheme },
    .{ "get_path_names", sysconfig_mod.genGetPathNames },
    .{ "get_paths", sysconfig_mod.genGetPaths },
    .{ "get_path", sysconfig_mod.genGetPath },
    .{ "get_python_lib", sysconfig_mod.genGetPythonLib },
    .{ "get_platform", sysconfig_mod.genGetPlatform },
    .{ "get_makefile_filename", sysconfig_mod.genGetMakefileFilename },
    .{ "parse_config_h", sysconfig_mod.genParseConfigH },
    .{ "is_python_build", sysconfig_mod.genIsPythonBuild },
});

/// fileinput module functions
const FileinputFuncs = FuncMap.initComptime(.{
    .{ "input", fileinput_mod.genInput },
    .{ "filename", fileinput_mod.genFilename },
    .{ "fileno", fileinput_mod.genFileno },
    .{ "lineno", fileinput_mod.genLineno },
    .{ "filelineno", fileinput_mod.genFilelineno },
    .{ "isfirstline", fileinput_mod.genIsfirstline },
    .{ "isstdin", fileinput_mod.genIsstdin },
    .{ "nextfile", fileinput_mod.genNextfile },
    .{ "close", fileinput_mod.genClose },
    .{ "FileInput", fileinput_mod.genFileInput },
    .{ "hook_compressed", fileinput_mod.genHookCompressed },
    .{ "hook_encoded", fileinput_mod.genHookEncoded },
});

/// getopt module functions
const GetoptFuncs = FuncMap.initComptime(.{
    .{ "getopt", getopt_mod.genGetopt },
    .{ "gnu_getopt", getopt_mod.genGnuGetopt },
    .{ "GetoptError", getopt_mod.genGetoptError },
    .{ "error", getopt_mod.genError },
});

/// chunk module functions
const ChunkFuncs = FuncMap.initComptime(.{
    .{ "Chunk", chunk_mod.genChunk },
    .{ "getname", chunk_mod.genGetname },
    .{ "getsize", chunk_mod.genGetsize },
    .{ "close", chunk_mod.genClose },
    .{ "isatty", chunk_mod.genIsatty },
    .{ "seek", chunk_mod.genSeek },
    .{ "tell", chunk_mod.genTell },
    .{ "read", chunk_mod.genRead },
    .{ "skip", chunk_mod.genSkip },
});

/// bdb module functions
const BdbFuncs = FuncMap.initComptime(.{
    .{ "Bdb", bdb_mod.genBdb },
    .{ "Breakpoint", bdb_mod.genBreakpoint },
    .{ "effective", bdb_mod.genEffective },
    .{ "checkfuncname", bdb_mod.genCheckfuncname },
    .{ "set_trace", bdb_mod.genSetTrace },
    .{ "BdbQuit", bdb_mod.genBdbQuit },
    .{ "reset", bdb_mod.genReset },
    .{ "trace_dispatch", bdb_mod.genTraceDispatch },
    .{ "dispatch_line", bdb_mod.genDispatchLine },
    .{ "dispatch_call", bdb_mod.genDispatchCall },
    .{ "dispatch_return", bdb_mod.genDispatchReturn },
    .{ "dispatch_exception", bdb_mod.genDispatchException },
    .{ "is_skipped_module", bdb_mod.genIsSkippedModule },
    .{ "stop_here", bdb_mod.genStopHere },
    .{ "break_here", bdb_mod.genBreakHere },
    .{ "break_anywhere", bdb_mod.genBreakAnywhere },
    .{ "set_step", bdb_mod.genSetStep },
    .{ "set_next", bdb_mod.genSetNext },
    .{ "set_return", bdb_mod.genSetReturn },
    .{ "set_until", bdb_mod.genSetUntil },
    .{ "set_continue", bdb_mod.genSetContinue },
    .{ "set_quit", bdb_mod.genSetQuit },
    .{ "set_break", bdb_mod.genSetBreak },
    .{ "clear_break", bdb_mod.genClearBreak },
    .{ "clear_bpbynumber", bdb_mod.genClearBpbynumber },
    .{ "clear_all_file_breaks", bdb_mod.genClearAllFileBreaks },
    .{ "clear_all_breaks", bdb_mod.genClearAllBreaks },
    .{ "get_bpbynumber", bdb_mod.genGetBpbynumber },
    .{ "get_break", bdb_mod.genGetBreak },
    .{ "get_breaks", bdb_mod.genGetBreaks },
    .{ "get_file_breaks", bdb_mod.genGetFileBreaks },
    .{ "get_all_breaks", bdb_mod.genGetAllBreaks },
    .{ "get_stack", bdb_mod.genGetStack },
    .{ "format_stack_entry", bdb_mod.genFormatStackEntry },
    .{ "run", bdb_mod.genRun },
    .{ "runeval", bdb_mod.genRuneval },
    .{ "runctx", bdb_mod.genRunctx },
    .{ "runcall", bdb_mod.genRuncall },
    .{ "canonic", bdb_mod.genCanonic },
});

/// pstats module functions
const PstatsFuncs = FuncMap.initComptime(.{
    .{ "Stats", pstats_mod.genStats },
    .{ "SortKey", pstats_mod.genSortKey },
    .{ "strip_dirs", pstats_mod.genStripDirs },
    .{ "add", pstats_mod.genAdd },
    .{ "dump_stats", pstats_mod.genDumpStats },
    .{ "sort_stats", pstats_mod.genSortStats },
    .{ "reverse_order", pstats_mod.genReverseOrder },
    .{ "print_stats", pstats_mod.genPrintStats },
    .{ "print_callers", pstats_mod.genPrintCallers },
    .{ "print_callees", pstats_mod.genPrintCallees },
    .{ "get_stats_profile", pstats_mod.genGetStatsProfile },
    .{ "FunctionProfile", pstats_mod.genFunctionProfile },
    .{ "StatsProfile", pstats_mod.genStatsProfile },
});

/// unicodedata module functions
const UnicodedataFuncs = FuncMap.initComptime(.{
    .{ "lookup", unicodedata_mod.genLookup },
    .{ "name", unicodedata_mod.genName },
    .{ "decimal", unicodedata_mod.genDecimal },
    .{ "digit", unicodedata_mod.genDigit },
    .{ "numeric", unicodedata_mod.genNumeric },
    .{ "category", unicodedata_mod.genCategory },
    .{ "bidirectional", unicodedata_mod.genBidirectional },
    .{ "combining", unicodedata_mod.genCombining },
    .{ "east_asian_width", unicodedata_mod.genEastAsianWidth },
    .{ "mirrored", unicodedata_mod.genMirrored },
    .{ "decomposition", unicodedata_mod.genDecomposition },
    .{ "normalize", unicodedata_mod.genNormalize },
    .{ "is_normalized", unicodedata_mod.genIsNormalized },
    .{ "unidata_version", unicodedata_mod.genUnidataVersion },
    .{ "ucd_3_2_0", unicodedata_mod.genUcd320 },
});

/// zoneinfo module functions
const ZoneinfoFuncs = FuncMap.initComptime(.{
    .{ "ZoneInfo", zoneinfo_mod.genZoneInfo },
    .{ "available_timezones", zoneinfo_mod.genAvailableTimezones },
    .{ "reset_tzpath", zoneinfo_mod.genResetTzpath },
    .{ "TZPATH", zoneinfo_mod.genTZPATH },
    .{ "key", zoneinfo_mod.genKey },
    .{ "utcoffset", zoneinfo_mod.genUtcoffset },
    .{ "tzname", zoneinfo_mod.genTzname },
    .{ "dst", zoneinfo_mod.genDst },
    .{ "fromutc", zoneinfo_mod.genFromutc },
    .{ "no_cache", zoneinfo_mod.genNoCache },
    .{ "clear_cache", zoneinfo_mod.genClearCache },
    .{ "ZoneInfoNotFoundError", zoneinfo_mod.genZoneInfoNotFoundError },
    .{ "InvalidTZPathWarning", zoneinfo_mod.genInvalidTZPathWarning },
});

/// tomllib module functions
const TomllibFuncs = FuncMap.initComptime(.{
    .{ "load", tomllib_mod.genLoad },
    .{ "loads", tomllib_mod.genLoads },
    .{ "TOMLDecodeError", tomllib_mod.genTOMLDecodeError },
});

/// webbrowser module functions
const WebbrowserFuncs = FuncMap.initComptime(.{
    .{ "open", webbrowser_mod.genOpen },
    .{ "open_new", webbrowser_mod.genOpenNew },
    .{ "open_new_tab", webbrowser_mod.genOpenNewTab },
    .{ "get", webbrowser_mod.genGet },
    .{ "register", webbrowser_mod.genRegister },
    .{ "Error", webbrowser_mod.genError },
    .{ "BaseBrowser", webbrowser_mod.genBaseBrowser },
    .{ "GenericBrowser", webbrowser_mod.genGenericBrowser },
    .{ "BackgroundBrowser", webbrowser_mod.genBackgroundBrowser },
    .{ "UnixBrowser", webbrowser_mod.genUnixBrowser },
    .{ "Mozilla", webbrowser_mod.genMozilla },
    .{ "Netscape", webbrowser_mod.genNetscape },
    .{ "Galeon", webbrowser_mod.genGaleon },
    .{ "Chrome", webbrowser_mod.genChrome },
    .{ "Chromium", webbrowser_mod.genChromium },
    .{ "Opera", webbrowser_mod.genOpera },
    .{ "Elinks", webbrowser_mod.genElinks },
    .{ "Konqueror", webbrowser_mod.genKonqueror },
    .{ "Grail", webbrowser_mod.genGrail },
    .{ "MacOSX", webbrowser_mod.genMacOSX },
    .{ "MacOSXOSAScript", webbrowser_mod.genMacOSXOSAScript },
    .{ "WindowsDefault", webbrowser_mod.genWindowsDefault },
});

/// modulefinder module functions
const ModulefinderFuncs = FuncMap.initComptime(.{
    .{ "ModuleFinder", modulefinder_mod.genModuleFinder },
    .{ "msg", modulefinder_mod.genMsg },
    .{ "msgin", modulefinder_mod.genMsgin },
    .{ "msgout", modulefinder_mod.genMsgout },
    .{ "run_script", modulefinder_mod.genRunScript },
    .{ "load_file", modulefinder_mod.genLoadFile },
    .{ "import_hook", modulefinder_mod.genImportHook },
    .{ "determine_parent", modulefinder_mod.genDetermineParent },
    .{ "find_head_package", modulefinder_mod.genFindHeadPackage },
    .{ "load_tail", modulefinder_mod.genLoadTail },
    .{ "ensure_fromlist", modulefinder_mod.genEnsureFromlist },
    .{ "find_all_submodules", modulefinder_mod.genFindAllSubmodules },
    .{ "import_module", modulefinder_mod.genImportModule },
    .{ "load_module", modulefinder_mod.genLoadModule },
    .{ "scan_code", modulefinder_mod.genScanCode },
    .{ "scan_opcodes", modulefinder_mod.genScanOpcodes },
    .{ "any_missing", modulefinder_mod.genAnyMissing },
    .{ "any_missing_maybe", modulefinder_mod.genAnyMissingMaybe },
    .{ "replace_paths_in_code", modulefinder_mod.genReplacePathsInCode },
    .{ "report", modulefinder_mod.genReport },
    .{ "Module", modulefinder_mod.genModule },
    .{ "ReplacePackage", modulefinder_mod.genReplacePackage },
    .{ "AddPackagePath", modulefinder_mod.genAddPackagePath },
});

/// pyclbr module functions
const PyclbrFuncs = FuncMap.initComptime(.{
    .{ "readmodule", pyclbr_mod.genReadmodule },
    .{ "readmodule_ex", pyclbr_mod.genReadmoduleEx },
    .{ "Class", pyclbr_mod.genClass },
    .{ "Function", pyclbr_mod.genFunction },
});

/// tabnanny module functions
const TabnannyFuncs = FuncMap.initComptime(.{
    .{ "check", tabnanny_mod.genCheck },
    .{ "process_tokens", tabnanny_mod.genProcessTokens },
    .{ "NannyNag", tabnanny_mod.genNannyNag },
    .{ "verbose", tabnanny_mod.genVerbose },
    .{ "filename_only", tabnanny_mod.genFilenameOnly },
});

/// stringprep module functions
const StringprepFuncs = FuncMap.initComptime(.{
    .{ "in_table_a1", stringprep_mod.genInTableA1 },
    .{ "in_table_b1", stringprep_mod.genInTableB1 },
    .{ "map_table_b2", stringprep_mod.genMapTableB2 },
    .{ "map_table_b3", stringprep_mod.genMapTableB3 },
    .{ "in_table_c11", stringprep_mod.genInTableC11 },
    .{ "in_table_c12", stringprep_mod.genInTableC12 },
    .{ "in_table_c11_c12", stringprep_mod.genInTableC11C12 },
    .{ "in_table_c21", stringprep_mod.genInTableC21 },
    .{ "in_table_c22", stringprep_mod.genInTableC22 },
    .{ "in_table_c21_c22", stringprep_mod.genInTableC21C22 },
    .{ "in_table_c3", stringprep_mod.genInTableC3 },
    .{ "in_table_c4", stringprep_mod.genInTableC4 },
    .{ "in_table_c5", stringprep_mod.genInTableC5 },
    .{ "in_table_c6", stringprep_mod.genInTableC6 },
    .{ "in_table_c7", stringprep_mod.genInTableC7 },
    .{ "in_table_c8", stringprep_mod.genInTableC8 },
    .{ "in_table_c9", stringprep_mod.genInTableC9 },
    .{ "in_table_d1", stringprep_mod.genInTableD1 },
    .{ "in_table_d2", stringprep_mod.genInTableD2 },
});

/// pickletools module functions
const PickletoolsFuncs = FuncMap.initComptime(.{
    .{ "dis", pickletools_mod.genDis },
    .{ "genops", pickletools_mod.genGenops },
    .{ "optimize", pickletools_mod.genOptimize },
    .{ "OpcodeInfo", pickletools_mod.genOpcodeInfo },
    .{ "opcodes", pickletools_mod.genOpcodes },
    .{ "bytes_types", pickletools_mod.genBytesTypes },
    .{ "UP_TO_NEWLINE", pickletools_mod.genUpToNewline },
    .{ "TAKEN_FROM_ARGUMENT1", pickletools_mod.genTakenFromArgument1 },
    .{ "TAKEN_FROM_ARGUMENT4", pickletools_mod.genTakenFromArgument4 },
    .{ "TAKEN_FROM_ARGUMENT4U", pickletools_mod.genTakenFromArgument4U },
    .{ "TAKEN_FROM_ARGUMENT8U", pickletools_mod.genTakenFromArgument8U },
});

/// pipes module functions
const PipesFuncs = FuncMap.initComptime(.{
    .{ "Template", pipes_mod.genTemplate },
    .{ "reset", pipes_mod.genReset },
    .{ "clone", pipes_mod.genClone },
    .{ "debug", pipes_mod.genDebug },
    .{ "append", pipes_mod.genAppend },
    .{ "prepend", pipes_mod.genPrepend },
    .{ "open", pipes_mod.genOpen },
    .{ "copy", pipes_mod.genCopy },
    .{ "FILEIN_FILEOUT", pipes_mod.genFileInFileOut },
    .{ "STDIN_FILEOUT", pipes_mod.genStdinFileOut },
    .{ "FILEIN_STDOUT", pipes_mod.genFileInStdout },
    .{ "STDIN_STDOUT", pipes_mod.genStdinStdout },
    .{ "quote", pipes_mod.genQuote },
});

/// socketserver module functions
const SocketserverFuncs = FuncMap.initComptime(.{
    .{ "BaseServer", socketserver_mod.genBaseServer },
    .{ "TCPServer", socketserver_mod.genTCPServer },
    .{ "UDPServer", socketserver_mod.genUDPServer },
    .{ "UnixStreamServer", socketserver_mod.genUnixStreamServer },
    .{ "UnixDatagramServer", socketserver_mod.genUnixDatagramServer },
    .{ "ForkingMixIn", socketserver_mod.genForkingMixIn },
    .{ "ThreadingMixIn", socketserver_mod.genThreadingMixIn },
    .{ "ForkingTCPServer", socketserver_mod.genForkingTCPServer },
    .{ "ForkingUDPServer", socketserver_mod.genForkingUDPServer },
    .{ "ThreadingTCPServer", socketserver_mod.genThreadingTCPServer },
    .{ "ThreadingUDPServer", socketserver_mod.genThreadingUDPServer },
    .{ "ThreadingUnixStreamServer", socketserver_mod.genThreadingUnixStreamServer },
    .{ "ThreadingUnixDatagramServer", socketserver_mod.genThreadingUnixDatagramServer },
    .{ "BaseRequestHandler", socketserver_mod.genBaseRequestHandler },
    .{ "StreamRequestHandler", socketserver_mod.genStreamRequestHandler },
    .{ "DatagramRequestHandler", socketserver_mod.genDatagramRequestHandler },
    .{ "serve_forever", socketserver_mod.genServeForever },
    .{ "shutdown", socketserver_mod.genShutdown },
    .{ "handle_request", socketserver_mod.genHandleRequest },
    .{ "server_close", socketserver_mod.genServerClose },
});

/// cgitb module functions
const CgitbFuncs = FuncMap.initComptime(.{
    .{ "enable", cgitb_mod.genEnable },
    .{ "handler", cgitb_mod.genHandler },
    .{ "text", cgitb_mod.genText },
    .{ "html", cgitb_mod.genHtml },
    .{ "reset", cgitb_mod.genReset },
    .{ "Hook", cgitb_mod.genHook },
});

/// optparse module functions
const OptparseFuncs = FuncMap.initComptime(.{
    .{ "OptionParser", optparse_mod.genOptionParser },
    .{ "add_option", optparse_mod.genAddOption },
    .{ "parse_args", optparse_mod.genParseArgs },
    .{ "set_usage", optparse_mod.genSetUsage },
    .{ "set_defaults", optparse_mod.genSetDefaults },
    .{ "get_default_values", optparse_mod.genGetDefaultValues },
    .{ "get_option", optparse_mod.genGetOption },
    .{ "has_option", optparse_mod.genHasOption },
    .{ "remove_option", optparse_mod.genRemoveOption },
    .{ "add_option_group", optparse_mod.genAddOptionGroup },
    .{ "get_option_group", optparse_mod.genGetOptionGroup },
    .{ "print_help", optparse_mod.genPrintHelp },
    .{ "print_usage", optparse_mod.genPrintUsage },
    .{ "print_version", optparse_mod.genPrintVersion },
    .{ "format_help", optparse_mod.genFormatHelp },
    .{ "format_usage", optparse_mod.genFormatUsage },
    .{ "error", optparse_mod.genError },
    .{ "Option", optparse_mod.genOption },
    .{ "OptionGroup", optparse_mod.genOptionGroup },
    .{ "Values", optparse_mod.genValues },
    .{ "OptionError", optparse_mod.genOptionError },
    .{ "OptionConflictError", optparse_mod.genOptionConflictError },
    .{ "OptionValueError", optparse_mod.genOptionValueError },
    .{ "BadOptionError", optparse_mod.genBadOptionError },
    .{ "AmbiguousOptionError", optparse_mod.genAmbiguousOptionError },
    .{ "HelpFormatter", optparse_mod.genHelpFormatter },
    .{ "IndentedHelpFormatter", optparse_mod.genIndentedHelpFormatter },
    .{ "TitledHelpFormatter", optparse_mod.genTitledHelpFormatter },
    .{ "SUPPRESS_HELP", optparse_mod.genSuppressHelp },
    .{ "SUPPRESS_USAGE", optparse_mod.genSuppressUsage },
    .{ "NO_DEFAULT", optparse_mod.genNoDefault },
});

/// sre_compile module functions
const SreCompileFuncs = FuncMap.initComptime(.{
    .{ "compile", sre_compile_mod.genCompile },
    .{ "isstring", sre_compile_mod.genIsstring },
    .{ "MAXCODE", sre_compile_mod.genMaxcode },
    .{ "MAXGROUPS", sre_compile_mod.genMaxgroups },
    .{ "_code", sre_compile_mod.genCode },
    .{ "_compile", sre_compile_mod.genInternalCompile },
    .{ "_compile_charset", sre_compile_mod.genCompileCharset },
    .{ "_optimize_charset", sre_compile_mod.genOptimizeCharset },
    .{ "_generate_overlap_table", sre_compile_mod.genGenerateOverlapTable },
    .{ "_compile_info", sre_compile_mod.genCompileInfo },
    .{ "SRE_FLAG_TEMPLATE", sre_compile_mod.genSreFlagTemplate },
    .{ "SRE_FLAG_IGNORECASE", sre_compile_mod.genSreFlagIgnorecase },
    .{ "SRE_FLAG_LOCALE", sre_compile_mod.genSreFlagLocale },
    .{ "SRE_FLAG_MULTILINE", sre_compile_mod.genSreFlagMultiline },
    .{ "SRE_FLAG_DOTALL", sre_compile_mod.genSreFlagDotall },
    .{ "SRE_FLAG_UNICODE", sre_compile_mod.genSreFlagUnicode },
    .{ "SRE_FLAG_VERBOSE", sre_compile_mod.genSreFlagVerbose },
    .{ "SRE_FLAG_DEBUG", sre_compile_mod.genSreFlagDebug },
    .{ "SRE_FLAG_ASCII", sre_compile_mod.genSreFlagAscii },
});

/// sre_constants module functions
const SreConstantsFuncs = FuncMap.initComptime(.{
    .{ "MAGIC", sre_constants_mod.genMagic },
    .{ "MAXREPEAT", sre_constants_mod.genMaxrepeat },
    .{ "MAXGROUPS", sre_constants_mod.genMaxgroups },
    .{ "OPCODES", sre_constants_mod.genOpcodes },
    .{ "ATCODES", sre_constants_mod.genAtcodes },
    .{ "CHCODES", sre_constants_mod.genChcodes },
    .{ "FAILURE", sre_constants_mod.genFailure },
    .{ "SUCCESS", sre_constants_mod.genSuccess },
    .{ "ANY", sre_constants_mod.genAny },
    .{ "ANY_ALL", sre_constants_mod.genAnyAll },
    .{ "ASSERT", sre_constants_mod.genAssert },
    .{ "ASSERT_NOT", sre_constants_mod.genAssertNot },
    .{ "AT", sre_constants_mod.genAt },
    .{ "BRANCH", sre_constants_mod.genBranch },
    .{ "CALL", sre_constants_mod.genCall },
    .{ "CATEGORY", sre_constants_mod.genCategory },
    .{ "CHARSET", sre_constants_mod.genCharset },
    .{ "BIGCHARSET", sre_constants_mod.genBigcharset },
    .{ "GROUPREF", sre_constants_mod.genGroupref },
    .{ "GROUPREF_EXISTS", sre_constants_mod.genGrouprefExists },
    .{ "IN", sre_constants_mod.genIn },
    .{ "INFO", sre_constants_mod.genInfo },
    .{ "JUMP", sre_constants_mod.genJump },
    .{ "LITERAL", sre_constants_mod.genLiteral },
    .{ "MARK", sre_constants_mod.genMark },
    .{ "MAX_UNTIL", sre_constants_mod.genMaxUntil },
    .{ "MIN_UNTIL", sre_constants_mod.genMinUntil },
    .{ "NOT_LITERAL", sre_constants_mod.genNotLiteral },
    .{ "NEGATE", sre_constants_mod.genNegate },
    .{ "RANGE", sre_constants_mod.genRange },
    .{ "REPEAT", sre_constants_mod.genRepeat },
    .{ "REPEAT_ONE", sre_constants_mod.genRepeatOne },
    .{ "SUBPATTERN", sre_constants_mod.genSubpattern },
    .{ "MIN_REPEAT_ONE", sre_constants_mod.genMinRepeatOne },
    .{ "SRE_FLAG_TEMPLATE", sre_constants_mod.genSreFlagTemplate },
    .{ "SRE_FLAG_IGNORECASE", sre_constants_mod.genSreFlagIgnorecase },
    .{ "SRE_FLAG_LOCALE", sre_constants_mod.genSreFlagLocale },
    .{ "SRE_FLAG_MULTILINE", sre_constants_mod.genSreFlagMultiline },
    .{ "SRE_FLAG_DOTALL", sre_constants_mod.genSreFlagDotall },
    .{ "SRE_FLAG_UNICODE", sre_constants_mod.genSreFlagUnicode },
    .{ "SRE_FLAG_VERBOSE", sre_constants_mod.genSreFlagVerbose },
    .{ "SRE_FLAG_DEBUG", sre_constants_mod.genSreFlagDebug },
    .{ "SRE_FLAG_ASCII", sre_constants_mod.genSreFlagAscii },
    .{ "SRE_INFO_PREFIX", sre_constants_mod.genSreInfoPrefix },
    .{ "SRE_INFO_LITERAL", sre_constants_mod.genSreInfoLiteral },
    .{ "SRE_INFO_CHARSET", sre_constants_mod.genSreInfoCharset },
    .{ "error", sre_constants_mod.genError },
});

/// sre_parse module functions
const SreParseFuncs = FuncMap.initComptime(.{
    .{ "parse", sre_parse_mod.genParse },
    .{ "parse_template", sre_parse_mod.genParseTemplate },
    .{ "expand_template", sre_parse_mod.genExpandTemplate },
    .{ "SubPattern", sre_parse_mod.genSubPattern },
    .{ "Pattern", sre_parse_mod.genPattern },
    .{ "Tokenizer", sre_parse_mod.genTokenizer },
    .{ "getwidth", sre_parse_mod.genGetwidth },
    .{ "SPECIAL_CHARS", sre_parse_mod.genSpecialChars },
    .{ "REPEAT_CHARS", sre_parse_mod.genRepeatChars },
    .{ "DIGITS", sre_parse_mod.genDigits },
    .{ "OCTDIGITS", sre_parse_mod.genOctdigits },
    .{ "HEXDIGITS", sre_parse_mod.genHexdigits },
    .{ "ASCIILETTERS", sre_parse_mod.genAsciiletters },
    .{ "WHITESPACE", sre_parse_mod.genWhitespace },
    .{ "ESCAPES", sre_parse_mod.genEscapes },
    .{ "CATEGORIES", sre_parse_mod.genCategories },
    .{ "FLAGS", sre_parse_mod.genFlags },
    .{ "TYPE_FLAGS", sre_parse_mod.genTypeFlags },
    .{ "GLOBAL_FLAGS", sre_parse_mod.genGlobalFlags },
    .{ "Verbose", sre_parse_mod.genVerbose },
});

/// encodings module functions
const EncodingsFuncs = FuncMap.initComptime(.{
    .{ "search_function", encodings_mod.genSearchFunction },
    .{ "normalize_encoding", encodings_mod.genNormalizeEncoding },
    .{ "CodecInfo", encodings_mod.genCodecInfo },
    .{ "aliases", encodings_mod.genAliases },
});

/// marshal module functions
const MarshalFuncs = FuncMap.initComptime(.{
    .{ "dump", marshal_mod.genDump },
    .{ "dumps", marshal_mod.genDumps },
    .{ "load", marshal_mod.genLoad },
    .{ "loads", marshal_mod.genLoads },
    .{ "version", marshal_mod.genVersion },
});

/// opcode module functions
const OpcodeFuncs = FuncMap.initComptime(.{
    .{ "opname", opcode_mod.genOpname },
    .{ "opmap", opcode_mod.genOpmap },
    .{ "cmp_op", opcode_mod.genCmpOp },
    .{ "hasarg", opcode_mod.genHasarg },
    .{ "hasconst", opcode_mod.genHasconst },
    .{ "hasname", opcode_mod.genHasname },
    .{ "hasjrel", opcode_mod.genHasjrel },
    .{ "hasjabs", opcode_mod.genHasjabs },
    .{ "haslocal", opcode_mod.genHaslocal },
    .{ "hascompare", opcode_mod.genHascompare },
    .{ "hasfree", opcode_mod.genHasfree },
    .{ "hasexc", opcode_mod.genHasexc },
    .{ "HAVE_ARGUMENT", opcode_mod.genHaveArgument },
    .{ "EXTENDED_ARG", opcode_mod.genExtendedArg },
    .{ "stack_effect", opcode_mod.genStackEffect },
    .{ "_specialized_opmap", opcode_mod.genSpecializedOpmap },
    .{ "_intrinsic_1_descs", opcode_mod.genIntrinsic1Descs },
    .{ "_intrinsic_2_descs", opcode_mod.genIntrinsic2Descs },
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
    .{ "multiprocessing", MultiprocessingFuncs },
    .{ "concurrent.futures", ConcurrentFuturesFuncs },
    .{ "ctypes", CtypesFuncs },
    .{ "select", SelectFuncs },
    .{ "signal", SignalFuncs },
    .{ "mmap", MmapFuncs },
    .{ "fcntl", FcntlFuncs },
    .{ "termios", TermiosFuncs },
    .{ "pty", PtyFuncs },
    .{ "tty", TtyFuncs },
    .{ "errno", ErrnoFuncs },
    .{ "resource", ResourceFuncs },
    .{ "grp", GrpFuncs },
    .{ "pwd", PwdFuncs },
    .{ "syslog", SyslogFuncs },
    .{ "curses", CursesFuncs },
    .{ "bz2", Bz2Funcs },
    .{ "lzma", LzmaFuncs },
    .{ "tarfile", TarfileFuncs },
    .{ "shlex", ShlexFuncs },
    .{ "gettext", GettextFuncs },
    .{ "calendar", CalendarFuncs },
    .{ "cmd", CmdFuncs },
    .{ "code", CodeFuncs },
    .{ "codeop", CodeopFuncs },
    .{ "dis", DisFuncs },
    .{ "gc", GcFuncs },
    .{ "ast", AstFuncs },
    .{ "unittest.mock", UnittestMockFuncs },
    .{ "mock", UnittestMockFuncs }, // Also support direct "from mock import ..."
    .{ "doctest", DoctestFuncs },
    .{ "profile", ProfileFuncs },
    .{ "cProfile", CProfileFuncs },
    .{ "pdb", PdbFuncs },
    .{ "timeit", TimeitFuncs },
    .{ "trace", TraceFuncs },
    .{ "binascii", BinasciiFuncs },
    .{ "smtplib", SmtplibFuncs },
    .{ "imaplib", ImaplibFuncs },
    .{ "ftplib", FtplibFuncs },
    .{ "poplib", PoplibFuncs },
    .{ "nntplib", NntplibFuncs },
    .{ "ssl", SslFuncs },
    .{ "selectors", SelectorsFuncs },
    .{ "ipaddress", IpaddressFuncs },
    .{ "telnetlib", TelnetlibFuncs },
    .{ "xmlrpc.client", XmlrpcClientFuncs },
    .{ "xmlrpc.server", XmlrpcServerFuncs },
    .{ "http.cookiejar", HttpCookiejarFuncs },
    .{ "urllib.request", UrllibRequestFuncs },
    .{ "urllib.error", UrllibErrorFuncs },
    .{ "urllib.robotparser", UrllibRobotparserFuncs },
    .{ "cgi", CgiFuncs },
    .{ "wsgiref.simple_server", WsgirefSimpleServerFuncs },
    .{ "wsgiref.util", WsgirefUtilFuncs },
    .{ "wsgiref.headers", WsgirefHeadersFuncs },
    .{ "wsgiref.handlers", WsgirefHandlersFuncs },
    .{ "wsgiref.validate", WsgirefValidateFuncs },
    .{ "audioop", AudioopFuncs },
    .{ "wave", WaveFuncs },
    .{ "aifc", AifcFuncs },
    .{ "sunau", SunauFuncs },
    .{ "sndhdr", SndhdrFuncs },
    .{ "imghdr", ImghdrFuncs },
    .{ "colorsys", ColorsysFuncs },
    .{ "netrc", NetrcFuncs },
    .{ "xdrlib", XdrlibFuncs },
    .{ "plistlib", PlistlibFuncs },
    .{ "rlcompleter", RlcompleterFuncs },
    .{ "readline", ReadlineFuncs },
    .{ "sched", SchedFuncs },
    .{ "mailbox", MailboxFuncs },
    .{ "mailcap", MailcapFuncs },
    .{ "mimetypes", MimetypesFuncs },
    .{ "quopri", QuopriFuncs },
    .{ "uu", UuFuncs },
    .{ "html.parser", HtmlParserFuncs },
    .{ "html.entities", HtmlEntitiesFuncs },
    .{ "xml.sax", XmlSaxFuncs },
    .{ "xml.sax.handler", XmlSaxFuncs },
    .{ "xml.sax.xmlreader", XmlSaxFuncs },
    .{ "xml.dom", XmlDomFuncs },
    .{ "builtins", BuiltinsFuncs },
    .{ "typing_extensions", TypingExtensionsFuncs },
    .{ "importlib", ImportlibFuncs },
    .{ "importlib.abc", ImportlibAbcFuncs },
    .{ "importlib.resources", ImportlibResourcesFuncs },
    .{ "importlib.metadata", ImportlibMetadataFuncs },
    .{ "importlib.util", ImportlibUtilFuncs },
    .{ "importlib.machinery", ImportlibMachineryFuncs },
    .{ "pkgutil", PkgutilFuncs },
    .{ "runpy", RunpyFuncs },
    .{ "venv", VenvFuncs },
    .{ "zipimport", ZipimportFuncs },
    .{ "compileall", CompileallFuncs },
    .{ "py_compile", PyCompileFuncs },
    .{ "contextvars", ContextvarsFuncs },
    .{ "site", SiteFuncs },
    .{ "__future__", FutureFuncs },
    .{ "copyreg", CopyregFuncs },
    .{ "_thread", ThreadFuncs },
    .{ "posixpath", PosixpathFuncs },
    .{ "reprlib", ReprlibFuncs },
    .{ "collections.abc", CollectionsAbcFuncs },
    .{ "_collections_abc", CollectionsAbcFuncs },
    .{ "keyword", KeywordFuncs },
    .{ "token", TokenFuncs },
    .{ "tokenize", TokenizeFuncs },
    .{ "dbm", DbmFuncs },
    .{ "dbm.dumb", DbmDumbFuncs },
    .{ "dbm.gnu", DbmGnuFuncs },
    .{ "dbm.ndbm", DbmNdbmFuncs },
    .{ "symtable", SymtableFuncs },
    .{ "crypt", CryptFuncs },
    .{ "posix", PosixFuncs },
    .{ "_io", IoInternalFuncs },
    .{ "genericpath", GenericpathFuncs },
    .{ "ntpath", NtpathFuncs },
    .{ "zlib", ZlibFuncs },
    .{ "zipapp", ZipappFuncs },
    .{ "ensurepip", EnsurepipFuncs },
    .{ "_string", StringInternalFuncs },
    .{ "_weakref", WeakrefInternalFuncs },
    .{ "_functools", FunctoolsInternalFuncs },
    .{ "_operator", OperatorInternalFuncs },
    .{ "_json", JsonInternalFuncs },
    .{ "_codecs", CodecsInternalFuncs },
    .{ "_collections", CollectionsInternalFuncs },
    .{ "_stat", StatInternalFuncs },
    .{ "stat", StatFuncs },
    .{ "_heapq", HeapqInternalFuncs },
    .{ "_bisect", BisectInternalFuncs },
    .{ "_random", RandomInternalFuncs },
    .{ "_struct", StructInternalFuncs },
    .{ "_pickle", PickleInternalFuncs },
    .{ "_datetime", DatetimeInternalFuncs },
    .{ "_csv", CsvInternalFuncs },
    .{ "_socket", SocketInternalFuncs },
    .{ "_hashlib", HashlibInternalFuncs },
    .{ "_locale", LocaleInternalFuncs },
    .{ "_signal", SignalInternalFuncs },
    .{ "math", MathFuncs },
    .{ "faulthandler", FaulthandlerFuncs },
    .{ "tracemalloc", TracemallocFuncs },
    .{ "sysconfig", SysconfigFuncs },
    .{ "fileinput", FileinputFuncs },
    .{ "getopt", GetoptFuncs },
    .{ "chunk", ChunkFuncs },
    .{ "bdb", BdbFuncs },
    .{ "pstats", PstatsFuncs },
    .{ "unicodedata", UnicodedataFuncs },
    .{ "zoneinfo", ZoneinfoFuncs },
    .{ "tomllib", TomllibFuncs },
    .{ "webbrowser", WebbrowserFuncs },
    .{ "modulefinder", ModulefinderFuncs },
    .{ "pyclbr", PyclbrFuncs },
    .{ "tabnanny", TabnannyFuncs },
    .{ "stringprep", StringprepFuncs },
    .{ "pickletools", PickletoolsFuncs },
    .{ "pipes", PipesFuncs },
    .{ "socketserver", SocketserverFuncs },
    .{ "cgitb", CgitbFuncs },
    .{ "optparse", OptparseFuncs },
    .{ "sre_compile", SreCompileFuncs },
    .{ "sre_constants", SreConstantsFuncs },
    .{ "sre_parse", SreParseFuncs },
    .{ "encodings", EncodingsFuncs },
    .{ "marshal", MarshalFuncs },
    .{ "opcode", OpcodeFuncs },
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

    std.debug.print("[DEBUG] module_functions.tryDispatch: module={s}, func={s}\n", .{ module_name, func_name });

    // O(1) module lookup, then O(1) function lookup
    if (ModuleMap.get(module_name)) |func_map| {
        std.debug.print("[DEBUG]   Module found in ModuleMap\n", .{});
        if (func_map.get(func_name)) |handler| {
            std.debug.print("[DEBUG]   Function found, calling handler\n", .{});
            try handler(self, call.args);
            return true;
        }
        std.debug.print("[DEBUG]   Function NOT found in module\n", .{});
    } else {
        std.debug.print("[DEBUG]   Module NOT found in ModuleMap\n", .{});
    }

    return false;
}
