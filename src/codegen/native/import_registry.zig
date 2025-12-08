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
const hashmap_helper = @import("utils.hashmap_helper");
const stdlib_modules_gen = @import("stdlib_modules_gen.zig");

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

/// Return type hint for stdlib functions
/// Mirrors TypeHint in function_traits.zig for type flow
pub const ReturnTypeHint = enum {
    void,
    int,
    float,
    bool,
    string,
    list,
    dict,
    tuple,
    none,
    object, // Default - dynamic type
    any,
};

/// Function signature metadata for codegen
pub const FunctionMeta = struct {
    /// Function does NOT need allocator as first parameter
    no_alloc: bool = false,
    /// Function returns error union (needs try)
    returns_error: bool = false,
    /// Return type hint for type inference
    return_type: ReturnTypeHint = .object,
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

    /// Direct import path for DCE-friendly imports (e.g. "runtime.Lib.json")
    /// When set, codegen emits `runtime.Lib.json` instead of `runtime.json`
    /// This enables Zig's dead code elimination for unused modules
    direct_import: ?[]const u8 = null,

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
        try self.registerFull(python_module, strategy, zig_import, null, c_library, false, null);
    }

    /// Register a Python module with DCE-friendly direct import path
    pub fn registerDirect(
        self: *ImportRegistry,
        python_module: []const u8,
        strategy: ImportStrategy,
        zig_import: ?[]const u8,
        direct_import: ?[]const u8,
        c_library: ?[]const u8,
    ) !void {
        try self.registerFull(python_module, strategy, zig_import, direct_import, c_library, false, null);
    }

    /// Register a Python module mapping with full metadata (legacy, no direct_import)
    pub fn registerWithMeta(
        self: *ImportRegistry,
        python_module: []const u8,
        strategy: ImportStrategy,
        zig_import: ?[]const u8,
        c_library: ?[]const u8,
        needs_init: bool,
        func_meta: ?*const std.StaticStringMap(FunctionMeta),
    ) !void {
        try self.registerFull(python_module, strategy, zig_import, null, c_library, needs_init, func_meta);
    }

    /// Register a Python module mapping with full metadata including direct_import
    pub fn registerFull(
        self: *ImportRegistry,
        python_module: []const u8,
        strategy: ImportStrategy,
        zig_import: ?[]const u8,
        direct_import: ?[]const u8,
        c_library: ?[]const u8,
        needs_init: bool,
        func_meta: ?*const std.StaticStringMap(FunctionMeta),
    ) !void {
        const info = ImportInfo{
            .python_module = python_module,
            .strategy = strategy,
            .zig_import = zig_import,
            .direct_import = direct_import,
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
    // direct_import paths enable DCE by using runtime.Lib.xxx instead of runtime.xxx
    try registry.registerDirect("json", .zig_runtime, "runtime.json", "runtime.Lib.json", null);
    try registry.registerDirect("http", .zig_runtime, "runtime.http", "runtime.Lib.http", null);
    try registry.registerDirect("http.client", .zig_runtime, "runtime.http.client", "runtime.Lib.http.client", null);
    try registry.registerDirect("requests", .zig_runtime, "runtime.http", "runtime.Lib.http", null);
    try registry.registerDirect("asyncio", .zig_runtime, "runtime.async", "runtime.Lib.asyncio", null);
    try registry.registerFull("re", .zig_runtime, "runtime.re", "runtime.Lib.re", null, false, &ReFuncMeta);
    try registry.registerFull("sys", .zig_runtime, "runtime.sys", "runtime.Lib.sys", null, false, &SysFuncMeta);
    try registry.registerFull("time", .zig_runtime, "runtime.time", "runtime.Lib.time", null, false, &TimeFuncMeta);
    try registry.registerFull("math", .zig_runtime, "runtime.math", "runtime.Lib.math", null, false, &MathFuncMeta);
    try registry.registerDirect("unittest", .zig_runtime, "runtime.unittest", "runtime.Lib.unittest", null);

    // Tier 2: C library wrappers (CPython stdlib modules only)
    // c_interop modules use c_interop.modules.xxx namespace for DCE
    try registry.registerFull("sqlite3", .c_library, "@import(\"c_interop\").sqlite3", "@import(\"c_interop\").modules.sqlite3", "sqlite3", false, &Sqlite3FuncMeta);
    try registry.registerFull("zlib", .c_library, "@import(\"c_interop\").zlib", "@import(\"c_interop\").modules.zlib", "z", false, &ZlibFuncMeta);
    try registry.registerDirect("ssl", .c_library, "@import(\"c_interop\").ssl", "@import(\"c_interop\").modules.ssl", "ssl");

    // Lib modules with DCE-friendly direct_import paths
    try registry.registerDirect("hashlib", .zig_runtime, "runtime.hashlib", "runtime.Modules.hashlib", null);
    try registry.registerDirect("io", .zig_runtime, "runtime.io", "runtime.Lib.io", null);
    try registry.registerDirect("pickle", .zig_runtime, "runtime.pickle", "runtime.Lib.pickle", null);
    try registry.registerDirect("os", .zig_runtime, "runtime.os", "runtime.Lib.os", null);
    try registry.registerDirect("typing", .zig_runtime, "runtime.typing", "runtime.Lib.typing", null);
    try registry.registerDirect("ctypes", .zig_runtime, "runtime.ctypes", "runtime.Modules.ctypes", null);
    try registry.registerDirect("_ctypes", .zig_runtime, "runtime.ctypes", "runtime.Modules.ctypes", null);
    try registry.registerDirect("pathlib", .zig_runtime, "runtime.pathlib", "runtime.Lib.pathlib", null);
    try registry.registerDirect("datetime", .zig_runtime, "runtime.datetime", "runtime.Lib.datetime", null);
    try registry.registerDirect("calendar", .zig_runtime, "runtime.calendar", "runtime.Lib.calendar", null);
    try registry.registerDirect("itertools", .zig_runtime, "runtime.itertools", "runtime.Lib.itertools", null);

    // Modules that use inline codegen only (no direct_import needed)
    try registry.register("struct", .zig_runtime, "std", null);
    try registry.register("base64", .zig_runtime, "std", null);
    try registry.register("hmac", .zig_runtime, "std", null);
    try registry.register("socket", .zig_runtime, "std", null);
    try registry.register("random", .zig_runtime, null, null);
    try registry.registerDirect("collections", .zig_runtime, null, "runtime.Lib.collections", null);
    try registry.registerDirect("collections.abc", .zig_runtime, null, "runtime.Lib.collections.abc", null);
    try registry.register("functools", .zig_runtime, "std", null);
    try registry.register("logging", .zig_runtime, "std", null);
    try registry.register("threading", .zig_runtime, "std", null);
    try registry.register("queue", .zig_runtime, "std", null);
    try registry.register("copy", .zig_runtime, "std", null);
    try registry.register("operator", .zig_runtime, null, null);
    try registry.register("ast", .zig_runtime, "runtime.ast_executor", null);
    try registry.register("contextlib", .zig_runtime, "std", null);
    try registry.register("string", .zig_runtime, "std", null);
    try registry.register("_string", .zig_runtime, "std", null);
    try registry.register("_testcapi", .zig_runtime, null, null);
    try registry.register("_testbuffer", .zig_runtime, null, null);
    try registry.register("shutil", .zig_runtime, "std", null);
    try registry.register("glob", .zig_runtime, "std", null);
    try registry.register("fnmatch", .zig_runtime, "std", null);
    try registry.register("secrets", .zig_runtime, "std", null);
    try registry.register("csv", .zig_runtime, "std", null);
    try registry.register("configparser", .zig_runtime, "std", null);
    try registry.register("argparse", .zig_runtime, "std", null);
    try registry.register("zipfile", .zig_runtime, "std", null);
    try registry.register("gzip", .zig_runtime, "std", "z");
    try registry.register("textwrap", .zig_runtime, "std", null);
    try registry.register("uuid", .zig_runtime, "std", null);
    try registry.register("tempfile", .zig_runtime, "std", null);
    try registry.register("subprocess", .zig_runtime, "std", null);
    try registry.register("heapq", .zig_runtime, "std", null);
    try registry.register("bisect", .zig_runtime, "std", null);
    try registry.register("statistics", .zig_runtime, "std", null);
    try registry.register("decimal", .zig_runtime, null, null);
    try registry.register("fractions", .zig_runtime, null, null);
    try registry.register("cmath", .zig_runtime, "std", null);
    try registry.register("html", .zig_runtime, "std", null);
    try registry.register("xml", .zig_runtime, "std", null);
    try registry.register("email", .zig_runtime, "std", null);
    try registry.register("signal", .zig_runtime, "std", null);
    try registry.register("multiprocessing", .zig_runtime, "std", null);
    try registry.register("array", .zig_runtime, null, null);
    try registry.register("weakref", .zig_runtime, "std", null);
    try registry.register("types", .zig_runtime, "std", null);
    try registry.register("abc", .zig_runtime, "std", null);
    try registry.register("inspect", .zig_runtime, "std", null);
    try registry.register("dataclasses", .zig_runtime, "std", null);
    try registry.register("enum", .zig_runtime, "std", null);
    try registry.register("atexit", .zig_runtime, "std", null);
    try registry.register("warnings", .zig_runtime, "std", null);
    try registry.register("traceback", .zig_runtime, "std", null);
    try registry.register("pprint", .zig_runtime, "std", null);
    try registry.register("platform", .zig_runtime, "std", null);
    try registry.register("locale", .zig_runtime, "std", null);
    try registry.register("codecs", .zig_runtime, "std", null);
    try registry.register("binascii", .zig_runtime, "std", null);
    try registry.register("errno", .zig_runtime, "std", null);
    try registry.register("gc", .zig_runtime, "std", null);
    try registry.register("select", .zig_runtime, "std", null);
    try registry.register("mmap", .zig_runtime, "std", null);
    try registry.register("fcntl", .zig_runtime, "std", null);
    try registry.register("unicodedata", .zig_runtime, null, null);

    // Tier 3: Mark as compile_python (will be handled later)
    try registry.register("urllib", .compile_python, null, null);

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
    try registry.register("test.list_tests", .zig_runtime, "runtime.list_tests", null);

    // metal0 native libraries (Zig implementations exposed to Python)
    // Usage: from metal0 import tokenizer
    // Note: metal0 itself doesn't need a zig_import - only the submodules do
    try registry.register("metal0", .zig_runtime, null, null);
    try registry.registerWithMeta("metal0.tokenizer", .zig_runtime, "__metal0_tokenizer", null, true, &TokenizerFuncMeta);

    // ========================================================================
    // NOTE: Auto-registration loop REMOVED for DCE
    // ========================================================================
    // The previous loop over stdlib_modules_gen.auto_registrable_modules blocked
    // dead code elimination by referencing all 1250 module name strings at runtime.
    //
    // Modules not in this manual registry are handled via:
    // 1. stdlib_modules_gen.hasModule() - O(1) lookup via StaticStringMap
    // 2. Codegen checks hasModule() and generates appropriate imports
    //
    // This enables Zig's DCE to eliminate unused stdlib modules from the binary.

    return registry;
}
