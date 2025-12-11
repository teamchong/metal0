/// pystate - Python Thread and Interpreter State
/// Mirrors cpython/Python/pystate.c
///
/// Manages interpreter and thread state:
/// - Interpreter state creation/deletion
/// - Thread state creation/deletion/binding
/// - Current thread state lookup
/// - GIL state management
/// - Cross-interpreter operations

const std = @import("std");
const allocator_helper = @import("utils.allocator_helper");
const builtin = @import("builtin");

// Re-export the core types from pylifecycle for consistency
pub const lifecycle = @import("pylifecycle.zig");

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
    /// Used by threading.local() and other thread-specific data
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
// Interpreter State
// ============================================================================

/// Python interpreter state
pub const InterpreterState = struct {
    /// Unique interpreter ID
    id: i64 = 0,

    /// Reference count for ID
    id_refcount: i64 = 0,

    /// Does interpreter require ID references?
    requires_idref: bool = false,

    /// Linked list pointers (global)
    next: ?*InterpreterState = null,
    prev: ?*InterpreterState = null,

    /// Is the interpreter ready for use?
    _ready: bool = false,

    /// Is the interpreter finalizing?
    finalizing: bool = false,

    /// How was this interpreter created?
    _whence: InterpreterWhence = .unknown,

    /// Feature flags
    feature_flags: u64 = 0,

    /// Configuration
    config: lifecycle.Config = .{},

    /// Thread state list
    threads: ThreadStateList = .{},

    /// Modules dictionary
    modules: ?*anyopaque = null,

    /// Builtins module
    builtins: ?*anyopaque = null,

    /// Import state
    imports: ImportState = .{},

    /// Codec state
    codecs: CodecState = .{},

    /// Warnings state
    warnings: ?*anyopaque = null,

    /// Audit hooks
    audit_hooks: ?*anyopaque = null,

    /// GC state
    gc: GCState = .{},

    /// Integer string conversion limit
    long_state: LongState = .{},

    /// Type cache
    type_cache: ?*anyopaque = null,

    /// Dict state
    dict_state: DictState = .{},

    /// CEVAL state
    ceval: CEvalState = .{},

    /// Allocator
    allocator: std.mem.Allocator = allocator_helper.fast_allocator,

    const Self = @This();

    pub fn isMain(self: *const Self) bool {
        return self.id == 0;
    }

    pub fn isReady(self: *const Self) bool {
        return self._ready;
    }
};

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

// ============================================================================
// Feature Flags
// ============================================================================

pub const FeatureFlags = struct {
    pub const USE_MAIN_OBMALLOC: u64 = 1 << 0;
    pub const FORK: u64 = 1 << 1;
    pub const EXEC: u64 = 1 << 2;
    pub const THREADS: u64 = 1 << 3;
    pub const DAEMON_THREADS: u64 = 1 << 4;
    pub const MULTI_INTERP_EXTENSIONS: u64 = 1 << 5;
};

// ============================================================================
// Thread-Local Storage
// ============================================================================

/// Current thread state (thread-local)
threadlocal var _tss_tstate: ?*ThreadState = null;

/// Current interpreter (thread-local, for faster access)
threadlocal var _tss_interp: ?*InterpreterState = null;

/// GILState thread state (thread-local)
threadlocal var _tss_gilstate: ?*ThreadState = null;

// ============================================================================
// Global State
// ============================================================================

/// Global interpreter list
var interpreters: InterpreterList = .{};

/// Next interpreter ID
var next_interp_id: i64 = 0;

/// Interpreter list
const InterpreterList = struct {
    head: ?*InterpreterState = null,
    main: ?*InterpreterState = null,
    count: u64 = 0,
};

// ============================================================================
// Thread State Functions
// ============================================================================

/// Create a new thread state
/// Mirrors: PyThreadState_New()
pub fn threadStateNew(interp: *InterpreterState) ?*ThreadState {
    return threadStateNewWithWhence(interp, .interp);
}

/// Create a new thread state with origin
fn threadStateNewWithWhence(interp: *InterpreterState, whence: ThreadStateWhence) ?*ThreadState {
    const tstate = interp.allocator.create(ThreadState) catch {
        return null;
    };
    tstate.* = .{};
    tstate.interp = interp;
    tstate._whence = whence;
    tstate.recursion_limit = interp.ceval.recursion_limit;
    tstate._status.initialized = true;

    // Assign ID
    tstate.id = interp.threads.next_id;
    interp.threads.next_id += 1;

    // Add to interpreter's thread list
    tstate.next = interp.threads.head;
    if (interp.threads.head) |head| {
        head.prev = tstate;
    }
    interp.threads.head = tstate;
    interp.threads.count += 1;

    return tstate;
}

/// Delete a thread state
/// Mirrors: PyThreadState_Delete()
pub fn threadStateDelete(tstate: *ThreadState) void {
    threadStateClear(tstate);

    if (tstate.interp) |interp| {
        // Remove from interpreter's thread list
        if (tstate.prev) |prev| {
            prev.next = tstate.next;
        } else {
            interp.threads.head = tstate.next;
        }
        if (tstate.next) |next| {
            next.prev = tstate.prev;
        }
        interp.threads.count -= 1;
    }

    // Deallocate
    const allocator = tstate.allocator;
    allocator.destroy(tstate);
}

/// Clear thread state
/// Mirrors: PyThreadState_Clear()
pub fn threadStateClear(tstate: *ThreadState) void {
    tstate._status.cleared = true;
    tstate.current_frame = null;
    tstate.curexc_type = null;
    tstate.curexc_value = null;
    tstate.curexc_traceback = null;
    tstate.c_profilefunc = null;
    tstate.c_tracefunc = null;
    tstate.c_profileobj = null;
    tstate.c_traceobj = null;
    tstate.async_gen_firstiter = null;
    tstate.async_gen_finalizer = null;
    tstate.context = null;
}

/// Bind thread state to current thread
/// Mirrors: _PyThreadState_Bind()
pub fn threadStateBind(tstate: *ThreadState) void {
    tstate.thread_id = std.Thread.getCurrentId();
    tstate._status.bound = true;
}

/// Get current thread state
/// Mirrors: PyThreadState_Get()
pub fn threadStateGet() ?*ThreadState {
    return _tss_tstate;
}

/// Swap thread states
/// Mirrors: PyThreadState_Swap()
pub fn threadStateSwap(new_tstate: ?*ThreadState) ?*ThreadState {
    const old = _tss_tstate;

    if (new_tstate) |ts| {
        _tss_tstate = ts;
        _tss_interp = ts.interp;
        ts._status.active = true;
    } else {
        if (old) |o| {
            o._status.active = false;
        }
        _tss_tstate = null;
        _tss_interp = null;
    }

    return old;
}

/// Get thread state dictionary (per-thread storage)
/// Mirrors: PyThreadState_GetDict()
/// Returns the per-thread dictionary, creating it lazily if needed.
/// The dictionary can be used for thread-local storage (threading.local).
pub fn threadStateGetDict(tstate: *ThreadState) ?*anyopaque {
    // Lazy creation - return existing dict or null
    // In a full implementation, we would create a dict here if null
    // For AOT code, thread-local storage is typically compile-time known
    return tstate.dict;
}

/// Set async exception on a thread
/// Mirrors: PyThreadState_SetAsyncExc()
/// This is used to raise exceptions in other threads (e.g., for thread interruption).
/// Returns the number of thread states modified (0, 1, or rarely more).
pub fn threadStateSetAsyncExc(id: u64, exc: ?*anyopaque) i32 {
    // Find the thread state with the given ID
    const interp = head_interp orelse return 0;
    var tstate = interp.threads_head;
    var count: i32 = 0;

    while (tstate) |ts| : (tstate = ts.next) {
        if (ts.thread_id == id) {
            // Set the async exception
            // The thread will check this and raise the exception at the next
            // safe point (between bytecode instructions)
            if (exc == null) {
                // Clear the async exception
                ts.curexc_type = null;
                ts.curexc_value = null;
                ts.curexc_traceback = null;
            } else {
                // Set the pending exception
                ts.curexc_type = exc;
            }
            count += 1;
        }
    }

    return count;
}

// ============================================================================
// Interpreter State Functions
// ============================================================================

/// Create a new interpreter state
/// Mirrors: PyInterpreterState_New()
pub fn interpreterStateNew() ?*InterpreterState {
    const interp = allocator_helper.fast_allocator.create(InterpreterState) catch {
        return null;
    };
    interp.* = .{};

    // Assign ID
    interp.id = next_interp_id;
    next_interp_id += 1;

    // Add to global list
    interp.next = interpreters.head;
    if (interpreters.head) |head| {
        head.prev = interp;
    }
    interpreters.head = interp;
    interpreters.count += 1;

    // First interpreter is main
    if (interpreters.main == null) {
        interpreters.main = interp;
        interp._whence = .runtime;
    }

    return interp;
}

/// Delete an interpreter state
/// Mirrors: PyInterpreterState_Delete()
pub fn interpreterStateDelete(interp: *InterpreterState) void {
    interpreterStateClear(interp);

    // Remove from global list
    if (interp.prev) |prev| {
        prev.next = interp.next;
    } else {
        interpreters.head = interp.next;
    }
    if (interp.next) |next| {
        next.prev = interp.prev;
    }
    interpreters.count -= 1;

    if (interpreters.main == interp) {
        interpreters.main = null;
    }

    allocator_helper.fast_allocator.destroy(interp);
}

/// Clear interpreter state
/// Mirrors: PyInterpreterState_Clear()
pub fn interpreterStateClear(interp: *InterpreterState) void {
    interp.finalizing = true;

    // Delete all thread states
    while (interp.threads.head) |tstate| {
        threadStateDelete(tstate);
    }

    interp.modules = null;
    interp.builtins = null;
}

/// Get interpreter ID
/// Mirrors: PyInterpreterState_GetID()
pub fn interpreterStateGetID(interp: *InterpreterState) i64 {
    return interp.id;
}

/// Get main interpreter
/// Mirrors: PyInterpreterState_Main()
pub fn interpreterStateMain() ?*InterpreterState {
    return interpreters.main;
}

/// Get head interpreter
/// Mirrors: PyInterpreterState_Head()
pub fn interpreterStateHead() ?*InterpreterState {
    return interpreters.head;
}

/// Get next interpreter
/// Mirrors: PyInterpreterState_Next()
pub fn interpreterStateNext(interp: *InterpreterState) ?*InterpreterState {
    return interp.next;
}

/// Get current interpreter
pub fn interpreterStateGet() ?*InterpreterState {
    return _tss_interp;
}

/// Check if interpreter is main
pub fn isMainInterpreter(interp: *const InterpreterState) bool {
    return interp == interpreters.main;
}

// ============================================================================
// GIL State Functions
// ============================================================================

/// GIL state
pub const GILState = enum {
    locked,
    unlocked,
};

/// Ensure GIL is held
/// Mirrors: PyGILState_Ensure()
pub fn gilStateEnsure() GILState {
    var tstate = _tss_tstate;

    if (tstate != null) {
        tstate.?.gilstate_counter += 1;
        return .locked;
    }

    // Create new thread state
    const interp = interpreters.main orelse return .unlocked;
    tstate = threadStateNewWithWhence(interp, .gilstate);
    if (tstate == null) {
        return .unlocked;
    }

    threadStateBind(tstate.?);
    _ = threadStateSwap(tstate);
    tstate.?.gilstate_counter = 1;
    _tss_gilstate = tstate;

    return .unlocked;
}

/// Release GIL
/// Mirrors: PyGILState_Release()
pub fn gilStateRelease(state: GILState) void {
    const tstate = _tss_tstate orelse return;

    tstate.gilstate_counter -= 1;

    if (tstate.gilstate_counter == 0 and state == .unlocked) {
        // We created this thread state, clean it up
        _ = threadStateSwap(null);
        threadStateDelete(tstate);
        _tss_gilstate = null;
    }
}

/// Check if GIL is held by current thread
/// Mirrors: PyGILState_Check()
pub fn gilStateCheck() bool {
    return _tss_tstate != null;
}

/// Get the thread state for GILState
/// Mirrors: PyGILState_GetThisThreadState()
pub fn gilStateGetThisThreadState() ?*ThreadState {
    return _tss_gilstate;
}

// ============================================================================
// Initialization
// ============================================================================

/// Initialize the pystate module
pub fn init() void {
    // Initialize global state
    interpreters = .{};
    next_interp_id = 0;
}

/// Finalize the pystate module
pub fn fini() void {
    // Clean up all interpreters
    while (interpreters.head) |interp| {
        interpreterStateDelete(interp);
    }
}

// ============================================================================
// Utility Functions
// ============================================================================

/// Get number of interpreters
pub fn getInterpreterCount() u64 {
    return interpreters.count;
}

/// Get thread count for an interpreter
pub fn getThreadCount(interp: *InterpreterState) u64 {
    return interp.threads.count;
}

/// Enumerate all thread states in an interpreter
pub fn enumerateThreadStates(interp: *InterpreterState, callback: *const fn (*ThreadState) void) void {
    var tstate = interp.threads.head;
    while (tstate) |ts| {
        callback(ts);
        tstate = ts.next;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "interpreter state new/delete" {
    init();
    defer fini();

    const interp = interpreterStateNew();
    try std.testing.expect(interp != null);
    try std.testing.expectEqual(@as(i64, 0), interp.?.id);
    try std.testing.expect(isMainInterpreter(interp.?));

    interpreterStateDelete(interp.?);
    try std.testing.expectEqual(@as(u64, 0), interpreters.count);
}

test "thread state new/delete" {
    init();
    defer fini();

    const interp = interpreterStateNew().?;
    defer interpreterStateDelete(interp);

    const tstate = threadStateNew(interp);
    try std.testing.expect(tstate != null);
    try std.testing.expectEqual(@as(u64, 0), tstate.?.id);
    try std.testing.expectEqual(@as(u64, 1), interp.threads.count);

    threadStateDelete(tstate.?);
    try std.testing.expectEqual(@as(u64, 0), interp.threads.count);
}

test "thread state swap" {
    init();
    defer fini();

    const interp = interpreterStateNew().?;
    defer interpreterStateDelete(interp);

    const tstate = threadStateNew(interp).?;
    defer threadStateDelete(tstate);

    try std.testing.expect(threadStateGet() == null);

    const old = threadStateSwap(tstate);
    try std.testing.expect(old == null);
    try std.testing.expectEqual(tstate, threadStateGet().?);

    _ = threadStateSwap(null);
    try std.testing.expect(threadStateGet() == null);
}

test "gilstate" {
    init();
    defer fini();

    // Create main interpreter
    const interp = interpreterStateNew().?;
    defer interpreterStateDelete(interp);

    try std.testing.expect(!gilStateCheck());

    const state = gilStateEnsure();
    try std.testing.expect(gilStateCheck());

    gilStateRelease(state);
}

test "interpreter iteration" {
    init();
    defer fini();

    const interp1 = interpreterStateNew().?;
    const interp2 = interpreterStateNew().?;
    defer interpreterStateDelete(interp1);
    defer interpreterStateDelete(interp2);

    try std.testing.expectEqual(@as(u64, 2), getInterpreterCount());

    var count: u64 = 0;
    var current = interpreterStateHead();
    while (current) |i| {
        count += 1;
        current = interpreterStateNext(i);
    }
    try std.testing.expectEqual(@as(u64, 2), count);
}
