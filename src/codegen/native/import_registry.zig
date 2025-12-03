//! Import Registry - Centralized Python→Zig module mapping
//!
//! This module manages how Python imports are translated to Zig code.
//! It implements the three-tier strategy:
//!
//! Tier 1 (zig_runtime): Performance-critical modules (json, http, async)
//! Tier 2 (c_library): C library wrappers (sqlite3, zlib, ssl - CPython stdlib only)
//! Tier 3 (compile_python): Pure Python modules (pathlib, urllib)
//!
//! Usage:
//!   var registry = try createDefaultRegistry(allocator);
//!   const info = registry.lookup("json");
//!   const import_code = info.zig_import; // "@import(\"runtime\").json"

const std = @import("std");
const hashmap_helper = @import("hashmap_helper");

/// Strategy for handling Python imports
pub const ImportStrategy = enum {
    /// Use Zig implementation (Tier 1: performance-critical)
    zig_runtime,

    /// Use C library via @cImport (Tier 2: C interop)
    c_library,

    /// Compile Python source (Tier 3: pure Python)
    compile_python,

    /// Not yet supported (error)
    unsupported,
};

/// Function signature metadata for codegen
pub const FunctionMeta = struct {
    /// Function does NOT need allocator as first parameter
    no_alloc: bool = false,
    /// Function returns error union (needs try)
    returns_error: bool = false,
};

/// Information about how to import a Python module
pub const ImportInfo = struct {
    /// Python module name (e.g. "json", "os")
    python_module: []const u8,

    /// Strategy to use
    strategy: ImportStrategy,

    /// Zig import path (e.g. "@import(\"runtime\").json")
    /// Only used for zig_runtime and c_library strategies
    zig_import: ?[]const u8,

    /// C library name for linking (e.g. "openblas")
    /// Only used for c_library strategy
    c_library: ?[]const u8,

    /// Python source path for compilation
    /// Only used for compile_python strategy
    python_source: ?[]const u8,

    /// Whether module needs initialization (e.g., module.init(__global_allocator))
    needs_init: bool = false,

    /// Function metadata (keyed by function name)
    /// Used to determine allocator/try requirements at codegen time
    func_meta: ?*const std.StaticStringMap(FunctionMeta) = null,
};

pub const ImportRegistry = struct {
    allocator: std.mem.Allocator,
    registry: hashmap_helper.StringHashMap(ImportInfo),

    pub fn init(allocator: std.mem.Allocator) ImportRegistry {
        return ImportRegistry{
            .allocator = allocator,
            .registry = hashmap_helper.StringHashMap(ImportInfo).init(allocator),
        };
    }

    pub fn deinit(self: *ImportRegistry) void {
        self.registry.deinit();
    }

    /// Register a Python module mapping
    pub fn register(
        self: *ImportRegistry,
        python_module: []const u8,
        strategy: ImportStrategy,
        zig_import: ?[]const u8,
        c_library: ?[]const u8,
    ) !void {
        try self.registerWithMeta(python_module, strategy, zig_import, c_library, false, null);
    }

    /// Register a Python module mapping with full metadata
    pub fn registerWithMeta(
        self: *ImportRegistry,
        python_module: []const u8,
        strategy: ImportStrategy,
        zig_import: ?[]const u8,
        c_library: ?[]const u8,
        needs_init: bool,
        func_meta: ?*const std.StaticStringMap(FunctionMeta),
    ) !void {
        const info = ImportInfo{
            .python_module = python_module,
            .strategy = strategy,
            .zig_import = zig_import,
            .c_library = c_library,
            .python_source = null,
            .needs_init = needs_init,
            .func_meta = func_meta,
        };
        try self.registry.put(python_module, info);
    }

    /// Get function metadata for a module.function call
    pub fn getFunctionMeta(self: *ImportRegistry, module: []const u8, func_name: []const u8) ?FunctionMeta {
        const info = self.lookup(module) orelse return null;
        const meta_map = info.func_meta orelse return null;
        return meta_map.get(func_name);
    }

    /// Look up how to import a Python module
    pub fn lookup(self: *ImportRegistry, python_module: []const u8) ?ImportInfo {
        return self.registry.get(python_module);
    }

    /// Get Zig import statement for a Python module
    pub fn getImportCode(self: *ImportRegistry, python_module: []const u8) ?[]const u8 {
        const info = self.lookup(python_module) orelse return null;
        return info.zig_import;
    }
};

// ============================================================================
// Function metadata for modules (comptime maps)
// ============================================================================

/// time module: pure functions, no allocator needed
const TimeFuncMeta = std.StaticStringMap(FunctionMeta).initComptime(.{
    .{ "time", FunctionMeta{ .no_alloc = true, .returns_error = false } },
    .{ "monotonic", FunctionMeta{ .no_alloc = true, .returns_error = false } },
    .{ "perf_counter", FunctionMeta{ .no_alloc = true, .returns_error = false } },
    .{ "sleep", FunctionMeta{ .no_alloc = true, .returns_error = false } },
});

/// sys module: pure functions
const SysFuncMeta = std.StaticStringMap(FunctionMeta).initComptime(.{
    .{ "exit", FunctionMeta{ .no_alloc = true, .returns_error = false } },
});

/// math module: all pure functions, no allocator needed
const PureFn = FunctionMeta{ .no_alloc = true, .returns_error = false };
const MathFuncMeta = std.StaticStringMap(FunctionMeta).initComptime(.{
    .{ "sqrt", PureFn },   .{ "sin", PureFn },        .{ "cos", PureFn },
    .{ "tan", PureFn },    .{ "asin", PureFn },       .{ "acos", PureFn },
    .{ "atan", PureFn },   .{ "atan2", PureFn },      .{ "sinh", PureFn },
    .{ "cosh", PureFn },   .{ "tanh", PureFn },       .{ "asinh", PureFn },
    .{ "acosh", PureFn },  .{ "atanh", PureFn },      .{ "log", PureFn },
    .{ "log10", PureFn },  .{ "log2", PureFn },       .{ "log1p", PureFn },
    .{ "exp", PureFn },    .{ "expm1", PureFn },      .{ "pow", PureFn },
    .{ "floor", PureFn },  .{ "ceil", PureFn },       .{ "trunc", PureFn },
    .{ "round", PureFn },  .{ "fabs", PureFn },       .{ "abs", PureFn },
    .{ "fmod", PureFn },   .{ "remainder", PureFn },  .{ "modf", PureFn },
    .{ "hypot", PureFn },  .{ "cbrt", PureFn },       .{ "copysign", PureFn },
    .{ "degrees", PureFn },.{ "radians", PureFn },    .{ "factorial", PureFn },
    .{ "gcd", PureFn },    .{ "lcm", PureFn },        .{ "isnan", PureFn },
    .{ "isinf", PureFn },  .{ "isfinite", PureFn },   .{ "erf", PureFn },
    .{ "erfc", PureFn },   .{ "gamma", PureFn },      .{ "lgamma", PureFn },
});

/// re module: regex functions (all return error unions, match/search return None on no-match)
const ReErrorFn = FunctionMeta{ .no_alloc = false, .returns_error = true };
const ReFuncMeta = std.StaticStringMap(FunctionMeta).initComptime(.{
    .{ "match", ReErrorFn },
    .{ "search", ReErrorFn },
    .{ "compile", ReErrorFn },
    .{ "sub", ReErrorFn },
    .{ "findall", ReErrorFn },
});

/// metal0.tokenizer module: native Zig BPE tokenizer (248x faster than tiktoken)
const TokenizerFuncMeta = std.StaticStringMap(FunctionMeta).initComptime(.{
    .{ "encode", FunctionMeta{ .no_alloc = false, .returns_error = true } },
    .{ "decode", FunctionMeta{ .no_alloc = false, .returns_error = true } },
    .{ "count_tokens", FunctionMeta{ .no_alloc = false, .returns_error = true } },
    .{ "init", FunctionMeta{ .no_alloc = false, .returns_error = true } },
    .{ "load", FunctionMeta{ .no_alloc = false, .returns_error = true } },
});

/// sqlite3 module: C interop functions (no allocator needed, returns errors)
const Sqlite3ErrorFn = FunctionMeta{ .no_alloc = true, .returns_error = true };
const Sqlite3FuncMeta = std.StaticStringMap(FunctionMeta).initComptime(.{
    .{ "connect", Sqlite3ErrorFn },
});


/// zlib module: compression functions (no allocator needed from Python side)
const ZlibFuncMeta = std.StaticStringMap(FunctionMeta).initComptime(.{
    .{ "compress", FunctionMeta{ .no_alloc = true, .returns_error = true } },
    .{ "decompress", FunctionMeta{ .no_alloc = true, .returns_error = true } },
});

// ============================================================================
// Registry initialization
// ============================================================================

/// Initialize registry with built-in Python→Zig mappings
pub fn createDefaultRegistry(allocator: std.mem.Allocator) !ImportRegistry {
    var registry = ImportRegistry.init(allocator);

    // Tier 1: Zig implementations (performance-critical)
    // Note: runtime is imported as @import("./runtime.zig") at module level
    try registry.register("json", .zig_runtime, "runtime.json", null);
    try registry.register("http", .zig_runtime, "runtime.http", null);
    try registry.register("asyncio", .zig_runtime, "runtime.async", null);
    try registry.registerWithMeta("re", .zig_runtime, "runtime.re", null, false, &ReFuncMeta);
    try registry.registerWithMeta("sys", .zig_runtime, "runtime.sys", null, false, &SysFuncMeta);
    try registry.registerWithMeta("time", .zig_runtime, "runtime.time", null, false, &TimeFuncMeta);
    try registry.registerWithMeta("math", .zig_runtime, "runtime.math", null, false, &MathFuncMeta);
    try registry.register("unittest", .zig_runtime, "runtime.unittest", null);

    // Tier 2: C library wrappers (CPython stdlib modules only)
    try registry.registerWithMeta("sqlite3", .c_library, "@import(\"./c_interop/c_interop.zig\").sqlite3", "sqlite3", false, &Sqlite3FuncMeta);
    try registry.registerWithMeta("zlib", .c_library, "@import(\"./c_interop/c_interop.zig\").zlib", "z", false, &ZlibFuncMeta);
    try registry.register("ssl", .c_library, "@import(\"./c_interop/c_interop.zig\").ssl", "ssl");
    try registry.register("hashlib", .zig_runtime, "runtime.hashlib", null); // Uses Zig std.crypto
    try registry.register("io", .zig_runtime, "runtime.io", null); // io.StringIO, io.BytesIO
    try registry.register("struct", .zig_runtime, "std", null); // struct module is inline codegen
    try registry.register("base64", .zig_runtime, "std", null); // base64 uses std.base64
    try registry.register("pickle", .zig_runtime, "runtime.pickle", null);
    try registry.register("hmac", .zig_runtime, "std", null); // hmac uses std.crypto.auth.hmac
    try registry.register("socket", .zig_runtime, "std", null); // socket uses std.posix
    try registry.register("os", .zig_runtime, "std", null); // os uses std.fs and std.process
    try registry.register("random", .zig_runtime, null, null); // random module (inline codegen only)
    try registry.register("collections", .zig_runtime, null, null); // collections module (inline codegen only)
    try registry.register("collections.abc", .zig_runtime, null, null); // collections.abc module (inline codegen only)
    try registry.register("functools", .zig_runtime, "std", null); // functools module
    try registry.register("itertools", .zig_runtime, null, null); // itertools module (inline codegen only)
    try registry.register("logging", .zig_runtime, "std", null); // logging module
    try registry.register("threading", .zig_runtime, "std", null); // threading module
    try registry.register("queue", .zig_runtime, "std", null); // queue module
    try registry.register("copy", .zig_runtime, "std", null); // copy module
    try registry.register("operator", .zig_runtime, null, null); // operator module (inline codegen only)
    try registry.register("typing", .zig_runtime, "runtime.typing", null); // typing module
    try registry.register("ast", .zig_runtime, "runtime.ast_executor", null); // ast module - uses ast_executor for parse/compile
    try registry.register("contextlib", .zig_runtime, "std", null); // contextlib module
    try registry.register("string", .zig_runtime, "std", null); // string module
    try registry.register("_string", .zig_runtime, "std", null); // _string module (internal string formatting)
    try registry.register("_testcapi", .zig_runtime, null, null); // _testcapi module - inline only (dispatch codegen)
    try registry.register("_testbuffer", .zig_runtime, null, null); // _testbuffer module - buffer protocol tests (inline codegen)
    try registry.register("shutil", .zig_runtime, "std", null); // shutil module
    try registry.register("glob", .zig_runtime, "std", null); // glob module
    try registry.register("fnmatch", .zig_runtime, "std", null); // fnmatch module
    try registry.register("secrets", .zig_runtime, "std", null); // secrets module
    try registry.register("csv", .zig_runtime, "std", null); // csv module
    try registry.register("configparser", .zig_runtime, "std", null); // configparser module
    try registry.register("argparse", .zig_runtime, "std", null); // argparse module
    try registry.register("zipfile", .zig_runtime, "std", null); // zipfile module
    try registry.register("gzip", .zig_runtime, "std", "z"); // gzip module (uses zlib)
    try registry.register("textwrap", .zig_runtime, "std", null); // textwrap module
    try registry.register("uuid", .zig_runtime, "std", null); // uuid module
    try registry.register("tempfile", .zig_runtime, "std", null); // tempfile module
    try registry.register("subprocess", .zig_runtime, "std", null); // subprocess module
    try registry.register("heapq", .zig_runtime, "std", null); // heapq module
    try registry.register("bisect", .zig_runtime, "std", null); // bisect module
    try registry.register("statistics", .zig_runtime, "std", null); // statistics module
    try registry.register("decimal", .zig_runtime, null, null); // decimal module - inline only (dispatch codegen)
    try registry.register("fractions", .zig_runtime, "std", null); // fractions module
    try registry.register("cmath", .zig_runtime, "std", null); // cmath module
    try registry.register("html", .zig_runtime, "std", null); // html module
    try registry.register("xml", .zig_runtime, "std", null); // xml module
    try registry.register("email", .zig_runtime, "std", null); // email module
    try registry.register("signal", .zig_runtime, "std", null); // signal module
    try registry.register("multiprocessing", .zig_runtime, "std", null); // multiprocessing module
    try registry.register("operator", .zig_runtime, "std", null); // operator module
    try registry.register("array", .zig_runtime, null, null); // array module - inline only
    try registry.register("weakref", .zig_runtime, "std", null); // weakref module
    try registry.register("types", .zig_runtime, "std", null); // types module
    try registry.register("abc", .zig_runtime, "std", null); // abc module
    try registry.register("inspect", .zig_runtime, "std", null); // inspect module
    try registry.register("dataclasses", .zig_runtime, "std", null); // dataclasses module
    try registry.register("enum", .zig_runtime, "std", null); // enum module
    try registry.register("atexit", .zig_runtime, "std", null); // atexit module
    try registry.register("warnings", .zig_runtime, "std", null); // warnings module
    try registry.register("traceback", .zig_runtime, "std", null); // traceback module
    try registry.register("pprint", .zig_runtime, "std", null); // pprint module
    try registry.register("ctypes", .zig_runtime, "runtime.ctypes", null); // ctypes module - FFI for C libraries
    try registry.register("_ctypes", .zig_runtime, "runtime.ctypes", null); // _ctypes internal module
    try registry.register("platform", .zig_runtime, "std", null); // platform module
    try registry.register("locale", .zig_runtime, "std", null); // locale module
    try registry.register("codecs", .zig_runtime, "std", null); // codecs module
    try registry.register("calendar", .zig_runtime, "std", null); // calendar module
    try registry.register("binascii", .zig_runtime, "std", null); // binascii module
    try registry.register("errno", .zig_runtime, "std", null); // errno module
    try registry.register("gc", .zig_runtime, "std", null); // gc module
    try registry.register("select", .zig_runtime, "std", null); // select module
    try registry.register("mmap", .zig_runtime, "std", null); // mmap module
    try registry.register("fcntl", .zig_runtime, "std", null); // fcntl module
    try registry.register("unicodedata", .zig_runtime, null, null); // unicodedata module - inline only

    // Additional Tier 1: OS and filesystem modules
    try registry.register("pathlib", .zig_runtime, "runtime.pathlib", null);

    // Tier 3: Mark as compile_python (will be handled later)
    try registry.register("urllib", .compile_python, null, null);
    try registry.register("datetime", .zig_runtime, "runtime.datetime", null); // datetime uses runtime.datetime

    // importlib module - static resolution at compile time
    try registry.register("importlib", .zig_runtime, null, null);
    try registry.register("importlib.abc", .zig_runtime, null, null);
    try registry.register("importlib.resources", .zig_runtime, null, null);
    try registry.register("importlib.metadata", .zig_runtime, null, null);
    try registry.register("importlib.util", .zig_runtime, null, null);
    try registry.register("importlib.machinery", .zig_runtime, null, null);

    // Test support modules (for CPython unittest compatibility)
    try registry.register("test", .zig_runtime, "runtime.test_support", null);
    try registry.register("test.support", .zig_runtime, "runtime.test_support", null);
    try registry.register("test.support.os_helper", .zig_runtime, "runtime.test_support.os_helper", null);
    try registry.register("test.support.import_helper", .zig_runtime, "runtime.test_support.import_helper", null);
    try registry.register("test.support.warnings_helper", .zig_runtime, "runtime.test_support.warnings_helper", null);
    try registry.register("test.support.threading_helper", .zig_runtime, "runtime.test_support.threading_helper", null);
    try registry.register("test.support.socket_helper", .zig_runtime, "runtime.test_support.socket_helper", null);
    try registry.register("test.support.script_helper", .zig_runtime, "runtime.test_support.script_helper", null);
    try registry.register("test.support.hashlib_helper", .zig_runtime, "runtime.test_support.hashlib_helper", null);
    try registry.register("test.support.numbers", .zig_runtime, "runtime.test_support.numbers", null);

    // metal0 native libraries (Zig implementations exposed to Python)
    // Usage: from metal0 import tokenizer
    // Note: metal0 itself doesn't need a zig_import - only the submodules do
    try registry.register("metal0", .zig_runtime, null, null);
    try registry.registerWithMeta("metal0.tokenizer", .zig_runtime, "__metal0_tokenizer", null, true, &TokenizerFuncMeta);

    return registry;
}
