/// Metal GPU integration for PyAOT
/// Provides unified memory management and GPU kernel execution on Apple Silicon
const std = @import("std");

/// Opaque types for Metal C API
pub const Device = opaque {};
pub const CommandQueue = opaque {};
pub const Buffer = opaque {};
pub const Library = opaque {};
pub const Function = opaque {};
pub const ComputePipelineState = opaque {};
pub const CommandBuffer = opaque {};
pub const ComputeCommandEncoder = opaque {};

/// Resource storage mode
pub const StorageMode = enum(c_uint) {
    shared = 0, // CPU + GPU accessible (unified memory)
    managed = 1,
    private = 2,
    memoryless = 3,
};

/// Metal C API bindings (via Objective-C runtime)
extern "c" fn MTLCreateSystemDefaultDevice() ?*Device;
extern "c" fn MTLDeviceNewCommandQueue(device: *Device) ?*CommandQueue;
extern "c" fn MTLDeviceNewBufferWithLength(
    device: *Device,
    length: usize,
    options: c_uint,
) ?*Buffer;
extern "c" fn MTLDeviceNewLibraryWithSource(
    device: *Device,
    source: [*:0]const u8,
    options: ?*anyopaque,
    error: ?*?*anyopaque,
) ?*Library;
extern "c" fn MTLLibraryNewFunctionWithName(
    library: *Library,
    name: [*:0]const u8,
) ?*Function;
extern "c" fn MTLDeviceNewComputePipelineStateWithFunction(
    device: *Device,
    function: *Function,
    error: ?*?*anyopaque,
) ?*ComputePipelineState;
extern "c" fn MTLCommandQueueCommandBuffer(queue: *CommandQueue) ?*CommandBuffer;
extern "c" fn MTLCommandBufferComputeCommandEncoder(
    buffer: *CommandBuffer,
) ?*ComputeCommandEncoder;
extern "c" fn MTLComputeCommandEncoderSetComputePipelineState(
    encoder: *ComputeCommandEncoder,
    pipeline: *ComputePipelineState,
) void;
extern "c" fn MTLComputeCommandEncoderSetBuffer(
    encoder: *ComputeCommandEncoder,
    buffer: *Buffer,
    offset: usize,
    index: c_uint,
) void;
extern "c" fn MTLComputeCommandEncoderDispatchThreads(
    encoder: *ComputeCommandEncoder,
    threads_per_grid: MTLSize,
    threads_per_threadgroup: MTLSize,
) void;
extern "c" fn MTLComputeCommandEncoderEndEncoding(encoder: *ComputeCommandEncoder) void;
extern "c" fn MTLCommandBufferCommit(buffer: *CommandBuffer) void;
extern "c" fn MTLCommandBufferWaitUntilCompleted(buffer: *CommandBuffer) void;
extern "c" fn MTLBufferContents(buffer: *Buffer) ?*anyopaque;

pub const MTLSize = extern struct {
    width: usize,
    height: usize,
    depth: usize,
};

/// Metal context - manages device, queue, and unified memory
pub const MetalContext = struct {
    device: *Device,
    queue: *CommandQueue,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !MetalContext {
        const device = MTLCreateSystemDefaultDevice() orelse
            return error.NoMetalDevice;

        const queue = MTLDeviceNewCommandQueue(device) orelse
            return error.CommandQueueCreationFailed;

        return .{
            .device = device,
            .queue = queue,
            .allocator = allocator,
        };
    }

    /// Allocate unified memory buffer (CPU + GPU accessible)
    pub fn allocateBuffer(self: *MetalContext, size: usize) !*Buffer {
        const buffer = MTLDeviceNewBufferWithLength(
            self.device,
            size,
            @intFromEnum(StorageMode.shared), // Unified memory!
        ) orelse return error.BufferAllocationFailed;

        return buffer;
    }

    /// Get CPU-accessible pointer to buffer contents
    pub fn getBufferPointer(self: *MetalContext, buffer: *Buffer, comptime T: type) ![*]T {
        _ = self;
        const ptr = MTLBufferContents(buffer) orelse
            return error.InvalidBuffer;
        return @ptrCast(@alignCast(ptr));
    }

    /// Compile Metal shader source code
    pub fn compileShader(
        self: *MetalContext,
        source: [:0]const u8,
        function_name: [:0]const u8,
    ) !*ComputePipelineState {
        var err: ?*anyopaque = null;

        const library = MTLDeviceNewLibraryWithSource(
            self.device,
            source.ptr,
            null,
            &err,
        ) orelse return error.ShaderCompilationFailed;

        const function = MTLLibraryNewFunctionWithName(
            library,
            function_name.ptr,
        ) orelse return error.FunctionNotFound;

        const pipeline = MTLDeviceNewComputePipelineStateWithFunction(
            self.device,
            function,
            &err,
        ) orelse return error.PipelineCreationFailed;

        return pipeline;
    }

    /// Execute compute kernel
    pub fn executeKernel(
        self: *MetalContext,
        pipeline: *ComputePipelineState,
        buffers: []const *Buffer,
        grid_size: MTLSize,
        threadgroup_size: MTLSize,
    ) !void {
        const cmd_buffer = MTLCommandQueueCommandBuffer(self.queue) orelse
            return error.CommandBufferCreationFailed;

        const encoder = MTLCommandBufferComputeCommandEncoder(cmd_buffer) orelse
            return error.EncoderCreationFailed;

        MTLComputeCommandEncoderSetComputePipelineState(encoder, pipeline);

        // Bind buffers
        for (buffers, 0..) |buffer, i| {
            MTLComputeCommandEncoderSetBuffer(
                encoder,
                buffer,
                0,
                @intCast(i),
            );
        }

        MTLComputeCommandEncoderDispatchThreads(
            encoder,
            grid_size,
            threadgroup_size,
        );

        MTLComputeCommandEncoderEndEncoding(encoder);
        MTLCommandBufferCommit(cmd_buffer);
        MTLCommandBufferWaitUntilCompleted(cmd_buffer);
    }
};

/// Matrix multiplication using Metal GPU
pub fn matmul(
    ctx: *MetalContext,
    a: []const f32,
    b: []const f32,
    c: []f32,
    m: u32,
    n: u32,
    k: u32,
) !void {
    // Compile kernel (in real implementation, this would be cached)
    const shader_source = @embedFile("../kernels/matmul.metal");
    const pipeline = try ctx.compileShader(shader_source, "matrix_multiply");

    // Allocate unified memory buffers
    const a_buffer = try ctx.allocateBuffer(a.len * @sizeOf(f32));
    const b_buffer = try ctx.allocateBuffer(b.len * @sizeOf(f32));
    const c_buffer = try ctx.allocateBuffer(c.len * @sizeOf(f32));
    const params_buffer = try ctx.allocateBuffer(3 * @sizeOf(u32));

    // Copy data to buffers (CPU write, GPU will read - zero copy!)
    const a_ptr = try ctx.getBufferPointer(a_buffer, f32);
    const b_ptr = try ctx.getBufferPointer(b_buffer, f32);
    const params_ptr = try ctx.getBufferPointer(params_buffer, u32);

    @memcpy(a_ptr[0..a.len], a);
    @memcpy(b_ptr[0..b.len], b);
    params_ptr[0] = m;
    params_ptr[1] = n;
    params_ptr[2] = k;

    // Execute kernel
    try ctx.executeKernel(
        pipeline,
        &[_]*Buffer{ a_buffer, b_buffer, c_buffer, params_buffer },
        .{ .width = n, .height = m, .depth = 1 },
        .{ .width = 16, .height = 16, .depth = 1 },
    );

    // Read result (GPU write, CPU read - zero copy!)
    const c_ptr = try ctx.getBufferPointer(c_buffer, f32);
    @memcpy(c, c_ptr[0..c.len]);
}

// Tests
test "Metal device creation" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;

    var ctx = try MetalContext.init(std.testing.allocator);
    _ = ctx;
}

test "Unified memory buffer allocation" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;

    var ctx = try MetalContext.init(std.testing.allocator);

    const buffer = try ctx.allocateBuffer(1024 * @sizeOf(f32));
    const ptr = try ctx.getBufferPointer(buffer, f32);

    // Write from CPU
    ptr[0] = 3.14;
    ptr[1] = 2.71;

    // Read from CPU (same memory!)
    try std.testing.expectEqual(@as(f32, 3.14), ptr[0]);
    try std.testing.expectEqual(@as(f32, 2.71), ptr[1]);
}

test "Matrix multiplication 2x2" {
    if (@import("builtin").os.tag != .macos) return error.SkipZigTest;

    var ctx = try MetalContext.init(std.testing.allocator);

    // A = [1 2]    B = [5 6]    C = [19 22]
    //     [3 4]        [7 8]        [43 50]
    const a = [_]f32{ 1, 2, 3, 4 };
    const b = [_]f32{ 5, 6, 7, 8 };
    var c = [_]f32{ 0, 0, 0, 0 };

    try matmul(&ctx, &a, &b, &c, 2, 2, 2);

    try std.testing.expectEqual(@as(f32, 19), c[0]);
    try std.testing.expectEqual(@as(f32, 22), c[1]);
    try std.testing.expectEqual(@as(f32, 43), c[2]);
    try std.testing.expectEqual(@as(f32, 50), c[3]);
}
