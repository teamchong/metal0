//! Metal GPU compute backend for vector search.
//!
//! Uses Objective-C interop to call Metal framework APIs.
//! Only available on macOS - compiles to no-ops on other platforms.

const std = @import("std");
const builtin = @import("builtin");

const is_macos = builtin.os.tag == .macos;

// Objective-C / Metal bindings (macOS only)
const objc = if (is_macos) @cImport({
    @cInclude("objc/runtime.h");
    @cInclude("objc/message.h");
}) else struct {};

const metal = if (is_macos) @cImport({
    @cInclude("Metal/Metal.h");
}) else struct {};

/// Metal GPU context for vector operations
pub const MetalGPU = struct {
    device: ?*anyopaque,
    command_queue: ?*anyopaque,
    library: ?*anyopaque,
    cosine_fn: ?*anyopaque,
    dot_fn: ?*anyopaque,
    l2_fn: ?*anyopaque,

    const Self = @This();

    /// Initialize Metal GPU context
    pub fn init() !Self {
        if (comptime !is_macos) {
            return Self{
                .device = null,
                .command_queue = null,
                .library = null,
                .cosine_fn = null,
                .dot_fn = null,
                .l2_fn = null,
            };
        }

        // Get default Metal device
        const device = metal.MTLCreateSystemDefaultDevice();
        if (device == null) {
            return error.NoMetalDevice;
        }

        // Create command queue
        const queue_sel = objc.sel_registerName("newCommandQueue");
        const command_queue = objc.objc_msgSend(device, queue_sel);
        if (command_queue == null) {
            return error.CommandQueueFailed;
        }

        return Self{
            .device = device,
            .command_queue = command_queue,
            .library = null,
            .cosine_fn = null,
            .dot_fn = null,
            .l2_fn = null,
        };
    }

    /// Load shader library from source
    pub fn loadShaderSource(self: *Self, source: []const u8) !void {
        if (comptime !is_macos) return;
        if (self.device == null) return error.NoDevice;

        // Create NSString from source
        const ns_string_class = objc.objc_getClass("NSString");
        const alloc_sel = objc.sel_registerName("alloc");
        const init_sel = objc.sel_registerName("initWithBytes:length:encoding:");

        const ns_str = objc.objc_msgSend(ns_string_class, alloc_sel);
        const source_str = @call(.auto, @as(*const fn (*anyopaque, *anyopaque, [*]const u8, usize, usize) *anyopaque, @ptrCast(&objc.objc_msgSend)), .{ ns_str, init_sel, source.ptr, source.len, 4 }); // NSUTF8StringEncoding = 4

        _ = source_str;

        // For now, we'll compile shaders at build time using xcrun
        // Runtime compilation requires more complex objc interop
    }

    /// Check if GPU is available
    pub fn isAvailable(self: Self) bool {
        return self.device != null;
    }

    /// Deinitialize
    pub fn deinit(self: *Self) void {
        // Release Objective-C objects
        if (comptime is_macos) {
            const release_sel = objc.sel_registerName("release");
            if (self.command_queue) |q| {
                _ = objc.objc_msgSend(q, release_sel);
            }
            // Device is autoreleased
        }
        self.* = undefined;
    }
};

/// Compile Metal shaders using xcrun (build-time or runtime)
pub fn compileShaders(allocator: std.mem.Allocator, output_path: []const u8) !void {
    if (comptime !is_macos) return;

    const shader_source = "src/metal/vector_search.metal";

    // Create temp directory
    const tmp_dir = "/tmp/lanceql-metal";
    std.fs.cwd().makePath(tmp_dir) catch {};

    const air_path = try std.fmt.allocPrint(allocator, "{s}/shader.air", .{tmp_dir});
    defer allocator.free(air_path);

    // Step 1: Compile .metal to .air
    std.debug.print("Compiling Metal shaders...\n", .{});
    const compile_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "xcrun", "-sdk", "macosx", "metal",
            "-O3", "-c", shader_source, "-o", air_path,
        },
    });
    defer allocator.free(compile_result.stdout);
    defer allocator.free(compile_result.stderr);

    if (compile_result.term.Exited != 0) {
        std.debug.print("Metal compile error: {s}\n", .{compile_result.stderr});
        return error.MetalCompileFailed;
    }

    // Step 2: Link .air to .metallib
    const link_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "xcrun", "-sdk", "macosx", "metallib",
            air_path, "-o", output_path,
        },
    });
    defer allocator.free(link_result.stdout);
    defer allocator.free(link_result.stderr);

    if (link_result.term.Exited != 0) {
        std.debug.print("Metal link error: {s}\n", .{link_result.stderr});
        return error.MetalLinkFailed;
    }

    std.debug.print("  ✅ Compiled to {s}\n", .{output_path});
}

/// Check if Metal toolchain is available
pub fn isMetalToolchainAvailable() bool {
    if (comptime !is_macos) return false;

    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "xcrun", "--find", "metal" },
    }) catch return false;

    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);

    return result.term.Exited == 0;
}

// =============================================================================
// Tests
// =============================================================================

test "metal toolchain check" {
    const available = isMetalToolchainAvailable();
    std.debug.print("Metal toolchain available: {}\n", .{available});
}

test "metal gpu init" {
    if (comptime !is_macos) return;

    var gpu = MetalGPU.init() catch |err| {
        std.debug.print("Metal GPU init failed: {}\n", .{err});
        return;
    };
    defer gpu.deinit();

    std.debug.print("Metal GPU available: {}\n", .{gpu.isAvailable()});
}
