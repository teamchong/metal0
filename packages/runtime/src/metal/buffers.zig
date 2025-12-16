//! Metal GPU Buffer Management
//!
//! Handles GPU memory allocation and data transfer between CPU and GPU.

const std = @import("std");
const builtin = @import("builtin");
const objc = @import("objc.zig");

/// Metal GPU buffer wrapper
pub const MetalBuffer = struct {
    buffer: objc.MTLBuffer,
    device: objc.MTLDevice,
    length: usize,

    /// Create a new GPU buffer with specified size
    pub fn init(device: objc.MTLDevice, size: usize) !@This() {
        const buffer = objc.deviceNewBuffer(
            device,
            size * @sizeOf(f32),
            objc.MTLResourceStorageModeShared,
        ) orelse return error.BufferCreationFailed;

        return .{
            .buffer = buffer,
            .device = device,
            .length = size,
        };
    }

    /// Create buffer from existing data
    pub fn initWithData(device: objc.MTLDevice, data: []const f32) !@This() {
        const buffer = objc.deviceNewBufferWithBytes(
            device,
            @ptrCast(data.ptr),
            data.len * @sizeOf(f32),
            objc.MTLResourceStorageModeShared,
        ) orelse return error.BufferCreationFailed;

        return .{
            .buffer = buffer,
            .device = device,
            .length = data.len,
        };
    }

    /// Release GPU buffer
    pub fn deinit(self: *@This()) void {
        objc.release(self.buffer);
    }

    /// Get pointer to buffer contents (CPU-accessible for shared storage)
    pub fn getContents(self: *@This()) []f32 {
        const ptr = objc.bufferGetContents(self.buffer) orelse return &[_]f32{};
        const float_ptr: [*]f32 = @ptrCast(@alignCast(ptr));
        return float_ptr[0..self.length];
    }

    /// Copy data to buffer
    pub fn setData(self: *@This(), data: []const f32) void {
        const contents = self.getContents();
        const copy_len = @min(data.len, contents.len);
        @memcpy(contents[0..copy_len], data[0..copy_len]);
    }

    /// Copy data from buffer
    pub fn getData(self: *@This(), allocator: std.mem.Allocator) ![]f32 {
        const result = try allocator.alloc(f32, self.length);
        const contents = self.getContents();
        @memcpy(result, contents);
        return result;
    }

    /// Get underlying Metal buffer object
    pub fn getBuffer(self: *const @This()) objc.MTLBuffer {
        return self.buffer;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "buffer creation" {
    if (comptime builtin.os.tag != .macos) return;

    const device = objc.MTLCreateSystemDefaultDevice() orelse return;
    defer objc.release(device);

    var buffer = try MetalBuffer.init(device, 1024);
    defer buffer.deinit();

    const contents = buffer.getContents();
    try std.testing.expectEqual(@as(usize, 1024), contents.len);
}

test "buffer with data" {
    if (comptime builtin.os.tag != .macos) return;

    const device = objc.MTLCreateSystemDefaultDevice() orelse return;
    defer objc.release(device);

    const data = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    var buffer = try MetalBuffer.initWithData(device, &data);
    defer buffer.deinit();

    const contents = buffer.getContents();
    try std.testing.expectEqual(@as(usize, 4), contents.len);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), contents[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4.0), contents[3], 0.001);
}
