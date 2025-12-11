/// pylifecycle state - RuntimeState, ThreadState, InterpreterState
const std = @import("std");
const types = @import("types.zig");
const Config = types.Config;
const PreConfig = types.PreConfig;
const ExitFunc = types.ExitFunc;
const AuditHookList = types.AuditHookList;
const OpenCodeHook = types.OpenCodeHook;
const AtForkHandlers = types.AtForkHandlers;
const GILState = types.GILState;

/// Runtime state (singleton)
pub const RuntimeState = struct {
    preconfig: PreConfig = .{},
    preinitializing: bool = false,
    preinitialized: bool = false,
    core_initialized: bool = false,
    initialized: bool = false,
    finalizing: ?*ThreadState = null,
    exitfuncs: [32]?ExitFunc = [_]?ExitFunc{null} ** 32,
    nexitfuncs: usize = 0,
    main_tstate: ?*ThreadState = null,
    next_interp_id: i64 = 0,
    audit_hooks: AuditHookList = .{},
    open_code_hook: ?OpenCodeHook = null,
    atfork_handlers: AtForkHandlers = .{},
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
    recursion_depth: u32 = 0,
    recursion_limit: u32 = 1000,
    recursion_headroom: u32 = 50,
    tracing: bool = false,
    use_tracing: bool = false,
    curexc_type: ?[]const u8 = null,
    curexc_value: ?[]const u8 = null,
    curexc_traceback: ?[]const u8 = null,
    thread_id: u64 = 0,
    native_thread_id: u64 = 0,
    gilstate_counter: u32 = 0,
    async_gen_firstiter: ?*anyopaque = null,
    async_gen_finalizer: ?*anyopaque = null,
    context: ?*anyopaque = null,
    context_ver: u64 = 0,
};

/// Interpreter state
pub const InterpreterState = struct {
    next: ?*InterpreterState = null,
    id: i64 = 0,
    id_refcount: i64 = 0,
    requires_idref: bool = false,
    _ready: bool = false,
    config: Config = .{},
    feature_flags: u64 = 0,
    threads_head: ?*ThreadState = null,
    threads_count: u64 = 0,
    modules: ?*anyopaque = null,
    builtins: ?*anyopaque = null,
    import_func: ?*anyopaque = null,
    codec_search_path: ?*anyopaque = null,
    codec_search_cache: ?*anyopaque = null,
    codec_error_registry: ?*anyopaque = null,
    finalizing: bool = false,
    long_state: struct {
        max_str_digits: i32 = 4300,
    } = .{},
    interned_strings: ?*anyopaque = null,
    warnings_state: ?*anyopaque = null,
    audit_hooks: ?*anyopaque = null,
};

/// Global runtime state
pub var runtime: RuntimeState = .{};

/// Main interpreter
pub var main_interp: InterpreterState = .{};

/// Main thread state
pub var main_tstate: ThreadState = .{};
