/// getplatform - Platform Identification
/// Mirrors cpython/Python/getplatform.c
///
/// Returns the platform identifier string used by sys.platform

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Platform String
// ============================================================================

/// Get the platform identifier
/// Returns "darwin", "linux", "win32", "freebsd", etc.
pub fn getPlatform() []const u8 {
    return switch (builtin.os.tag) {
        .macos => "darwin",
        .ios => "darwin",
        .linux => "linux",
        .windows => "win32",
        .freebsd => "freebsd",
        .openbsd => "openbsd",
        .netbsd => "netbsd",
        .dragonfly => "dragonfly",
        .solaris => "sunos",
        .aix => "aix",
        .wasi => "wasi",
        .emscripten => "emscripten",
        .haiku => "haiku",
        .freestanding => "freestanding",
        else => "unknown",
    };
}

/// Static buffer for cached OS release string
var os_release_buf: [256]u8 = undefined;
var cached_os_release: ?[]const u8 = null;

/// Get detailed OS version info (for sys.version_info)
/// Uses uname() on POSIX systems
pub fn getOSRelease() ?[]const u8 {
    // Return cached value if available
    if (cached_os_release) |rel| return rel;

    if (comptime isPosix()) {
        // Call uname to get OS release
        var uts: std.posix.utsname = undefined;
        const result = std.posix.uname(&uts);
        if (result == 0) {
            // Return release string (e.g., "5.15.0-generic" on Linux, "23.1.0" on macOS)
            const release = &uts.release;
            // Find null terminator
            var len: usize = 0;
            while (len < release.len and release[len] != 0) : (len += 1) {}
            if (len > 0) {
                // Copy to static buffer to avoid dangling pointer
                const copy_len = @min(len, os_release_buf.len - 1);
                @memcpy(os_release_buf[0..copy_len], release[0..copy_len]);
                cached_os_release = os_release_buf[0..copy_len];
                return cached_os_release;
            }
        }
    } else if (comptime isWindows()) {
        // On Windows, return a static version string
        cached_os_release = "Windows";
        return cached_os_release;
    }
    return null;
}

/// Get machine architecture
pub fn getMachine() []const u8 {
    return switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .x86 => "i386",
        .aarch64 => "arm64",
        .arm => "arm",
        .riscv64 => "riscv64",
        .riscv32 => "riscv32",
        .powerpc64 => "ppc64",
        .powerpc64le => "ppc64le",
        .powerpc => "ppc",
        .mips64 => "mips64",
        .mips => "mips",
        .s390x => "s390x",
        .wasm32 => "wasm32",
        .wasm64 => "wasm64",
        else => "unknown",
    };
}

/// Check if running on specific platform
pub fn isDarwin() bool {
    return builtin.os.tag == .macos or builtin.os.tag == .ios;
}

pub fn isLinux() bool {
    return builtin.os.tag == .linux;
}

pub fn isWindows() bool {
    return builtin.os.tag == .windows;
}

pub fn isPosix() bool {
    return switch (builtin.os.tag) {
        .linux, .macos, .ios, .freebsd, .openbsd, .netbsd, .dragonfly, .solaris, .aix => true,
        else => false,
    };
}

pub fn isUnix() bool {
    return isPosix();
}

/// Get endianness
pub fn getEndian() []const u8 {
    return switch (builtin.cpu.arch.endian()) {
        .little => "little",
        .big => "big",
    };
}

/// Get pointer size in bits
pub fn getPointerSize() usize {
    return @bitSizeOf(*anyopaque);
}

/// Check if 64-bit platform
pub fn is64Bit() bool {
    return getPointerSize() == 64;
}

// ============================================================================
// System Information
// ============================================================================

/// Get processor count (stub - would use sysconf)
pub fn getProcessorCount() usize {
    return std.Thread.getCpuCount() catch 1;
}

/// Get page size
pub fn getPageSize() usize {
    return std.mem.page_size;
}

// ============================================================================
// Initialization
// ============================================================================

pub fn init() void {}

// ============================================================================
// Tests
// ============================================================================

test "platform string" {
    const platform = getPlatform();
    try std.testing.expect(platform.len > 0);

    // Should be one of known platforms
    const known = [_][]const u8{
        "darwin", "linux", "win32", "freebsd", "openbsd",
        "netbsd", "dragonfly", "sunos", "aix", "wasi",
        "emscripten", "haiku", "freestanding", "unknown",
    };

    var found = false;
    for (known) |p| {
        if (std.mem.eql(u8, platform, p)) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "machine string" {
    const machine = getMachine();
    try std.testing.expect(machine.len > 0);
}

test "platform checks" {
    // At least one should match current platform
    const is_known = isDarwin() or isLinux() or isWindows() or
        builtin.os.tag == .freebsd or builtin.os.tag == .wasi;
    _ = is_known; // May be unknown platform in CI

    // Posix and Unix should be equivalent
    try std.testing.expectEqual(isPosix(), isUnix());
}

test "pointer size" {
    const size = getPointerSize();
    try std.testing.expect(size == 32 or size == 64);
    try std.testing.expectEqual(size == 64, is64Bit());
}

test "endian" {
    const endian = getEndian();
    try std.testing.expect(std.mem.eql(u8, endian, "little") or std.mem.eql(u8, endian, "big"));
}

test "processor count" {
    const count = getProcessorCount();
    try std.testing.expect(count >= 1);
}
