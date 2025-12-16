//! Metal Shader Compilation and Caching
//!
//! Compiles Metal shading language (.metal) to binary (.metallib) format.
//! Uses SHA256-based caching for fast startup.
//!
//! Pattern from zell: Two-step compilation with persistent cache.

const std = @import("std");
const builtin = @import("builtin");
const objc = @import("objc.zig");

/// Shader cache directory
const CACHE_DIR = ".metal0/metal/shaders";

/// Shader manager handles compilation and caching
pub const ShaderManager = struct {
    device: objc.MTLDevice,
    library: ?objc.MTLLibrary,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, device: objc.MTLDevice) !@This() {
        return .{
            .device = device,
            .library = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        if (self.library) |lib| {
            objc.release(lib);
        }
    }

    /// Compile shaders (with caching)
    pub fn compile(self: *@This()) !void {
        // Check cache first
        const cache_path = try getCachePath(self.allocator);
        defer self.allocator.free(cache_path);

        // Try to load from cache
        if (self.loadFromCache(cache_path)) |lib| {
            self.library = lib;
            return;
        }

        // Compile from source
        const source = @embedFile("kernels/metal_kernels.metal");
        self.library = try self.compileSource(source);

        // Save to cache for next time
        self.saveToCache(cache_path) catch |err| {
            std.debug.print("Warning: Could not save shader cache: {}\n", .{err});
        };
    }

    /// Compile Metal source code
    fn compileSource(self: *@This(), source: [*:0]const u8) !objc.MTLLibrary {
        var err: ?*anyopaque = null;
        const library = objc.deviceNewLibraryWithSource(
            self.device,
            source,
            null,
            &err,
        ) orelse {
            // TODO: Extract error message from NSError
            return error.ShaderCompilationFailed;
        };
        return library;
    }

    /// Load compiled library from cache
    fn loadFromCache(_: *@This(), _: []const u8) ?objc.MTLLibrary {
        // TODO: Implement metallib loading
        // For now, always recompile
        return null;
    }

    /// Save compiled library to cache
    fn saveToCache(_: *@This(), _: []const u8) !void {
        // TODO: Implement metallib saving
    }

    /// Get function from compiled library
    pub fn getFunction(self: *@This(), name: [*:0]const u8) !objc.MTLFunction {
        const lib = self.library orelse return error.LibraryNotCompiled;
        return objc.libraryNewFunction(lib, name) orelse error.FunctionNotFound;
    }
};

/// Check if Metal compiler is available
pub fn checkMetalAvailable() bool {
    if (comptime builtin.os.tag != .macos) return false;

    // Check if xcrun metal is available
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "xcrun", "--find", "metal" },
    }) catch return false;

    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);

    return result.term.Exited == 0;
}

/// Get cache path for compiled shaders
fn getCachePath(allocator: std.mem.Allocator) ![]u8 {
    // Get home directory
    const home = std.posix.getenv("HOME") orelse "/tmp";

    // Create cache directory if needed
    const cache_dir = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ home, CACHE_DIR });
    defer allocator.free(cache_dir);

    std.fs.cwd().makePath(cache_dir) catch {};

    // Return cache file path
    return std.fmt.allocPrint(allocator, "{s}/kernels.metallib", .{cache_dir});
}

/// Get cache key based on shader source hash
pub fn getCacheKey(source: []const u8) [64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(source);
    var hash_bytes: [32]u8 = undefined;
    hasher.final(&hash_bytes);
    return std.fmt.bytesToHex(hash_bytes, .lower);
}

// ============================================================================
// Tests
// ============================================================================

test "cache key generation" {
    const source = "kernel void test() {}";
    const key = getCacheKey(source);
    try std.testing.expect(key.len == 64);
}

test "metal availability check" {
    const available = checkMetalAvailable();
    if (comptime builtin.os.tag != .macos) {
        try std.testing.expect(!available);
    }
    // On macOS with Xcode, metal should be available
    // But don't fail test if not (e.g., CI without Xcode)
}
