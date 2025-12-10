//! CPython source: Lib/platform.py
//!
//! Provides portable interface to platform-identifying data.
//!
//! Mirrors: CPython Lib/platform.py

const std = @import("std");
const builtin = @import("builtin");

// ============================================================================
// Platform identification
// ============================================================================

/// Returns the system/OS name (e.g., 'Linux', 'Darwin', 'Windows')
pub fn system() []const u8 {
    return switch (builtin.os.tag) {
        .linux => "Linux",
        .macos => "Darwin",
        .windows => "Windows",
        .freebsd => "FreeBSD",
        .netbsd => "NetBSD",
        .openbsd => "OpenBSD",
        .dragonfly => "DragonFly",
        .ios => "iOS",
        .tvos => "tvOS",
        .watchos => "watchOS",
        .emscripten => "Emscripten",
        .wasi => "WASI",
        .freestanding => "Freestanding",
        else => "Unknown",
    };
}

/// Returns the machine type (e.g., 'x86_64', 'arm64')
pub fn machine() []const u8 {
    return switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .x86 => "i686",
        .aarch64 => "arm64",
        .arm => "arm",
        .riscv64 => "riscv64",
        .riscv32 => "riscv32",
        .powerpc64 => "ppc64",
        .powerpc64le => "ppc64le",
        .powerpc => "ppc",
        .mips64 => "mips64",
        .mips => "mips",
        .sparc64 => "sparc64",
        .sparc => "sparc",
        .wasm32 => "wasm32",
        .wasm64 => "wasm64",
        else => "unknown",
    };
}

/// Returns the processor type (alias for machine on most systems)
pub fn processor() []const u8 {
    return machine();
}

/// Returns the network name of the computer (hostname)
pub fn node(allocator: std.mem.Allocator) ![]u8 {
    if (comptime builtin.os.tag == .windows) {
        // Windows: use GetComputerNameExA
        const windows = std.os.windows;
        var buf: [256]u8 = undefined;
        var size: windows.DWORD = buf.len;
        if (windows.kernel32.GetComputerNameExA(
            @intFromEnum(windows.ComputerNameFormat.ComputerNameDnsHostname),
            &buf,
            &size,
        ) != 0) {
            return try allocator.dupe(u8, buf[0..size]);
        }
        return try allocator.dupe(u8, "localhost");
    } else {
        // POSIX: use uname
        var uts: std.posix.utsname = undefined;
        if (std.posix.uname(&uts) == 0) {
            // Find null terminator
            const nodename = &uts.nodename;
            var len: usize = 0;
            while (len < nodename.len and nodename[len] != 0) : (len += 1) {}
            return try allocator.dupe(u8, nodename[0..len]);
        }
        return try allocator.dupe(u8, "localhost");
    }
}

/// Static buffers for cached uname results
var release_buf: [256]u8 = undefined;
var version_buf: [256]u8 = undefined;
var cached_release: ?[]const u8 = null;
var cached_version: ?[]const u8 = null;

/// Returns the system's release (e.g., kernel version like "5.15.0" or "23.1.0")
pub fn release() []const u8 {
    if (cached_release) |rel| return rel;

    if (comptime builtin.os.tag == .windows) {
        cached_release = "Windows";
        return cached_release.?;
    }

    // POSIX: use uname
    var uts: std.posix.utsname = undefined;
    if (std.posix.uname(&uts) == 0) {
        const rel = &uts.release;
        var len: usize = 0;
        while (len < rel.len and rel[len] != 0) : (len += 1) {}
        // Copy to static buffer to avoid dangling pointer
        const copy_len = @min(len, release_buf.len - 1);
        @memcpy(release_buf[0..copy_len], rel[0..copy_len]);
        cached_release = release_buf[0..copy_len];
        return cached_release.?;
    }
    cached_release = "";
    return cached_release.?;
}

/// Returns the system's release version (e.g., build info)
pub fn version() []const u8 {
    if (cached_version) |ver| return ver;

    if (comptime builtin.os.tag == .windows) {
        cached_version = "";
        return cached_version.?;
    }

    // POSIX: use uname
    var uts: std.posix.utsname = undefined;
    if (std.posix.uname(&uts) == 0) {
        const ver = &uts.version;
        var len: usize = 0;
        while (len < ver.len and ver[len] != 0) : (len += 1) {}
        // Copy to static buffer to avoid dangling pointer
        const copy_len = @min(len, version_buf.len - 1);
        @memcpy(version_buf[0..copy_len], ver[0..copy_len]);
        cached_version = version_buf[0..copy_len];
        return cached_version.?;
    }
    cached_version = "";
    return cached_version.?;
}

// ============================================================================
// Platform tuple
// ============================================================================

/// Platform info tuple
pub const PlatformInfo = struct {
    system: []const u8,
    node: []const u8,
    release: []const u8,
    version: []const u8,
    machine: []const u8,
    processor: []const u8,
};

/// Returns a tuple of platform info
pub fn uname(allocator: std.mem.Allocator) !PlatformInfo {
    return .{
        .system = system(),
        .node = try node(allocator),
        .release = release(),
        .version = version(),
        .machine = machine(),
        .processor = processor(),
    };
}

// ============================================================================
// Platform string formatting
// ============================================================================

/// Returns a single string identifying the platform with all info
pub fn platform_str(allocator: std.mem.Allocator, aliased: bool, terse: bool) ![]u8 {
    _ = aliased;

    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit();

    try result.appendSlice(system());

    if (!terse) {
        try result.append('-');
        try result.appendSlice(release());
        try result.append('-');
        try result.appendSlice(machine());
    }

    return result.toOwnedSlice();
}

// ============================================================================
// Python version info
// ============================================================================

/// Python version as a string
pub fn python_version() []const u8 {
    return "3.12.0"; // Metal0 targets Python 3.12 compatibility
}

/// Python version as a tuple (major, minor, micro)
pub fn python_version_tuple() struct { major: u32, minor: u32, micro: u32 } {
    return .{ .major = 3, .minor = 12, .micro = 0 };
}

/// Python implementation (CPython, PyPy, Metal0, etc.)
pub fn python_implementation() []const u8 {
    return "Metal0";
}

/// Python compiler
pub fn python_compiler() []const u8 {
    return "Zig " ++ @import("builtin").zig_version_string;
}

/// Python build info
pub fn python_build() struct { build_number: []const u8, build_date: []const u8 } {
    return .{ .build_number = "main", .build_date = "Dec 2024" };
}

/// Python branch
pub fn python_branch() []const u8 {
    return "main";
}

/// Python revision
pub fn python_revision() []const u8 {
    return "";
}

// ============================================================================
// Architecture info
// ============================================================================

/// Returns (bits, linkage) info about the executable
pub fn architecture() struct { bits: []const u8, linkage: []const u8 } {
    const bits = switch (builtin.cpu.arch) {
        .x86_64, .aarch64, .riscv64, .powerpc64, .powerpc64le, .mips64, .sparc64, .wasm64 => "64bit",
        .x86, .arm, .riscv32, .powerpc, .mips, .sparc, .wasm32 => "32bit",
        else => "unknown",
    };

    const linkage = if (builtin.link_libc) "ELF" else "static";

    return .{ .bits = bits, .linkage = linkage };
}

// ============================================================================
// OS-specific info
// ============================================================================

/// Check if running on Windows
pub fn isWindows() bool {
    return builtin.os.tag == .windows;
}

/// Check if running on Linux
pub fn isLinux() bool {
    return builtin.os.tag == .linux;
}

/// Check if running on macOS
pub fn isMacOS() bool {
    return builtin.os.tag == .macos;
}

/// Check if running on a Unix-like system
pub fn isUnix() bool {
    return switch (builtin.os.tag) {
        .linux, .macos, .freebsd, .netbsd, .openbsd, .dragonfly, .ios, .tvos, .watchos => true,
        else => false,
    };
}

/// Returns macOS version info (if on macOS)
pub fn mac_ver() struct { release: []const u8, versioninfo: []const u8, machine: []const u8 } {
    if (builtin.os.tag != .macos) {
        return .{ .release = "", .versioninfo = "", .machine = "" };
    }
    return .{ .release = "14.0", .versioninfo = "", .machine = machine() };
}

/// Returns Windows version info (if on Windows)
pub fn win32_ver() struct { release: []const u8, version: []const u8, csd: []const u8, ptype: []const u8 } {
    if (builtin.os.tag != .windows) {
        return .{ .release = "", .version = "", .csd = "", .ptype = "" };
    }
    return .{ .release = "10", .version = "10.0.0", .csd = "", .ptype = "Multiprocessor Free" };
}

/// Returns Linux distribution info (if on Linux)
pub fn linux_distribution() struct { distname: []const u8, version: []const u8, id: []const u8 } {
    if (builtin.os.tag != .linux) {
        return .{ .distname = "", .version = "", .id = "" };
    }
    return .{ .distname = "Linux", .version = "", .id = "" };
}

// ============================================================================
// Libc info
// ============================================================================

/// Returns the libc library and version
pub fn libc_ver() struct { lib: []const u8, version: []const u8 } {
    if (!builtin.link_libc) {
        return .{ .lib = "", .version = "" };
    }

    // For now, return generic info
    return switch (builtin.os.tag) {
        .linux => .{ .lib = "glibc", .version = "2.17" },
        .macos => .{ .lib = "libSystem", .version = "" },
        .windows => .{ .lib = "msvcrt", .version = "" },
        else => .{ .lib = "", .version = "" },
    };
}

// ============================================================================
// Tests
// ============================================================================

test "system" {
    const sys = system();
    try std.testing.expect(sys.len > 0);
}

test "machine" {
    const m = machine();
    try std.testing.expect(m.len > 0);
}

test "architecture" {
    const arch = architecture();
    try std.testing.expect(std.mem.eql(u8, arch.bits, "64bit") or std.mem.eql(u8, arch.bits, "32bit") or std.mem.eql(u8, arch.bits, "unknown"));
}

test "python_version" {
    const ver = python_version();
    try std.testing.expect(std.mem.startsWith(u8, ver, "3."));
}

test "python_implementation" {
    const impl = python_implementation();
    try std.testing.expectEqualStrings("Metal0", impl);
}

test "python_version_tuple" {
    const tuple = python_version_tuple();
    try std.testing.expectEqual(@as(u32, 3), tuple.major);
    try std.testing.expectEqual(@as(u32, 12), tuple.minor);
}

test "isUnix" {
    const unix = isUnix();
    // Just verify it returns a bool
    _ = unix;
}

test "platform_str" {
    const allocator = std.testing.allocator;

    const p = try platform_str(allocator, false, false);
    defer allocator.free(p);

    try std.testing.expect(p.len > 0);

    const p_terse = try platform_str(allocator, false, true);
    defer allocator.free(p_terse);

    try std.testing.expect(p_terse.len <= p.len);
}

test "uname" {
    const allocator = std.testing.allocator;

    const info = try uname(allocator);
    defer allocator.free(info.node);

    try std.testing.expect(info.system.len > 0);
    try std.testing.expect(info.machine.len > 0);
}
