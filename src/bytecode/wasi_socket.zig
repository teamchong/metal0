/// WasmEdge WASI Socket Support for eval()/exec()
///
/// Enables subprocess-like bytecode execution for WasmEdge WASI targets.
/// Uses WASI sockets for inter-process communication.
///
/// Architecture:
/// 1. Main WASM module compiles bytecode
/// 2. Connects to metal0 server via Unix socket
/// 3. Sends bytecode for execution
/// 4. Receives result
const std = @import("std");
const builtin = @import("builtin");
const opcode = @import("opcode.zig");
const vm = @import("vm.zig");

const Program = opcode.Program;
const VM = vm.VM;
const StackValue = vm.StackValue;
const VMError = vm.VMError;

/// Check if running in WasmEdge WASI context
pub const is_wasm_edge = builtin.cpu.arch.isWasm() and
    builtin.os.tag == .wasi;

/// WASI socket path for metal0 server
const EVAL_SOCKET_PATH = "/tmp/metal0-server.sock";

/// Connection state for WASI socket communication
pub const WasiConnection = struct {
    fd: std.posix.fd_t,
    allocator: std.mem.Allocator,

    /// Connect to server
    pub fn connect(allocator: std.mem.Allocator) VMError!WasiConnection {
        if (!is_wasm_edge) {
            return error.NotImplemented;
        }

        // Create Unix socket
        const fd = std.posix.socket(
            std.posix.AF.UNIX,
            std.posix.SOCK.STREAM,
            0,
        ) catch {
            return error.RuntimeError;
        };

        // Connect to server
        var addr = std.posix.sockaddr.un{
            .family = std.posix.AF.UNIX,
            .path = undefined,
        };
        @memset(&addr.path, 0);
        @memcpy(addr.path[0..EVAL_SOCKET_PATH.len], EVAL_SOCKET_PATH);

        std.posix.connect(fd, @ptrCast(&addr), @sizeOf(@TypeOf(addr))) catch {
            std.posix.close(fd);
            return error.RuntimeError;
        };

        return .{
            .fd = fd,
            .allocator = allocator,
        };
    }

    /// Send bytecode and receive result
    pub fn execute(self: *WasiConnection, program: *const Program) VMError!StackValue {
        // Serialize bytecode
        const bytecode_data = opcode.serialize(self.allocator, program) catch {
            return error.OutOfMemory;
        };
        defer self.allocator.free(bytecode_data);

        // Send length prefix
        const len: u32 = @intCast(bytecode_data.len);
        _ = std.posix.write(self.fd, std.mem.asBytes(&len)) catch {
            return error.RuntimeError;
        };

        // Send bytecode
        _ = std.posix.write(self.fd, bytecode_data) catch {
            return error.RuntimeError;
        };

        // Read result length
        var result_len: u32 = undefined;
        _ = std.posix.read(self.fd, std.mem.asBytes(&result_len)) catch {
            return error.RuntimeError;
        };

        // Read result data
        var result_buf = self.allocator.alloc(u8, result_len) catch {
            return error.OutOfMemory;
        };
        defer self.allocator.free(result_buf);

        _ = std.posix.read(self.fd, result_buf) catch {
            return error.RuntimeError;
        };

        // Deserialize result
        return deserializeResult(result_buf);
    }

    /// Close connection
    pub fn close(self: *WasiConnection) void {
        std.posix.close(self.fd);
    }
};

/// Execute bytecode via WASI socket to server
pub fn executeWasiEdge(
    allocator: std.mem.Allocator,
    program: *const Program,
) VMError!StackValue {
    if (!is_wasm_edge) {
        return error.NotImplemented;
    }

    // For simple expressions, run locally
    if (!needsIsolation(program)) {
        var executor = VM.init(allocator);
        defer executor.deinit();
        return executor.execute(program);
    }

    // For complex code, use socket communication
    var conn = try WasiConnection.connect(allocator);
    defer conn.close();

    return conn.execute(program);
}

/// Determine if bytecode needs isolation (subprocess)
/// Returns true for operations that benefit from sandboxing
fn needsIsolation(program: *const Program) bool {
    // Check for operations that benefit from isolation
    for (program.instructions) |inst| {
        switch (inst.opcode) {
            // Imports may have side effects
            .IMPORT_NAME, .IMPORT_FROM => return true,
            // Class definitions are complex
            .BUILD_CLASS => return true,
            // Exception handling is complex
            .SETUP_EXCEPT, .RAISE_VARARGS => return true,
            // Potentially blocking I/O
            .LOAD_ATTR => {
                // Check if accessing I/O methods (simplified)
                // Full implementation would check actual names
                return false;
            },
            else => {},
        }
    }
    return false;
}

/// Deserialize result from server response
fn deserializeResult(data: []const u8) StackValue {
    if (data.len < 1) {
        return .{ .none = {} };
    }

    // Simple encoding: type byte + value
    const type_byte = data[0];
    const value_data = data[1..];

    return switch (type_byte) {
        0 => .{ .none = {} },
        1 => blk: {
            // Integer
            if (value_data.len >= 8) {
                const int_val = std.mem.readInt(i64, value_data[0..8], .little);
                break :blk .{ .int = int_val };
            }
            break :blk .{ .int = 0 };
        },
        2 => blk: {
            // Float
            if (value_data.len >= 8) {
                const bits = std.mem.readInt(u64, value_data[0..8], .little);
                break :blk .{ .float = @bitCast(bits) };
            }
            break :blk .{ .float = 0.0 };
        },
        3 => blk: {
            // Bool
            break :blk .{ .bool = value_data.len > 0 and value_data[0] != 0 };
        },
        4 => blk: {
            // String (remaining bytes)
            break :blk .{ .string = value_data };
        },
        else => .{ .none = {} },
    };
}

/// Serialize result for sending to client
pub fn serializeResult(allocator: std.mem.Allocator, value: StackValue) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    switch (value) {
        .none => {
            try result.append(allocator, 0);
        },
        .int => |v| {
            try result.append(allocator, 1);
            const bytes = std.mem.asBytes(&v);
            try result.appendSlice(allocator, bytes);
        },
        .float => |v| {
            try result.append(allocator, 2);
            const bits: u64 = @bitCast(v);
            const bytes = std.mem.asBytes(&bits);
            try result.appendSlice(allocator, bytes);
        },
        .bool => |v| {
            try result.append(allocator, 3);
            try result.append(allocator, if (v) 1 else 0);
        },
        .string => |v| {
            try result.append(allocator, 4);
            try result.appendSlice(allocator, v);
        },
        else => {
            try result.append(allocator, 0); // None for unsupported types
        },
    }

    return result.toOwnedSlice();
}

/// Server for handling WASI socket connections
/// Run this as a separate process to handle eval() requests
pub const EvalServer = struct {
    allocator: std.mem.Allocator,
    server_fd: std.posix.fd_t,

    pub fn init(allocator: std.mem.Allocator) !EvalServer {
        // Create Unix socket
        const fd = try std.posix.socket(
            std.posix.AF.UNIX,
            std.posix.SOCK.STREAM,
            0,
        );

        // Bind to socket path
        var addr = std.posix.sockaddr.un{
            .family = std.posix.AF.UNIX,
            .path = undefined,
        };
        @memset(&addr.path, 0);
        @memcpy(addr.path[0..EVAL_SOCKET_PATH.len], EVAL_SOCKET_PATH);

        // Remove existing socket
        std.fs.deleteFileAbsolute(EVAL_SOCKET_PATH) catch {};

        try std.posix.bind(fd, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
        try std.posix.listen(fd, 128);

        return .{
            .allocator = allocator,
            .server_fd = fd,
        };
    }

    pub fn deinit(self: *EvalServer) void {
        std.posix.close(self.server_fd);
        std.fs.deleteFileAbsolute(EVAL_SOCKET_PATH) catch {};
    }

    /// Handle one client connection
    pub fn handleConnection(self: *EvalServer, client_fd: std.posix.fd_t) !void {
        defer std.posix.close(client_fd);

        // Read bytecode length
        var len_buf: [4]u8 = undefined;
        _ = try std.posix.read(client_fd, &len_buf);
        const bytecode_len = std.mem.readInt(u32, &len_buf, .little);

        // Read bytecode
        const bytecode_data = try self.allocator.alloc(u8, bytecode_len);
        defer self.allocator.free(bytecode_data);
        _ = try std.posix.read(client_fd, bytecode_data);

        // Deserialize program
        const program = try opcode.deserialize(self.allocator, bytecode_data);

        // Execute
        var executor = VM.init(self.allocator);
        defer executor.deinit();
        const result = try executor.execute(&program);

        // Serialize result
        const result_data = try serializeResult(self.allocator, result);
        defer self.allocator.free(result_data);

        // Send result length
        const result_len: u32 = @intCast(result_data.len);
        _ = try std.posix.write(client_fd, std.mem.asBytes(&result_len));

        // Send result
        _ = try std.posix.write(client_fd, result_data);
    }

    /// Run server loop
    pub fn run(self: *EvalServer) !void {
        while (true) {
            const client_fd = try std.posix.accept(self.server_fd, null, null);
            self.handleConnection(client_fd) catch |err| {
                std.log.err("Client error: {}", .{err});
            };
        }
    }
};

test "wasi detection" {
    // On native, is_wasm_edge should be false
    if (!builtin.cpu.arch.isWasm()) {
        try std.testing.expect(!is_wasm_edge);
    }
}

test "result serialization" {
    const allocator = std.testing.allocator;

    // Test integer
    const int_data = try serializeResult(allocator, .{ .int = 42 });
    defer allocator.free(int_data);
    const int_result = deserializeResult(int_data);
    try std.testing.expectEqual(@as(i64, 42), int_result.int);

    // Test bool
    const bool_data = try serializeResult(allocator, .{ .bool = true });
    defer allocator.free(bool_data);
    const bool_result = deserializeResult(bool_data);
    try std.testing.expectEqual(true, bool_result.bool);

    // Test none
    const none_data = try serializeResult(allocator, .{ .none = {} });
    defer allocator.free(none_data);
    const none_result = deserializeResult(none_data);
    _ = none_result.none; // Just check it's .none variant
}
