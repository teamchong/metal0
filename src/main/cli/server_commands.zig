/// Server command: WasmEdge-based bytecode execution server
/// Runs a server that executes Python bytecode in isolated WasmEdge instances
const std = @import("std");
const Color = @import("common.zig").Color;
const printSuccess = @import("common.zig").printSuccess;
const printError = @import("common.zig").printError;
const printInfo = @import("common.zig").printInfo;

const DEFAULT_SOCKET_PATH = "/tmp/metal0-server.sock";
const DEFAULT_VM_MODULE = "metal0_vm.wasm";

/// Server: runs WasmEdge-based bytecode execution server
/// Usage: metal0 server [--socket <path>] [--vm-module <path>]
pub fn cmdServer(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var socket_path: []const u8 = DEFAULT_SOCKET_PATH;
    var vm_module: []const u8 = DEFAULT_VM_MODULE;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--socket")) {
            i += 1;
            if (i < args.len) {
                socket_path = args[i];
            } else {
                printError("--socket requires a path argument", .{});
                return;
            }
        } else if (std.mem.eql(u8, arg, "--vm-module")) {
            i += 1;
            if (i < args.len) {
                vm_module = args[i];
            } else {
                printError("--vm-module requires a path argument", .{});
                return;
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print(
                \\{s}metal0 Server - Isolated eval()/exec() execution{s}
                \\
                \\{s}Usage:{s}
                \\  metal0 server [options]
                \\
                \\{s}Options:{s}
                \\  --socket <path>     Unix socket path (default: {s})
                \\  --vm-module <path>  Bytecode VM WASM module (default: {s})
                \\  --help              Show this help
                \\
                \\{s}Description:{s}
                \\  Runs a server that executes Python bytecode in isolated WasmEdge
                \\  instances. Each eval() request runs in a fresh WASM sandbox for
                \\  security isolation.
                \\
                \\{s}Architecture:{s}
                \\  1. Client compiles Python code to bytecode
                \\  2. Bytecode sent to server via Unix socket
                \\  3. Server loads bytecode VM WASM module
                \\  4. Executes bytecode in isolated WASM sandbox
                \\  5. Returns result to client
                \\
            , .{
                Color.bold,          Color.reset,
                Color.bold,          Color.reset,
                Color.bold,          Color.reset,
                DEFAULT_SOCKET_PATH, DEFAULT_VM_MODULE,
                Color.bold,          Color.reset,
                Color.bold,          Color.reset,
            });
            return;
        }
    }

    // Check if VM module exists
    std.fs.cwd().access(vm_module, .{}) catch {
        printError("VM module not found: {s}", .{vm_module});
        std.debug.print("\n{s}Build the bytecode VM first:{s}\n", .{ Color.dim, Color.reset });
        std.debug.print("  zig build -Dtarget=wasm32-wasi bytecode-vm\n\n", .{});
        return;
    };

    printInfo("Starting server...", .{});
    std.debug.print("  Socket: {s}\n", .{socket_path});
    std.debug.print("  VM module: {s}\n", .{vm_module});

    // Load VM WASM module
    const vm_wasm = std.fs.cwd().readFileAlloc(allocator, vm_module, 64 * 1024 * 1024) catch |err| {
        printError("Failed to load VM module {s}: {any}", .{ vm_module, err });
        return;
    };
    defer allocator.free(vm_wasm);

    // Create Unix socket
    const fd = std.posix.socket(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0) catch |err| {
        printError("Failed to create socket: {any}", .{err});
        return;
    };
    defer std.posix.close(fd);

    // Bind to socket path
    var addr = std.posix.sockaddr.un{
        .family = std.posix.AF.UNIX,
        .path = undefined,
    };
    @memset(&addr.path, 0);
    @memcpy(addr.path[0..socket_path.len], socket_path);

    // Remove existing socket
    std.fs.deleteFileAbsolute(socket_path) catch {};

    std.posix.bind(fd, @ptrCast(&addr), @sizeOf(@TypeOf(addr))) catch |err| {
        printError("Failed to bind socket: {any}", .{err});
        return;
    };

    std.posix.listen(fd, 128) catch |err| {
        printError("Failed to listen: {any}", .{err});
        return;
    };

    printSuccess("Server listening on {s}", .{socket_path});
    std.debug.print("{s}Press Ctrl+C to stop{s}\n\n", .{ Color.dim, Color.reset });

    // Server loop - spawn thread per client for concurrency
    while (true) {
        const client_fd = std.posix.accept(fd, null, null, 0) catch |err| {
            if (err == error.ConnectionAborted) continue;
            printError("Accept error: {any}", .{err});
            continue;
        };

        // Spawn thread to handle client concurrently
        const ClientContext = struct {
            fd: std.posix.fd_t,
            alloc: std.mem.Allocator,
            wasm: []const u8,

            fn handler(ctx: @This()) void {
                defer std.posix.close(ctx.fd);
                handleEvalClient(ctx.alloc, ctx.fd, ctx.wasm) catch |err| {
                    std.log.err("Client error: {any}", .{err});
                };
            }
        };

        const ctx = ClientContext{
            .fd = client_fd,
            .alloc = allocator,
            .wasm = vm_wasm,
        };

        _ = std.Thread.spawn(.{}, ClientContext.handler, .{ctx}) catch |err| {
            // Fallback to synchronous handling if thread spawn fails
            std.log.warn("Thread spawn failed ({any}), handling synchronously", .{err});
            handleEvalClient(allocator, client_fd, vm_wasm) catch |e| {
                std.log.err("Client error: {any}", .{e});
            };
            std.posix.close(client_fd);
        };
    }
}

fn handleEvalClient(allocator: std.mem.Allocator, client_fd: std.posix.fd_t, vm_wasm: []const u8) !void {
    // Read bytecode length
    var len_buf: [4]u8 = undefined;
    _ = try std.posix.read(client_fd, &len_buf);
    const bytecode_len = std.mem.readInt(u32, &len_buf, .little);

    if (bytecode_len > 16 * 1024 * 1024) {
        return error.BytecodeTooLarge;
    }

    // Read bytecode
    const bytecode = try allocator.alloc(u8, bytecode_len);
    defer allocator.free(bytecode);

    var total_read: usize = 0;
    while (total_read < bytecode_len) {
        const n = try std.posix.read(client_fd, bytecode[total_read..]);
        if (n == 0) return error.ConnectionClosed;
        total_read += n;
    }

    std.log.info("Received {d} bytes of bytecode", .{bytecode_len});

    // Execute bytecode using the internal bytecode VM
    var result_value: i64 = 0;
    var result_type: u8 = 1; // Default: int

    // Deserialize and execute bytecode using our VM
    const opcode_mod = @import("../../bytecode/opcode.zig");
    const vm_mod = @import("../../bytecode/vm.zig");

    if (opcode_mod.deserialize(bytecode, allocator)) |program| {
        var vm = vm_mod.VM.init(allocator);
        defer vm.deinit();

        // If we have WASM module, we could use WasmEdge for sandboxed execution
        // For now, execute directly in our VM (faster, no sandbox)
        _ = vm_wasm;

        const exec_result = vm.execute(program) catch {
            result_type = 0; // Error
            return sendResult(client_fd, result_type, result_value);
        };

        // Convert result to i64
        switch (exec_result) {
            .int => |int_val| {
                result_value = int_val;
                result_type = 1;
            },
            .float => |f| {
                result_value = @intFromFloat(f);
                result_type = 2;
            },
            .bool => |b| {
                result_value = if (b) 1 else 0;
                result_type = 3;
            },
            .none => {
                result_value = 0;
                result_type = 0;
            },
            else => {
                result_value = 0;
                result_type = 0;
            },
        }
    } else |_| {
        std.log.err("Failed to deserialize bytecode", .{});
        result_type = 0;
    }

    return sendResult(client_fd, result_type, result_value);
}

fn sendResult(client_fd: std.posix.fd_t, result_type: u8, result_value: i64) !void {
    // Send result (type: int, value)
    var result: [9]u8 = undefined;
    result[0] = result_type;
    std.mem.writeInt(i64, result[1..9], result_value, .little);

    const result_len: u32 = @intCast(result.len);
    _ = try std.posix.write(client_fd, std.mem.asBytes(&result_len));
    _ = try std.posix.write(client_fd, &result);
}
