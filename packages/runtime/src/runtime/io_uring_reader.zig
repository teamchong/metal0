//! io_uring file reader - batch async file I/O for Linux
//!
//! Provides Bun-style fast file reading using Linux io_uring.
//! Falls back to synchronous I/O on non-Linux platforms.
//!
//! Usage:
//!   var reader = try IoUringReader.init(allocator);
//!   defer reader.deinit();
//!
//!   // Queue multiple reads
//!   try reader.queueRead("file1.txt");
//!   try reader.queueRead("file2.txt");
//!
//!   // Submit and wait for all
//!   const results = try reader.submitAndWait();

const std = @import("std");
const builtin = @import("builtin");

/// io_uring batch file reader
pub const IoUringReader = struct {
    allocator: std.mem.Allocator,

    // Linux-specific io_uring
    ring: if (builtin.os.tag == .linux) std.os.linux.IoUring else void,

    // Pending reads
    pending: std.ArrayList(PendingRead),

    // Results
    results: std.ArrayList(ReadResult),

    const PendingRead = struct {
        path: []const u8,
        fd: std.posix.fd_t,
        buffer: []u8,
        size: usize,
    };

    pub const ReadResult = struct {
        path: []const u8,
        content: []u8,
        err: ?anyerror,
    };

    pub fn init(allocator: std.mem.Allocator) !IoUringReader {
        var self = IoUringReader{
            .allocator = allocator,
            .ring = undefined,
            .pending = .{},
            .results = .{},
        };

        if (builtin.os.tag == .linux) {
            // Initialize io_uring with 64 entries
            self.ring = try std.os.linux.IoUring.init(64, 0);
        }

        return self;
    }

    pub fn deinit(self: *IoUringReader) void {
        if (builtin.os.tag == .linux) {
            self.ring.deinit();
        }

        for (self.pending.items) |p| {
            if (p.fd >= 0) std.posix.close(p.fd);
            self.allocator.free(p.buffer);
        }
        self.pending.deinit(self.allocator);

        for (self.results.items) |r| {
            self.allocator.free(r.content);
        }
        self.results.deinit(self.allocator);
    }

    /// Queue a file for reading
    pub fn queueRead(self: *IoUringReader, path: []const u8) !void {
        if (builtin.os.tag == .linux) {
            return self.queueReadLinux(path);
        } else {
            return self.queueReadFallback(path);
        }
    }

    fn queueReadLinux(self: *IoUringReader, path: []const u8) !void {
        // Open file
        const fd = try std.posix.open(path, .{ .ACCMODE = .RDONLY }, 0);
        errdefer std.posix.close(fd);

        // Get file size
        const stat = try std.posix.fstat(fd);
        const size: usize = @intCast(stat.size);

        // Allocate buffer
        const buffer = try self.allocator.alloc(u8, size);
        errdefer self.allocator.free(buffer);

        // Queue read operation
        _ = self.ring.read(
            @intFromPtr(&self.pending.items[self.pending.items.len]),
            fd,
            .{ .buffer = buffer },
            0,
        ) catch |err| {
            std.posix.close(fd);
            self.allocator.free(buffer);
            return err;
        };

        try self.pending.append(self.allocator, .{
            .path = path,
            .fd = fd,
            .buffer = buffer,
            .size = size,
        });
    }

    fn queueReadFallback(self: *IoUringReader, path: []const u8) !void {
        // Synchronous fallback for non-Linux
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
        try self.results.append(self.allocator, .{
            .path = path,
            .content = content,
            .err = null,
        });
    }

    /// Submit all queued reads and wait for completion
    pub fn submitAndWait(self: *IoUringReader) ![]ReadResult {
        if (builtin.os.tag == .linux) {
            return self.submitAndWaitLinux();
        } else {
            // Results already populated by fallback
            return self.results.items;
        }
    }

    fn submitAndWaitLinux(self: *IoUringReader) ![]ReadResult {
        if (self.pending.items.len == 0) return self.results.items;

        // Submit all queued operations
        _ = try self.ring.submit();

        // Wait for completions
        var completed: usize = 0;
        while (completed < self.pending.items.len) {
            const cqe = self.ring.copy_cqe() catch |err| {
                if (err == error.SystemResources) {
                    // No completions ready, wait
                    _ = try self.ring.submit_and_wait(1);
                    continue;
                }
                return err;
            };

            // Process completion
            const user_data = cqe.user_data;
            const pending_idx = @divExact(user_data - @intFromPtr(self.pending.items.ptr), @sizeOf(PendingRead));

            if (pending_idx < self.pending.items.len) {
                const p = self.pending.items[pending_idx];
                if (cqe.res >= 0) {
                    try self.results.append(self.allocator, .{
                        .path = p.path,
                        .content = p.buffer[0..@intCast(cqe.res)],
                        .err = null,
                    });
                } else {
                    try self.results.append(self.allocator, .{
                        .path = p.path,
                        .content = &[_]u8{},
                        .err = error.ReadFailed,
                    });
                }
                std.posix.close(p.fd);
            }

            self.ring.cq_advance(1);
            completed += 1;
        }

        return self.results.items;
    }
};

/// Batch read multiple files using io_uring on Linux
/// Falls back to sequential reads on other platforms
pub fn batchReadFiles(
    allocator: std.mem.Allocator,
    paths: []const []const u8,
) ![]IoUringReader.ReadResult {
    var reader = try IoUringReader.init(allocator);
    defer reader.deinit();

    for (paths) |path| {
        try reader.queueRead(path);
    }

    return reader.submitAndWait();
}

test "IoUringReader basic" {
    const allocator = std.testing.allocator;

    var reader = try IoUringReader.init(allocator);
    defer reader.deinit();

    // This test would need actual files
}
