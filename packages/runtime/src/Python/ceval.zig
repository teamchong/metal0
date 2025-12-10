/// ceval - Central Execution Loop and Interpreter Control
/// Mirrors cpython/Python/ceval.c
///
/// This module provides:
/// - Bytecode execution machinery (_PyEval_EvalFrameDefault equivalent)
/// - Pending calls mechanism (Py_AddPendingCall, Py_MakePendingCalls)
/// - Tracing and profiling hooks
/// - Thread switching and GIL management
/// - Recursion limit checking
/// - Binary operations tables
/// - Frame evaluation control

const std = @import("std");
const builtin = @import("builtin");
const runtime = @import("../runtime.zig");

// ============================================================================
// Pending Call System
// ============================================================================

/// Maximum pending calls per interpreter
pub const PENDING_CALLS_ARRAY_SIZE = 32;

/// Maximum pending calls to process per pass
pub const MAX_PENDING_CALLS_LOOP = 100;

/// Pending call function signature
/// Mirrors: int (*func)(void *arg)
pub const PendingCallFunc = *const fn (arg: ?*anyopaque) callconv(.C) c_int;

/// Single pending call entry
const PendingCall = struct {
    func: ?PendingCallFunc = null,
    arg: ?*anyopaque = null,
};

/// Result codes for AddPendingCall
pub const AddPendingResult = enum(c_int) {
    success = 0,
    full = -1,
};

/// Pending calls state for an interpreter
/// Mirrors: struct _pending_calls
pub const PendingCalls = struct {
    /// Mutex for thread safety
    mutex: std.Thread.Mutex = .{},
    /// Number of pending calls
    npending: i32 = 0,
    /// Maximum allowed pending calls
    max: i32 = PENDING_CALLS_ARRAY_SIZE,
    /// Maximum calls to handle per pass (0 = unlimited)
    maxloop: i32 = MAX_PENDING_CALLS_LOOP,
    /// Ring buffer of pending calls
    calls: [PENDING_CALLS_ARRAY_SIZE]PendingCall = [_]PendingCall{.{}} ** PENDING_CALLS_ARRAY_SIZE,
    /// First valid entry index
    first: i32 = 0,
    /// Next empty slot index
    next: i32 = 0,
    /// Thread currently handling calls (null if none)
    handling_thread: ?std.Thread.Id = null,

    /// Initialize pending calls state
    pub fn init() PendingCalls {
        return .{};
    }

    /// Add a pending call to the queue
    /// Returns: success (0) or full (-1)
    pub fn add(self: *PendingCalls, func: PendingCallFunc, arg: ?*anyopaque) AddPendingResult {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.npending >= self.max) {
            return .full;
        }

        self.calls[@intCast(self.next)] = .{
            .func = func,
            .arg = arg,
        };
        self.next = @mod(self.next + 1, @as(i32, PENDING_CALLS_ARRAY_SIZE));
        self.npending += 1;

        return .success;
    }

    /// Pop the next pending call from the queue
    fn pop(self: *PendingCalls) ?PendingCall {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.npending == 0) {
            return null;
        }

        const call = self.calls[@intCast(self.first)];
        self.calls[@intCast(self.first)] = .{};
        self.first = @mod(self.first + 1, @as(i32, PENDING_CALLS_ARRAY_SIZE));
        self.npending -= 1;

        return call;
    }

    /// Process pending calls
    /// Returns: 0 on success, -1 on error
    pub fn makeCalls(self: *PendingCalls) c_int {
        const thread_id = std.Thread.getCurrentId();

        // Check if another thread is already handling
        self.mutex.lock();
        if (self.handling_thread != null) {
            self.mutex.unlock();
            return 0;
        }
        self.handling_thread = thread_id;
        self.mutex.unlock();

        defer {
            self.mutex.lock();
            self.handling_thread = null;
            self.mutex.unlock();
        }

        var calls_made: i32 = 0;
        const max_calls = if (self.maxloop > 0) self.maxloop else std.math.maxInt(i32);

        while (calls_made < max_calls) {
            const call = self.pop() orelse break;

            if (call.func) |func| {
                const result = func(call.arg);
                if (result != 0) {
                    return -1;
                }
            }
            calls_made += 1;
        }

        return 0;
    }

    /// Check if there are pending calls
    pub fn hasPending(self: *PendingCalls) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.npending > 0;
    }
};

// ============================================================================
// Global Pending Calls (Main Thread)
// ============================================================================

/// Global pending calls for main thread (signal handlers)
var pending_mainthread: PendingCalls = PendingCalls.init();

/// Add a pending call (main thread)
/// Mirrors: Py_AddPendingCall()
pub fn addPendingCall(func: PendingCallFunc, arg: ?*anyopaque) c_int {
    return @intFromEnum(pending_mainthread.add(func, arg));
}

/// Process pending calls (main thread)
/// Mirrors: Py_MakePendingCalls()
pub fn makePendingCalls() c_int {
    return pending_mainthread.makeCalls();
}

// ============================================================================
// CEval State (Per-Interpreter)
// ============================================================================

/// CEval state for an interpreter
/// Mirrors: struct _ceval_state
pub const CEvalState = struct {
    /// Instrumentation version for breaking eval loop
    instrumentation_version: usize = 0,
    /// Recursion limit (default 1000)
    recursion_limit: i32 = 1000,
    /// Whether this interpreter owns its GIL
    own_gil: bool = true,
    /// Pending calls for this interpreter
    pending: PendingCalls = PendingCalls.init(),
    /// Check interval for signal/thread switching
    check_interval: i32 = 100,
    /// Switch interval in microseconds
    switch_interval: u64 = 5000, // 5ms default
    /// GIL drop request flag
    gil_drop_request: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// Eval breaker flags
    eval_breaker: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),

    /// Initialize ceval state
    pub fn init() CEvalState {
        return .{};
    }

    /// Set recursion limit
    pub fn setRecursionLimit(self: *CEvalState, limit: i32) !void {
        if (limit < 1) {
            return error.ValueError;
        }
        self.recursion_limit = limit;
    }

    /// Get recursion limit
    pub fn getRecursionLimit(self: *CEvalState) i32 {
        return self.recursion_limit;
    }

    /// Request GIL drop for thread switching
    pub fn requestGilDrop(self: *CEvalState) void {
        self.gil_drop_request.store(true, .release);
        self.setEvalBreakerBit(EVAL_BREAKER_GIL_DROP);
    }

    /// Clear GIL drop request
    pub fn clearGilDropRequest(self: *CEvalState) void {
        self.gil_drop_request.store(false, .release);
        self.clearEvalBreakerBit(EVAL_BREAKER_GIL_DROP);
    }

    /// Set eval breaker bit
    pub fn setEvalBreakerBit(self: *CEvalState, bit: usize) void {
        _ = self.eval_breaker.fetchOr(bit, .acq_rel);
    }

    /// Clear eval breaker bit
    pub fn clearEvalBreakerBit(self: *CEvalState, bit: usize) void {
        _ = self.eval_breaker.fetchAnd(~bit, .acq_rel);
    }

    /// Check if eval should break
    pub fn shouldBreak(self: *CEvalState) bool {
        return self.eval_breaker.load(.acquire) != 0;
    }
};

// ============================================================================
// Eval Breaker Flags
// ============================================================================

/// Eval breaker bit flags
pub const EVAL_BREAKER_GIL_DROP: usize = 1 << 0;
pub const EVAL_BREAKER_PENDING_CALLS: usize = 1 << 1;
pub const EVAL_BREAKER_SIGNALS: usize = 1 << 2;
pub const EVAL_BREAKER_TRACING: usize = 1 << 3;
pub const EVAL_BREAKER_GC: usize = 1 << 4;
pub const EVAL_BREAKER_STOP_WORLD: usize = 1 << 5;

// ============================================================================
// Tracing and Profiling
// ============================================================================

/// Trace/profile event types
/// Mirrors: PyTrace_* constants
pub const TraceEvent = enum(c_int) {
    call = 0,
    exception = 1,
    line = 2,
    return_ = 3,
    c_call = 4,
    c_exception = 5,
    c_return = 6,
    opcode = 7,
};

/// Trace function signature
/// Mirrors: Py_tracefunc
pub const TraceFunc = *const fn (
    obj: ?*anyopaque, // PyObject* self
    frame: ?*anyopaque, // PyFrameObject* frame
    what: TraceEvent,
    arg: ?*anyopaque, // PyObject* arg
) callconv(.C) c_int;

/// Thread-local trace function
threadlocal var trace_func: ?TraceFunc = null;
threadlocal var trace_arg: ?*anyopaque = null;

/// Thread-local profile function
threadlocal var profile_func: ?TraceFunc = null;
threadlocal var profile_arg: ?*anyopaque = null;

/// Set trace function for current thread
/// Mirrors: PyEval_SetTrace()
pub fn setTrace(func: ?TraceFunc, arg: ?*anyopaque) void {
    trace_func = func;
    trace_arg = arg;
}

/// Get trace function for current thread
/// Mirrors: PyEval_GetTrace() (internal)
pub fn getTrace() ?TraceFunc {
    return trace_func;
}

/// Set profile function for current thread
/// Mirrors: PyEval_SetProfile()
pub fn setProfile(func: ?TraceFunc, arg: ?*anyopaque) void {
    profile_func = func;
    profile_arg = arg;
}

/// Get profile function for current thread
/// Mirrors: PyEval_GetProfile() (internal)
pub fn getProfile() ?TraceFunc {
    return profile_func;
}

/// Call trace function if set
pub fn callTrace(frame: ?*anyopaque, event: TraceEvent, arg: ?*anyopaque) c_int {
    if (trace_func) |func| {
        return func(trace_arg, frame, event, arg);
    }
    return 0;
}

/// Call profile function if set
pub fn callProfile(frame: ?*anyopaque, event: TraceEvent, arg: ?*anyopaque) c_int {
    if (profile_func) |func| {
        // Profile only sees call/return events
        switch (event) {
            .call, .return_, .c_call, .c_return, .c_exception => {
                return func(profile_arg, frame, event, arg);
            },
            else => {},
        }
    }
    return 0;
}

// ============================================================================
// Binary Operations Table
// ============================================================================

/// Binary operation types for the bytecode interpreter
pub const BinaryOp = enum(u8) {
    add = 0,
    and_ = 1,
    floor_div = 2,
    lshift = 3,
    matmul = 4,
    mul = 5,
    mod = 6,
    or_ = 7,
    power = 8,
    rshift = 9,
    sub = 10,
    true_div = 11,
    xor_ = 12,
    inplace_add = 13,
    inplace_and = 14,
    inplace_floor_div = 15,
    inplace_lshift = 16,
    inplace_matmul = 17,
    inplace_mul = 18,
    inplace_mod = 19,
    inplace_or = 20,
    inplace_power = 21,
    inplace_rshift = 22,
    inplace_sub = 23,
    inplace_true_div = 24,
    inplace_xor = 25,
};

/// Comparison operations
pub const CompareOp = enum(u8) {
    lt = 0,
    le = 1,
    eq = 2,
    ne = 3,
    gt = 4,
    ge = 5,
};

// ============================================================================
// Recursion Checking
// ============================================================================

/// Current recursion depth (thread-local)
threadlocal var recursion_depth: i32 = 0;

/// Recursion limit (global default)
var global_recursion_limit: i32 = 1000;

/// Enter a call frame, checking recursion limit
/// Mirrors: Py_EnterRecursiveCall()
pub fn enterRecursiveCall(where: []const u8) !void {
    _ = where;
    recursion_depth += 1;
    if (recursion_depth > global_recursion_limit) {
        recursion_depth -= 1;
        return error.RecursionError;
    }
}

/// Leave a call frame
/// Mirrors: Py_LeaveRecursiveCall()
pub fn leaveRecursiveCall() void {
    recursion_depth -= 1;
}

/// Get current recursion depth
pub fn getRecursionDepth() i32 {
    return recursion_depth;
}

/// Set recursion limit
/// Mirrors: Py_SetRecursionLimit()
pub fn setRecursionLimit(limit: i32) !void {
    if (limit < 1) {
        return error.ValueError;
    }
    global_recursion_limit = limit;
}

/// Get recursion limit
/// Mirrors: Py_GetRecursionLimit()
pub fn getRecursionLimit() i32 {
    return global_recursion_limit;
}

// ============================================================================
// Check Interval (Legacy)
// ============================================================================

/// Legacy check interval for Py_CheckInterval
var check_interval: i32 = 100;
var ticker: i32 = 0;

/// Set check interval (deprecated in Python 3.2+)
/// Mirrors: _Py_SetCheckInterval() (internal)
pub fn setCheckInterval(interval: i32) void {
    check_interval = interval;
    ticker = interval;
}

/// Get check interval
pub fn getCheckInterval() i32 {
    return check_interval;
}

/// Decrement ticker and return true if signals should be checked
pub fn checkTicker() bool {
    ticker -= 1;
    if (ticker <= 0) {
        ticker = check_interval;
        return true;
    }
    return false;
}

// ============================================================================
// Frame Evaluation Control
// ============================================================================

/// Frame evaluation function type
/// Mirrors: _PyFrameEvalFunction
pub const FrameEvalFunction = *const fn (
    tstate: ?*anyopaque, // PyThreadState*
    frame: ?*anyopaque, // _PyInterpreterFrame*
    throwflag: c_int,
) callconv(.C) ?*anyopaque; // PyObject*

/// Custom frame evaluation function (for debuggers, coverage tools)
threadlocal var custom_eval_frame: ?FrameEvalFunction = null;

/// Set custom frame evaluator
/// Mirrors: _PyInterpreterState_SetEvalFrameFunc()
pub fn setEvalFrameFunc(func: ?FrameEvalFunction) void {
    custom_eval_frame = func;
}

/// Get custom frame evaluator
/// Mirrors: _PyInterpreterState_GetEvalFrameFunc()
pub fn getEvalFrameFunc() ?FrameEvalFunction {
    return custom_eval_frame;
}

// ============================================================================
// Coroutine Support
// ============================================================================

/// Coroutine origin tracking depth (for async debugging)
threadlocal var coroutine_origin_tracking_depth: i32 = 0;

/// Set coroutine origin tracking depth
/// Mirrors: _PyEval_SetCoroutineOriginTrackingDepth()
pub fn setCoroutineOriginTrackingDepth(depth: i32) !void {
    if (depth < 0) {
        return error.ValueError;
    }
    coroutine_origin_tracking_depth = depth;
}

/// Get coroutine origin tracking depth
/// Mirrors: _PyEval_GetCoroutineOriginTrackingDepth()
pub fn getCoroutineOriginTrackingDepth() i32 {
    return coroutine_origin_tracking_depth;
}

/// Async generator first iteration hook
threadlocal var async_gen_firstiter: ?*anyopaque = null;

/// Async generator finalizer hook
threadlocal var async_gen_finalizer: ?*anyopaque = null;

/// Set async generator first iteration hook
/// Mirrors: _PyEval_SetAsyncGenFirstiter()
pub fn setAsyncGenFirstiter(firstiter: ?*anyopaque) void {
    async_gen_firstiter = firstiter;
}

/// Get async generator first iteration hook
/// Mirrors: _PyEval_GetAsyncGenFirstiter()
pub fn getAsyncGenFirstiter() ?*anyopaque {
    return async_gen_firstiter;
}

/// Set async generator finalizer hook
/// Mirrors: _PyEval_SetAsyncGenFinalizer()
pub fn setAsyncGenFinalizer(finalizer: ?*anyopaque) void {
    async_gen_finalizer = finalizer;
}

/// Get async generator finalizer hook
/// Mirrors: _PyEval_GetAsyncGenFinalizer()
pub fn getAsyncGenFinalizer() ?*anyopaque {
    return async_gen_finalizer;
}

// ============================================================================
// Signal Handling Integration
// ============================================================================

/// Signal received flag (set by signal handlers)
var signal_received: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

/// Trip signal to wake up eval loop
/// Mirrors: Py_AddPendingCall() with trip_signal
pub fn tripSignal() void {
    signal_received.store(true, .release);
}

/// Check and clear signal flag
pub fn checkAndClearSignal() bool {
    return signal_received.swap(false, .acq_rel);
}

// ============================================================================
// Stop-the-World Support (for GC)
// ============================================================================

/// Stop-the-world request flag
var stop_the_world_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

/// Request stop-the-world (for GC)
/// Mirrors: _PyEval_StopTheWorld()
pub fn stopTheWorld() void {
    stop_the_world_requested.store(true, .release);
}

/// Resume from stop-the-world
/// Mirrors: _PyEval_StartTheWorld()
pub fn startTheWorld() void {
    stop_the_world_requested.store(false, .release);
}

/// Check if stop-the-world is requested
pub fn isWorldStopped() bool {
    return stop_the_world_requested.load(.acquire);
}

// ============================================================================
// Eval Cache Integration (Reexport existing functionality)
// ============================================================================

const eval_cache = @import("eval_cache.zig");

/// Cached eval function - evaluate Python expression
/// Uses LRU bytecode cache for performance
pub const evalCached = eval_cache.evalCached;

/// Initialize eval cache
pub const initCache = eval_cache.initCache;

/// Clear eval cache
pub const clearCache = eval_cache.clearCache;

/// Get cache statistics
pub const getCacheStats = eval_cache.getCacheStats;

/// Deinitialize cache
pub const deinitCache = eval_cache.deinitCache;

/// Python eval() builtin - alias for evalCached
pub const eval = evalCached;

// ============================================================================
// Bytecode Execution (High-Level)
// ============================================================================

/// Evaluate a code object
/// Mirrors: PyEval_EvalCode()
pub fn evalCode(
    allocator: std.mem.Allocator,
    code: anytype,
    globals: anytype,
    locals: anytype,
) !?*anyopaque {
    _ = allocator;
    _ = code;
    _ = globals;
    _ = locals;
    // In AOT compilation, this is a stub
    // Real bytecode execution happens at compile time
    return null;
}

/// Evaluate with keyword arguments
/// Mirrors: PyEval_EvalCodeEx()
pub fn evalCodeEx(
    allocator: std.mem.Allocator,
    code: anytype,
    globals: anytype,
    locals: anytype,
    args: anytype,
    kwargs: anytype,
    defaults: anytype,
    kwdefaults: anytype,
    closure: anytype,
) !?*anyopaque {
    _ = allocator;
    _ = code;
    _ = globals;
    _ = locals;
    _ = args;
    _ = kwargs;
    _ = defaults;
    _ = kwdefaults;
    _ = closure;
    // Stub for AOT
    return null;
}

// ============================================================================
// Call Tracing (for debugging/profiling tools)
// ============================================================================

/// Enable tracing for all threads
/// Mirrors: PyEval_SetTraceAllThreads()
pub fn setTraceAllThreads(func: ?TraceFunc, arg: ?*anyopaque) void {
    // In single-threaded context, same as setTrace
    setTrace(func, arg);
}

/// Enable profiling for all threads
/// Mirrors: PyEval_SetProfileAllThreads()
pub fn setProfileAllThreads(func: ?TraceFunc, arg: ?*anyopaque) void {
    // In single-threaded context, same as setProfile
    setProfile(func, arg);
}

// ============================================================================
// Frame Access
// ============================================================================

/// Get current execution frame (thread-local)
threadlocal var current_frame: ?*anyopaque = null;

/// Get current frame
/// Mirrors: _PyEval_GetFrame()
pub fn getFrame() ?*anyopaque {
    return current_frame;
}

/// Set current frame
pub fn setFrame(frame: ?*anyopaque) void {
    current_frame = frame;
}

/// Get builtins from current frame
/// Mirrors: _PyEval_GetBuiltins()
pub fn getBuiltins() ?*anyopaque {
    // Would extract from current frame's globals['__builtins__']
    return null;
}

/// Get globals from current frame
/// Mirrors: _PyEval_GetGlobals()
pub fn getGlobals() ?*anyopaque {
    // Would extract from current frame
    return null;
}

/// Get locals from current frame
/// Mirrors: _PyEval_GetFrameLocals()
pub fn getFrameLocals() ?*anyopaque {
    // Would extract from current frame
    return null;
}

// ============================================================================
// Exception Match (for pattern matching)
// ============================================================================

/// Match exception group
/// Mirrors: _PyEval_ExceptionGroupMatch()
/// Returns (match, rest) tuple where:
///   - match: ExceptionGroup containing exceptions that match the type
///   - rest: ExceptionGroup containing exceptions that don't match (or null if all matched)
pub fn exceptionGroupMatch(
    exc_value: ?*anyopaque,
    match_type: ?*anyopaque,
) struct { ?*anyopaque, ?*anyopaque } {
    const exc = exc_value orelse return .{ null, null };
    const type_to_match = match_type orelse return .{ null, null };

    // Get the PyObject pointers
    const exc_obj: *runtime.PyObject = @ptrCast(@alignCast(exc));
    const type_obj: *runtime.PyObject = @ptrCast(@alignCast(type_to_match));

    // Check if this exception matches the type
    if (exceptionTypeMatches(exc_obj, type_obj)) {
        return .{ exc, null };
    }
    return .{ null, exc };
}

/// Helper to check if an exception matches a type
fn exceptionTypeMatches(exc: *runtime.PyObject, type_obj: *runtime.PyObject) bool {
    // Get exception type
    const exc_type = exc.ob_type orelse return false;

    // Check if type_obj is a type object we should compare against
    // type_obj could be either a type object or an instance
    const match_type_ptr = type_obj.ob_type orelse return false;

    // Direct type match
    if (exc_type == match_type_ptr) return true;

    // Check type name match for common exceptions
    const exc_name = exc_type.tp_name;
    const match_name = match_type_ptr.tp_name;

    // If names match, it's a match
    if (std.mem.eql(u8, std.mem.span(exc_name), std.mem.span(match_name))) {
        return true;
    }

    // Check if exc type is subclass of match type using type hierarchy
    return runtime.isSubclass(exc_type, match_type_ptr);
}

/// Match mapping keys for pattern matching
/// Mirrors: _PyEval_MatchKeys()
/// Given a mapping and a tuple of keys, return a tuple of values if all keys exist
/// Returns null if any key is missing
pub fn matchKeys(
    map: ?*anyopaque,
    keys: ?*anyopaque,
) ?*anyopaque {
    const map_ptr = map orelse return null;
    const keys_ptr = keys orelse return null;

    const map_obj: *runtime.PyObject = @ptrCast(@alignCast(map_ptr));
    const keys_obj: *runtime.PyObject = @ptrCast(@alignCast(keys_ptr));

    // Verify map is a dict
    if (!runtime.PyDict_Check(map_obj)) {
        return null;
    }

    // Get the keys - must be a list or tuple
    const keys_type = runtime.getTypeId(keys_obj);
    const allocator = runtime.c_allocator;

    // Collect values for each key
    var values = std.ArrayList(*runtime.PyObject).init(allocator);
    defer values.deinit();

    if (keys_type == .list) {
        const list_obj: *runtime.PyListObject = @ptrCast(@alignCast(keys_obj));
        const items_ptr = list_obj.ob_item orelse return null;
        const list_size: usize = @intCast(list_obj.ob_size);

        for (items_ptr[0..list_size]) |key_obj| {
            // Key must be a string for dict lookup
            const key_type = runtime.getTypeId(key_obj);
            if (key_type != .string) {
                return null;
            }

            const key_str = runtime.PyString.getValue(key_obj);

            // Look up value in dict
            if (runtime.PyDict.get(map_obj, key_str)) |value| {
                values.append(value) catch return null;
            } else {
                // Key not found - pattern doesn't match
                return null;
            }
        }
    } else if (keys_type == .tuple) {
        const tuple_obj: *runtime.PyTupleObject = @ptrCast(@alignCast(keys_obj));
        const items_ptr = tuple_obj.ob_item orelse return null;
        const tuple_size: usize = @intCast(tuple_obj.ob_size);

        for (items_ptr[0..tuple_size]) |key_obj| {
            // Key must be a string for dict lookup
            const key_type = runtime.getTypeId(key_obj);
            if (key_type != .string) {
                return null;
            }

            const key_str = runtime.PyString.getValue(key_obj);

            // Look up value in dict
            if (runtime.PyDict.get(map_obj, key_str)) |value| {
                values.append(value) catch return null;
            } else {
                // Key not found - pattern doesn't match
                return null;
            }
        }
    } else {
        return null;
    }

    // Create result tuple with the values
    const result = runtime.PyTuple.create(allocator, values.items) catch return null;
    return @ptrCast(result);
}

/// Match class for pattern matching
/// Mirrors: _PyEval_MatchClass()
/// Matches a subject against a class pattern with positional and keyword arguments
/// Returns a tuple of matched values or null if pattern doesn't match
pub fn matchClass(
    subject: ?*anyopaque,
    type_: ?*anyopaque,
    nargs: usize,
    kwargs: ?*anyopaque,
) ?*anyopaque {
    const subj_ptr = subject orelse return null;
    const type_ptr = type_ orelse return null;

    const subj_obj: *runtime.PyObject = @ptrCast(@alignCast(subj_ptr));
    const type_obj: *runtime.PyObject = @ptrCast(@alignCast(type_ptr));

    // Check if subject is an instance of the type
    const subj_type = subj_obj.ob_type orelse return null;
    const match_type: *runtime.PyTypeObject = @ptrCast(@alignCast(type_obj));

    // Check type match using isinstance logic
    if (subj_type != match_type and !runtime.isSubclass(subj_type, match_type)) {
        return null;
    }

    const allocator = runtime.c_allocator;

    // Collect matched values
    var matched_values = std.ArrayList(*runtime.PyObject).init(allocator);
    defer matched_values.deinit();

    // For positional args, we'd extract __match_args__ from the type
    // and get corresponding attributes from the subject
    // This is a simplified implementation for common patterns

    // Handle builtin types with known structures
    const type_id = runtime.getTypeId(subj_obj);
    switch (type_id) {
        .tuple => {
            // For tuples, positional args are the elements
            const tuple_obj: *runtime.PyTupleObject = @ptrCast(@alignCast(subj_obj));
            const items_ptr = tuple_obj.ob_item orelse return null;
            const tuple_size: usize = @intCast(tuple_obj.ob_size);

            if (tuple_size >= nargs) {
                for (items_ptr[0..nargs]) |item| {
                    matched_values.append(item) catch return null;
                }
            } else {
                return null;
            }
        },
        .list => {
            // For lists, positional args are the elements
            const list_obj: *runtime.PyListObject = @ptrCast(@alignCast(subj_obj));
            const items_ptr = list_obj.ob_item orelse return null;
            const list_size: usize = @intCast(list_obj.ob_size);

            if (list_size >= nargs) {
                for (items_ptr[0..nargs]) |item| {
                    matched_values.append(item) catch return null;
                }
            } else {
                return null;
            }
        },
        else => {
            // For other types, try to get attributes from __match_args__
            // or fall back to direct attribute access via kwargs
            if (nargs > 0) {
                // Need __match_args__ to know which attrs to extract
                // For now, return null for non-standard types with positional args
                return null;
            }
        },
    }

    // Handle keyword arguments - look up attributes on subject
    // For simplicity, skip kwargs processing in this implementation
    // Real implementation would need getattr functionality
    _ = kwargs;

    // Create result tuple
    const result = runtime.PyTuple.create(allocator, matched_values.items) catch return null;
    return @ptrCast(result);
}

// ============================================================================
// Unpack Iterable
// ============================================================================

/// Unpack iterable for assignment
/// Mirrors: _PyEval_UnpackIterableStackRef()
/// Unpacks an iterable into argcnt values before a star, and argcntafter values after
/// For example: a, *b, c = [1,2,3,4,5] would have argcnt=1, argcntafter=1
/// Returns an array of PyObject pointers representing unpacked values
pub fn unpackIterable(
    allocator: std.mem.Allocator,
    iterable: ?*anyopaque,
    argcnt: usize,
    argcntafter: usize,
) ![]?*anyopaque {
    const iter_ptr = iterable orelse return error.NotImplemented;
    const iter_obj: *runtime.PyObject = @ptrCast(@alignCast(iter_ptr));
    const type_id = runtime.getTypeId(iter_obj);

    // Handle different types
    return switch (type_id) {
        .list => unpackList(allocator, iter_obj, argcnt, argcntafter),
        .tuple => unpackTuple(allocator, iter_obj, argcnt, argcntafter),
        .string => unpackString(allocator, iter_obj, argcnt, argcntafter),
        else => error.NotImplemented,
    };
}

fn unpackList(allocator: std.mem.Allocator, iter_obj: *runtime.PyObject, argcnt: usize, argcntafter: usize) ![]?*anyopaque {
    const list_obj: *runtime.PyListObject = @ptrCast(@alignCast(iter_obj));
    const items_ptr = list_obj.ob_item orelse return error.ValueError;
    const list_size: usize = @intCast(list_obj.ob_size);

    return unpackSlice(allocator, items_ptr[0..list_size], argcnt, argcntafter);
}

fn unpackTuple(allocator: std.mem.Allocator, iter_obj: *runtime.PyObject, argcnt: usize, argcntafter: usize) ![]?*anyopaque {
    const tuple_obj: *runtime.PyTupleObject = @ptrCast(@alignCast(iter_obj));
    const items_ptr = tuple_obj.ob_item orelse return error.ValueError;
    const tuple_size: usize = @intCast(tuple_obj.ob_size);

    return unpackSlice(allocator, items_ptr[0..tuple_size], argcnt, argcntafter);
}

fn unpackSlice(allocator: std.mem.Allocator, items: []*runtime.PyObject, argcnt: usize, argcntafter: usize) ![]?*anyopaque {
    const total_needed = argcnt + argcntafter;

    if (argcntafter > 0) {
        // Star unpacking
        if (items.len < total_needed) {
            return error.ValueError;
        }

        var result = try allocator.alloc(?*anyopaque, argcnt + 1 + argcntafter);

        // First argcnt items
        for (0..argcnt) |i| {
            runtime.incref(items[i]);
            result[i] = @ptrCast(items[i]);
        }

        // Middle star item
        const star_len = items.len - argcnt - argcntafter;
        const star_list = try runtime.PyList.create(allocator);
        for (0..star_len) |i| {
            runtime.incref(items[argcnt + i]);
            try runtime.PyList.append(star_list, items[argcnt + i]);
        }
        result[argcnt] = @ptrCast(star_list);

        // Last argcntafter items
        for (0..argcntafter) |i| {
            const idx = items.len - argcntafter + i;
            runtime.incref(items[idx]);
            result[argcnt + 1 + i] = @ptrCast(items[idx]);
        }

        return result;
    } else {
        // Simple unpacking
        if (items.len != argcnt) {
            return error.ValueError;
        }

        var result = try allocator.alloc(?*anyopaque, argcnt);
        for (items, 0..) |item, i| {
            runtime.incref(item);
            result[i] = @ptrCast(item);
        }
        return result;
    }
}

fn unpackString(allocator: std.mem.Allocator, iter_obj: *runtime.PyObject, argcnt: usize, argcntafter: usize) ![]?*anyopaque {
    const str_val = runtime.PyString.getValue(iter_obj);
    const total_needed = argcnt + argcntafter;

    if (argcntafter > 0) {
        // Star unpacking: a, *b, c = "hello"
        if (str_val.len < total_needed) {
            return error.ValueError;
        }

        var result = try allocator.alloc(?*anyopaque, argcnt + 1 + argcntafter);

        // First argcnt items
        for (0..argcnt) |i| {
            const char_str = try allocator.alloc(u8, 1);
            char_str[0] = str_val[i];
            const char_obj = try runtime.PyString.create(allocator, char_str);
            result[i] = @ptrCast(char_obj);
        }

        // Middle star item
        const star_len = str_val.len - argcnt - argcntafter;
        const star_list = try runtime.PyList.create(allocator);
        for (0..star_len) |i| {
            const char_str = try allocator.alloc(u8, 1);
            char_str[0] = str_val[argcnt + i];
            const char_obj = try runtime.PyString.create(allocator, char_str);
            try runtime.PyList.append(star_list, char_obj);
        }
        result[argcnt] = @ptrCast(star_list);

        // Last argcntafter items
        for (0..argcntafter) |i| {
            const idx = str_val.len - argcntafter + i;
            const char_str = try allocator.alloc(u8, 1);
            char_str[0] = str_val[idx];
            const char_obj = try runtime.PyString.create(allocator, char_str);
            result[argcnt + 1 + i] = @ptrCast(char_obj);
        }

        return result;
    } else {
        // Simple unpacking: a, b, c = "abc"
        if (str_val.len != argcnt) {
            return error.ValueError;
        }

        var result = try allocator.alloc(?*anyopaque, argcnt);
        for (0..argcnt) |i| {
            const char_str = try allocator.alloc(u8, 1);
            char_str[0] = str_val[i];
            const char_obj = try runtime.PyString.create(allocator, char_str);
            result[i] = @ptrCast(char_obj);
        }
        return result;
    }
}

// ============================================================================
// Conversion Functions
// ============================================================================

/// Conversion function types for format strings
pub const ConversionFunc = enum(u8) {
    none = 0,
    str = ord('s'),
    repr = ord('r'),
    ascii = ord('a'),

    fn ord(c: u8) u8 {
        return c;
    }
};

// ============================================================================
// Initialization
// ============================================================================

/// Initialize ceval subsystem
pub fn init() void {
    recursion_depth = 0;
    ticker = check_interval;
    pending_mainthread = PendingCalls.init();
}

/// Finalize ceval subsystem
pub fn fini() void {
    // Clear any pending calls
    while (pending_mainthread.pop() != null) {}

    // Clear hooks
    trace_func = null;
    trace_arg = null;
    profile_func = null;
    profile_arg = null;
    custom_eval_frame = null;
}

// ============================================================================
// Tests
// ============================================================================

test "pending calls" {
    var pending = PendingCalls.init();

    // Test adding calls
    const TestCallback = struct {
        var call_count: i32 = 0;
        fn callback(_: ?*anyopaque) callconv(.C) c_int {
            call_count += 1;
            return 0;
        }
    };

    try std.testing.expectEqual(AddPendingResult.success, pending.add(&TestCallback.callback, null));
    try std.testing.expect(pending.hasPending());

    // Process calls
    const result = pending.makeCalls();
    try std.testing.expectEqual(@as(c_int, 0), result);
    try std.testing.expectEqual(@as(i32, 1), TestCallback.call_count);
    try std.testing.expect(!pending.hasPending());
}

test "recursion limit" {
    const original = getRecursionLimit();
    defer setRecursionLimit(original) catch {};

    try setRecursionLimit(500);
    try std.testing.expectEqual(@as(i32, 500), getRecursionLimit());

    // Test invalid limit
    try std.testing.expectError(error.ValueError, setRecursionLimit(0));
}

test "ceval state" {
    var state = CEvalState.init();

    try std.testing.expectEqual(@as(i32, 1000), state.getRecursionLimit());

    try state.setRecursionLimit(2000);
    try std.testing.expectEqual(@as(i32, 2000), state.getRecursionLimit());

    // Test eval breaker
    try std.testing.expect(!state.shouldBreak());
    state.setEvalBreakerBit(EVAL_BREAKER_PENDING_CALLS);
    try std.testing.expect(state.shouldBreak());
    state.clearEvalBreakerBit(EVAL_BREAKER_PENDING_CALLS);
    try std.testing.expect(!state.shouldBreak());
}

test "trace events" {
    try std.testing.expectEqual(@as(c_int, 0), @intFromEnum(TraceEvent.call));
    try std.testing.expectEqual(@as(c_int, 3), @intFromEnum(TraceEvent.return_));
    try std.testing.expectEqual(@as(c_int, 7), @intFromEnum(TraceEvent.opcode));
}

test "check ticker" {
    setCheckInterval(10);
    defer setCheckInterval(100);

    // First 9 checks should return false
    var i: i32 = 0;
    while (i < 9) : (i += 1) {
        try std.testing.expect(!checkTicker());
    }
    // 10th check should return true
    try std.testing.expect(checkTicker());
}
