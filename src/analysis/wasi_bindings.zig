/// WASI Bindings Analysis
///
/// Extends the @wasm_import pattern for WASI-specific imports.
/// Generates optimized bindings for WasmEdge and other WASI runtimes.
///
/// Usage in Python:
/// ```python
/// from metal0 import wasi_import
///
/// @wasi_import
/// def fd_read(fd: int, iovs_ptr: int, iovs_len: int) -> tuple[int, int]: ...
///
/// @wasi_import
/// def environ_get(environ: int, environ_buf: int) -> int: ...
/// ```
///
/// Or use high-level wrappers:
/// ```python
/// from metal0.wasi import fs, env
///
/// content = fs.read_file("/data/input.txt")
/// home = env.get("HOME")
/// ```
const std = @import("std");
const wasm_bindings = @import("wasm_bindings.zig");

/// WASI function categories for capability-based security
pub const WasiCapability = enum {
    /// File system operations (fd_read, fd_write, path_open, etc.)
    filesystem,
    /// Environment variables (environ_get, environ_sizes_get)
    environ,
    /// Command line arguments (args_get, args_sizes_get)
    args,
    /// Clock/time operations (clock_time_get, clock_res_get)
    clock,
    /// Random number generation (random_get)
    random,
    /// Process control (proc_exit, proc_raise)
    proc,
    /// Socket operations (sock_accept, sock_recv, sock_send) - WASI preview2
    sockets,
    /// Poll/async operations (poll_oneoff)
    poll,
};

/// WASI function signature
pub const WasiFunction = struct {
    name: []const u8,
    capability: WasiCapability,
    params: []const WasiParam,
    returns: []const WasiType,
    /// WASI preview version (1 or 2)
    preview: u8 = 1,
};

pub const WasiParam = struct {
    name: []const u8,
    wasi_type: WasiType,
};

/// WASI-specific types (more specific than general WASM types)
pub const WasiType = enum {
    i32,
    i64,
    /// File descriptor
    fd,
    /// Pointer to memory
    ptr,
    /// Size/length
    size,
    /// WASI errno
    errno,
    /// Timestamp (nanoseconds)
    timestamp,
    /// File size
    filesize,
    /// Rights flags
    rights,
    /// Lookup flags
    lookupflags,
    /// Open flags
    oflags,
    /// File type
    filetype,

    pub fn toZigType(self: WasiType) []const u8 {
        return switch (self) {
            .i32, .fd, .errno, .lookupflags, .oflags, .filetype => "i32",
            .i64, .timestamp, .filesize, .rights => "i64",
            .ptr, .size => "usize",
        };
    }
};

/// Standard WASI preview1 functions
pub const wasi_snapshot_preview1 = [_]WasiFunction{
    // Args
    .{ .name = "args_get", .capability = .args, .params = &.{
        .{ .name = "argv", .wasi_type = .ptr },
        .{ .name = "argv_buf", .wasi_type = .ptr },
    }, .returns = &.{.errno} },
    .{ .name = "args_sizes_get", .capability = .args, .params = &.{
        .{ .name = "argc", .wasi_type = .ptr },
        .{ .name = "argv_buf_size", .wasi_type = .ptr },
    }, .returns = &.{.errno} },

    // Environ
    .{ .name = "environ_get", .capability = .environ, .params = &.{
        .{ .name = "environ", .wasi_type = .ptr },
        .{ .name = "environ_buf", .wasi_type = .ptr },
    }, .returns = &.{.errno} },
    .{ .name = "environ_sizes_get", .capability = .environ, .params = &.{
        .{ .name = "environc", .wasi_type = .ptr },
        .{ .name = "environ_buf_size", .wasi_type = .ptr },
    }, .returns = &.{.errno} },

    // Clock
    .{ .name = "clock_time_get", .capability = .clock, .params = &.{
        .{ .name = "id", .wasi_type = .i32 },
        .{ .name = "precision", .wasi_type = .timestamp },
        .{ .name = "time", .wasi_type = .ptr },
    }, .returns = &.{.errno} },

    // Random
    .{ .name = "random_get", .capability = .random, .params = &.{
        .{ .name = "buf", .wasi_type = .ptr },
        .{ .name = "buf_len", .wasi_type = .size },
    }, .returns = &.{.errno} },

    // Filesystem
    .{ .name = "fd_read", .capability = .filesystem, .params = &.{
        .{ .name = "fd", .wasi_type = .fd },
        .{ .name = "iovs", .wasi_type = .ptr },
        .{ .name = "iovs_len", .wasi_type = .size },
        .{ .name = "nread", .wasi_type = .ptr },
    }, .returns = &.{.errno} },
    .{ .name = "fd_write", .capability = .filesystem, .params = &.{
        .{ .name = "fd", .wasi_type = .fd },
        .{ .name = "iovs", .wasi_type = .ptr },
        .{ .name = "iovs_len", .wasi_type = .size },
        .{ .name = "nwritten", .wasi_type = .ptr },
    }, .returns = &.{.errno} },
    .{ .name = "fd_close", .capability = .filesystem, .params = &.{
        .{ .name = "fd", .wasi_type = .fd },
    }, .returns = &.{.errno} },
    .{ .name = "fd_seek", .capability = .filesystem, .params = &.{
        .{ .name = "fd", .wasi_type = .fd },
        .{ .name = "offset", .wasi_type = .i64 },
        .{ .name = "whence", .wasi_type = .i32 },
        .{ .name = "newoffset", .wasi_type = .ptr },
    }, .returns = &.{.errno} },
    .{ .name = "path_open", .capability = .filesystem, .params = &.{
        .{ .name = "fd", .wasi_type = .fd },
        .{ .name = "dirflags", .wasi_type = .lookupflags },
        .{ .name = "path", .wasi_type = .ptr },
        .{ .name = "path_len", .wasi_type = .size },
        .{ .name = "oflags", .wasi_type = .oflags },
        .{ .name = "fs_rights_base", .wasi_type = .rights },
        .{ .name = "fs_rights_inheriting", .wasi_type = .rights },
        .{ .name = "fdflags", .wasi_type = .i32 },
        .{ .name = "opened_fd", .wasi_type = .ptr },
    }, .returns = &.{.errno} },

    // Process
    .{ .name = "proc_exit", .capability = .proc, .params = &.{
        .{ .name = "rval", .wasi_type = .i32 },
    }, .returns = &.{} },
};

/// Analyzed WASI bindings for a module
pub const WasiBindings = struct {
    /// Required capabilities based on @wasi_import decorators
    capabilities: std.EnumSet(WasiCapability),
    /// Specific functions imported
    functions: std.ArrayList(WasiFunction),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WasiBindings {
        return .{
            .capabilities = std.EnumSet(WasiCapability).initEmpty(),
            .functions = std.ArrayList(WasiFunction).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *WasiBindings) void {
        self.functions.deinit();
    }

    pub fn hasCapability(self: *const WasiBindings, cap: WasiCapability) bool {
        return self.capabilities.contains(cap);
    }

    pub fn addFunction(self: *WasiBindings, func: WasiFunction) !void {
        self.capabilities.insert(func.capability);
        try self.functions.append(func);
    }
};

/// Generate Zig externs for WASI imports
pub fn generateZigExterns(allocator: std.mem.Allocator, bindings: *const WasiBindings) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();
    const w = output.writer();

    try w.writeAll(
        \\// Auto-generated WASI imports by metal0
        \\// Only includes functions declared via @wasi_import
        \\
        \\const std = @import("std");
        \\
        \\pub const wasi = struct {
        \\
    );

    for (bindings.functions.items) |func| {
        try w.print("    pub extern \"wasi_snapshot_preview1\" fn {s}(", .{func.name});

        for (func.params, 0..) |param, i| {
            try w.print("{s}: {s}", .{ param.name, param.wasi_type.toZigType() });
            if (i < func.params.len - 1) try w.writeAll(", ");
        }

        try w.writeAll(") ");
        if (func.returns.len > 0) {
            try w.print("{s}", .{func.returns[0].toZigType()});
        } else {
            try w.writeAll("void");
        }
        try w.writeAll(";\n");
    }

    try w.writeAll("};\n");

    // Generate high-level wrappers
    try w.writeAll(
        \\
        \\// High-level wrappers
        \\pub const fs = struct {
        \\    pub fn read(fd: i32, buf: []u8) !usize {
        \\        var iov = .{ .buf = buf.ptr, .len = buf.len };
        \\        var nread: usize = 0;
        \\        const errno = wasi.fd_read(fd, @ptrCast(&iov), 1, &nread);
        \\        if (errno != 0) return error.WasiError;
        \\        return nread;
        \\    }
        \\
        \\    pub fn write(fd: i32, buf: []const u8) !usize {
        \\        var iov = .{ .buf = buf.ptr, .len = buf.len };
        \\        var nwritten: usize = 0;
        \\        const errno = wasi.fd_write(fd, @ptrCast(&iov), 1, &nwritten);
        \\        if (errno != 0) return error.WasiError;
        \\        return nwritten;
        \\    }
        \\};
        \\
    );

    return output.toOwnedSlice();
}

/// Generate capability manifest for WASI runtime
pub fn generateCapabilityManifest(allocator: std.mem.Allocator, bindings: *const WasiBindings) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();
    const w = output.writer();

    try w.writeAll(
        \\# WASI Capability Manifest
        \\# Auto-generated by metal0
        \\# Use with: wasmtime --dir=/path module.wasm
        \\
        \\capabilities:
        \\
    );

    inline for (std.meta.fields(WasiCapability)) |field| {
        const cap = @as(WasiCapability, @enumFromInt(field.value));
        if (bindings.hasCapability(cap)) {
            try w.print("  - {s}\n", .{field.name});
        }
    }

    try w.writeAll(
        \\
        \\# Suggested runtime flags:
        \\
    );

    if (bindings.hasCapability(.filesystem)) {
        try w.writeAll("# wasmtime --dir=. module.wasm\n");
    }
    if (bindings.hasCapability(.environ)) {
        try w.writeAll("# wasmtime --env=VAR=value module.wasm\n");
    }
    if (bindings.hasCapability(.sockets)) {
        try w.writeAll("# wasmedge --enable-wasi-socket module.wasm\n");
    }

    return output.toOwnedSlice();
}

test "WasiType.toZigType" {
    try std.testing.expectEqualStrings("i32", WasiType.fd.toZigType());
    try std.testing.expectEqualStrings("i64", WasiType.timestamp.toZigType());
    try std.testing.expectEqualStrings("usize", WasiType.size.toZigType());
}

test "WasiBindings.capabilities" {
    const allocator = std.testing.allocator;
    var bindings = WasiBindings.init(allocator);
    defer bindings.deinit();

    try bindings.addFunction(wasi_snapshot_preview1[0]); // args_get
    try std.testing.expect(bindings.hasCapability(.args));
    try std.testing.expect(!bindings.hasCapability(.filesystem));
}
