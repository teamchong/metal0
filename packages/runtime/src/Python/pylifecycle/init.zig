/// pylifecycle initialization functions
const std = @import("std");
const builtin = @import("builtin");
const allocator_helper = @import("utils.allocator_helper");
const types = @import("types.zig");
const state = @import("state.zig");
const locale = @import("locale.zig");

const Status = types.Status;
const PreConfig = types.PreConfig;
const Config = types.Config;
const RuntimeState = state.RuntimeState;
const ThreadState = state.ThreadState;
const InterpreterState = state.InterpreterState;

/// Thread-local thread state
pub threadlocal var _tstate: ?*ThreadState = null;

/// Pre-initialize the Python runtime
pub fn preInitialize(config: ?PreConfig) Status {
    return preInitializeFromConfig(config orelse PreConfig{});
}

/// Pre-initialize from PreConfig
pub fn preInitializeFromConfig(config: PreConfig) Status {
    if (state.runtime.preinitialized) {
        return Status.ok();
    }

    state.runtime.preinitializing = true;
    defer state.runtime.preinitializing = false;

    state.runtime.preconfig = config;

    if (config.configure_locale) {
        locale.initLocale();
    }

    if (config.coerce_c_locale > 0) {
        _ = locale.coerceLegacyLocale(config.coerce_c_locale_warn);
    }

    state.runtime.preinitialized = true;
    return Status.ok();
}

/// Initialize Python runtime (simple version)
pub fn initialize() void {
    const status = initializeFromConfig(Config{});
    if (status.isException()) {
        exitStatusException(status);
    }
}

/// Initialize Python runtime with signal handlers option
pub fn initializeEx(install_sigs: bool) void {
    var config = Config{};
    config.install_signal_handlers = install_sigs;
    const status = initializeFromConfig(config);
    if (status.isException()) {
        exitStatusException(status);
    }
}

/// Initialize Python from configuration
pub fn initializeFromConfig(src_config: Config) Status {
    if (!state.runtime.preinitialized) {
        const pre_status = preInitialize(null);
        if (pre_status.isException()) {
            return pre_status;
        }
    }

    if (state.runtime.initialized) {
        return Status.ok();
    }

    var status = initCore(&src_config);
    if (status.isException()) {
        return status;
    }

    status = initMain();
    if (status.isException()) {
        return status;
    }

    return Status.ok();
}

/// Core initialization
fn initCore(config: *const Config) Status {
    if (state.runtime.core_initialized) {
        return Status.ok();
    }

    initVersion();

    if (!config.use_hash_seed) {
        initHashRandomization();
    }

    const interp_status = createMainInterpreter(config);
    if (interp_status.isException()) {
        return interp_status;
    }

    initTypes();
    initBuiltins();

    state.runtime.core_initialized = true;
    return Status.ok();
}

/// Main initialization (after core)
fn initMain() Status {
    if (state.runtime.initialized) {
        return Status.ok();
    }

    if (!state.runtime.core_initialized) {
        return Status.err("core not initialized");
    }

    initSysModule();
    initImport();

    if (state.runtime.main_tstate) |tstate| {
        if (tstate.interp) |interp| {
            if (interp.config.install_signal_handlers) {
                initSignalHandlers();
            }
        }
    }

    if (state.runtime.main_tstate) |tstate| {
        if (tstate.interp) |interp| {
            if (interp.config.site_import) {
                _ = initSite();
            }
        }
    }

    state.runtime.initialized = true;
    return Status.ok();
}

/// Create the main interpreter
fn createMainInterpreter(config: *const Config) Status {
    var interp = allocator_helper.fast_allocator.create(InterpreterState) catch {
        return Status.noMemory();
    };
    interp.* = .{};
    interp.config = config.*;
    interp.id = state.runtime.next_interp_id;
    state.runtime.next_interp_id += 1;
    interp._ready = true;

    var tstate = allocator_helper.fast_allocator.create(ThreadState) catch {
        return Status.noMemory();
    };
    tstate.* = .{};
    tstate.interp = interp;
    tstate.id = 0;
    tstate.thread_id = @intCast(std.Thread.getCurrentId());

    interp.threads_head = tstate;
    interp.threads_count = 1;

    state.runtime.main_tstate = tstate;
    _tstate = tstate;

    return Status.ok();
}

fn initVersion() void {}
fn initHashRandomization() void {}
fn initTypes() void {}
fn initBuiltins() void {}

fn initSysModule() void {
    const sysmodule = @import("../sysmodule.zig");
    sysmodule.init();
}

fn initImport() void {}
fn initSignalHandlers() void {}
fn initSite() Status {
    return Status.ok();
}

/// Exit with a status exception
pub fn exitStatusException(status: Status) noreturn {
    if (status.kind == .exit_code) {
        std.process.exit(@intCast(@as(u8, @truncate(@as(u32, @bitCast(status.exit_code))))));
    }

    const stderr = std.io.getStdErr().writer();
    if (status.err_msg) |msg| {
        stderr.print("Python error: {s}\n", .{msg}) catch {};
    } else if (status.kind == .no_memory) {
        stderr.print("Python error: out of memory\n", .{}) catch {};
    }

    std.process.exit(1);
}
