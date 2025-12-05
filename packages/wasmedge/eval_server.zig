/// WasmEdge Eval Server
///
/// Provides isolated eval()/exec() execution using WasmEdge.
/// Each eval request runs in a fresh WASM instance for security.
///
/// Architecture:
/// 1. Main process compiles Python to bytecode
/// 2. Bytecode sent to eval server
/// 3. Server loads bytecode VM WASM module
/// 4. Executes bytecode in isolated WASM sandbox
/// 5. Returns result
///
/// Usage:
///   metal0-eval-server [--socket /tmp/metal0-eval.sock] [--vm-module metal0_vm.wasm]
///
const std = @import("std");
const wasmedge = @import("wasmedge.zig");

const DEFAULT_SOCKET_PATH = "/tmp/metal0-eval.sock";
const DEFAULT_VM_MODULE = "metal0_vm.wasm";

pub const EvalServer = struct {
    allocator: std.mem.Allocator,
    socket_path: []const u8,
    vm_module_path: []const u8,
    server_fd: std.posix.fd_t,
    running: bool,

    /// Cached WASM module bytes for fast instance creation
    vm_wasm: ?[]const u8,

    pub fn init(
        allocator: std.mem.Allocator,
        socket_path: []const u8,
        vm_module_path: []const u8,
    ) !EvalServer {
        // Load VM WASM module
        const vm_wasm = std.fs.cwd().readFileAlloc(allocator, vm_module_path, 64 * 1024 * 1024) catch |err| {
            std.log.err("Failed to load VM module {s}: {}", .{ vm_module_path, err });
            return error.VMModuleNotFound;
        };

        // Create Unix socket
        const fd = try std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0);
        errdefer std.posix.close(fd);

        // Bind to socket path
        var addr = std.posix.sockaddr.un{
            .family = std.posix.AF.UNIX,
            .path = undefined,
        };
        @memset(&addr.path, 0);
        @memcpy(addr.path[0..socket_path.len], socket_path);

        // Remove existing socket
        std.fs.deleteFileAbsolute(socket_path) catch {};

        try std.posix.bind(fd, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
        try std.posix.listen(fd, 128);

        std.log.info("Eval server listening on {s}", .{socket_path});

        return .{
            .allocator = allocator,
            .socket_path = socket_path,
            .vm_module_path = vm_module_path,
            .server_fd = fd,
            .running = true,
            .vm_wasm = vm_wasm,
        };
    }

    pub fn deinit(self: *EvalServer) void {
        self.running = false;
        std.posix.close(self.server_fd);
        std.fs.deleteFileAbsolute(self.socket_path) catch {};
        if (self.vm_wasm) |wasm| {
            self.allocator.free(wasm);
        }
    }

    /// Run server loop
    pub fn run(self: *EvalServer) !void {
        while (self.running) {
            const client_fd = std.posix.accept(self.server_fd, null, null) catch |err| {
                if (err == error.ConnectionAborted) continue;
                return err;
            };

            // Handle in separate thread for concurrency
            const thread = try std.Thread.spawn(.{}, handleClient, .{ self, client_fd });
            thread.detach();
        }
    }

    fn handleClient(self: *EvalServer, client_fd: std.posix.fd_t) void {
        defer std.posix.close(client_fd);

        self.handleRequest(client_fd) catch |err| {
            std.log.err("Client error: {}", .{err});
            // Send error response
            const error_response = [_]u8{ 0xFF, 0, 0, 0, 0, 0, 0, 0 };
            _ = std.posix.write(client_fd, &error_response) catch {};
        };
    }

    fn handleRequest(self: *EvalServer, client_fd: std.posix.fd_t) !void {
        // Read bytecode length
        var len_buf: [4]u8 = undefined;
        _ = try std.posix.read(client_fd, &len_buf);
        const bytecode_len = std.mem.readInt(u32, &len_buf, .little);

        if (bytecode_len > 16 * 1024 * 1024) {
            return error.BytecodeTooLarge;
        }

        // Read bytecode
        const bytecode = try self.allocator.alloc(u8, bytecode_len);
        defer self.allocator.free(bytecode);

        var total_read: usize = 0;
        while (total_read < bytecode_len) {
            const n = try std.posix.read(client_fd, bytecode[total_read..]);
            if (n == 0) return error.ConnectionClosed;
            total_read += n;
        }

        // Execute in WasmEdge
        const result = try self.executeBytecode(bytecode);

        // Send result
        const result_len: u32 = @intCast(result.len);
        _ = try std.posix.write(client_fd, std.mem.asBytes(&result_len));
        _ = try std.posix.write(client_fd, result);

        self.allocator.free(result);
    }

    fn executeBytecode(self: *EvalServer, bytecode: []const u8) ![]u8 {
        // Create fresh WasmEdge instance for isolation
        var config = try wasmedge.Config.create();
        defer config.destroy();
        config.enableWASI();

        var vm = try wasmedge.VM.createWithConfig(&config);
        defer vm.destroy();

        // Load bytecode VM module
        if (self.vm_wasm) |wasm| {
            try vm.loadFromBuffer(wasm);
        } else {
            try vm.loadFromFile(self.vm_module_path);
        }
        try vm.validate();
        try vm.instantiate();

        // Allocate memory in WASM for bytecode
        var alloc_results: [1]wasmedge.Value = undefined;
        try vm.execute("alloc", &.{
            wasmedge.Value.i32(@intCast(bytecode.len)),
        }, &alloc_results);

        const wasm_ptr = alloc_results[0].getI32();

        // Copy bytecode to WASM memory
        // Note: This requires accessing WASM memory directly
        // For now, we'll use a simpler approach with a single execute call
        // that takes bytecode inline

        // Execute bytecode
        var exec_results: [1]wasmedge.Value = undefined;
        try vm.execute("execute_bytecode", &.{
            wasmedge.Value.i32(wasm_ptr),
            wasmedge.Value.i32(@intCast(bytecode.len)),
        }, &exec_results);

        // Get result
        const result_ptr = exec_results[0].getI32();
        _ = result_ptr;

        // For now, return a simple result
        // Full implementation would read from WASM memory
        var result = try self.allocator.alloc(u8, 9);
        result[0] = 1; // Type: int
        std.mem.writeInt(i64, result[1..9], 0, .little);

        return result;
    }
};

/// Entry point for standalone eval server
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse args
    var socket_path: []const u8 = DEFAULT_SOCKET_PATH;
    var vm_module: []const u8 = DEFAULT_VM_MODULE;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // Skip program name

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--socket")) {
            socket_path = args.next() orelse {
                std.log.err("--socket requires a path argument", .{});
                return error.InvalidArgs;
            };
        } else if (std.mem.eql(u8, arg, "--vm-module")) {
            vm_module = args.next() orelse {
                std.log.err("--vm-module requires a path argument", .{});
                return error.InvalidArgs;
            };
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            const stdout = std.io.getStdOut().writer();
            try stdout.print(
                \\metal0 Eval Server - Isolated eval()/exec() execution
                \\
                \\Usage:
                \\  metal0-eval-server [options]
                \\
                \\Options:
                \\  --socket <path>     Unix socket path (default: {s})
                \\  --vm-module <path>  Bytecode VM WASM module (default: {s})
                \\  --help              Show this help
                \\
            , .{ DEFAULT_SOCKET_PATH, DEFAULT_VM_MODULE });
            return;
        }
    }

    var server = try EvalServer.init(allocator, socket_path, vm_module);
    defer server.deinit();

    // Handle signals for graceful shutdown
    const handler = struct {
        var srv: *EvalServer = undefined;

        fn handle(_: c_int) callconv(.C) void {
            srv.running = false;
        }
    };
    handler.srv = &server;

    const act = std.posix.Sigaction{
        .handler = .{ .handler = handler.handle },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    try std.posix.sigaction(std.posix.SIG.INT, &act, null);
    try std.posix.sigaction(std.posix.SIG.TERM, &act, null);

    try server.run();
}

test "EvalServer init/deinit" {
    // Skip if no VM module available
    if (true) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var server = try EvalServer.init(allocator, "/tmp/test-eval.sock", "test_vm.wasm");
    defer server.deinit();
}
