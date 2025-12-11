/// pylifecycle types - Status, PreConfig, Config, State types
const std = @import("std");

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

/// Pre-configuration for Python initialization
pub const PreConfig = struct {
    parse_argv: bool = true,
    isolated: i32 = 0,
    use_environment: bool = true,
    configure_locale: bool = true,
    coerce_c_locale: i32 = 0,
    coerce_c_locale_warn: bool = false,
    utf8_mode: i32 = -1,
    dev_mode: bool = false,
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

/// Python configuration
pub const Config = struct {
    parse_argv: bool = true,
    isolated: bool = false,
    use_environment: bool = true,
    dev_mode: bool = false,
    install_signal_handlers: bool = true,
    use_hash_seed: bool = false,
    hash_seed: u64 = 0,
    faulthandler: bool = false,
    tracemalloc: i32 = 0,
    import_time: bool = false,
    show_ref_count: bool = false,
    dump_refs: bool = false,
    dump_refs_file: ?[]const u8 = null,
    malloc_stats: bool = false,
    filesystem_encoding: ?[]const u8 = null,
    filesystem_errors: ?[]const u8 = null,
    pycache_prefix: ?[]const u8 = null,
    parse_debug: bool = false,
    verbose: i32 = 0,
    quiet: bool = false,
    user_site_directory: bool = true,
    configure_c_stdio: bool = true,
    buffered_stdio: bool = true,
    stdio_encoding: ?[]const u8 = null,
    stdio_errors: ?[]const u8 = null,
    check_hash_pycs_mode: CheckHashPycsMode = .default,
    pathconfig_warnings: bool = true,
    program_name: ?[]const u8 = null,
    pythonpath_env: ?[]const u8 = null,
    home: ?[]const u8 = null,
    platlibdir: ?[]const u8 = null,
    module_search_paths_set: bool = false,
    module_search_paths: ?[][]const u8 = null,
    executable: ?[]const u8 = null,
    base_executable: ?[]const u8 = null,
    prefix: ?[]const u8 = null,
    base_prefix: ?[]const u8 = null,
    exec_prefix: ?[]const u8 = null,
    base_exec_prefix: ?[]const u8 = null,
    skip_source_first_line: bool = false,
    run_command: ?[]const u8 = null,
    run_module: ?[]const u8 = null,
    run_filename: ?[]const u8 = null,
    _install_importlib: bool = true,
    _init_main: bool = true,
    _isolated_interpreter: bool = false,
    orig_argv: ?[][]const u8 = null,
    argv: ?[][]const u8 = null,
    xoptions: ?[][]const u8 = null,
    warnoptions: ?[][]const u8 = null,
    site_import: bool = true,
    bytes_warning: i32 = 0,
    warn_default_encoding: bool = false,
    inspect: bool = false,
    interactive: bool = false,
    optimization_level: i32 = 0,
    parser_debug: bool = false,
    write_bytecode: bool = true,
    safe_path: bool = false,
    int_max_str_digits: i32 = 4300,

    pub const CheckHashPycsMode = enum {
        default,
        always,
        never,
    };
};

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
    before: ?*const fn () void = null,
    after_in_parent: ?*const fn () void = null,
    after_in_child: ?*const fn () void = null,
};

/// GIL state
pub const GILState = struct {
    autoTSSkey: ?*anyopaque = null,
    autoInterpreterState: ?*anyopaque = null,
};
