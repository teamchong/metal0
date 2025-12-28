/// Extension Plugin System
/// Enables fast paths for specific external libraries (numpy, torch, etc.)
///
/// Architecture:
/// 1. Phase 1 (Generic): dlopen + C-API shim (slow but universal)
/// 2. Phase 2 (Plugin): Library-specific fast paths (optional optimization)
///
/// Plugin Registration:
/// - Plugins register import hooks for specific modules
/// - When import detected, plugin takes over
/// - Plugin can provide:
///   - Static dispatch tables (comptime-generated)
///   - Type specializations (ndarray -> Zig slice)
///   - JIT-compiled hot paths

const std = @import("std");
const Allocator = std.mem.Allocator;
const cpython = @import("../cpython.zig");
const PyObject = cpython.PyObject;

// =============================================================================
// Plugin Interface
// =============================================================================

/// Plugin capability flags
pub const PluginCaps = packed struct {
    /// Plugin can handle import
    handles_import: bool = false,
    /// Plugin provides static dispatch
    static_dispatch: bool = false,
    /// Plugin can convert types
    type_conversion: bool = false,
    /// Plugin has comptime-generated specs
    has_spec: bool = false,
    /// Plugin requires GIL
    needs_gil: bool = true,
    /// Reserved
    _reserved: u3 = 0,
};

/// Function signature info (extracted at spec-gen time)
pub const FuncSpec = struct {
    name: []const u8,
    /// C function pointer (resolved at first call, cached)
    c_ptr: ?*anyopaque = null,
    /// Argument count (-1 for varargs)
    arg_count: i8 = -1,
    /// Return type hint
    return_type: TypeHint = .unknown,
    /// Can this be inlined? (pure, no side effects)
    inlinable: bool = false,
};

/// Type hints for optimization
pub const TypeHint = enum {
    unknown,
    py_object,
    py_long,
    py_float,
    py_array, // numpy ndarray
    py_tensor, // pytorch tensor
    void_ptr, // raw pointer
    int64,
    float64,
};

/// Type conversion spec
pub const TypeConversion = struct {
    /// Source Python type name
    from_type: []const u8,
    /// Target Zig type
    to_type: type,
    /// Conversion function
    convert_fn: *const fn (*PyObject) ?*anyopaque,
};

/// Plugin definition
pub const Plugin = struct {
    /// Plugin name (e.g., "numpy", "torch")
    name: []const u8,
    /// Module patterns this plugin handles (e.g., "numpy", "numpy.*")
    module_patterns: []const []const u8,
    /// Capabilities
    caps: PluginCaps,
    /// Function specs (if has_spec)
    func_specs: ?[]const FuncSpec = null,
    /// Type conversions
    type_conversions: ?[]const TypeConversion = null,

    /// Import hook - called when module is imported
    /// Returns module object or null to fall back to generic path
    on_import: ?*const fn (allocator: Allocator, module_name: []const u8) ?*PyObject = null,

    /// Call hook - called when method is invoked
    /// Returns result or null to fall back to generic C-API call
    on_call: ?*const fn (
        allocator: Allocator,
        func_name: []const u8,
        args: []*PyObject,
    ) ?*PyObject = null,

    /// Type hook - called to convert PyObject to optimized type
    on_type_convert: ?*const fn (
        allocator: Allocator,
        obj: *PyObject,
        target_hint: TypeHint,
    ) ?*anyopaque = null,
};

// =============================================================================
// Plugin Registry
// =============================================================================

/// Maximum plugins
const MAX_PLUGINS = 32;

/// Plugin registry singleton
pub const PluginRegistry = struct {
    const Self = @This();

    plugins: [MAX_PLUGINS]?*const Plugin = [_]?*const Plugin{null} ** MAX_PLUGINS,
    count: usize = 0,
    allocator: Allocator,

    /// Module -> Plugin cache
    module_cache: std.StringHashMap(*const Plugin),

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .module_cache = std.StringHashMap(*const Plugin).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.module_cache.deinit();
    }

    /// Register a plugin
    pub fn register(self: *Self, plugin: *const Plugin) !void {
        if (self.count >= MAX_PLUGINS) return error.TooManyPlugins;
        self.plugins[self.count] = plugin;
        self.count += 1;

        // Pre-cache module patterns
        for (plugin.module_patterns) |pattern| {
            try self.module_cache.put(pattern, plugin);
        }
    }

    /// Find plugin for module
    pub fn findPlugin(self: *Self, module_name: []const u8) ?*const Plugin {
        // Exact match first
        if (self.module_cache.get(module_name)) |plugin| {
            return plugin;
        }

        // Try prefix match (e.g., "numpy.*" matches "numpy.core")
        for (self.plugins[0..self.count]) |maybe_plugin| {
            if (maybe_plugin) |plugin| {
                for (plugin.module_patterns) |pattern| {
                    if (std.mem.endsWith(u8, pattern, ".*")) {
                        const prefix = pattern[0 .. pattern.len - 2];
                        if (std.mem.startsWith(u8, module_name, prefix)) {
                            return plugin;
                        }
                    }
                }
            }
        }

        return null;
    }

    /// Try to import via plugin
    pub fn tryImport(self: *Self, module_name: []const u8) ?*PyObject {
        const plugin = self.findPlugin(module_name) orelse return null;

        if (plugin.on_import) |import_fn| {
            return import_fn(self.allocator, module_name);
        }

        return null;
    }

    /// Try to call via plugin
    pub fn tryCall(
        self: *Self,
        module_name: []const u8,
        func_name: []const u8,
        args: []*PyObject,
    ) ?*PyObject {
        const plugin = self.findPlugin(module_name) orelse return null;

        if (plugin.on_call) |call_fn| {
            return call_fn(self.allocator, func_name, args);
        }

        return null;
    }
};

// =============================================================================
// Global Registry
// =============================================================================

var global_registry: ?PluginRegistry = null;

pub fn getRegistry(allocator: Allocator) *PluginRegistry {
    if (global_registry == null) {
        global_registry = PluginRegistry.init(allocator);
    }
    return &global_registry.?;
}

pub fn reset() void {
    if (global_registry) |*reg| {
        reg.deinit();
    }
    global_registry = null;
}

// =============================================================================
// Spec Generator (Build-time Tool)
// =============================================================================

/// Spec file format for comptime-generated module info
pub const ModuleSpec = struct {
    name: []const u8,
    version: []const u8,
    functions: []const FuncSpec,
    types: []const TypeSpec,
};

pub const TypeSpec = struct {
    name: []const u8,
    size: usize,
    alignment: usize,
    /// Offset of data pointer (for array types)
    data_offset: ?usize = null,
    /// Offset of shape array (for array types)
    shape_offset: ?usize = null,
};

/// Generate spec from loaded module (run at build time)
pub fn generateSpec(allocator: Allocator, module: *PyObject) !ModuleSpec {
    _ = allocator;
    _ = module;
    // This would be called by a build-time tool that:
    // 1. dlopen's the real .so
    // 2. Calls PyInit_xxx
    // 3. Walks the module dict
    // 4. Extracts function signatures and type info
    // 5. Writes a .zig file with the spec
    return ModuleSpec{
        .name = "",
        .version = "",
        .functions = &[_]FuncSpec{},
        .types = &[_]TypeSpec{},
    };
}

// =============================================================================
// Example: NumPy Plugin Skeleton
// =============================================================================

/// NumPy-specific optimizations
pub const numpy_plugin = Plugin{
    .name = "numpy",
    .module_patterns = &[_][]const u8{ "numpy", "numpy.*" },
    .caps = .{
        .handles_import = true,
        .static_dispatch = true,
        .type_conversion = true,
        .has_spec = false, // Set true when spec is generated
    },
    .on_import = numpyImport,
    .on_call = numpyCall,
    .on_type_convert = numpyTypeConvert,
};

fn numpyImport(allocator: Allocator, module_name: []const u8) ?*PyObject {
    _ = allocator;
    _ = module_name;
    // Phase 1: Fall back to generic dlopen
    // Phase 2: Use pre-loaded module from spec
    return null;
}

fn numpyCall(allocator: Allocator, func_name: []const u8, args: []*PyObject) ?*PyObject {
    _ = allocator;
    _ = args;

    // Fast path for common functions
    if (std.mem.eql(u8, func_name, "array")) {
        // TODO: Direct ndarray creation without going through C-API
        return null;
    }
    if (std.mem.eql(u8, func_name, "zeros")) {
        // TODO: Pre-allocate zeroed buffer
        return null;
    }
    if (std.mem.eql(u8, func_name, "dot")) {
        // TODO: Direct BLAS call
        return null;
    }

    return null;
}

fn numpyTypeConvert(allocator: Allocator, obj: *PyObject, target_hint: TypeHint) ?*anyopaque {
    _ = allocator;
    _ = obj;
    _ = target_hint;

    // Convert ndarray to Zig slice for fast access
    // PyArray_DATA() equivalent
    return null;
}

// =============================================================================
// Tests
// =============================================================================

test "plugin registry" {
    const allocator = std.testing.allocator;
    var registry = PluginRegistry.init(allocator);
    defer registry.deinit();

    try registry.register(&numpy_plugin);

    const plugin = registry.findPlugin("numpy");
    try std.testing.expect(plugin != null);
    try std.testing.expectEqualStrings("numpy", plugin.?.name);

    const sub_plugin = registry.findPlugin("numpy.core");
    try std.testing.expect(sub_plugin != null);
}

test "plugin caps" {
    const caps = PluginCaps{
        .handles_import = true,
        .static_dispatch = true,
    };
    try std.testing.expect(caps.handles_import);
    try std.testing.expect(caps.static_dispatch);
    try std.testing.expect(!caps.type_conversion);
}
