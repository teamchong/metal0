//! metal0 compiler daemon - zero-config persistent compiler
//!
//! Eliminates startup overhead by keeping compiler loaded in memory.
//! 100% automatic - no manual start/stop needed.
//!
//! Zero-config behavior:
//!   - Auto-starts when running multiple tests (>3 files)
//!   - Auto-shuts down after 5 minutes idle
//!   - Auto-restarts if crashed (health check)
//!   - Falls back gracefully if daemon unavailable
//!
//! Protocol (JSON over Unix socket):
//!   Request:  {"cmd": "compile", "file": "test.py", "opts": {...}}
//!   Response: {"ok": true, "output": "...", "time_ms": 5}

const std = @import("std");
const builtin = @import("builtin");
const CompileOptions = @import("../../main.zig").CompileOptions;
const compile_mod = @import("../compile.zig");
const build_dirs = @import("../../build_dirs.zig");

/// Socket path for daemon communication
pub const SOCKET_PATH = "/tmp/metal0-daemon.sock";
pub const PID_FILE = "/tmp/metal0-daemon.pid";

/// Auto-start threshold: start daemon if running more than this many tests
pub const AUTO_START_THRESHOLD = 3;

/// Idle timeout: shutdown after 5 minutes of no activity
pub const IDLE_TIMEOUT_MS = 5 * 60 * 1000;

/// Health check timeout
pub const HEALTH_CHECK_TIMEOUT_MS = 1000;

/// Daemon request types
pub const Request = struct {
    cmd: []const u8, // "compile", "test", "ping", "shutdown"
    file: ?[]const u8 = null,
    mode: ?[]const u8 = null,
    emit_zig_only: bool = false,
};

/// Daemon response
pub const Response = struct {
    ok: bool,
    output: ?[]const u8 = null,
    @"error": ?[]const u8 = null,
    time_ms: ?u64 = null,
};

/// Check if daemon is running and healthy
pub fn isRunning() bool {
    return healthCheck();
}

/// Health check - verify daemon responds to ping
pub fn healthCheck() bool {
    const stream = std.net.connectUnixSocket(SOCKET_PATH) catch return false;
    defer stream.close();

    // Send ping (simple text protocol)
    stream.writeAll("ping\n") catch return false;

    // Wait for response
    var buf: [256]u8 = undefined;
    const n = stream.read(&buf) catch return false;
    if (n == 0) return false;

    // Check response is "OK pong"
    return std.mem.indexOf(u8, buf[0..n], "pong") != null;
}

/// Ensure daemon is running, auto-start if needed for batch operations
pub fn ensureDaemon(allocator: std.mem.Allocator, num_files: usize) bool {
    // Only auto-start for batch operations
    if (num_files < AUTO_START_THRESHOLD) return false;

    if (healthCheck()) return true;

    // Try to start daemon
    startDaemonBackground(allocator) catch return false;

    // Wait for daemon to be ready (max 2 seconds)
    var attempts: usize = 0;
    while (attempts < 20) : (attempts += 1) {
        std.Thread.sleep(100 * std.time.ns_per_ms);
        if (healthCheck()) return true;
    }

    return false;
}

/// Start daemon in background (detached)
fn startDaemonBackground(allocator: std.mem.Allocator) !void {
    // Get path to self executable
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const self_exe = try std.fs.selfExePath(&path_buf);

    var child = std.process.Child.init(&.{ self_exe, "daemon", "run" }, allocator);
    child.stdin_behavior = .Close;
    child.stdout_behavior = .Close;
    child.stderr_behavior = .Close;

    try child.spawn();
    // Don't wait - let it run in background
}

/// Get daemon PID if running
pub fn getPid() ?std.process.Child.Id {
    const file = std.fs.cwd().openFile(PID_FILE, .{}) catch return null;
    defer file.close();
    var buf: [32]u8 = undefined;
    const len = file.readAll(&buf) catch return null;
    const pid_str = std.mem.trim(u8, buf[0..len], &std.ascii.whitespace);
    return std.fmt.parseInt(std.process.Child.Id, pid_str, 10) catch null;
}

/// Send request to daemon and get response
/// Simple text protocol: "CMD FILE\n" -> "OK OUTPUT\n" or "ERR MESSAGE\n"
pub fn sendRequest(allocator: std.mem.Allocator, request: Request) !Response {
    _ = allocator;
    const stream = try std.net.connectUnixSocket(SOCKET_PATH);
    defer stream.close();

    // Send request as simple text: "CMD FILE"
    var buf: [4096]u8 = undefined;
    const msg = if (request.file) |f|
        std.fmt.bufPrint(&buf, "{s} {s}\n", .{ request.cmd, f }) catch return error.BufferTooSmall
    else
        std.fmt.bufPrint(&buf, "{s}\n", .{request.cmd}) catch return error.BufferTooSmall;
    try stream.writeAll(msg);

    // Read response: "OK OUTPUT" or "ERR MESSAGE"
    var resp_buf: [4096]u8 = undefined;
    const n = try stream.read(&resp_buf);
    if (n == 0) return error.EmptyResponse;

    const resp_line = std.mem.trimRight(u8, resp_buf[0..n], "\n");
    if (std.mem.startsWith(u8, resp_line, "OK ")) {
        return Response{ .ok = true, .output = resp_line[3..] };
    } else if (std.mem.startsWith(u8, resp_line, "ERR ")) {
        return Response{ .ok = false, .@"error" = resp_line[4..] };
    } else if (std.mem.eql(u8, resp_line, "OK")) {
        return Response{ .ok = true };
    }
    return Response{ .ok = false, .@"error" = resp_line };
}

/// Compile via daemon (falls back to direct if daemon not running)
pub fn compileViaDaemon(allocator: std.mem.Allocator, opts: CompileOptions) ![]const u8 {
    if (!isRunning()) {
        // Fall back to direct compilation
        try compile_mod.compileFile(allocator, opts);
        return opts.input_file;
    }

    const response = try sendRequest(allocator, .{
        .cmd = "compile",
        .file = opts.input_file,
        .mode = opts.mode,
        .emit_zig_only = opts.emit_zig_only,
    });

    if (!response.ok) {
        return error.DaemonCompileFailed;
    }

    return response.output orelse opts.input_file;
}

/// Start the daemon process
pub fn startDaemon(allocator: std.mem.Allocator) !void {
    if (isRunning()) {
        std.debug.print("Daemon already running (pid: {?d})\n", .{getPid()});
        return;
    }

    // Fork and run daemon in background
    var child = std.process.Child.init(&.{ "metal0", "daemon", "run" }, allocator);
    child.stdin_behavior = .Close;
    child.stdout_behavior = .Close;
    child.stderr_behavior = .Close;

    try child.spawn();
    std.debug.print("Daemon started (pid: {d})\n", .{child.id});
}

/// Stop the daemon
pub fn stopDaemon() !void {
    if (!isRunning()) {
        std.debug.print("Daemon not running\n", .{});
        return;
    }

    // Send shutdown request
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    _ = sendRequest(arena.allocator(), .{ .cmd = "shutdown" }) catch {};
    std.debug.print("Daemon stopped\n", .{});
}

/// Run the daemon (called by `metal0 daemon run`)
pub fn runDaemon(allocator: std.mem.Allocator) !void {
    // Remove old socket
    std.fs.cwd().deleteFile(SOCKET_PATH) catch {};

    // Create Unix socket server
    const addr = std.net.Address.initUnix(SOCKET_PATH) catch unreachable;
    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    // Write PID file
    {
        const pid_file = try std.fs.cwd().createFile(PID_FILE, .{});
        defer pid_file.close();
        var buf: [32]u8 = undefined;
        const pid: i32 = if (builtin.os.tag == .linux)
            std.os.linux.getpid()
        else if (builtin.os.tag == .macos or builtin.os.tag == .freebsd)
            std.c.getpid()
        else
            0;
        const pid_str = std.fmt.bufPrint(&buf, "{d}", .{pid}) catch unreachable;
        try pid_file.writeAll(pid_str);
    }
    defer std.fs.cwd().deleteFile(PID_FILE) catch {};
    defer std.fs.cwd().deleteFile(SOCKET_PATH) catch {};

    // Pre-initialize build dirs
    try build_dirs.init();

    // Track last activity for idle timeout
    var last_activity = std.time.milliTimestamp();

    // Spawn idle checker thread
    const idle_thread = std.Thread.spawn(.{}, idleChecker, .{&last_activity}) catch null;
    defer if (idle_thread) |t| t.detach();

    // Event loop
    while (true) {
        const conn = server.accept() catch |err| {
            if (err == error.ConnectionAborted) continue;
            return err;
        };

        // Update activity timestamp
        last_activity = std.time.milliTimestamp();

        // Handle request in same thread (simple, no threading overhead)
        handleConnection(allocator, conn.stream) catch |err| {
            std.debug.print("Connection error: {any}\n", .{err});
        };
    }
}

/// Background thread that checks for idle timeout
fn idleChecker(last_activity: *i64) void {
    while (true) {
        std.Thread.sleep(30 * std.time.ns_per_s); // Check every 30s

        const now = std.time.milliTimestamp();
        const idle_ms = now - last_activity.*;

        if (idle_ms > IDLE_TIMEOUT_MS) {
            // Idle timeout - shutdown
            std.process.exit(0);
        }
    }
}

fn handleConnection(allocator: std.mem.Allocator, stream: std.net.Stream) !void {
    defer stream.close();

    // Read request: "CMD [FILE]\n"
    var buf: [4096]u8 = undefined;
    const n = try stream.read(&buf);
    if (n == 0) return;

    const line = std.mem.trimRight(u8, buf[0..n], "\n\r ");
    var parts = std.mem.splitScalar(u8, line, ' ');
    const cmd = parts.next() orelse return;
    const file = parts.next();

    // Handle commands
    if (std.mem.eql(u8, cmd, "ping")) {
        try stream.writeAll("OK pong\n");
        return;
    }

    if (std.mem.eql(u8, cmd, "shutdown")) {
        try stream.writeAll("OK bye\n");
        std.process.exit(0);
    }

    if (std.mem.eql(u8, cmd, "compile")) {
        const start = std.time.milliTimestamp();

        const target_file = file orelse {
            try stream.writeAll("ERR missing file\n");
            return;
        };

        const opts = CompileOptions{
            .input_file = target_file,
            .mode = "build",
            .emit_zig_only = true,
        };

        compile_mod.compileFile(allocator, opts) catch |err| {
            var err_buf: [256]u8 = undefined;
            const err_msg = std.fmt.bufPrint(&err_buf, "ERR {s}\n", .{@errorName(err)}) catch "ERR unknown\n";
            try stream.writeAll(err_msg);
            return;
        };

        const elapsed = std.time.milliTimestamp() - start;
        var resp_buf: [256]u8 = undefined;
        const resp = std.fmt.bufPrint(&resp_buf, "OK {d}ms\n", .{elapsed}) catch "OK\n";
        try stream.writeAll(resp);
        return;
    }

    try stream.writeAll("ERR unknown command\n");
}

/// Handle daemon CLI commands
pub fn cmdDaemon(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        std.debug.print("Usage: metal0 daemon <start|stop|status|run>\n", .{});
        return;
    }

    const subcmd = args[0];

    if (std.mem.eql(u8, subcmd, "start")) {
        try startDaemon(allocator);
    } else if (std.mem.eql(u8, subcmd, "stop")) {
        try stopDaemon();
    } else if (std.mem.eql(u8, subcmd, "status")) {
        if (isRunning()) {
            std.debug.print("Daemon running (pid: {?d})\n", .{getPid()});
        } else {
            std.debug.print("Daemon not running\n", .{});
        }
    } else if (std.mem.eql(u8, subcmd, "run")) {
        try runDaemon(allocator);
    } else {
        std.debug.print("Unknown daemon command: {s}\n", .{subcmd});
    }
}
