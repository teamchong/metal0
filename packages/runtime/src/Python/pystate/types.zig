/// types - Thread and Interpreter State Types
/// Core type definitions for pystate module.

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");

// ============================================================================
// Thread State Status
// ============================================================================

/// Thread state status flags
pub const ThreadStateStatus = struct {
    /// Thread state is initialized
    initialized: bool = false,

    /// Thread state is bound to an OS thread
    bound: bool = false,

    /// Thread state has been unbound
    unbound: bool = false,

    /// Thread state is active (running Python code)
    active: bool = false,

    /// Thread state is bound for GILState
    bound_gilstate: bool = false,

    /// Thread is finalizing
    finalizing: bool = false,

    /// Thread cleared its exception state
    cleared: bool = false,
};

/// Exception info structure
pub const ExceptionInfo = struct {
    exc_type: ?*anyopaque = null,
    exc_value: ?*anyopaque = null,
    exc_traceback: ?*anyopaque = null,
};

/// Profile/trace function types
pub const ProfileFunc = *const fn (*ThreadState, ?*anyopaque, i32, ?*anyopaque) i32;
pub const TraceFunc = *const fn (*ThreadState, ?*anyopaque, i32, ?*anyopaque) i32;

/// Thread state origin
pub const ThreadStateWhence = enum {
    unknown,
    interp, // Created by interpreter
    threading, // Created by threading module
    gilstate, // Created by GILState
    exec, // Created by exec
};

// ============================================================================
// Thread State
// ============================================================================

/// Python thread state
pub const ThreadState = struct {
    /// Pointer to the interpreter state
    interp: ?*InterpreterState = null,

    /// Status flags
    _status: ThreadStateStatus = .{},

    /// Thread ID (OS thread identifier)
    thread_id: u64 = 0,

    /// Native thread ID (platform-specific)
    native_thread_id: u64 = 0,

    /// Unique ID for this thread state
    id: u64 = 0,

    /// Linked list pointers (within interpreter)
    next: ?*ThreadState = null,
    prev: ?*ThreadState = null,

    /// Current recursion depth
    recursion_depth: u32 = 0,

    /// Recursion limit
    recursion_limit: u32 = 1000,

    /// Headroom for stack overflow recovery
    recursion_headroom: u32 = 50,

    /// Stack depth for recursion checking
    py_recursion_depth: u32 = 0,
    c_recursion_depth: u32 = 0,

    /// Exception state
    curexc_type: ?*anyopaque = null,
    curexc_value: ?*anyopaque = null,
    curexc_traceback: ?*anyopaque = null,

    /// Previous exception (for context)
    exc_info: ExceptionInfo = .{},

    /// Current frame being executed
    current_frame: ?*anyopaque = null,

    /// Tracing/profiling state
    tracing: bool = false,
    use_tracing: bool = false,
    c_profilefunc: ?ProfileFunc = null,
    c_tracefunc: ?TraceFunc = null,
    c_profileobj: ?*anyopaque = null,
    c_traceobj: ?*anyopaque = null,

    /// GIL state counter
    gilstate_counter: u32 = 0,

    /// Async generator hooks
    async_gen_firstiter: ?*anyopaque = null,
    async_gen_finalizer: ?*anyopaque = null,

    /// Context variables
    context: ?*anyopaque = null,
    context_ver: u64 = 0,

    /// Critical section state (for free-threading)
    critical_section: u64 = 0,

    /// What created this thread state
    _whence: ThreadStateWhence = .unknown,

    /// Allocator used for this thread state
    allocator: std.mem.Allocator = allocator_helper.fast_allocator,

    /// Per-thread dictionary for thread-local storage
    dict: ?*anyopaque = null,

    const Self = @This();

    pub fn isAlive(self: *const Self) bool {
        return self._status.initialized and !self._status.finalizing;
    }

    pub fn isBound(self: *const Self) bool {
        return self._status.bound and !self._status.unbound;
    }

    pub fn isActive(self: *const Self) bool {
        return self._status.active;
    }
};

// ============================================================================
// Interpreter Sub-States
// ============================================================================

/// Thread state list
pub const ThreadStateList = struct {
    head: ?*ThreadState = null,
    count: u64 = 0,
    next_id: u64 = 0,
};

/// Import state
pub const ImportState = struct {
    modules: ?*anyopaque = null,
    modules_by_index: ?*anyopaque = null,
    importlib: ?*anyopaque = null,
    import_func: ?*anyopaque = null,
    dlopenflags: i32 = 0,
};

/// Codec state
pub const CodecState = struct {
    search_path: ?*anyopaque = null,
    search_cache: ?*anyopaque = null,
    error_registry: ?*anyopaque = null,
};

/// GC state (per-interpreter)
pub const GCState = struct {
    enabled: bool = true,
    debug: u32 = 0,
    generations: [3]u64 = .{ 0, 0, 0 },
    threshold: [3]u64 = .{ 700, 10, 10 },
};

/// Long (int) state
pub const LongState = struct {
    max_str_digits: i32 = 4300,
};

/// Dict state
pub const DictState = struct {
    global_version: u64 = 0,
    next_keys_version: u64 = 2,
};

/// CEVAL state
pub const CEvalState = struct {
    recursion_limit: u32 = 1000,
    tracing_possible: bool = false,
    eval_breaker: u32 = 0,
    gil_drop_request: bool = false,
    pending_calls: ?*anyopaque = null,
    own_gil: bool = true,
};

/// Interpreter origin
pub const InterpreterWhence = enum {
    unknown,
    runtime, // Main interpreter
    legacy, // Py_NewInterpreter
    capi, // Py_NewInterpreterFromConfig
    xi, // Cross-interpreter
};

/// Feature flags
pub const FeatureFlags = struct {
    pub const USE_MAIN_OBMALLOC: u64 = 1 << 0;
    pub const FORK: u64 = 1 << 1;
    pub const EXEC: u64 = 1 << 2;
    pub const THREADS: u64 = 1 << 3;
    pub const DAEMON_THREADS: u64 = 1 << 4;
    pub const MULTI_INTERP_EXTENSIONS: u64 = 1 << 5;
};

// Forward declaration for InterpreterState
pub const InterpreterState = @import("interpreter.zig").InterpreterState;

/// GIL state
pub const GILState = enum {
    locked,
    unlocked,
};
