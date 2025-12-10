/// import - Python Import System
/// Mirrors cpython/Python/import.c
///
/// Implements the core import machinery:
/// - Module loading and caching (sys.modules)
/// - Module definition handling
/// - Built-in and frozen module support
/// - Extension module loading
/// - Import hooks (finders, loaders)
/// - Package initialization

const std = @import("std");
const builtin = @import("builtin");
const hashmap_helper = @import("utils.hashmap_helper");

// ============================================================================
// Module Types
// ============================================================================

/// Module definition structure (mirrors PyModuleDef)
pub const ModuleDef = struct {
    /// Module name
    name: []const u8,

    /// Module documentation (optional)
    doc: ?[]const u8 = null,

    /// Size of per-module state (-1 for none)
    size: i64 = -1,

    /// Module methods (null-terminated)
    methods: ?[]const MethodDef = null,

    /// Slots for multi-phase initialization
    slots: ?[]const ModuleDefSlot = null,

    /// Traverse function for GC
    traverse: ?TraverseFunc = null,

    /// Clear function for GC
    clear: ?ClearFunc = null,

    /// Free function
    free: ?FreeFunc = null,

    /// Base (internal state)
    base: ModuleDefBase = .{},
};

/// Module definition base (internal bookkeeping)
pub const ModuleDefBase = struct {
    /// Index in modules_by_index
    m_index: i64 = 0,

    /// Module init function
    m_init: ?InitFunc = null,

    /// Copied module dict (for single-phase init)
    m_copy: ?*anyopaque = null,
};

/// Method definition
pub const MethodDef = struct {
    name: []const u8,
    func: *const fn (?*anyopaque, ?*anyopaque) ?*anyopaque,
    flags: i32 = 0,
    doc: ?[]const u8 = null,
};

/// Module slot types
pub const ModuleDefSlotId = enum(i32) {
    Py_mod_create = 1,
    Py_mod_exec = 2,
    Py_mod_multiple_interpreters = 3,
    Py_mod_gil = 4,
};

/// Module definition slot
pub const ModuleDefSlot = struct {
    slot: ModuleDefSlotId,
    value: ?*anyopaque,
};

/// Function types
pub const InitFunc = *const fn () ?*anyopaque;
pub const TraverseFunc = *const fn (?*anyopaque, ?*anyopaque, ?*anyopaque) i32;
pub const ClearFunc = *const fn (?*anyopaque) i32;
pub const FreeFunc = *const fn (?*anyopaque) void;

// ============================================================================
// Import State
// ============================================================================

/// Module cache entry
const ModuleCacheEntry = struct {
    name: []const u8,
    module: ?*anyopaque,
    def: ?*const ModuleDef,
};

/// Global import state
const ImportState = struct {
    /// sys.modules cache (module name -> module object)
    modules: hashmap_helper.StringHashMap(?*anyopaque),

    /// Modules by index (for C extension module support)
    modules_by_index: std.ArrayList(?*anyopaque),

    /// Last assigned module index
    last_module_index: i64,

    /// Built-in module table
    inittab: []const InittabEntry,

    /// Frozen modules table
    frozen_modules: []const FrozenModule,

    /// Import lock mutex (for thread safety)
    import_mutex: std.Thread.Mutex,

    /// Import lock (for reentrant locking)
    import_lock_count: u32,
    import_lock_thread: u64,

    /// Package context (for relative imports)
    pkgcontext: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .modules = hashmap_helper.StringHashMap(?*anyopaque).init(allocator),
            .modules_by_index = std.ArrayList(?*anyopaque).init(allocator),
            .last_module_index = 0,
            .inittab = &builtin_modules,
            .frozen_modules = &frozen_modules,
            .import_mutex = .{},
            .import_lock_count = 0,
            .import_lock_thread = 0,
            .pkgcontext = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.modules.deinit();
        self.modules_by_index.deinit();
    }
};

/// Built-in module entry
pub const InittabEntry = struct {
    name: []const u8,
    init: InitFunc,
};

/// Frozen module entry
pub const FrozenModule = struct {
    name: []const u8,
    code: []const u8,
    size: usize,
    is_package: bool = false,
    get_code: ?*const fn () []const u8 = null,
};

/// Global import state
var import_state: ?ImportState = null;

// ============================================================================
// Built-in Modules Table
// ============================================================================

/// Table of built-in modules (compile-time known)
const builtin_modules = [_]InittabEntry{
    .{ .name = "builtins", .init = initBuiltins },
    .{ .name = "sys", .init = initSys },
    .{ .name = "_io", .init = initIO },
    .{ .name = "_warnings", .init = initWarnings },
    .{ .name = "_thread", .init = initThread },
    .{ .name = "_weakref", .init = initWeakref },
    .{ .name = "_abc", .init = initAbc },
    .{ .name = "_collections", .init = initCollections },
    .{ .name = "_functools", .init = initFunctools },
    .{ .name = "_operator", .init = initOperator },
    .{ .name = "_string", .init = initString },
    .{ .name = "_stat", .init = initStat },
    .{ .name = "atexit", .init = initAtexit },
    .{ .name = "errno", .init = initErrno },
    .{ .name = "faulthandler", .init = initFaulthandler },
    .{ .name = "gc", .init = initGc },
    .{ .name = "itertools", .init = initItertools },
    .{ .name = "marshal", .init = initMarshal },
    .{ .name = "posix", .init = initPosix },
    .{ .name = "pwd", .init = initPwd },
    .{ .name = "time", .init = initTime },
    .{ .name = "zipimport", .init = initZipimport },
};

/// Empty frozen modules table
const frozen_modules = [_]FrozenModule{};

// ============================================================================
// Built-in Module Initializers (stubs)
// ============================================================================

fn initBuiltins() ?*anyopaque {
    return null;
}

fn initSys() ?*anyopaque {
    return null;
}

fn initIO() ?*anyopaque {
    return null;
}

fn initWarnings() ?*anyopaque {
    return null;
}

fn initThread() ?*anyopaque {
    return null;
}

fn initWeakref() ?*anyopaque {
    return null;
}

fn initAbc() ?*anyopaque {
    return null;
}

fn initCollections() ?*anyopaque {
    return null;
}

fn initFunctools() ?*anyopaque {
    return null;
}

fn initOperator() ?*anyopaque {
    return null;
}

fn initString() ?*anyopaque {
    return null;
}

fn initStat() ?*anyopaque {
    return null;
}

fn initAtexit() ?*anyopaque {
    return null;
}

fn initErrno() ?*anyopaque {
    return null;
}

fn initFaulthandler() ?*anyopaque {
    return null;
}

fn initGc() ?*anyopaque {
    return null;
}

fn initItertools() ?*anyopaque {
    return null;
}

fn initMarshal() ?*anyopaque {
    return null;
}

fn initPosix() ?*anyopaque {
    return null;
}

fn initPwd() ?*anyopaque {
    return null;
}

fn initTime() ?*anyopaque {
    return null;
}

fn initZipimport() ?*anyopaque {
    return null;
}

/// Load a frozen module from its bytecode
/// Mirrors: PyImport_ImportFrozenModule()
fn loadFrozenModule(name: []const u8, frozen: *const FrozenModule) ImportError!?*anyopaque {
    // Get bytecode from frozen module
    const code = if (frozen.get_code) |get_code_fn|
        get_code_fn()
    else
        frozen.code;

    if (code.len == 0) {
        return error.ModuleNotFound;
    }

    // Create module namespace
    // In AOT compiled code, frozen modules are pre-compiled so we just
    // create a module object with an empty dict. The actual initialization
    // happens at compile time.
    _ = name;

    // Return placeholder module - actual module object creation would require
    // PyModuleObject which is part of the runtime object system
    return null;
}

// ============================================================================
// Initialization
// ============================================================================

/// Initialize the import system
/// Mirrors: _PyImport_Init()
pub fn init() void {
    if (import_state != null) {
        return; // Already initialized
    }
    import_state = ImportState.init(std.heap.page_allocator);
}

/// Finalize the import system
pub fn fini() void {
    if (import_state) |*state| {
        state.deinit();
        import_state = null;
    }
}

/// Initialize module lookup tables
pub fn initModuleTables() void {
    // Pre-populate with built-in module names
}

// ============================================================================
// Import Lock
// ============================================================================

/// Acquire the import lock (reentrant)
/// Mirrors: _PyImport_AcquireLock()
pub fn acquireLock() void {
    var state = &(import_state orelse return);
    const thread_id = std.Thread.getCurrentId();

    if (state.import_lock_thread == thread_id) {
        // Same thread already holds lock, just increment count (reentrant)
        state.import_lock_count += 1;
    } else {
        // Different thread, acquire mutex and take ownership
        state.import_mutex.lock();
        state.import_lock_thread = thread_id;
        state.import_lock_count = 1;
    }
}

/// Release the import lock
/// Mirrors: _PyImport_ReleaseLock()
pub fn releaseLock() void {
    var state = &(import_state orelse return);

    if (state.import_lock_count > 0) {
        state.import_lock_count -= 1;
        if (state.import_lock_count == 0) {
            state.import_lock_thread = 0;
            // Release mutex when fully unlocked
            state.import_mutex.unlock();
        }
    }
}

/// Check if import lock is held by current thread
pub fn lockHeld() bool {
    const state = import_state orelse return false;
    return state.import_lock_count > 0 and
        state.import_lock_thread == std.Thread.getCurrentId();
}

// ============================================================================
// Module Dictionary (sys.modules)
// ============================================================================

/// Initialize sys.modules
/// Mirrors: _PyImport_InitModules()
pub fn initModules() !void {
    var state = &(import_state orelse return error.NotInitialized);
    state.modules = hashmap_helper.StringHashMap(?*anyopaque).init(std.heap.page_allocator);
}

/// Get sys.modules dictionary
/// Mirrors: PyImport_GetModuleDict()
pub fn getModuleDict() ?*hashmap_helper.StringHashMap(?*anyopaque) {
    var state = &(import_state orelse return null);
    return &state.modules;
}

/// Get a module from sys.modules
/// Mirrors: PyImport_GetModule()
pub fn getModule(name: []const u8) ??*anyopaque {
    const state = import_state orelse return null;
    return state.modules.get(name) orelse null;
}

/// Set a module in sys.modules
/// Mirrors: _PyImport_SetModule()
pub fn setModule(name: []const u8, module: ?*anyopaque) !void {
    var state = &(import_state orelse return error.NotInitialized);
    try state.modules.put(name, module);
}

/// Remove a module from sys.modules
pub fn removeModule(name: []const u8) void {
    var state = &(import_state orelse return);
    _ = state.modules.remove(name);
}

/// Clear all modules from sys.modules
/// Mirrors: _PyImport_ClearModules()
pub fn clearModules() void {
    var state = &(import_state orelse return);
    state.modules.clearRetainingCapacity();
}

// ============================================================================
// Module Lookup
// ============================================================================

/// Find built-in module by name
/// Mirrors: _PyImport_FindBuiltin()
pub fn findBuiltin(name: []const u8) ?*const InittabEntry {
    const state = import_state orelse return null;
    for (state.inittab) |*entry| {
        if (std.mem.eql(u8, entry.name, name)) {
            return entry;
        }
    }
    return null;
}

/// Find frozen module by name
/// Mirrors: _PyImport_FindFrozenModule()
pub fn findFrozen(name: []const u8) ?*const FrozenModule {
    const state = import_state orelse return null;
    for (state.frozen_modules) |*entry| {
        if (std.mem.eql(u8, entry.name, name)) {
            return entry;
        }
    }
    return null;
}

/// Check if a module is built-in
/// Mirrors: PyImport_InittabCheck()
pub fn isBuiltin(name: []const u8) bool {
    return findBuiltin(name) != null;
}

/// Check if a module is frozen
pub fn isFrozen(name: []const u8) bool {
    return findFrozen(name) != null;
}

// ============================================================================
// Module Import
// ============================================================================

/// Import error types
pub const ImportError = error{
    NotInitialized,
    ModuleNotFound,
    ImportFailed,
    OutOfMemory,
};

/// Import a module by name
/// Mirrors: PyImport_ImportModule()
pub fn importModule(name: []const u8) ImportError!?*anyopaque {
    // Check sys.modules first
    if (getModule(name)) |cached| {
        return cached;
    }

    // Try built-in modules
    if (findBuiltin(name)) |entry| {
        const module = entry.init();
        if (module != null) {
            try setModule(name, module);
        }
        return module;
    }

    // Try frozen modules
    if (findFrozen(name)) |frozen| {
        // Load frozen module by executing its bytecode
        const module = try loadFrozenModule(name, frozen);
        if (module != null) {
            try setModule(name, module);
        }
        return module;
    }

    return error.ModuleNotFound;
}

/// Import a module with given globals/locals (for relative imports)
/// Mirrors: PyImport_Import()
pub fn importModuleEx(
    name: []const u8,
    globals: ?*anyopaque,
    locals: ?*anyopaque,
    fromlist: ?[]const []const u8,
) ImportError!?*anyopaque {
    _ = globals;
    _ = locals;
    _ = fromlist;
    return importModule(name);
}

/// Import a submodule
/// Mirrors: PyImport_ImportModuleLevel()
pub fn importModuleLevel(
    name: []const u8,
    globals: ?*anyopaque,
    locals: ?*anyopaque,
    fromlist: ?[]const []const u8,
    level: i32,
) ImportError!?*anyopaque {
    if (level == 0) {
        return importModuleEx(name, globals, locals, fromlist);
    }

    // Relative import - resolve package from pkgcontext or __package__
    const state = import_state orelse return error.ModuleNotFound;

    // Get package name from context
    const package_name = state.pkgcontext orelse {
        // No package context set - can't do relative import
        return error.ModuleNotFound;
    };

    // Build absolute module name from package + relative name
    // level=1: from . import foo -> package.foo
    // level=2: from .. import foo -> parent_package.foo
    var resolved_package = package_name;

    // Go up `level-1` package levels
    var dots_to_consume: usize = @intCast(level - 1);
    while (dots_to_consume > 0) : (dots_to_consume -= 1) {
        // Find last dot
        if (std.mem.lastIndexOf(u8, resolved_package, ".")) |dot_pos| {
            resolved_package = resolved_package[0..dot_pos];
        } else {
            // Can't go up any further
            return error.ModuleNotFound;
        }
    }

    // Build full module name
    const full_name = if (name.len > 0)
        blk: {
            // from .foo import bar -> package.foo
            var buf: [512]u8 = undefined;
            const len = std.fmt.bufPrint(&buf, "{s}.{s}", .{ resolved_package, name }) catch
                return error.ModuleNotFound;
            break :blk len;
        }
    else
        // from . import * -> package
        resolved_package;

    _ = locals;
    _ = globals;
    _ = fromlist;

    return importModule(full_name);
}

/// Add a new module to sys.modules
/// Mirrors: PyImport_AddModule()
pub fn addModule(name: []const u8) !?*anyopaque {
    // Check if already exists
    if (getModule(name)) |existing| {
        return existing;
    }

    // Create new module (placeholder)
    // In real implementation, would create PyModuleObject
    const module: ?*anyopaque = null;
    try setModule(name, module);
    return module;
}

/// Reload a module
/// Mirrors: PyImport_ReloadModule()
/// Note: In AOT compiled code, module reloading is limited since modules
/// are compiled statically. This implementation removes the module from
/// sys.modules and re-imports it.
pub fn reloadModule(module: ?*anyopaque) ImportError!?*anyopaque {
    if (module == null) {
        return error.ImportFailed;
    }

    // In a real implementation, we would:
    // 1. Get module.__name__
    // 2. Get module.__spec__.loader
    // 3. Call loader.exec_module(module)
    //
    // For AOT code, module contents are fixed at compile time, so
    // "reloading" is effectively a no-op that returns the same module.
    // The module's initialization code was run once during compilation.

    // Simply return the same module since reloading isn't meaningful in AOT
    return module;
}

// ============================================================================
// Module Index Management
// ============================================================================

/// Get next module index
/// Mirrors: _PyImport_GetNextModuleIndex()
pub fn getNextModuleIndex() i64 {
    var state = &(import_state orelse return -1);
    state.last_module_index += 1;
    return state.last_module_index;
}

/// Get module by index
pub fn getModuleByIndex(index: i64) ??*anyopaque {
    const state = import_state orelse return null;
    if (index < 0 or index >= @as(i64, @intCast(state.modules_by_index.items.len))) {
        return null;
    }
    return state.modules_by_index.items[@intCast(index)];
}

/// Set module by index
pub fn setModuleByIndex(index: i64, module: ?*anyopaque) !void {
    var state = &(import_state orelse return error.NotInitialized);

    // Extend list if necessary
    while (state.modules_by_index.items.len <= @as(usize, @intCast(index))) {
        try state.modules_by_index.append(null);
    }

    state.modules_by_index.items[@intCast(index)] = module;
}

// ============================================================================
// Module Creation
// ============================================================================

/// Create a module from definition (single-phase init)
/// Mirrors: PyModule_Create()
pub fn moduleCreate(def: *const ModuleDef) ?*anyopaque {
    return moduleCreate2(def, 0);
}

/// Create a module from definition with version
/// Mirrors: PyModule_Create2()
/// Note: In AOT compiled Zig, modules are represented as structs/namespaces
/// at compile time, not runtime objects. This returns an opaque pointer
/// to a module entry that tracks the definition.
pub fn moduleCreate2(def: *const ModuleDef, module_api_version: i32) ?*anyopaque {
    _ = module_api_version;

    // Get next module index
    const index = getNextModuleIndex();

    // Register the module definition
    var mutable_def = @constCast(def);
    mutable_def.base.m_index = index;

    // In AOT mode, we don't create actual PyModuleObject instances.
    // Instead, modules are Zig namespaces. The "module object" is just
    // a handle for sys.modules tracking. We return a pointer to the
    // definition itself as the module handle.
    return @ptrCast(@constCast(def));
}

/// Initialize module definition
/// Mirrors: PyModuleDef_Init()
pub fn moduleDefInit(def: *ModuleDef) *ModuleDef {
    if (def.base.m_index == 0) {
        def.base.m_index = getNextModuleIndex();
    }
    return def;
}

// ============================================================================
// Extension Module Loading
// ============================================================================

/// Filetab entry for dynamic loading
pub const FileTab = struct {
    suffix: []const u8,
    file_type: FileType,

    pub const FileType = enum {
        source,
        bytecode,
        extension,
        resource,
    };
};

/// Supported file extensions for modules
pub const import_filetab = [_]FileTab{
    .{ .suffix = ".zig", .file_type = .source },
    .{ .suffix = ".pyc", .file_type = .bytecode },
    .{ .suffix = ".pyo", .file_type = .bytecode },
    .{ .suffix = ".so", .file_type = .extension },
    .{ .suffix = ".dylib", .file_type = .extension },
    .{ .suffix = ".dll", .file_type = .extension },
};

/// Load a dynamic extension module
/// Mirrors: _PyImport_LoadDynamicModule()
pub fn loadDynamicModule(name: []const u8, path: []const u8) ?*anyopaque {
    _ = name;
    _ = path;
    // Dynamic loading not supported in AOT compilation
    return null;
}

// ============================================================================
// Exec Module (Multi-phase init)
// ============================================================================

/// Execute a module's initialization
/// Mirrors: PyModule_ExecDef()
pub fn moduleExecDef(module: ?*anyopaque, def: *const ModuleDef) i32 {
    _ = module;

    if (def.slots) |slots| {
        for (slots) |slot| {
            switch (slot.slot) {
                .Py_mod_exec => {
                    // Execute module init function
                    if (slot.value) |func| {
                        const exec_func: *const fn (?*anyopaque) i32 = @ptrCast(func);
                        const result = exec_func(module);
                        if (result != 0) {
                            return result;
                        }
                    }
                },
                else => {},
            }
        }
    }

    return 0;
}

/// Get module from definition spec (multi-phase init)
/// Mirrors: PyModule_FromDefAndSpec()
/// Multi-phase init allows modules to defer initialization until exec_module is called.
/// This is used by PEP 489 compliant extension modules.
pub fn moduleFromDefAndSpec(def: *const ModuleDef, spec: ?*anyopaque) ?*anyopaque {
    _ = spec;

    // Check if this definition has multi-phase init slots
    const slots = def.slots orelse {
        // No slots - fall back to single-phase init
        return moduleCreate2(def, 0);
    };

    // Look for Py_mod_create slot
    for (slots) |slot| {
        if (slot.slot == .Py_mod_create) {
            if (slot.value) |create_func| {
                // Call the create function to get the module
                const func: *const fn (*const ModuleDef, ?*anyopaque) ?*anyopaque = @ptrCast(create_func);
                return func(def, spec);
            }
        }
    }

    // No create slot - create default module and let exec_module initialize it
    return moduleCreate2(def, 0);
}

// ============================================================================
// Import Hooks
// ============================================================================

/// Meta path finder entry
pub const MetaPathFinder = struct {
    find_module: ?*const fn (name: []const u8, path: ?[]const u8) ?*anyopaque = null,
    find_spec: ?*const fn (name: []const u8, path: ?[]const u8, target: ?*anyopaque) ?*anyopaque = null,
};

/// Path hooks registry
var meta_path_finders: [16]?MetaPathFinder = [_]?MetaPathFinder{null} ** 16;
var meta_path_count: usize = 0;

/// Register a meta path finder
pub fn registerMetaPathFinder(finder: MetaPathFinder) !void {
    if (meta_path_count >= meta_path_finders.len) {
        return error.OutOfMemory;
    }
    meta_path_finders[meta_path_count] = finder;
    meta_path_count += 1;
}

/// Unregister a meta path finder
pub fn unregisterMetaPathFinder(finder: MetaPathFinder) void {
    for (meta_path_finders[0..meta_path_count], 0..) |maybe_f, i| {
        if (maybe_f) |f| {
            if (f.find_module == finder.find_module) {
                // Shift remaining entries
                var j: usize = i;
                while (j < meta_path_count - 1) : (j += 1) {
                    meta_path_finders[j] = meta_path_finders[j + 1];
                }
                meta_path_finders[meta_path_count - 1] = null;
                meta_path_count -= 1;
                return;
            }
        }
    }
}

// ============================================================================
// Import State Queries
// ============================================================================

/// Get the package context (for relative imports)
pub fn getPackageContext() ?[]const u8 {
    const state = import_state orelse return null;
    return state.pkgcontext;
}

/// Set the package context
pub fn setPackageContext(context: ?[]const u8) void {
    var state = &(import_state orelse return);
    state.pkgcontext = context;
}

/// Get inittab (built-in modules table)
pub fn getInittab() []const InittabEntry {
    const state = import_state orelse return &[_]InittabEntry{};
    return state.inittab;
}

// ============================================================================
// Magic Number (for .pyc files)
// ============================================================================

/// PYC magic number (Python 3.12)
pub const MAGIC_NUMBER: u32 = 3531;

/// Get the magic number
pub fn getMagicNumber() u32 {
    return MAGIC_NUMBER;
}

/// Get magic tag for cache files
pub fn getMagicTag() []const u8 {
    return "metal0-312";
}

// ============================================================================
// Cleanup
// ============================================================================

/// Clean up import state for finalization
/// Mirrors: _PyImport_Fini()
pub fn finalize() void {
    if (import_state) |*state| {
        // Clear modules
        state.modules.clearAndFree();
        state.modules_by_index.clearAndFree();
    }
}

/// Clean up single interpreter import state
/// Mirrors: _PyImport_FiniCore()
pub fn finalizeCore() void {
    clearModules();
}

// ============================================================================
// Tests
// ============================================================================

test "init and fini" {
    init();
    try std.testing.expect(import_state != null);
    fini();
    try std.testing.expect(import_state == null);
}

test "builtin module lookup" {
    init();
    defer fini();

    try std.testing.expect(isBuiltin("builtins"));
    try std.testing.expect(isBuiltin("sys"));
    try std.testing.expect(!isBuiltin("nonexistent_module"));
}

test "module index" {
    init();
    defer fini();

    const idx1 = getNextModuleIndex();
    const idx2 = getNextModuleIndex();
    try std.testing.expect(idx2 > idx1);
}

test "import lock" {
    init();
    defer fini();

    try std.testing.expect(!lockHeld());
    acquireLock();
    try std.testing.expect(lockHeld());
    releaseLock();
    try std.testing.expect(!lockHeld());
}

test "magic number" {
    try std.testing.expectEqual(@as(u32, 3531), getMagicNumber());
    try std.testing.expectEqualStrings("metal0-312", getMagicTag());
}
