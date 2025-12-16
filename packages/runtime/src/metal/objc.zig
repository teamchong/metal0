//! Objective-C / Metal Framework Bindings
//!
//! Low-level bindings to Apple's Metal framework via Objective-C runtime.
//! Only compiled on macOS.

const std = @import("std");
const builtin = @import("builtin");

// Type aliases for Metal objects (opaque pointers)
pub const MTLDevice = *anyopaque;
pub const MTLCommandQueue = *anyopaque;
pub const MTLCommandBuffer = *anyopaque;
pub const MTLComputeCommandEncoder = *anyopaque;
pub const MTLBuffer = *anyopaque;
pub const MTLLibrary = *anyopaque;
pub const MTLFunction = *anyopaque;
pub const MTLComputePipelineState = *anyopaque;

// Only link these on macOS
const c = if (builtin.os.tag == .macos) struct {
    // Metal framework functions
    extern "Metal" fn MTLCreateSystemDefaultDevice() ?MTLDevice;

    // Objective-C runtime for method dispatch
    extern "objc" fn objc_msgSend() void;
    extern "objc" fn sel_registerName(name: [*:0]const u8) *anyopaque;
    extern "objc" fn objc_getClass(name: [*:0]const u8) ?*anyopaque;
} else struct {};

/// Create the default Metal device
pub fn MTLCreateSystemDefaultDevice() ?MTLDevice {
    if (comptime builtin.os.tag != .macos) return null;
    return c.MTLCreateSystemDefaultDevice();
}

/// Send Objective-C message (generic)
fn msgSend(comptime ReturnType: type) *const fn (target: *anyopaque, sel: *anyopaque) callconv(.C) ReturnType {
    if (comptime builtin.os.tag != .macos) {
        return undefined;
    }
    return @ptrCast(&c.objc_msgSend);
}

fn msgSendWithArg(comptime ReturnType: type, comptime ArgType: type) *const fn (target: *anyopaque, sel: *anyopaque, arg: ArgType) callconv(.C) ReturnType {
    if (comptime builtin.os.tag != .macos) {
        return undefined;
    }
    return @ptrCast(&c.objc_msgSend);
}

/// Get selector by name
fn sel(name: [*:0]const u8) *anyopaque {
    if (comptime builtin.os.tag != .macos) {
        return undefined;
    }
    return c.sel_registerName(name);
}

/// Release an Objective-C object
pub fn release(obj: *anyopaque) void {
    if (comptime builtin.os.tag != .macos) return;
    const releaseMsg = msgSend(void);
    releaseMsg(obj, sel("release"));
}

/// Retain an Objective-C object
pub fn retain(obj: *anyopaque) *anyopaque {
    if (comptime builtin.os.tag != .macos) return obj;
    const retainMsg = msgSend(*anyopaque);
    return retainMsg(obj, sel("retain"));
}

// ============================================================================
// MTLDevice methods
// ============================================================================

/// Create a new command queue from device
pub fn deviceNewCommandQueue(device: MTLDevice) ?MTLCommandQueue {
    if (comptime builtin.os.tag != .macos) return null;
    const newCommandQueue = msgSend(?MTLCommandQueue);
    return newCommandQueue(device, sel("newCommandQueue"));
}

/// Get device name
pub fn deviceGetName(device: MTLDevice) []const u8 {
    if (comptime builtin.os.tag != .macos) return "Unknown";
    const getName = msgSend(?[*:0]const u8);
    const name_ptr = getName(device, sel("name")) orelse return "Unknown";
    return std.mem.span(name_ptr);
}

/// Create a new buffer on device
pub fn deviceNewBuffer(device: MTLDevice, length: usize, options: u32) ?MTLBuffer {
    if (comptime builtin.os.tag != .macos) return null;
    const NewBufferFn = *const fn (*anyopaque, *anyopaque, usize, u32) callconv(.C) ?MTLBuffer;
    const newBuffer: NewBufferFn = @ptrCast(&c.objc_msgSend);
    return newBuffer(device, sel("newBufferWithLength:options:"), length, options);
}

/// Create buffer with data
pub fn deviceNewBufferWithBytes(device: MTLDevice, bytes: [*]const u8, length: usize, options: u32) ?MTLBuffer {
    if (comptime builtin.os.tag != .macos) return null;
    const NewBufferFn = *const fn (*anyopaque, *anyopaque, [*]const u8, usize, u32) callconv(.C) ?MTLBuffer;
    const newBuffer: NewBufferFn = @ptrCast(&c.objc_msgSend);
    return newBuffer(device, sel("newBufferWithBytes:length:options:"), bytes, length, options);
}

/// Create library from source
pub fn deviceNewLibraryWithSource(device: MTLDevice, source: [*:0]const u8, options: ?*anyopaque, err: *?*anyopaque) ?MTLLibrary {
    if (comptime builtin.os.tag != .macos) return null;
    const NewLibraryFn = *const fn (*anyopaque, *anyopaque, [*:0]const u8, ?*anyopaque, *?*anyopaque) callconv(.C) ?MTLLibrary;
    const newLibrary: NewLibraryFn = @ptrCast(&c.objc_msgSend);
    return newLibrary(device, sel("newLibraryWithSource:options:error:"), source, options, err);
}

// ============================================================================
// MTLCommandQueue methods
// ============================================================================

/// Create new command buffer
pub fn commandQueueNewCommandBuffer(queue: MTLCommandQueue) ?MTLCommandBuffer {
    if (comptime builtin.os.tag != .macos) return null;
    const newCommandBuffer = msgSend(?MTLCommandBuffer);
    return newCommandBuffer(queue, sel("commandBuffer"));
}

// ============================================================================
// MTLCommandBuffer methods
// ============================================================================

/// Create compute command encoder
pub fn commandBufferNewComputeEncoder(buffer: MTLCommandBuffer) ?MTLComputeCommandEncoder {
    if (comptime builtin.os.tag != .macos) return null;
    const newEncoder = msgSend(?MTLComputeCommandEncoder);
    return newEncoder(buffer, sel("computeCommandEncoder"));
}

/// Commit command buffer
pub fn commandBufferCommit(buffer: MTLCommandBuffer) void {
    if (comptime builtin.os.tag != .macos) return;
    const commit = msgSend(void);
    commit(buffer, sel("commit"));
}

/// Wait until completed
pub fn commandBufferWaitUntilCompleted(buffer: MTLCommandBuffer) void {
    if (comptime builtin.os.tag != .macos) return;
    const wait = msgSend(void);
    wait(buffer, sel("waitUntilCompleted"));
}

// ============================================================================
// MTLBuffer methods
// ============================================================================

/// Get buffer contents pointer
pub fn bufferGetContents(buffer: MTLBuffer) ?*anyopaque {
    if (comptime builtin.os.tag != .macos) return null;
    const contents = msgSend(?*anyopaque);
    return contents(buffer, sel("contents"));
}

/// Get buffer length
pub fn bufferGetLength(buffer: MTLBuffer) usize {
    if (comptime builtin.os.tag != .macos) return 0;
    const length = msgSend(usize);
    return length(buffer, sel("length"));
}

// ============================================================================
// MTLLibrary methods
// ============================================================================

/// Get function from library
pub fn libraryNewFunction(library: MTLLibrary, name: [*:0]const u8) ?MTLFunction {
    if (comptime builtin.os.tag != .macos) return null;
    const NewFunctionFn = *const fn (*anyopaque, *anyopaque, [*:0]const u8) callconv(.C) ?MTLFunction;
    const newFunction: NewFunctionFn = @ptrCast(&c.objc_msgSend);
    return newFunction(library, sel("newFunctionWithName:"), name);
}

// ============================================================================
// MTLComputeCommandEncoder methods
// ============================================================================

/// Set compute pipeline state
pub fn encoderSetComputePipelineState(encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState) void {
    if (comptime builtin.os.tag != .macos) return;
    const SetPipelineFn = *const fn (*anyopaque, *anyopaque, MTLComputePipelineState) callconv(.C) void;
    const setPipeline: SetPipelineFn = @ptrCast(&c.objc_msgSend);
    setPipeline(encoder, sel("setComputePipelineState:"), pipeline);
}

/// Set buffer at index
pub fn encoderSetBuffer(encoder: MTLComputeCommandEncoder, buffer: MTLBuffer, offset: usize, index: usize) void {
    if (comptime builtin.os.tag != .macos) return;
    const SetBufferFn = *const fn (*anyopaque, *anyopaque, MTLBuffer, usize, usize) callconv(.C) void;
    const setBuffer: SetBufferFn = @ptrCast(&c.objc_msgSend);
    setBuffer(encoder, sel("setBuffer:offset:atIndex:"), buffer, offset, index);
}

/// Set bytes at index
pub fn encoderSetBytes(encoder: MTLComputeCommandEncoder, bytes: *const anyopaque, length: usize, index: usize) void {
    if (comptime builtin.os.tag != .macos) return;
    const SetBytesFn = *const fn (*anyopaque, *anyopaque, *const anyopaque, usize, usize) callconv(.C) void;
    const setBytes: SetBytesFn = @ptrCast(&c.objc_msgSend);
    setBytes(encoder, sel("setBytes:length:atIndex:"), bytes, length, index);
}

/// Dispatch threadgroups
pub fn encoderDispatchThreadgroups(encoder: MTLComputeCommandEncoder, grid: MTLSize, threadgroup: MTLSize) void {
    if (comptime builtin.os.tag != .macos) return;
    const DispatchFn = *const fn (*anyopaque, *anyopaque, MTLSize, MTLSize) callconv(.C) void;
    const dispatch: DispatchFn = @ptrCast(&c.objc_msgSend);
    dispatch(encoder, sel("dispatchThreadgroups:threadsPerThreadgroup:"), grid, threadgroup);
}

/// Dispatch threads (non-uniform)
pub fn encoderDispatchThreads(encoder: MTLComputeCommandEncoder, threads: MTLSize, threadgroup: MTLSize) void {
    if (comptime builtin.os.tag != .macos) return;
    const DispatchFn = *const fn (*anyopaque, *anyopaque, MTLSize, MTLSize) callconv(.C) void;
    const dispatch: DispatchFn = @ptrCast(&c.objc_msgSend);
    dispatch(encoder, sel("dispatchThreads:threadsPerThreadgroup:"), threads, threadgroup);
}

/// End encoding
pub fn encoderEndEncoding(encoder: MTLComputeCommandEncoder) void {
    if (comptime builtin.os.tag != .macos) return;
    const endEncoding = msgSend(void);
    endEncoding(encoder, sel("endEncoding"));
}

// ============================================================================
// MTLDevice pipeline creation
// ============================================================================

/// Create compute pipeline state from function
pub fn deviceNewComputePipelineState(device: MTLDevice, function: MTLFunction, err: *?*anyopaque) ?MTLComputePipelineState {
    if (comptime builtin.os.tag != .macos) return null;
    const NewPipelineFn = *const fn (*anyopaque, *anyopaque, MTLFunction, *?*anyopaque) callconv(.C) ?MTLComputePipelineState;
    const newPipeline: NewPipelineFn = @ptrCast(&c.objc_msgSend);
    return newPipeline(device, sel("newComputePipelineStateWithFunction:error:"), function, err);
}

// ============================================================================
// Types
// ============================================================================

/// Metal size structure (for grid/threadgroup dimensions)
pub const MTLSize = extern struct {
    width: usize,
    height: usize,
    depth: usize,
};

// ============================================================================
// Constants
// ============================================================================

/// MTLResourceOptions
pub const MTLResourceStorageModeShared: u32 = 0;
pub const MTLResourceStorageModeManaged: u32 = 1 << 4;
pub const MTLResourceStorageModePrivate: u32 = 2 << 4;
