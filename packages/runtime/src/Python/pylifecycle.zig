/// pylifecycle - Python Interpreter Lifecycle Management
/// Mirrors cpython/Python/pylifecycle.c
///
/// Manages the interpreter lifecycle:
/// - Initialization (Py_Initialize, Py_InitializeEx)
/// - Finalization (Py_Finalize, Py_FinalizeEx)
/// - Runtime state management
/// - Thread state lifecycle
/// - Exit functions (atexit handlers)

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Status Types (mirror PyStatus)
// ============================================================================

/// Status codes for initialization/finalization operations
pub const StatusKind = enum {
    ok,
    exit_code,
    err,
    no_memory,
};

/// Initialization/operation status
pub const Status = struct {
    kind: StatusKind = .ok,
    exit_code: i32 = 0,
    err_msg: ?[]const u8 = null,
    func: ?[]const u8 = null,

    pub fn ok() Status {
        return .{ .kind = .ok };
    }

    pub fn exit(code: i32) Status {
        return .{ .kind = .exit_code, .exit_code = code };
    }

    pub fn err(msg: []const u8) Status {
        return .{ .kind = .err, .err_msg = msg };
    }

    pub fn noMemory() Status {
        return .{ .kind = .no_memory, .err_msg = "memory allocation failed" };
    }

    pub fn isException(self: Status) bool {
        return self.kind != .ok;
    }

    pub fn isExit(self: Status) bool {
        return self.kind == .exit_code;
    }

    pub fn isError(self: Status) bool {
        return self.kind == .err or self.kind == .no_memory;
    }
};

// ============================================================================
// Pre-Configuration (mirror PyPreConfig)
// ============================================================================

/// Pre-configuration for Python initialization
pub const PreConfig = struct {
    /// Parse Py_PreInitializeFromBytesArgs() arguments?
    parse_argv: bool = true,

    /// Isolated mode: sys.path contains neither script directory nor cwd
    isolated: i32 = 0,

    /// Use environment variables?
    use_environment: bool = true,

    /// Platform-specific configure locale?
    configure_locale: bool = true,

    /// Coerce the C locale? (Unix only)
    coerce_c_locale: i32 = 0,

    /// Emit LC_CTYPE coercion warning?
    coerce_c_locale_warn: bool = false,

    /// Force UTF-8 mode?
    utf8_mode: i32 = -1,

    /// Use hash randomization?
    dev_mode: bool = false,

    /// Memory allocator
    allocator: AllocatorType = .default,

    pub const AllocatorType = enum {
        default,
        debug,
        malloc,
        malloc_debug,
        pymalloc,
        pymalloc_debug,
    };
};

// ============================================================================
// Configuration (mirror PyConfig)
// ============================================================================

/// Python configuration
pub const Config = struct {
    /// Parse command line arguments?
    parse_argv: bool = true,

    /// Isolated mode
    isolated: bool = false,

    /// Use environment variables
    use_environment: bool = true,

    /// Development mode (extra debugging)
    dev_mode: bool = false,

    /// Install signal handlers
    install_signal_handlers: bool = true,

    /// Hash randomization
    use_hash_seed: bool = false,
    hash_seed: u64 = 0,

    /// Fault handler (traceback on SIGSEGV, etc.)
    faulthandler: bool = false,

    /// Import site module
    site_import: bool = true,

    /// Bytes/str warnings
    bytes_warning: i32 = 0,

    /// Warnings filter
    warn_default_encoding: bool = false,

    /// Inspect interactively after running script
    inspect: bool = false,

    /// Interactive mode (REPL)
    interactive: bool = false,

    /// Optimization level (-O, -OO)
    optimization_level: i32 = 0,

    /// Parser debug mode
    parser_debug: bool = false,

    /// Write .pyc files
    write_bytecode: bool = true,

    /// Verbose mode (-v)
    verbose: i32 = 0,

    /// Quiet mode (-q)
    quiet: bool = false,

    /// Add user site directory to sys.path
    user_site_directory: bool = true,

    /// Configure the C stdio streams?
    configure_c_stdio: bool = true,

    /// Buffered stdio?
    buffered_stdio: bool = true,

    /// stdio encoding
    stdio_encoding: ?[]const u8 = null,

    /// stdio errors
    stdio_errors: ?[]const u8 = null,

    /// Skip first line of source
    skip_source_first_line: bool = false,

    /// Run code (from command line)
    run_command: ?[]const u8 = null,

    /// Run module (from command line)
    run_module: ?[]const u8 = null,

    /// Run filename (from command line)
    run_filename: ?[]const u8 = null,

    /// Install importlib
    _install_importlib: bool = true,

    /// Check hash of .pyc files
    _check_hash_pycs_mode: CheckHashMode = .default,

    /// Safe path mode
    safe_path: bool = false,

    /// Max digits for int<->str conversion
    int_max_str_digits: i32 = 4300,

    /// Enable perf profiler
    perf_profiling: bool = false,

    /// Code object extra generation
    code_debug_ranges: bool = true,

    pub const CheckHashMode = enum {
        default,
        always,
        never,
    };
};

// ============================================================================
// Runtime State
// ============================================================================

/// Runtime state (singleton)
pub const RuntimeState = struct {
    /// Pre-initialization config
    preconfig: PreConfig = .{},

    /// Is the runtime pre-initialized?
    preinitializing: bool = false,
    preinitialized: bool = false,

    /// Is the runtime core-initialized?
    core_initialized: bool = false,

    /// Is the runtime fully initialized?
    initialized: bool = false,

    /// Is the runtime being finalized?
    finalizing: ?*ThreadState = null,

    /// Exit functions (atexit)
    exitfuncs: [32]?ExitFunc = [_]?ExitFunc{null} ** 32,
    nexitfuncs: usize = 0,

    /// Main thread state
    main_tstate: ?*ThreadState = null,

    /// Interpreter ID counter
    next_interp_id: i64 = 0,

    /// Audit hooks
    audit_hooks: AuditHookList = .{},

    /// Open code hook
    open_code_hook: ?OpenCodeHook = null,

    /// At-fork handlers
    atfork_handlers: AtForkHandlers = .{},

    /// GIL state
    gilstate: GILState = .{},

    const Self = @This();

    pub fn isInitialized(self: *const Self) bool {
        return self.initialized;
    }

    pub fn isCoreInitialized(self: *const Self) bool {
        return self.core_initialized;
    }

    pub fn isFinalizing(self: *const Self) bool {
        return self.finalizing != null;
    }

    pub fn setFinalizing(self: *Self, tstate: ?*ThreadState) void {
        self.finalizing = tstate;
    }
};

/// Thread state
pub const ThreadState = struct {
    interp: ?*InterpreterState = null,
    next: ?*ThreadState = null,
    prev: ?*ThreadState = null,
    id: u64 = 0,

    // Recursion tracking
    recursion_depth: u32 = 0,
    recursion_limit: u32 = 1000,
    recursion_headroom: u32 = 50,

    // Tracing/profiling
    tracing: bool = false,
    use_tracing: bool = false,

    // Exception state
    curexc_type: ?[]const u8 = null,
    curexc_value: ?[]const u8 = null,
    curexc_traceback: ?[]const u8 = null,

    // Thread info
    thread_id: u64 = 0,
    native_thread_id: u64 = 0,

    // Gilstate counter
    gilstate_counter: u32 = 0,

    // Async generator hooks
    async_gen_firstiter: ?*anyopaque = null,
    async_gen_finalizer: ?*anyopaque = null,

    // Context variables
    context: ?*anyopaque = null,
    context_ver: u64 = 0,
};

/// Interpreter state
pub const InterpreterState = struct {
    next: ?*InterpreterState = null,
    id: i64 = 0,
    id_refcount: i64 = 0,
    requires_idref: bool = false,

    /// Is this interpreter ready?
    _ready: bool = false,

    /// Configuration
    config: Config = .{},

    /// Feature flags
    feature_flags: u64 = 0,

    /// Thread list head
    threads_head: ?*ThreadState = null,
    threads_count: u64 = 0,

    /// Modules dict
    modules: ?*anyopaque = null,

    /// Builtins module
    builtins: ?*anyopaque = null,

    /// Import state
    import_func: ?*anyopaque = null,

    /// Codec search path
    codec_search_path: ?*anyopaque = null,
    codec_search_cache: ?*anyopaque = null,
    codec_error_registry: ?*anyopaque = null,

    /// Finalizing?
    finalizing: bool = false,

    /// Int<->str conversion limit
    long_state: struct {
        max_str_digits: i32 = 4300,
    } = .{},

    /// Interned strings
    interned_strings: ?*anyopaque = null,

    /// Warnings state
    warnings_state: ?*anyopaque = null,

    /// Audit hooks
    audit_hooks: ?*anyopaque = null,
};

// ============================================================================
// Exit Functions
// ============================================================================

/// Exit function type
pub const ExitFunc = *const fn () void;

/// Open code hook type
pub const OpenCodeHook = *const fn (path: []const u8, mode: []const u8) ?*anyopaque;

/// Audit hook entry
pub const AuditHook = struct {
    func: *const fn (event: []const u8, args: ?*anyopaque) void,
    next: ?*AuditHook = null,
};

pub const AuditHookList = struct {
    head: ?*AuditHook = null,
    count: usize = 0,
};

/// At-fork handlers
pub const AtForkHandlers = struct {
    prepare: ?*const fn () void = null,
    parent: ?*const fn () void = null,
    child: ?*const fn () void = null,
};

/// GIL state
pub const GILState = struct {
    tstate_current: ?*ThreadState = null,
    autoTSSkey: ?*anyopaque = null,
    autoInterpreterState: ?*InterpreterState = null,
};

// ============================================================================
// Global Runtime Instance
// ============================================================================

/// The global runtime state (singleton)
var runtime: RuntimeState = .{};

/// Thread-local thread state
threadlocal var _tstate: ?*ThreadState = null;

// ============================================================================
// Initialization Functions
// ============================================================================

/// Pre-initialize the Python runtime
/// Mirrors: Py_PreInitialize()
pub fn preInitialize(config: ?PreConfig) Status {
    return preInitializeFromConfig(config orelse PreConfig{});
}

/// Pre-initialize from PreConfig
pub fn preInitializeFromConfig(config: PreConfig) Status {
    if (runtime.preinitialized) {
        return Status.ok();
    }

    runtime.preinitializing = true;
    defer runtime.preinitializing = false;

    // Store preconfig
    runtime.preconfig = config;

    // Initialize locale if requested
    if (config.configure_locale) {
        initLocale();
    }

    // Coerce C locale if requested (Unix)
    if (config.coerce_c_locale > 0) {
        _ = coerceLegacyLocale(config.coerce_c_locale_warn);
    }

    runtime.preinitialized = true;
    return Status.ok();
}

/// Initialize Python runtime (simple version)
/// Mirrors: Py_Initialize()
pub fn initialize() void {
    const status = initializeFromConfig(Config{});
    if (status.isException()) {
        exitStatusException(status);
    }
}

/// Initialize Python runtime with signal handlers option
/// Mirrors: Py_InitializeEx()
pub fn initializeEx(install_sigs: bool) void {
    var config = Config{};
    config.install_signal_handlers = install_sigs;
    const status = initializeFromConfig(config);
    if (status.isException()) {
        exitStatusException(status);
    }
}

/// Initialize Python from configuration
/// Mirrors: Py_InitializeFromConfig()
pub fn initializeFromConfig(src_config: Config) Status {
    // Pre-initialize if needed
    if (!runtime.preinitialized) {
        const pre_status = preInitialize(null);
        if (pre_status.isException()) {
            return pre_status;
        }
    }

    // Already initialized?
    if (runtime.initialized) {
        return Status.ok();
    }

    // Core initialization
    var status = initCore(&src_config);
    if (status.isException()) {
        return status;
    }

    // Main initialization
    status = initMain();
    if (status.isException()) {
        return status;
    }

    return Status.ok();
}

/// Core initialization
fn initCore(config: *const Config) Status {
    if (runtime.core_initialized) {
        return Status.ok();
    }

    // Initialize version info
    initVersion();

    // Initialize hash randomization
    if (!config.use_hash_seed) {
        initHashRandomization();
    }

    // Create main interpreter
    const interp_status = createMainInterpreter(config);
    if (interp_status.isException()) {
        return interp_status;
    }

    // Initialize types
    initTypes();

    // Initialize builtins
    initBuiltins();

    runtime.core_initialized = true;
    return Status.ok();
}

/// Main initialization (after core)
fn initMain() Status {
    if (runtime.initialized) {
        return Status.ok();
    }

    if (!runtime.core_initialized) {
        return Status.err("core not initialized");
    }

    // Initialize sys module
    initSysModule();

    // Initialize import machinery
    initImport();

    // Install signal handlers
    if (runtime.main_tstate) |tstate| {
        if (tstate.interp) |interp| {
            if (interp.config.install_signal_handlers) {
                initSignalHandlers();
            }
        }
    }

    // Import site module
    if (runtime.main_tstate) |tstate| {
        if (tstate.interp) |interp| {
            if (interp.config.site_import) {
                _ = initSite();
            }
        }
    }

    runtime.initialized = true;
    return Status.ok();
}

/// Create the main interpreter
fn createMainInterpreter(config: *const Config) Status {
    // Allocate interpreter state
    var interp = std.heap.page_allocator.create(InterpreterState) catch {
        return Status.noMemory();
    };
    interp.* = .{};
    interp.config = config.*;
    interp.id = runtime.next_interp_id;
    runtime.next_interp_id += 1;
    interp._ready = true;

    // Allocate main thread state
    var tstate = std.heap.page_allocator.create(ThreadState) catch {
        return Status.noMemory();
    };
    tstate.* = .{};
    tstate.interp = interp;
    tstate.id = 0;
    tstate.thread_id = @intCast(std.Thread.getCurrentId());

    // Link thread to interpreter
    interp.threads_head = tstate;
    interp.threads_count = 1;

    // Set main thread state
    runtime.main_tstate = tstate;
    _tstate = tstate;

    // Initialize GIL state
    runtime.gilstate.tstate_current = tstate;
    runtime.gilstate.autoInterpreterState = interp;

    return Status.ok();
}

// ============================================================================
// Finalization Functions
// ============================================================================

/// Finalize Python runtime
/// Mirrors: Py_Finalize()
pub fn finalize() void {
    _ = finalizeEx();
}

/// Finalize Python runtime with status return
/// Mirrors: Py_FinalizeEx()
pub fn finalizeEx() i32 {
    if (!runtime.initialized) {
        return 0;
    }

    // Get main thread state
    const tstate = runtime.main_tstate orelse return -1;

    // Mark as finalizing
    runtime.finalizing = tstate;

    // Wait for non-daemon threads
    waitForThreadShutdown();

    // Call exit functions
    callExitFuncs();

    // Clear audit hooks
    clearAuditHooks();

    // Finalize interpreter
    if (tstate.interp) |interp| {
        interp.finalizing = true;
    }

    // Clear thread state
    _tstate = null;

    // Mark as not initialized
    runtime.initialized = false;
    runtime.core_initialized = false;
    runtime.finalizing = null;

    return 0;
}

/// Wait for non-daemon threads to finish
fn waitForThreadShutdown() void {
    // In AOT, threads are managed differently
    // For now, just a placeholder
}

/// Call registered exit functions
fn callExitFuncs() void {
    // Call in reverse order
    var i = runtime.nexitfuncs;
    while (i > 0) {
        i -= 1;
        if (runtime.exitfuncs[i]) |func| {
            func();
            runtime.exitfuncs[i] = null;
        }
    }
    runtime.nexitfuncs = 0;
}

/// Clear audit hooks
fn clearAuditHooks() void {
    runtime.audit_hooks.head = null;
    runtime.audit_hooks.count = 0;
}

// ============================================================================
// Runtime Query Functions
// ============================================================================

/// Check if Python is initialized
/// Mirrors: Py_IsInitialized()
pub fn isInitialized() bool {
    return runtime.initialized;
}

/// Check if Python is finalizing
/// Mirrors: Py_IsFinalizing()
pub fn isFinalizing() bool {
    return runtime.finalizing != null;
}

/// Get the runtime state
pub fn getRuntime() *RuntimeState {
    return &runtime;
}

/// Get the current thread state
/// Mirrors: PyThreadState_Get()
pub fn getThreadState() ?*ThreadState {
    return _tstate;
}

/// Get the main interpreter
/// Mirrors: PyInterpreterState_Main()
pub fn getMainInterpreter() ?*InterpreterState {
    if (runtime.main_tstate) |tstate| {
        return tstate.interp;
    }
    return null;
}

// ============================================================================
// Exit Functions Registration
// ============================================================================

/// Register an exit function
/// Mirrors: Py_AtExit()
pub fn atExit(func: ExitFunc) i32 {
    if (runtime.nexitfuncs >= runtime.exitfuncs.len) {
        return -1;
    }
    runtime.exitfuncs[runtime.nexitfuncs] = func;
    runtime.nexitfuncs += 1;
    return 0;
}

// ============================================================================
// Locale Handling
// ============================================================================

/// Initialize locale settings
fn initLocale() void {
    // Set locale from environment
    // In Zig, we rely on system defaults
}

/// Coerce legacy C locale to UTF-8
fn coerceLegacyLocale(warn: bool) bool {
    _ = warn;
    // Check if we're in C locale
    // For now, assume UTF-8
    return false;
}

/// Check if current locale is legacy C locale
pub fn isLegacyLocaleDetected(warn: bool) bool {
    _ = warn;
    // On Windows, no legacy locale concept
    if (builtin.os.tag == .windows) {
        return false;
    }
    // Check LC_CTYPE
    // For now, assume non-legacy
    return false;
}

// ============================================================================
// Internal Initialization Helpers
// ============================================================================

/// Initialize version info
fn initVersion() void {
    // Version is set at compile time
}

/// Initialize hash randomization
fn initHashRandomization() void {
    // Use random seed for hash randomization
    // Zig's hash functions handle this internally
}

/// Initialize types
fn initTypes() void {
    // Types are defined at compile time in Zig
}

/// Initialize builtins
fn initBuiltins() void {
    // Builtins are registered via bltinmodule.zig
}

/// Initialize sys module
fn initSysModule() void {
    // Sys module is initialized via sysmodule.zig
    const sysmodule = @import("sysmodule.zig");
    sysmodule.init();
}

/// Initialize import machinery
fn initImport() void {
    // Import is handled at compile time for AOT
}

/// Initialize signal handlers
fn initSignalHandlers() void {
    // Signal handlers for Python exceptions
}

/// Initialize site module
fn initSite() Status {
    // Site module initialization
    return Status.ok();
}

// ============================================================================
// Error Handling
// ============================================================================

/// Exit with a status exception
pub fn exitStatusException(status: Status) noreturn {
    if (status.kind == .exit_code) {
        std.process.exit(@intCast(@as(u8, @truncate(@as(u32, @bitCast(status.exit_code))))));
    }

    // Print error message
    const stderr = std.io.getStdErr().writer();
    if (status.err_msg) |msg| {
        stderr.print("Python error: {s}\n", .{msg}) catch {};
    } else if (status.kind == .no_memory) {
        stderr.print("Python error: out of memory\n", .{}) catch {};
    }

    std.process.exit(1);
}

// ============================================================================
// Audit Hooks
// ============================================================================

/// Add an audit hook
pub fn addAuditHook(hook: *AuditHook) i32 {
    hook.next = runtime.audit_hooks.head;
    runtime.audit_hooks.head = hook;
    runtime.audit_hooks.count += 1;
    return 0;
}

/// Trigger an audit event
pub fn audit(event: []const u8, args: ?*anyopaque) void {
    var hook = runtime.audit_hooks.head;
    while (hook) |h| {
        h.func(event, args);
        hook = h.next;
    }
}

// ============================================================================
// Interpreter Lifecycle
// ============================================================================

/// Create a new interpreter
/// Mirrors: Py_NewInterpreter()
pub fn newInterpreter() ?*ThreadState {
    if (!runtime.initialized) {
        return null;
    }

    // Allocate interpreter state
    var interp = std.heap.page_allocator.create(InterpreterState) catch {
        return null;
    };
    interp.* = .{};
    interp.id = runtime.next_interp_id;
    runtime.next_interp_id += 1;

    // Copy config from main interpreter
    if (getMainInterpreter()) |main_interp| {
        interp.config = main_interp.config;
    }

    // Allocate thread state
    var tstate = std.heap.page_allocator.create(ThreadState) catch {
        std.heap.page_allocator.destroy(interp);
        return null;
    };
    tstate.* = .{};
    tstate.interp = interp;
    tstate.thread_id = @intCast(std.Thread.getCurrentId());

    interp.threads_head = tstate;
    interp.threads_count = 1;
    interp._ready = true;

    return tstate;
}

/// End an interpreter
/// Mirrors: Py_EndInterpreter()
pub fn endInterpreter(tstate: *ThreadState) void {
    if (tstate.interp) |interp| {
        interp.finalizing = true;
        // Cleanup
        std.heap.page_allocator.destroy(interp);
    }
    std.heap.page_allocator.destroy(tstate);
}

// ============================================================================
// Thread State Management
// ============================================================================

/// Create a new thread state
/// Mirrors: PyThreadState_New()
pub fn threadStateNew(interp: *InterpreterState) ?*ThreadState {
    var tstate = std.heap.page_allocator.create(ThreadState) catch {
        return null;
    };
    tstate.* = .{};
    tstate.interp = interp;
    tstate.thread_id = @intCast(std.Thread.getCurrentId());

    // Link to interpreter's thread list
    tstate.next = interp.threads_head;
    if (interp.threads_head) |head| {
        head.prev = tstate;
    }
    interp.threads_head = tstate;
    interp.threads_count += 1;

    return tstate;
}

/// Delete a thread state
/// Mirrors: PyThreadState_Delete()
pub fn threadStateDelete(tstate: *ThreadState) void {
    if (tstate.interp) |interp| {
        // Unlink from interpreter's thread list
        if (tstate.prev) |prev| {
            prev.next = tstate.next;
        } else {
            interp.threads_head = tstate.next;
        }
        if (tstate.next) |next| {
            next.prev = tstate.prev;
        }
        interp.threads_count -= 1;
    }
    std.heap.page_allocator.destroy(tstate);
}

/// Swap thread state
/// Mirrors: PyThreadState_Swap()
pub fn threadStateSwap(new_tstate: ?*ThreadState) ?*ThreadState {
    const old = _tstate;
    _tstate = new_tstate;
    return old;
}

// ============================================================================
// GIL State Functions
// ============================================================================

/// Ensure GIL is held (acquire if needed)
/// Mirrors: PyGILState_Ensure()
pub fn gilStateEnsure() GILStateResult {
    const tstate = _tstate;
    if (tstate != null) {
        tstate.?.gilstate_counter += 1;
        return .locked;
    }

    // Need to acquire GIL and possibly create thread state
    if (getMainInterpreter()) |interp| {
        const new_tstate = threadStateNew(interp);
        if (new_tstate) |ts| {
            ts.gilstate_counter = 1;
            _tstate = ts;
            return .unlocked;
        }
    }
    return .unlocked;
}

/// Release GIL if we acquired it
/// Mirrors: PyGILState_Release()
pub fn gilStateRelease(state: GILStateResult) void {
    const tstate = _tstate orelse return;

    tstate.gilstate_counter -= 1;
    if (tstate.gilstate_counter == 0 and state == .unlocked) {
        // We created this thread state, so delete it
        threadStateDelete(tstate);
        _tstate = null;
    }
}

/// GIL state result
pub const GILStateResult = enum {
    locked,
    unlocked,
};

/// Check if current thread holds GIL
/// Mirrors: PyGILState_Check()
pub fn gilStateCheck() bool {
    return _tstate != null;
}

// ============================================================================
// Tests
// ============================================================================

test "status ok" {
    const status = Status.ok();
    try std.testing.expect(!status.isException());
    try std.testing.expect(!status.isExit());
    try std.testing.expect(!status.isError());
}

test "status error" {
    const status = Status.err("test error");
    try std.testing.expect(status.isException());
    try std.testing.expect(status.isError());
    try std.testing.expectEqualStrings("test error", status.err_msg.?);
}

test "preconfig defaults" {
    const config = PreConfig{};
    try std.testing.expect(config.parse_argv);
    try std.testing.expect(config.use_environment);
    try std.testing.expect(config.configure_locale);
}

test "config defaults" {
    const config = Config{};
    try std.testing.expect(config.site_import);
    try std.testing.expect(config.install_signal_handlers);
    try std.testing.expectEqual(@as(i32, 4300), config.int_max_str_digits);
}

test "runtime query before init" {
    // Runtime should not be initialized at test start
    // (unless other tests ran)
}

test "at_exit registration" {
    const initial = runtime.nexitfuncs;
    const result = atExit(struct {
        fn exit() void {}
    }.exit);
    try std.testing.expectEqual(@as(i32, 0), result);
    try std.testing.expectEqual(initial + 1, runtime.nexitfuncs);
    // Clean up
    runtime.nexitfuncs = initial;
}
