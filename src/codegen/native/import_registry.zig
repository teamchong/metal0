//! Import Registry - Centralized Python→Zig module mapping
//!
//! This module manages how Python imports are translated to Zig code.
//! It implements the three-tier strategy:
//!
//! Tier 1 (zig_runtime): Performance-critical modules (json, http, async)
//! Tier 2 (c_library): C library wrappers (numpy, sqlite3, ssl)
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
    /// Python module name (e.g. "json", "numpy")
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

    /// Whether module needs initialization (e.g., requests.init(allocator))
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

/// requests module: functions use internal allocator, return errors
const RequestsFuncMeta = std.StaticStringMap(FunctionMeta).initComptime(.{
    .{ "get", FunctionMeta{ .no_alloc = true, .returns_error = true } },
    .{ "post", FunctionMeta{ .no_alloc = true, .returns_error = true } },
    .{ "put", FunctionMeta{ .no_alloc = true, .returns_error = true } },
    .{ "delete", FunctionMeta{ .no_alloc = true, .returns_error = true } },
});

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
    try registry.register("flask", .zig_runtime, "runtime.flask", null);
    // requests: needs_init=true, has function metadata
    try registry.registerWithMeta("requests", .zig_runtime, "runtime.requests", null, true, &RequestsFuncMeta);

    // Tier 2: C library wrappers
    try registry.register("numpy", .c_library, "@import(\"./c_interop/c_interop.zig\").numpy", "blas");
    try registry.register("sqlite3", .c_library, "@import(\"./c_interop/c_interop.zig\").sqlite3", "sqlite3");
    try registry.register("zlib", .c_library, "@import(\"./c_interop/c_interop.zig\").zlib", "z");
    try registry.register("ssl", .c_library, "@import(\"./c_interop/c_interop.zig\").ssl", "ssl");
    try registry.register("hashlib", .zig_runtime, "runtime.hashlib", null); // Uses Zig std.crypto
    try registry.register("struct", .zig_runtime, "std", null); // struct module is inline codegen
    try registry.register("base64", .zig_runtime, "std", null); // base64 uses std.base64
    try registry.register("pickle", .zig_runtime, "std", null); // pickle uses JSON serialization
    try registry.register("hmac", .zig_runtime, "std", null); // hmac uses std.crypto.auth.hmac
    try registry.register("socket", .zig_runtime, "std", null); // socket uses std.posix
    try registry.register("os", .zig_runtime, "std", null); // os uses std.fs and std.process
    try registry.register("random", .zig_runtime, "std", null); // random uses std.Random
    try registry.register("collections", .zig_runtime, "std", null); // collections module
    try registry.register("functools", .zig_runtime, "std", null); // functools module
    try registry.register("itertools", .zig_runtime, "std", null); // itertools module
    try registry.register("copy", .zig_runtime, "std", null); // copy module
    try registry.register("typing", .zig_runtime, "std", null); // typing module (no-ops)
    try registry.register("contextlib", .zig_runtime, "std", null); // contextlib module
    try registry.register("string", .zig_runtime, "std", null); // string module
    try registry.register("shutil", .zig_runtime, "std", null); // shutil module
    try registry.register("glob", .zig_runtime, "std", null); // glob module
    try registry.register("fnmatch", .zig_runtime, "std", null); // fnmatch module
    try registry.register("secrets", .zig_runtime, "std", null); // secrets module
    try registry.register("csv", .zig_runtime, "std", null); // csv module
    try registry.register("configparser", .zig_runtime, "std", null); // configparser module
    try registry.register("argparse", .zig_runtime, "std", null); // argparse module
    try registry.register("zipfile", .zig_runtime, "std", null); // zipfile module
    try registry.register("gzip", .zig_runtime, "std", null); // gzip module
    try registry.register("textwrap", .zig_runtime, "std", null); // textwrap module
    try registry.register("uuid", .zig_runtime, "std", null); // uuid module
    try registry.register("tempfile", .zig_runtime, "std", null); // tempfile module
    try registry.register("subprocess", .zig_runtime, "std", null); // subprocess module

    // Additional Tier 1: OS and filesystem modules
    try registry.register("pathlib", .zig_runtime, "runtime.pathlib", null);

    // Tier 3: Mark as compile_python (will be handled later)
    try registry.register("urllib", .compile_python, null, null);
    try registry.register("datetime", .zig_runtime, "runtime.datetime", null); // datetime uses runtime.datetime

    // Dynamic features (unsupported - require runtime)
    try registry.register("importlib", .unsupported, null, null);

    return registry;
}
