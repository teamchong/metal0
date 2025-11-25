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
const fnv_hash = @import("../../utils/fnv_hash.zig");

const FnvContext = fnv_hash.FnvHashContext([]const u8);

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
};

pub const ImportRegistry = struct {
    allocator: std.mem.Allocator,
    registry: std.HashMap([]const u8, ImportInfo, FnvContext, 80),

    pub fn init(allocator: std.mem.Allocator) ImportRegistry {
        return ImportRegistry{
            .allocator = allocator,
            .registry = std.HashMap([]const u8, ImportInfo, FnvContext, 80).init(allocator),
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
        const info = ImportInfo{
            .python_module = python_module,
            .strategy = strategy,
            .zig_import = zig_import,
            .c_library = c_library,
            .python_source = null,
        };
        try self.registry.put(python_module, info);
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

/// Initialize registry with built-in Python→Zig mappings
pub fn createDefaultRegistry(allocator: std.mem.Allocator) !ImportRegistry {
    var registry = ImportRegistry.init(allocator);

    // Tier 1: Zig implementations (performance-critical)
    // Note: runtime is imported as @import("./runtime.zig") at module level
    // So we reference the already-imported runtime module, not @import("runtime")
    try registry.register("json", .zig_runtime, "runtime.json", null);
    try registry.register("http", .zig_runtime, "runtime.http", null);
    try registry.register("asyncio", .zig_runtime, "runtime.async", null);
    try registry.register("re", .zig_runtime, "runtime.re", null);
    try registry.register("sys", .zig_runtime, "runtime.sys", null);
    try registry.register("time", .zig_runtime, "runtime.time", null);
    try registry.register("math", .zig_runtime, "runtime.math", null);
    try registry.register("unittest", .zig_runtime, "runtime.unittest", null);

    // Tier 2: C library wrappers
    try registry.register("numpy", .c_library, "@import(\"./c_interop/c_interop.zig\").numpy", "blas");
    try registry.register("sqlite3", .c_library, "@import(\"./c_interop/c_interop.zig\").sqlite3", "sqlite3");
    try registry.register("zlib", .c_library, "@import(\"./c_interop/c_interop.zig\").zlib", "z");
    try registry.register("ssl", .c_library, "@import(\"./c_interop/c_interop.zig\").ssl", "ssl");

    // Tier 3: Mark as compile_python (will be handled later)
    try registry.register("pathlib", .compile_python, null, null);
    try registry.register("urllib", .compile_python, null, null);
    try registry.register("datetime", .compile_python, null, null);

    // Dynamic features (unsupported - require runtime)
    try registry.register("importlib", .unsupported, null, null);

    return registry;
}
